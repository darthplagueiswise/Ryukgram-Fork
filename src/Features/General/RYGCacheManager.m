#import "RYGCacheManager.h"
#import "../../Background/RYGBackgroundActivity.h"
#import <stdatomic.h>
#import <fts.h>
#import <sys/stat.h>
#import <dirent.h>
#import <removefile.h>

static NSString *const kAutoClearModeKey = @"cache_auto_clear_mode";
static NSString *const kLastAutoClearKey = @"cache_last_auto_clear_ts";
static NSString *const kLastKnownSizeKey = @"cache_last_known_size";
static NSString *const kInProgressKey = @"cache_auto_clear_in_progress";
static NSString *const kLastResultKey = @"cache_auto_clear_last_result";
static NSString *const kFailCountKey = @"cache_auto_clear_fail_count";
static NSString *const kBgSource = @"cache_autoclear";

static const NSUInteger kMaxRetries = 5;
static const NSTimeInterval kClockSkewGrace = 300;

typedef struct {
	uint64_t removed;
	uint64_t failures;
} RYGDeleteStats;

static _Atomic bool gClearing;

NSString *const RYGCacheSizeDidUpdateNotification = @"RYGCacheSizeDidUpdateNotification";

static _Atomic uint64_t gCachedSize;
static dispatch_once_t gLoadOnce, gQueueOnce;
static dispatch_queue_t gQueue;

static dispatch_queue_t rygQueue(void) {
	dispatch_once(&gQueueOnce, ^{
		gQueue = dispatch_queue_create("com.ryukgram.cache.manager", DISPATCH_QUEUE_SERIAL);
	});
	return gQueue;
}

static void rygLoadSize(void) {
	dispatch_once(&gLoadOnce, ^{
		NSNumber *n = [[NSUserDefaults standardUserDefaults] objectForKey:kLastKnownSizeKey];
		atomic_store(&gCachedSize, n.unsignedLongLongValue);
	});
}

static NSArray<NSString *> *rygCacheDirs(void) {
	NSString *cache = NSSearchPathForDirectoriesInDomains(NSCachesDirectory, NSUserDomainMask, YES).firstObject;
	NSString *support = NSSearchPathForDirectoriesInDomains(NSApplicationSupportDirectory, NSUserDomainMask, YES).firstObject;
	NSString *tmp = NSTemporaryDirectory();
	NSMutableArray *a = [NSMutableArray arrayWithCapacity:3];
	if (cache.length) [a addObject:cache];
	if (support.length) [a addObject:support];
	if (tmp.length) [a addObject:tmp];
	return a;
}

static BOOL rygSafeDir(NSString *path) {
	BOOL isDir = NO;
	NSString *p = path.stringByStandardizingPath;
	NSString *home = NSHomeDirectory().stringByStandardizingPath;
	return p.length && ![p isEqualToString:@"/"] && ![p isEqualToString:home] &&
		[p hasPrefix:home] && [NSFileManager.defaultManager fileExistsAtPath:p isDirectory:&isDir] && isDir;
}

static BOOL rygProtected(const char *name) {
	return name && strcmp(name, "RyukGram") == 0;
}

static BOOL rygProtectedMessageStore(const char *name) {
	if (!name) return NO;
	static const char * const list[] = {
		"DirectSQLiteDatabase", "IGDirectE2EEDiskStore", "direct", "Notes",
		"unified-drafts", "saved-drafts", "Drafts", "PostCreation",
		"ThreadCreation", NULL
	};
	for (const char * const *p = list; *p; p++) if (!strcmp(name, *p)) return YES;
	return !strncmp(name, "Drafts_", 7);
}

static uint64_t rygDirSize(NSString *path) {
	if (!rygSafeDir(path)) return 0;
	const char *root = path.fileSystemRepresentation;
	char * const paths[] = { (char *)root, NULL };
	FTS *fts = fts_open(paths, FTS_PHYSICAL | FTS_NOCHDIR | FTS_XDEV, NULL);
	if (!fts) return 0;

	uint64_t total = 0;
	FTSENT *e;
	while ((e = fts_read(fts))) {
		if (e->fts_info == FTS_D && e->fts_level == 1 && rygProtected(e->fts_name)) {
			fts_set(fts, e, FTS_SKIP);
			continue;
		}
		if ((e->fts_info == FTS_F || e->fts_info == FTS_DEFAULT) && e->fts_statp) {
			total += (uint64_t)e->fts_statp->st_size;
		}
	}
	fts_close(fts);
	return total;
}

