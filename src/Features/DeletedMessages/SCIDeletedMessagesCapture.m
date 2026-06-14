#import "SCIDeletedMessagesCapture.h"
#import "SCIDeletedMessagesModels.h"
#import "SCIDeletedMessagesStorage.h"
#import "../StoriesAndMessages/SCIDirectUserResolver.h"
#import "../StoriesAndMessages/SCIDirectThreadInfo.h"
#import "../../Utils.h"
#import "../../SCIDashParser.h"
#import "../../SCIFFmpeg.h"
#import "../../SCITempFiles.h"
#import "../../Networking/SCIInstagramAPI.h"
#import "../../UI/Notification/SCINotificationActions.h"
#import "../../Background/SCIBackgroundActivity.h"
#import <objc/runtime.h>
#import <objc/message.h>

#pragma mark - Shared state

static NSMapTable *sciMessageRefs(void) {
	static NSMapTable *t;
	static dispatch_once_t once;
	dispatch_once(&once, ^{
		t = [NSMapTable mapTableWithKeyOptions:NSPointerFunctionsStrongMemory | NSPointerFunctionsObjectPersonality
								  valueOptions:NSPointerFunctionsWeakMemory   | NSPointerFunctionsObjectPersonality];
	});
	return t;
}

static NSObject *sciLock(void) {
	static NSObject *o;
	static dispatch_once_t once;
	dispatch_once(&once, ^{ o = [NSObject new]; });
	return o;
}

static dispatch_queue_t sciCaptureQueue(void) {
	static dispatch_queue_t q;
	static dispatch_once_t once;
	dispatch_once(&once, ^{
		q = dispatch_queue_create("com.ryukgram.deletedmessages.capture", DISPATCH_QUEUE_SERIAL);
	});
	return q;
}

static dispatch_queue_t sciDownloadQueue(void) {
	static dispatch_queue_t q;
	static dispatch_once_t once;
	dispatch_once(&once, ^{
		q = dispatch_queue_create("com.ryukgram.deletedmessages.download", DISPATCH_QUEUE_CONCURRENT);
	});
	return q;
}

static NSURLSession *sciSession(void) {
	static NSURLSession *s;
	static dispatch_once_t once;
	dispatch_once(&once, ^{
		NSURLSessionConfiguration *cfg = NSURLSessionConfiguration.defaultSessionConfiguration;
		cfg.timeoutIntervalForRequest = 30;
		cfg.timeoutIntervalForResource = 120;
		cfg.HTTPMaximumConnectionsPerHost = 4;
		s = [NSURLSession sessionWithConfiguration:cfg];
	});
	return s;
}

static BOOL sciCaptureEnabled(void) {
	return [SCIUtils getBoolPref:@"deleted_messages_log_enabled"];
}

// Defined later; needed by callers above their definitions.
static NSDictionary *sciCachedThreadInfo(NSString *threadId);
static void sciResolveThreadInfo(NSString *threadId, NSString *owner, BOOL force);
static NSArray<NSDictionary *> *sciVisualPhotoCandidates(id photo, NSString **outDisplay);
static NSArray<NSDictionary *> *sciVisualVideoCandidates(id video, NSString **outAudio, NSString **outDisplay);
static void sciAcquireMediaCandidates(NSString *messageId, NSString *ownerPk, SCIDeletedMessageKind kind,
									  NSArray<NSDictionary *> *cands, NSString *audioURL, NSString *mediaPk);

#pragma mark - Runtime helpers

static BOOL sciSystemObject(id obj) {
	if (!obj) return YES;
	if ([obj isKindOfClass:NSString.class] || [obj isKindOfClass:NSNumber.class] ||
		[obj isKindOfClass:NSDate.class] || [obj isKindOfClass:NSURL.class]) return YES;

	NSString *cn = NSStringFromClass([obj class]);
	return [cn hasPrefix:@"NS"] || [cn hasPrefix:@"_NS"] || [cn hasPrefix:@"OS"] || [cn hasPrefix:@"__"];
}

static id sciIvar(id obj, const char *name) {
	if (!obj || !name) return nil;

	for (Class c = [obj class]; c; c = class_getSuperclass(c)) {
		Ivar iv = class_getInstanceVariable(c, name);
		if (!iv) continue;
		const char *enc = ivar_getTypeEncoding(iv);
		if (!enc || (enc[0] != '@' && enc[0] != '#')) return nil;
		@try { return object_getIvar(obj, iv); }
		@catch (__unused id e) { return nil; }
	}
	return nil;
}

static NSString *sciStrIvar(id obj, const char *name) {
	id v = sciIvar(obj, name);
	return [v isKindOfClass:NSString.class] ? v : nil;
}

static id sciKVC(id obj, NSString *key) {
	if (!obj || !key.length) return nil;
	@try {
		id v = [obj valueForKey:key];
		return (v && v != NSNull.null) ? v : nil;
	} @catch (__unused id e) {
		return nil;
	}
}

static BOOL sciBadDesc(NSString *s) {
	return s.length && [s hasPrefix:@"<"] && [s containsString:@": 0x"] && [s hasSuffix:@">"];
}

static NSString *sciStringValue(id v) {
	if ([v isKindOfClass:NSAttributedString.class]) v = [(NSAttributedString *)v string];
	if ([v isKindOfClass:NSString.class] && [(NSString *)v length] && !sciBadDesc(v)) return v;
	if ([v isKindOfClass:NSNumber.class]) return [(NSNumber *)v stringValue];
	return nil;
}

static NSString *sciURLValue(id v) {
	if ([v isKindOfClass:NSURL.class]) return [(NSURL *)v absoluteString];
	if ([v isKindOfClass:NSString.class] && [(NSString *)v length]) return v;
	return nil;
}

static NSString *sciPickString(id obj, NSArray<NSString *> *keys) {
	for (NSString *k in keys) {
		NSString *s = sciStringValue(sciKVC(obj, k));
		if (s.length) return s;
	}
	return nil;
}

static NSString *sciPickURL(id obj, NSArray<NSString *> *keys) {
	for (NSString *k in keys) {
		NSString *s = sciURLValue(sciKVC(obj, k));
		if (s.length) return s;
	}
	return nil;
}

static double sciDouble(id obj, NSString *selName) {
	if (!obj || !selName.length) return 0;

	SEL sel = NSSelectorFromString(selName);
	if (![obj respondsToSelector:sel]) return 0;

	@try {
		NSMethodSignature *sig = [obj methodSignatureForSelector:sel];
		if (!sig) return 0;

		NSInvocation *inv = [NSInvocation invocationWithMethodSignature:sig];
		inv.target = obj;
		inv.selector = sel;
		[inv invoke];

		const char *rt = sig.methodReturnType;
		if (strcmp(rt, "d") == 0) { double r; [inv getReturnValue:&r]; return r; }
		if (strcmp(rt, "f") == 0) { float r; [inv getReturnValue:&r]; return r; }
		if (strcmp(rt, "q") == 0) { long long r; [inv getReturnValue:&r]; return r; }
		if (strcmp(rt, "Q") == 0) { unsigned long long r; [inv getReturnValue:&r]; return r; }
		if (strcmp(rt, "i") == 0) { int r; [inv getReturnValue:&r]; return r; }
	} @catch (__unused id e) {}

	return 0;
}

#pragma mark - Recursive scan helpers

static BOOL sciURLish(NSString *s) {
	return [s hasPrefix:@"http://"] || [s hasPrefix:@"https://"] ||
		   [s hasPrefix:@"instagram://"] || [s hasPrefix:@"fb://"] ||
		   [s hasPrefix:@"fbthreads://"] || [s hasPrefix:@"intent://"];
}

static BOOL sciAudioish(NSString *s) {
	NSString *x = s.lowercaseString ?: @"";
	return [x containsString:@"audio"] || [x containsString:@"voice"] ||
		   [x containsString:@"music"] || [x containsString:@".m4a"] ||
		   [x containsString:@".mp3"] || [x containsString:@".aac"] ||
		   [x containsString:@".opus"] || [x containsString:@".oga"];
}

static void sciScoreURL(NSString *s, NSString *name, NSString **media, int *ms, NSString **thumb, int *ts) {
	if (!sciURLish(s)) return;

	NSString *n = name.lowercaseString ?: @"";
	BOOL th = [n containsString:@"thumb"] || [n containsString:@"preview"] ||
			  [n containsString:@"poster"] || [n containsString:@"cover"] ||
			  [n containsString:@"image"];

	BOOL audio = [n containsString:@"audio"] || [n containsString:@"voice"] || sciAudioish(s);
	BOOL med = audio || [n containsString:@"playable"] || [n containsString:@"video"] ||
			   [n containsString:@"asset"] || [n containsString:@"download"] ||
			   [n containsString:@"src"] || [n containsString:@"url"];

	int score = audio ? 10 : (med ? 5 : 1);

	if (th && !audio) {
		if (score > *ts) { *ts = score; *thumb = s; }
	} else if (score > *ms) {
		*ms = score;
		*media = s;
	}
}

static void sciScanURLs(id obj, int depth, NSString **media, int *ms, NSString **thumb, int *ts, NSString *name) {
	if (!obj || depth < 0) return;

	if ([obj isKindOfClass:NSString.class]) {
		sciScoreURL(obj, name, media, ms, thumb, ts);
		return;
	}

	if ([obj isKindOfClass:NSURL.class]) {
		sciScoreURL([(NSURL *)obj absoluteString], name, media, ms, thumb, ts);
		return;
	}

	if ([obj isKindOfClass:NSArray.class]) {
		for (id e in (NSArray *)obj) sciScanURLs(e, depth - 1, media, ms, thumb, ts, name);
		return;
	}

	if ([obj isKindOfClass:NSDictionary.class]) {
		for (id k in (NSDictionary *)obj) {
			NSString *kn = [k isKindOfClass:NSString.class] ? k : name;
			sciScanURLs(((NSDictionary *)obj)[k], depth - 1, media, ms, thumb, ts, kn);
		}
		return;
	}

	if (sciSystemObject(obj)) return;

	for (Class c = [obj class]; c && c != NSObject.class; c = class_getSuperclass(c)) {
		unsigned int n = 0;
		Ivar *list = class_copyIvarList(c, &n);

		for (unsigned int i = 0; i < n; i++) {
			const char *type = ivar_getTypeEncoding(list[i]);
			if (!type || type[0] != '@') continue;

			id v = nil;
			@try { v = object_getIvar(obj, list[i]); }
			@catch (__unused id e) {}

			if (!v) continue;
			const char *ivn = ivar_getName(list[i]);
			sciScanURLs(v, depth - 1, media, ms, thumb, ts, ivn ? @(ivn) : name);
		}

		if (list) free(list);
	}
}

static void sciCollectTokens(id obj, int depth, NSMutableSet *seen, NSMutableSet<NSString *> *out) {
	if (!obj || depth < 0) return;

	if ([obj isKindOfClass:NSArray.class]) {
		for (id e in (NSArray *)obj) sciCollectTokens(e, depth - 1, seen, out);
		return;
	}

	if ([obj isKindOfClass:NSDictionary.class]) {
		for (id k in (NSDictionary *)obj) {
			if ([k isKindOfClass:NSString.class]) [out addObject:[(NSString *)k lowercaseString]];
			sciCollectTokens(((NSDictionary *)obj)[k], depth - 1, seen, out);
		}
		return;
	}

	if (sciSystemObject(obj)) return;

	NSValue *box = [NSValue valueWithNonretainedObject:obj];
	if ([seen containsObject:box]) return;
	[seen addObject:box];

	[out addObject:NSStringFromClass([obj class]).lowercaseString];

	for (Class c = [obj class]; c && c != NSObject.class; c = class_getSuperclass(c)) {
		unsigned int n = 0;
		Ivar *list = class_copyIvarList(c, &n);

		for (unsigned int i = 0; i < n; i++) {
			const char *type = ivar_getTypeEncoding(list[i]);
			if (!type || type[0] != '@') continue;

			id v = nil;
			@try { v = object_getIvar(obj, list[i]); }
			@catch (__unused id e) {}

			if (!v) continue;

			const char *ivn = ivar_getName(list[i]);
			if (ivn) [out addObject:[@(ivn) lowercaseString]];
			sciCollectTokens(v, depth - 1, seen, out);
		}

		if (list) free(list);
	}
}

