#import "RYGDeletedMessagesStorage.h"
#import "../StoriesAndMessages/RYGKeptMessageStore.h"

NSNotificationName const RYGDeletedMessagesDidChangeNotification = @"RYGDeletedMessagesDidChangeNotification";

static NSString *const kRYGDMStorageDir = @"RyukGram/DeletedMessages";
static NSString *const kRYGDMMediaDir = @"media";
static NSString *const kRYGDMKeptDir = @"kept";

@implementation RYGDeletedMessagesStorage

#pragma mark - Helpers

static void *kRYGDMQKey = &kRYGDMQKey;

static dispatch_queue_t rygDMQ(void) {
	static dispatch_queue_t q;
	static dispatch_once_t once;
	dispatch_once(&once, ^{
		q = dispatch_queue_create("com.ryukgram.deletedmessages.io", DISPATCH_QUEUE_SERIAL);
		dispatch_queue_set_specific(q, kRYGDMQKey, kRYGDMQKey, NULL);
	});
	return q;
}

static void rygSync(dispatch_block_t b) {
	dispatch_get_specific(kRYGDMQKey) ? b() : dispatch_sync(rygDMQ(), b);
}

static NSFileManager *rygFM(void) { return NSFileManager.defaultManager; }

static NSString *rygClean(NSString *s, NSString *fallback) {
	if (!s.length) return fallback;
	NSMutableString *m = s.mutableCopy;
	NSCharacterSet *bad = [NSCharacterSet characterSetWithCharactersInString:@"/\\:?%*|\"<>"];
	for (NSUInteger i = 0; i < m.length; i++) {
		unichar c = [m characterAtIndex:i];
		if (c < 32 || [bad characterIsMember:c]) [m replaceCharactersInRange:NSMakeRange(i, 1) withString:@"_"];
	}
	return m.length ? m : fallback;
}

static NSString *rygDir(NSString *tail) {
	NSString *root = NSSearchPathForDirectoriesInDomains(NSApplicationSupportDirectory, NSUserDomainMask, YES).firstObject;
	NSString *dir = [[root stringByAppendingPathComponent:kRYGDMStorageDir] stringByAppendingPathComponent:(tail ?: @"")];
	[rygFM() createDirectoryAtPath:dir withIntermediateDirectories:YES attributes:nil error:nil];
	return dir;
}

static NSString *rygOwner(NSString *pk) { return rygClean(pk, @"anon"); }
static NSString *rygStoreDir(void) { return rygDir(nil); }
static NSString *rygMediaDir(NSString *owner) { return rygDir([kRYGDMMediaDir stringByAppendingPathComponent:rygOwner(owner)]); }
static NSString *rygJSON(NSString *owner) { return [rygStoreDir() stringByAppendingPathComponent:[rygOwner(owner) stringByAppendingString:@".json"]]; }
static NSString *rygExcludeJSON(NSString *owner) { return [rygStoreDir() stringByAppendingPathComponent:[rygOwner(owner) stringByAppendingString:@".excluded.json"]]; }

+ (NSString *)storageDirectory { return rygStoreDir(); }

static NSString *rygExcludeKey(NSString *threadId, NSString *senderPk) {
	if (threadId.length) return threadId;
	return senderPk.length ? [@"s:" stringByAppendingString:senderPk] : @"";
}

static NSMutableSet<NSString *> *rygReadExcluded(NSString *owner) {
	NSData *data = [NSData dataWithContentsOfFile:rygExcludeJSON(owner)];
	id raw = data.length ? [NSJSONSerialization JSONObjectWithData:data options:0 error:nil] : nil;
	return [raw isKindOfClass:NSArray.class] ? [NSMutableSet setWithArray:raw] : [NSMutableSet set];
}

static BOOL rygWriteExcluded(NSString *owner, NSSet<NSString *> *set) {
	NSData *data = [NSJSONSerialization dataWithJSONObject:set.allObjects options:0 error:nil];
	return data.length && [data writeToFile:rygExcludeJSON(owner) atomically:YES];
}

