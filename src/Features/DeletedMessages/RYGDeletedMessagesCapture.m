#import "RYGDeletedMessagesCapture.h"
#import "RYGDeletedMessagesModels.h"
#import "RYGDeletedMessagesStorage.h"
#import "../Feed/RYGHomeShortcutBadges.h"
#import "../StoriesAndMessages/RYGDirectUserResolver.h"
#import "../StoriesAndMessages/RYGDirectThreadInfo.h"
#import "../../Utils.h"
#import "../../RYGDashParser.h"
#import "../../RYGFFmpeg.h"
#import "../../RYGTempFiles.h"
#import "../../Networking/RYGInstagramAPI.h"
#import "../../UI/Notification/RYGNotificationActions.h"
#import "../../Background/RYGBackgroundActivity.h"
#import <objc/runtime.h>
#import <objc/message.h>

#pragma mark - Shared state

static NSMapTable *rygMessageRefs(void) {
	static NSMapTable *t;
	static dispatch_once_t once;
	dispatch_once(&once, ^{
		t = [NSMapTable mapTableWithKeyOptions:NSPointerFunctionsStrongMemory | NSPointerFunctionsObjectPersonality
								  valueOptions:NSPointerFunctionsWeakMemory   | NSPointerFunctionsObjectPersonality];
	});
	return t;
}

static NSObject *rygLock(void) {
	static NSObject *o;
	static dispatch_once_t once;
	dispatch_once(&once, ^{ o = [NSObject new]; });
	return o;
}

static dispatch_queue_t rygCaptureQueue(void) {
	static dispatch_queue_t q;
	static dispatch_once_t once;
	dispatch_once(&once, ^{
		q = dispatch_queue_create("com.ryukgram.deletedmessages.capture", DISPATCH_QUEUE_SERIAL);
	});
	return q;
}

static dispatch_queue_t rygDownloadQueue(void) {
	static dispatch_queue_t q;
	static dispatch_once_t once;
	dispatch_once(&once, ^{
		q = dispatch_queue_create("com.ryukgram.deletedmessages.download", DISPATCH_QUEUE_CONCURRENT);
	});
	return q;
}

static NSURLSession *rygSession(void) {
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

static BOOL rygCaptureEnabled(void) {
	return [RYGUtils getBoolPref:@"deleted_messages_log_enabled"];
}

static NSDictionary *rygCachedThreadInfo(NSString *threadId);
static NSDictionary *rygRosterEntry(NSString *threadId, NSString *pk);
static NSString *rygRosterUsername(NSString *threadId, NSString *pk);
static void rygResolveThreadInfo(NSString *threadId, NSString *owner, BOOL force);
static NSArray<NSDictionary *> *rygVisualPhotoCandidates(id photo, NSString **outDisplay);
static NSArray<NSDictionary *> *rygVisualVideoCandidates(id video, NSString **outAudio, NSString **outDisplay);
static void rygAcquireMediaCandidates(NSString *messageId, NSString *ownerPk, RYGDeletedMessageKind kind,
									  NSArray<NSDictionary *> *cands, NSString *audioURL, NSString *mediaPk);

#pragma mark - Runtime helpers

static BOOL rygSystemObject(id obj) {
	if (!obj) return YES;
	if ([obj isKindOfClass:NSString.class] || [obj isKindOfClass:NSNumber.class] ||
		[obj isKindOfClass:NSDate.class] || [obj isKindOfClass:NSURL.class]) return YES;

	NSString *cn = NSStringFromClass([obj class]);
	return [cn hasPrefix:@"NS"] || [cn hasPrefix:@"_NS"] || [cn hasPrefix:@"OS"] || [cn hasPrefix:@"__"];
}

static id rygIvar(id obj, const char *name) {
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

static NSString *rygStrIvar(id obj, const char *name) {
	id v = rygIvar(obj, name);
	return [v isKindOfClass:NSString.class] ? v : nil;
}

static id rygKVC(id obj, NSString *key) {
	if (!obj || !key.length) return nil;
	@try {
		id v = [obj valueForKey:key];
		return (v && v != NSNull.null) ? v : nil;
	} @catch (__unused id e) {
		return nil;
	}
}

static BOOL rygBadDesc(NSString *s) {
	return s.length && [s hasPrefix:@"<"] && [s containsString:@": 0x"] && [s hasSuffix:@">"];
}

static NSString *rygStringValue(id v) {
	if ([v isKindOfClass:NSAttributedString.class]) v = [(NSAttributedString *)v string];
	if ([v isKindOfClass:NSString.class] && [(NSString *)v length] && !rygBadDesc(v)) return v;
	if ([v isKindOfClass:NSNumber.class]) return [(NSNumber *)v stringValue];
	return nil;
}

static NSString *rygURLValue(id v) {
	if ([v isKindOfClass:NSURL.class]) return [(NSURL *)v absoluteString];
	if ([v isKindOfClass:NSString.class] && [(NSString *)v length]) return v;
	return nil;
}

static NSString *rygPickString(id obj, NSArray<NSString *> *keys) {
	for (NSString *k in keys) {
		NSString *s = rygStringValue(rygKVC(obj, k));
		if (s.length) return s;
	}
	return nil;
}

static NSString *rygPickURL(id obj, NSArray<NSString *> *keys) {
	for (NSString *k in keys) {
		NSString *s = rygURLValue(rygKVC(obj, k));
		if (s.length) return s;
	}
	return nil;
}

static double rygDouble(id obj, NSString *selName) {
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

static BOOL rygURLish(NSString *s) {
	return [s hasPrefix:@"http://"] || [s hasPrefix:@"https://"] ||
		   [s hasPrefix:@"instagram://"] || [s hasPrefix:@"fb://"] ||
		   [s hasPrefix:@"fbthreads://"] || [s hasPrefix:@"intent://"];
}

static BOOL rygAudioish(NSString *s) {
	NSString *x = s.lowercaseString ?: @"";
	return [x containsString:@"audio"] || [x containsString:@"voice"] ||
		   [x containsString:@"music"] || [x containsString:@".m4a"] ||
		   [x containsString:@".mp3"] || [x containsString:@".aac"] ||
		   [x containsString:@".opus"] || [x containsString:@".oga"];
}

static void rygScoreURL(NSString *s, NSString *name, NSString **media, int *ms, NSString **thumb, int *ts) {
	if (!rygURLish(s)) return;

	NSString *n = name.lowercaseString ?: @"";
	BOOL th = [n containsString:@"thumb"] || [n containsString:@"preview"] ||
			  [n containsString:@"poster"] || [n containsString:@"cover"] ||
			  [n containsString:@"image"];

	BOOL audio = [n containsString:@"audio"] || [n containsString:@"voice"] || rygAudioish(s);
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

static void rygScanURLs(id obj, int depth, NSString **media, int *ms, NSString **thumb, int *ts, NSString *name) {
	if (!obj || depth < 0) return;

	if ([obj isKindOfClass:NSString.class]) {
		rygScoreURL(obj, name, media, ms, thumb, ts);
		return;
	}

	if ([obj isKindOfClass:NSURL.class]) {
		rygScoreURL([(NSURL *)obj absoluteString], name, media, ms, thumb, ts);
		return;
	}

	if ([obj isKindOfClass:NSArray.class]) {
		for (id e in (NSArray *)obj) rygScanURLs(e, depth - 1, media, ms, thumb, ts, name);
		return;
	}

	if ([obj isKindOfClass:NSDictionary.class]) {
		for (id k in (NSDictionary *)obj) {
			NSString *kn = [k isKindOfClass:NSString.class] ? k : name;
			rygScanURLs(((NSDictionary *)obj)[k], depth - 1, media, ms, thumb, ts, kn);
		}
		return;
	}

	if (rygSystemObject(obj)) return;

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
			rygScanURLs(v, depth - 1, media, ms, thumb, ts, ivn ? @(ivn) : name);
		}

		if (list) free(list);
	}
}

static void rygCollectTokens(id obj, int depth, NSMutableSet *seen, NSMutableSet<NSString *> *out) {
	if (!obj || depth < 0) return;

	if ([obj isKindOfClass:NSArray.class]) {
		for (id e in (NSArray *)obj) rygCollectTokens(e, depth - 1, seen, out);
		return;
	}

	if ([obj isKindOfClass:NSDictionary.class]) {
		for (id k in (NSDictionary *)obj) {
			if ([k isKindOfClass:NSString.class]) [out addObject:[(NSString *)k lowercaseString]];
			rygCollectTokens(((NSDictionary *)obj)[k], depth - 1, seen, out);
		}
		return;
	}

	if (rygSystemObject(obj)) return;

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
			rygCollectTokens(v, depth - 1, seen, out);
		}

		if (list) free(list);
	}
}

static BOOL rygTokensContain(NSSet<NSString *> *tokens, NSArray<NSString *> *needles) {
	for (NSString *t in tokens) {
		for (NSString *n in needles) {
			if ([t containsString:n]) return YES;
		}
	}
	return NO;
}

// Real media PKs are long digit strings; reject short numbers (counts/indices).
static NSString *rygNumericMediaId(id v) {
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

static NSString *rygMediaPkFrom(id obj) {
	if (!obj) return nil;
	for (NSString *n in @[@"_mediaId", @"_pk", @"_mediaPk", @"_postId", @"_id", @"_instagramMediaId"]) {
		NSString *s = rygNumericMediaId(rygIvar(obj, n.UTF8String));
		if (s.length) return s;
	}
	return nil;
}

// First long digit-string ivar — pulls a thread id out of an opaque identifier wrapper.
static NSString *rygScanLongDigitString(id obj) {
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
			NSString *s = rygNumericMediaId(v);
			if (s.length) { found = s; break; }
		}
		free(ivars);
		if (found) return found;
	}
	return nil;
}

