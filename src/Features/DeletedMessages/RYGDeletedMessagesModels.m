#import "RYGDeletedMessagesModels.h"
#import "../../Localization/RYGLocalization.h"

typedef struct {
	RYGDeletedMessageKind kind;
	__unsafe_unretained NSString *key;
	__unsafe_unretained NSString *title;
	__unsafe_unretained NSString *symbol;
} RYGDMKindInfo;

static const RYGDMKindInfo kRYGDMKindInfos[] = {
	{ RYGDeletedMessageKindText,		@"text",		@"Text",	@"text.bubble.fill" },
	{ RYGDeletedMessageKindPhoto,		@"photo",		@"Photo",	@"photo.fill" },
	{ RYGDeletedMessageKindVideo,		@"video",		@"Video",	@"video.fill" },
	{ RYGDeletedMessageKindVoice,		@"voice",		@"Voice",	@"waveform" },
	{ RYGDeletedMessageKindGif,			@"gif",			@"GIF",		@"square.stack.fill" },
	{ RYGDeletedMessageKindSticker,		@"sticker",		@"Sticker",	@"face.smiling.fill" },
	{ RYGDeletedMessageKindShare,		@"share",		@"Share",	@"arrowshape.turn.up.right.fill" },
	{ RYGDeletedMessageKindLink,		@"link",		@"Link",	@"link" },
	{ RYGDeletedMessageKindAudioShare,	@"audio_share",	@"Audio",	@"music.note" },
	{ RYGDeletedMessageKindReactionRemoved,	@"reaction_removed",	@"Reaction removed",	@"heart.slash.fill" },
	{ RYGDeletedMessageKindOther,		@"other",		@"Other",	@"bubble.left.fill" },
	{ RYGDeletedMessageKindUnknown,		@"unknown",		@"Unknown",	@"bubble.left.fill" },
};

static NSUInteger rygKindCount(void) {
	return sizeof(kRYGDMKindInfos) / sizeof(kRYGDMKindInfos[0]);
}

static const RYGDMKindInfo *rygKindInfo(RYGDeletedMessageKind kind) {
	for (NSUInteger i = 0; i < rygKindCount(); i++) {
		if (kRYGDMKindInfos[i].kind == kind) return &kRYGDMKindInfos[i];
	}
	return &kRYGDMKindInfos[rygKindCount() - 1];
}

NSString *RYGDeletedMessageKindToString(RYGDeletedMessageKind kind) {
	return rygKindInfo(kind)->key;
}

RYGDeletedMessageKind RYGDeletedMessageKindFromString(NSString *s) {
	if (![s isKindOfClass:NSString.class]) return RYGDeletedMessageKindUnknown;

	NSString *x = s.lowercaseString;
	for (NSUInteger i = 0; i < rygKindCount(); i++) {
		if ([x isEqualToString:kRYGDMKindInfos[i].key]) return kRYGDMKindInfos[i].kind;
	}

	// Backward/fuzzy compatibility for older saved logs or IG naming.
	if ([x isEqualToString:@"audio"] || [x isEqualToString:@"music"] || [x isEqualToString:@"xma_audio"]) return RYGDeletedMessageKindAudioShare;
	if ([x isEqualToString:@"voice_media"] || [x isEqualToString:@"voice_message"] || [x isEqualToString:@"audio_clip"]) return RYGDeletedMessageKindVoice;
	if ([x isEqualToString:@"animated"] || [x isEqualToString:@"animated_media"]) return RYGDeletedMessageKindGif;
	if ([x isEqualToString:@"reshare"] || [x isEqualToString:@"xma"] || [x isEqualToString:@"generic_xma"]) return RYGDeletedMessageKindShare;

	return RYGDeletedMessageKindUnknown;
}

NSString *RYGDeletedMessageKindLocalizedName(RYGDeletedMessageKind kind) {
	return RYGLocalized(rygKindInfo(kind)->title);
}

NSString *RYGDeletedMessageKindSymbol(RYGDeletedMessageKind kind) {
	return rygKindInfo(kind)->symbol;
}

NSString *RYGDeletedMessageMediaStatusToString(RYGDeletedMessageMediaStatus s) {
	switch (s) {
		case RYGDeletedMessageMediaStatusSaved:       return @"saved";
		case RYGDeletedMessageMediaStatusPending:     return @"pending";
		case RYGDeletedMessageMediaStatusFailed:      return @"failed";
		case RYGDeletedMessageMediaStatusUnavailable: return @"unavailable";
		case RYGDeletedMessageMediaStatusNone:        break;
	}
	return @"none";
}

RYGDeletedMessageMediaStatus RYGDeletedMessageMediaStatusFromString(NSString *s) {
	if (![s isKindOfClass:NSString.class]) return RYGDeletedMessageMediaStatusNone;
	NSString *x = s.lowercaseString;
	if ([x isEqualToString:@"saved"])       return RYGDeletedMessageMediaStatusSaved;
	if ([x isEqualToString:@"pending"])     return RYGDeletedMessageMediaStatusPending;
	if ([x isEqualToString:@"failed"])      return RYGDeletedMessageMediaStatusFailed;
	if ([x isEqualToString:@"unavailable"]) return RYGDeletedMessageMediaStatusUnavailable;
	return RYGDeletedMessageMediaStatusNone;
}

