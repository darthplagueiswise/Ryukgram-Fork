#import "SCICacheManager.h"
#import "../../Background/SCIBackgroundActivity.h"
#import <stdatomic.h>
#import <fts.h>
#import <sys/stat.h>
#import <dirent.h>
#import <removefile.h>

static NSString *const kAutoClearModeKey = @"cache_auto_clear_mode";
static NSString *const kLastAutoClearKey = @"cache_last_auto_clear_ts";
static NSString *const kLastKnownSizeKey = @"cache_last_known_size";
static NSString *const kInProgressKey = @"cache_auto_clear_in_progress";
static NSString *const kBgSource = @"cache_autoclear";

static _Atomic bool gClearing;

NSString *const SCICacheSizeDidUpdateNotification = @"SCICacheSizeDidUpdateNotification";

static _Atomic uint64_t gCachedSize;
static dispatch_once_t gLoadOnce, gQueueOnce;
static dispatch_queue_t gQueue;

static dispatch_queue_t sciQueue(void) {
	dispatch_once(&gQueueOnce, ^{
		gQueue = dispatch_queue_create("com.ryukgram.cache.manager", DISPATCH_QUEUE_SERIAL);
	});
	return gQueue;
}

static void sciLoadSize(void) {
	dispatch_once(&gLoadOnce, ^{
		NSNumber *n = [[NSUserDefaults standardUserDefaults] objectForKey:kLastKnownSizeKey];
		atomic_store(&gCachedSize, n.unsignedLongLongValue);
	});
}

static NSArray<NSString *> *sciCacheDirs(void) {
	NSString *cache = NSSearchPathForDirectoriesInDomains(NSCachesDirectory, NSUserDomainMask, YES).firstObject;
	NSString *support = NSSearchPathForDirectoriesInDomains(NSApplicationSupportDirectory, NSUserDomainMask, YES).firstObject;
	NSString *tmp = NSTemporaryDirectory();
	NSMutableArray *a = [NSMutableArray arrayWithCapacity:3];
	if (cache.length) [a addObject:cache];
	if (support.length) [a addObject:support];
	if (tmp.length) [a addObject:tmp];
	return a;
}

static BOOL sciSafeDir(NSString *path) {
	BOOL isDir = NO;
	NSString *p = path.stringByStandardizingPath;
	NSString *home = NSHomeDirectory().stringByStandardizingPath;
	return p.length && ![p isEqualToString:@"/"] && ![p isEqualToString:home] &&
		[p hasPrefix:home] && [NSFileManager.defaultManager fileExistsAtPath:p isDirectory:&isDir] && isDir;
}

static BOOL sciProtected(const char *name) {
	return name && strcmp(name, "RyukGram") == 0;
}

static BOOL sciProtectedMessageStore(const char *name) {
	if (!name) return NO;
	static const char * const list[] = {
		"DirectSQLiteDatabase", "IGDirectE2EEDiskStore", "direct", "Notes",
		"unified-drafts", "saved-drafts", "Drafts", "PostCreation",
		"ThreadCreation", NULL
	};
	for (const char * const *p = list; *p; p++) if (!strcmp(name, *p)) return YES;
	return !strncmp(name, "Drafts_", 7);
}