#pragma mark - Metadata extraction

static NSString *rygSidFromMessage(id m) {
	id meta = rygIvar(m, "_metadata");
	NSString *sid = rygStrIvar(meta, "_serverId") ?: rygStrIvar(meta, "_messageServerId");

	if (!sid.length) {
		id key = rygIvar(meta, "_key");
		sid = rygStrIvar(key, "_serverId") ?: rygStrIvar(key, "_messageServerId");
	}

	return sid;
}

static NSString *rygSenderPkFromMessage(id m) {
	return rygStrIvar(rygIvar(m, "_metadata"), "_senderPk");
}

static NSDate *rygDateFromTimestampValue(id v) {
	if ([v isKindOfClass:NSDate.class]) return v;
	if (![v isKindOfClass:NSNumber.class]) return nil;

	double d = [(NSNumber *)v doubleValue];
	if (d > 1.0e12) d /= 1.0e9;
	else if (d > 1.0e10) d /= 1.0e3;
	return d > 0 ? [NSDate dateWithTimeIntervalSince1970:d] : nil;
}

// A restored IGDirectPublishedMessage exposes these as properties, not ivars.
static NSDate *rygSentAtFromMessage(id m) {
	id meta = rygIvar(m, "_metadata") ?: rygKVC(m, @"metadata");
	if (!meta) return nil;

	for (NSString *k in @[@"_serverTimestamp", @"_clientTimestamp", @"_timestamp"]) {
		NSDate *date = rygDateFromTimestampValue(rygIvar(meta, k.UTF8String));
		if (date) return date;
	}

	for (NSString *k in @[@"serverTimestamp", @"sentDate", @"timestamp"]) {
		NSDate *date = rygDateFromTimestampValue(rygKVC(meta, k));
		if (date) return date;
	}

	return nil;
}

static void rygResolveSender(NSString *pk, NSString **outUser, NSString **outName, NSString **outPic) {
	if (!pk.length) return;

	NSString *u = rygDirectUserResolverUsernameForPK(pk);
	NSString *p = rygDirectUserResolverProfilePicURLStringForPK(pk);
	NSString *fn = nil;

	id user = rygDirectUserResolverUserForPK(pk);
	NSDictionary *fc = nil;

	if (user) {
		id raw = rygIvar(user, "_fieldCache");
		if ([raw isKindOfClass:NSDictionary.class]) fc = raw;

		NSString *(^fcStr)(NSString *) = ^NSString *(NSString *k) {
			id v = fc[k];
			return [v isKindOfClass:NSString.class] && [(NSString *)v length] ? v : nil;
		};

		if (!u.length) u = fcStr(@"username");
		if (!p.length) p = fcStr(@"profile_pic_url");
		fn = fcStr(@"full_name") ?: rygStringValue(rygKVC(user, @"fullName"));
	}

	if (outUser) *outUser = u;
	if (outName) *outName = fn;
	if (outPic) *outPic = p;
}

static NSString *rygReplyIdFromMessage(id message) {
	id meta = rygIvar(message, "_metadata");

	for (NSString *k in @[@"_replyToMessageId", @"_replyMessageId", @"_quotedMessageId", @"_repliedToMessageId", @"_parentMessageId"]) {
		NSString *v = rygStrIvar(meta, k.UTF8String) ?: rygStrIvar(message, k.UTF8String);
		if (v.length) return v;
	}

	for (NSString *k in @[@"replyToMessageId", @"replyMessageId", @"quotedMessageId", @"repliedToMessageId", @"reply_message_id"]) {
		NSString *v = rygStringValue(rygKVC(message, k));
		if (v.length) return v;
	}

	return nil;
}

#pragma mark - Share / XMA / voice

