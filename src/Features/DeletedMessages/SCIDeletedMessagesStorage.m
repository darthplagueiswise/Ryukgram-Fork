#import "SCIDeletedMessagesStorage.h"

NSNotificationName const SCIDeletedMessagesDidChangeNotification = @"SCIDeletedMessagesDidChangeNotification";

static NSString *const kSCIDMStorageDir = @"RyukGram/DeletedMessages";
static NSString *const kSCIDMMediaDir = @"media";

@implementation SCIDeletedMessagesStorage

#pragma mark - Helpers

static void *kSCIDMQKey = &kSCIDMQKey;

static dispatch_queue_t sciDMQ(void) {
	static dispatch_queue_t q;
	static dispatch_once_t once;
	dispatch_once(&once, ^{
		q = dispatch_queue_create("com.ryukgram.deletedmessages.io", DISPATCH_QUEUE_SERIAL);
		dispatch_queue_set_specific(q, kSCIDMQKey, kSCIDMQKey, NULL);
	});
	return q;
}

static void sciSync(dispatch_block_t b) {
	dispatch_get_specific(kSCIDMQKey) ? b() : dispatch_sync(sciDMQ(), b);
}

static NSFileManager *sciFM(void) { return NSFileManager.defaultManager; }

static NSString *sciClean(NSString *s, NSString *fallback) {
	if (!s.length) return fallback;
	NSMutableString *m = s.mutableCopy;
	NSCharacterSet *bad = [NSCharacterSet characterSetWithCharactersInString:@"/\\:?%*|\"<>"];
	for (NSUInteger i = 0; i < m.length; i++) {
		unichar c = [m characterAtIndex:i];
		if (c < 32 || [bad characterIsMember:c]) [m replaceCharactersInRange:NSMakeRange(i, 1) withString:@"_"];
	}
	return m.length ? m : fallback;
}

static NSString *sciDir(NSString *tail) {
	NSString *root = NSSearchPathForDirectoriesInDomains(NSApplicationSupportDirectory, NSUserDomainMask, YES).firstObject;
	NSString *dir = [[root stringByAppendingPathComponent:kSCIDMStorageDir] stringByAppendingPathComponent:(tail ?: @"")];
	[sciFM() createDirectoryAtPath:dir withIntermediateDirectories:YES attributes:nil error:nil];
	return dir;
}

static NSString *sciOwner(NSString *pk) { return sciClean(pk, @"anon"); }
static NSString *sciStoreDir(void) { return sciDir(nil); }
static NSString *sciMediaDir(NSString *owner) { return sciDir([kSCIDMMediaDir stringByAppendingPathComponent:sciOwner(owner)]); }
static NSString *sciJSON(NSString *owner) { return [sciStoreDir() stringByAppendingPathComponent:[sciOwner(owner) stringByAppendingString:@".json"]]; }

+ (NSString *)storageDirectory { return sciStoreDir(); }

static NSDate *sciDate(SCIDeletedMessage *m) {
	return m.deletedAt ?: m.capturedAt ?: m.sentAt ?: NSDate.distantPast;
}

static void sciPost(NSString *owner) {
	dispatch_async(dispatch_get_main_queue(), ^{
		[NSNotificationCenter.defaultCenter postNotificationName:SCIDeletedMessagesDidChangeNotification
														  object:nil
														userInfo:owner.length ? @{@"owner_pk": owner} : @{}];
	});
}

static NSArray<SCIDeletedMessage *> *sciRead(NSString *owner) {
	NSData *data = [NSData dataWithContentsOfFile:sciJSON(owner)];
	if (!data.length) return @[];

	id raw = [NSJSONSerialization JSONObjectWithData:data options:0 error:nil];
	if (![raw isKindOfClass:NSArray.class]) return @[];

	NSMutableArray *out = [NSMutableArray arrayWithCapacity:[raw count]];
	for (id d in (NSArray *)raw) {
		SCIDeletedMessage *m = [SCIDeletedMessage messageFromJSONDict:d];
		if (m) [out addObject:m];
	}
	return out;
}

static BOOL sciWrite(NSString *owner, NSArray<SCIDeletedMessage *> *msgs) {
	NSMutableArray *raw = [NSMutableArray arrayWithCapacity:msgs.count];
	for (SCIDeletedMessage *m in msgs) {
		NSDictionary *d = [m toJSONDict];
		if (d) [raw addObject:d];
	}

	NSData *data = [NSJSONSerialization dataWithJSONObject:raw options:0 error:nil];
	return data.length && [data writeToFile:sciJSON(owner) atomically:YES];
}

static void sciSort(NSMutableArray<SCIDeletedMessage *> *a) {
	[a sortUsingComparator:^NSComparisonResult(SCIDeletedMessage *x, SCIDeletedMessage *y) {
		return [sciDate(y) compare:sciDate(x)];
	}];
}