NSString *RYGDeletedMessageMediaStatusNote(RYGDeletedMessage *m) {
	if (!m) return nil;
	switch (m.mediaStatus) {
		case RYGDeletedMessageMediaStatusPending:
			return RYGLocalized(@"Downloading…");
		case RYGDeletedMessageMediaStatusFailed:
			return m.isEphemeral
				? RYGLocalized(@"Disappearing media expired before it could be saved")
				: RYGLocalized(@"Media couldn’t be downloaded — the link expired");
		case RYGDeletedMessageMediaStatusUnavailable:
			return m.isEphemeral
				? RYGLocalized(@"Disappearing media — gone before it could be saved")
				: RYGLocalized(@"Media wasn’t available to save");
		case RYGDeletedMessageMediaStatusSaved:
		case RYGDeletedMessageMediaStatusNone:
			return nil;
	}
	return nil;
}

#pragma mark - JSON helpers

static NSString *rygStr(id v) {
	return [v isKindOfClass:NSString.class] ? v : nil;
}

static NSNumber *rygNum(id v) {
	return [v isKindOfClass:NSNumber.class] ? v : nil;
}

static double rygDouble(id v) {
	return rygNum(v).doubleValue;
}

static NSDate *rygDate(id v) {
	if ([v isKindOfClass:NSDate.class]) return v;
	if (![v isKindOfClass:NSNumber.class]) return nil;

	double t = [(NSNumber *)v doubleValue];
	if (t > 1.0e12) t /= 1000.0;
	return t > 0 ? [NSDate dateWithTimeIntervalSince1970:t] : nil;
}

static NSNumber *rygJSONDate(NSDate *d) {
	return d ? @(d.timeIntervalSince1970) : nil;
}

static void rygSet(NSMutableDictionary *d, NSString *k, id v) {
	if (!k.length || !v) return;
	if ([v isKindOfClass:NSString.class] && ![(NSString *)v length]) return;
	if ([v isKindOfClass:NSArray.class] && ![(NSArray *)v count]) return;
	d[k] = v;
}

static NSArray *rygCleanArray(id v, Class itemClass) {
	if (![v isKindOfClass:NSArray.class]) return nil;

	NSMutableArray *out = [NSMutableArray array];
	for (id item in (NSArray *)v) {
		if (!itemClass || [item isKindOfClass:itemClass]) [out addObject:item];
	}
	return out.count ? out : nil;
}

@implementation RYGDeletedMessage

+ (instancetype)messageFromJSONDict:(NSDictionary *)dict {
	if (![dict isKindOfClass:NSDictionary.class]) return nil;

	RYGDeletedMessage *m = [RYGDeletedMessage new];
	m.messageId = rygStr(dict[@"message_id"]);
	if (!m.messageId.length) return nil;

	m.threadId = rygStr(dict[@"thread_id"]);
	m.threadTitle = rygStr(dict[@"thread_title"]);
	m.threadAvatarURL = rygStr(dict[@"thread_avatar_url"]);
	m.isGroup = rygNum(dict[@"is_group"]).boolValue;
	m.senderPk = rygStr(dict[@"sender_pk"]) ?: @"";
	m.senderUsername = rygStr(dict[@"sender_username"]);
	m.senderFullName = rygStr(dict[@"sender_full_name"]);
	m.senderProfilePicURL = rygStr(dict[@"sender_profile_pic_url"]);

	m.sentAt = rygDate(dict[@"sent_at"]);
	m.capturedAt = rygDate(dict[@"captured_at"]);
	m.deletedAt = rygDate(dict[@"deleted_at"]);

	m.kind = RYGDeletedMessageKindFromString(rygStr(dict[@"kind"]));
	m.text = rygStr(dict[@"text"]);
	m.previewText = rygStr(dict[@"preview"]);

	m.mediaURL = rygStr(dict[@"media_url"]);
	m.mediaPath = rygStr(dict[@"media_path"]);
	m.thumbnailURL = rygStr(dict[@"thumbnail_url"]);
	m.thumbnailPath = rygStr(dict[@"thumbnail_path"]);
	m.mediaMimeType = rygStr(dict[@"media_mime"]);

	m.isEphemeral = rygNum(dict[@"is_ephemeral"]).boolValue;
	m.mediaPk = rygStr(dict[@"media_pk"]);
	m.mediaCandidates = rygCleanArray(dict[@"media_candidates"], NSDictionary.class);
	if (dict[@"media_status"]) {
		m.mediaStatus = RYGDeletedMessageMediaStatusFromString(rygStr(dict[@"media_status"]));
	} else {
		// Legacy records: infer Saved if a blob exists, else None.
		m.mediaStatus = m.mediaPath.length ? RYGDeletedMessageMediaStatusSaved : RYGDeletedMessageMediaStatusNone;
	}

	m.durationSeconds = rygDouble(dict[@"duration"]);
	m.waveform = rygCleanArray(dict[@"waveform"], NSNumber.class);

	m.width = rygDouble(dict[@"width"]);
	m.height = rygDouble(dict[@"height"]);
	m.replyToMessageId = rygStr(dict[@"reply_to_id"]);

	m.originalText = rygStr(dict[@"original_text"]);
	m.editCount = rygNum(dict[@"edit_count"]).unsignedIntegerValue;
	m.edits = rygCleanArray(dict[@"edits"], NSDictionary.class);

	m.reactionEmoji = rygStr(dict[@"reaction_emoji"]);
	m.targetMessageId = rygStr(dict[@"target_message_id"]);
	m.reactionTargetUsername = rygStr(dict[@"reaction_target_username"]);

	// Backward safety: old captures may save audio as unknown but still have duration/waveform.
	if (m.kind == RYGDeletedMessageKindUnknown) {
		if (m.durationSeconds > 0 || m.waveform.count) m.kind = RYGDeletedMessageKindVoice;
		else if (m.mediaURL.length || m.mediaPath.length) m.kind = RYGDeletedMessageKindOther;
	}

	return m;
}