static NSDate *rygDate(RYGDeletedMessage *m) {
	return m.deletedAt ?: m.capturedAt ?: m.sentAt ?: NSDate.distantPast;
}

static void rygPost(NSString *owner) {
	dispatch_async(dispatch_get_main_queue(), ^{
		[NSNotificationCenter.defaultCenter postNotificationName:RYGDeletedMessagesDidChangeNotification
														  object:nil
														userInfo:owner.length ? @{@"owner_pk": owner} : @{}];
	});
}

static NSArray<RYGDeletedMessage *> *rygRead(NSString *owner) {
	NSData *data = [NSData dataWithContentsOfFile:rygJSON(owner)];
	if (!data.length) return @[];

	id raw = [NSJSONSerialization JSONObjectWithData:data options:0 error:nil];
	if (![raw isKindOfClass:NSArray.class]) return @[];

	NSMutableArray *out = [NSMutableArray arrayWithCapacity:[raw count]];
	for (id d in (NSArray *)raw) {
		RYGDeletedMessage *m = [RYGDeletedMessage messageFromJSONDict:d];
		if (m) [out addObject:m];
	}
	return out;
}

static BOOL rygWrite(NSString *owner, NSArray<RYGDeletedMessage *> *msgs) {
	NSMutableArray *raw = [NSMutableArray arrayWithCapacity:msgs.count];
	for (RYGDeletedMessage *m in msgs) {
		NSDictionary *d = [m toJSONDict];
		if (d) [raw addObject:d];
	}

	NSData *data = [NSJSONSerialization dataWithJSONObject:raw options:0 error:nil];
	return data.length && [data writeToFile:rygJSON(owner) atomically:YES];
}

static void rygSort(NSMutableArray<RYGDeletedMessage *> *a) {
	[a sortUsingComparator:^NSComparisonResult(RYGDeletedMessage *x, RYGDeletedMessage *y) {
		return [rygDate(y) compare:rygDate(x)];
	}];
}

static NSString *rygAbs(NSString *rel, NSString *owner) {
	return rel.length ? [rygMediaDir(owner) stringByAppendingPathComponent:rel.lastPathComponent] : nil;
}

static void rygRemoveFiles(RYGDeletedMessage *m, NSString *owner) {
	for (NSString *rel in @[m.mediaPath ?: @"", m.thumbnailPath ?: @""]) {
		NSString *p = rygAbs(rel, owner);
		if (p.length) [rygFM() removeItemAtPath:p error:nil];
	}
}

static BOOL rygRewrite(NSString *owner, BOOL notify, void (^mutate)(NSMutableArray<RYGDeletedMessage *> *list, BOOL *changed)) {
	__block BOOL changed = NO;
	__block BOOL ok = NO;

	rygSync(^{
		NSMutableArray *list = [rygRead(owner) mutableCopy];
		mutate(list, &changed);
		if (changed) ok = rygWrite(owner, list);
	});

	if (ok && notify) rygPost(owner);
	return ok;
}

#pragma mark - Read

+ (NSArray<RYGDeletedMessage *> *)allMessagesForOwnerPK:(NSString *)ownerPK {
	__block NSArray *out = nil;
	rygSync(^{ out = rygRead(ownerPK); });
	return out ?: @[];
}

+ (NSArray<RYGDeletedMessage *> *)messagesForSenderPK:(NSString *)senderPK ownerPK:(NSString *)ownerPK {
	if (!senderPK.length) return @[];

	__block NSMutableArray *out = nil;
	rygSync(^{
		out = [NSMutableArray array];
		for (RYGDeletedMessage *m in rygRead(ownerPK)) {
			if ([m.senderPk isEqualToString:senderPK]) [out addObject:m];
		}
	});
	return out ?: @[];
}

+ (NSArray<RYGDeletedMessage *> *)messagesForThreadId:(NSString *)threadId ownerPK:(NSString *)ownerPK {
	if (!threadId.length) return @[];

	__block NSMutableArray *out = nil;
	rygSync(^{
		out = [NSMutableArray array];
		for (RYGDeletedMessage *m in rygRead(ownerPK)) {
			if ([m.threadId isEqualToString:threadId]) [out addObject:m];
		}
	});
	return out ?: @[];
}

