#import "RYGProfileAnalyzerStorage.h"

NSNotificationName const RYGProfileAnalyzerDataDidChangeNotification = @"RYGProfileAnalyzerDataDidChangeNotification";
NSString *const RYGProfileAnalyzerCompareSelectionPrevious = @"previous";

@implementation RYGProfileAnalyzerSnapshotMeta
@end

@implementation RYGProfileAnalyzerStorage

static NSString *const kRYGPAStorageDir = @"RyukGram/ProfileAnalyzer";

// Serial: racing record/refresh/remove writes would resurrect deleted entries.
static dispatch_queue_t rygVisitQueue(void) {
	static dispatch_queue_t q;
	static dispatch_once_t once;
	dispatch_once(&once, ^{
		q = dispatch_queue_create("com.ryukgram.profileanalyzer.visits", DISPATCH_QUEUE_SERIAL);
	});
	return q;
}

// IG payloads carry NSNull and NSJSONSerialization rejects it.
static id rygStripNull(id obj) {
	if ([obj isKindOfClass:[NSDictionary class]]) {
		NSMutableDictionary *out = [NSMutableDictionary dictionaryWithCapacity:[obj count]];
		for (id k in obj) {
			id v = obj[k];
			if (v && ![v isKindOfClass:[NSNull class]]) out[k] = rygStripNull(v);
		}
		return out;
	}
	if ([obj isKindOfClass:[NSArray class]]) {
		NSMutableArray *out = [NSMutableArray arrayWithCapacity:[obj count]];
		for (id v in obj) if (v && ![v isKindOfClass:[NSNull class]]) [out addObject:rygStripNull(v)];
		return out;
	}
	return obj;
}

static void rygPostDataChanged(NSString *userPK) {
	dispatch_async(dispatch_get_main_queue(), ^{
		[[NSNotificationCenter defaultCenter] postNotificationName:RYGProfileAnalyzerDataDidChangeNotification
															 object:nil
														   userInfo:userPK.length ? @{ @"user_pk": userPK } : @{}];
	});
}

static NSString *rygStorageDir(void) {
	NSArray *roots = NSSearchPathForDirectoriesInDomains(NSApplicationSupportDirectory, NSUserDomainMask, YES);
	NSString *dir = [roots.firstObject stringByAppendingPathComponent:kRYGPAStorageDir];
	[[NSFileManager defaultManager] createDirectoryAtPath:dir withIntermediateDirectories:YES attributes:nil error:nil];
	return dir;
}

+ (NSString *)storageDirectory { return rygStorageDir(); }

static NSString *rygPath(NSString *userPK, NSString *slot) {
	NSString *safePK = userPK.length ? userPK : @"anon";
	return [rygStorageDir() stringByAppendingPathComponent:
			[NSString stringWithFormat:@"%@.%@.json", safePK, slot]];
}

static NSDictionary *rygReadJSON(NSString *path) {
	NSData *data = [NSData dataWithContentsOfFile:path];
	if (!data.length) return nil;
	id obj = [NSJSONSerialization JSONObjectWithData:data options:0 error:nil];
	return [obj isKindOfClass:[NSDictionary class]] ? obj : nil;
}

static BOOL rygWriteJSON(NSString *path, NSDictionary *dict) {
	NSError *err = nil;
	id sanitized = rygStripNull(dict ?: @{});
	NSData *data = [NSJSONSerialization dataWithJSONObject:sanitized options:0 error:&err];
	if (!data) return NO;
	return [data writeToFile:path atomically:YES];
}

+ (RYGProfileAnalyzerSnapshot *)currentSnapshotForUserPK:(NSString *)userPK {
	return [RYGProfileAnalyzerSnapshot snapshotFromJSONDict:rygReadJSON(rygPath(userPK, @"current"))];
}

+ (RYGProfileAnalyzerSnapshot *)previousSnapshotForUserPK:(NSString *)userPK {
	return [RYGProfileAnalyzerSnapshot snapshotFromJSONDict:rygReadJSON(rygPath(userPK, @"previous"))];
}

