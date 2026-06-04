#import "SCIProfileAnalyzerStorage.h"

NSNotificationName const SCIProfileAnalyzerDataDidChangeNotification = @"SCIProfileAnalyzerDataDidChangeNotification";
NSString *const SCIProfileAnalyzerCompareSelectionPrevious = @"previous";

@implementation SCIProfileAnalyzerSnapshotMeta
@end

@implementation SCIProfileAnalyzerStorage

static NSString *const kSCIPAStorageDir = @"RyukGram/ProfileAnalyzer";

// Serial queue for visit-list reads + writes — prevents racing record / refresh
// / remove writes from resurrecting deleted entries.
static dispatch_queue_t sciVisitQueue(void) {
	static dispatch_queue_t q;
	static dispatch_once_t once;
	dispatch_once(&once, ^{
		q = dispatch_queue_create("com.ryukgram.profileanalyzer.visits", DISPATCH_QUEUE_SERIAL);
	});
	return q;
}

// Strip NSNull recursively — NSJSONSerialization rejects it and IG payloads carry it.
static id sciStripNull(id obj) {
	if ([obj isKindOfClass:[NSDictionary class]]) {
		NSMutableDictionary *out = [NSMutableDictionary dictionaryWithCapacity:[obj count]];
		for (id k in obj) {
			id v = obj[k];
			if (v && ![v isKindOfClass:[NSNull class]]) out[k] = sciStripNull(v);
		}
		return out;
	}
	if ([obj isKindOfClass:[NSArray class]]) {
		NSMutableArray *out = [NSMutableArray arrayWithCapacity:[obj count]];
		for (id v in obj) if (v && ![v isKindOfClass:[NSNull class]]) [out addObject:sciStripNull(v)];
		return out;
	}
	return obj;
}

static void sciPostDataChanged(NSString *userPK) {
	dispatch_async(dispatch_get_main_queue(), ^{
		[[NSNotificationCenter defaultCenter] postNotificationName:SCIProfileAnalyzerDataDidChangeNotification
															 object:nil
														   userInfo:userPK.length ? @{ @"user_pk": userPK } : @{}];
	});
}

static NSString *sciStorageDir(void) {
	NSArray *roots = NSSearchPathForDirectoriesInDomains(NSApplicationSupportDirectory, NSUserDomainMask, YES);
	NSString *dir = [roots.firstObject stringByAppendingPathComponent:kSCIPAStorageDir];
	[[NSFileManager defaultManager] createDirectoryAtPath:dir withIntermediateDirectories:YES attributes:nil error:nil];
	return dir;
}

static NSString *sciPath(NSString *userPK, NSString *slot) {
	NSString *safePK = userPK.length ? userPK : @"anon";
	return [sciStorageDir() stringByAppendingPathComponent:
			[NSString stringWithFormat:@"%@.%@.json", safePK, slot]];
}

static NSDictionary *sciReadJSON(NSString *path) {
	NSData *data = [NSData dataWithContentsOfFile:path];
	if (!data.length) return nil;
	id obj = [NSJSONSerialization JSONObjectWithData:data options:0 error:nil];
	return [obj isKindOfClass:[NSDictionary class]] ? obj : nil;
}

static BOOL sciWriteJSON(NSString *path, NSDictionary *dict) {
	NSError *err = nil;
	id sanitized = sciStripNull(dict ?: @{});
	NSData *data = [NSJSONSerialization dataWithJSONObject:sanitized options:0 error:&err];
	if (!data) return NO;
	return [data writeToFile:path atomically:YES];
}

+ (SCIProfileAnalyzerSnapshot *)currentSnapshotForUserPK:(NSString *)userPK {
	return [SCIProfileAnalyzerSnapshot snapshotFromJSONDict:sciReadJSON(sciPath(userPK, @"current"))];
}

+ (SCIProfileAnalyzerSnapshot *)previousSnapshotForUserPK:(NSString *)userPK {
	return [SCIProfileAnalyzerSnapshot snapshotFromJSONDict:sciReadJSON(sciPath(userPK, @"previous"))];
}

+ (BOOL)saveSnapshot:(SCIProfileAnalyzerSnapshot *)snapshot forUserPK:(NSString *)userPK {
	if (!snapshot) return NO;
	NSString *cur = sciPath(userPK, @"current");
	NSString *prev = sciPath(userPK, @"previous");
	NSFileManager *fm = [NSFileManager defaultManager];
	if ([fm fileExistsAtPath:cur]) {
		[fm removeItemAtPath:prev error:nil];
		[fm moveItemAtPath:cur toPath:prev error:nil];
	}
	BOOL ok = sciWriteJSON(cur, [snapshot toJSONDict]);
	if (ok) sciPostDataChanged(userPK);
	return ok;
}