static BOOL sciTokensContain(NSSet<NSString *> *tokens, NSArray<NSString *> *needles) {
	for (NSString *t in tokens) {
		for (NSString *n in needles) {
			if ([t containsString:n]) return YES;
		}
	}
	return NO;
}

// Real media PKs are long digit strings; reject short numbers (counts/indices).
static NSString *sciNumericMediaId(id v) {
	if ([v isKindOfClass:NSNumber.class]) v = [(NSNumber *)v stringValue];
	if (![v isKindOfClass:NSString.class]) return nil;

	NSString *s = v;
	NSString *digits = [s componentsSeparatedByString:@"_"].firstObject;
	if (digits.length < 8) return nil;
	for (NSUInteger i = 0; i < digits.length; i++) {
		unichar c = [digits characterAtIndex:i];
		if (c < '0' || c > '9') return nil;
	}
	return s;
}

static NSString *sciMediaPkFrom(id obj) {
	if (!obj) return nil;
	for (NSString *n in @[@"_mediaId", @"_pk", @"_mediaPk", @"_postId", @"_id", @"_instagramMediaId"]) {
		NSString *s = sciNumericMediaId(sciIvar(obj, n.UTF8String));
		if (s.length) return s;
	}
	return nil;
}

// First long digit-string ivar — pulls a thread id out of an opaque identifier wrapper.
static NSString *sciScanLongDigitString(id obj) {
	if (!obj) return nil;
	for (Class c = [obj class]; c && c != NSObject.class; c = class_getSuperclass(c)) {
		unsigned n = 0;
		Ivar *ivars = class_copyIvarList(c, &n);
		NSString *found = nil;
		for (unsigned i = 0; i < n; i++) {
			const char *t = ivar_getTypeEncoding(ivars[i]);
			if (!t || t[0] != '@') continue;
			id v = nil;
			@try { v = object_getIvar(obj, ivars[i]); } @catch (__unused id e) {}
			NSString *s = sciNumericMediaId(v);
			if (s.length) { found = s; break; }
		}
		free(ivars);
		if (found) return found;
	}
	return nil;
}

#pragma mark - Metadata extraction

static NSString *sciSidFromMessage(id m) {
	id meta = sciIvar(m, "_metadata");
	NSString *sid = sciStrIvar(meta, "_serverId") ?: sciStrIvar(meta, "_messageServerId");

	if (!sid.length) {
		id key = sciIvar(meta, "_key");
		sid = sciStrIvar(key, "_serverId") ?: sciStrIvar(key, "_messageServerId");
	}

	return sid;
}

static NSString *sciSenderPkFromMessage(id m) {
	return sciStrIvar(sciIvar(m, "_metadata"), "_senderPk");
}

static NSDate *sciSentAtFromMessage(id m) {
	id meta = sciIvar(m, "_metadata");
	if (!meta) return nil;

	for (NSString *k in @[@"_serverTimestamp", @"_clientTimestamp", @"_timestamp"]) {
		id v = sciIvar(meta, k.UTF8String);

		if ([v isKindOfClass:NSDate.class]) return v;

		if ([v isKindOfClass:NSNumber.class]) {
			double d = [(NSNumber *)v doubleValue];
			if (d > 1.0e12) d /= 1.0e9;
			else if (d > 1.0e10) d /= 1.0e3;
			if (d > 0) return [NSDate dateWithTimeIntervalSince1970:d];
		}
	}

	return nil;
}

static void sciResolveSender(NSString *pk, NSString **outUser, NSString **outName, NSString **outPic) {
	if (!pk.length) return;

	NSString *u = sciDirectUserResolverUsernameForPK(pk);
	NSString *p = sciDirectUserResolverProfilePicURLStringForPK(pk);
	NSString *fn = nil;

	id user = sciDirectUserResolverUserForPK(pk);
	NSDictionary *fc = nil;

	if (user) {
		id raw = sciIvar(user, "_fieldCache");
		if ([raw isKindOfClass:NSDictionary.class]) fc = raw;

		NSString *(^fcStr)(NSString *) = ^NSString *(NSString *k) {
			id v = fc[k];
			return [v isKindOfClass:NSString.class] && [(NSString *)v length] ? v : nil;
		};

		if (!u.length) u = fcStr(@"username");
		if (!p.length) p = fcStr(@"profile_pic_url");
		fn = fcStr(@"full_name") ?: sciStringValue(sciKVC(user, @"fullName"));
	}

	if (outUser) *outUser = u;
	if (outName) *outName = fn;
	if (outPic) *outPic = p;
}

static NSString *sciReplyIdFromMessage(id message) {
	id meta = sciIvar(message, "_metadata");

	for (NSString *k in @[@"_replyToMessageId", @"_replyMessageId", @"_quotedMessageId", @"_repliedToMessageId", @"_parentMessageId"]) {
		NSString *v = sciStrIvar(meta, k.UTF8String) ?: sciStrIvar(message, k.UTF8String);
		if (v.length) return v;
	}

	for (NSString *k in @[@"replyToMessageId", @"replyMessageId", @"quotedMessageId", @"repliedToMessageId", @"reply_message_id"]) {
		NSString *v = sciStringValue(sciKVC(message, k));
		if (v.length) return v;
	}

	return nil;
}

#pragma mark - Share / XMA / voice

static NSString *sciDeepTitle(id obj) {
	if (!obj) return nil;

	NSMutableArray *stack = [NSMutableArray arrayWithObject:obj];
	NSMutableSet *seen = [NSMutableSet set];
	NSString *best = nil;
	NSArray *keys = @[@"title", @"caption", @"text", @"name", @"description", @"summary", @"label", @"username", @"headline"];

	for (int hops = 0; stack.count && hops < 96; hops++) {
		id cur = stack.lastObject;
		[stack removeLastObject];

		if ([cur isKindOfClass:NSArray.class]) {
			for (id e in (NSArray *)cur) [stack addObject:e];
			continue;
		}

		if (sciSystemObject(cur)) continue;

		NSValue *box = [NSValue valueWithNonretainedObject:cur];
		if ([seen containsObject:box]) continue;
		[seen addObject:box];

		for (Class c = [cur class]; c && c != NSObject.class; c = class_getSuperclass(c)) {
			unsigned int n = 0;
			Ivar *list = class_copyIvarList(c, &n);

			for (unsigned int i = 0; i < n; i++) {
				const char *type = ivar_getTypeEncoding(list[i]);
				if (!type || type[0] != '@') continue;

				id v = nil;
				@try { v = object_getIvar(cur, list[i]); }
				@catch (__unused id e) {}

				if (!v) continue;

				NSString *name = ivar_getName(list[i]) ? [@(ivar_getName(list[i])) lowercaseString] : @"";
				if ([v isKindOfClass:NSString.class]) {
					for (NSString *k in keys) {
						if (![name containsString:k]) continue;
						NSString *s = sciStringValue(v);
						if (s.length && (!best || s.length > best.length)) best = s;
					}
				} else {
					[stack addObject:v];
				}
			}

			if (list) free(list);
		}
	}

	return best;
}

static NSArray *sciXMATargets(id xma) {
	NSMutableArray *a = [NSMutableArray array];
	if (xma) [a addObject:xma];

	id items = sciKVC(xma, @"xmaItems");
	if ([items isKindOfClass:NSArray.class]) {
		for (id it in (NSArray *)items) {
			if (it) [a addObject:it];
			id meta = sciKVC(it, @"metadata");
			id preview = sciKVC(it, @"preview");
			if (meta) [a addObject:meta];
			if (preview) [a addObject:preview];
		}
	}

	id meta = sciKVC(xma, @"metadata");
	if (meta) [a addObject:meta];

	return a;
}

static BOOL sciXMAIsAudio(id xma, NSArray *targets, NSString *contentType) {
	NSString *ct = contentType.lowercaseString ?: @"";
	if ([ct containsString:@"audio"] || [ct containsString:@"music"] || [ct containsString:@"reels_audio"]) return YES;

	NSArray *audioKeys = @[@"playableAudioURL", @"accessoryPlayableURL", @"audioURL", @"audioUrl", @"musicAssetURL", @"voiceURL", @"voiceUrl"];
	NSArray *targetKeys = @[@"targetURL", @"webURL", @"shareURL", @"deepLink", @"url", @"mediaURL", @"playableURL", @"fullSizeURL"];

	for (id obj in targets) {
		if (sciPickURL(obj, audioKeys).length) return YES;

		NSString *u = sciPickURL(obj, targetKeys).lowercaseString;
		if ([u containsString:@"reels_audio_page"] || [u containsString:@"audio_page"] ||
			[u containsString:@"/audio/"] || [u containsString:@"music_canonical_id"] ||
			[u containsString:@"original_audio"]) return YES;
	}

	NSString *m = nil, *t = nil;
	int ms = 0, ts = 0;
	sciScanURLs(xma, 4, &m, &ms, &t, &ts, @"xma");
	return sciAudioish(m);
}

static void sciExtractXMA(id xma, SCIDeletedMessageKind *kind, NSString **text, NSString **media, int *ms, NSString **thumb, int *ts) {
	if (!xma || !kind) return;

	NSString *ct = sciStringValue(sciKVC(xma, @"contentType")).lowercaseString;
	NSArray *targets = sciXMATargets(xma);
	BOOL audio = sciXMAIsAudio(xma, targets, ct);

	if (audio) *kind = SCIDeletedMessageKindAudioShare;
	else if ([ct containsString:@"link"]) *kind = SCIDeletedMessageKindLink;
	else *kind = SCIDeletedMessageKindShare;

	NSArray *titles = @[@"headerTitleText", @"titleText", @"headerSubtitleText", @"subtitleText",
						@"captionBodyText", @"footerBodyText", @"overlayTitle", @"overlayDescription",
						@"quotedTitleText", @"quotedAttributionText", @"groupName", @"targetURLTitle",
						@"artistName", @"audioTitle", @"musicTitle", @"title", @"caption", @"text",
						@"summary", @"description"];

	NSArray *mediaKeys = audio
		? @[@"playableAudioURL", @"audioURL", @"audioUrl", @"accessoryPlayableURL", @"playableURL",
			@"fullSizeURL", @"targetURL", @"webURL", @"shareURL", @"deepLink", @"url", @"mediaURL"]
		: @[@"targetURL", @"webURL", @"shareURL", @"deepLink", @"url", @"mediaURL",
			@"playableURL", @"playableAudioURL", @"accessoryPlayableURL", @"fullSizeURL"];

	NSArray *thumbKeys = @[@"previewURL", @"accessoryPreviewURL", @"previewMaskURL", @"previewIgImageURL",
						   @"thumbnailURL", @"posterURL", @"imageURL"];

	NSMutableArray *parts = [NSMutableArray array];
	for (id obj in targets) {
		NSString *s = sciPickString(obj, titles);
		if (s.length && ![parts containsObject:s]) [parts addObject:s];
		if (parts.count >= 3) break;
	}
	if (!(*text).length && parts.count) *text = [parts componentsJoinedByString:@"\n"];

	for (id obj in targets) {
		if (!(*media).length) {
			NSString *u = sciPickURL(obj, mediaKeys);
			if (u.length) { *media = u; *ms = audio ? 120 : 70; }
		}
		if (!(*thumb).length) {
			NSString *u = sciPickURL(obj, thumbKeys);
			if (u.length) { *thumb = u; *ts = 70; }
		}
		if ((*media).length && (*thumb).length) break;
	}

	sciScanURLs(xma, 5, media, ms, thumb, ts, audio ? @"playableAudioURL" : @"xma");

	if (*kind == SCIDeletedMessageKindLink && (*media).length) {
		NSURL *u = [NSURL URLWithString:*media];
		NSString *host = u.host.lowercaseString;
		if ([host isEqualToString:@"l.instagram.com"] || [host isEqualToString:@"l.facebook.com"] || [host isEqualToString:@"lm.facebook.com"]) {
			NSURLComponents *c = [NSURLComponents componentsWithURL:u resolvingAgainstBaseURL:NO];
			for (NSURLQueryItem *q in c.queryItems) {
				if ([q.name isEqualToString:@"u"] && q.value.length) {
					*media = q.value;
					break;
				}
			}
		}
	}
}