static uint64_t rygTotalSize(void) {
	uint64_t total = NSURLCache.sharedURLCache.currentDiskUsage;
	for (NSString *dir in rygCacheDirs()) total += rygDirSize(dir);
	return total;
}

static void rygSaveSize(uint64_t size) {
	atomic_store(&gCachedSize, size);
	[[NSUserDefaults standardUserDefaults] setObject:@(size) forKey:kLastKnownSizeKey];
}

static void rygPost(uint64_t size, void(^completion)(uint64_t), BOOL notify) {
	dispatch_async(dispatch_get_main_queue(), ^{
		if (notify) [[NSNotificationCenter defaultCenter] postNotificationName:RYGCacheSizeDidUpdateNotification object:@(size)];
		if (completion) completion(size);
	});
}

static void rygDeleteContents(NSString *path, BOOL preserveMessages, RYGDeleteStats *stats) {
	if (!rygSafeDir(path)) return;
	const char *root = path.fileSystemRepresentation;

	if (!preserveMessages) {
		DIR *dp = opendir(root);
		if (!dp) {
			stats->failures++;
			return;
		}

		struct dirent *de;
		while ((de = readdir(dp))) {
			if (de->d_name[0] == '.' && (!de->d_name[1] || (de->d_name[1] == '.' && !de->d_name[2]))) continue;
			if (rygProtected(de->d_name)) continue;

			char full[PATH_MAX];
			if (snprintf(full, sizeof(full), "%s/%s", root, de->d_name) < (int)sizeof(full)) {
				if (removefile(full, NULL, REMOVEFILE_RECURSIVE) == 0) stats->removed++;
				else stats->failures++;
			}
		}
		closedir(dp);
		return;
	}

	char * const paths[] = { (char *)root, NULL };
	FTS *fts = fts_open(paths, FTS_PHYSICAL | FTS_NOCHDIR | FTS_XDEV, NULL);
	if (!fts) {
		stats->failures++;
		return;
	}

	FTSENT *e;
	while ((e = fts_read(fts))) {
		if (!e->fts_level) continue;

		if (e->fts_info == FTS_D) {
			if ((e->fts_level == 1 && rygProtected(e->fts_name)) || rygProtectedMessageStore(e->fts_name)) {
				fts_set(fts, e, FTS_SKIP);
			}
			continue;
		}

		if (e->fts_info == FTS_DP) { rmdir(e->fts_accpath); continue; }
		if (unlink(e->fts_accpath) == 0) stats->removed++;
		else stats->failures++;
	}
	fts_close(fts);
}

static NSTimeInterval rygIntervalForMode(NSString *mode) {
	if ([mode isEqualToString:@"launch"]) return 0;
	if ([mode isEqualToString:@"daily"]) return 86400;
	if ([mode isEqualToString:@"weekly"]) return 604800;
	if ([mode isEqualToString:@"monthly"]) return 2592000;
	return -1;
}

@implementation RYGCacheManager

+ (void)_scanTransient:(BOOL)transient completion:(void(^)(uint64_t))completion {
	dispatch_async(rygQueue(), ^{
		uint64_t total = rygTotalSize();
		if (!transient) rygSaveSize(total);
		rygPost(total, completion, !transient);
	});
}

+ (void)getCacheSizeWithCompletion:(void(^)(uint64_t))completion {
	[self _scanTransient:NO completion:completion];
}

+ (void)getCacheSizeTransientWithCompletion:(void(^)(uint64_t))completion {
	[self _scanTransient:YES completion:completion];
}

+ (uint64_t)cachedSize {
	rygLoadSize();
	return atomic_load(&gCachedSize);
}

+ (void)refreshSizeInBackground {
	[self _scanTransient:NO completion:nil];
}

+ (void)refreshSizeInBackgroundIfEnabled {
	if ([[NSUserDefaults standardUserDefaults] boolForKey:@"cache_auto_check_size"]) {
		[self refreshSizeInBackground];
	}
}