// Newest non-owner message = the 1-1 counterparty (an outgoing latest must not hijack identity).
static RYGDeletedMessage *rygCounterparty(NSArray<RYGDeletedMessage *> *msgs, NSString *ownerPK) {
	for (RYGDeletedMessage *m in msgs) {
		if (!(ownerPK.length && [m.senderPk isEqualToString:ownerPK])) return m;
	}
	return msgs.firstObject;
}

+ (NSArray<RYGDeletedMessageGroup *> *)groupedByThreadForOwnerPK:(NSString *)ownerPK {
	__block NSArray *result = nil;

	rygSync(^{
		NSMutableDictionary<NSString *, NSMutableArray *> *map = [NSMutableDictionary dictionary];
		NSMutableArray<NSString *> *order = [NSMutableArray array];

		for (RYGDeletedMessage *m in rygRead(ownerPK)) {
			// Legacy records with no threadId stay keyed by sender.
			NSString *key = m.threadId.length ? [@"t:" stringByAppendingString:m.threadId]
											  : (m.senderPk.length ? [@"s:" stringByAppendingString:m.senderPk] : nil);
			if (!key) continue;
			if (!map[key]) { map[key] = [NSMutableArray array]; [order addObject:key]; }
			[map[key] addObject:m];
		}

		NSMutableArray *groups = [NSMutableArray arrayWithCapacity:map.count];
		for (NSString *key in order) {
			NSArray<RYGDeletedMessage *> *msgs = map[key];
			RYGDeletedMessage *latest = msgs.firstObject;
			if (!latest) continue;

			BOOL isGroup = NO;
			NSString *threadTitle = nil, *threadAvatar = nil;
			for (RYGDeletedMessage *m in msgs) {
				if (m.isGroup) isGroup = YES;
				if (!threadTitle.length && m.threadTitle.length) threadTitle = m.threadTitle;
				if (!threadAvatar.length && m.threadAvatarURL.length) threadAvatar = m.threadAvatarURL;
			}

			RYGDeletedMessageGroup *g = [RYGDeletedMessageGroup new];
			g.threadId = latest.threadId;
			g.isGroup = isGroup;
			g.threadTitle = threadTitle;
			g.threadAvatarURL = threadAvatar;
			g.messages = msgs;

			// 1-1: carry the other party's identity so the row renders as before.
			RYGDeletedMessage *cp = rygCounterparty(msgs, ownerPK);
			g.senderPk = cp.senderPk;
			g.senderUsername = cp.senderUsername;
			g.senderFullName = cp.senderFullName;
			g.senderProfilePicURL = cp.senderProfilePicURL;

			[groups addObject:g];
		}

		[groups sortUsingComparator:^NSComparisonResult(RYGDeletedMessageGroup *a, RYGDeletedMessageGroup *b) {
			return [(b.lastDeletedAt ?: NSDate.distantPast) compare:(a.lastDeletedAt ?: NSDate.distantPast)];
		}];

		result = groups;
	});

	return result ?: @[];
}

+ (NSArray<RYGDeletedMessageGroup *> *)groupedBySenderForOwnerPK:(NSString *)ownerPK {
	__block NSArray *result = nil;

	rygSync(^{
		NSMutableDictionary<NSString *, NSMutableArray *> *map = [NSMutableDictionary dictionary];

		for (RYGDeletedMessage *m in rygRead(ownerPK)) {
			if (!m.senderPk.length) continue;
			if (!map[m.senderPk]) map[m.senderPk] = [NSMutableArray array];
			[map[m.senderPk] addObject:m];
		}

		NSMutableArray *groups = [NSMutableArray arrayWithCapacity:map.count];
		for (NSString *pk in map) {
			RYGDeletedMessage *latest = [map[pk] firstObject];
			if (!latest) continue;

			RYGDeletedMessageGroup *g = [RYGDeletedMessageGroup new];
			g.senderPk = pk;
			g.senderUsername = latest.senderUsername;
			g.senderFullName = latest.senderFullName;
			g.senderProfilePicURL = latest.senderProfilePicURL;
			g.messages = map[pk];
			[groups addObject:g];
		}

		[groups sortUsingComparator:^NSComparisonResult(RYGDeletedMessageGroup *a, RYGDeletedMessageGroup *b) {
			return [(b.lastDeletedAt ?: NSDate.distantPast) compare:(a.lastDeletedAt ?: NSDate.distantPast)];
		}];

		result = groups;
	});

	return result ?: @[];
}