+ (BOOL)updateCurrentSnapshot:(SCIProfileAnalyzerSnapshot *)snapshot forUserPK:(NSString *)userPK {
	if (!snapshot) return NO;
	BOOL ok = sciWriteJSON(sciPath(userPK, @"current"), [snapshot toJSONDict]);
	if (ok) sciPostDataChanged(userPK);
	return ok;
}

+ (void)resetForUserPK:(NSString *)userPK {
	NSFileManager *fm = [NSFileManager defaultManager];
	[fm removeItemAtPath:sciPath(userPK, @"current") error:nil];
	[fm removeItemAtPath:sciPath(userPK, @"previous") error:nil];
	[fm removeItemAtPath:sciPath(userPK, @"baseline") error:nil];
	[fm removeItemAtPath:sciPath(userPK, @"seen") error:nil];
	[self clearHistoryForUserPK:userPK];
	sciPostDataChanged(userPK);
}

#pragma mark - Snapshot history

// `<pk>.snap.<id>.json` holds a full snapshot body; one shared manifest tracks
// order + lightweight counts + the compare selection.
static NSString *sciSnapBodyPath(NSString *userPK, NSString *snapshotID) {
	NSString *safePK = userPK.length ? userPK : @"anon";
	return [sciStorageDir() stringByAppendingPathComponent:
			[NSString stringWithFormat:@"%@.snap.%@.json", safePK, snapshotID]];
}

static NSDictionary *sciHistoryManifest(NSString *userPK) {
	return sciReadJSON(sciPath(userPK, @"snaphistory")) ?: @{};
}

static NSArray *sciHistoryEntries(NSDictionary *manifest) {
	id list = manifest[@"snapshots"];
	return [list isKindOfClass:[NSArray class]] ? list : @[];
}

+ (NSArray<SCIProfileAnalyzerSnapshotMeta *> *)snapshotHistoryForUserPK:(NSString *)userPK {
	NSFileManager *fm = [NSFileManager defaultManager];
	NSMutableArray *out = [NSMutableArray array];
	for (NSDictionary *e in sciHistoryEntries(sciHistoryManifest(userPK))) {
		if (![e isKindOfClass:[NSDictionary class]]) continue;
		NSString *sid = [e[@"id"] isKindOfClass:[NSString class]] ? e[@"id"] : nil;
		if (!sid.length) continue;
		SCIProfileAnalyzerSnapshotMeta *m = [SCIProfileAnalyzerSnapshotMeta new];
		m.snapshotID = sid;
		m.scanDate = [NSDate dateWithTimeIntervalSince1970:[e[@"scan_date"] doubleValue]];
		m.followerCount = [e[@"follower_count"] integerValue];
		m.followingCount = [e[@"following_count"] integerValue];
		m.mediaCount = [e[@"media_count"] integerValue];
		NSDictionary *attrs = [fm attributesOfItemAtPath:sciSnapBodyPath(userPK, sid) error:nil];
		m.byteSize = attrs ? [attrs fileSize] : 0;
		[out addObject:m];
	}
	return out;
}

+ (NSString *)appendSnapshotToHistory:(SCIProfileAnalyzerSnapshot *)snapshot
                            forUserPK:(NSString *)userPK
                             capacity:(NSInteger)capacity {
	if (!snapshot) return nil;
	NSString *sid = [[NSUUID UUID] UUIDString];
	if (!sciWriteJSON(sciSnapBodyPath(userPK, sid), [snapshot toJSONDict])) return nil;

	NSDictionary *manifest = sciHistoryManifest(userPK);
	NSMutableArray *entries = [sciHistoryEntries(manifest) mutableCopy];
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
			if (dropID.length) [fm removeItemAtPath:sciSnapBodyPath(userPK, dropID) error:nil];
		}
	}

	NSMutableDictionary *out = [manifest mutableCopy];
	out[@"snapshots"] = entries;
	sciWriteJSON(sciPath(userPK, @"snaphistory"), out);
	sciPostDataChanged(userPK);
	return sid;
}

+ (SCIProfileAnalyzerSnapshot *)historySnapshotWithID:(NSString *)snapshotID forUserPK:(NSString *)userPK {
	if (!snapshotID.length) return nil;
	return [SCIProfileAnalyzerSnapshot snapshotFromJSONDict:sciReadJSON(sciSnapBodyPath(userPK, snapshotID))];
}