static uint64_t sciDirSize(NSString *path) {
	if (!sciSafeDir(path)) return 0;
	const char *root = path.fileSystemRepresentation;
	char * const paths[] = { (char *)root, NULL };
	FTS *fts = fts_open(paths, FTS_PHYSICAL | FTS_NOCHDIR | FTS_XDEV, NULL);
	if (!fts) return 0;

	uint64_t total = 0;
	FTSENT *e;
	while ((e = fts_read(fts))) {
		if (e->fts_info == FTS_D && e->fts_level == 1 && sciProtected(e->fts_name)) {
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

static uint64_t sciTotalSize(void) {
	uint64_t total = NSURLCache.sharedURLCache.currentDiskUsage;
	for (NSString *dir in sciCacheDirs()) total += sciDirSize(dir);
	return total;
}

static void sciSaveSize(uint64_t size) {
	atomic_store(&gCachedSize, size);
	[[NSUserDefaults standardUserDefaults] setObject:@(size) forKey:kLastKnownSizeKey];
}

static void sciPost(uint64_t size, void(^completion)(uint64_t), BOOL notify) {
	dispatch_async(dispatch_get_main_queue(), ^{
		if (notify) [[NSNotificationCenter defaultCenter] postNotificationName:SCICacheSizeDidUpdateNotification object:@(size)];
		if (completion) completion(size);
	});
}

static void sciDeleteContents(NSString *path, BOOL preserveMessages) {
	if (!sciSafeDir(path)) return;
	const char *root = path.fileSystemRepresentation;

	if (!preserveMessages) {
		DIR *dp = opendir(root);
		if (!dp) return;

		struct dirent *de;
		while ((de = readdir(dp))) {
			if (de->d_name[0] == '.' && (!de->d_name[1] || (de->d_name[1] == '.' && !de->d_name[2]))) continue;
			if (sciProtected(de->d_name)) continue;

			char full[PATH_MAX];
			if (snprintf(full, sizeof(full), "%s/%s", root, de->d_name) < (int)sizeof(full)) {
				removefile(full, NULL, REMOVEFILE_RECURSIVE);
			}
		}
		closedir(dp);
		return;
	}

	char * const paths[] = { (char *)root, NULL };
	FTS *fts = fts_open(paths, FTS_PHYSICAL | FTS_NOCHDIR | FTS_XDEV, NULL);
	if (!fts) return;

	FTSENT *e;
	while ((e = fts_read(fts))) {
		if (!e->fts_level) continue;

		if (e->fts_info == FTS_D) {
			if ((e->fts_level == 1 && sciProtected(e->fts_name)) || sciProtectedMessageStore(e->fts_name)) {
				fts_set(fts, e, FTS_SKIP);
			}
			continue;
		}

		if (e->fts_info == FTS_DP) rmdir(e->fts_accpath);
		else unlink(e->fts_accpath);
	}
	fts_close(fts);
}

@implementation SCICacheManager

+ (void)_scanTransient:(BOOL)transient completion:(void(^)(uint64_t))completion {
	dispatch_async(sciQueue(), ^{
		uint64_t total = sciTotalSize();
		if (!transient) sciSaveSize(total);
		sciPost(total, completion, !transient);
	});
}

+ (void)getCacheSizeWithCompletion:(void(^)(uint64_t))completion {
	[self _scanTransient:NO completion:completion];
}

+ (void)getCacheSizeTransientWithCompletion:(void(^)(uint64_t))completion {
	[self _scanTransient:YES completion:completion];
}

+ (uint64_t)cachedSize {
	sciLoadSize();
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
		if (completion) sciPost(0, completion, NO);
		return;
	}
	if (isAuto) [SCIBackgroundActivity setSource:kBgSource active:YES];

	dispatch_async(sciQueue(), ^{
		uint64_t reclaimed = atomic_load(&gCachedSize) ?: sciTotalSize();
		BOOL preserve = [[NSUserDefaults standardUserDefaults] boolForKey:@"cache_preserve_messages_db"];

		NSUserDefaults *ud = [NSUserDefaults standardUserDefaults];
		[ud setBool:YES forKey:kInProgressKey];
		[ud synchronize];

		for (NSString *dir in sciCacheDirs()) sciDeleteContents(dir, preserve);
		[NSURLCache.sharedURLCache removeAllCachedResponses];

		sciSaveSize(0);
		[ud setDouble:NSDate.date.timeIntervalSince1970 forKey:kLastAutoClearKey];
		[ud setBool:NO forKey:kInProgressKey];
		[ud synchronize];

		atomic_store(&gClearing, false);
		if (isAuto) [SCIBackgroundActivity setSource:kBgSource active:NO];

		sciPost(0, ^(uint64_t size) {
			if (completion) completion(reclaimed);
		}, YES);
	});
}

+ (void)clearCacheWithCompletion:(void(^)(uint64_t))completion {
	[self _clearAuto:NO completion:completion];
}

+ (void)runAutoClearIfDue {
	NSString *mode = [[NSUserDefaults standardUserDefaults] stringForKey:kAutoClearModeKey];
	if (!mode.length || [mode isEqualToString:@"off"]) return [self refreshSizeInBackgroundIfEnabled];

	NSTimeInterval interval = 0;
	if ([mode isEqualToString:@"daily"]) interval = 86400;
	else if ([mode isEqualToString:@"weekly"]) interval = 604800;
	else if ([mode isEqualToString:@"monthly"]) interval = 2592000;
	else return [self refreshSizeInBackgroundIfEnabled];

	BOOL interrupted = [[NSUserDefaults standardUserDefaults] boolForKey:kInProgressKey];
	NSTimeInterval last = [[NSUserDefaults standardUserDefaults] doubleForKey:kLastAutoClearKey];
	BOOL due = interrupted || last <= 0 || NSDate.date.timeIntervalSince1970 - last >= interval;
	if (!due) return [self refreshSizeInBackgroundIfEnabled];

	[self _clearAuto:YES completion:nil];
}

+ (NSString *)formattedSize:(uint64_t)bytes {
	return [NSByteCountFormatter stringFromByteCount:(long long)bytes countStyle:NSByteCountFormatterCountStyleFile];
}

@end
