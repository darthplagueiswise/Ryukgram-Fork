#import "RYGFileLog.h"

#if RYG_FILELOG

#import "../modules/fishhook/fishhook.h"
#import <objc/runtime.h>
#import <sys/file.h>
#import <sys/stat.h>
#import <sys/time.h>
#import <unistd.h>

// Rotate (truncate) once the file passes this size so it can't grow forever.
static const off_t kRYGLogMaxBytes = 8 * 1024 * 1024;

@interface LSBundleProxy : NSObject
@property (nonatomic, readonly) NSDictionary *entitlements;
@property (nonatomic, readonly) NSDictionary *groupContainerURLs;
+ (instancetype)bundleProxyForCurrentProcess;
@end

// Same app-group resolution SideloadFix uses, so app + appex resolve the
// identical shared container and append to one file when entitled.
static NSURL *rygAppGroupContainer(void) {
	Class cls = objc_getClass("LSBundleProxy");
	if (!cls) return nil;

	LSBundleProxy *proxy = [cls bundleProxyForCurrentProcess];
	if (!proxy) return nil;

	NSDictionary *ents = proxy.entitlements;
	if (![ents isKindOfClass:NSDictionary.class]) return nil;

	NSArray *groups = ents[@"com.apple.security.application-groups"];
	if (![groups isKindOfClass:NSArray.class] || !groups.count) return nil;

	NSDictionary *urls = proxy.groupContainerURLs;
	if (![urls isKindOfClass:NSDictionary.class]) return nil;

	NSURL *url = urls[groups.firstObject];
	return [url isKindOfClass:NSURL.class] ? url : nil;
}

static NSString *rygResolveLogPath(void) {
	NSFileManager *fm = NSFileManager.defaultManager;

	NSURL *group = rygAppGroupContainer();
	if (group) {
		NSURL *dir = [group URLByAppendingPathComponent:@"RyukGram" isDirectory:YES];
		[fm createDirectoryAtURL:dir withIntermediateDirectories:YES attributes:nil error:nil];
		return [dir URLByAppendingPathComponent:@"RyukGram.log"].path;
	}

	// No app-group entitlement: each process logs into its own Documents.
	NSString *docs = NSSearchPathForDirectoriesInDomains(NSDocumentDirectory, NSUserDomainMask, YES).lastObject;
	return [docs stringByAppendingPathComponent:@"RyukGram.log"];
}

NSString *RYGFileLogPath(void) {
	static NSString *path;
	static dispatch_once_t once;
	dispatch_once(&once, ^{ path = rygResolveLogPath(); });
	return path;
}

NSURL *RYGFileLogURL(void) {
	NSString *p = RYGFileLogPath();
	return p ? [NSURL fileURLWithPath:p] : nil;
}

// === runtime enable gate (marker-file backed, cross-process) ================

static double rygNow(void) {
	struct timeval tv;
	gettimeofday(&tv, NULL);
	return tv.tv_sec + tv.tv_usec / 1e6;
}

static NSString *rygMarkerPath(void) {
	NSString *p = RYGFileLogPath();
	if (!p.length) return nil;
	return [[p stringByDeletingLastPathComponent] stringByAppendingPathComponent:@".RyukGram.logging_on"];
}

static BOOL sEnabledCached = NO;
static double sEnabledCheckedAt = 0;

BOOL RYGFileLogIsEnabled(void) {
	double now = rygNow();
	if (now - sEnabledCheckedAt > 2.0) {
		NSString *m = rygMarkerPath();
		sEnabledCached = (m.length && [NSFileManager.defaultManager fileExistsAtPath:m]);
		sEnabledCheckedAt = now;
	}
	return sEnabledCached;
}

void RYGFileLogSetEnabled(BOOL enabled) {
	NSString *m = rygMarkerPath();
	if (!m.length) return;

	if (enabled) [[NSData data] writeToFile:m atomically:YES];
	else [NSFileManager.defaultManager removeItemAtPath:m error:nil];

	sEnabledCached = enabled;
	sEnabledCheckedAt = rygNow();
}

// === writer =================================================================

static void rygTimestamp(char *buf, size_t len) {
	struct timeval tv;
	gettimeofday(&tv, NULL);
	struct tm tmv;
	localtime_r(&tv.tv_sec, &tmv);

	char base[32];
	strftime(base, sizeof(base), "%Y-%m-%d %H:%M:%S", &tmv);
	snprintf(buf, len, "%s.%03d", base, (int)(tv.tv_usec / 1000));
}

