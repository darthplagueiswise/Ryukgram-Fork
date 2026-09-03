#import "RYGDMLocalSeen.h"
#import "../../RYGAccountScopedDefaults.h"

NSString * const RYGDMSeenStateDidChangeNotification = @"RYGDMSeenStateDidChange";

#define RYG_DM_LOCAL_SEEN_KEY @"ryg_dm_local_seen"
#define RYG_DM_SERVER_SEEN_KEY @"ryg_dm_server_seen"

static const NSTimeInterval kRYGDMLocalSeenTTL = 30.0 * 24.0 * 3600.0;

// Keyed per scoped key: a single slot hands one concurrent account the other's entries.
static NSMutableDictionary<NSString *, NSDictionary *> *rygDMSeenCaches;
static NSMutableDictionary<NSString *, NSDictionary *> *rygDMServerCaches;
static NSLock *rygDMCacheLock;

__attribute__((constructor)) static void rygDMLocalSeenInit(void) {
	rygDMSeenCaches = [NSMutableDictionary dictionary];
	rygDMServerCaches = [NSMutableDictionary dictionary];
	rygDMCacheLock = [NSLock new];
}

static NSDictionary *rygDMCacheGet(NSMutableDictionary *store, NSString *key) {
	[rygDMCacheLock lock];
	NSDictionary *v = store[key];
	[rygDMCacheLock unlock];
	return v;
}

static void rygDMCacheSet(NSMutableDictionary *store, NSString *key, NSDictionary *value) {
	[rygDMCacheLock lock];
	store[key] = value;
	[rygDMCacheLock unlock];
}

@implementation RYGDMLocalSeen

+ (NSMutableDictionary *)newestIncomingMap {
	static NSMutableDictionary *m;
	static dispatch_once_t once;
	dispatch_once(&once, ^{ m = [NSMutableDictionary dictionary]; });
	return m;
}

+ (void)postChangeForThreadId:(NSString *)threadId {
	dispatch_async(dispatch_get_main_queue(), ^{
		[NSNotificationCenter.defaultCenter postNotificationName:RYGDMSeenStateDidChangeNotification
														  object:nil
														userInfo:threadId.length ? @{@"threadId": threadId} : nil];
	});
}

#pragma mark - Local ghost seen

+ (NSDictionary *)entriesForPK:(NSString *)pk {
	NSString *scoped = pk.length ? [RYGAccountScopedDefaults scopedKey:RYG_DM_LOCAL_SEEN_KEY forPK:pk]
								 : [RYGAccountScopedDefaults scopedKey:RYG_DM_LOCAL_SEEN_KEY];
	NSDictionary *cached = rygDMCacheGet(rygDMSeenCaches, scoped);
	if (cached) return cached;

	id v = pk.length ? [RYGAccountScopedDefaults objectForKey:RYG_DM_LOCAL_SEEN_KEY pk:pk]
					 : [RYGAccountScopedDefaults dictForKey:RYG_DM_LOCAL_SEEN_KEY];
	NSDictionary *entries = [v isKindOfClass:NSDictionary.class] ? v : @{};
	rygDMCacheSet(rygDMSeenCaches, scoped, entries);
	return entries;
}

+ (void)recordThreadId:(NSString *)threadId coveredTs:(double)ts pk:(NSString *)pk {
	if (!threadId.length || ts <= 0) return;

	NSDictionary *stored = [self entriesForPK:pk];
	NSDictionary *existing = stored[threadId];
	if ([existing isKindOfClass:NSDictionary.class] && [RYGJSONScalar(existing[@"ts"]) doubleValue] >= ts) return;

	NSTimeInterval now = NSDate.date.timeIntervalSince1970;
	NSMutableDictionary *entries = [NSMutableDictionary dictionaryWithCapacity:stored.count + 1];

	for (NSString *key in stored) {
		NSDictionary *e = stored[key];
		if ([e isKindOfClass:NSDictionary.class] && now - [RYGJSONScalar(e[@"at"]) doubleValue] < kRYGDMLocalSeenTTL) entries[key] = e;
	}

	entries[threadId] = @{@"ts": @(ts), @"at": @(now)};
	if (pk.length) [RYGAccountScopedDefaults setObject:entries forKey:RYG_DM_LOCAL_SEEN_KEY pk:pk];
	else [RYGAccountScopedDefaults setObject:entries forKey:RYG_DM_LOCAL_SEEN_KEY];
	rygDMCacheSet(rygDMSeenCaches, (pk.length ? [RYGAccountScopedDefaults scopedKey:RYG_DM_LOCAL_SEEN_KEY forPK:pk]
											  : [RYGAccountScopedDefaults scopedKey:RYG_DM_LOCAL_SEEN_KEY]), entries);
	[self postChangeForThreadId:threadId];
}

+ (double)localSeenTsForThreadId:(NSString *)threadId pk:(NSString *)pk {
	if (!threadId.length) return 0;

	NSDictionary *e = [self entriesForPK:pk][threadId];
	return [e isKindOfClass:NSDictionary.class] ? [RYGJSONScalar(e[@"ts"]) doubleValue] : 0;
}