static void sciVoiceMeta(id media, double *dur, NSArray **wave) {
	if (!media) return;

	NSMutableArray *stack = [NSMutableArray arrayWithObject:media];
	NSMutableSet *seen = [NSMutableSet set];

	while (stack.count) {
		id cur = stack.lastObject;
		[stack removeLastObject];

		if ([cur isKindOfClass:NSArray.class]) {
			for (id e in (NSArray *)cur) [stack addObject:e];
			continue;
		}

		if (sciSystemObject(cur)) continue;

		NSValue *box = [NSValue valueWithNonretainedObject:cur];
		if ([seen containsObject:box]) continue;
		[seen addObject:box];

		if (!*dur) {
			double d = sciDouble(cur, @"durationInSeconds");
			if (d <= 0) d = sciDouble(cur, @"duration");
			if (d <= 0) d = sciDouble(cur, @"audioDuration");
			if (d <= 0) d = sciDouble(cur, @"playbackDuration");

			if (d <= 0) {
				for (Class c = [cur class]; c && c != NSObject.class; c = class_getSuperclass(c)) {
					Ivar iv = class_getInstanceVariable(c, "_durationMs") ?: class_getInstanceVariable(c, "_instamadillo_durationMs");
					if (!iv) continue;

					const char *t = ivar_getTypeEncoding(iv);
					ptrdiff_t off = ivar_getOffset(iv);
					if (t[0] == 'q' || t[0] == 'Q') {
						long long ms = *(long long *)((char *)(__bridge void *)cur + off);
						if (ms > 0) d = ms / 1000.0;
					}
					break;
				}
			}

			if (d > 0) *dur = d;
		}

		if (!*wave) {
			id w = sciIvar(cur, "_averageVolume") ?: sciIvar(cur, "_waveformData") ?:
				   sciIvar(cur, "_waveform") ?: sciIvar(cur, "_amplitudes") ?:
				   sciKVC(cur, @"waveform") ?: sciKVC(cur, @"waveformData") ?: sciKVC(cur, @"averageVolume");
			if ([w isKindOfClass:NSArray.class]) *wave = w;
		}

		for (Class c = [cur class]; c && c != NSObject.class; c = class_getSuperclass(c)) {
			unsigned int n = 0;
			Ivar *list = class_copyIvarList(c, &n);

			for (unsigned int i = 0; i < n; i++) {
				const char *type = ivar_getTypeEncoding(list[i]);
				if (!type || type[0] != '@') continue;

				id v = nil;
				@try { v = object_getIvar(cur, list[i]); }
				@catch (__unused id e) {}

				if (v) [stack addObject:v];
			}

			if (list) free(list);
		}
	}
}

#pragma mark - Snapshot

static NSDictionary *sciBuildSnapshot(id message, NSString *ownerHint) {
	NSString *sid = sciSidFromMessage(message);
	if (!sid.length) return nil;

	NSMutableDictionary *snap = [NSMutableDictionary dictionary];
	snap[@"sid"] = sid;
	if (ownerHint.length) snap[@"owner_pk"] = ownerHint;

	NSString *threadId = sciStringValue(sciKVC(message, @"threadId"));
	id meta = sciIvar(message, "_metadata");
	if (!threadId.length) threadId = sciStrIvar(meta, "_threadId") ?: sciStrIvar(meta, "_threadID");
	if (threadId.length) snap[@"thread_id"] = threadId;

	NSString *senderPk = sciSenderPkFromMessage(message);
	if (senderPk.length) {
		NSString *u = nil, *fn = nil, *pic = nil;
		sciResolveSender(senderPk, &u, &fn, &pic);

		snap[@"sender_pk"] = senderPk;
		if (u.length) snap[@"sender_username"] = u;
		if (fn.length) snap[@"sender_full_name"] = fn;
		if (pic.length) snap[@"sender_profile_pic_url"] = pic;
	}

	NSDate *sentAt = sciSentAtFromMessage(message);
	if (sentAt) snap[@"sent_at"] = sentAt;

	NSString *replyId = sciReplyIdFromMessage(message);
	if (replyId.length) snap[@"reply_to_id"] = replyId;

	id content = sciIvar(message, "_content") ?: sciIvar(message, "_messageContent") ?: sciIvar(message, "_payload") ?: sciKVC(message, @"content");
	if (!content) {
		snap[@"kind"] = @(SCIDeletedMessageKindUnknown);
		return snap;
	}

	if (sciIvar(content, "_threadActivity") ||
		sciIvar(content, "_messageTypeNotLocallyAvailable_placeholderTitle") ||
		sciIvar(content, "_messageTypeNotLocallyAvailable_placeholderMessage") ||
		sciIvar(content, "_expiredPlaceholder_messageContent")) return nil;

	SCIDeletedMessageKind kind = SCIDeletedMessageKindUnknown;
	NSString *text = nil, *mediaURL = nil, *thumbURL = nil;
	int mediaScore = 0, thumbScore = 0;

	NSString *txt = sciStrIvar(content, "_text_string");
	if (txt.length) {
		kind = SCIDeletedMessageKindText;
		text = txt;
	}

	id media = sciIvar(content, "_media");
	if (media) {
		NSMutableSet *seen = [NSMutableSet set];
		NSMutableSet *tokens = [NSMutableSet set];
		sciCollectTokens(media, 5, seen, tokens);

		NSString *mpk = sciMediaPkFrom(media);
		if (mpk.length) snap[@"media_pk"] = mpk;

		// View-once media: photo/video lives at media._visualMedia._media._photo_photo / _video_video.
		BOOL visualHandled = NO;
		id vinfo = sciIvar(media, "_visualMedia");
		id vmedia = sciIvar(vinfo, "_media");
		if (vmedia) {
			snap[@"ephemeral"] = @YES;
			NSString *vpk = sciStrIvar(vinfo, "_mediaId");
			if (vpk.length) snap[@"media_pk"] = vpk;

			id vvideo = sciIvar(vmedia, "_video_video");
			id vphoto = sciIvar(vmedia, "_photo_photo");
			NSArray *cands = nil;
			if (vvideo) {
				kind = SCIDeletedMessageKindVideo;
				NSString *disp = nil, *a = nil;
				cands = sciVisualVideoCandidates(vvideo, &a, &disp);
				if (disp.length) { mediaURL = disp; mediaScore = 130; }
				if (a.length) snap[@"audio_url"] = a;
				NSString *thDisp = nil;
				sciVisualPhotoCandidates(sciIvar(vmedia, "_video_overlayPhoto"), &thDisp);
				if (thDisp.length) { thumbURL = thDisp; thumbScore = 130; }
			} else if (vphoto) {
				kind = SCIDeletedMessageKindPhoto;
				NSString *disp = nil;
				cands = sciVisualPhotoCandidates(vphoto, &disp);
				if (disp.length) { mediaURL = disp; mediaScore = 130; }
			}
			if (cands.count) snap[@"media_candidates"] = cands;
			visualHandled = (mediaURL.length > 0 || cands.count > 0);
		} else if (sciTokensContain(tokens, @[@"raven", @"visual", @"expiring", @"ephemeral", @"disappear"])) {
			snap[@"ephemeral"] = @YES;
		}

		if (!visualHandled) {
		if (sciTokensContain(tokens, @[@"voice", @"voicemedia", @"audio", @"audiomedia", @"audioclip"])) kind = SCIDeletedMessageKindVoice;
		else if (sciTokensContain(tokens, @[@"sticker"])) kind = SCIDeletedMessageKindSticker;
		else if (sciTokensContain(tokens, @[@"giphy", @"gif", @"animated"])) kind = SCIDeletedMessageKindGif;
		else if (sciTokensContain(tokens, @[@"video", @"dashmanifest", @"playableurl"])) kind = SCIDeletedMessageKindVideo;
		else kind = SCIDeletedMessageKindPhoto;

		if (kind == SCIDeletedMessageKindVoice) {
			double dur = 0;
			NSArray *wf = nil;
			sciVoiceMeta(media, &dur, &wf);

			if (dur > 0) snap[@"duration"] = @(dur);
			if (wf.count) snap[@"waveform"] = wf;

			NSString *u = sciPickURL(media, @[@"playableAudioURL", @"audioURL", @"voiceURL", @"playableURL", @"url", @"mediaURL"]);
			if (u.length) {
				mediaURL = u;
				mediaScore = 120;
			}
		}

		if (kind == SCIDeletedMessageKindVideo) {
			id permanent = sciIvar(media, "_permanentMedia_permanentMedia");
			id visual = sciIvar(media, "_visualMedia");
			id video = nil, overlay = nil;

			if (permanent) {
				video = sciIvar(permanent, "_video_video") ?: sciIvar(permanent, "_videoMemo_memoVideo");
				overlay = sciIvar(permanent, "_video_overlayPhoto") ?: sciIvar(permanent, "_videoMemo_videoMemoPhoto");
			}

			if (!video && visual) {
				video = sciIvar(visual, "_video_video") ?: sciIvar(visual, "_video");
				overlay = overlay ?: sciIvar(visual, "_video_overlayPhoto") ?: sciIvar(visual, "_overlayPhoto");
			}

			NSData *manifest = video ? sciIvar(video, "_dashManifestData") : nil;
			if ([manifest isKindOfClass:NSData.class] && manifest.length) {
				NSString *xml = [[NSString alloc] initWithData:manifest encoding:NSUTF8StringEncoding];
				NSArray<SCIDashRepresentation *> *reps = [SCIDashParser parseManifest:xml];
				SCIDashRepresentation *bestV = [SCIDashParser bestVideoFromRepresentations:reps];
				SCIDashRepresentation *bestA = [SCIDashParser bestAudioFromRepresentations:reps];

				if (bestV.url.absoluteString.length) {
					mediaURL = bestV.url.absoluteString;
					mediaScore = 100;
				}
				if (bestA.url.absoluteString.length) snap[@"audio_url"] = bestA.url.absoluteString;
			}

			if (!mediaURL.length && video) {
				for (NSString *iv in @[@"_broadcastURL", @"_subtitleURL", @"_playableURL"]) {
					id v = sciIvar(video, iv.UTF8String);
					if ([v isKindOfClass:NSURL.class]) {
						mediaURL = [(NSURL *)v absoluteString];
						mediaScore = 90;
						break;
					}
				}
			}

			if (overlay) {
				NSString *m = nil, *t = nil;
				int ms = 0, ts = 0;
				sciScanURLs(overlay, 4, &m, &ms, &t, &ts, @"thumbnail");
				if ((t ?: m).length) {
					thumbURL = t ?: m;
					thumbScore = MAX(ts, ms);
				}
			}
		}

		sciScanURLs(media, 5, &mediaURL, &mediaScore, &thumbURL, &thumbScore, kind == SCIDeletedMessageKindVoice ? @"playableAudioURL" : @"media");
		}  // !visualHandled
	}

	id reshare = sciIvar(content, "_reshare_attachment");
	if (reshare && kind == SCIDeletedMessageKindUnknown) {
		kind = SCIDeletedMessageKindShare;
		sciScanURLs(reshare, 5, &mediaURL, &mediaScore, &thumbURL, &thumbScore, @"reshare");

		if (!snap[@"media_pk"]) {
			NSString *rpk = sciMediaPkFrom(reshare) ?: sciMediaPkFrom(sciIvar(reshare, "_media"));
			if (rpk.length) snap[@"media_pk"] = rpk;
		}

		text = sciStrIvar(content, "_reshare_comment") ?: sciDeepTitle(reshare);
		if (!text.length) text = sciPickString(reshare, @[@"caption", @"captionText", @"title", @"headline", @"summary", @"name", @"username", @"text"]);
		if (!mediaURL.length) mediaURL = sciPickURL(reshare, @[@"webURL", @"shareURL", @"deepLink", @"url", @"mediaURL", @"playableURL"]);
	}

	id link = sciIvar(content, "_link_linkContext");
	if (link && kind == SCIDeletedMessageKindUnknown) {
		kind = SCIDeletedMessageKindLink;

		mediaURL = sciURLValue(sciIvar(link, "_url"));
		thumbURL = sciURLValue(sciIvar(link, "_imageURL"));

		NSMutableArray *parts = [NSMutableArray array];
		for (NSString *s in @[sciStrIvar(content, "_link_commentText") ?: @"",
							   sciStrIvar(link, "_title") ?: @"",
							   sciStrIvar(link, "_summary") ?: @""]) {
			if (s.length) [parts addObject:s];
		}
		if (!parts.count && mediaURL.length) [parts addObject:mediaURL];
		if (parts.count) text = [parts componentsJoinedByString:@"\n"];
	}

	id xma = sciIvar(content, "_xma") ?: sciIvar(content, "_bloksXMA") ?: sciIvar(content, "_pollMessage") ?: sciIvar(content, "_progressiveImage");
	if (xma && (kind == SCIDeletedMessageKindUnknown || kind == SCIDeletedMessageKindShare || kind == SCIDeletedMessageKindLink)) {
		SCIDeletedMessageKind xk = SCIDeletedMessageKindUnknown;
		NSString *xt = text, *xm = nil, *xh = nil;
		int xms = 0, xts = 0;

		sciExtractXMA(xma, &xk, &xt, &xm, &xms, &xh, &xts);

		if (xk != SCIDeletedMessageKindUnknown) {
			kind = xk;
			if (xt.length) text = xt;
			if (xm.length && xms >= mediaScore) {
				mediaURL = xm;
				mediaScore = xms;
			}
			if (xh.length && xts >= thumbScore) {
				thumbURL = xh;
				thumbScore = xts;
			}
		}
	}

	if (kind == SCIDeletedMessageKindUnknown && text.length) kind = SCIDeletedMessageKindText;

	snap[@"kind"] = @(kind);
	if (text.length) snap[@"text"] = text;
	if (mediaURL.length) snap[@"media_url"] = mediaURL;
	if (thumbURL.length) snap[@"thumb_url"] = thumbURL;

	return snap;
}