+ (void)_clearAuto:(BOOL)isAuto completion:(void(^)(uint64_t))completion {
	if (atomic_exchange(&gClearing, true)) {
		if (completion) rygPost(0, completion, NO);
		return;
	}
	if (isAuto) [RYGBackgroundActivity setSource:kBgSource active:YES];

	dispatch_async(rygQueue(), ^{
		NSUserDefaults *ud = [NSUserDefaults standardUserDefaults];
		BOOL preserve = [ud boolForKey:@"cache_preserve_messages_db"];

		[ud setBool:YES forKey:kInProgressKey];
		[ud setObject:@"running" forKey:kLastResultKey];
		[ud synchronize];

		uint64_t before = rygTotalSize();

		RYGDeleteStats stats = {0, 0};
		for (NSString *dir in rygCacheDirs()) rygDeleteContents(dir, preserve, &stats);
		[NSURLCache.sharedURLCache removeAllCachedResponses];

		uint64_t after = rygTotalSize();
		uint64_t freed = after < before ? before - after : 0;
		BOOL ok = stats.failures == 0 && (before == 0 || after < before);

		rygSaveSize(after);
		[ud setObject:ok ? @"ok" : @"failed" forKey:kLastResultKey];
		if (ok) [ud setInteger:0 forKey:kFailCountKey];
		else [ud setInteger:[ud integerForKey:kFailCountKey] + 1 forKey:kFailCountKey];
		if (isAuto && ok) [ud setDouble:NSDate.date.timeIntervalSince1970 forKey:kLastAutoClearKey];
		[ud setBool:NO forKey:kInProgressKey];
		[ud synchronize];

		atomic_store(&gClearing, false);
		if (isAuto) [RYGBackgroundActivity setSource:kBgSource active:NO];

		rygPost(after, ^(__unused uint64_t size) {
			if (completion) completion(freed);
		}, YES);
	});
}

+ (void)clearCacheWithCompletion:(void(^)(uint64_t))completion {
	[self _clearAuto:NO completion:completion];
}

+ (void)runAutoClearIfDue {
	if (atomic_load(&gClearing)) return;

	NSUserDefaults *ud = [NSUserDefaults standardUserDefaults];
	NSString *mode = [ud stringForKey:kAutoClearModeKey];
	NSTimeInterval interval = mode.length ? rygIntervalForMode(mode) : -1;
	if (interval < 0) return [self refreshSizeInBackgroundIfEnabled];

	NSTimeInterval last = [ud doubleForKey:kLastAutoClearKey];
	NSTimeInterval elapsed = last > 0 ? NSDate.date.timeIntervalSince1970 - last : -1;
	BOOL interrupted = [ud boolForKey:kInProgressKey];
	NSString *lastResult = [ud stringForKey:kLastResultKey] ?: @"never";
	NSInteger fails = [ud integerForKey:kFailCountKey];
	BOOL underCap = fails <= (NSInteger)kMaxRetries;

	// Without the cap, a device that always kills us mid-clear re-clears every launch.
	if (interrupted && !underCap) {
		[ud setBool:NO forKey:kInProgressKey];
		[ud setObject:@"failed" forKey:kLastResultKey];
		[ud synchronize];
		interrupted = NO;
		lastResult = @"failed";
	}

	BOOL retryPending = ![lastResult isEqualToString:@"ok"] && ![lastResult isEqualToString:@"never"] && fails > 0 && underCap;
	// A corrected clock leaves the stamp in the future, which would stall the schedule.
	BOOL due = interrupted || retryPending || last <= 0 || elapsed < -kClockSkewGrace || elapsed >= interval;
	if (!due) return [self refreshSizeInBackgroundIfEnabled];

	if (interrupted) {
		[ud setInteger:fails + 1 forKey:kFailCountKey];
		[ud synchronize];
	}

	[self _clearAuto:YES completion:nil];
}

+ (void)recoverInterruptedAutoClear {
	if (![[NSUserDefaults standardUserDefaults] boolForKey:kInProgressKey]) return;
	[self runAutoClearIfDue];
}

+ (NSString *)formattedSize:(uint64_t)bytes {
	return [NSByteCountFormatter stringFromByteCount:(long long)bytes countStyle:NSByteCountFormatterCountStyleFile];
}

@end