#pragma mark - Server-acknowledged seen

+ (NSDictionary *)serverEntriesForPK:(NSString *)pk {
	NSString *scoped = pk.length ? [RYGAccountScopedDefaults scopedKey:RYG_DM_SERVER_SEEN_KEY forPK:pk]
								 : [RYGAccountScopedDefaults scopedKey:RYG_DM_SERVER_SEEN_KEY];
	NSDictionary *cached = rygDMCacheGet(rygDMServerCaches, scoped);
	if (cached) return cached;

	id v = pk.length ? [RYGAccountScopedDefaults objectForKey:RYG_DM_SERVER_SEEN_KEY pk:pk]
					 : [RYGAccountScopedDefaults dictForKey:RYG_DM_SERVER_SEEN_KEY];
	NSDictionary *entries = [v isKindOfClass:NSDictionary.class] ? v : @{};
	rygDMCacheSet(rygDMServerCaches, scoped, entries);
	return entries;
}

+ (void)recordServerSeenThreadId:(NSString *)threadId ts:(double)ts {
	[self recordServerSeenThreadId:threadId ts:ts pk:nil];
}

+ (void)recordServerSeenThreadId:(NSString *)threadId ts:(double)ts pk:(NSString *)pk {
	if (!threadId.length || ts <= 0) return;

	NSDictionary *stored = [self serverEntriesForPK:pk];
	NSDictionary *existing = stored[threadId];
	if ([existing isKindOfClass:NSDictionary.class] && [RYGJSONScalar(existing[@"ts"]) doubleValue] + 2.0 >= ts) return;

	NSTimeInterval now = NSDate.date.timeIntervalSince1970;
	NSMutableDictionary *entries = [NSMutableDictionary dictionaryWithCapacity:stored.count + 1];

	for (NSString *key in stored) {
		NSDictionary *e = stored[key];
		if ([e isKindOfClass:NSDictionary.class] && now - [RYGJSONScalar(e[@"at"]) doubleValue] < kRYGDMLocalSeenTTL) entries[key] = e;
	}

	entries[threadId] = @{@"ts": @(ts), @"at": @(now)};
	if (pk.length) [RYGAccountScopedDefaults setObject:entries forKey:RYG_DM_SERVER_SEEN_KEY pk:pk];
	else [RYGAccountScopedDefaults setObject:entries forKey:RYG_DM_SERVER_SEEN_KEY];
	rygDMCacheSet(rygDMServerCaches, (pk.length ? [RYGAccountScopedDefaults scopedKey:RYG_DM_SERVER_SEEN_KEY forPK:pk]
												: [RYGAccountScopedDefaults scopedKey:RYG_DM_SERVER_SEEN_KEY]), entries);
	[self postChangeForThreadId:threadId];
}

+ (void)seedServerSeenThreadId:(NSString *)threadId ts:(double)ts pk:(NSString *)pk {
	if (!threadId.length || ts <= 0) return;
	if ([self entriesForPK:pk][threadId] != nil) return;
	if ([self serverSeenTsForThreadId:threadId pk:pk] > 0) return;
	[self recordServerSeenThreadId:threadId ts:ts pk:pk];
}

+ (double)serverSeenTsForThreadId:(NSString *)threadId pk:(NSString *)pk {
	if (!threadId.length) return 0;

	NSDictionary *e = [self serverEntriesForPK:pk][threadId];
	return [e isKindOfClass:NSDictionary.class] ? [RYGJSONScalar(e[@"ts"]) doubleValue] : 0;
}

#pragma mark - Live thread state

+ (NSString *)liveKeyForThreadId:(NSString *)threadId pk:(NSString *)pk {
	return [NSString stringWithFormat:@"%@|%@", pk.length ? pk : @"", threadId];
}

+ (void)noteNewestIncomingTs:(double)ts forThreadId:(NSString *)threadId pk:(NSString *)pk {
	if (!threadId.length) return;

	NSString *key = [self liveKeyForThreadId:threadId pk:pk];
	NSMutableDictionary *m = [self newestIncomingMap];
	@synchronized (m) {
		double prev = [m[key] doubleValue];
		if (ts <= prev) return;
		m[key] = @(ts);
	}
	[self postChangeForThreadId:threadId];
}

+ (double)newestIncomingTsForThreadId:(NSString *)threadId pk:(NSString *)pk {
	if (!threadId.length) return 0;

	NSString *key = [self liveKeyForThreadId:threadId pk:pk];
	NSMutableDictionary *m = [self newestIncomingMap];
	@synchronized (m) { return [m[key] doubleValue]; }
}

+ (BOOL)isServerPendingForThreadId:(NSString *)threadId {
	NSString *pk = [RYGAccountScopedDefaults currentPK];
	double newestIn = [self newestIncomingTsForThreadId:threadId pk:pk];
	if (newestIn <= 0) return NO;
	return newestIn > [self serverSeenTsForThreadId:threadId pk:pk] + 1.0;
}

@end