+ (void)deleteHistorySnapshotIDs:(NSArray<NSString *> *)ids forUserPK:(NSString *)userPK {
	if (!ids.count) return;
	NSSet *drop = [NSSet setWithArray:ids];
	NSFileManager *fm = [NSFileManager defaultManager];
	NSDictionary *manifest = sciHistoryManifest(userPK);
	NSMutableArray *kept = [NSMutableArray array];
	for (NSDictionary *e in sciHistoryEntries(manifest)) {
		NSString *sid = [e[@"id"] isKindOfClass:[NSString class]] ? e[@"id"] : nil;
		if (sid.length && [drop containsObject:sid]) {
			[fm removeItemAtPath:sciSnapBodyPath(userPK, sid) error:nil];
		} else if ([e isKindOfClass:[NSDictionary class]]) {
			[kept addObject:e];
		}
	}
	NSMutableDictionary *out = [manifest mutableCopy];
	out[@"snapshots"] = kept;
	// Drop a dangling compare selection so the next scan falls back to "previous".
	NSString *sel = [out[@"compare"] isKindOfClass:[NSString class]] ? out[@"compare"] : nil;
	if (sel.length && [drop containsObject:sel]) [out removeObjectForKey:@"compare"];
	sciWriteJSON(sciPath(userPK, @"snaphistory"), out);
	sciPostDataChanged(userPK);
}

+ (void)clearHistoryForUserPK:(NSString *)userPK {
	NSFileManager *fm = [NSFileManager defaultManager];
	for (NSDictionary *e in sciHistoryEntries(sciHistoryManifest(userPK))) {
		NSString *sid = [e[@"id"] isKindOfClass:[NSString class]] ? e[@"id"] : nil;
		if (sid.length) [fm removeItemAtPath:sciSnapBodyPath(userPK, sid) error:nil];
	}
	[fm removeItemAtPath:sciPath(userPK, @"snaphistory") error:nil];
	sciPostDataChanged(userPK);
}

+ (unsigned long long)historyByteSizeForUserPK:(NSString *)userPK {
	NSFileManager *fm = [NSFileManager defaultManager];
	unsigned long long total = 0;
	for (NSDictionary *e in sciHistoryEntries(sciHistoryManifest(userPK))) {
		NSString *sid = [e[@"id"] isKindOfClass:[NSString class]] ? e[@"id"] : nil;
		if (!sid.length) continue;
		NSDictionary *attrs = [fm attributesOfItemAtPath:sciSnapBodyPath(userPK, sid) error:nil];
		if (attrs) total += [attrs fileSize];
	}
	return total;
}

+ (NSString *)compareSelectionForUserPK:(NSString *)userPK {
	id sel = sciHistoryManifest(userPK)[@"compare"];
	return [sel isKindOfClass:[NSString class]] && [sel length] ? sel : nil;
}

+ (void)setCompareSelection:(NSString *)selection forUserPK:(NSString *)userPK {
	NSMutableDictionary *out = [sciHistoryManifest(userPK) mutableCopy];
	if (selection.length) out[@"compare"] = selection;
	else [out removeObjectForKey:@"compare"];
	sciWriteJSON(sciPath(userPK, @"snaphistory"), out);
	sciPostDataChanged(userPK);
}

#pragma mark - Unread tracking

+ (NSArray<NSString *> *)seenIDsForUserPK:(NSString *)userPK categoryKey:(NSString *)key {
	if (!key.length) return nil;
	NSDictionary *root = sciReadJSON(sciPath(userPK, @"seen"));
	NSDictionary *cats = [root[@"categories"] isKindOfClass:[NSDictionary class]] ? root[@"categories"] : nil;
	id v = cats[key];
	return [v isKindOfClass:[NSArray class]] ? v : nil;
}

+ (void)markSeenIDs:(NSArray<NSString *> *)ids forUserPK:(NSString *)userPK categoryKey:(NSString *)key {
	if (!key.length) return;
	NSDictionary *root = sciReadJSON(sciPath(userPK, @"seen"));
	NSMutableDictionary *cats = [([root[@"categories"] isKindOfClass:[NSDictionary class]] ? root[@"categories"] : @{}) mutableCopy];
	cats[key] = ids ?: @[];
	sciWriteJSON(sciPath(userPK, @"seen"), @{ @"categories": cats });
}

#pragma mark - Visited profiles

+ (NSArray<SCIProfileAnalyzerVisit *> *)visitedProfilesForUserPK:(NSString *)userPK {
	__block NSArray *result = @[];
	dispatch_sync(sciVisitQueue(), ^{
		NSDictionary *root = sciReadJSON(sciPath(userPK, @"visits"));
		NSArray *list = root[@"visits"];
		if (![list isKindOfClass:[NSArray class]]) return;
		NSMutableArray *out = [NSMutableArray arrayWithCapacity:list.count];
		for (NSDictionary *d in list) {
			if (![d isKindOfClass:[NSDictionary class]]) continue;
			SCIProfileAnalyzerVisit *v = [SCIProfileAnalyzerVisit visitFromJSONDict:d];
			if (v) [out addObject:v];
		}
		result = out;
	});
	return result;
}