#pragma mark - Download

static NSString *sciExt(NSURL *url, NSURLResponse *resp, BOOL thumb) {
	NSString *e = url.pathExtension.lowercaseString;
	if (e.length) return e;

	NSString *m = resp.MIMEType.lowercaseString ?: @"";
	if ([m containsString:@"jpeg"] || [m containsString:@"jpg"]) return @"jpg";
	if ([m containsString:@"png"]) return @"png";
	if ([m containsString:@"gif"]) return @"gif";
	if ([m containsString:@"webp"]) return @"webp";
	if ([m containsString:@"mp4"]) return @"mp4";
	if ([m containsString:@"mpeg"] || [m containsString:@"mp3"]) return @"mp3";
	if ([m containsString:@"aac"]) return @"aac";
	if ([m containsString:@"m4a"]) return @"m4a";
	if ([m containsString:@"ogg"] || [m containsString:@"opus"]) return @"ogg";
	return thumb ? @"jpg" : @"mp4";
}

static void sciDownloadTemp(NSURL *url, void (^done)(NSURL *file, NSError *err)) {
	if (!url) {
		done(nil, [NSError errorWithDomain:@"SCIDM" code:0 userInfo:nil]);
		return;
	}

	[[sciSession() dataTaskWithURL:url completionHandler:^(NSData *data, NSURLResponse *resp, NSError *err) {
		if (err || !data.length) {
			done(nil, err);
			return;
		}

		NSURL *file = [SCITempFiles claimWithExt:sciExt(url, resp, NO) ttl:300 tag:@"dm"];
		if (![data writeToFile:file.path atomically:YES]) {
			[SCITempFiles releaseURL:file];
			done(nil, [NSError errorWithDomain:@"SCIDM" code:1 userInfo:nil]);
			return;
		}

		done(file, nil);
	}] resume];
}

static void sciSetMediaStatus(NSString *messageId, NSString *ownerPk, SCIDeletedMessageMediaStatus status) {
	if (!messageId.length) return;
	[SCIDeletedMessagesStorage updateMessageWithId:messageId ownerPK:ownerPk mutator:^BOOL(SCIDeletedMessage *m) {
		if (m.mediaStatus == status) return NO;
		m.mediaStatus = status;
		return YES;
	}];
}

static NSString *sciBestCandidateURL(id imageVersions2) {
	if (![imageVersions2 isKindOfClass:NSDictionary.class]) return nil;
	NSArray *cands = imageVersions2[@"candidates"];
	if (![cands isKindOfClass:NSArray.class]) return nil;

	NSString *best = nil;
	double bestW = -1;
	for (id c in cands) {
		if (![c isKindOfClass:NSDictionary.class]) continue;
		id u = c[@"url"];
		if (![u isKindOfClass:NSString.class] || !((NSString *)u).length) continue;
		double w = [c[@"width"] isKindOfClass:NSNumber.class] ? [c[@"width"] doubleValue] : 0;
		if (w > bestW) { bestW = w; best = u; }
	}
	return best;
}

// Rebuild a live media URL by feed PK (resolves nil for view-once — no public PK).
static void sciRefetchMediaByPK(NSString *pk, void (^completion)(NSString *videoURL, NSString *photoURL)) {
	if (!pk.length) { completion(nil, nil); return; }

	NSString *path = [NSString stringWithFormat:@"media/%@/info/", pk];
	[SCIInstagramAPI sendRequestWithMethod:@"GET" path:path body:nil completion:^(NSDictionary *resp, NSError *err) {
		NSArray *items = [resp[@"items"] isKindOfClass:NSArray.class] ? resp[@"items"] : nil;
		id item = items.firstObject;
		if (![item isKindOfClass:NSDictionary.class]) { completion(nil, nil); return; }

		NSString *video = nil, *photo = nil;

		NSArray *vv = ((NSDictionary *)item)[@"video_versions"];
		if ([vv isKindOfClass:NSArray.class] && vv.count && [vv[0] isKindOfClass:NSDictionary.class]) {
			id u = vv[0][@"url"];
			if ([u isKindOfClass:NSString.class]) video = u;
		}

		photo = sciBestCandidateURL(((NSDictionary *)item)[@"image_versions2"]);

		// Carousel: fall back to the first child's media.
		if (!video && !photo) {
			NSArray *carousel = ((NSDictionary *)item)[@"carousel_media"];
			id first = [carousel isKindOfClass:NSArray.class] ? carousel.firstObject : nil;
			if ([first isKindOfClass:NSDictionary.class]) {
				NSArray *cvv = first[@"video_versions"];
				if ([cvv isKindOfClass:NSArray.class] && cvv.count && [cvv[0] isKindOfClass:NSDictionary.class]) {
					id u = cvv[0][@"url"];
					if ([u isKindOfClass:NSString.class]) video = u;
				}
				photo = sciBestCandidateURL(first[@"image_versions2"]);
			}
		}

		completion(video, photo);
	}];
}

// Reject error/HTML/JSON bodies masquerading as media (e.g. media_fallback's 400).
static BOOL sciLooksLikeMedia(NSURLResponse *resp, NSData *data) {
	if (data.length < 256) return NO;   // real media is never this small
	if ([resp isKindOfClass:NSHTTPURLResponse.class]) {
		long s = [(NSHTTPURLResponse *)resp statusCode];
		if (s < 200 || s >= 300) return NO;
	}
	NSString *m = resp.MIMEType.lowercaseString ?: @"";
	if (m.length) {
		if ([m hasPrefix:@"image/"] || [m hasPrefix:@"video/"] || [m hasPrefix:@"audio/"] || [m containsString:@"octet-stream"] || [m containsString:@"mp4"]) return YES;
		if ([m hasPrefix:@"text/"] || [m containsString:@"json"] || [m containsString:@"javascript"] || [m containsString:@"html"]) return NO;
	}
	return YES;   // unknown mime but sizeable body — accept
}

static BOOL sciWriteMediaBytes(NSData *data, NSURLResponse *resp, NSURL *url, NSString *messageId, NSString *ownerPk, BOOL thumb) {
	if (!data.length || !messageId.length) return NO;

	NSString *ext = sciExt(url, resp, thumb);
	NSString *rel = thumb
		? [NSString stringWithFormat:@"thumb_%@.%@", messageId, ext]
		: [SCIDeletedMessagesStorage reserveRelativeMediaPathForMessageId:messageId extension:ext ownerPK:ownerPk];

	NSString *abs = [SCIDeletedMessagesStorage absolutePathForRelativePath:rel ownerPK:ownerPk];
	if (!abs.length || ![data writeToFile:abs atomically:YES]) return NO;

	[SCIDeletedMessagesStorage updateMessageWithId:messageId ownerPK:ownerPk mutator:^BOOL(SCIDeletedMessage *m) {
		if (thumb) m.thumbnailPath = rel;
		else m.mediaPath = rel;
		return YES;
	}];
	return YES;
}

static void sciDownloadOne(NSString *urlString, BOOL auth, NSString *messageId, NSString *ownerPk, BOOL thumb, void (^completion)(BOOL ok)) {
	NSURL *url = urlString.length ? [NSURL URLWithString:urlString] : nil;
	if (!url || !messageId.length) { if (completion) completion(NO); return; }

	if (auth) {
		[SCIInstagramAPI downloadAuthorizedURL:url completion:^(NSData *data, NSURLResponse *resp, NSError *err) {
			BOOL ok = (!err && sciLooksLikeMedia(resp, data)) ? sciWriteMediaBytes(data, resp, url, messageId, ownerPk, thumb) : NO;
			if (completion) completion(ok);
		}];
		return;
	}

	dispatch_async(sciDownloadQueue(), ^{
		[[sciSession() dataTaskWithURL:url completionHandler:^(NSData *data, NSURLResponse *resp, NSError *err) {
			BOOL ok = (!err && sciLooksLikeMedia(resp, data)) ? sciWriteMediaBytes(data, resp, url, messageId, ownerPk, thumb) : NO;
			if (completion) completion(ok);
		}] resume];
	});
}