#pragma mark - Write

+ (BOOL)saveMessage:(RYGDeletedMessage *)message forOwnerPK:(NSString *)ownerPK {
	return message ? [self saveMessages:@[message] forOwnerPK:ownerPK] : NO;
}

+ (BOOL)saveMessages:(NSArray<RYGDeletedMessage *> *)messages forOwnerPK:(NSString *)ownerPK {
	if (!messages.count) return NO;

	return rygRewrite(ownerPK, YES, ^(NSMutableArray<RYGDeletedMessage *> *list, BOOL *changed) {
		NSMutableSet *ids = [NSMutableSet set];

		for (RYGDeletedMessage *m in messages) {
			if (m.messageId.length) [ids addObject:m.messageId];
		}
		if (!ids.count) return;

		NSMutableDictionary<NSString *, RYGDeletedMessage *> *existing = [NSMutableDictionary dictionary];
		for (RYGDeletedMessage *m in list) {
			if (m.messageId.length && [ids containsObject:m.messageId]) existing[m.messageId] = m;
		}

		NSIndexSet *dupes = [list indexesOfObjectsPassingTest:^BOOL(RYGDeletedMessage *m, NSUInteger idx, BOOL *stop) {
			return [ids containsObject:m.messageId];
		}];
		if (dupes.count) [list removeObjectsAtIndexes:dupes];

		for (RYGDeletedMessage *m in messages) {
			if (!m.messageId.length) continue;
			// A later media-less write for the same id must not drop media a prior
			// capture already saved, nor relabel a saved video as a photo.
			RYGDeletedMessage *old = existing[m.messageId];
			if (old.mediaPath.length && !m.mediaPath.length) {
				m.mediaPath = old.mediaPath;
				if (!m.mediaMimeType.length) m.mediaMimeType = old.mediaMimeType;
				if (!m.thumbnailPath.length) m.thumbnailPath = old.thumbnailPath;
				if (m.width <= 0) m.width = old.width;
				if (m.height <= 0) m.height = old.height;
				if (old.mediaStatus == RYGDeletedMessageMediaStatusSaved) m.mediaStatus = RYGDeletedMessageMediaStatusSaved;
				if (old.kind == RYGDeletedMessageKindPhoto || old.kind == RYGDeletedMessageKindVideo) m.kind = old.kind;
				m.isEphemeral = m.isEphemeral || old.isEphemeral;
			}
			[list addObject:m];
		}

		rygSort(list);
		*changed = YES;
	});
}

+ (BOOL)updateMessageWithId:(NSString *)messageId ownerPK:(NSString *)ownerPK mutator:(BOOL (^)(RYGDeletedMessage *m))mutator {
	if (!messageId.length || !mutator) return NO;

	return rygRewrite(ownerPK, YES, ^(NSMutableArray<RYGDeletedMessage *> *list, BOOL *changed) {
		for (RYGDeletedMessage *m in list) {
			if (![m.messageId isEqualToString:messageId]) continue;
			*changed = mutator(m);
			return;
		}
	});
}

+ (BOOL)applySenderInfo:(NSDictionary *)info forSenderPK:(NSString *)senderPK ownerPK:(NSString *)ownerPK {
	return [self applySenderInfo:info forSenderPK:senderPK ownerPK:ownerPK overwrite:NO];
}