+ (BOOL)saveSnapshot:(RYGProfileAnalyzerSnapshot *)snapshot forUserPK:(NSString *)userPK {
	if (!snapshot) return NO;
	NSString *cur = rygPath(userPK, @"current");
	NSString *prev = rygPath(userPK, @"previous");
	NSFileManager *fm = [NSFileManager defaultManager];
	if ([fm fileExistsAtPath:cur]) {
		[fm removeItemAtPath:prev error:nil];
		[fm moveItemAtPath:cur toPath:prev error:nil];
	}
	BOOL ok = rygWriteJSON(cur, [snapshot toJSONDict]);
	if (ok) rygPostDataChanged(userPK);
	return ok;
}

+ (BOOL)updateCurrentSnapshot:(RYGProfileAnalyzerSnapshot *)snapshot forUserPK:(NSString *)userPK {
	if (!snapshot) return NO;
	BOOL ok = rygWriteJSON(rygPath(userPK, @"current"), [snapshot toJSONDict]);
	if (ok) rygPostDataChanged(userPK);
	return ok;
}

+ (void)resetForUserPK:(NSString *)userPK {
	NSFileManager *fm = [NSFileManager defaultManager];
	[fm removeItemAtPath:rygPath(userPK, @"current") error:nil];
	[fm removeItemAtPath:rygPath(userPK, @"previous") error:nil];
	[fm removeItemAtPath:rygPath(userPK, @"baseline") error:nil];
	[fm removeItemAtPath:rygPath(userPK, @"seen") error:nil];
	[self clearHistoryForUserPK:userPK];
	rygPostDataChanged(userPK);
}

#pragma mark - Snapshot history

// `<pk>.snap.<id>.json` holds the body; one manifest tracks order, counts and the compare pick.
static NSString *rygSnapBodyPath(NSString *userPK, NSString *snapshotID) {
	NSString *safePK = userPK.length ? userPK : @"anon";
	return [rygStorageDir() stringByAppendingPathComponent:
			[NSString stringWithFormat:@"%@.snap.%@.json", safePK, snapshotID]];
}

static NSDictionary *rygHistoryManifest(NSString *userPK) {
	return rygReadJSON(rygPath(userPK, @"snaphistory")) ?: @{};
}

static NSArray *rygHistoryEntries(NSDictionary *manifest) {
	id list = manifest[@"snapshots"];
	return [list isKindOfClass:[NSArray class]] ? list : @[];
}

+ (NSArray<RYGProfileAnalyzerSnapshotMeta *> *)snapshotHistoryForUserPK:(NSString *)userPK {
	NSFileManager *fm = [NSFileManager defaultManager];
	NSMutableArray *out = [NSMutableArray array];
	for (NSDictionary *e in rygHistoryEntries(rygHistoryManifest(userPK))) {
		if (![e isKindOfClass:[NSDictionary class]]) continue;
		NSString *sid = [e[@"id"] isKindOfClass:[NSString class]] ? e[@"id"] : nil;
		if (!sid.length) continue;
		RYGProfileAnalyzerSnapshotMeta *m = [RYGProfileAnalyzerSnapshotMeta new];
		m.snapshotID = sid;
		m.scanDate = [NSDate dateWithTimeIntervalSince1970:[RYGJSONScalar(e[@"scan_date"]) doubleValue]];
		m.followerCount = [RYGJSONScalar(e[@"follower_count"]) integerValue];
		m.followingCount = [RYGJSONScalar(e[@"following_count"]) integerValue];
		m.mediaCount = [RYGJSONScalar(e[@"media_count"]) integerValue];
		NSDictionary *attrs = [fm attributesOfItemAtPath:rygSnapBodyPath(userPK, sid) error:nil];
		m.byteSize = attrs ? [attrs fileSize] : 0;
		[out addObject:m];
	}
	return out;
}

