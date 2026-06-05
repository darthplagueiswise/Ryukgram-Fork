#import "SCIDeletedMessagesModels.h"
#import "../../Localization/SCILocalization.h"

typedef struct {
	SCIDeletedMessageKind kind;
	__unsafe_unretained NSString *key;
	__unsafe_unretained NSString *title;
	__unsafe_unretained NSString *symbol;
} SCIDMKindInfo;

static const SCIDMKindInfo kSCIDMKindInfos[] = {
	{ SCIDeletedMessageKindText,		@"text",		@"Text",	@"text.bubble.fill" },
	{ SCIDeletedMessageKindPhoto,		@"photo",		@"Photo",	@"photo.fill" },
	{ SCIDeletedMessageKindVideo,		@"video",		@"Video",	@"video.fill" },
	{ SCIDeletedMessageKindVoice,		@"voice",		@"Voice",	@"waveform" },
	{ SCIDeletedMessageKindGif,			@"gif",			@"GIF",		@"square.stack.fill" },
	{ SCIDeletedMessageKindSticker,		@"sticker",		@"Sticker",	@"face.smiling.fill" },
	{ SCIDeletedMessageKindShare,		@"share",		@"Share",	@"arrowshape.turn.up.right.fill" },
	{ SCIDeletedMessageKindLink,		@"link",		@"Link",	@"link" },
	{ SCIDeletedMessageKindAudioShare,	@"audio_share",	@"Audio",	@"music.note" },
	{ SCIDeletedMessageKindOther,		@"other",		@"Other",	@"bubble.left.fill" },
	{ SCIDeletedMessageKindUnknown,		@"unknown",		@"Unknown",	@"bubble.left.fill" },
};

static NSUInteger sciKindCount(void) {
	return sizeof(kSCIDMKindInfos) / sizeof(kSCIDMKindInfos[0]);
}

static const SCIDMKindInfo *sciKindInfo(SCIDeletedMessageKind kind) {
	for (NSUInteger i = 0; i < sciKindCount(); i++) {
		if (kSCIDMKindInfos[i].kind == kind) return &kSCIDMKindInfos[i];
	}
	return &kSCIDMKindInfos[sciKindCount() - 1];
}

NSString *SCIDeletedMessageKindToString(SCIDeletedMessageKind kind) {
	return sciKindInfo(kind)->key;
}

SCIDeletedMessageKind SCIDeletedMessageKindFromString(NSString *s) {
	if (![s isKindOfClass:NSString.class]) return SCIDeletedMessageKindUnknown;

	NSString *x = s.lowercaseString;
	for (NSUInteger i = 0; i < sciKindCount(); i++) {
		if ([x isEqualToString:kSCIDMKindInfos[i].key]) return kSCIDMKindInfos[i].kind;
	}

	// Backward/fuzzy compatibility for older saved logs or IG naming.
	if ([x isEqualToString:@"audio"] || [x isEqualToString:@"music"] || [x isEqualToString:@"xma_audio"]) return SCIDeletedMessageKindAudioShare;
	if ([x isEqualToString:@"voice_media"] || [x isEqualToString:@"voice_message"] || [x isEqualToString:@"audio_clip"]) return SCIDeletedMessageKindVoice;
	if ([x isEqualToString:@"animated"] || [x isEqualToString:@"animated_media"]) return SCIDeletedMessageKindGif;
	if ([x isEqualToString:@"reshare"] || [x isEqualToString:@"xma"] || [x isEqualToString:@"generic_xma"]) return SCIDeletedMessageKindShare;

	return SCIDeletedMessageKindUnknown;
}

NSString *SCIDeletedMessageKindLocalizedName(SCIDeletedMessageKind kind) {
	return SCILocalized(sciKindInfo(kind)->title);
}

NSString *SCIDeletedMessageKindSymbol(SCIDeletedMessageKind kind) {
	return sciKindInfo(kind)->symbol;
}

#pragma mark - JSON helpers

static NSString *sciStr(id v) {
	return [v isKindOfClass:NSString.class] ? v : nil;
}

static NSNumber *sciNum(id v) {
	return [v isKindOfClass:NSNumber.class] ? v : nil;
}

static double sciDouble(id v) {
	return sciNum(v).doubleValue;
}

static NSDate *sciDate(id v) {
	if ([v isKindOfClass:NSDate.class]) return v;
	if (![v isKindOfClass:NSNumber.class]) return nil;

	double t = [(NSNumber *)v doubleValue];
	if (t > 1.0e12) t /= 1000.0;
	return t > 0 ? [NSDate dateWithTimeIntervalSince1970:t] : nil;
}

static NSNumber *sciJSONDate(NSDate *d) {
	return d ? @(d.timeIntervalSince1970) : nil;
}

static void sciSet(NSMutableDictionary *d, NSString *k, id v) {
	if (!k.length || !v) return;
	if ([v isKindOfClass:NSString.class] && ![(NSString *)v length]) return;
	if ([v isKindOfClass:NSArray.class] && ![(NSArray *)v count]) return;
	d[k] = v;
}