static void sciDownloadMedia(NSString *urlString, NSString *messageId, NSString *ownerPk, BOOL thumb, void (^completion)(BOOL ok)) {
	sciDownloadOne(urlString, NO, messageId, ownerPk, thumb, completion);
}

static void sciDownloadAndMuxVideo(NSString *videoURL, NSString *audioURL, NSString *messageId, NSString *ownerPk, void (^completion)(BOOL ok)) {
	NSURL *vURL = videoURL.length ? [NSURL URLWithString:videoURL] : nil;
	NSURL *aURL = audioURL.length ? [NSURL URLWithString:audioURL] : nil;
	if (!vURL || !aURL || !messageId.length || ![SCIFFmpeg isAvailable]) { if (completion) completion(NO); return; }

	dispatch_async(sciDownloadQueue(), ^{
		__block NSURL *vFile = nil, *aFile = nil;
		dispatch_semaphore_t sema = dispatch_semaphore_create(0);

		sciDownloadTemp(vURL, ^(NSURL *f, NSError *e) {
			if (!e) vFile = f;
			dispatch_semaphore_signal(sema);
		});
		dispatch_semaphore_wait(sema, DISPATCH_TIME_FOREVER);

		sciDownloadTemp(aURL, ^(NSURL *f, NSError *e) {
			if (!e) aFile = f;
			dispatch_semaphore_signal(sema);
		});
		dispatch_semaphore_wait(sema, DISPATCH_TIME_FOREVER);

		if (!vFile || !aFile) {
			if (vFile) [NSFileManager.defaultManager removeItemAtURL:vFile error:nil];
			if (aFile) [NSFileManager.defaultManager removeItemAtURL:aFile error:nil];
			if (completion) completion(NO);
			return;
		}

		[SCIFFmpeg muxVideoURL:vFile audioURL:aFile preset:nil progress:nil completion:^(NSURL *outURL, NSError *err) {
			[NSFileManager.defaultManager removeItemAtURL:vFile error:nil];
			[NSFileManager.defaultManager removeItemAtURL:aFile error:nil];

			if (err || !outURL) { if (completion) completion(NO); return; }

			NSString *rel = [SCIDeletedMessagesStorage reserveRelativeMediaPathForMessageId:messageId extension:@"mp4" ownerPK:ownerPk];
			NSString *abs = [SCIDeletedMessagesStorage absolutePathForRelativePath:rel ownerPK:ownerPk];
			if (!abs.length) { if (completion) completion(NO); return; }

			[NSFileManager.defaultManager removeItemAtPath:abs error:nil];
			if (![NSFileManager.defaultManager moveItemAtURL:outURL toURL:[NSURL fileURLWithPath:abs] error:nil]) { if (completion) completion(NO); return; }

			[SCIDeletedMessagesStorage updateMessageWithId:messageId ownerPK:ownerPk mutator:^BOOL(SCIDeletedMessage *m) {
				m.mediaPath = rel;
				return YES;
			}];
			if (completion) completion(YES);
		}];
	});
}

// Try each candidate; on total failure, refetch-by-PK. Sets the final status.
static void sciAcquireFromCandidates(NSString *messageId, NSString *ownerPk, SCIDeletedMessageKind kind,
									 NSArray<NSDictionary *> *cands, NSUInteger idx, NSString *mediaPk, BOOL hadAny) {
	if (idx < cands.count) {
		NSDictionary *c = cands[idx];
		sciDownloadOne(c[@"url"], [c[@"auth"] boolValue], messageId, ownerPk, NO, ^(BOOL ok) {
			if (ok) { sciSetMediaStatus(messageId, ownerPk, SCIDeletedMessageMediaStatusSaved); return; }
			sciAcquireFromCandidates(messageId, ownerPk, kind, cands, idx + 1, mediaPk, hadAny);
		});
		return;
	}

	if (mediaPk.length) {
		sciRefetchMediaByPK(mediaPk, ^(NSString *v, NSString *p) {
			NSString *fresh = (kind == SCIDeletedMessageKindVideo) ? (v ?: p) : (p ?: v);
			if (fresh.length) {
				sciAcquireFromCandidates(messageId, ownerPk, kind, @[@{@"url": fresh, @"auth": @NO}], 0, nil, YES);
			} else {
				sciSetMediaStatus(messageId, ownerPk, hadAny ? SCIDeletedMessageMediaStatusFailed : SCIDeletedMessageMediaStatusUnavailable);
			}
		});
		return;
	}

	sciSetMediaStatus(messageId, ownerPk, hadAny ? SCIDeletedMessageMediaStatusFailed : SCIDeletedMessageMediaStatusUnavailable);
}

static void sciAcquireMediaCandidates(NSString *messageId, NSString *ownerPk, SCIDeletedMessageKind kind,
									  NSArray<NSDictionary *> *cands, NSString *audioURL, NSString *mediaPk) {
	if (!messageId.length) return;
	BOOL hadAny = cands.count > 0 || mediaPk.length > 0;

	if (kind == SCIDeletedMessageKindVideo && audioURL.length && cands.count &&
		![cands[0][@"auth"] boolValue] && [SCIFFmpeg isAvailable]) {
		NSString *vurl = cands[0][@"url"];
		sciDownloadAndMuxVideo(vurl, audioURL, messageId, ownerPk, ^(BOOL ok) {
			if (ok) { sciSetMediaStatus(messageId, ownerPk, SCIDeletedMessageMediaStatusSaved); return; }
			sciAcquireFromCandidates(messageId, ownerPk, kind, cands, 0, mediaPk, hadAny);  // retry video-only
		});
		return;
	}

	sciAcquireFromCandidates(messageId, ownerPk, kind, cands, 0, mediaPk, hadAny);
}

static void sciAcquireMedia(NSString *messageId, NSString *ownerPk, SCIDeletedMessageKind kind,
							NSString *mediaURL, NSString *audioURL, NSString *mediaPk, BOOL allowRefetch) {
	NSMutableArray *c = [NSMutableArray array];
	if (mediaURL.length) [c addObject:@{@"url": mediaURL, @"auth": @NO}];
	sciAcquireMediaCandidates(messageId, ownerPk, kind, c, audioURL, allowRefetch ? mediaPk : nil);
}

void sciDMUpdateKeepAlive(void) {
	[SCIBackgroundActivity setSource:@"dm_keepalive" active:[SCIUtils getBoolPref:@"deleted_messages_keepalive"]];
}

void sciDMRetryMediaDownload(NSString *messageId, NSString *ownerPk) {
	if (!messageId.length || !ownerPk.length) return;

	// Throttle per-message: foreground/viewDidAppear both drive retries, so a
	// permanently-dead PK (expired/private) would re-hit the API every time.
	static NSMutableDictionary<NSString *, NSNumber *> *lastAttempt;
	static dispatch_once_t once;
	dispatch_once(&once, ^{ lastAttempt = [NSMutableDictionary new]; });
	@synchronized (lastAttempt) {
		double now = CACurrentMediaTime();
		NSNumber *prev = lastAttempt[messageId];
		if (prev && now - prev.doubleValue < 60.0) return;
		lastAttempt[messageId] = @(now);
	}

	__block BOOL go = NO;
	__block SCIDeletedMessageKind kind = SCIDeletedMessageKindUnknown;
	__block NSString *mediaURL = nil, *mediaPk = nil;
	__block NSArray *cands = nil;

	[SCIDeletedMessagesStorage updateMessageWithId:messageId ownerPK:ownerPk mutator:^BOOL(SCIDeletedMessage *m) {
		if (m.mediaPath.length) return NO;                // already have the blob
		if (!m.mediaCandidates.count && !m.mediaURL.length && !m.mediaPk.length) return NO;  // nothing to try

		kind = m.kind;
		mediaURL = m.mediaURL;
		mediaPk = m.mediaPk;
		cands = m.mediaCandidates;
		go = YES;
		m.mediaStatus = SCIDeletedMessageMediaStatusPending;
		return YES;
	}];

	if (!go) return;
	if (cands.count) sciAcquireMediaCandidates(messageId, ownerPk, kind, cands, nil, mediaPk);
	else sciAcquireMedia(messageId, ownerPk, kind, mediaURL, nil, mediaPk, YES);
}

#pragma mark - On-open visual (view-once) capture

static double sciIVWidth(id v) {
	for (NSString *wk in @[@"_width", @"width", @"_pixelWidth", @"_size"]) {
		Ivar iv = class_getInstanceVariable([v class], wk.UTF8String);
		if (!iv) continue;
		const char *t = ivar_getTypeEncoding(iv);
		char *b = (char *)(__bridge void *)v + ivar_getOffset(iv);
		if (!t) continue;
		if (t[0] == 'q') return (double)*(long long *)b;
		if (t[0] == 'Q') return (double)*(unsigned long long *)b;
		if (t[0] == 'i') return (double)*(int *)b;
		if (t[0] == 'd') return *(double *)b;
		if (t[0] == '{') return ((CGSize *)b)->width;   // _size = CGSize
	}
	return 0;
}

static NSString *sciIVURL(id v) {
	NSString *m = nil, *t = nil;
	int ms = 0, ts = 0;
	sciScanURLs(v, 3, &m, &ms, &t, &ts, @"url");
	return m.length ? m : t;
}

// IGPhoto download candidates (widest CDN, then authed media_fallback). outDisplay = display URL.
static NSArray<NSDictionary *> *sciVisualPhotoCandidates(id photo, NSString **outDisplay) {
	if (outDisplay) *outDisplay = nil;
	if (!photo) return @[];

	NSString *fallback = nil, *bestCDN = nil;
	double bestW = -1;
	for (NSString *ivk in @[@"_originalImageVersions", @"_processedImageVersions"]) {
		id arr = sciIvar(photo, ivk.UTF8String);
		if (![arr isKindOfClass:NSArray.class]) continue;
		for (id v in (NSArray *)arr) {
			if (!fallback.length) {
				id fb = sciIvar(v, "_fallbackURL");
				if ([fb isKindOfClass:NSURL.class]) fallback = [(NSURL *)fb absoluteString];
			}
			NSString *u = sciIVURL(v);
			if (u.length) {
				double w = sciIVWidth(v);
				if (w > bestW) { bestW = w; bestCDN = u; }
			}
		}
	}
	if (!bestCDN.length) {
		NSString *m = nil, *t = nil;
		int ms = 0, ts = 0;
		sciScanURLs(photo, 6, &m, &ms, &t, &ts, @"image");
		bestCDN = m.length ? m : t;
	}

	if (outDisplay) *outDisplay = bestCDN;

	NSMutableArray *out = [NSMutableArray array];
	if (bestCDN.length)  [out addObject:@{@"url": bestCDN,  @"auth": @NO}];
	if (fallback.length) [out addObject:@{@"url": fallback, @"auth": @YES}];
	return out;
}