- (NSDictionary *)toJSONDict {
	NSMutableDictionary *d = [NSMutableDictionary dictionary];

	rygSet(d, @"message_id", self.messageId);
	rygSet(d, @"thread_id", self.threadId);
	rygSet(d, @"thread_title", self.threadTitle);
	rygSet(d, @"thread_avatar_url", self.threadAvatarURL);
	if (self.isGroup) d[@"is_group"] = @YES;
	rygSet(d, @"sender_pk", self.senderPk);
	rygSet(d, @"sender_username", self.senderUsername);
	rygSet(d, @"sender_full_name", self.senderFullName);
	rygSet(d, @"sender_profile_pic_url", self.senderProfilePicURL);

	rygSet(d, @"sent_at", rygJSONDate(self.sentAt));
	rygSet(d, @"captured_at", rygJSONDate(self.capturedAt));
	rygSet(d, @"deleted_at", rygJSONDate(self.deletedAt));

	d[@"kind"] = RYGDeletedMessageKindToString(self.kind);

	rygSet(d, @"text", self.text);
	rygSet(d, @"preview", self.previewText);

	rygSet(d, @"media_url", self.mediaURL);
	rygSet(d, @"media_path", self.mediaPath);
	rygSet(d, @"thumbnail_url", self.thumbnailURL);
	rygSet(d, @"thumbnail_path", self.thumbnailPath);
	rygSet(d, @"media_mime", self.mediaMimeType);

	if (self.mediaStatus != RYGDeletedMessageMediaStatusNone) d[@"media_status"] = RYGDeletedMessageMediaStatusToString(self.mediaStatus);
	if (self.isEphemeral) d[@"is_ephemeral"] = @YES;
	rygSet(d, @"media_pk", self.mediaPk);
	rygSet(d, @"media_candidates", self.mediaCandidates);

	if (self.durationSeconds > 0) d[@"duration"] = @(self.durationSeconds);
	rygSet(d, @"waveform", self.waveform);

	if (self.width > 0) d[@"width"] = @(self.width);
	if (self.height > 0) d[@"height"] = @(self.height);

	rygSet(d, @"reply_to_id", self.replyToMessageId);
	rygSet(d, @"original_text", self.originalText);

	if (self.editCount > 0) d[@"edit_count"] = @(self.editCount);
	rygSet(d, @"edits", self.edits);

	rygSet(d, @"reaction_emoji", self.reactionEmoji);
	rygSet(d, @"target_message_id", self.targetMessageId);
	rygSet(d, @"reaction_target_username", self.reactionTargetUsername);

	return d;
}

@end

@implementation RYGDeletedMessageGroup

- (NSUInteger)count { return self.messages.count; }
- (RYGDeletedMessage *)latest { return self.messages.firstObject; }
- (NSDate *)lastDeletedAt { return self.latest.deletedAt ?: self.latest.capturedAt ?: self.latest.sentAt; }

- (NSString *)identifier {
	if (self.threadId.length) return self.threadId;
	return self.senderPk.length ? [@"s:" stringByAppendingString:self.senderPk] : @"";
}

- (NSArray<RYGDeletedMessage *> *)distinctSenders {
	NSMutableArray<RYGDeletedMessage *> *out = [NSMutableArray array];
	NSMutableSet<NSString *> *seen = [NSMutableSet set];
	for (RYGDeletedMessage *m in self.messages) {
		NSString *pk = m.senderPk.length ? m.senderPk : (m.senderUsername ?: @"");
		if (!pk.length || [seen containsObject:pk]) continue;
		[seen addObject:pk];
		[out addObject:m];
	}
	return out;
}

@end