+ (NSString *)appendSnapshotToHistory:(RYGProfileAnalyzerSnapshot *)snapshot
                            forUserPK:(NSString *)userPK
                             capacity:(NSInteger)capacity {
	if (!snapshot) return nil;
	NSString *sid = [[NSUUID UUID] UUIDString];
	if (!rygWriteJSON(rygSnapBodyPath(userPK, sid), [snapshot toJSONDict])) return nil;

	NSDictionary *manifest = rygHistoryManifest(userPK);
	NSMutableArray *entries = [rygHistoryEntries(manifest) mutableCopy];
	[entries insertObject:@{
		@"id": sid,
		@"scan_date": @([snapshot.scanDate timeIntervalSince1970]),
		@"follower_count": @(snapshot.followerCount),
		@"following_count": @(snapshot.followingCount),
		@"media_count": @(snapshot.mediaCount),
	} atIndex:0];

	NSFileManager *fm = [NSFileManager defaultManager];
	if (capacity > 0) {
		while ((NSInteger)entries.count > capacity) {
			NSDictionary *drop = entries.lastObject;
			[entries removeLastObject];
			NSString *dropID = [drop[@"id"] isKindOfClass:[NSString class]] ? drop[@"id"] : nil;
			if (dropID.length) [fm removeItemAtPath:rygSnapBodyPath(userPK, dropID) error:nil];
		}
	}

	NSMutableDictionary *out = [manifest mutableCopy];
	out[@"snapshots"] = entries;
	rygWriteJSON(rygPath(userPK, @"snaphistory"), out);
	rygPostDataChanged(userPK);
	return sid;
}

+ (RYGProfileAnalyzerSnapshot *)historySnapshotWithID:(NSString *)snapshotID forUserPK:(NSString *)userPK {
	if (!snapshotID.length) return nil;
	return [RYGProfileAnalyzerSnapshot snapshotFromJSONDict:rygReadJSON(rygSnapBodyPath(userPK, snapshotID))];
}

+ (void)deleteHistorySnapshotIDs:(NSArray<NSString *> *)ids forUserPK:(NSString *)userPK {
	if (!ids.count) return;
	NSSet *drop = [NSSet setWithArray:ids];
	NSFileManager *fm = [NSFileManager defaultManager];
	NSDictionary *manifest = rygHistoryManifest(userPK);
	NSMutableArray *kept = [NSMutableArray array];
	for (NSDictionary *e in rygHistoryEntries(manifest)) {
		NSString *sid = [e[@"id"] isKindOfClass:[NSString class]] ? e[@"id"] : nil;
		if (sid.length && [drop containsObject:sid]) {
			[fm removeItemAtPath:rygSnapBodyPath(userPK, sid) error:nil];
		} else if ([e isKindOfClass:[NSDictionary class]]) {
			[kept addObject:e];
		}
	}
	NSMutableDictionary *out = [manifest mutableCopy];
	out[@"snapshots"] = kept;
	// Drop a dangling compare selection so the next scan falls back to "previous".
	NSString *sel = [out[@"compare"] isKindOfClass:[NSString class]] ? out[@"compare"] : nil;
	if (sel.length && [drop containsObject:sel]) [out removeObjectForKey:@"compare"];
	rygWriteJSON(rygPath(userPK, @"snaphistory"), out);
	rygPostDataChanged(userPK);
}

+ (void)clearHistoryForUserPK:(NSString *)userPK {
	NSFileManager *fm = [NSFileManager defaultManager];
	for (NSDictionary *e in rygHistoryEntries(rygHistoryManifest(userPK))) {
		NSString *sid = [e[@"id"] isKindOfClass:[NSString class]] ? e[@"id"] : nil;
		if (sid.length) [fm removeItemAtPath:rygSnapBodyPath(userPK, sid) error:nil];
	}
	[fm removeItemAtPath:rygPath(userPK, @"snaphistory") error:nil];
	rygPostDataChanged(userPK);
}

+ (unsigned long long)historyByteSizeForUserPK:(NSString *)userPK {
	NSFileManager *fm = [NSFileManager defaultManager];
	unsigned long long total = 0;
	for (NSDictionary *e in rygHistoryEntries(rygHistoryManifest(userPK))) {
		NSString *sid = [e[@"id"] isKindOfClass:[NSString class]] ? e[@"id"] : nil;
		if (!sid.length) continue;
		NSDictionary *attrs = [fm attributesOfItemAtPath:rygSnapBodyPath(userPK, sid) error:nil];
		if (attrs) total += [attrs fileSize];
	}
	return total;
}

+ (NSString *)compareSelectionForUserPK:(NSString *)userPK {
	id sel = rygHistoryManifest(userPK)[@"compare"];
	return [sel isKindOfClass:[NSString class]] && [sel length] ? sel : nil;
}