// IGVideo download candidates (CDN). outAudio = DASH audio for mux; outDisplay = primary URL.
static NSArray<NSDictionary *> *sciVisualVideoCandidates(id video, NSString **outAudio, NSString **outDisplay) {
	if (outAudio) *outAudio = nil;
	if (outDisplay) *outDisplay = nil;
	if (!video) return @[];

	NSMutableArray *out = [NSMutableArray array];
	NSString *primary = nil;

	NSData *manifest = sciIvar(video, "_dashManifestData");
	if ([manifest isKindOfClass:NSData.class] && manifest.length) {
		NSString *xml = [[NSString alloc] initWithData:manifest encoding:NSUTF8StringEncoding];
		NSArray<SCIDashRepresentation *> *reps = [SCIDashParser parseManifest:xml];
		SCIDashRepresentation *bestV = [SCIDashParser bestVideoFromRepresentations:reps];
		SCIDashRepresentation *bestA = [SCIDashParser bestAudioFromRepresentations:reps];
		if (bestV.url.absoluteString.length) { primary = bestV.url.absoluteString; [out addObject:@{@"url": primary, @"auth": @NO}]; }
		if (bestA.url.absoluteString.length && outAudio) *outAudio = bestA.url.absoluteString;
	}

	id urls = sciIvar(video, "_allVideoURLs");
	if ([urls isKindOfClass:NSSet.class] || [urls isKindOfClass:NSArray.class]) {
		for (id u in urls) {
			NSString *us = [u isKindOfClass:NSURL.class] ? [(NSURL *)u absoluteString] : ([u isKindOfClass:NSString.class] ? u : nil);
			if (us.length) { [out addObject:@{@"url": us, @"auth": @NO}]; if (!primary) primary = us; }
		}
	}

	for (NSString *iv in @[@"_broadcastURL", @"_playableURL"]) {
		id v = sciIvar(video, iv.UTF8String);
		NSString *us = [v isKindOfClass:NSURL.class] ? [(NSURL *)v absoluteString] : nil;
		if (us.length) { [out addObject:@{@"url": us, @"auth": @NO}]; if (!primary) primary = us; }
	}

	if (!out.count) {
		NSString *m = nil, *t = nil;
		int ms = 0, ts = 0;
		sciScanURLs(video, 5, &m, &ms, &t, &ts, @"video");
		if (m.length) { [out addObject:@{@"url": m, @"auth": @NO}]; primary = m; }
	}

	if (outDisplay) *outDisplay = primary;
	return out;
}

void sciDMCaptureVisualMessageOnOpen(id visualMessage, id contextMetadata, NSString *ownerPk) {
	if (!sciCaptureEnabled() || !visualMessage || !contextMetadata) return;

	@try {
		id info = sciIvar(visualMessage, "_visualMediaInfo");
		if (!info) return;

		// _viewMode: 1 = replayable, 2 = view-once (capture these); 0 = permanent (skip).
		long long viewMode = 0;
		Ivar vm = class_getInstanceVariable([info class], "_viewMode");
		if (vm) {
			const char *t = ivar_getTypeEncoding(vm);
			char *b = (char *)(__bridge void *)info + ivar_getOffset(vm);
			if (t && t[0] == 'q') viewMode = *(long long *)b;
			else if (t && t[0] == 'Q') viewMode = (long long)*(unsigned long long *)b;
			else if (t && t[0] == 'i') viewMode = *(int *)b;
		}
		if (viewMode != 1 && viewMode != 2) return;

		id key = sciIvar(contextMetadata, "_key");
		NSString *sid = sciStrIvar(key, "_serverId") ?: sciStrIvar(key, "_messageServerId");
		if (!sid.length) return;

		NSString *owner = ownerPk.length ? ownerPk.copy : @"";
		NSString *senderPk = sciStrIvar(contextMetadata, "_senderPk");
		if (senderPk.length && [senderPk isEqualToString:owner]) return;  // skip own sends

		id media = sciIvar(info, "_media");
		id videoObj = sciIvar(media, "_video_video");
		id photoObj = sciIvar(media, "_photo_photo");
		SCIDeletedMessageKind kind = videoObj ? SCIDeletedMessageKindVideo : SCIDeletedMessageKindPhoto;

		NSString *mediaURL = nil, *audioURL = nil, *thumbURL = nil;
		NSArray *cands = nil;
		if (videoObj) {
			cands = sciVisualVideoCandidates(videoObj, &audioURL, &mediaURL);
			sciVisualPhotoCandidates(sciIvar(media, "_video_overlayPhoto"), &thumbURL);
		} else {
			cands = sciVisualPhotoCandidates(photoObj, &mediaURL);
		}

		NSString *mediaPk = sciStrIvar(info, "_mediaId");
		NSDate *sentAt = nil;
		id sd = sciIvar(contextMetadata, "_sentDate");
		if ([sd isKindOfClass:NSDate.class]) sentAt = sd;

		// Thread id for grouping. The django identifier holds it as a long digit string; scan for it.
		id threadKey = sciIvar(contextMetadata, "_threadKey");
		id dj = sciIvar(threadKey, "_djangoThread_identifier");
		NSString *threadId = sciStrIvar(dj, "_identifier") ?: sciStrIvar(dj, "_threadId") ?: sciScanLongDigitString(dj);

		NSString *senderU = nil;
		if (senderPk.length) sciResolveSender(senderPk, &senderU, NULL, NULL);

		dispatch_async(sciCaptureQueue(), ^{
			// Dedup: if we already hold the blob for this message, don't re-capture.
			__block BOOL haveBlob = NO;
			[SCIDeletedMessagesStorage updateMessageWithId:sid ownerPK:owner mutator:^BOOL(SCIDeletedMessage *m) {
				haveBlob = m.mediaPath.length > 0;
				return NO;
			}];
			if (haveBlob) return;

			NSDate *now = NSDate.date;
			SCIDeletedMessage *m = [SCIDeletedMessage new];
			m.messageId = sid;
			m.threadId = threadId;
			m.senderPk = senderPk ?: @"";
			m.senderUsername = senderU;
			m.sentAt = sentAt ?: now;
			m.capturedAt = now;
			m.deletedAt = now;          // view-once is consumed on open — no longer in the chat
			m.kind = kind;
			m.isEphemeral = YES;
			m.mediaURL = mediaURL;
			m.thumbnailURL = thumbURL;
			m.mediaPk = mediaPk;
			if (cands.count) m.mediaCandidates = cands;

			NSDictionary *tinfo = sciCachedThreadInfo(threadId);
			if (tinfo) {
				if ([tinfo[@"is_group"] isKindOfClass:NSNumber.class]) m.isGroup = [tinfo[@"is_group"] boolValue];
				if ([tinfo[@"thread_title"] isKindOfClass:NSString.class]) m.threadTitle = tinfo[@"thread_title"];
				if ([tinfo[@"thread_avatar_url"] isKindOfClass:NSString.class]) m.threadAvatarURL = tinfo[@"thread_avatar_url"];
			}

			BOOL fetchable = cands.count || mediaPk.length;
			m.mediaStatus = fetchable ? SCIDeletedMessageMediaStatusPending : SCIDeletedMessageMediaStatusUnavailable;

			if ([SCIDeletedMessagesStorage isExcludedThreadId:m.threadId senderPk:m.senderPk ownerPK:owner]) return;

			[SCIDeletedMessagesStorage saveMessage:m forOwnerPK:owner];
			if (threadId.length) sciResolveThreadInfo(threadId, owner, NO);

			if (fetchable) sciAcquireMediaCandidates(sid, owner, kind, cands ?: @[], audioURL, mediaPk);
			if (thumbURL.length) sciDownloadMedia(thumbURL, sid, owner, YES, nil);
		});
	} @catch (__unused id e) {}
}

#pragma mark - Fallback lookup

static id sciThreadStateForApplicator(id applicator, NSString *threadId) {
	if (!applicator || !threadId.length) return nil;

	@try {
		id cache = sciIvar(applicator, "_cache");
		SEL sel = NSSelectorFromString(@"threadClientStateForThreadId:");
		if (!cache || ![cache respondsToSelector:sel]) return nil;
		return ((id (*)(id, SEL, id))objc_msgSend)(cache, sel, threadId);
	} @catch (__unused id e) {
		return nil;
	}
}

static id sciFallbackLookupMessage(id applicator, NSString *sid, NSString *threadId) {
	if (!sid.length) return nil;

	id state = sciThreadStateForApplicator(applicator, threadId);
	id messageSet = sciIvar(state, "_threadMessageSet");
	id dict = sciIvar(messageSet, "_messagesByServerId");
	return [dict isKindOfClass:NSDictionary.class] ? dict[sid] : nil;
}

#pragma mark - Thread metadata resolution

static NSMutableDictionary<NSString *, NSDictionary *> *sciThreadInfoCache(void) {
	static NSMutableDictionary *d;
	static dispatch_once_t once;
	dispatch_once(&once, ^{ d = [NSMutableDictionary new]; });
	return d;
}

// Threads with a REST fetch currently in flight — avoids firing duplicates.
static NSMutableSet<NSString *> *sciThreadFetchInflight(void) {
	static NSMutableSet *s;
	static dispatch_once_t once;
	dispatch_once(&once, ^{ s = [NSMutableSet set]; });
	return s;
}

// Cached per session, applied to any account.
static NSMutableDictionary<NSString *, NSArray *> *sciThreadParticipants(void) {
	static NSMutableDictionary *d;
	static dispatch_once_t once;
	dispatch_once(&once, ^{ d = [NSMutableDictionary new]; });
	return d;
}

static NSDictionary *sciCachedThreadInfo(NSString *threadId) {
	if (!threadId.length) return nil;
	@synchronized (sciThreadInfoCache()) { return sciThreadInfoCache()[threadId]; }
}

static NSString *sciThreadImageURL(NSDictionary *thread) {
	id img = thread[@"thread_image"];
	if ([img isKindOfClass:NSString.class] && [(NSString *)img length]) return img;
	if ([img isKindOfClass:NSDictionary.class]) {
		id u = img[@"url"] ?: img[@"uri"];
		if ([u isKindOfClass:NSString.class] && [(NSString *)u length]) return u;
	}
	return nil;
}

static void sciApplyThreadCacheForOwner(NSString *threadId, NSString *owner, BOOL overwrite) {
	NSDictionary *info = sciCachedThreadInfo(threadId);
	if (info.count) [SCIDeletedMessagesStorage applyThreadInfo:info forThreadId:threadId ownerPK:owner];

	NSArray *roster = nil;
	@synchronized (sciThreadParticipants()) { roster = sciThreadParticipants()[threadId]; }
	for (NSDictionary *u in roster) {
		NSString *pk = u[@"pk"];
		NSMutableDictionary *si = [NSMutableDictionary dictionary];
		if ([u[@"username"] isKindOfClass:NSString.class]) si[@"username"] = u[@"username"];
		if ([u[@"full_name"] isKindOfClass:NSString.class]) si[@"full_name"] = u[@"full_name"];
		if ([u[@"profile_pic_url"] isKindOfClass:NSString.class]) si[@"profile_pic_url"] = u[@"profile_pic_url"];
		if (pk.length && si.count) [SCIDeletedMessagesStorage applySenderInfo:si forSenderPK:pk ownerPK:owner overwrite:overwrite];
	}
}