static NSString *sciAbs(NSString *rel, NSString *owner) {
	return rel.length ? [sciMediaDir(owner) stringByAppendingPathComponent:rel.lastPathComponent] : nil;
}

static void sciRemoveFiles(SCIDeletedMessage *m, NSString *owner) {
	for (NSString *rel in @[m.mediaPath ?: @"", m.thumbnailPath ?: @""]) {
		NSString *p = sciAbs(rel, owner);
		if (p.length) [sciFM() removeItemAtPath:p error:nil];
	}
}

static BOOL sciRewrite(NSString *owner, BOOL notify, void (^mutate)(NSMutableArray<SCIDeletedMessage *> *list, BOOL *changed)) {
	__block BOOL changed = NO;
	__block BOOL ok = NO;

	sciSync(^{
		NSMutableArray *list = [sciRead(owner) mutableCopy];
		mutate(list, &changed);
		if (changed) ok = sciWrite(owner, list);
	});

	if (ok && notify) sciPost(owner);
	return ok;
}

#pragma mark - Read

+ (NSArray<SCIDeletedMessage *> *)allMessagesForOwnerPK:(NSString *)ownerPK {
	__block NSArray *out = nil;
	sciSync(^{ out = sciRead(ownerPK); });
	return out ?: @[];
}

+ (NSArray<SCIDeletedMessage *> *)messagesForSenderPK:(NSString *)senderPK ownerPK:(NSString *)ownerPK {
	if (!senderPK.length) return @[];

	__block NSMutableArray *out = nil;
	sciSync(^{
		out = [NSMutableArray array];
		for (SCIDeletedMessage *m in sciRead(ownerPK)) {
			if ([m.senderPk isEqualToString:senderPK]) [out addObject:m];
		}
	});
	return out ?: @[];
}

+ (NSArray<SCIDeletedMessageGroup *> *)groupedBySenderForOwnerPK:(NSString *)ownerPK {
	__block NSArray *result = nil;

	sciSync(^{
		NSMutableDictionary<NSString *, NSMutableArray *> *map = [NSMutableDictionary dictionary];

		for (SCIDeletedMessage *m in sciRead(ownerPK)) {
			if (!m.senderPk.length) continue;
			if (!map[m.senderPk]) map[m.senderPk] = [NSMutableArray array];
			[map[m.senderPk] addObject:m];
		}

		NSMutableArray *groups = [NSMutableArray arrayWithCapacity:map.count];
		for (NSString *pk in map) {
			SCIDeletedMessage *latest = [map[pk] firstObject];
			if (!latest) continue;

			SCIDeletedMessageGroup *g = [SCIDeletedMessageGroup new];
			g.senderPk = pk;
			g.senderUsername = latest.senderUsername;
			g.senderFullName = latest.senderFullName;
			g.senderProfilePicURL = latest.senderProfilePicURL;
			g.messages = map[pk];
			[groups addObject:g];
		}

		[groups sortUsingComparator:^NSComparisonResult(SCIDeletedMessageGroup *a, SCIDeletedMessageGroup *b) {
			return [(b.lastDeletedAt ?: NSDate.distantPast) compare:(a.lastDeletedAt ?: NSDate.distantPast)];
		}];

		result = groups;
	});

	return result ?: @[];
}

#pragma mark - Write

+ (BOOL)saveMessage:(SCIDeletedMessage *)message forOwnerPK:(NSString *)ownerPK {
	return message ? [self saveMessages:@[message] forOwnerPK:ownerPK] : NO;
}

+ (BOOL)saveMessages:(NSArray<SCIDeletedMessage *> *)messages forOwnerPK:(NSString *)ownerPK {
	if (!messages.count) return NO;

	return sciRewrite(ownerPK, YES, ^(NSMutableArray<SCIDeletedMessage *> *list, BOOL *changed) {
		NSMutableSet *ids = [NSMutableSet set];

		for (SCIDeletedMessage *m in messages) {
			if (m.messageId.length) [ids addObject:m.messageId];
		}
		if (!ids.count) return;

		NSIndexSet *dupes = [list indexesOfObjectsPassingTest:^BOOL(SCIDeletedMessage *m, NSUInteger idx, BOOL *stop) {
			return [ids containsObject:m.messageId];
		}];
		if (dupes.count) [list removeObjectsAtIndexes:dupes];

		for (SCIDeletedMessage *m in messages) {
			if (m.messageId.length) [list addObject:m];
		}

		sciSort(list);
		*changed = YES;
	});
}

