#import "RYGKeptMessageStore.h"
#import "../DeletedMessages/RYGDeletedMessagesStorage.h"
#import <UIKit/UIKit.h>

static NSString *const kSubDir = @"kept";
static NSUInteger const kMaxArchiveBytes = 512 * 1024;

@implementation RYGKeptMessageStore

static void *kQKey = &kQKey;
static dispatch_queue_t ioQ(void) {
	static dispatch_queue_t q; static dispatch_once_t once;
	dispatch_once(&once, ^{
		q = dispatch_queue_create("com.ryukgram.keptmessages.io", DISPATCH_QUEUE_SERIAL);
		dispatch_queue_set_specific(q, kQKey, kQKey, NULL);
	});
	return q;
}
static void ioSync(dispatch_block_t b) { dispatch_get_specific(kQKey) ? b() : dispatch_sync(ioQ(), b); }

static NSString *cleanComp(NSString *s, NSString *fallback) {
	if (!s.length) return fallback;

	NSMutableString *m = s.mutableCopy;
	NSCharacterSet *bad = [NSCharacterSet characterSetWithCharactersInString:@"/\\:?%*|\"<>"];

	for (NSUInteger i = 0; i < m.length; i++) {
		unichar c = [m characterAtIndex:i];
		if (c < 32 || [bad characterIsMember:c]) [m replaceCharactersInRange:NSMakeRange(i, 1) withString:@"_"];
	}

	return m.length ? m : fallback;
}

static NSString *owner(NSString *pk) { return cleanComp(pk, @"anon"); }

// Inside the deleted-messages store so both halves back up and reset as one.
static NSString *storeDir(void) {
	NSString *dir = [[RYGDeletedMessagesStorage storageDirectory] stringByAppendingPathComponent:kSubDir];

	[NSFileManager.defaultManager createDirectoryAtPath:dir withIntermediateDirectories:YES attributes:nil error:nil];

	static dispatch_once_t once;
	dispatch_once(&once, ^{
		NSFileManager *fm = NSFileManager.defaultManager;
		NSString *root = NSSearchPathForDirectoriesInDomains(NSApplicationSupportDirectory, NSUserDomainMask, YES).firstObject;
		NSString *legacy = [root stringByAppendingPathComponent:@"RyukGram/KeptMessages"];

		BOOL failed = NO;

		for (NSString *rel in [fm subpathsAtPath:legacy] ?: @[]) {
			NSString *src = [legacy stringByAppendingPathComponent:rel];
			NSString *dst = [dir stringByAppendingPathComponent:rel];

			BOOL srcIsDir = NO;
			if (![fm fileExistsAtPath:src isDirectory:&srcIsDir]) continue;

			if (srcIsDir) {
				[fm createDirectoryAtPath:dst withIntermediateDirectories:YES attributes:nil error:nil];
				continue;
			}

			if ([fm fileExistsAtPath:dst]) continue;
			if (![fm copyItemAtPath:src toPath:dst error:nil]) failed = YES;
		}

		if (!failed) [fm removeItemAtPath:legacy error:nil];
	});

	return dir;
}

static NSString *ownerDir(NSString *pk, BOOL create) {
	NSString *dir = [storeDir() stringByAppendingPathComponent:owner(pk)];
	if (create) [NSFileManager.defaultManager createDirectoryAtPath:dir withIntermediateDirectories:YES attributes:nil error:nil];
	return dir;
}

static NSString *archivePath(NSString *pk, NSString *sid, BOOL create) {
	return [ownerDir(pk, create) stringByAppendingPathComponent:[NSString stringWithFormat:@"%@.archive", cleanComp(sid, @"unknown")]];
}

static NSString *cacheKey(NSString *pk, NSString *sid) {
	return [NSString stringWithFormat:@"%@|%@", owner(pk), sid];
}

static NSMutableDictionary<NSString *, id> *sLoaded;
static NSMutableSet<NSString *> *sMissing;

+ (void)saveMessage:(id)message serverId:(NSString *)serverId ownerPK:(NSString *)ownerPK {
	if (!message || !serverId.length) return;

	NSString *key = cacheKey(ownerPK, serverId);
	if (sLoaded[key]) return;

	NSData *data = encodeObject(message);

	if (!data.length || data.length > kMaxArchiveBytes) return;

	if (!sLoaded) sLoaded = NSMutableDictionary.dictionary;
	sLoaded[key] = message;
	[sMissing removeObject:key];

	ioSync(^{ [data writeToFile:archivePath(ownerPK, serverId, YES) atomically:YES]; });
}