// Fetch thread group/title/roster over REST and stamp onto the asking account's
// store (delta stream has no thread metadata). force=YES refetches + overwrites.
static void sciResolveThreadInfo(NSString *threadId, NSString *owner, BOOL force) {
	if (!threadId.length) return;

	// Group name + image from live metadata (the REST thread_image is usually empty for groups).
	if (force || !sciCachedThreadInfo(threadId)) {
		[SCIDirectThreadInfo fetchThreadId:threadId ownerPK:owner completion:^(id thread) {
			NSDictionary *gi = [SCIDirectThreadInfo groupInfoForThread:thread viewerPK:owner];
			if (![gi[@"is_group"] boolValue]) return;
			NSMutableDictionary *info = [NSMutableDictionary dictionaryWithObject:@YES forKey:@"is_group"];
			if ([gi[@"name"] isKindOfClass:NSString.class]) info[@"thread_title"] = gi[@"name"];
			if ([gi[@"image"] isKindOfClass:NSString.class]) info[@"thread_avatar_url"] = gi[@"image"];
			if (info.count > 1) [SCIDeletedMessagesStorage applyThreadInfo:info forThreadId:threadId ownerPK:owner];
		}];
	}

	// Cached — apply to this account and skip the fetch (covers account switching).
	if (sciCachedThreadInfo(threadId) && !force) {
		sciApplyThreadCacheForOwner(threadId, owner, NO);
		return;
	}

	@synchronized (sciThreadFetchInflight()) {
		if ([sciThreadFetchInflight() containsObject:threadId]) return;
		[sciThreadFetchInflight() addObject:threadId];
	}

	NSString *path = [NSString stringWithFormat:@"direct_v2/threads/%@/?limit=1", threadId];
	[SCIInstagramAPI sendRequestWithMethod:@"GET" path:path body:nil completion:^(NSDictionary *resp, NSError *err) {
		@synchronized (sciThreadFetchInflight()) { [sciThreadFetchInflight() removeObject:threadId]; }

		NSDictionary *t = [resp[@"thread"] isKindOfClass:NSDictionary.class] ? resp[@"thread"] : nil;
		if (!t.count) return;

		NSMutableDictionary *info = [NSMutableDictionary dictionary];
		id grp = t[@"is_group"];
		if ([grp isKindOfClass:NSNumber.class]) info[@"is_group"] = @([grp boolValue]);
		NSString *title = [t[@"thread_title"] isKindOfClass:NSString.class] ? t[@"thread_title"] : nil;
		if (title.length) info[@"thread_title"] = title;
		NSString *avatar = sciThreadImageURL(t);
		if (avatar.length) info[@"thread_avatar_url"] = avatar;

		NSMutableArray *roster = [NSMutableArray array];
		id users = t[@"users"];
		if ([users isKindOfClass:NSArray.class]) {
			for (id u in (NSArray *)users) {
				if (![u isKindOfClass:NSDictionary.class]) continue;
				id pk = u[@"pk"] ?: u[@"pk_id"] ?: u[@"strong_id__"];
				NSString *pkStr = [pk isKindOfClass:NSString.class] ? pk : ([pk isKindOfClass:NSNumber.class] ? [pk stringValue] : nil);
				if (!pkStr.length) continue;
				NSMutableDictionary *e = [NSMutableDictionary dictionaryWithObject:pkStr forKey:@"pk"];
				if ([u[@"username"] isKindOfClass:NSString.class]) e[@"username"] = u[@"username"];
				if ([u[@"full_name"] isKindOfClass:NSString.class]) e[@"full_name"] = u[@"full_name"];
				if ([u[@"profile_pic_url"] isKindOfClass:NSString.class]) e[@"profile_pic_url"] = u[@"profile_pic_url"];
				[roster addObject:e];
			}
		}

		if (!info.count && !roster.count) return;

		if (info.count) { @synchronized (sciThreadInfoCache()) { sciThreadInfoCache()[threadId] = info; } }
		if (roster.count) { @synchronized (sciThreadParticipants()) { sciThreadParticipants()[threadId] = roster; } }

		sciApplyThreadCacheForOwner(threadId, owner, force);
	}];
}

void sciDMResolveThreadInfo(NSString *threadId, NSString *ownerPk) {
	sciResolveThreadInfo(threadId, ownerPk, NO);
}

void sciDMRefreshThreadInfo(NSString *threadId, NSString *ownerPk) {
	sciResolveThreadInfo(threadId, ownerPk, YES);
}

static NSString *sciRosterUsername(NSString *threadId, NSString *pk) {
	if (!threadId.length || !pk.length) return nil;
	NSArray *roster = nil;
	@synchronized (sciThreadParticipants()) { roster = sciThreadParticipants()[threadId]; }
	for (NSDictionary *u in roster) {
		if ([u[@"pk"] isEqualToString:pk] && [u[@"username"] isKindOfClass:NSString.class]) return u[@"username"];
	}
	return nil;
}

static NSString *sciItemTypeLabel(NSString *type) {
	NSString *t = type.lowercaseString ?: @"";
	if ([t containsString:@"voice"]) return SCILocalized(@"Voice");
	if ([t isEqualToString:@"clip"] || [t containsString:@"reel"]) return SCILocalized(@"Reel");
	if ([t containsString:@"animated"]) return SCILocalized(@"GIF");
	if ([t containsString:@"story"]) return SCILocalized(@"Story");
	if ([t containsString:@"media"] || [t containsString:@"raven"] || [t containsString:@"visual"]) return SCILocalized(@"Photo or video");
	if ([t containsString:@"link"]) return SCILocalized(@"Link");
	return SCILocalized(@"a message");
}

static void sciResolveReactionTarget(NSString *recordId, NSString *threadId, NSString *targetMessageId, NSString *owner) {
	if (!recordId.length || !threadId.length || !targetMessageId.length) return;

	NSString *path = [NSString stringWithFormat:@"direct_v2/threads/%@/?limit=20", threadId];
	[SCIInstagramAPI sendRequestWithMethod:@"GET" path:path body:nil completion:^(NSDictionary *resp, NSError *err) {
		NSDictionary *t = [resp[@"thread"] isKindOfClass:NSDictionary.class] ? resp[@"thread"] : nil;
		NSArray *items = [t[@"items"] isKindOfClass:NSArray.class] ? t[@"items"] : nil;

		NSDictionary *found = nil;
		for (id it in items) {
			if (![it isKindOfClass:NSDictionary.class]) continue;
			id iid = ((NSDictionary *)it)[@"item_id"];
			NSString *iidS = [iid isKindOfClass:NSString.class] ? iid : ([iid isKindOfClass:NSNumber.class] ? [iid stringValue] : nil);
			if ([iidS isEqualToString:targetMessageId]) { found = it; break; }
		}
		if (!found) return;

		NSString *text = [found[@"text"] isKindOfClass:NSString.class] ? found[@"text"] : nil;
		NSString *preview = text.length ? text : sciItemTypeLabel([found[@"item_type"] isKindOfClass:NSString.class] ? found[@"item_type"] : nil);

		id uid = found[@"user_id"];
		NSString *authorPk = [uid isKindOfClass:NSString.class] ? uid : ([uid isKindOfClass:NSNumber.class] ? [uid stringValue] : nil);
		NSString *authorU = sciRosterUsername(threadId, authorPk);
		if (!authorU.length && authorPk.length) sciResolveSender(authorPk, &authorU, NULL, NULL);

		[SCIDeletedMessagesStorage updateMessageWithId:recordId ownerPK:owner mutator:^BOOL(SCIDeletedMessage *m) {
			BOOL ch = NO;
			if (preview.length && ![preview isEqualToString:m.text]) { m.text = preview; m.previewText = preview; ch = YES; }
			if (authorU.length && ![authorU isEqualToString:m.reactionTargetUsername]) { m.reactionTargetUsername = authorU; ch = YES; }
			return ch;
		}];
	}];
}

#pragma mark - Edit state

static NSMutableDictionary<NSString *, NSMutableDictionary *> *sciEditStates(void) {
	static NSMutableDictionary *d;
	static dispatch_once_t once;
	dispatch_once(&once, ^{ d = [NSMutableDictionary new]; });
	return d;
}

static NSMutableDictionary *sciEditState(NSString *sid, BOOL create) {
	if (!sid.length) return nil;

	@synchronized (sciLock()) {
		NSMutableDictionary *state = sciEditStates()[sid];
		if (state || !create) return state;

		if (sciEditStates().count >= 4000) {
			NSArray *keys = sciEditStates().allKeys;
			NSUInteger drop = MIN((NSUInteger)400, keys.count);
			for (NSUInteger i = 0; i < drop; i++) [sciEditStates() removeObjectForKey:keys[i]];
		}

		state = [NSMutableDictionary dictionary];
		sciEditStates()[sid] = state;
		return state;
	}
}

#pragma mark - Public hooks

void sciDMCaptureNoteInsert(id message) {
	if (!sciCaptureEnabled() || !message) return;

	@try {
		NSString *sid = sciSidFromMessage(message);
		if (!sid.length) return;

		@synchronized (sciLock()) {
			[sciMessageRefs() setObject:message forKey:sid];
		}

		id content = sciIvar(message, "_content") ?: sciIvar(message, "_messageContent") ?: sciIvar(message, "_payload");
		NSString *txt = sciStrIvar(content, "_text_string");
		if (!txt.length) return;

		NSMutableDictionary *st = sciEditState(sid, YES);
		if (!st[@"original"]) st[@"original"] = txt.copy;
	} @catch (__unused id e) {}
}

void sciDMCaptureNoteEdit(NSString *messageId, id contentMutation, NSString *ownerPk, NSString *threadId) {
	if (!sciCaptureEnabled() || !messageId.length || !contentMutation) return;

	NSString *newText = sciStrIvar(contentMutation, "_editText_newContent");
	if (!newText.length) return;

	long long editCount = 0;
	@try {
		Ivar iv = class_getInstanceVariable([contentMutation class], "_editText_editCount");
		if (iv) editCount = *(long long *)((char *)(__bridge void *)contentMutation + ivar_getOffset(iv));
	} @catch (__unused id e) {}

	NSDate *editAt = NSDate.date;
	id hist = sciIvar(contentMutation, "_editText_editHistory");
	if ([hist isKindOfClass:NSArray.class] && [(NSArray *)hist count]) {
		id ts = sciKVC([(NSArray *)hist lastObject], @"timestamp");
		if ([ts isKindOfClass:NSDate.class]) editAt = ts;
	}

	@synchronized (sciLock()) {
		NSMutableDictionary *st = sciEditState(messageId, YES);
		NSMutableArray *edits = st[@"edits"];

		if (![edits isKindOfClass:NSMutableArray.class]) {
			edits = [NSMutableArray array];
			st[@"edits"] = edits;
		}

		BOOL dup = NO;
		for (NSDictionary *e in edits) {
			if ([e[@"count"] integerValue] == (NSInteger)editCount && [e[@"text"] isEqual:newText]) {
				dup = YES;
				break;
			}
		}

		if (!dup) {
			[edits addObject:@{@"text": newText.copy,
								@"at": @(editAt.timeIntervalSince1970),
								@"count": @(editCount)}];
		}

		st[@"latest"] = newText.copy;
		st[@"editCount"] = @(editCount);
	}
}