static NSArray *sciCleanArray(id v, Class itemClass) {
	if (![v isKindOfClass:NSArray.class]) return nil;

	NSMutableArray *out = [NSMutableArray array];
	for (id item in (NSArray *)v) {
		if (!itemClass || [item isKindOfClass:itemClass]) [out addObject:item];
	}
	return out.count ? out : nil;
}

@implementation SCIDeletedMessage

+ (instancetype)messageFromJSONDict:(NSDictionary *)dict {
	if (![dict isKindOfClass:NSDictionary.class]) return nil;

	SCIDeletedMessage *m = [SCIDeletedMessage new];
	m.messageId = sciStr(dict[@"message_id"]);
	if (!m.messageId.length) return nil;

	m.threadId = sciStr(dict[@"thread_id"]);
	m.threadTitle = sciStr(dict[@"thread_title"]);
	m.senderPk = sciStr(dict[@"sender_pk"]) ?: @"";
	m.senderUsername = sciStr(dict[@"sender_username"]);
	m.senderFullName = sciStr(dict[@"sender_full_name"]);
	m.senderProfilePicURL = sciStr(dict[@"sender_profile_pic_url"]);

	m.sentAt = sciDate(dict[@"sent_at"]);
	m.capturedAt = sciDate(dict[@"captured_at"]);
	m.deletedAt = sciDate(dict[@"deleted_at"]);

	m.kind = SCIDeletedMessageKindFromString(sciStr(dict[@"kind"]));
	m.text = sciStr(dict[@"text"]);
	m.previewText = sciStr(dict[@"preview"]);

	m.mediaURL = sciStr(dict[@"media_url"]);
	m.mediaPath = sciStr(dict[@"media_path"]);
	m.thumbnailURL = sciStr(dict[@"thumbnail_url"]);
	m.thumbnailPath = sciStr(dict[@"thumbnail_path"]);
	m.mediaMimeType = sciStr(dict[@"media_mime"]);

	m.durationSeconds = sciDouble(dict[@"duration"]);
	m.waveform = sciCleanArray(dict[@"waveform"], NSNumber.class);

	m.width = sciDouble(dict[@"width"]);
	m.height = sciDouble(dict[@"height"]);
	m.replyToMessageId = sciStr(dict[@"reply_to_id"]);

	m.originalText = sciStr(dict[@"original_text"]);
	m.editCount = sciNum(dict[@"edit_count"]).unsignedIntegerValue;
	m.edits = sciCleanArray(dict[@"edits"], NSDictionary.class);

	// Backward safety: old captures may save audio as unknown but still have duration/waveform.
	if (m.kind == SCIDeletedMessageKindUnknown) {
		if (m.durationSeconds > 0 || m.waveform.count) m.kind = SCIDeletedMessageKindVoice;
		else if (m.mediaURL.length || m.mediaPath.length) m.kind = SCIDeletedMessageKindOther;
	}

	return m;
}

- (NSDictionary *)toJSONDict {
	NSMutableDictionary *d = [NSMutableDictionary dictionary];

	sciSet(d, @"message_id", self.messageId);
	sciSet(d, @"thread_id", self.threadId);
	sciSet(d, @"thread_title", self.threadTitle);
	sciSet(d, @"sender_pk", self.senderPk);
	sciSet(d, @"sender_username", self.senderUsername);
	sciSet(d, @"sender_full_name", self.senderFullName);
	sciSet(d, @"sender_profile_pic_url", self.senderProfilePicURL);

	sciSet(d, @"sent_at", sciJSONDate(self.sentAt));
	sciSet(d, @"captured_at", sciJSONDate(self.capturedAt));
	sciSet(d, @"deleted_at", sciJSONDate(self.deletedAt));

	d[@"kind"] = SCIDeletedMessageKindToString(self.kind);

	sciSet(d, @"text", self.text);
	sciSet(d, @"preview", self.previewText);

	sciSet(d, @"media_url", self.mediaURL);
	sciSet(d, @"media_path", self.mediaPath);
	sciSet(d, @"thumbnail_url", self.thumbnailURL);
	sciSet(d, @"thumbnail_path", self.thumbnailPath);
	sciSet(d, @"media_mime", self.mediaMimeType);

	if (self.durationSeconds > 0) d[@"duration"] = @(self.durationSeconds);
	sciSet(d, @"waveform", self.waveform);

	if (self.width > 0) d[@"width"] = @(self.width);
	if (self.height > 0) d[@"height"] = @(self.height);

	sciSet(d, @"reply_to_id", self.replyToMessageId);
	sciSet(d, @"original_text", self.originalText);

	if (self.editCount > 0) d[@"edit_count"] = @(self.editCount);
	sciSet(d, @"edits", self.edits);

	return d;
}

@end

@implementation SCIDeletedMessageGroup

- (NSUInteger)count { return self.messages.count; }
- (SCIDeletedMessage *)latest { return self.messages.firstObject; }
- (NSDate *)lastDeletedAt { return self.latest.deletedAt ?: self.latest.capturedAt ?: self.latest.sentAt; }

@end