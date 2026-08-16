#import "RYGCallRecordingModels.h"

static NSString *rygStr(id v) { return [v isKindOfClass:NSString.class] ? v : nil; }

@implementation RYGCallRecording

+ (instancetype)recordingFromJSONDict:(NSDictionary *)dict {
	if (![dict isKindOfClass:NSDictionary.class]) return nil;
	NSString *rid = rygStr(dict[@"id"]);
	if (!rid.length) return nil;

	RYGCallRecording *m = [RYGCallRecording new];
	m.recordingId = rid;
	m.threadId = rygStr(dict[@"thread_id"]);
	m.isGroup = [dict[@"is_group"] boolValue];
	m.isVideo = [dict[@"is_video"] boolValue];
	m.peerPk = rygStr(dict[@"peer_pk"]);
	m.peerUsername = rygStr(dict[@"peer_username"]);
	m.peerFullName = rygStr(dict[@"peer_full_name"]);
	m.peerProfilePicURL = rygStr(dict[@"peer_profile_pic_url"]);
	m.threadTitle = rygStr(dict[@"thread_title"]);
	m.threadAvatarURL = rygStr(dict[@"thread_avatar_url"]);
	double t = [dict[@"started_at"] doubleValue];
	m.startedAt = t > 0 ? [NSDate dateWithTimeIntervalSince1970:t] : NSDate.distantPast;
	m.durationSeconds = [dict[@"duration"] doubleValue];
	m.fileSizeBytes = [dict[@"size"] unsignedLongLongValue];
	m.mediaPath = rygStr(dict[@"media_path"]) ?: @"";
	return m;
}

- (NSDictionary *)toJSONDict {
	NSMutableDictionary *d = [NSMutableDictionary dictionary];
	d[@"id"] = self.recordingId ?: @"";
	if (self.threadId.length) d[@"thread_id"] = self.threadId;
	d[@"is_group"] = @(self.isGroup);
	d[@"is_video"] = @(self.isVideo);
	if (self.peerPk.length) d[@"peer_pk"] = self.peerPk;
	if (self.peerUsername.length) d[@"peer_username"] = self.peerUsername;
	if (self.peerFullName.length) d[@"peer_full_name"] = self.peerFullName;
	if (self.peerProfilePicURL.length) d[@"peer_profile_pic_url"] = self.peerProfilePicURL;
	if (self.threadTitle.length) d[@"thread_title"] = self.threadTitle;
	if (self.threadAvatarURL.length) d[@"thread_avatar_url"] = self.threadAvatarURL;
	d[@"started_at"] = @([(self.startedAt ?: NSDate.distantPast) timeIntervalSince1970]);
	d[@"duration"] = @(self.durationSeconds);
	d[@"size"] = @(self.fileSizeBytes);
	d[@"media_path"] = self.mediaPath ?: @"";
	return d;
}

- (NSString *)displayName {
	if (self.isGroup) return self.threadTitle.length ? self.threadTitle : RYGLocalized(@"Group call");
	if (self.peerFullName.length) return self.peerFullName;
	if (self.peerUsername.length) return self.peerUsername;
	return RYGLocalized(@"Unknown chat");
}

- (NSString *)avatarURL {
	return self.isGroup ? self.threadAvatarURL : self.peerProfilePicURL;
}

@end

@implementation RYGCallRecordingGroup

- (NSUInteger)count { return self.recordings.count; }
- (unsigned long long)totalBytes {
	unsigned long long t = 0;
	for (RYGCallRecording *r in self.recordings) t += r.fileSizeBytes;
	return t;
}
- (RYGCallRecording *)latest { return self.recordings.firstObject; }
- (NSDate *)lastRecordedAt { return self.latest.startedAt; }

- (NSString *)displayName {
	if (self.customName.length) return self.customName;
	if ([self.identifier isEqualToString:@"uncategorized"]) return RYGLocalized(@"Unknown chat");
	if (self.isGroup) return self.threadTitle.length ? self.threadTitle : RYGLocalized(@"Group call");
	if (self.peerFullName.length) return self.peerFullName;
	if (self.peerUsername.length) return self.peerUsername;
	return RYGLocalized(@"Unknown chat");
}

- (NSString *)avatarURL {
	return self.isGroup ? self.threadAvatarURL : self.peerProfilePicURL;
}

@end