+ (void)setCompareSelection:(NSString *)selection forUserPK:(NSString *)userPK {
	NSMutableDictionary *out = [rygHistoryManifest(userPK) mutableCopy];
	if (selection.length) out[@"compare"] = selection;
	else [out removeObjectForKey:@"compare"];
	rygWriteJSON(rygPath(userPK, @"snaphistory"), out);
	rygPostDataChanged(userPK);
}

#pragma mark - Unread tracking

+ (NSArray<NSString *> *)seenIDsForUserPK:(NSString *)userPK categoryKey:(NSString *)key {
	if (!key.length) return nil;
	NSDictionary *root = rygReadJSON(rygPath(userPK, @"seen"));
	NSDictionary *cats = [root[@"categories"] isKindOfClass:[NSDictionary class]] ? root[@"categories"] : nil;
	id v = cats[key];
	return [v isKindOfClass:[NSArray class]] ? v : nil;
}

+ (void)markSeenIDs:(NSArray<NSString *> *)ids forUserPK:(NSString *)userPK categoryKey:(NSString *)key {
	if (!key.length) return;
	NSDictionary *root = rygReadJSON(rygPath(userPK, @"seen"));
	NSMutableDictionary *cats = [([root[@"categories"] isKindOfClass:[NSDictionary class]] ? root[@"categories"] : @{}) mutableCopy];
	cats[key] = ids ?: @[];
	rygWriteJSON(rygPath(userPK, @"seen"), @{ @"categories": cats });
}

#pragma mark - Visited profiles

+ (NSArray<RYGProfileAnalyzerVisit *> *)visitedProfilesForUserPK:(NSString *)userPK {
	__block NSArray *result = @[];
	dispatch_sync(rygVisitQueue(), ^{
		NSDictionary *root = rygReadJSON(rygPath(userPK, @"visits"));
		NSArray *list = root[@"visits"];
		if (![list isKindOfClass:[NSArray class]]) return;
		NSMutableArray *out = [NSMutableArray arrayWithCapacity:list.count];
		for (NSDictionary *d in list) {
			if (![d isKindOfClass:[NSDictionary class]]) continue;
			RYGProfileAnalyzerVisit *v = [RYGProfileAnalyzerVisit visitFromJSONDict:d];
			if (v) [out addObject:v];
		}
		result = out;
	});
	return result;
}

// Locate a visit entry by pk with type-safe lookups; NSNotFound when absent.
static NSInteger rygVisitIndexForPK(NSArray *list, NSString *pk) {
	if (!pk.length) return NSNotFound;
	for (NSInteger i = 0; i < (NSInteger)list.count; i++) {
		id entry = list[i];
		if (![entry isKindOfClass:[NSDictionary class]]) continue;
		id u = entry[@"user"];
		if (![u isKindOfClass:[NSDictionary class]]) continue;
		id storedPK = u[@"pk"];
		if (![storedPK isKindOfClass:[NSString class]]) continue;
		if ([(NSString *)storedPK isEqualToString:pk]) return i;
	}
	return NSNotFound;
}

+ (void)recordVisitForUser:(RYGProfileAnalyzerUser *)user forUserPK:(NSString *)userPK {
	if (!user.pk.length) return;
	dispatch_sync(rygVisitQueue(), ^{
	NSDictionary *root = rygReadJSON(rygPath(userPK, @"visits"));
	NSMutableArray *list = [(root[@"visits"] ?: @[]) mutableCopy];

	NSDate *now = [NSDate date];
	NSInteger foundIdx = rygVisitIndexForPK(list, user.pk);
	if (foundIdx == NSNotFound) {
		RYGProfileAnalyzerVisit *v = [RYGProfileAnalyzerVisit new];
		v.user = user;
		v.firstSeen = now;
		v.lastSeen = now;
		v.visitCount = 1;
		[list insertObject:[v toJSONDict] atIndex:0];
	} else {
		// A half-loaded fieldCache must not clobber known-good fields; booleans only flip on.
		NSMutableDictionary *d = [list[foundIdx] mutableCopy];
		NSDictionary *prevUser = [d[@"user"] isKindOfClass:[NSDictionary class]] ? d[@"user"] : @{};
		NSMutableDictionary *merged = [prevUser mutableCopy];
		NSDictionary *fresh = [user toJSONDict];
		for (NSString *k in @[@"pk", @"username", @"full_name", @"profile_pic_url", @"profile_pic_id"]) {
			id v = fresh[k];
			if ([v isKindOfClass:[NSString class]] && [(NSString *)v length]) merged[k] = v;
		}
		if ([fresh[@"is_verified"] boolValue]) merged[@"is_verified"] = @YES;
		if ([fresh[@"is_private"]  boolValue]) merged[@"is_private"]  = @YES;

		d[@"user"] = merged;
		d[@"last_seen"] = @([now timeIntervalSince1970]);
		d[@"visit_count"] = @([RYGJSONScalar(d[@"visit_count"]) integerValue] + 1);
		[list removeObjectAtIndex:foundIdx];
		[list insertObject:d atIndex:0];   // most-recent first
	}
	rygWriteJSON(rygPath(userPK, @"visits"), @{ @"visits": list });
	rygPostDataChanged(userPK);
	});
}