static NSString *rygDeepTitle(id obj) {
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

		if (rygSystemObject(cur)) continue;

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
						NSString *s = rygStringValue(v);
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

static NSArray *rygXMATargets(id xma) {
	NSMutableArray *a = [NSMutableArray array];
	if (xma) [a addObject:xma];

	id items = rygKVC(xma, @"xmaItems");
	if ([items isKindOfClass:NSArray.class]) {
		for (id it in (NSArray *)items) {
			if (it) [a addObject:it];
			id meta = rygKVC(it, @"metadata");
			id preview = rygKVC(it, @"preview");
			if (meta) [a addObject:meta];
			if (preview) [a addObject:preview];
		}
	}

	id meta = rygKVC(xma, @"metadata");
	if (meta) [a addObject:meta];

	return a;
}

static BOOL rygXMAIsAudio(id xma, NSArray *targets, NSString *contentType) {
	NSString *ct = contentType.lowercaseString ?: @"";
	if ([ct containsString:@"audio"] || [ct containsString:@"music"] || [ct containsString:@"reels_audio"]) return YES;

	NSArray *audioKeys = @[@"playableAudioURL", @"accessoryPlayableURL", @"audioURL", @"audioUrl", @"musicAssetURL", @"voiceURL", @"voiceUrl"];
	NSArray *targetKeys = @[@"targetURL", @"webURL", @"shareURL", @"deepLink", @"url", @"mediaURL", @"playableURL", @"fullSizeURL"];

	for (id obj in targets) {
		if (rygPickURL(obj, audioKeys).length) return YES;

		NSString *u = rygPickURL(obj, targetKeys).lowercaseString;
		if ([u containsString:@"reels_audio_page"] || [u containsString:@"audio_page"] ||
			[u containsString:@"/audio/"] || [u containsString:@"music_canonical_id"] ||
			[u containsString:@"original_audio"]) return YES;
	}

	NSString *m = nil, *t = nil;
	int ms = 0, ts = 0;
	rygScanURLs(xma, 4, &m, &ms, &t, &ts, @"xma");
	return rygAudioish(m);
}

static void rygExtractXMA(id xma, RYGDeletedMessageKind *kind, NSString **text, NSString **media, int *ms, NSString **thumb, int *ts) {
	if (!xma || !kind) return;

	NSString *ct = rygStringValue(rygKVC(xma, @"contentType")).lowercaseString;
	NSArray *targets = rygXMATargets(xma);
	BOOL audio = rygXMAIsAudio(xma, targets, ct);

	if (audio) *kind = RYGDeletedMessageKindAudioShare;
	else if ([ct containsString:@"link"]) *kind = RYGDeletedMessageKindLink;
	else *kind = RYGDeletedMessageKindShare;

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
		NSString *s = rygPickString(obj, titles);
		if (s.length && ![parts containsObject:s]) [parts addObject:s];
		if (parts.count >= 3) break;
	}
	if (!(*text).length && parts.count) *text = [parts componentsJoinedByString:@"\n"];

	for (id obj in targets) {
		if (!(*media).length) {
			NSString *u = rygPickURL(obj, mediaKeys);
			if (u.length) { *media = u; *ms = audio ? 120 : 70; }
		}
		if (!(*thumb).length) {
			NSString *u = rygPickURL(obj, thumbKeys);
			if (u.length) { *thumb = u; *ts = 70; }
		}
		if ((*media).length && (*thumb).length) break;
	}

	rygScanURLs(xma, 5, media, ms, thumb, ts, audio ? @"playableAudioURL" : @"xma");

	if (*kind == RYGDeletedMessageKindLink && (*media).length) {
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

static void rygVoiceMeta(id media, double *dur, NSArray **wave) {
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

		if (rygSystemObject(cur)) continue;

		NSValue *box = [NSValue valueWithNonretainedObject:cur];
		if ([seen containsObject:box]) continue;
		[seen addObject:box];

		if (!*dur) {
			double d = rygDouble(cur, @"durationInSeconds");
			if (d <= 0) d = rygDouble(cur, @"duration");
			if (d <= 0) d = rygDouble(cur, @"audioDuration");
			if (d <= 0) d = rygDouble(cur, @"playbackDuration");

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
			id w = rygIvar(cur, "_averageVolume") ?: rygIvar(cur, "_waveformData") ?:
				   rygIvar(cur, "_waveform") ?: rygIvar(cur, "_amplitudes") ?:
				   rygIvar(cur, "_voiceReply_waveform") ?: rygIvar(cur, "_audio_waveform") ?:
				   rygKVC(cur, @"waveform") ?: rygKVC(cur, @"waveformData") ?: rygKVC(cur, @"averageVolume");
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

// Never prompt in the log; "always_ask" resolves to highest.
static RYGVideoQuality rygPreferredVideoQuality(void) {
	NSString *q = [RYGUtils getStringPref:@"default_video_quality"];
	if ([q isEqualToString:@"medium"]) return RYGVideoQualityMedium;
	if ([q isEqualToString:@"low"]) return RYGVideoQualityLowest;
	return RYGVideoQualityHighest;
}

// Widest-res photo candidates; the IGPhoto sits in one of a few slots.
static NSArray<NSDictionary *> *rygPhotoCandidatesFromMedia(id media, NSString **outDisplay) {
	if (outDisplay) *outDisplay = nil;
	if (!media) return @[];
	id photo = rygIvar(media, "_photo_photo")
		?: rygIvar(rygIvar(media, "_permanentMedia_permanentMedia"), "_photo_photo")
		?: rygIvar(rygIvar(media, "_visualMedia"), "_photo_photo")
		?: rygIvar(media, "_photo") ?: rygIvar(media, "_image");
	if (!photo) return @[];
	return rygVisualPhotoCandidates(photo, outDisplay);
}

static NSDictionary *rygBuildSnapshot(id message, NSString *ownerHint) {
	NSString *sid = rygSidFromMessage(message);
	if (!sid.length) return nil;

	NSMutableDictionary *snap = [NSMutableDictionary dictionary];
	snap[@"sid"] = sid;
	if (ownerHint.length) snap[@"owner_pk"] = ownerHint;

	NSString *threadId = rygStringValue(rygKVC(message, @"threadId"));
	id meta = rygIvar(message, "_metadata");
	if (!threadId.length) threadId = rygStrIvar(meta, "_threadId") ?: rygStrIvar(meta, "_threadID");
	if (threadId.length) snap[@"thread_id"] = threadId;

	NSString *senderPk = rygSenderPkFromMessage(message);
	if (senderPk.length) {
		NSString *u = nil, *fn = nil, *pic = nil;
		rygResolveSender(senderPk, &u, &fn, &pic);

		if ((!u.length || !fn.length || !pic.length) && threadId.length) {
			NSDictionary *r = rygRosterEntry(threadId, senderPk);
			if (!u.length && [r[@"username"] isKindOfClass:NSString.class]) u = r[@"username"];
			if (!fn.length && [r[@"full_name"] isKindOfClass:NSString.class]) fn = r[@"full_name"];
			if (!pic.length && [r[@"profile_pic_url"] isKindOfClass:NSString.class]) pic = r[@"profile_pic_url"];
		}

		snap[@"sender_pk"] = senderPk;
		if (u.length) snap[@"sender_username"] = u;
		if (fn.length) snap[@"sender_full_name"] = fn;
		if (pic.length) snap[@"sender_profile_pic_url"] = pic;
	}

	NSDate *sentAt = rygSentAtFromMessage(message);
	if (sentAt) snap[@"sent_at"] = sentAt;

	NSString *replyId = rygReplyIdFromMessage(message);
	if (replyId.length) snap[@"reply_to_id"] = replyId;

	id content = rygIvar(message, "_content") ?: rygIvar(message, "_messageContent") ?: rygIvar(message, "_payload") ?: rygKVC(message, @"content");
	if (!content) {
		snap[@"kind"] = @(RYGDeletedMessageKindUnknown);
		return snap;
	}

	if (rygIvar(content, "_threadActivity") ||
		rygIvar(content, "_messageTypeNotLocallyAvailable_placeholderTitle") ||
		rygIvar(content, "_messageTypeNotLocallyAvailable_placeholderMessage") ||
		rygIvar(content, "_expiredPlaceholder_messageContent")) return nil;

	RYGDeletedMessageKind kind = RYGDeletedMessageKindUnknown;
	NSString *text = nil, *mediaURL = nil, *thumbURL = nil;
	int mediaScore = 0, thumbScore = 0;

	NSString *txt = rygStrIvar(content, "_text_string");
	if (txt.length) {
		kind = RYGDeletedMessageKindText;
		text = txt;
	}

	id media = rygIvar(content, "_media");
	if (media) {
		NSMutableSet *seen = [NSMutableSet set];
		NSMutableSet *tokens = [NSMutableSet set];
		rygCollectTokens(media, 5, seen, tokens);

		NSString *mpk = rygMediaPkFrom(media);
		if (mpk.length) snap[@"media_pk"] = mpk;

		// View-once media: photo/video lives at media._visualMedia._media._photo_photo / _video_video.
		BOOL visualHandled = NO;
		id vinfo = rygIvar(media, "_visualMedia");
		id vmedia = rygIvar(vinfo, "_media");
		if (vmedia) {
			snap[@"ephemeral"] = @YES;
			NSString *vpk = rygStrIvar(vinfo, "_mediaId");
			if (vpk.length) snap[@"media_pk"] = vpk;

			id vvideo = rygIvar(vmedia, "_video_video");
			id vphoto = rygIvar(vmedia, "_photo_photo");
			NSArray *cands = nil;
			if (vvideo) {
				kind = RYGDeletedMessageKindVideo;
				NSString *disp = nil, *a = nil;
				cands = rygVisualVideoCandidates(vvideo, &a, &disp);
				if (disp.length) { mediaURL = disp; mediaScore = 130; }
				if (a.length) snap[@"audio_url"] = a;
				NSString *thDisp = nil;
				rygVisualPhotoCandidates(rygIvar(vmedia, "_video_overlayPhoto"), &thDisp);
				if (thDisp.length) { thumbURL = thDisp; thumbScore = 130; }
			} else if (vphoto) {
				kind = RYGDeletedMessageKindPhoto;
				NSString *disp = nil;
				cands = rygVisualPhotoCandidates(vphoto, &disp);
				if (disp.length) { mediaURL = disp; mediaScore = 130; }
			}
			if (cands.count) snap[@"media_candidates"] = cands;
			visualHandled = (mediaURL.length > 0 || cands.count > 0);
		} else if (rygTokensContain(tokens, @[@"raven", @"visual", @"expiring", @"ephemeral", @"disappear"])) {
			snap[@"ephemeral"] = @YES;
		}

		if (!visualHandled) {
		if (rygTokensContain(tokens, @[@"voice", @"voicemedia", @"audio", @"audiomedia", @"audioclip"])) kind = RYGDeletedMessageKindVoice;
		else if (rygTokensContain(tokens, @[@"sticker"])) kind = RYGDeletedMessageKindSticker;
		else if (rygTokensContain(tokens, @[@"giphy", @"gif", @"animated"])) kind = RYGDeletedMessageKindGif;
		else if (rygTokensContain(tokens, @[@"video", @"dashmanifest", @"playableurl"])) kind = RYGDeletedMessageKindVideo;
		else kind = RYGDeletedMessageKindPhoto;

		if (kind == RYGDeletedMessageKindVoice) {
			double dur = 0;
			NSArray *wf = nil;
			rygVoiceMeta(media, &dur, &wf);

			if (dur > 0) snap[@"duration"] = @(dur);
			if (wf.count) snap[@"waveform"] = wf;

			NSString *u = rygPickURL(media, @[@"playableAudioURL", @"audioURL", @"voiceURL", @"playableURL", @"url", @"mediaURL"]);
			if (u.length) {
				mediaURL = u;
				mediaScore = 120;
			}
		}

		BOOL haveVideoSource = NO;
		if (kind == RYGDeletedMessageKindVideo) {
			id permanent = rygIvar(media, "_permanentMedia_permanentMedia");
			id visual = rygIvar(media, "_visualMedia");
			id video = nil, overlay = nil;

			if (permanent) {
				video = rygIvar(permanent, "_video_video") ?: rygIvar(permanent, "_videoMemo_memoVideo");
				overlay = rygIvar(permanent, "_video_overlayPhoto") ?: rygIvar(permanent, "_videoMemo_videoMemoPhoto");
			}

			if (!video && visual) {
				video = rygIvar(visual, "_video_video") ?: rygIvar(visual, "_video");
				overlay = overlay ?: rygIvar(visual, "_video_overlayPhoto") ?: rygIvar(visual, "_overlayPhoto");
			}
			if (!video) video = rygIvar(media, "_video_video");

			// DASH highest + _allVideoURLs + broadcast/playable; never the thumbnail.
			NSString *audioDash = nil, *primary = nil;
			NSArray<NSDictionary *> *vcands = video ? rygVisualVideoCandidates(video, &audioDash, &primary) : @[];
			if (primary.length) { mediaURL = primary; mediaScore = 100; }
			if (audioDash.length) snap[@"audio_url"] = audioDash;
			if (vcands.count) snap[@"media_candidates"] = vcands;
			haveVideoSource = vcands.count > 0;

			if (overlay) {
				NSString *m = nil, *t = nil;
				int ms = 0, ts = 0;
				rygScanURLs(overlay, 4, &m, &ms, &t, &ts, @"thumbnail");
				if ((t ?: m).length) {
					thumbURL = t ?: m;
					thumbScore = MAX(ts, ms);
				}
			}
		}

		if (kind == RYGDeletedMessageKindPhoto) {
			NSString *disp = nil;
			NSArray<NSDictionary *> *pc = rygPhotoCandidatesFromMedia(media, &disp);
			if (disp.length) { mediaURL = disp; mediaScore = 130; }
			if (pc.count) snap[@"media_candidates"] = pc;
		}

		// A video with no stream must not adopt its own thumbnail as the blob — route stray URLs to thumb.
		if (kind == RYGDeletedMessageKindVideo && !haveVideoSource) {
			NSString *dump = nil; int ds = 0;
			rygScanURLs(media, 5, &dump, &ds, &thumbURL, &thumbScore, @"thumbnail");
		} else {
			rygScanURLs(media, 5, &mediaURL, &mediaScore, &thumbURL, &thumbScore, kind == RYGDeletedMessageKindVoice ? @"playableAudioURL" : @"media");
		}
		}  // !visualHandled
	}

	id reshare = rygIvar(content, "_reshare_attachment");
	if (reshare && kind == RYGDeletedMessageKindUnknown) {
		kind = RYGDeletedMessageKindShare;
		rygScanURLs(reshare, 5, &mediaURL, &mediaScore, &thumbURL, &thumbScore, @"reshare");

		if (!snap[@"media_pk"]) {
			NSString *rpk = rygMediaPkFrom(reshare) ?: rygMediaPkFrom(rygIvar(reshare, "_media"));
			if (rpk.length) snap[@"media_pk"] = rpk;
		}

		text = rygStrIvar(content, "_reshare_comment") ?: rygDeepTitle(reshare);
		if (!text.length) text = rygPickString(reshare, @[@"caption", @"captionText", @"title", @"headline", @"summary", @"name", @"username", @"text"]);
		if (!mediaURL.length) mediaURL = rygPickURL(reshare, @[@"webURL", @"shareURL", @"deepLink", @"url", @"mediaURL", @"playableURL"]);
	}

	id link = rygIvar(content, "_link_linkContext");
	if (link && kind == RYGDeletedMessageKindUnknown) {
		kind = RYGDeletedMessageKindLink;

		mediaURL = rygURLValue(rygIvar(link, "_url"));
		thumbURL = rygURLValue(rygIvar(link, "_imageURL"));

		NSMutableArray *parts = [NSMutableArray array];
		for (NSString *s in @[rygStrIvar(content, "_link_commentText") ?: @"",
							   rygStrIvar(link, "_title") ?: @"",
							   rygStrIvar(link, "_summary") ?: @""]) {
			if (s.length) [parts addObject:s];
		}
		if (!parts.count && mediaURL.length) [parts addObject:mediaURL];
		if (parts.count) text = [parts componentsJoinedByString:@"\n"];
	}

	id xma = rygIvar(content, "_xma") ?: rygIvar(content, "_bloksXMA") ?: rygIvar(content, "_pollMessage") ?: rygIvar(content, "_progressiveImage");
	if (xma && (kind == RYGDeletedMessageKindUnknown || kind == RYGDeletedMessageKindShare || kind == RYGDeletedMessageKindLink)) {
		RYGDeletedMessageKind xk = RYGDeletedMessageKindUnknown;
		NSString *xt = text, *xm = nil, *xh = nil;
		int xms = 0, xts = 0;

		rygExtractXMA(xma, &xk, &xt, &xm, &xms, &xh, &xts);

		if (xk != RYGDeletedMessageKindUnknown) {
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

	if (kind == RYGDeletedMessageKindUnknown && text.length) kind = RYGDeletedMessageKindText;

	snap[@"kind"] = @(kind);
	if (text.length) snap[@"text"] = text;
	if (mediaURL.length) snap[@"media_url"] = mediaURL;
	if (thumbURL.length) snap[@"thumb_url"] = thumbURL;

	return snap;
}

#pragma mark - Download

static NSString *rygExt(NSURL *url, NSURLResponse *resp, BOOL thumb) {
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

static void rygDownloadTemp(NSURL *url, void (^done)(NSURL *file, NSError *err)) {
	if (!url) {
		done(nil, [NSError errorWithDomain:@"RYGDM" code:0 userInfo:nil]);
		return;
	}

	[[rygSession() dataTaskWithURL:url completionHandler:^(NSData *data, NSURLResponse *resp, NSError *err) {
		if (err || !data.length) {
			done(nil, err);
			return;
		}

		NSURL *file = [RYGTempFiles claimWithExt:rygExt(url, resp, NO) ttl:300 tag:@"dm"];
		if (![data writeToFile:file.path atomically:YES]) {
			[RYGTempFiles releaseURL:file];
			done(nil, [NSError errorWithDomain:@"RYGDM" code:1 userInfo:nil]);
			return;
		}

		done(file, nil);
	}] resume];
}

static void rygSetMediaStatus(NSString *messageId, NSString *ownerPk, RYGDeletedMessageMediaStatus status) {
	if (!messageId.length) return;
	[RYGDeletedMessagesStorage updateMessageWithId:messageId ownerPK:ownerPk mutator:^BOOL(RYGDeletedMessage *m) {
		if (m.mediaStatus == status) return NO;
		m.mediaStatus = status;
		return YES;
	}];
}

static NSString *rygBestCandidateURL(id imageVersions2) {
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
static void rygRefetchMediaByPK(NSString *pk, void (^completion)(NSString *videoURL, NSString *photoURL)) {
	if (!pk.length) { completion(nil, nil); return; }

	NSString *path = [NSString stringWithFormat:@"media/%@/info/", pk];
	[RYGInstagramAPI sendRequestWithMethod:@"GET" path:path body:nil completion:^(NSDictionary *resp, NSError *err) {
		NSArray *items = [resp[@"items"] isKindOfClass:NSArray.class] ? resp[@"items"] : nil;
		id item = items.firstObject;
		if (![item isKindOfClass:NSDictionary.class]) { completion(nil, nil); return; }

		NSString *video = nil, *photo = nil;

		NSArray *vv = ((NSDictionary *)item)[@"video_versions"];
		if ([vv isKindOfClass:NSArray.class] && vv.count && [vv[0] isKindOfClass:NSDictionary.class]) {
			id u = vv[0][@"url"];
			if ([u isKindOfClass:NSString.class]) video = u;
		}

		photo = rygBestCandidateURL(((NSDictionary *)item)[@"image_versions2"]);

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
				photo = rygBestCandidateURL(first[@"image_versions2"]);
			}
		}

		completion(video, photo);
	}];
}

// Reject error/HTML/JSON bodies masquerading as media (e.g. media_fallback's 400).
static BOOL rygLooksLikeMedia(NSURLResponse *resp, NSData *data) {
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

static BOOL rygWriteMediaBytes(NSData *data, NSURLResponse *resp, NSURL *url, NSString *messageId, NSString *ownerPk, BOOL thumb) {
	if (!data.length || !messageId.length) return NO;

	NSString *ext = rygExt(url, resp, thumb);
	NSString *rel = thumb
		? [NSString stringWithFormat:@"thumb_%@.%@", messageId, ext]
		: [RYGDeletedMessagesStorage reserveRelativeMediaPathForMessageId:messageId extension:ext ownerPK:ownerPk];

	NSString *abs = [RYGDeletedMessagesStorage absolutePathForRelativePath:rel ownerPK:ownerPk];
	if (!abs.length || ![data writeToFile:abs atomically:YES]) return NO;

	[RYGDeletedMessagesStorage updateMessageWithId:messageId ownerPK:ownerPk mutator:^BOOL(RYGDeletedMessage *m) {
		if (thumb) m.thumbnailPath = rel;
		else m.mediaPath = rel;
		return YES;
	}];
	return YES;
}

static void rygDownloadOne(NSString *urlString, BOOL auth, NSString *messageId, NSString *ownerPk, BOOL thumb, void (^completion)(BOOL ok)) {
	NSURL *url = urlString.length ? [NSURL URLWithString:urlString] : nil;
	if (!url || !messageId.length) { if (completion) completion(NO); return; }

	if (auth) {
		[RYGInstagramAPI downloadAuthorizedURL:url completion:^(NSData *data, NSURLResponse *resp, NSError *err) {
			BOOL ok = (!err && rygLooksLikeMedia(resp, data)) ? rygWriteMediaBytes(data, resp, url, messageId, ownerPk, thumb) : NO;
			if (completion) completion(ok);
		}];
		return;
	}

	dispatch_async(rygDownloadQueue(), ^{
		[[rygSession() dataTaskWithURL:url completionHandler:^(NSData *data, NSURLResponse *resp, NSError *err) {
			BOOL ok = (!err && rygLooksLikeMedia(resp, data)) ? rygWriteMediaBytes(data, resp, url, messageId, ownerPk, thumb) : NO;
			if (completion) completion(ok);
		}] resume];
	});
}

static void rygDownloadMedia(NSString *urlString, NSString *messageId, NSString *ownerPk, BOOL thumb, void (^completion)(BOOL ok)) {
	rygDownloadOne(urlString, NO, messageId, ownerPk, thumb, completion);
}

static void rygDownloadAndMuxVideo(NSString *videoURL, NSString *audioURL, NSString *messageId, NSString *ownerPk, void (^completion)(BOOL ok)) {
	NSURL *vURL = videoURL.length ? [NSURL URLWithString:videoURL] : nil;
	NSURL *aURL = audioURL.length ? [NSURL URLWithString:audioURL] : nil;
	if (!vURL || !aURL || !messageId.length || ![RYGFFmpeg isAvailable]) { if (completion) completion(NO); return; }

	dispatch_async(rygDownloadQueue(), ^{
		__block NSURL *vFile = nil, *aFile = nil;
		dispatch_semaphore_t sema = dispatch_semaphore_create(0);

		rygDownloadTemp(vURL, ^(NSURL *f, NSError *e) {
			if (!e) vFile = f;
			dispatch_semaphore_signal(sema);
		});
		dispatch_semaphore_wait(sema, DISPATCH_TIME_FOREVER);

		rygDownloadTemp(aURL, ^(NSURL *f, NSError *e) {
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

		[RYGFFmpeg muxVideoURL:vFile audioURL:aFile preset:nil progress:nil completion:^(NSURL *outURL, NSError *err) {
			[NSFileManager.defaultManager removeItemAtURL:vFile error:nil];
			[NSFileManager.defaultManager removeItemAtURL:aFile error:nil];

			if (err || !outURL) { if (completion) completion(NO); return; }

			NSString *rel = [RYGDeletedMessagesStorage reserveRelativeMediaPathForMessageId:messageId extension:@"mp4" ownerPK:ownerPk];
			NSString *abs = [RYGDeletedMessagesStorage absolutePathForRelativePath:rel ownerPK:ownerPk];
			if (!abs.length) { if (completion) completion(NO); return; }

			[NSFileManager.defaultManager removeItemAtPath:abs error:nil];
			if (![NSFileManager.defaultManager moveItemAtURL:outURL toURL:[NSURL fileURLWithPath:abs] error:nil]) { if (completion) completion(NO); return; }

			[RYGDeletedMessagesStorage updateMessageWithId:messageId ownerPK:ownerPk mutator:^BOOL(RYGDeletedMessage *m) {
				m.mediaPath = rel;
				return YES;
			}];
			if (completion) completion(YES);
		}];
	});
}

// Try each candidate; on total failure, refetch-by-PK. Sets the final status.
static void rygAcquireFromCandidates(NSString *messageId, NSString *ownerPk, RYGDeletedMessageKind kind,
									 NSArray<NSDictionary *> *cands, NSUInteger idx, NSString *mediaPk, BOOL hadAny) {
	if (idx < cands.count) {
		NSDictionary *c = cands[idx];
		rygDownloadOne(c[@"url"], [c[@"auth"] boolValue], messageId, ownerPk, NO, ^(BOOL ok) {
			if (ok) { rygSetMediaStatus(messageId, ownerPk, RYGDeletedMessageMediaStatusSaved); return; }
			rygAcquireFromCandidates(messageId, ownerPk, kind, cands, idx + 1, mediaPk, hadAny);
		});
		return;
	}

	if (mediaPk.length) {
		rygRefetchMediaByPK(mediaPk, ^(NSString *v, NSString *p) {
			NSString *fresh = (kind == RYGDeletedMessageKindVideo) ? (v ?: p) : (p ?: v);
			if (fresh.length) {
				rygAcquireFromCandidates(messageId, ownerPk, kind, @[@{@"url": fresh, @"auth": @NO}], 0, nil, YES);
			} else {
				rygSetMediaStatus(messageId, ownerPk, hadAny ? RYGDeletedMessageMediaStatusFailed : RYGDeletedMessageMediaStatusUnavailable);
			}
		});
		return;
	}

	rygSetMediaStatus(messageId, ownerPk, hadAny ? RYGDeletedMessageMediaStatusFailed : RYGDeletedMessageMediaStatusUnavailable);
}

static void rygAcquireMediaCandidates(NSString *messageId, NSString *ownerPk, RYGDeletedMessageKind kind,
									  NSArray<NSDictionary *> *cands, NSString *audioURL, NSString *mediaPk) {
	if (!messageId.length) return;
	BOOL hadAny = cands.count > 0 || mediaPk.length > 0;

	if (kind == RYGDeletedMessageKindVideo && audioURL.length && cands.count &&
		![cands[0][@"auth"] boolValue] && [RYGFFmpeg isAvailable]) {
		NSString *vurl = cands[0][@"url"];
		rygDownloadAndMuxVideo(vurl, audioURL, messageId, ownerPk, ^(BOOL ok) {
			if (ok) { rygSetMediaStatus(messageId, ownerPk, RYGDeletedMessageMediaStatusSaved); return; }
			rygAcquireFromCandidates(messageId, ownerPk, kind, cands, 0, mediaPk, hadAny);  // retry video-only
		});
		return;
	}

	rygAcquireFromCandidates(messageId, ownerPk, kind, cands, 0, mediaPk, hadAny);
}

static void rygAcquireMedia(NSString *messageId, NSString *ownerPk, RYGDeletedMessageKind kind,
							NSString *mediaURL, NSString *audioURL, NSString *mediaPk, BOOL allowRefetch) {
	NSMutableArray *c = [NSMutableArray array];
	if (mediaURL.length) [c addObject:@{@"url": mediaURL, @"auth": @NO}];
	rygAcquireMediaCandidates(messageId, ownerPk, kind, c, audioURL, allowRefetch ? mediaPk : nil);
}

void rygDMUpdateKeepAlive(void) {
	[RYGBackgroundActivity setSource:@"dm_keepalive" active:[RYGUtils getBoolPref:@"deleted_messages_keepalive"]];
}

void rygDMRetryMediaDownload(NSString *messageId, NSString *ownerPk) {
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
	__block RYGDeletedMessageKind kind = RYGDeletedMessageKindUnknown;
	__block NSString *mediaURL = nil, *mediaPk = nil;
	__block NSArray *cands = nil;

	[RYGDeletedMessagesStorage updateMessageWithId:messageId ownerPK:ownerPk mutator:^BOOL(RYGDeletedMessage *m) {
		if (m.mediaPath.length) return NO;                // already have the blob
		if (!m.mediaCandidates.count && !m.mediaURL.length && !m.mediaPk.length) return NO;  // nothing to try

		kind = m.kind;
		mediaURL = m.mediaURL;
		mediaPk = m.mediaPk;
		cands = m.mediaCandidates;
		go = YES;
		m.mediaStatus = RYGDeletedMessageMediaStatusPending;
		return YES;
	}];

	if (!go) return;
	if (cands.count) rygAcquireMediaCandidates(messageId, ownerPk, kind, cands, nil, mediaPk);
	else rygAcquireMedia(messageId, ownerPk, kind, mediaURL, nil, mediaPk, YES);
}

#pragma mark - On-open visual (view-once) capture

static double rygIVWidth(id v) {
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

static NSString *rygIVURL(id v) {
	NSString *m = nil, *t = nil;
	int ms = 0, ts = 0;
	rygScanURLs(v, 3, &m, &ms, &t, &ts, @"url");
	return m.length ? m : t;
}

// IGPhoto download candidates: widest CDN, then authed media_fallback.
static NSArray<NSDictionary *> *rygVisualPhotoCandidates(id photo, NSString **outDisplay) {
	if (outDisplay) *outDisplay = nil;
	if (!photo) return @[];

	NSString *fallback = nil, *bestCDN = nil;
	double bestW = -1;
	for (NSString *ivk in @[@"_originalImageVersions", @"_processedImageVersions"]) {
		id arr = rygIvar(photo, ivk.UTF8String);
		if (![arr isKindOfClass:NSArray.class]) continue;
		for (id v in (NSArray *)arr) {
			if (!fallback.length) {
				id fb = rygIvar(v, "_fallbackURL");
				if ([fb isKindOfClass:NSURL.class]) fallback = [(NSURL *)fb absoluteString];
			}
			NSString *u = rygIVURL(v);
			if (u.length) {
				double w = rygIVWidth(v);
				if (w > bestW) { bestW = w; bestCDN = u; }
			}
		}
	}
	if (!bestCDN.length) {
		NSString *m = nil, *t = nil;
		int ms = 0, ts = 0;
		rygScanURLs(photo, 6, &m, &ms, &t, &ts, @"image");
		bestCDN = m.length ? m : t;
	}

	if (outDisplay) *outDisplay = bestCDN;

	NSMutableArray *out = [NSMutableArray array];
	if (bestCDN.length)  [out addObject:@{@"url": bestCDN,  @"auth": @NO}];
	if (fallback.length) [out addObject:@{@"url": fallback, @"auth": @YES}];
	return out;
}

// IGVideo download candidates; outAudio = DASH audio for mux.
static NSArray<NSDictionary *> *rygVisualVideoCandidates(id video, NSString **outAudio, NSString **outDisplay) {
	if (outAudio) *outAudio = nil;
	if (outDisplay) *outDisplay = nil;
	if (!video) return @[];

	NSMutableArray *out = [NSMutableArray array];
	NSString *primary = nil;

	NSData *manifest = rygIvar(video, "_dashManifestData");
	if ([manifest isKindOfClass:NSData.class] && manifest.length) {
		NSString *xml = [[NSString alloc] initWithData:manifest encoding:NSUTF8StringEncoding];
		NSArray<RYGDashRepresentation *> *reps = [RYGDashParser parseManifest:xml];
		RYGDashRepresentation *bestV = [RYGDashParser representationForQuality:rygPreferredVideoQuality() fromRepresentations:reps];
		RYGDashRepresentation *bestA = [RYGDashParser bestAudioFromRepresentations:reps];
		if (bestV.url.absoluteString.length) { primary = bestV.url.absoluteString; [out addObject:@{@"url": primary, @"auth": @NO}]; }
		if (bestA.url.absoluteString.length && outAudio) *outAudio = bestA.url.absoluteString;
	}

	id urls = rygIvar(video, "_allVideoURLs");
	if ([urls isKindOfClass:NSSet.class] || [urls isKindOfClass:NSArray.class]) {
		for (id u in urls) {
			NSString *us = [u isKindOfClass:NSURL.class] ? [(NSURL *)u absoluteString] : ([u isKindOfClass:NSString.class] ? u : nil);
			if (us.length) { [out addObject:@{@"url": us, @"auth": @NO}]; if (!primary) primary = us; }
		}
	}

	for (NSString *iv in @[@"_broadcastURL", @"_playableURL"]) {
		id v = rygIvar(video, iv.UTF8String);
		NSString *us = [v isKindOfClass:NSURL.class] ? [(NSURL *)v absoluteString] : nil;
		if (us.length) { [out addObject:@{@"url": us, @"auth": @NO}]; if (!primary) primary = us; }
	}

	if (!out.count) {
		NSString *m = nil, *t = nil;
		int ms = 0, ts = 0;
		rygScanURLs(video, 5, &m, &ms, &t, &ts, @"video");
		if (m.length) { [out addObject:@{@"url": m, @"auth": @NO}]; primary = m; }
	}

	if (outDisplay) *outDisplay = primary;
	return out;
}

void rygDMCaptureVisualMessageOnOpen(id visualMessage, id contextMetadata, NSString *ownerPk) {
	if (!rygCaptureEnabled() || !visualMessage || !contextMetadata) return;

	@try {
		id info = rygIvar(visualMessage, "_visualMediaInfo");
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

		id key = rygIvar(contextMetadata, "_key");
		NSString *sid = rygStrIvar(key, "_serverId") ?: rygStrIvar(key, "_messageServerId");
		if (!sid.length) return;

		NSString *owner = ownerPk.length ? ownerPk.copy : @"";
		NSString *senderPk = rygStrIvar(contextMetadata, "_senderPk");
		if (senderPk.length && [senderPk isEqualToString:owner]) return;  // skip own sends

		id media = rygIvar(info, "_media");
		id videoObj = rygIvar(media, "_video_video");
		id photoObj = rygIvar(media, "_photo_photo");
		RYGDeletedMessageKind kind = videoObj ? RYGDeletedMessageKindVideo : RYGDeletedMessageKindPhoto;

		NSString *mediaURL = nil, *audioURL = nil, *thumbURL = nil;
		NSArray *cands = nil;
		if (videoObj) {
			cands = rygVisualVideoCandidates(videoObj, &audioURL, &mediaURL);
			rygVisualPhotoCandidates(rygIvar(media, "_video_overlayPhoto"), &thumbURL);
		} else {
			cands = rygVisualPhotoCandidates(photoObj, &mediaURL);
		}

		NSString *mediaPk = rygStrIvar(info, "_mediaId");
		NSDate *sentAt = nil;
		id sd = rygIvar(contextMetadata, "_sentDate");
		if ([sd isKindOfClass:NSDate.class]) sentAt = sd;

		// Thread id for grouping. The django identifier holds it as a long digit string; scan for it.
		id threadKey = rygIvar(contextMetadata, "_threadKey");
		id dj = rygIvar(threadKey, "_djangoThread_identifier");
		NSString *threadId = rygStrIvar(dj, "_identifier") ?: rygStrIvar(dj, "_threadId") ?: rygScanLongDigitString(dj);

		NSString *senderU = nil;
		if (senderPk.length) {
			rygResolveSender(senderPk, &senderU, NULL, NULL);
			if (!senderU.length) senderU = rygRosterUsername(threadId, senderPk);
		}

		dispatch_async(rygCaptureQueue(), ^{
			// Dedup: if we already hold the blob for this message, don't re-capture.
			__block BOOL haveBlob = NO;
			[RYGDeletedMessagesStorage updateMessageWithId:sid ownerPK:owner mutator:^BOOL(RYGDeletedMessage *m) {
				haveBlob = m.mediaPath.length > 0;
				return NO;
			}];
			if (haveBlob) return;

			NSDate *now = NSDate.date;
			RYGDeletedMessage *m = [RYGDeletedMessage new];
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

			NSDictionary *tinfo = rygCachedThreadInfo(threadId);
			if (tinfo) {
				if ([tinfo[@"is_group"] isKindOfClass:NSNumber.class]) m.isGroup = [tinfo[@"is_group"] boolValue];
				if ([tinfo[@"thread_title"] isKindOfClass:NSString.class]) m.threadTitle = tinfo[@"thread_title"];
				if ([tinfo[@"thread_avatar_url"] isKindOfClass:NSString.class]) m.threadAvatarURL = tinfo[@"thread_avatar_url"];
			}

			BOOL fetchable = cands.count || mediaPk.length;
			m.mediaStatus = fetchable ? RYGDeletedMessageMediaStatusPending : RYGDeletedMessageMediaStatusUnavailable;

			if ([RYGDeletedMessagesStorage isExcludedThreadId:m.threadId senderPk:m.senderPk ownerPK:owner]) return;

			[RYGDeletedMessagesStorage saveMessage:m forOwnerPK:owner];
			[RYGHomeShortcutBadges bumpActionID:@"deleted_messages"];
			if (threadId.length) rygResolveThreadInfo(threadId, owner, NO);

			if (fetchable) rygAcquireMediaCandidates(sid, owner, kind, cands ?: @[], audioURL, mediaPk);
			if (thumbURL.length) rygDownloadMedia(thumbURL, sid, owner, YES, nil);
		});
	} @catch (__unused id e) {}
}

#pragma mark - Fallback lookup

static id rygThreadStateForApplicator(id applicator, NSString *threadId) {
	if (!applicator || !threadId.length) return nil;

	@try {
		id cache = rygIvar(applicator, "_cache");
		SEL sel = NSSelectorFromString(@"threadClientStateForThreadId:");
		if (!cache || ![cache respondsToSelector:sel]) return nil;
		return ((id (*)(id, SEL, id))objc_msgSend)(cache, sel, threadId);
	} @catch (__unused id e) {
		return nil;
	}
}

static id rygFallbackLookupMessage(id applicator, NSString *sid, NSString *threadId) {
	if (!sid.length) return nil;

	id state = rygThreadStateForApplicator(applicator, threadId);
	id messageSet = rygIvar(state, "_threadMessageSet");
	id dict = rygIvar(messageSet, "_messagesByServerId");
	return [dict isKindOfClass:NSDictionary.class] ? dict[sid] : nil;
}

#pragma mark - Thread metadata resolution

static NSMutableDictionary<NSString *, NSDictionary *> *rygThreadInfoCache(void) {
	static NSMutableDictionary *d;
	static dispatch_once_t once;
	dispatch_once(&once, ^{ d = [NSMutableDictionary new]; });
	return d;
}

// Threads with a REST fetch currently in flight — avoids firing duplicates.
static NSMutableSet<NSString *> *rygThreadFetchInflight(void) {
	static NSMutableSet *s;
	static dispatch_once_t once;
	dispatch_once(&once, ^{ s = [NSMutableSet set]; });
	return s;
}

// Cached per session, applied to any account.
static NSMutableDictionary<NSString *, NSArray *> *rygThreadParticipants(void) {
	static NSMutableDictionary *d;
	static dispatch_once_t once;
	dispatch_once(&once, ^{ d = [NSMutableDictionary new]; });
	return d;
}

static NSDictionary *rygCachedThreadInfo(NSString *threadId) {
	if (!threadId.length) return nil;
	@synchronized (rygThreadInfoCache()) { return rygThreadInfoCache()[threadId]; }
}

static NSString *rygThreadImageURL(NSDictionary *thread) {
	id img = thread[@"thread_image"];
	if ([img isKindOfClass:NSString.class] && [(NSString *)img length]) return img;
	if ([img isKindOfClass:NSDictionary.class]) {
		id u = img[@"url"] ?: img[@"uri"];
		if ([u isKindOfClass:NSString.class] && [(NSString *)u length]) return u;
	}
	return nil;
}

static void rygApplyThreadCacheForOwner(NSString *threadId, NSString *owner, BOOL overwrite) {
	NSDictionary *info = rygCachedThreadInfo(threadId);
	if (info.count) [RYGDeletedMessagesStorage applyThreadInfo:info forThreadId:threadId ownerPK:owner];

	NSArray *roster = nil;
	@synchronized (rygThreadParticipants()) { roster = rygThreadParticipants()[threadId]; }
	for (NSDictionary *u in roster) {
		NSString *pk = u[@"pk"];
		NSMutableDictionary *si = [NSMutableDictionary dictionary];
		if ([u[@"username"] isKindOfClass:NSString.class]) si[@"username"] = u[@"username"];
		if ([u[@"full_name"] isKindOfClass:NSString.class]) si[@"full_name"] = u[@"full_name"];
		if ([u[@"profile_pic_url"] isKindOfClass:NSString.class]) si[@"profile_pic_url"] = u[@"profile_pic_url"];
		if (pk.length && si.count) [RYGDeletedMessagesStorage applySenderInfo:si forSenderPK:pk ownerPK:owner overwrite:overwrite];
	}
}

// Fetch thread group/title/roster over REST and stamp onto the asking account's
// store (delta stream has no thread metadata). force=YES refetches + overwrites.
static void rygResolveThreadInfo(NSString *threadId, NSString *owner, BOOL force) {
	if (!threadId.length) return;

	// Group name + image from live metadata (the REST thread_image is usually empty for groups).
	if (force || !rygCachedThreadInfo(threadId)) {
		[RYGDirectThreadInfo fetchThreadId:threadId ownerPK:owner completion:^(id thread) {
			NSDictionary *gi = [RYGDirectThreadInfo groupInfoForThread:thread viewerPK:owner];
			if (![gi[@"is_group"] boolValue]) return;
			NSMutableDictionary *info = [NSMutableDictionary dictionaryWithObject:@YES forKey:@"is_group"];
			if ([gi[@"name"] isKindOfClass:NSString.class]) info[@"thread_title"] = gi[@"name"];
			if ([gi[@"image"] isKindOfClass:NSString.class]) info[@"thread_avatar_url"] = gi[@"image"];
			if (info.count > 1) [RYGDeletedMessagesStorage applyThreadInfo:info forThreadId:threadId ownerPK:owner];
		}];
	}

	// Cached — apply to this account and skip the fetch (covers account switching).
	if (rygCachedThreadInfo(threadId) && !force) {
		rygApplyThreadCacheForOwner(threadId, owner, NO);
		return;
	}

	@synchronized (rygThreadFetchInflight()) {
		if ([rygThreadFetchInflight() containsObject:threadId]) return;
		[rygThreadFetchInflight() addObject:threadId];
	}

	NSString *path = [NSString stringWithFormat:@"direct_v2/threads/%@/?limit=1", threadId];
	[RYGInstagramAPI sendRequestWithMethod:@"GET" path:path body:nil completion:^(NSDictionary *resp, NSError *err) {
		@synchronized (rygThreadFetchInflight()) { [rygThreadFetchInflight() removeObject:threadId]; }

		NSDictionary *t = [resp[@"thread"] isKindOfClass:NSDictionary.class] ? resp[@"thread"] : nil;
		if (!t.count) return;

		NSMutableDictionary *info = [NSMutableDictionary dictionary];
		id grp = t[@"is_group"];
		if ([grp isKindOfClass:NSNumber.class]) info[@"is_group"] = @([grp boolValue]);
		NSString *title = [t[@"thread_title"] isKindOfClass:NSString.class] ? t[@"thread_title"] : nil;
		if (title.length) info[@"thread_title"] = title;
		NSString *avatar = rygThreadImageURL(t);
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

		if (info.count) { @synchronized (rygThreadInfoCache()) { rygThreadInfoCache()[threadId] = info; } }
		if (roster.count) { @synchronized (rygThreadParticipants()) { rygThreadParticipants()[threadId] = roster; } }

		rygApplyThreadCacheForOwner(threadId, owner, force);
	}];
}

void rygDMResolveThreadInfo(NSString *threadId, NSString *ownerPk) {
	rygResolveThreadInfo(threadId, ownerPk, NO);
}

void rygDMRefreshThreadInfo(NSString *threadId, NSString *ownerPk) {
	rygResolveThreadInfo(threadId, ownerPk, YES);
}

static NSDictionary *rygRosterEntry(NSString *threadId, NSString *pk) {
	if (!threadId.length || !pk.length) return nil;
	NSArray *roster = nil;
	@synchronized (rygThreadParticipants()) { roster = rygThreadParticipants()[threadId]; }
	for (NSDictionary *u in roster) {
		if ([u[@"pk"] isEqualToString:pk]) return u;
	}
	return nil;
}

static NSString *rygRosterUsername(NSString *threadId, NSString *pk) {
	id u = rygRosterEntry(threadId, pk)[@"username"];
	return [u isKindOfClass:NSString.class] ? u : nil;
}

static NSString *rygItemTypeLabel(NSString *type) {
	NSString *t = type.lowercaseString ?: @"";
	if ([t containsString:@"voice"]) return RYGLocalized(@"Voice");
	if ([t isEqualToString:@"clip"] || [t containsString:@"reel"]) return RYGLocalized(@"Reel");
	if ([t containsString:@"animated"]) return RYGLocalized(@"GIF");
	if ([t containsString:@"story"]) return RYGLocalized(@"Story");
	if ([t containsString:@"media"] || [t containsString:@"raven"] || [t containsString:@"visual"]) return RYGLocalized(@"Photo or video");
	if ([t containsString:@"link"]) return RYGLocalized(@"Link");
	return RYGLocalized(@"a message");
}

static void rygResolveReactionTarget(NSString *recordId, NSString *threadId, NSString *targetMessageId, NSString *owner) {
	if (!recordId.length || !threadId.length || !targetMessageId.length) return;

	NSString *path = [NSString stringWithFormat:@"direct_v2/threads/%@/?limit=20", threadId];
	[RYGInstagramAPI sendRequestWithMethod:@"GET" path:path body:nil completion:^(NSDictionary *resp, NSError *err) {
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
		NSString *preview = text.length ? text : rygItemTypeLabel([found[@"item_type"] isKindOfClass:NSString.class] ? found[@"item_type"] : nil);

		id uid = found[@"user_id"];
		NSString *authorPk = [uid isKindOfClass:NSString.class] ? uid : ([uid isKindOfClass:NSNumber.class] ? [uid stringValue] : nil);
		NSString *authorU = rygRosterUsername(threadId, authorPk);
		if (!authorU.length && authorPk.length) rygResolveSender(authorPk, &authorU, NULL, NULL);

		[RYGDeletedMessagesStorage updateMessageWithId:recordId ownerPK:owner mutator:^BOOL(RYGDeletedMessage *m) {
			BOOL ch = NO;
			if (preview.length && ![preview isEqualToString:m.text]) { m.text = preview; m.previewText = preview; ch = YES; }
			if (authorU.length && ![authorU isEqualToString:m.reactionTargetUsername]) { m.reactionTargetUsername = authorU; ch = YES; }
			return ch;
		}];
	}];
}

#pragma mark - Edit state

static NSMutableDictionary<NSString *, NSMutableDictionary *> *rygEditStates(void) {
	static NSMutableDictionary *d;
	static dispatch_once_t once;
	dispatch_once(&once, ^{ d = [NSMutableDictionary new]; });
	return d;
}

static NSMutableDictionary *rygEditState(NSString *sid, BOOL create) {
	if (!sid.length) return nil;

	@synchronized (rygLock()) {
		NSMutableDictionary *state = rygEditStates()[sid];
		if (state || !create) return state;

		if (rygEditStates().count >= 4000) {
			NSArray *keys = rygEditStates().allKeys;
			NSUInteger drop = MIN((NSUInteger)400, keys.count);
			for (NSUInteger i = 0; i < drop; i++) [rygEditStates() removeObjectForKey:keys[i]];
		}

		state = [NSMutableDictionary dictionary];
		rygEditStates()[sid] = state;
		return state;
	}
}

#pragma mark - Public hooks

void rygDMCaptureNoteInsert(id message) {
	if (!rygCaptureEnabled() || !message) return;

	@try {
		NSString *sid = rygSidFromMessage(message);
		if (!sid.length) return;

		@synchronized (rygLock()) {
			[rygMessageRefs() setObject:message forKey:sid];
		}

		id content = rygIvar(message, "_content") ?: rygIvar(message, "_messageContent") ?: rygIvar(message, "_payload");
		NSString *txt = rygStrIvar(content, "_text_string");
		if (!txt.length) return;

		NSMutableDictionary *st = rygEditState(sid, YES);
		if (!st[@"original"]) st[@"original"] = txt.copy;
	} @catch (__unused id e) {}
}

void rygDMCaptureNoteEdit(NSString *messageId, id contentMutation, NSString *ownerPk, NSString *threadId) {
	if (!rygCaptureEnabled() || !messageId.length || !contentMutation) return;

	NSString *newText = rygStrIvar(contentMutation, "_editText_newContent");
	if (!newText.length) return;

	long long editCount = 0;
	@try {
		Ivar iv = class_getInstanceVariable([contentMutation class], "_editText_editCount");
		if (iv) editCount = *(long long *)((char *)(__bridge void *)contentMutation + ivar_getOffset(iv));
	} @catch (__unused id e) {}

	NSDate *editAt = NSDate.date;
	id hist = rygIvar(contentMutation, "_editText_editHistory");
	if ([hist isKindOfClass:NSArray.class] && [(NSArray *)hist count]) {
		id ts = rygKVC([(NSArray *)hist lastObject], @"timestamp");
		if ([ts isKindOfClass:NSDate.class]) editAt = ts;
	}

	@synchronized (rygLock()) {
		NSMutableDictionary *st = rygEditState(messageId, YES);
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

void rygDMCaptureNoteReaction(NSString *messageId, id contentMutation, NSString *ownerPk, NSString *threadId) {
	if (!rygCaptureEnabled() || !messageId.length || !contentMutation) return;
	if (![RYGUtils getBoolPref:@"deleted_messages_log_reactions"]) return;

	// Only removals — adds arrive via _react_reactions and aren't deleted content.
	id rx = rygIvar(contentMutation, "_unreact_reaction");
	if (!rx) return;

	NSString *emoji = rygStrIvar(rx, "_userBasedReaction_emojiUnicode");
	NSString *reactorPk = rygStrIvar(contentMutation, "_unreact_userPk") ?: rygStrIvar(rx, "_userBasedReaction_userId");
	if (!reactorPk.length) return;

	NSString *owner = ownerPk.length ? ownerPk.copy : @"";
	if ([reactorPk isEqualToString:owner]) return;  // skip own

	NSDate *reactedAt = nil;
	id ts = rygIvar(rx, "_userBasedReaction_serverTimestamp");
	if ([ts isKindOfClass:NSDate.class]) reactedAt = ts;

	NSString *thread = threadId.length ? threadId.copy : nil;
	NSString *msgId = messageId.copy;
	NSString *emojiC = emoji.copy;
	NSString *reactorC = reactorPk.copy;

	id targetMsg = nil;
	@synchronized (rygLock()) { targetMsg = [rygMessageRefs() objectForKey:msgId]; }

	dispatch_async(rygCaptureQueue(), ^{
		NSString *preview = nil, *targetAuthorPk = nil;
		if (targetMsg) {
			NSDictionary *snap = rygBuildSnapshot(targetMsg, owner);
			RYGDeletedMessageKind tkind = (RYGDeletedMessageKind)[snap[@"kind"] integerValue];
			preview = snap[@"text"];
			if (!preview.length && tkind != RYGDeletedMessageKindUnknown) preview = RYGDeletedMessageKindLocalizedName(tkind);
			targetAuthorPk = snap[@"sender_pk"];
		}

		NSString *targetAuthorU = nil;
		if (targetAuthorPk.length) {
			targetAuthorU = rygRosterUsername(thread, targetAuthorPk);
			if (!targetAuthorU.length) rygResolveSender(targetAuthorPk, &targetAuthorU, NULL, NULL);
		}

		NSString *u = nil, *fn = nil, *pic = nil;
		rygResolveSender(reactorC, &u, &fn, &pic);
		if (!u.length) u = rygRosterUsername(thread, reactorC);

		NSDate *now = NSDate.date;
		RYGDeletedMessage *m = [RYGDeletedMessage new];
		m.messageId = [NSString stringWithFormat:@"%@:rx:%@:%@", msgId, reactorC, emojiC ?: @""];
		m.threadId = thread;
		m.senderPk = reactorC;
		m.senderUsername = u;
		m.senderFullName = fn;
		m.senderProfilePicURL = pic;
		m.kind = RYGDeletedMessageKindReactionRemoved;
		m.reactionEmoji = emojiC;
		m.targetMessageId = msgId;
		m.reactionTargetUsername = targetAuthorU;
		m.text = preview;
		m.previewText = preview;
		m.sentAt = reactedAt;
		m.capturedAt = now;
		m.deletedAt = now;

		NSDictionary *tinfo = rygCachedThreadInfo(thread);
		if (tinfo) {
			if ([tinfo[@"is_group"] isKindOfClass:NSNumber.class]) m.isGroup = [tinfo[@"is_group"] boolValue];
			if ([tinfo[@"thread_title"] isKindOfClass:NSString.class]) m.threadTitle = tinfo[@"thread_title"];
			if ([tinfo[@"thread_avatar_url"] isKindOfClass:NSString.class]) m.threadAvatarURL = tinfo[@"thread_avatar_url"];
		}

		if ([RYGDeletedMessagesStorage isExcludedThreadId:m.threadId senderPk:m.senderPk ownerPK:owner]) return;

		[RYGDeletedMessagesStorage saveMessage:m forOwnerPK:owner];
		[RYGHomeShortcutBadges bumpActionID:@"deleted_messages"];
		rygResolveThreadInfo(thread, owner, NO);

		// Not in memory — resolve over REST.
		if (!preview.length) rygResolveReactionTarget(m.messageId, thread, msgId, owner);

		// Toast: short title so it doesn't truncate, sentence in the subtitle.
		NSString *who = u.length ? [@"@" stringByAppendingString:u] : RYGLocalized(@"Someone");
		NSString *e = emojiC.length ? emojiC : @"";
		NSString *snippet = preview.length ? (preview.length > 40 ? [[preview substringToIndex:40] stringByAppendingString:@"…"] : preview) : nil;
		NSString *sub = snippet.length
			? [NSString stringWithFormat:RYGLocalized(@"removed %@ on: %@"), e, snippet]
			: [NSString stringWithFormat:RYGLocalized(@"removed reaction %@"), e];
		dispatch_async(dispatch_get_main_queue(), ^{
			RYGNotify(RYG_NOTIF_REACTION_REMOVED, who, sub, @"heart.slash.fill", RYGNotificationToneError);
		});
	});
}

static NSString *rygKeySid(id key) {
	if (!key) return nil;

	@try {
		NSString *sid = rygStrIvar(key, "_serverId") ?: rygStrIvar(key, "_messageServerId");
		return sid.length ? sid : nil;
	} @catch (__unused id e) {
		return nil;
	}
}

// Snapshot a live message into a record + acquire media.
static void rygSaveSnapshotForMessage(id msgObj, NSString *sid, NSString *owner, NSString *thread, BOOL skipIfExists) {
	if (!msgObj || !sid.length) return;

	// Isolate per message: a single bad message must never abort the rest of a launch batch.
	@try {
	if (skipIfExists) {
		__block BOOL exists = NO;
		[RYGDeletedMessagesStorage updateMessageWithId:sid ownerPK:owner mutator:^BOOL(RYGDeletedMessage *m) {
			exists = YES;
			return NO;
		}];
		if (exists) return;
	}

	NSDictionary *snap = rygBuildSnapshot(msgObj, owner);
	if (!snap) return;

	NSString *senderPk = snap[@"sender_pk"];
	BOOL outgoing = senderPk.length && [senderPk isEqualToString:owner];
	if (outgoing && ![RYGUtils getBoolPref:@"keep_my_deleted_messages"]) return;

	RYGDeletedMessageKind kind = (RYGDeletedMessageKind)[snap[@"kind"] integerValue];
	NSString *txt = snap[@"text"];
	NSString *media = snap[@"media_url"];
	NSString *thumb = snap[@"thumb_url"];
	NSArray *cands = [snap[@"media_candidates"] isKindOfClass:NSArray.class] ? snap[@"media_candidates"] : nil;

	if ((kind == RYGDeletedMessageKindUnknown || kind == RYGDeletedMessageKindOther) &&
		!txt.length && !media.length && !thumb.length && !cands.count) {
		return;
	}

	NSDate *now = NSDate.date;
	RYGDeletedMessage *m = [RYGDeletedMessage new];
	m.messageId = sid;
	m.threadId = snap[@"thread_id"] ?: thread;

	NSDictionary *tinfo = rygCachedThreadInfo(m.threadId);
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

	@synchronized (rygLock()) {
		NSMutableDictionary *st = rygEditStates()[sid];
		NSString *orig = [st[@"original"] isKindOfClass:NSString.class] ? st[@"original"] : nil;
		m.originalText = orig.length ? orig : m.text;

		NSArray *edits = st[@"edits"];
		if ([edits isKindOfClass:NSArray.class] && edits.count) {
			m.edits = edits.copy;
			m.editCount = [st[@"editCount"] unsignedIntegerValue];
			NSString *latest = st[@"latest"];
			if ([latest isKindOfClass:NSString.class] && latest.length) { m.text = latest; m.previewText = latest; }
		}
		[rygEditStates() removeObjectForKey:sid];
	}

	NSString *audioURL = snap[@"audio_url"];
	BOOL deeplinkOnly = m.kind == RYGDeletedMessageKindShare || m.kind == RYGDeletedMessageKindLink;
	BOOL carriesBlob = !deeplinkOnly &&
		(m.kind == RYGDeletedMessageKindPhoto || m.kind == RYGDeletedMessageKindVideo ||
		 m.kind == RYGDeletedMessageKindVoice || m.kind == RYGDeletedMessageKindGif ||
		 m.kind == RYGDeletedMessageKindSticker);

	if (carriesBlob) {
		BOOL fetchable = cands.count || m.mediaURL.length || m.mediaPk.length;
		m.mediaStatus = fetchable ? RYGDeletedMessageMediaStatusPending : RYGDeletedMessageMediaStatusUnavailable;
	}
	if (cands.count) m.mediaCandidates = cands;

	if ([RYGDeletedMessagesStorage isExcludedThreadId:m.threadId senderPk:m.senderPk ownerPK:owner]) return;

	[RYGDeletedMessagesStorage saveMessage:m forOwnerPK:owner];
	[RYGHomeShortcutBadges bumpActionID:@"deleted_messages"];

	if (carriesBlob) {
		if (cands.count) rygAcquireMediaCandidates(sid, owner, m.kind, cands, audioURL, m.mediaPk);
		else rygAcquireMedia(sid, owner, m.kind, m.mediaURL, audioURL, m.mediaPk, YES);
	}
	if (m.thumbnailURL.length) rygDownloadMedia(m.thumbnailURL, sid, owner, YES, nil);
	} @catch (__unused id e) {}
}

void rygDMCaptureNotePreservedMessage(id message, NSString *ownerPk, NSString *threadId) {
	if (!rygCaptureEnabled() || !message) return;
	NSString *sid = rygSidFromMessage(message);
	if (!sid.length) return;

	NSString *owner = ownerPk.length ? ownerPk.copy : @"";
	NSString *thread = threadId.length ? threadId.copy : nil;
	id msg = message;
	if (thread.length) rygResolveThreadInfo(thread, owner, NO);
	dispatch_async(rygCaptureQueue(), ^{
		rygSaveSnapshotForMessage(msg, sid, owner, thread, YES);
	});
}

void rygDMCaptureNoteRemoveKeys(NSArray *keys, id applicator, NSString *ownerPk, NSString *threadId) {
	if (!rygCaptureEnabled() || !keys.count) return;

	NSString *owner = ownerPk.length ? ownerPk.copy : @"";
	NSString *thread = threadId.length ? threadId.copy : nil;
	NSMutableDictionary<NSString *, id> *refs = [NSMutableDictionary dictionary];

	@synchronized (rygLock()) {
		for (id key in keys) {
			NSString *sid = rygKeySid(key);
			if (!sid.length) continue;

			id m = [rygMessageRefs() objectForKey:sid];
			if (m) {
				refs[sid] = m;
				[rygMessageRefs() removeObjectForKey:sid];
			}
		}
	}

	for (id key in keys) {
		NSString *sid = rygKeySid(key);
		if (!sid.length || refs[sid]) continue;

		id m = rygFallbackLookupMessage(applicator, sid, thread);
		if (m) refs[sid] = m;
	}

	if (!refs.count) return;

	rygResolveThreadInfo(thread, owner, NO);

	dispatch_async(rygCaptureQueue(), ^{
		for (NSString *sid in refs) {
			rygSaveSnapshotForMessage(refs[sid], sid, owner, thread, NO);
		}
	});
}