void sciDMCaptureNoteReaction(NSString *messageId, id contentMutation, NSString *ownerPk, NSString *threadId) {
	if (!sciCaptureEnabled() || !messageId.length || !contentMutation) return;
	if (![SCIUtils getBoolPref:@"deleted_messages_log_reactions"]) return;

	// Only removals — adds arrive via _react_reactions and aren't deleted content.
	id rx = sciIvar(contentMutation, "_unreact_reaction");
	if (!rx) return;

	NSString *emoji = sciStrIvar(rx, "_userBasedReaction_emojiUnicode");
	NSString *reactorPk = sciStrIvar(contentMutation, "_unreact_userPk") ?: sciStrIvar(rx, "_userBasedReaction_userId");
	if (!reactorPk.length) return;

	NSString *owner = ownerPk.length ? ownerPk.copy : @"";
	if ([reactorPk isEqualToString:owner]) return;  // skip own

	NSDate *reactedAt = nil;
	id ts = sciIvar(rx, "_userBasedReaction_serverTimestamp");
	if ([ts isKindOfClass:NSDate.class]) reactedAt = ts;

	NSString *thread = threadId.length ? threadId.copy : nil;
	NSString *msgId = messageId.copy;
	NSString *emojiC = emoji.copy;
	NSString *reactorC = reactorPk.copy;

	id targetMsg = nil;
	@synchronized (sciLock()) { targetMsg = [sciMessageRefs() objectForKey:msgId]; }

	dispatch_async(sciCaptureQueue(), ^{
		NSString *preview = nil, *targetAuthorPk = nil;
		if (targetMsg) {
			NSDictionary *snap = sciBuildSnapshot(targetMsg, owner);
			SCIDeletedMessageKind tkind = (SCIDeletedMessageKind)[snap[@"kind"] integerValue];
			preview = snap[@"text"];
			if (!preview.length && tkind != SCIDeletedMessageKindUnknown) preview = SCIDeletedMessageKindLocalizedName(tkind);
			targetAuthorPk = snap[@"sender_pk"];
		}

		NSString *targetAuthorU = nil;
		if (targetAuthorPk.length) {
			targetAuthorU = sciRosterUsername(thread, targetAuthorPk);
			if (!targetAuthorU.length) sciResolveSender(targetAuthorPk, &targetAuthorU, NULL, NULL);
		}

		NSString *u = nil, *fn = nil, *pic = nil;
		sciResolveSender(reactorC, &u, &fn, &pic);
		if (!u.length) u = sciRosterUsername(thread, reactorC);

		NSDate *now = NSDate.date;
		SCIDeletedMessage *m = [SCIDeletedMessage new];
		m.messageId = [NSString stringWithFormat:@"%@:rx:%@:%@", msgId, reactorC, emojiC ?: @""];
		m.threadId = thread;
		m.senderPk = reactorC;
		m.senderUsername = u;
		m.senderFullName = fn;
		m.senderProfilePicURL = pic;
		m.kind = SCIDeletedMessageKindReactionRemoved;
		m.reactionEmoji = emojiC;
		m.targetMessageId = msgId;
		m.reactionTargetUsername = targetAuthorU;
		m.text = preview;
		m.previewText = preview;
		m.sentAt = reactedAt;
		m.capturedAt = now;
		m.deletedAt = now;

		NSDictionary *tinfo = sciCachedThreadInfo(thread);
		if (tinfo) {
			if ([tinfo[@"is_group"] isKindOfClass:NSNumber.class]) m.isGroup = [tinfo[@"is_group"] boolValue];
			if ([tinfo[@"thread_title"] isKindOfClass:NSString.class]) m.threadTitle = tinfo[@"thread_title"];
			if ([tinfo[@"thread_avatar_url"] isKindOfClass:NSString.class]) m.threadAvatarURL = tinfo[@"thread_avatar_url"];
		}

		if ([SCIDeletedMessagesStorage isExcludedThreadId:m.threadId senderPk:m.senderPk ownerPK:owner]) return;

		[SCIDeletedMessagesStorage saveMessage:m forOwnerPK:owner];
		sciResolveThreadInfo(thread, owner, NO);

		// Not in memory — resolve over REST.
		if (!preview.length) sciResolveReactionTarget(m.messageId, thread, msgId, owner);

		// Toast: short title so it doesn't truncate, sentence in the subtitle.
		NSString *who = u.length ? [@"@" stringByAppendingString:u] : SCILocalized(@"Someone");
		NSString *e = emojiC.length ? emojiC : @"";
		NSString *snippet = preview.length ? (preview.length > 40 ? [[preview substringToIndex:40] stringByAppendingString:@"…"] : preview) : nil;
		NSString *sub = snippet.length
			? [NSString stringWithFormat:SCILocalized(@"removed %@ on: %@"), e, snippet]
			: [NSString stringWithFormat:SCILocalized(@"removed reaction %@"), e];
		dispatch_async(dispatch_get_main_queue(), ^{
			SCINotify(SCI_NOTIF_REACTION_REMOVED, who, sub, @"heart.slash.fill", SCINotificationToneError);
		});
	});
}

static NSString *sciKeySid(id key) {
	if (!key) return nil;

	@try {
		NSString *sid = sciStrIvar(key, "_serverId") ?: sciStrIvar(key, "_messageServerId");
		return sid.length ? sid : nil;
	} @catch (__unused id e) {
		return nil;
	}
}

// Snapshot a live message into a record + acquire media. skipIfExists: bail if already stored.
static void sciSaveSnapshotForMessage(id msgObj, NSString *sid, NSString *owner, NSString *thread, BOOL skipIfExists) {
	if (!msgObj || !sid.length) return;

	// Isolate per message: a single bad message must never abort the rest of a launch batch.
	@try {
	if (skipIfExists) {
		__block BOOL exists = NO;
		[SCIDeletedMessagesStorage updateMessageWithId:sid ownerPK:owner mutator:^BOOL(SCIDeletedMessage *m) {
			exists = YES;
			return NO;
		}];
		if (exists) return;
	}

	NSDictionary *snap = sciBuildSnapshot(msgObj, owner);
	if (!snap) return;

	NSString *senderPk = snap[@"sender_pk"];
	if (senderPk.length && [senderPk isEqualToString:owner]) return;

	SCIDeletedMessageKind kind = (SCIDeletedMessageKind)[snap[@"kind"] integerValue];
	NSString *txt = snap[@"text"];
	NSString *media = snap[@"media_url"];
	NSString *thumb = snap[@"thumb_url"];
	NSArray *cands = [snap[@"media_candidates"] isKindOfClass:NSArray.class] ? snap[@"media_candidates"] : nil;

	if ((kind == SCIDeletedMessageKindUnknown || kind == SCIDeletedMessageKindOther) &&
		!txt.length && !media.length && !thumb.length && !cands.count) {
		return;
	}

	NSDate *now = NSDate.date;
	SCIDeletedMessage *m = [SCIDeletedMessage new];
	m.messageId = sid;
	m.threadId = snap[@"thread_id"] ?: thread;

	NSDictionary *tinfo = sciCachedThreadInfo(m.threadId);
	if (tinfo) {
		if ([tinfo[@"is_group"] isKindOfClass:NSNumber.class]) m.isGroup = [tinfo[@"is_group"] boolValue];
		if ([tinfo[@"thread_title"] isKindOfClass:NSString.class]) m.threadTitle = tinfo[@"thread_title"];
		if ([tinfo[@"thread_avatar_url"] isKindOfClass:NSString.class]) m.threadAvatarURL = tinfo[@"thread_avatar_url"];
	}
	m.senderPk = senderPk ?: @"";
	m.senderUsername = snap[@"sender_username"];
	m.senderFullName = snap[@"sender_full_name"];
	m.senderProfilePicURL = snap[@"sender_profile_pic_url"];
	m.sentAt = snap[@"sent_at"];
	m.capturedAt = now;
	m.deletedAt = now;
	m.kind = kind;
	m.text = txt;
	m.previewText = txt;
	m.mediaURL = media;
	m.thumbnailURL = thumb;
	m.durationSeconds = [snap[@"duration"] doubleValue];
	m.replyToMessageId = snap[@"reply_to_id"];
	m.isEphemeral = [snap[@"ephemeral"] boolValue];
	m.mediaPk = snap[@"media_pk"];

	id wf = snap[@"waveform"];
	if ([wf isKindOfClass:NSArray.class]) m.waveform = wf;

	@synchronized (sciLock()) {
		NSMutableDictionary *st = sciEditStates()[sid];
		NSString *orig = [st[@"original"] isKindOfClass:NSString.class] ? st[@"original"] : nil;
		m.originalText = orig.length ? orig : m.text;

		NSArray *edits = st[@"edits"];
		if ([edits isKindOfClass:NSArray.class] && edits.count) {
			m.edits = edits.copy;
			m.editCount = [st[@"editCount"] unsignedIntegerValue];
			NSString *latest = st[@"latest"];
			if ([latest isKindOfClass:NSString.class] && latest.length) { m.text = latest; m.previewText = latest; }
		}
		[sciEditStates() removeObjectForKey:sid];
	}

	NSString *audioURL = snap[@"audio_url"];
	BOOL deeplinkOnly = m.kind == SCIDeletedMessageKindShare || m.kind == SCIDeletedMessageKindLink;
	BOOL carriesBlob = !deeplinkOnly &&
		(m.kind == SCIDeletedMessageKindPhoto || m.kind == SCIDeletedMessageKindVideo ||
		 m.kind == SCIDeletedMessageKindVoice || m.kind == SCIDeletedMessageKindGif ||
		 m.kind == SCIDeletedMessageKindSticker);

	if (carriesBlob) {
		BOOL fetchable = cands.count || m.mediaURL.length || m.mediaPk.length;
		m.mediaStatus = fetchable ? SCIDeletedMessageMediaStatusPending : SCIDeletedMessageMediaStatusUnavailable;
	}
	if (cands.count) m.mediaCandidates = cands;

	if ([SCIDeletedMessagesStorage isExcludedThreadId:m.threadId senderPk:m.senderPk ownerPK:owner]) return;

	[SCIDeletedMessagesStorage saveMessage:m forOwnerPK:owner];

	if (carriesBlob) {
		if (cands.count) sciAcquireMediaCandidates(sid, owner, m.kind, cands, audioURL, m.mediaPk);
		else sciAcquireMedia(sid, owner, m.kind, m.mediaURL, audioURL, m.mediaPk, YES);
	}
	if (m.thumbnailURL.length) sciDownloadMedia(m.thumbnailURL, sid, owner, YES, nil);
	} @catch (__unused id e) {}
}

void sciDMCaptureNotePreservedMessage(id message, NSString *ownerPk, NSString *threadId) {
	if (!sciCaptureEnabled() || !message) return;
	NSString *sid = sciSidFromMessage(message);
	if (!sid.length) return;

	NSString *owner = ownerPk.length ? ownerPk.copy : @"";
	NSString *thread = threadId.length ? threadId.copy : nil;
	id msg = message;
	if (thread.length) sciResolveThreadInfo(thread, owner, NO);
	dispatch_async(sciCaptureQueue(), ^{
		sciSaveSnapshotForMessage(msg, sid, owner, thread, YES);
	});
}

void sciDMCaptureNoteRemoveKeys(NSArray *keys, id applicator, NSString *ownerPk, NSString *threadId) {
	if (!sciCaptureEnabled() || !keys.count) return;

	NSString *owner = ownerPk.length ? ownerPk.copy : @"";
	NSString *thread = threadId.length ? threadId.copy : nil;
	NSMutableDictionary<NSString *, id> *refs = [NSMutableDictionary dictionary];

	@synchronized (sciLock()) {
		for (id key in keys) {
			NSString *sid = sciKeySid(key);
			if (!sid.length) continue;

			id m = [sciMessageRefs() objectForKey:sid];
			if (m) {
				refs[sid] = m;
				[sciMessageRefs() removeObjectForKey:sid];
			}
		}
	}

	for (id key in keys) {
		NSString *sid = sciKeySid(key);
		if (!sid.length || refs[sid]) continue;

		id m = sciFallbackLookupMessage(applicator, sid, thread);
		if (m) refs[sid] = m;
	}

	if (!refs.count) return;

	sciResolveThreadInfo(thread, owner, NO);

	dispatch_async(sciCaptureQueue(), ^{
		for (NSString *sid in refs) {
			sciSaveSnapshotForMessage(refs[sid], sid, owner, thread, NO);
		}
	});
}