+ (BOOL)applySenderInfo:(NSDictionary *)info forSenderPK:(NSString *)senderPK ownerPK:(NSString *)ownerPK overwrite:(BOOL)overwrite {
	if (!senderPK.length || ![info isKindOfClass:NSDictionary.class]) return NO;

	NSString *u = [info[@"username"] isKindOfClass:NSString.class] ? info[@"username"] : nil;
	NSString *fn = [info[@"full_name"] isKindOfClass:NSString.class] ? info[@"full_name"] : nil;
	NSString *p = [info[@"profile_pic_url"] isKindOfClass:NSString.class] ? info[@"profile_pic_url"] : nil;
	if (!u.length && !fn.length && !p.length) return NO;

	return rygRewrite(ownerPK, YES, ^(NSMutableArray<RYGDeletedMessage *> *list, BOOL *changed) {
		for (RYGDeletedMessage *m in list) {
			if (![m.senderPk isEqualToString:senderPK]) continue;

			if (u.length && (overwrite ? ![u isEqualToString:m.senderUsername] : !m.senderUsername.length)) {
				m.senderUsername = u;
				*changed = YES;
			}
			if (fn.length && (overwrite ? ![fn isEqualToString:m.senderFullName] : !m.senderFullName.length)) {
				m.senderFullName = fn;
				*changed = YES;
			}
			if (p.length && (overwrite ? ![p isEqualToString:m.senderProfilePicURL] : !m.senderProfilePicURL.length)) {
				m.senderProfilePicURL = p;
				*changed = YES;
			}
		}
	});
}

+ (void)deleteMessageId:(NSString *)messageId forOwnerPK:(NSString *)ownerPK {
	if (!messageId.length) return;

	rygRewrite(ownerPK, YES, ^(NSMutableArray<RYGDeletedMessage *> *list, BOOL *changed) {
		for (NSInteger i = (NSInteger)list.count - 1; i >= 0; i--) {
			RYGDeletedMessage *m = list[i];
			if (![m.messageId isEqualToString:messageId]) continue;
			rygRemoveFiles(m, ownerPK);
			[list removeObjectAtIndex:(NSUInteger)i];
			*changed = YES;
		}
	});
}

+ (void)deleteMessagesForSenderPK:(NSString *)senderPK ownerPK:(NSString *)ownerPK {
	[self deleteMessagesForSenderPK:senderPK ownerPK:ownerPK threadlessOnly:NO];
}

+ (void)deleteMessagesForSenderPK:(NSString *)senderPK ownerPK:(NSString *)ownerPK threadlessOnly:(BOOL)threadlessOnly {
	if (!senderPK.length) return;

	rygRewrite(ownerPK, YES, ^(NSMutableArray<RYGDeletedMessage *> *list, BOOL *changed) {
		for (NSInteger i = (NSInteger)list.count - 1; i >= 0; i--) {
			RYGDeletedMessage *m = list[i];
			if (![m.senderPk isEqualToString:senderPK]) continue;
			if (threadlessOnly && m.threadId.length) continue;  // don't touch thread-grouped rows
			rygRemoveFiles(m, ownerPK);
			[list removeObjectAtIndex:(NSUInteger)i];
			*changed = YES;
		}
	});
}

+ (void)deleteMessagesForThreadId:(NSString *)threadId ownerPK:(NSString *)ownerPK {
	if (!threadId.length) return;

	rygRewrite(ownerPK, YES, ^(NSMutableArray<RYGDeletedMessage *> *list, BOOL *changed) {
		for (NSInteger i = (NSInteger)list.count - 1; i >= 0; i--) {
			RYGDeletedMessage *m = list[i];
			if (![m.threadId isEqualToString:threadId]) continue;
			rygRemoveFiles(m, ownerPK);
			[list removeObjectAtIndex:(NSUInteger)i];
			*changed = YES;
		}
	});
}