+ (id)messageForServerId:(NSString *)serverId ownerPK:(NSString *)ownerPK {
	if (!serverId.length) return nil;

	NSString *key = cacheKey(ownerPK, serverId);
	id cached = sLoaded[key];
	if (cached || [sMissing containsObject:key]) return cached;

	__block NSData *data = nil;
	ioSync(^{ data = [NSData dataWithContentsOfFile:archivePath(ownerPK, serverId, NO)]; });

	id message = decodeData(data);

	if (message) {
		if (!sLoaded) sLoaded = NSMutableDictionary.dictionary;
		sLoaded[key] = message;
	} else {
		if (!sMissing) sMissing = NSMutableSet.set;
		[sMissing addObject:key];
	}

	return message;
}

#pragma mark - History mirror

static NSString *const kMirrorSubDir = @"mirror";
static NSUInteger const kMaxMirroredPerThread = 400;
static NSUInteger const kMaxMirrorThreads = 60;

static NSMutableDictionary<NSString *, NSMutableDictionary<NSString *, id> *> *sMirrorByThread;
static NSMutableSet<NSString *> *sMirrorDirtyThreads;
static BOOL sMirrorFlushScheduled;

static NSString *mirrorDir(NSString *pk, BOOL create) {
	NSString *dir = [[storeDir() stringByAppendingPathComponent:kMirrorSubDir] stringByAppendingPathComponent:owner(pk)];
	if (create) [NSFileManager.defaultManager createDirectoryAtPath:dir withIntermediateDirectories:YES attributes:nil error:nil];
	return dir;
}

static NSString *mirrorFile(NSString *pk, NSString *threadId, BOOL create) {
	return [mirrorDir(pk, create) stringByAppendingPathComponent:
			[NSString stringWithFormat:@"%@.archive", cleanComp(threadId, @"unknown")]];
}

static NSData *encodeObject(id object) {
	@try {
		NSKeyedArchiver *archiver = [[NSKeyedArchiver alloc] initRequiringSecureCoding:NO];
		[archiver encodeObject:object forKey:NSKeyedArchiveRootObjectKey];
		[archiver finishEncoding];
		return archiver.encodedData;
	} @catch (__unused id e) {
		return nil;
	}
}

static id decodeData(NSData *data) {
	if (!data.length) return nil;

	@try {
		NSKeyedUnarchiver *unarchiver = [[NSKeyedUnarchiver alloc] initForReadingFromData:data error:nil];
		unarchiver.requiresSecureCoding = NO;
		id object = [unarchiver decodeObjectForKey:NSKeyedArchiveRootObjectKey];
		[unarchiver finishDecoding];
		return object;
	} @catch (__unused id e) {
		return nil;
	}
}

// Oldest thread files go first.
static void pruneMirrorFiles(NSString *pk) {
	NSFileManager *fm = NSFileManager.defaultManager;
	NSString *dir = mirrorDir(pk, NO);
	NSArray *names = [fm contentsOfDirectoryAtPath:dir error:nil];
	if (names.count <= kMaxMirrorThreads) return;

	NSArray *sorted = [names sortedArrayUsingComparator:^NSComparisonResult(NSString *a, NSString *b) {
		NSDate *da = [fm attributesOfItemAtPath:[dir stringByAppendingPathComponent:a] error:nil].fileModificationDate;
		NSDate *db = [fm attributesOfItemAtPath:[dir stringByAppendingPathComponent:b] error:nil].fileModificationDate;
		return [(da ?: NSDate.distantPast) compare:(db ?: NSDate.distantPast)];
	}];

	for (NSUInteger i = 0; i + kMaxMirrorThreads < sorted.count; i++) {
		[fm removeItemAtPath:[dir stringByAppendingPathComponent:sorted[i]] error:nil];
	}
}

+ (void)mirrorMessages:(NSDictionary<NSString *, id> *)messagesByServerId
			  threadId:(NSString *)threadId
			   ownerPK:(NSString *)ownerPK {
	if (!threadId.length || !messagesByServerId.count) return;

	NSString *key = cacheKey(ownerPK, threadId);
	if (!sMirrorByThread) {
		sMirrorByThread = NSMutableDictionary.dictionary;
		sMirrorDirtyThreads = NSMutableSet.set;
	}

	NSMutableDictionary *bucket = sMirrorByThread[key];
	if (!bucket) {
		bucket = [decodeData([NSData dataWithContentsOfFile:mirrorFile(ownerPK, threadId, NO)]) mutableCopy]
				 ?: NSMutableDictionary.dictionary;
		sMirrorByThread[key] = bucket;
	}

	NSUInteger before = bucket.count;
	for (NSString *sid in messagesByServerId) {
		if ([sid isKindOfClass:NSString.class] && !bucket[sid]) bucket[sid] = messagesByServerId[sid];
	}
	if (bucket.count == before) return;

	// Server ids sort chronologically, so the smallest are the oldest.
	if (bucket.count > kMaxMirroredPerThread) {
		NSArray *ordered = [bucket.allKeys sortedArrayUsingSelector:@selector(compare:)];
		for (NSUInteger i = 0; i + kMaxMirroredPerThread < ordered.count; i++) [bucket removeObjectForKey:ordered[i]];
	}

	[sMirrorDirtyThreads addObject:key];
	[self scheduleMirrorFlush];
}