+ (void)removeVisitForUserPK:(NSString *)userPK visitedPK:(NSString *)visitedPK {
	if (!visitedPK.length) return;
	dispatch_sync(rygVisitQueue(), ^{
		NSDictionary *root = rygReadJSON(rygPath(userPK, @"visits"));
		NSMutableArray *list = [(root[@"visits"] ?: @[]) mutableCopy];
		NSInteger removeIdx = rygVisitIndexForPK(list, visitedPK);
		if (removeIdx == NSNotFound) return;
		[list removeObjectAtIndex:removeIdx];
		rygWriteJSON(rygPath(userPK, @"visits"), @{ @"visits": list });
		rygPostDataChanged(userPK);
	});
}

+ (void)clearVisitsForUserPK:(NSString *)userPK {
	dispatch_sync(rygVisitQueue(), ^{
		[[NSFileManager defaultManager] removeItemAtPath:rygPath(userPK, @"visits") error:nil];
		rygPostDataChanged(userPK);
	});
}

+ (void)refreshVisitedUser:(RYGProfileAnalyzerUser *)user forUserPK:(NSString *)userPK {
	if (!user.pk.length) return;
	dispatch_sync(rygVisitQueue(), ^{
		NSDictionary *root = rygReadJSON(rygPath(userPK, @"visits"));
		NSMutableArray *list = [(root[@"visits"] ?: @[]) mutableCopy];
		NSInteger idx = rygVisitIndexForPK(list, user.pk);
		if (idx == NSNotFound) return;   // deleted between trigger + write
		NSMutableDictionary *d = [list[idx] mutableCopy];
		d[@"user"] = [user toJSONDict];
		list[idx] = d;
		rygWriteJSON(rygPath(userPK, @"visits"), @{ @"visits": list });
	});
}

+ (void)resetAll {
	[[NSFileManager defaultManager] removeItemAtPath:rygStorageDir() error:nil];
	rygPostDataChanged(nil);
}

+ (NSDictionary *)headerInfoForUserPK:(NSString *)userPK {
	return rygReadJSON(rygPath(userPK, @"header"));
}

+ (void)saveHeaderInfo:(NSDictionary *)info forUserPK:(NSString *)userPK {
	if (!info.count) return;
	NSMutableDictionary *stored = [info mutableCopy];
	stored[@"cached_at"] = @([[NSDate date] timeIntervalSince1970]);
	rygWriteJSON(rygPath(userPK, @"header"), stored);
}

+ (NSDictionary *)exportedDict {
	NSMutableDictionary *out = [NSMutableDictionary dictionary];
	NSFileManager *fm = [NSFileManager defaultManager];
	for (NSString *name in [fm contentsOfDirectoryAtPath:rygStorageDir() error:nil]) {
		NSDictionary *d = rygReadJSON([rygStorageDir() stringByAppendingPathComponent:name]);
		if (d) out[name] = d;
	}
	return out;
}

+ (BOOL)importFromDict:(NSDictionary *)dict {
	if (![dict isKindOfClass:[NSDictionary class]] || !dict.count) return NO;
	[self resetAll];
	NSString *dir = rygStorageDir();
	for (NSString *name in dict) {
		if (![name hasSuffix:@".json"]) continue;
		NSDictionary *d = dict[name];
		if (![d isKindOfClass:[NSDictionary class]]) continue;
		rygWriteJSON([dir stringByAppendingPathComponent:name], d);
	}
	return YES;
}

@end