+ (BOOL)applyThreadInfo:(NSDictionary *)info forThreadId:(NSString *)threadId ownerPK:(NSString *)ownerPK {
	if (!threadId.length || ![info isKindOfClass:NSDictionary.class]) return NO;

	NSNumber *grp = [info[@"is_group"] isKindOfClass:NSNumber.class] ? info[@"is_group"] : nil;
	NSString *title = [info[@"thread_title"] isKindOfClass:NSString.class] ? info[@"thread_title"] : nil;
	NSString *avatar = [info[@"thread_avatar_url"] isKindOfClass:NSString.class] ? info[@"thread_avatar_url"] : nil;
	if (!grp && !title.length && !avatar.length) return NO;

	return rygRewrite(ownerPK, YES, ^(NSMutableArray<RYGDeletedMessage *> *list, BOOL *changed) {
		for (RYGDeletedMessage *m in list) {
			if (![m.threadId isEqualToString:threadId]) continue;

			if (grp && m.isGroup != grp.boolValue) { m.isGroup = grp.boolValue; *changed = YES; }
			if (title.length && ![title isEqualToString:m.threadTitle]) { m.threadTitle = title; *changed = YES; }
			if (avatar.length && ![avatar isEqualToString:m.threadAvatarURL]) { m.threadAvatarURL = avatar; *changed = YES; }
		}
	});
}

+ (void)resetForOwnerPK:(NSString *)ownerPK {
	__block BOOL changed = NO;

	[RYGKeptMessageStore resetForOwnerPK:ownerPK];

	rygSync(^{
		NSString *json = rygJSON(ownerPK);
		NSString *media = rygMediaDir(ownerPK);

		changed = [rygFM() fileExistsAtPath:json] || [rygFM() fileExistsAtPath:media];
		[rygFM() removeItemAtPath:json error:nil];
		[rygFM() removeItemAtPath:media error:nil];
	});

	if (changed) rygPost(ownerPK);
}

+ (void)resetAll {
	__block BOOL changed = NO;

	[RYGKeptMessageStore resetAll];

	rygSync(^{
		NSString *dir = rygStoreDir();
		changed = [rygFM() fileExistsAtPath:dir];
		[rygFM() removeItemAtPath:dir error:nil];
	});

	if (changed) rygPost(nil);
}

#pragma mark - Backup merge

+ (void)mergeImportedStoreAtPath:(NSString *)importedDir {
	BOOL isDir = NO;
	if (!importedDir.length || ![rygFM() fileExistsAtPath:importedDir isDirectory:&isDir] || !isDir) return;

	NSArray *names = [rygFM() contentsOfDirectoryAtPath:importedDir error:nil] ?: @[];
	__block BOOL changed = NO;

	rygSync(^{
		for (NSString *name in names) {
			NSString *src = [importedDir stringByAppendingPathComponent:name];

			if ([name hasSuffix:@".excluded.json"]) {
				NSString *owner = [name substringToIndex:name.length - @".excluded.json".length];
				NSData *data = [NSData dataWithContentsOfFile:src];
				id raw = data.length ? [NSJSONSerialization JSONObjectWithData:data options:0 error:nil] : nil;
				if (![raw isKindOfClass:NSArray.class] || ![(NSArray *)raw count]) continue;
				NSMutableSet *s = rygReadExcluded(owner);
				NSUInteger before = s.count;
				[s addObjectsFromArray:raw];
				if (s.count != before) changed |= rygWriteExcluded(owner, s);
				continue;
			}

			if ([name hasSuffix:@".json"]) {
				NSString *owner = [name substringToIndex:name.length - @".json".length];
				NSData *data = [NSData dataWithContentsOfFile:src];
				id raw = data.length ? [NSJSONSerialization JSONObjectWithData:data options:0 error:nil] : nil;
				if (![raw isKindOfClass:NSArray.class]) continue;

				NSMutableArray *list = [rygRead(owner) mutableCopy];
				NSMutableSet *seen = [NSMutableSet set];
				for (RYGDeletedMessage *m in list) if (m.messageId.length) [seen addObject:m.messageId];

				BOOL added = NO;
				for (id d in (NSArray *)raw) {
					RYGDeletedMessage *m = [RYGDeletedMessage messageFromJSONDict:d];
					if (!m || (m.messageId.length && [seen containsObject:m.messageId])) continue;
					if (m.messageId.length) [seen addObject:m.messageId];
					[list addObject:m];
					added = YES;
				}
				if (!added) continue;
				rygSort(list);
				changed |= rygWrite(owner, list);
			}
		}

		// Copy media blobs and kept-message archives we don't already have.
		for (NSString *sub in @[kRYGDMMediaDir, kRYGDMKeptDir]) {
			NSString *srcRoot = [importedDir stringByAppendingPathComponent:sub];
			for (NSString *owner in [rygFM() contentsOfDirectoryAtPath:srcRoot error:nil] ?: @[]) {
				NSString *srcOwnerDir = [srcRoot stringByAppendingPathComponent:owner];
				BOOL ownerIsDir = NO;
				if (![rygFM() fileExistsAtPath:srcOwnerDir isDirectory:&ownerIsDir] || !ownerIsDir) continue;

				NSString *dstOwnerDir = rygDir([sub stringByAppendingPathComponent:rygOwner(owner)]);
				for (NSString *f in [rygFM() contentsOfDirectoryAtPath:srcOwnerDir error:nil] ?: @[]) {
					NSString *dst = [dstOwnerDir stringByAppendingPathComponent:f];
					if ([rygFM() fileExistsAtPath:dst]) continue;
					changed |= [rygFM() copyItemAtPath:[srcOwnerDir stringByAppendingPathComponent:f] toPath:dst error:nil];
				}
			}
		}
	});

	if (changed) rygPost(nil);
}