+ (void)scheduleMirrorFlush {
	static dispatch_once_t once;
	dispatch_once(&once, ^{
		[NSNotificationCenter.defaultCenter addObserverForName:UIApplicationDidEnterBackgroundNotification
														object:nil
														 queue:nil
													usingBlock:^(__unused NSNotification *n) { [self flushMirror]; }];
	});

	if (sMirrorFlushScheduled) return;
	sMirrorFlushScheduled = YES;

	dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(15.0 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
		sMirrorFlushScheduled = NO;
		[self flushMirror];
	});
}

+ (void)flushMirror {
	if (!sMirrorDirtyThreads.count) return;

	NSArray<NSString *> *dirty = sMirrorDirtyThreads.allObjects;
	[sMirrorDirtyThreads removeAllObjects];

	NSMutableDictionary<NSString *, NSData *> *payloads = NSMutableDictionary.dictionary;
	for (NSString *key in dirty) {
		NSData *data = encodeObject(sMirrorByThread[key]);
		if (data.length) payloads[key] = data;
	}
	if (!payloads.count) return;

	ioSync(^{
		for (NSString *key in payloads) {
			NSArray<NSString *> *parts = [key componentsSeparatedByString:@"|"];
			if (parts.count != 2) continue;
			[payloads[key] writeToFile:mirrorFile(parts[0], parts[1], YES) atomically:YES];
		}
		pruneMirrorFiles([dirty.firstObject componentsSeparatedByString:@"|"].firstObject);
	});
}

+ (id)mirroredMessageForServerId:(NSString *)serverId ownerPK:(NSString *)ownerPK {
	if (!serverId.length) return nil;

	for (NSMutableDictionary *bucket in sMirrorByThread.allValues) {
		id message = bucket[serverId];
		if (message) return message;
	}

	__block NSArray *names = nil;
	NSString *dir = mirrorDir(ownerPK, NO);
	ioSync(^{ names = [NSFileManager.defaultManager contentsOfDirectoryAtPath:dir error:nil]; });

	for (NSString *name in names) {
		NSString *threadId = name.stringByDeletingPathExtension;
		NSString *key = cacheKey(ownerPK, threadId);
		if (sMirrorByThread[key]) continue;

		NSDictionary *bucket = decodeData([NSData dataWithContentsOfFile:[dir stringByAppendingPathComponent:name]]);
		if (!bucket.count) continue;

		if (!sMirrorByThread) sMirrorByThread = NSMutableDictionary.dictionary;
		sMirrorByThread[key] = [bucket mutableCopy];

		if (bucket[serverId]) return bucket[serverId];
	}

	return nil;
}

+ (void)resetMirror {
	sMirrorByThread = nil;
	sMirrorDirtyThreads = nil;

	ioSync(^{ [NSFileManager.defaultManager removeItemAtPath:[storeDir() stringByAppendingPathComponent:kMirrorSubDir] error:nil]; });
}

+ (void)resetAll {
	sLoaded = nil;
	sMissing = nil;
	sMirrorByThread = nil;
	sMirrorDirtyThreads = nil;

	ioSync(^{ [NSFileManager.defaultManager removeItemAtPath:storeDir() error:nil]; });
}

+ (void)resetForOwnerPK:(NSString *)ownerPK {
	NSString *prefix = [owner(ownerPK) stringByAppendingString:@"|"];

	for (NSString *key in sLoaded.allKeys) {
		if ([key hasPrefix:prefix]) [sLoaded removeObjectForKey:key];
	}
	for (NSString *key in sMissing.allObjects) {
		if ([key hasPrefix:prefix]) [sMissing removeObject:key];
	}

	ioSync(^{ [NSFileManager.defaultManager removeItemAtPath:ownerDir(ownerPK, NO) error:nil]; });
}

@end