void RYGFileLogWrite(NSString *category, NSString *message) {
	if (!RYGFileLogIsEnabled()) return;
	if (!message.length) return;
	NSString *path = RYGFileLogPath();
	if (!path.length) return;

	char ts[40];
	rygTimestamp(ts, sizeof(ts));

	const char *proc = getprogname() ?: "?";
	NSString *cat = category.length ? [NSString stringWithFormat:@"[%@] ", category] : @"";
	NSString *line = [NSString stringWithFormat:@"%s [%d %s] %@%@\n",
					  ts, getpid(), proc, cat, message];
	NSData *data = [line dataUsingEncoding:NSUTF8StringEncoding];
	if (!data.length) return;

	int fd = open(path.fileSystemRepresentation, O_WRONLY | O_APPEND | O_CREAT, 0644);
	if (fd < 0) return;

	// flock coordinates the two injected dylibs / the appex; O_APPEND keeps
	// the offset at EOF so interleaved writers never clobber each other.
	flock(fd, LOCK_EX);

	struct stat st;
	if (fstat(fd, &st) == 0 && st.st_size > kRYGLogMaxBytes) {
		ftruncate(fd, 0);
		lseek(fd, 0, SEEK_SET);
		const char *marker = "--- log rotated (size cap) ---\n";
		write(fd, marker, strlen(marker));
	}

	write(fd, data.bytes, data.length);
	flock(fd, LOCK_UN);
	close(fd);
}

void RYGFileLogClear(void) {
	NSString *path = RYGFileLogPath();
	if (path.length) [NSFileManager.defaultManager removeItemAtPath:path error:nil];
}

NSString *RYGFileLogExportToDocuments(void) {
	if (!RYGFileLogIsEnabled()) return nil;

	NSString *src = RYGFileLogPath();
	if (!src.length) return nil;

	NSString *docs = NSSearchPathForDirectoriesInDomains(NSDocumentDirectory, NSUserDomainMask, YES).lastObject;
	if (!docs.length) return nil;
	NSString *dst = [docs stringByAppendingPathComponent:@"RyukGram.log"];
	if ([src isEqualToString:dst]) return dst;

	NSFileManager *fm = NSFileManager.defaultManager;
	if (![fm fileExistsAtPath:src]) return nil;

	// Skip the copy when the Documents mirror is already at or newer than the
	// source — keeps foregrounds cheap instead of re-copying the whole file.
	NSDate *srcMod = [fm attributesOfItemAtPath:src error:nil].fileModificationDate;
	NSDate *dstMod = [fm attributesOfItemAtPath:dst error:nil].fileModificationDate;
	if (srcMod && dstMod && [dstMod compare:srcMod] != NSOrderedAscending) return dst;

	[fm removeItemAtPath:dst error:nil];
	return [fm copyItemAtPath:src toPath:dst error:nil] ? dst : nil;
}

// === NSLog tee ==============================================================

static void (*orig_NSLog)(NSString *, ...);

static void ryg_NSLog(NSString *format, ...) {
	// When the toggle is off, pass straight through to the real NSLog with the
	// original args — same cost as an untouched NSLog, nothing captured.
	if (!RYGFileLogIsEnabled()) {
		va_list ap;
		va_start(ap, format);
		NSLogv(format, ap);
		va_end(ap);
		return;
	}

	va_list ap;
	va_start(ap, format);
	NSString *s = [[NSString alloc] initWithFormat:format arguments:ap];
	va_end(ap);

	if (orig_NSLog) orig_NSLog(@"%@", s);

	if (s && [s rangeOfString:@"[RyukGram]"].location != NSNotFound) {
		RYGFileLogWrite(nil, s);
	}
}

// Both dylibs carry this TU and load into the main app; the env flag lets only
// the first rebind NSLog, so a line is never written twice.
__attribute__((constructor)) static void rygInstallNSLogTee(void) {
	if (getenv("RYG_NSLOG_TEE")) return;
	setenv("RYG_NSLOG_TEE", "1", 1);

	struct rebinding r = {"NSLog", (void *)ryg_NSLog, (void **)&orig_NSLog};
	rebind_symbols(&r, 1);
}

#endif // RYG_FILELOG