#pragma mark - Exclude (skip logging)

+ (NSArray<NSString *> *)excludedIdentifiersForOwnerPK:(NSString *)ownerPK {
	__block NSArray *a = @[];
	rygSync(^{ a = rygReadExcluded(ownerPK).allObjects; });
	return a;
}

+ (BOOL)isExcludedIdentifier:(NSString *)identifier ownerPK:(NSString *)ownerPK {
	if (!identifier.length) return NO;
	__block BOOL r = NO;
	rygSync(^{ r = [rygReadExcluded(ownerPK) containsObject:identifier]; });
	return r;
}

+ (BOOL)isExcludedThreadId:(NSString *)threadId senderPk:(NSString *)senderPk ownerPK:(NSString *)ownerPK {
	return [self isExcludedIdentifier:rygExcludeKey(threadId, senderPk) ownerPK:ownerPK];
}

+ (void)setExcludedIdentifier:(NSString *)identifier excluded:(BOOL)excluded ownerPK:(NSString *)ownerPK {
	if (!identifier.length) return;
	__block BOOL ok = NO;
	rygSync(^{
		NSMutableSet *s = rygReadExcluded(ownerPK);
		NSUInteger before = s.count;
		excluded ? [s addObject:identifier] : [s removeObject:identifier];
		if (s.count != before) ok = rygWriteExcluded(ownerPK, s);
	});
	if (ok) rygPost(ownerPK);
}

#pragma mark - Media

+ (NSString *)absolutePathForRelativePath:(NSString *)relativePath ownerPK:(NSString *)ownerPK {
	return rygAbs(relativePath, ownerPK);
}

+ (NSString *)reserveRelativeMediaPathForMessageId:(NSString *)messageId extension:(NSString *)ext ownerPK:(NSString *)ownerPK {
	NSString *safeId = rygClean(messageId, @"message");
	NSString *cleanExt = rygClean(ext.length ? ext : @"bin", @"bin");
	if ([cleanExt hasPrefix:@"."]) cleanExt = [cleanExt substringFromIndex:1];

	(void)rygMediaDir(ownerPK);
	return [NSString stringWithFormat:@"%@.%@", safeId, cleanExt.length ? cleanExt : @"bin"];
}

+ (unsigned long long)mediaSizeBytesForOwnerPK:(NSString *)ownerPK {
	__block unsigned long long total = 0;

	rygSync(^{
		NSDirectoryEnumerator *en = [rygFM() enumeratorAtPath:rygMediaDir(ownerPK)];
		for (__unused NSString *rel in en) {
			NSDictionary *a = en.fileAttributes;
			if ([a[NSFileType] isEqualToString:NSFileTypeRegular]) {
				total += [a[NSFileSize] unsignedLongLongValue];
			}
		}
	});

	return total;
}

@end