// Locate a visit entry by pk with type-safe lookups; NSNotFound when absent.
static NSInteger sciVisitIndexForPK(NSArray *list, NSString *pk) {
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

+ (void)recordVisitForUser:(SCIProfileAnalyzerUser *)user forUserPK:(NSString *)userPK {
	if (!user.pk.length) return;
	dispatch_sync(sciVisitQueue(), ^{
	NSDictionary *root = sciReadJSON(sciPath(userPK, @"visits"));
	NSMutableArray *list = [(root[@"visits"] ?: @[]) mutableCopy];

	NSDate *now = [NSDate date];
	NSInteger foundIdx = sciVisitIndexForPK(list, user.pk);
	if (foundIdx == NSNotFound) {
		SCIProfileAnalyzerVisit *v = [SCIProfileAnalyzerVisit new];
		v.user = user;
		v.firstSeen = now;
		v.lastSeen = now;
		v.visitCount = 1;
		[list insertObject:[v toJSONDict] atIndex:0];
	} else {
		// Merge: don't clobber known-good fields with empty values from a
		// half-loaded fieldCache. Booleans only flip on, never off.
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
		d[@"visit_count"] = @([d[@"visit_count"] integerValue] + 1);
		[list removeObjectAtIndex:foundIdx];
		[list insertObject:d atIndex:0];   // most-recent first
	}
	sciWriteJSON(sciPath(userPK, @"visits"), @{ @"visits": list });
	sciPostDataChanged(userPK);
	});
}

+ (void)removeVisitForUserPK:(NSString *)userPK visitedPK:(NSString *)visitedPK {
	if (!visitedPK.length) return;
	dispatch_sync(sciVisitQueue(), ^{
		NSDictionary *root = sciReadJSON(sciPath(userPK, @"visits"));
		NSMutableArray *list = [(root[@"visits"] ?: @[]) mutableCopy];
		NSInteger removeIdx = sciVisitIndexForPK(list, visitedPK);
		if (removeIdx == NSNotFound) return;
		[list removeObjectAtIndex:removeIdx];
		sciWriteJSON(sciPath(userPK, @"visits"), @{ @"visits": list });
		sciPostDataChanged(userPK);
	});
}

+ (void)clearVisitsForUserPK:(NSString *)userPK {
	dispatch_sync(sciVisitQueue(), ^{
		[[NSFileManager defaultManager] removeItemAtPath:sciPath(userPK, @"visits") error:nil];
		sciPostDataChanged(userPK);
	});
}

+ (void)refreshVisitedUser:(SCIProfileAnalyzerUser *)user forUserPK:(NSString *)userPK {
	if (!user.pk.length) return;
	dispatch_sync(sciVisitQueue(), ^{
		NSDictionary *root = sciReadJSON(sciPath(userPK, @"visits"));
		NSMutableArray *list = [(root[@"visits"] ?: @[]) mutableCopy];
		NSInteger idx = sciVisitIndexForPK(list, user.pk);
		if (idx == NSNotFound) return;   // deleted between trigger + write
		NSMutableDictionary *d = [list[idx] mutableCopy];
		d[@"user"] = [user toJSONDict];
		list[idx] = d;
		sciWriteJSON(sciPath(userPK, @"visits"), @{ @"visits": list });
	});
}

+ (void)resetAll {
	[[NSFileManager defaultManager] removeItemAtPath:sciStorageDir() error:nil];
	sciPostDataChanged(nil);
}

+ (NSDictionary *)headerInfoForUserPK:(NSString *)userPK {
	return sciReadJSON(sciPath(userPK, @"header"));
}

+ (void)saveHeaderInfo:(NSDictionary *)info forUserPK:(NSString *)userPK {
	if (!info.count) return;
	NSMutableDictionary *stored = [info mutableCopy];
	stored[@"cached_at"] = @([[NSDate date] timeIntervalSince1970]);
	sciWriteJSON(sciPath(userPK, @"header"), stored);
}

+ (NSDictionary *)exportedDict {
	NSMutableDictionary *out = [NSMutableDictionary dictionary];
	NSFileManager *fm = [NSFileManager defaultManager];
	for (NSString *name in [fm contentsOfDirectoryAtPath:sciStorageDir() error:nil]) {
		NSDictionary *d = sciReadJSON([sciStorageDir() stringByAppendingPathComponent:name]);
		if (d) out[name] = d;
	}
	return out;
}

+ (BOOL)importFromDict:(NSDictionary *)dict {
	if (![dict isKindOfClass:[NSDictionary class]] || !dict.count) return NO;
	[self resetAll];
	NSString *dir = sciStorageDir();
	for (NSString *name in dict) {
		if (![name hasSuffix:@".json"]) continue;
		NSDictionary *d = dict[name];
		if (![d isKindOfClass:[NSDictionary class]]) continue;
		sciWriteJSON([dir stringByAppendingPathComponent:name], d);
	}
	return YES;
}

@end
