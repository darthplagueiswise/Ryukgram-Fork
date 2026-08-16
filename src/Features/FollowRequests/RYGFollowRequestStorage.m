#import "RYGFollowRequestStorage.h"

NSNotificationName const RYGFollowRequestsDidChangeNotification = @"RYGFollowRequestsDidChangeNotification";

static NSString *const kDir = @"RyukGram/FollowRequests";
static NSUInteger const kMaxRecordsPerOwner = 3000; // cull oldest beyond this

@implementation RYGFollowRequestStorage

static void *kQKey = &kQKey;
static dispatch_queue_t ioQ(void) {
	static dispatch_queue_t q; static dispatch_once_t once;
	dispatch_once(&once, ^{
		q = dispatch_queue_create("com.ryukgram.followrequests.io", DISPATCH_QUEUE_SERIAL);
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

static NSString *storeDir(void) {
	NSString *root = NSSearchPathForDirectoriesInDomains(NSApplicationSupportDirectory, NSUserDomainMask, YES).firstObject;
	NSString *dir = [root stringByAppendingPathComponent:kDir];
	[NSFileManager.defaultManager createDirectoryAtPath:dir withIntermediateDirectories:YES attributes:nil error:nil];
	return dir;
}
static NSString *fileFor(NSString *pk) { return [storeDir() stringByAppendingPathComponent:[NSString stringWithFormat:@"%@.json", owner(pk)]]; }
static NSString *stateFileFor(NSString *pk) { return [storeDir() stringByAppendingPathComponent:[NSString stringWithFormat:@"%@.state.json", owner(pk)]]; }

static NSMutableArray *readArray(NSString *path) {
	NSData *d = [NSData dataWithContentsOfFile:path];
	if (!d) return [NSMutableArray array];
	id j = [NSJSONSerialization JSONObjectWithData:d options:0 error:nil];
	return [j isKindOfClass:NSArray.class] ? [j mutableCopy] : [NSMutableArray array];
}
static void writeArray(NSArray *arr, NSString *path) {
	NSData *d = [NSJSONSerialization dataWithJSONObject:arr options:0 error:nil];
	[d writeToFile:path atomically:YES];
}
static NSMutableDictionary *readDict(NSString *path) {
	NSData *d = [NSData dataWithContentsOfFile:path];
	if (!d) return [NSMutableDictionary dictionary];
	id j = [NSJSONSerialization JSONObjectWithData:d options:0 error:nil];
	return [j isKindOfClass:NSDictionary.class] ? [j mutableCopy] : [NSMutableDictionary dictionary];
}
static void writeDict(NSDictionary *dict, NSString *path) {
	NSData *d = [NSJSONSerialization dataWithJSONObject:dict options:0 error:nil];
	[d writeToFile:path atomically:YES];
}
static void post(void) {
	dispatch_async(dispatch_get_main_queue(), ^{
		[NSNotificationCenter.defaultCenter postNotificationName:RYGFollowRequestsDidChangeNotification object:nil];
	});
}

+ (NSString *)storageDirectory { return storeDir(); }

#pragma mark - Read

+ (NSArray<RYGFollowRequest *> *)allForOwnerPK:(NSString *)ownerPK {
	__block NSMutableArray *out = [NSMutableArray array];
	ioSync(^{
		for (NSDictionary *d in readArray(fileFor(ownerPK))) {
			RYGFollowRequest *r = [RYGFollowRequest requestFromJSONDict:d];
			if (r.userPK) [out addObject:r];
		}
	});
	[out sortUsingComparator:^NSComparisonResult(RYGFollowRequest *a, RYGFollowRequest *b) {
		NSTimeInterval da = a.sortDate, db = b.sortDate;
		return da < db ? NSOrderedDescending : (da > db ? NSOrderedAscending : NSOrderedSame);
	}];
	return out;
}

+ (NSArray<NSString *> *)pendingTargetPKsForOwnerPK:(NSString *)ownerPK {
	NSMutableArray *pks = [NSMutableArray array];
	for (RYGFollowRequest *r in [self allForOwnerPK:ownerPK])
		if (r.type == RYGFollowRequestTypeSent && r.userPK.length && ![pks containsObject:r.userPK])
			[pks addObject:r.userPK];
	return pks;
}

+ (RYGFollowRequest *)latestPendingForTargetPK:(NSString *)targetPK ownerPK:(NSString *)ownerPK {
	for (RYGFollowRequest *r in [self allForOwnerPK:ownerPK]) // already newest-first
		if (r.type == RYGFollowRequestTypeSent && [r.userPK isEqualToString:targetPK]) return r;
	return nil;
}

+ (BOOL)restoreIncomingToReceivedForTargetPK:(NSString *)targetPK ownerPK:(NSString *)ownerPK {
	__block BOOL flipped = NO;
	ioSync(^{
		NSString *path = fileFor(ownerPK);
		NSMutableArray *arr = readArray(path);
		NSInteger best = -1; NSTimeInterval bestTs = -1;
		for (NSUInteger i = 0; i < arr.count; i++) {
			NSDictionary *d = arr[i];
			if (![d[@"userPK"] isEqualToString:targetPK]) continue;
			RYGFollowRequestType t = [d[@"type"] integerValue];
			if (t == RYGFollowRequestTypeReceived) return; // already pending, nothing to restore
			if (t != RYGFollowRequestTypeWithdrawn && t != RYGFollowRequestTypeApproved && t != RYGFollowRequestTypeIgnored) continue;
			NSTimeInterval ts = MAX([d[@"resolvedAt"] doubleValue], [d[@"sentAt"] doubleValue]);
			if (ts >= bestTs) { bestTs = ts; best = (NSInteger)i; }
		}
		if (best < 0) return;
		NSMutableDictionary *d = [arr[best] mutableCopy];
		d[@"type"] = @(RYGFollowRequestTypeReceived);
		d[@"resolvedAt"] = @0;
		arr[best] = d;
		writeArray(arr, path);
		flipped = YES;
	});
	if (flipped) post();
	return flipped;
}

#pragma mark - Write

+ (void)recordRequest:(RYGFollowRequest *)request forOwnerPK:(NSString *)ownerPK {
	if (!request.userPK.length) return;
	ioSync(^{
		NSString *path = fileFor(ownerPK);
		NSMutableArray *arr = readArray(path);
		if (!request.recordID.length) request.recordID = [NSUUID UUID].UUIDString;
		if (request.sentAt <= 0) request.sentAt = [NSDate date].timeIntervalSince1970;
		request.resolvedAt = 0;
		[arr insertObject:request.jsonDict atIndex:0];
		while (arr.count > kMaxRecordsPerOwner) [arr removeLastObject];
		writeArray(arr, path);
	});
	post();
}

+ (RYGFollowRequest *)resolveTargetPK:(NSString *)targetPK fromType:(RYGFollowRequestType)fromType toType:(RYGFollowRequestType)toType ownerPK:(NSString *)ownerPK {
	__block RYGFollowRequest *updated = nil;
	ioSync(^{
		NSString *path = fileFor(ownerPK);
		NSMutableArray *arr = readArray(path);
		NSInteger best = -1; NSTimeInterval bestTs = -1;
		for (NSUInteger i = 0; i < arr.count; i++) {
			NSDictionary *d = arr[i];
			if (![d[@"userPK"] isEqualToString:targetPK]) continue;
			if ([d[@"type"] integerValue] != fromType) continue;
			NSTimeInterval ts = [d[@"sentAt"] doubleValue];
			if (ts >= bestTs) { bestTs = ts; best = (NSInteger)i; }
		}
		if (best < 0) return;
		NSMutableDictionary *d = [arr[best] mutableCopy];
		d[@"type"] = @(toType);
		d[@"resolvedAt"] = @([NSDate date].timeIntervalSince1970);
		arr[best] = d;
		writeArray(arr, path);
		updated = [RYGFollowRequest requestFromJSONDict:d];
	});
	if (updated) post();
	return updated;
}

#pragma mark - Incoming state

+ (NSDictionary<NSString *, NSNumber *> *)incomingSnapshotForOwnerPK:(NSString *)ownerPK {
	__block NSDictionary *snap = nil;
	ioSync(^{ NSDictionary *s = readDict(stateFileFor(ownerPK))[@"incomingPending"]; snap = [s isKindOfClass:NSDictionary.class] ? s : @{}; });
	return snap ?: @{};
}

+ (void)setIncomingSnapshot:(NSDictionary<NSString *, NSNumber *> *)snapshot forOwnerPK:(NSString *)ownerPK {
	ioSync(^{
		NSMutableDictionary *root = readDict(stateFileFor(ownerPK));
		root[@"incomingPending"] = snapshot ?: @{};
		writeDict(root, stateFileFor(ownerPK));
	});
}

+ (BOOL)incomingSeededForOwnerPK:(NSString *)ownerPK {
	__block BOOL seeded = NO;
	ioSync(^{ seeded = [readDict(stateFileFor(ownerPK))[@"incomingSeeded"] boolValue]; });
	return seeded;
}

+ (void)setIncomingSeededForOwnerPK:(NSString *)ownerPK {
	ioSync(^{
		NSMutableDictionary *root = readDict(stateFileFor(ownerPK));
		root[@"incomingSeeded"] = @YES;
		writeDict(root, stateFileFor(ownerPK));
	});
}

+ (void)markIgnoredPK:(NSString *)pk ownerPK:(NSString *)ownerPK {
	if (!pk.length) return;
	ioSync(^{
		NSMutableDictionary *root = readDict(stateFileFor(ownerPK));
		NSMutableDictionary *ign = [root[@"ignored"] isKindOfClass:NSDictionary.class] ? [root[@"ignored"] mutableCopy] : [NSMutableDictionary dictionary];
		ign[pk] = @([NSDate date].timeIntervalSince1970);
		root[@"ignored"] = ign;
		writeDict(root, stateFileFor(ownerPK));
	});
}

+ (BOOL)consumeIgnoredPK:(NSString *)pk ownerPK:(NSString *)ownerPK {
	if (!pk.length) return NO;
	__block BOOL was = NO;
	ioSync(^{
		NSMutableDictionary *root = readDict(stateFileFor(ownerPK));
		NSMutableDictionary *ign = [root[@"ignored"] isKindOfClass:NSDictionary.class] ? [root[@"ignored"] mutableCopy] : nil;
		if (ign[pk]) { was = YES; [ign removeObjectForKey:pk]; root[@"ignored"] = ign; writeDict(root, stateFileFor(ownerPK)); }
	});
	return was;
}

#pragma mark - Unread

+ (NSUInteger)unreadCountForOwnerPK:(NSString *)ownerPK {
	__block NSTimeInterval lastSeen = 0;
	ioSync(^{ lastSeen = [readDict(stateFileFor(ownerPK))[@"lastSeenAt"] doubleValue]; });
	NSUInteger n = 0;
	for (RYGFollowRequest *r in [self allForOwnerPK:ownerPK]) if (r.sortDate > lastSeen) n++;
	return n;
}

+ (void)markAllSeenForOwnerPK:(NSString *)ownerPK {
	ioSync(^{
		NSMutableDictionary *root = readDict(stateFileFor(ownerPK));
		root[@"lastSeenAt"] = @([NSDate date].timeIntervalSince1970);
		writeDict(root, stateFileFor(ownerPK));
	});
	post();
}

+ (void)deleteRecordID:(NSString *)recordID ownerPK:(NSString *)ownerPK {
	if (!recordID.length) return;
	ioSync(^{
		NSString *path = fileFor(ownerPK);
		NSMutableArray *keep = [NSMutableArray array];
		for (NSDictionary *d in readArray(path)) if (![d[@"recordID"] isEqualToString:recordID]) [keep addObject:d];
		writeArray(keep, path);
	});
	post();
}

+ (void)resetForOwnerPK:(NSString *)ownerPK {
	ioSync(^{
		[NSFileManager.defaultManager removeItemAtPath:fileFor(ownerPK) error:nil];
		[NSFileManager.defaultManager removeItemAtPath:stateFileFor(ownerPK) error:nil];
	});
	post();
}

+ (void)resetAll {
	ioSync(^{
		NSString *dir = storeDir();
		for (NSString *f in [NSFileManager.defaultManager contentsOfDirectoryAtPath:dir error:nil])
			if ([f hasSuffix:@".json"]) [NSFileManager.defaultManager removeItemAtPath:[dir stringByAppendingPathComponent:f] error:nil];
	});
	post();
}

#pragma mark - Backup merge

+ (void)mergeImportedStoreAtPath:(NSString *)importedDir {
	ioSync(^{
		NSString *dest = storeDir();
		for (NSString *f in [NSFileManager.defaultManager contentsOfDirectoryAtPath:importedDir error:nil]) {
			if (![f hasSuffix:@".json"] || [f hasSuffix:@".state.json"]) continue; // state is rebuilt by polling
			NSMutableArray *mine = readArray([dest stringByAppendingPathComponent:f]);
			NSMutableSet *ids = [NSMutableSet set];
			for (NSDictionary *d in mine) if (d[@"recordID"]) [ids addObject:d[@"recordID"]];
			for (NSDictionary *d in readArray([importedDir stringByAppendingPathComponent:f]))
				if (d[@"recordID"] && ![ids containsObject:d[@"recordID"]]) { [mine addObject:d]; [ids addObject:d[@"recordID"]]; }
			[mine sortUsingComparator:^NSComparisonResult(NSDictionary *a, NSDictionary *b) {
				double da = MAX([a[@"resolvedAt"] doubleValue], [a[@"sentAt"] doubleValue]);
				double db = MAX([b[@"resolvedAt"] doubleValue], [b[@"sentAt"] doubleValue]);
				return da < db ? NSOrderedDescending : (da > db ? NSOrderedAscending : NSOrderedSame);
			}];
			while (mine.count > kMaxRecordsPerOwner) [mine removeLastObject];
			writeArray(mine, [dest stringByAppendingPathComponent:f]);
		}
	});
	post();
}

@end