+ (BOOL)updateMessageWithId:(NSString *)messageId ownerPK:(NSString *)ownerPK mutator:(BOOL (^)(SCIDeletedMessage *m))mutator {
	if (!messageId.length || !mutator) return NO;

	return sciRewrite(ownerPK, YES, ^(NSMutableArray<SCIDeletedMessage *> *list, BOOL *changed) {
		for (SCIDeletedMessage *m in list) {
			if (![m.messageId isEqualToString:messageId]) continue;
			*changed = mutator(m);
			return;
		}
	});
}

+ (BOOL)applySenderInfo:(NSDictionary *)info forSenderPK:(NSString *)senderPK ownerPK:(NSString *)ownerPK {
	if (!senderPK.length || ![info isKindOfClass:NSDictionary.class]) return NO;

	NSString *u = [info[@"username"] isKindOfClass:NSString.class] ? info[@"username"] : nil;
	NSString *fn = [info[@"full_name"] isKindOfClass:NSString.class] ? info[@"full_name"] : nil;
	NSString *p = [info[@"profile_pic_url"] isKindOfClass:NSString.class] ? info[@"profile_pic_url"] : nil;
	if (!u.length && !fn.length && !p.length) return NO;

	return sciRewrite(ownerPK, YES, ^(NSMutableArray<SCIDeletedMessage *> *list, BOOL *changed) {
		for (SCIDeletedMessage *m in list) {
			if (![m.senderPk isEqualToString:senderPK]) continue;

			if (u.length && !m.senderUsername.length) {
				m.senderUsername = u;
				*changed = YES;
			}
			if (fn.length && !m.senderFullName.length) {
				m.senderFullName = fn;
				*changed = YES;
			}
			if (p.length && !m.senderProfilePicURL.length) {
				m.senderProfilePicURL = p;
				*changed = YES;
			}
		}
	});
}

+ (void)deleteMessageId:(NSString *)messageId forOwnerPK:(NSString *)ownerPK {
	if (!messageId.length) return;

	sciRewrite(ownerPK, YES, ^(NSMutableArray<SCIDeletedMessage *> *list, BOOL *changed) {
		for (NSInteger i = (NSInteger)list.count - 1; i >= 0; i--) {
			SCIDeletedMessage *m = list[i];
			if (![m.messageId isEqualToString:messageId]) continue;
			sciRemoveFiles(m, ownerPK);
			[list removeObjectAtIndex:(NSUInteger)i];
			*changed = YES;
		}
	});
}

+ (void)deleteMessagesForSenderPK:(NSString *)senderPK ownerPK:(NSString *)ownerPK {
	if (!senderPK.length) return;

	sciRewrite(ownerPK, YES, ^(NSMutableArray<SCIDeletedMessage *> *list, BOOL *changed) {
		for (NSInteger i = (NSInteger)list.count - 1; i >= 0; i--) {
			SCIDeletedMessage *m = list[i];
			if (![m.senderPk isEqualToString:senderPK]) continue;
			sciRemoveFiles(m, ownerPK);
			[list removeObjectAtIndex:(NSUInteger)i];
			*changed = YES;
		}
	});
}

+ (void)resetForOwnerPK:(NSString *)ownerPK {
	__block BOOL changed = NO;

	sciSync(^{
		NSString *json = sciJSON(ownerPK);
		NSString *media = sciMediaDir(ownerPK);

		changed = [sciFM() fileExistsAtPath:json] || [sciFM() fileExistsAtPath:media];
		[sciFM() removeItemAtPath:json error:nil];
		[sciFM() removeItemAtPath:media error:nil];
	});

	if (changed) sciPost(ownerPK);
}

+ (void)resetAll {
	__block BOOL changed = NO;

	sciSync(^{
		NSString *dir = sciStoreDir();
		changed = [sciFM() fileExistsAtPath:dir];
		[sciFM() removeItemAtPath:dir error:nil];
	});

	if (changed) sciPost(nil);
}

#pragma mark - Media

+ (NSString *)absolutePathForRelativePath:(NSString *)relativePath ownerPK:(NSString *)ownerPK {
	return sciAbs(relativePath, ownerPK);
}

+ (NSString *)reserveRelativeMediaPathForMessageId:(NSString *)messageId extension:(NSString *)ext ownerPK:(NSString *)ownerPK {
	NSString *safeId = sciClean(messageId, @"message");
	NSString *cleanExt = sciClean(ext.length ? ext : @"bin", @"bin");
	if ([cleanExt hasPrefix:@"."]) cleanExt = [cleanExt substringFromIndex:1];

	(void)sciMediaDir(ownerPK);
	return [NSString stringWithFormat:@"%@.%@", safeId, cleanExt.length ? cleanExt : @"bin"];
}

+ (unsigned long long)mediaSizeBytesForOwnerPK:(NSString *)ownerPK {
	__block unsigned long long total = 0;

	sciSync(^{
		NSDirectoryEnumerator *en = [sciFM() enumeratorAtPath:sciMediaDir(ownerPK)];
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