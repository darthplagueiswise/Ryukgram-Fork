#import "RYGFFmpeg.h"
#import "ActionButton/RYGMediaActions.h"
#import "Utils.h"
#import "RYGTempFiles.h"
#import <UIKit/UIKit.h>
#import <objc/runtime.h>
#import <objc/message.h>
#import <dlfcn.h>
#import <stdatomic.h>

static Class FFmpegKitClass;
static Class FFprobeKitClass;
static Class ReturnCodeClass;
static BOOL rygFFmpegLoaded;
static BOOL rygFFmpegChecked;
static atomic_bool rygCancelRequested;
static NSHashTable<NSURLSession *> *rygActiveURLSessions;
static NSSet<NSString *> *rygEncoderSet;
static dispatch_once_t rygEncoderOnce;

static dispatch_queue_t rygCancelQueue(void) {
	static dispatch_queue_t q;
	static dispatch_once_t once;
	dispatch_once(&once, ^{
		q = dispatch_queue_create("com.ryuk.ryukgram.ffmpeg.cancel", DISPATCH_QUEUE_SERIAL);
		rygActiveURLSessions = [NSHashTable weakObjectsHashTable];
		atomic_init(&rygCancelRequested, false);
	});
	return q;
}

static void rygRegisterSession(NSURLSession *session) {
	if (!session) return;
	dispatch_sync(rygCancelQueue(), ^{ [rygActiveURLSessions addObject:session]; });
}

static void rygUnregisterSession(NSURLSession *session) {
	if (!session) return;
	dispatch_sync(rygCancelQueue(), ^{ [rygActiveURLSessions removeObject:session]; });
}

static NSArray<NSURLSession *> *rygActiveSessionsSnapshot(void) {
	__block NSArray *out = @[];
	dispatch_sync(rygCancelQueue(), ^{ out = rygActiveURLSessions.allObjects ?: @[]; });
	return out;
}

static NSString *rygDylibDir(void) {
	Dl_info info;
	if (dladdr((void *)rygDylibDir, &info) && info.dli_fname) {
		return [[NSString stringWithUTF8String:info.dli_fname] stringByDeletingLastPathComponent];
	}
	return nil;
}

static NSString *rygQuote(NSString *path) {
	if (![path isKindOfClass:NSString.class] || !path.length) return @"''";
	return [NSString stringWithFormat:@"'%@'", [path stringByReplacingOccurrencesOfString:@"'" withString:@"'\\''"]];
}

static NSError *rygError(NSInteger code, NSString *message) {
	return [NSError errorWithDomain:@"RYGFFmpeg" code:code userInfo:@{NSLocalizedDescriptionKey: message ?: RYGLocalized(@"Unknown error")}];
}

static NSString *rygSafeFileStem(NSString *stem) {
	if (![stem isKindOfClass:NSString.class] || !stem.length) return [NSString stringWithFormat:@"ryg_muxed_%@", NSUUID.UUID.UUIDString];
	NSCharacterSet *bad = [NSCharacterSet characterSetWithCharactersInString:@"/:\\?%*|\"<>\n\r\t"];
	NSArray *parts = [stem componentsSeparatedByCharactersInSet:bad];
	NSString *clean = [[parts componentsJoinedByString:@"_"] stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet];
	return clean.length ? clean : [NSString stringWithFormat:@"ryg_muxed_%@", NSUUID.UUID.UUIDString];
}

static BOOL rygSessionSuccess(id session, NSString **outputOut) {
	if (!session) return NO;
	NSString *output = nil;
	id returnCode = nil;
	SEL outSel = NSSelectorFromString(@"getOutput");
	SEL rcSel = NSSelectorFromString(@"getReturnCode");
	SEL okSel = NSSelectorFromString(@"isSuccess:");
	if ([session respondsToSelector:outSel]) output = ((id(*)(id, SEL))objc_msgSend)(session, outSel);
	if ([session respondsToSelector:rcSel]) returnCode = ((id(*)(id, SEL))objc_msgSend)(session, rcSel);
	if (outputOut) *outputOut = output;
	if (!ReturnCodeClass || !returnCode || ![ReturnCodeClass respondsToSelector:okSel]) return NO;
	return ((BOOL(*)(id, SEL, id))objc_msgSend)(ReturnCodeClass, okSel, returnCode);
}

// FFmpegKit's Statistics getters return different numeric types across builds
// (int ms vs double ms). Read whatever it is, as a double.
static double rygCallDoubleGetter(id obj, NSString *selName) {
	SEL sel = NSSelectorFromString(selName);
	if (!obj || ![obj respondsToSelector:sel]) return 0;
	NSMethodSignature *sig = [obj methodSignatureForSelector:sel];
	if (!sig) return 0;
	NSInvocation *inv = [NSInvocation invocationWithMethodSignature:sig];
	inv.selector = sel;
	[inv invokeWithTarget:obj];
	const char *t = sig.methodReturnType;
	switch (t[0]) {
		case 'i': { int v = 0; [inv getReturnValue:&v]; return v; }
		case 'I': { unsigned v = 0; [inv getReturnValue:&v]; return v; }
		case 'q': { long long v = 0; [inv getReturnValue:&v]; return v; }
		case 'Q': { unsigned long long v = 0; [inv getReturnValue:&v]; return v; }
		case 'l': { long v = 0; [inv getReturnValue:&v]; return v; }
		case 'd': { double v = 0; [inv getReturnValue:&v]; return v; }
		case 'f': { float v = 0; [inv getReturnValue:&v]; return v; }
		default:  return 0;
	}
}

static void rygPreloadFFmpegDeps(NSString *fwPath) {
	NSString *fwDir = [[fwPath stringByDeletingLastPathComponent] stringByDeletingLastPathComponent];
	NSArray *deps = @[@"libavutil", @"libswresample", @"libswscale", @"libavcodec", @"libavformat", @"libavfilter", @"libavdevice"];
	NSFileManager *fm = NSFileManager.defaultManager;
	for (NSString *dep in deps) {
		NSString *path = [NSString stringWithFormat:@"%@/%@.framework/%@", fwDir, dep, dep];
		if ([fm fileExistsAtPath:path]) dlopen(path.UTF8String, RTLD_NOW | RTLD_GLOBAL);
	}
}

static void rygPresentFFmpegDebug(NSArray *paths, NSArray *errors) {
	dispatch_async(dispatch_get_main_queue(), ^{
		NSMutableString *msg = [NSMutableString stringWithString:@"dlopen errors:\n"];
		for (NSString *e in errors) [msg appendFormat:@"%@\n\n", e];
		[msg appendString:@"\nTried paths:\n"];
		NSFileManager *fm = NSFileManager.defaultManager;
		for (NSString *p in paths) {
			BOOL exists = [fm fileExistsAtPath:p];
			[msg appendFormat:@"%@ %@\n", exists ? @"✓" : @"✗", p.lastPathComponent];
			if (!exists) {
				NSString *parent = p.stringByDeletingLastPathComponent;
				NSString *grandparent = parent.stringByDeletingLastPathComponent;
				[msg appendFormat:@"  dir: %@ %@\n  dir: %@ %@\n", [fm fileExistsAtPath:parent] ? @"✓" : @"✗", parent.lastPathComponent, [fm fileExistsAtPath:grandparent] ? @"✓" : @"✗", grandparent.lastPathComponent];
			}
		}
		NSString *bundlePath = NSBundle.mainBundle.bundlePath;
		NSArray *rootContents = [fm contentsOfDirectoryAtPath:bundlePath error:nil];
		[msg appendString:@"\nApp bundle root:\n"];
		for (NSString *item in rootContents) if ([item containsString:@"RyukGram"] || [item containsString:@"ffmpeg"] || [item containsString:@".bundle"]) [msg appendFormat:@"  %@\n", item];
		NSString *fwPath = NSBundle.mainBundle.privateFrameworksPath;
		NSArray *fwContents = [fm contentsOfDirectoryAtPath:fwPath error:nil];
		[msg appendString:@"\nFrameworks/:\n"];
		for (NSString *item in fwContents) if ([item containsString:@"ffmpeg"] || [item containsString:@"libav"] || [item containsString:@"libsw"] || [item containsString:@"RyukGram"]) [msg appendFormat:@"  %@\n", item];
		UIAlertController *alert = [UIAlertController alertControllerWithTitle:RYGLocalized(@"FFmpegKit Debug") message:msg preferredStyle:UIAlertControllerStyleAlert];
		NSString *copyMsg = msg.copy;
		[alert addAction:[UIAlertAction actionWithTitle:RYGLocalized(@"Copy") style:UIAlertActionStyleDefault handler:^(__unused UIAlertAction *a) {
			UIPasteboard.generalPasteboard.string = copyMsg;
			RYGNotifySuccess(RYG_NOTIF_GENERIC, RYGLocalized(@"FFmpeg log copied"), nil);
		}]];
		[alert addAction:[UIAlertAction actionWithTitle:RYGLocalized(@"OK") style:UIAlertActionStyleCancel handler:nil]];
		dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(1.0 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
			UIViewController *root = UIApplication.sharedApplication.keyWindow.rootViewController;
			while (root.presentedViewController) root = root.presentedViewController;
			[root presentViewController:alert animated:YES completion:nil];
		});
	});
}

static void rygLoadFFmpegKit(void) {
	@synchronized([RYGFFmpeg class]) {
		if (rygFFmpegChecked) return;
		rygFFmpegChecked = YES;
		NSMutableArray *paths = [NSMutableArray array];
		NSString *dylibDir = rygDylibDir();
		if (dylibDir.length) {
			[paths addObject:[dylibDir stringByAppendingPathComponent:@"ffmpegkit.framework/ffmpegkit"]];
			// roothide: jbroot is randomized, .jbroot symlinks back to it
			[paths addObject:[dylibDir stringByAppendingPathComponent:
				@".jbroot/Library/Application Support/RyukGram.bundle/ffmpegkit.framework/ffmpegkit"]];
		}
		NSString *bundlePath = NSBundle.mainBundle.bundlePath;
		NSString *frameworksPath = NSBundle.mainBundle.privateFrameworksPath;
		[paths addObjectsFromArray:@[
			[bundlePath stringByAppendingPathComponent:@"RyukGram.bundle/ffmpegkit.framework/ffmpegkit"],
			[frameworksPath stringByAppendingPathComponent:@"ffmpegkit.framework/ffmpegkit"],
			@"/var/jb/Library/Application Support/RyukGram.bundle/ffmpegkit.framework/ffmpegkit",
			@"/var/jb/Library/MobileSubstrate/DynamicLibraries/ffmpegkit.framework/ffmpegkit",
			@"/Library/Application Support/RyukGram.bundle/ffmpegkit.framework/ffmpegkit",
			@"/Library/MobileSubstrate/DynamicLibraries/ffmpegkit.framework/ffmpegkit"
		]];
		NSFileManager *fm = NSFileManager.defaultManager;
		void *handle = NULL;
		NSMutableArray *errors = [NSMutableArray array];
		for (NSString *fwPath in paths) {
			if (![fm fileExistsAtPath:fwPath]) continue;
			rygPreloadFFmpegDeps(fwPath);
			handle = dlopen(fwPath.UTF8String, RTLD_NOW | RTLD_GLOBAL);
			if (handle) { NSLog(@"[RyukGram] FFmpegKit loaded from %@", fwPath); break; }
			const char *err = dlerror();
			[errors addObject:[NSString stringWithFormat:@"%@\n%s", fwPath.lastPathComponent, err ?: "unknown"]];
		}
		if (!handle) {
			NSLog(@"[RyukGram] FFmpegKit not available");
			for (NSString *e in errors) NSLog(@"[RyukGram] dlopen: %@", e);
			rygPresentFFmpegDebug(paths, errors);
			return;
		}
		FFmpegKitClass = NSClassFromString(@"FFmpegKit");
		FFprobeKitClass = NSClassFromString(@"FFprobeKit");
		ReturnCodeClass = NSClassFromString(@"ReturnCode");
		if (FFmpegKitClass) {
			rygFFmpegLoaded = YES;
			NSLog(@"[RyukGram] FFmpegKit ready");
		} else {
			NSLog(@"[RyukGram] FFmpegKit classes not found after dlopen");
			dlclose(handle);
		}
	}
}

static BOOL rygMoveDownload(NSURL *location, NSString *path) {
	if (!location || !path.length) return NO;
	NSFileManager *fm = NSFileManager.defaultManager;
	NSURL *dest = [NSURL fileURLWithPath:path];
	[fm removeItemAtURL:dest error:nil];
	if ([fm moveItemAtURL:location toURL:dest error:nil]) return YES;
	[fm removeItemAtURL:dest error:nil];
	return [fm copyItemAtURL:location toURL:dest error:nil];
}

static BOOL rygDownloadToPath(NSURLSession *session, NSURL *url, NSString *path, BOOL (^cancelled)(void), void (^progress)(float)) {
	if (!session || !url || !path.length) return NO;
	dispatch_semaphore_t sem = dispatch_semaphore_create(0);
	__block BOOL ok = NO;
	__block NSError *err = nil;
	NSURLSessionDownloadTask *task = [session downloadTaskWithURL:url completionHandler:^(NSURL *loc, __unused NSURLResponse *resp, NSError *error) {
		err = error;
		if (!err && loc) ok = rygMoveDownload(loc, path);
		dispatch_semaphore_signal(sem);
	}];
	[task resume];
	while (dispatch_semaphore_wait(sem, dispatch_time(DISPATCH_TIME_NOW, 200 * NSEC_PER_MSEC)) != 0) {
		if (cancelled && cancelled()) { [task cancel]; return NO; }
		if (progress && task.countOfBytesExpectedToReceive > 0) progress((float)task.countOfBytesReceived / (float)task.countOfBytesExpectedToReceive);
	}
	if (err) NSLog(@"[RyukGram] download error: %@", err.localizedDescription);
	return ok;
}

// iOS kills VideoToolbox hardware sessions in the background (-12903); libx264 keeps
// working. A VT session killed mid-encode can deadlock ffmpeg's flush and, since
// ffmpeg executions are serialized in-process, block every later encode — so a VT
// encode is cancelled pre-emptively on resign and watchdogged if it wedges anyway.
static const NSTimeInterval kRYGMuxStallSeconds = 60.0;

typedef NS_ENUM(NSInteger, RYGMuxRun) { RYGMuxRunOK, RYGMuxRunFailed, RYGMuxRunStalled };

static BOOL rygAppInBackground(void) {
	__block UIApplicationState st = UIApplicationStateActive;
	dispatch_block_t read = ^{ st = UIApplication.sharedApplication.applicationState; };
	NSThread.isMainThread ? read() : dispatch_sync(dispatch_get_main_queue(), read);
	return st == UIApplicationStateBackground;
}

static void rygNotifySoftwareFallback(void) {
	dispatch_async(dispatch_get_main_queue(), ^{
		RYGNotifyInfo(RYG_NOTIF_GENERIC,
			RYGLocalized(@"Encoding in software"),
			RYGLocalized(@"Hardware encoder isn't available in the background — your quality settings were kept."));
	});
}

static BOOL rygOutputLooksLikeVTDeath(NSString *output) {
	if (!output.length) return NO;
	return [output containsString:@"-12903"]
		|| [output containsString:@"cannot encode frame"]
		|| [output containsString:@"Error submitting video frame"];
}

// xHE-AAC (USAC, object type 42) has no decoder before ffmpeg 7.1 — re-encode can't
// open it, so detect the failure and remux the original audio stream instead.
static BOOL rygOutputLooksLikeAudioDecodeFail(NSString *output) {
	if (!output.length) return NO;
	return [output containsString:@"Audio object type"]
		|| ([output containsString:@"opening decoder for input stream"] && [output containsString:@"Function not implemented"]);
}

// One synchronous ffmpeg run. cancelOnBackground cancels a VT encode the moment the app
// deactivates, while the VT session is still valid, so ffmpeg exits cleanly. The log
// scanner abandons after a short grace when VT-death lines appear anyway, and the
// statistics watchdog (stallSeconds) backstops hangs that never print anything.
static const NSTimeInterval kRYGVTDeathGraceSeconds = 5.0;
static const NSTimeInterval kRYGRetryStartupStallSeconds = 20.0;

static RYGMuxRun rygRunMuxCommand(NSString *cmd, BOOL cancelOnBackground, NSTimeInterval stallSeconds,
								  void (^statsCallback)(id), void (^onSessionID)(long),
								  NSString **outputOut, BOOL *bgKilledOut) {
	__block BOOL ffSuccess = NO;
	__block NSString *ffOutput = nil;
	dispatch_semaphore_t ffSem = dispatch_semaphore_create(0);
	void (^ffCallback)(id) = ^(id ffSession) {
		ffSuccess = rygSessionSuccess(ffSession, &ffOutput);
		dispatch_semaphore_signal(ffSem);
	};
	__block atomic_llong lastActivityMs;
	atomic_init(&lastActivityMs, (long long)(NSDate.timeIntervalSinceReferenceDate * 1000.0));
	void (^touch)(void) = ^{ atomic_store(&lastActivityMs, (long long)(NSDate.timeIntervalSinceReferenceDate * 1000.0)); };
	void (^statsWrapper)(id) = ^(id stats) { touch(); if (statsCallback) statsCallback(stats); };
	__block atomic_bool vtDied;
	atomic_init(&vtDied, false);
	void (^logCallback)(id) = ^(id logObj) {
		SEL msgSel = NSSelectorFromString(@"getMessage");
		if (![logObj respondsToSelector:msgSel]) return;
		NSString *msg = ((id(*)(id, SEL))objc_msgSend)(logObj, msgSel);
		if (rygOutputLooksLikeVTDeath(msg)) atomic_store(&vtDied, true);
	};
	__block atomic_llong sidShared;
	atomic_init(&sidShared, 0);
	__block atomic_bool bgKilled;
	atomic_init(&bgKilled, false);
	void (^cancelSession)(long) = ^(long s) {
		SEL cancelSel = NSSelectorFromString(@"cancel:");
		if (s && [FFmpegKitClass respondsToSelector:cancelSel]) {
			@try { ((void(*)(id, SEL, long))objc_msgSend)(FFmpegKitClass, cancelSel, s); } @catch (__unused id e) {}
		}
	};
	// Suspension freezes this thread but wall time keeps running — bump on resume so a
	// healthy encode isn't misread as stalled.
	id fgObserver = [NSNotificationCenter.defaultCenter addObserverForName:UIApplicationDidBecomeActiveNotification object:nil queue:NSOperationQueue.mainQueue usingBlock:^(__unused NSNotification *n) { touch(); }];
	// Resign fires seconds before backgrounding, while the VT session is still valid —
	// cancelling there lets ffmpeg exit cleanly before suspension can wedge it.
	// DidEnterBackground covers an encode that starts while already inactive.
	NSMutableArray *bgObservers = [NSMutableArray array];
	if (cancelOnBackground) {
		void (^bgKill)(NSNotification *) = ^(__unused NSNotification *n) {
			if (atomic_exchange(&bgKilled, true)) return;
			long s = (long)atomic_load(&sidShared);
			NSLog(@"[RyukGram][FFmpeg] app deactivating — cancelling VT session %ld before the encoder dies", s);
			cancelSession(s);
		};
		[bgObservers addObject:[NSNotificationCenter.defaultCenter addObserverForName:UIApplicationWillResignActiveNotification object:nil queue:NSOperationQueue.mainQueue usingBlock:bgKill]];
		[bgObservers addObject:[NSNotificationCenter.defaultCenter addObserverForName:UIApplicationDidEnterBackgroundNotification object:nil queue:NSOperationQueue.mainQueue usingBlock:bgKill]];
	}

	SEL statsSel = NSSelectorFromString(@"executeAsync:withCompleteCallback:withLogCallback:withStatisticsCallback:");
	SEL asyncSel = NSSelectorFromString(@"executeAsync:withCompleteCallback:");
	SEL sidSel = NSSelectorFromString(@"getSessionId");
	long sid = 0;
	BOOL watchable = NO;
	if ([FFmpegKitClass respondsToSelector:statsSel]) {
		id ffSession = ((id(*)(id, SEL, id, id, id, id))objc_msgSend)(FFmpegKitClass, statsSel, cmd, ffCallback, logCallback, statsWrapper);
		if (ffSession && [ffSession respondsToSelector:sidSel]) sid = ((long(*)(id, SEL))objc_msgSend)(ffSession, sidSel);
		watchable = YES;
	} else if ([FFmpegKitClass respondsToSelector:asyncSel]) {
		id ffSession = ((id(*)(id, SEL, id, id))objc_msgSend)(FFmpegKitClass, asyncSel, cmd, ffCallback);
		if (ffSession && [ffSession respondsToSelector:sidSel]) sid = ((long(*)(id, SEL))objc_msgSend)(ffSession, sidSel);
	} else {
		[RYGFFmpeg executeCommand:cmd completion:^(BOOL ok, NSString *out) {
			ffSuccess = ok;
			ffOutput = out;
			dispatch_semaphore_signal(ffSem);
		}];
	}
	atomic_store(&sidShared, (long long)sid);
	// Backgrounded in the launch window, before the sid was known — cancel now.
	if (cancelOnBackground && atomic_load(&bgKilled)) cancelSession(sid);
	if (onSessionID) onSessionID(sid);

	RYGMuxRun result;
	if (!watchable) {
		dispatch_semaphore_wait(ffSem, DISPATCH_TIME_FOREVER);
		result = ffSuccess ? RYGMuxRunOK : RYGMuxRunFailed;
	} else {
		double vtDeadAt = 0;
		for (;;) {
			if (dispatch_semaphore_wait(ffSem, dispatch_time(DISPATCH_TIME_NOW, (int64_t)(1 * NSEC_PER_SEC))) == 0) {
				result = ffSuccess ? RYGMuxRunOK : RYGMuxRunFailed;
				break;
			}
			double now = NSDate.timeIntervalSinceReferenceDate;
			if (atomic_load(&vtDied)) {
				if (!vtDeadAt) vtDeadAt = now;
				else if (now - vtDeadAt > kRYGVTDeathGraceSeconds) {
					cancelSession(sid);
					NSLog(@"[RyukGram][FFmpeg] session %ld abandoned: encoder died, session won't exit", sid);
					result = RYGMuxRunStalled;
					break;
				}
			}
			if (now * 1000.0 - atomic_load(&lastActivityMs) > stallSeconds * 1000.0) {
				cancelSession(sid);
				NSLog(@"[RyukGram][FFmpeg] session %ld abandoned: no statistics for %.0fs", sid, stallSeconds);
				result = RYGMuxRunStalled;
				break;
			}
		}
	}
	[NSNotificationCenter.defaultCenter removeObserver:fgObserver];
	for (id obs in bgObservers) [NSNotificationCenter.defaultCenter removeObserver:obs];
	if (outputOut) *outputOut = ffOutput;
	if (bgKilledOut) *bgKilledOut = atomic_load(&bgKilled);
	return result;
}

@implementation RYGFFmpeg

+ (BOOL)isAvailable {
	rygLoadFFmpegKit();
	return rygFFmpegLoaded;
}

+ (BOOL)isCancelled {
	return atomic_load(&rygCancelRequested);
}

+ (void)cancelAll {
	atomic_store(&rygCancelRequested, true);
	for (NSURLSession *s in rygActiveSessionsSnapshot()) {
		@try { [s invalidateAndCancel]; } @catch (__unused id e) {}
	}
	if (FFmpegKitClass) {
		SEL cancelSel = NSSelectorFromString(@"cancel");
		if ([FFmpegKitClass respondsToSelector:cancelSel]) {
			@try { ((void(*)(id, SEL))objc_msgSend)(FFmpegKitClass, cancelSel); } @catch (__unused id e) {}
		}
	}
	dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(1.0 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
		atomic_store(&rygCancelRequested, false);
	});
}

+ (void)executeCommand:(NSString *)command completion:(void(^)(BOOL success, NSString *output))completion {
	if (![self isAvailable]) { if (completion) completion(NO, @"FFmpegKit not available"); return; }
	dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
		@try {
			SEL executeSel = NSSelectorFromString(@"execute:");
			if (![FFmpegKitClass respondsToSelector:executeSel]) {
				dispatch_async(dispatch_get_main_queue(), ^{ if (completion) completion(NO, @"FFmpegKit execute: not found"); });
				return;
			}
			id session = ((id(*)(id, SEL, id))objc_msgSend)(FFmpegKitClass, executeSel, command);
			NSString *output = nil;
			BOOL success = rygSessionSuccess(session, &output);
			dispatch_async(dispatch_get_main_queue(), ^{ if (completion) completion(success, output ?: (session ? nil : @"FFmpegKit session nil")); });
		} @catch (NSException *e) {
			dispatch_async(dispatch_get_main_queue(), ^{ if (completion) completion(NO, [NSString stringWithFormat:@"Exception: %@", e.reason]); });
		}
	});
}

+ (void)probeCommand:(NSString *)command completion:(void(^)(BOOL success, NSString *output))completion {
	if (![self isAvailable]) { if (completion) completion(NO, @"FFmpegKit not available"); return; }
	dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
		@try {
			SEL executeSel = NSSelectorFromString(@"execute:");
			if (!FFprobeKitClass || ![FFprobeKitClass respondsToSelector:executeSel]) {
				dispatch_async(dispatch_get_main_queue(), ^{ if (completion) completion(NO, @"FFprobeKit not found"); });
				return;
			}
			id session = ((id(*)(id, SEL, id))objc_msgSend)(FFprobeKitClass, executeSel, command);
			NSString *output = nil;
			BOOL success = rygSessionSuccess(session, &output);
			dispatch_async(dispatch_get_main_queue(), ^{ if (completion) completion(success, output); });
		} @catch (NSException *e) {
			dispatch_async(dispatch_get_main_queue(), ^{ if (completion) completion(NO, e.reason); });
		}
	});
}

+ (void)convertAudioAtPath:(NSString *)inputPath toFormat:(NSString *)format bitrate:(NSString *)bitrate completion:(void(^)(NSURL *outputURL, NSError *error))completion {
	if (![self isAvailable]) { if (completion) completion(nil, rygError(1, @"FFmpegKit not available")); return; }
	NSString *fmt = format.length ? format.lowercaseString : @"m4a";
	NSString *outputPath = [RYGTempFiles claimWithExt:fmt ttl:600 tag:@"audio"].path;
	NSString *br = bitrate ?: @"192k";
	NSString *codecFlag = [fmt isEqualToString:@"mp3"] ? [NSString stringWithFormat:@"-c:a libmp3lame -b:a %@", br] : [NSString stringWithFormat:@"-c:a aac -b:a %@", br];
	NSString *cmd = [NSString stringWithFormat:@"-y -hide_banner -loglevel error -i %@ -vn -map a %@ %@", rygQuote(inputPath), codecFlag, rygQuote(outputPath)];
	[self executeCommand:cmd completion:^(BOOL success, NSString *output) {
		if (success && [NSFileManager.defaultManager fileExistsAtPath:outputPath]) {
			if (completion) completion([NSURL fileURLWithPath:outputPath], nil);
		} else {
			if (completion) completion(nil, rygError(4, output ?: RYGLocalized(@"Audio conversion failed")));
		}
	}];
}

+ (void)muxVideoURL:(NSURL *)videoURL audioURL:(NSURL *)audioURL preset:(NSString *)preset progress:(void(^)(float progress, NSString *stage))progressBlock completion:(void(^)(NSURL *outputURL, NSError *error))completion {
	[self muxVideoURL:videoURL audioURL:audioURL preset:preset progress:progressBlock completion:completion cancelOut:nil];
}

+ (void)muxVideoURL:(NSURL *)videoURL audioURL:(NSURL *)audioURL preset:(NSString *)preset progress:(void(^)(float progress, NSString *stage))progressBlock completion:(void(^)(NSURL *outputURL, NSError *error))completion cancelOut:(void(^)(void (^cancelBlock)(void)))cancelOut {
	if (![self isAvailable]) { if (completion) completion(nil, rygError(1, @"FFmpegKit not available")); return; }
	__block BOOL completionCalled = NO;
	void (^finish)(NSURL *, NSError *) = ^(NSURL *url, NSError *err) {
		if (completionCalled) return;
		completionCalled = YES;
		dispatch_async(dispatch_get_main_queue(), ^{ if (completion) completion(url, err); });
	};
	__block atomic_bool thisCancelled;
	atomic_init(&thisCancelled, false);
	__block NSURLSession *sessionRef = nil;
	__block long ffmpegSidRef = 0;
	BOOL (^cancelled)(void) = ^BOOL{ return atomic_load(&thisCancelled); };
	void (^cancelSelf)(void) = ^{
		atomic_store(&thisCancelled, true);
		NSURLSession *s = sessionRef;
		if (s) { @try { [s invalidateAndCancel]; } @catch (__unused id e) {} }
		long sid = ffmpegSidRef;
		SEL cancelSel = NSSelectorFromString(@"cancel:");
		if (sid && FFmpegKitClass && [FFmpegKitClass respondsToSelector:cancelSel]) {
			@try { ((void(*)(id, SEL, long))objc_msgSend)(FFmpegKitClass, cancelSel, sid); } @catch (__unused id e) {}
		}
	};
	if (cancelOut) cancelOut(cancelSelf);
	void (^report)(float, NSString *) = ^(float p, NSString *stage) {
		if (!progressBlock || cancelled()) return;
		dispatch_async(dispatch_get_main_queue(), ^{ progressBlock(p, stage); });
	};
	dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
		NSString *videoPath = [RYGTempFiles claimWithExt:@"mp4" ttl:300 tag:@"video"].path;
		NSString *audioPath = [RYGTempFiles claimWithExt:@"m4a" ttl:300 tag:@"audio"].path;
		NSString *stem = rygSafeFileStem([RYGMediaActions currentFilenameStem]);
		__block NSString *outputPath = [RYGTempFiles claimNamedFile:[NSString stringWithFormat:@"%@.mp4", stem] ttl:900 tag:@"mux"].path;
		NSError *(^cancelledError)(void) = ^NSError *{ return rygError(NSUserCancelledError, RYGLocalized(@"Cancelled")); };
		void (^cleanup)(BOOL removeOutput) = ^(BOOL removeOutput) {
			NSFileManager *fm = NSFileManager.defaultManager;
			[fm removeItemAtPath:videoPath error:nil];
			[fm removeItemAtPath:audioPath error:nil];
			if (removeOutput) [fm removeItemAtPath:outputPath error:nil];
		};
		NSURLSessionConfiguration *cfg = NSURLSessionConfiguration.ephemeralSessionConfiguration;
		cfg.requestCachePolicy = NSURLRequestReloadIgnoringLocalCacheData;
		cfg.timeoutIntervalForRequest = 30.0;
		cfg.timeoutIntervalForResource = 300.0;
		NSURLSession *session = [NSURLSession sessionWithConfiguration:cfg];
		sessionRef = session;
		rygRegisterSession(session);
		// Download fills 0…0.5, encoding fills 0.5…1.0.
		report(0.0f, RYGLocalized(@"Downloading video…"));
		BOOL videoOK = rygDownloadToPath(session, videoURL, videoPath, cancelled, ^(float p) { report(p * 0.45f, RYGLocalized(@"Downloading video…")); });
		if (cancelled()) { rygUnregisterSession(session); [session invalidateAndCancel]; cleanup(YES); finish(nil, cancelledError()); return; }
		if (!videoOK || ![NSFileManager.defaultManager fileExistsAtPath:videoPath]) { rygUnregisterSession(session); [session invalidateAndCancel]; cleanup(YES); finish(nil, rygError(2, RYGLocalized(@"Failed to download video"))); return; }
		report(0.45f, RYGLocalized(@"Downloading audio…"));
		BOOL hasAudio = audioURL != nil;
		if (hasAudio) hasAudio = rygDownloadToPath(session, audioURL, audioPath, cancelled, nil) && [NSFileManager.defaultManager fileExistsAtPath:audioPath];
		rygUnregisterSession(session);
		[session invalidateAndCancel];
		if (cancelled()) { cleanup(YES); finish(nil, cancelledError()); return; }

		// Probe total duration so encode statistics map to a real %.
		double durationMs = 0;
		SEL probeSel = NSSelectorFromString(@"execute:");
		if (FFprobeKitClass && [FFprobeKitClass respondsToSelector:probeSel]) {
			NSString *pcmd = [NSString stringWithFormat:@"-v error -show_entries format=duration -of default=nw=1:nk=1 %@", rygQuote(videoPath)];
			@try {
				id ps = ((id(*)(id, SEL, id))objc_msgSend)(FFprobeKitClass, probeSel, pcmd);
				NSString *pout = nil; rygSessionSuccess(ps, &pout);
				durationMs = [[pout stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet] doubleValue] * 1000.0;
			} @catch (__unused id e) {}
		}

		report(0.5f, RYGLocalized(@"Encoding…"));
		NSDictionary *args = [self encodingArgsForFallbackPreset:preset];
		NSString *vArgs = args[@"video"];
		__block NSString *aArgs = args[@"audio"];
		NSString *cArgs = args[@"container"];
		NSString *fArgs = args[@"filter"];
		BOOL vtPreferred = [vArgs containsString:@"h264_videotoolbox"];
		NSString *swArgs = (vtPreferred && [self hasEncoder:@"libx264"]) ? [self softwareFallbackVideoArgsForPreset:preset] : nil;
		// No -shortest: it can cut libx264's buffered tail before flush, freezing the
		// last frame. Same-source DASH a/v are equal length, so both end together.
		NSString *(^buildCmd)(NSString *, NSString *) = ^NSString *(NSString *v, NSString *outPath) {
			return hasAudio
				? [NSString stringWithFormat:@"-y -hide_banner -analyzeduration 100M -probesize 100M -fflags +genpts -i %@ -i %@ -map 0:v:0 -map 1:a:0 %@ %@ %@ %@ %@", rygQuote(videoPath), rygQuote(audioPath), fArgs, v, aArgs, cArgs, rygQuote(outPath)]
				: [NSString stringWithFormat:@"-y -hide_banner -analyzeduration 100M -probesize 100M -fflags +genpts -i %@ %@ %@ %@ %@", rygQuote(videoPath), fArgs, v, cArgs, rygQuote(outPath)];
		};
		// Real encode % from the statistics callback: time processed / total duration.
		void (^statsCallback)(id) = ^(id stats) {
			double timeMs = rygCallDoubleGetter(stats, @"getTime");
			if (durationMs > 0 && timeMs > 0) {
				float enc = (float)MIN(1.0, MAX(0.0, timeMs / durationMs));
				report(0.5f + 0.5f * enc, [NSString stringWithFormat:RYGLocalized(@"Encoding %d%%"), (int)(enc * 100)]);
			}
		};
		void (^onSID)(long) = ^(long sid) { ffmpegSidRef = sid; };

		// VT when foreground, software when backgrounded, software forced on the last try.
		// Each retry gets a fresh output path — an abandoned session must never share a
		// file with its retry. After a stalled attempt the next try gets a short startup
		// watchdog so a poisoned execution queue fails fast instead of hanging.
		NSString *ffOutput = nil;
		RYGMuxRun run = RYGMuxRunFailed;
		BOOL notifiedSW = NO;
		NSTimeInterval stall = kRYGMuxStallSeconds;
		for (int attempt = 0; attempt < 3; attempt++) {
			BOOL wantSW = vtPreferred && swArgs && (attempt == 2 || rygAppInBackground());
			NSString *v = wantSW ? swArgs : vArgs;
			BOOL vt = !wantSW && vtPreferred;
			if (wantSW && !notifiedSW) { notifiedSW = YES; rygNotifySoftwareFallback(); }
			if (attempt > 0) {
				outputPath = [RYGTempFiles claimNamedFile:[NSString stringWithFormat:@"%@.mp4", stem] ttl:900 tag:@"mux"].path;
				report(0.5f, RYGLocalized(@"Encoding…"));
			}
			BOOL bgKilled = NO;
			run = rygRunMuxCommand(buildCmd(v, outputPath), vt, stall, statsCallback, onSID, &ffOutput, &bgKilled);
			if (run == RYGMuxRunOK || cancelled()) break;
			if (hasAudio && ![aArgs isEqualToString:@"-c:a copy"] && rygOutputLooksLikeAudioDecodeFail(ffOutput)) {
				NSLog(@"[RyukGram][FFmpeg] source audio can't be decoded by this ffmpeg (likely xHE-AAC) — retrying with stream copy");
				aArgs = @"-c:a copy";
				continue;
			}
			BOOL vtDeath = vt && (bgKilled || run == RYGMuxRunStalled || rygOutputLooksLikeVTDeath(ffOutput));
			if (!vtDeath || !swArgs) break;
			stall = (run == RYGMuxRunStalled) ? kRYGRetryStartupStallSeconds : kRYGMuxStallSeconds;
			NSLog(@"[RyukGram][FFmpeg] VT encode died (attempt=%d run=%ld bgKilled=%d) — retrying", attempt + 1, (long)run, bgKilled);
			// Let the fg/bg transition settle — a quick home-and-back re-picks hardware.
			if (bgKilled) [NSThread sleepForTimeInterval:2.0];
			if (cancelled()) break;
		}
		cleanup(NO);
		if (cancelled()) { cleanup(YES); finish(nil, cancelledError()); return; }
		if (run == RYGMuxRunOK && [NSFileManager.defaultManager fileExistsAtPath:outputPath]) finish([NSURL fileURLWithPath:outputPath], nil);
		else { cleanup(YES); finish(nil, rygError(3, run == RYGMuxRunStalled ? RYGLocalized(@"Video encoder locked up — restart Instagram to encode again") : (ffOutput ?: RYGLocalized(@"FFmpeg mux failed")))); }
	});
}

+ (void)muxPhotoURL:(NSURL *)photoURL audioURL:(NSURL *)audioURL audioStartMs:(double)audioStartMs durationMs:(double)durationMs progress:(void(^)(float progress, NSString *stage))progressBlock completion:(void(^)(NSURL *outputURL, NSError *error))completion cancelOut:(void(^)(void (^cancelBlock)(void)))cancelOut {
	if (![self isAvailable]) { if (completion) completion(nil, rygError(1, @"FFmpegKit not available")); return; }
	__block BOOL completionCalled = NO;
	void (^finish)(NSURL *, NSError *) = ^(NSURL *url, NSError *err) {
		if (completionCalled) return;
		completionCalled = YES;
		dispatch_async(dispatch_get_main_queue(), ^{ if (completion) completion(url, err); });
	};
	__block atomic_bool thisCancelled;
	atomic_init(&thisCancelled, false);
	__block NSURLSession *sessionRef = nil;
	__block long ffmpegSidRef = 0;
	BOOL (^cancelled)(void) = ^BOOL{ return atomic_load(&thisCancelled); };
	void (^cancelSelf)(void) = ^{
		atomic_store(&thisCancelled, true);
		NSURLSession *s = sessionRef;
		if (s) { @try { [s invalidateAndCancel]; } @catch (__unused id e) {} }
		long sid = ffmpegSidRef;
		SEL cancelSel = NSSelectorFromString(@"cancel:");
		if (sid && FFmpegKitClass && [FFmpegKitClass respondsToSelector:cancelSel]) {
			@try { ((void(*)(id, SEL, long))objc_msgSend)(FFmpegKitClass, cancelSel, sid); } @catch (__unused id e) {}
		}
	};
	if (cancelOut) cancelOut(cancelSelf);
	void (^report)(float, NSString *) = ^(float p, NSString *stage) {
		if (!progressBlock || cancelled()) return;
		dispatch_async(dispatch_get_main_queue(), ^{ progressBlock(p, stage); });
	};
	dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
		NSString *photoPath = [RYGTempFiles claimWithExt:@"jpg" ttl:300 tag:@"photo"].path;
		NSString *audioPath = [RYGTempFiles claimWithExt:@"mp4" ttl:300 tag:@"audio"].path;
		NSString *stem = rygSafeFileStem([RYGMediaActions currentFilenameStem]);
		__block NSString *outputPath = [RYGTempFiles claimNamedFile:[NSString stringWithFormat:@"%@.mp4", stem] ttl:900 tag:@"mux"].path;
		NSError *(^cancelledError)(void) = ^NSError *{ return rygError(NSUserCancelledError, RYGLocalized(@"Cancelled")); };
		void (^cleanup)(BOOL removeOutput) = ^(BOOL removeOutput) {
			NSFileManager *fm = NSFileManager.defaultManager;
			[fm removeItemAtPath:photoPath error:nil];
			[fm removeItemAtPath:audioPath error:nil];
			if (removeOutput) [fm removeItemAtPath:outputPath error:nil];
		};
		NSURLSessionConfiguration *cfg = NSURLSessionConfiguration.ephemeralSessionConfiguration;
		cfg.requestCachePolicy = NSURLRequestReloadIgnoringLocalCacheData;
		cfg.timeoutIntervalForRequest = 30.0;
		cfg.timeoutIntervalForResource = 300.0;
		NSURLSession *session = [NSURLSession sessionWithConfiguration:cfg];
		sessionRef = session;
		rygRegisterSession(session);
		report(0.0f, RYGLocalized(@"Downloading…"));
		BOOL photoOK = rygDownloadToPath(session, photoURL, photoPath, cancelled, ^(float p) { report(p * 0.2f, RYGLocalized(@"Downloading…")); });
		if (cancelled()) { rygUnregisterSession(session); [session invalidateAndCancel]; cleanup(YES); finish(nil, cancelledError()); return; }
		if (!photoOK || ![NSFileManager.defaultManager fileExistsAtPath:photoPath]) { rygUnregisterSession(session); [session invalidateAndCancel]; cleanup(YES); finish(nil, rygError(2, RYGLocalized(@"Download failed"))); return; }
		report(0.2f, RYGLocalized(@"Downloading audio…"));
		BOOL audioOK = rygDownloadToPath(session, audioURL, audioPath, cancelled, ^(float p) { report(0.2f + p * 0.3f, RYGLocalized(@"Downloading audio…")); });
		rygUnregisterSession(session);
		[session invalidateAndCancel];
		if (cancelled()) { cleanup(YES); finish(nil, cancelledError()); return; }
		if (!audioOK || ![NSFileManager.defaultManager fileExistsAtPath:audioPath]) { cleanup(YES); finish(nil, rygError(2, RYGLocalized(@"Download failed"))); return; }

		report(0.5f, RYGLocalized(@"Encoding…"));
		double durSec = MAX(1.0, durationMs / 1000.0);
		double startSec = MAX(0.0, audioStartMs / 1000.0);
		NSString *swVenc = @"-c:v libx264 -preset veryfast -crf 20 -tune stillimage";
		NSString *venc = [self hasEncoder:@"h264_videotoolbox"] ? @"-c:v h264_videotoolbox -b:v 6M -allow_sw 1" : swVenc;
		BOOL vtPreferred = [venc containsString:@"h264_videotoolbox"];
		__block NSString *aenc = @"-c:a aac -b:a 192k";
		// 3fps: every frame is identical, more only slows the encode.
		NSString *(^buildCmd)(NSString *, NSString *) = ^NSString *(NSString *v, NSString *outPath) {
			return [NSString stringWithFormat:
				@"-y -hide_banner -loop 1 -framerate 3 -i %@ -ss %.3f -i %@ -t %.3f -map 0:v:0 -map 1:a:0 "
				@"-vf scale=trunc(iw/2)*2:trunc(ih/2)*2,format=yuv420p %@ %@ -movflags +faststart %@",
				rygQuote(photoPath), startSec, rygQuote(audioPath), durSec, v, aenc, rygQuote(outPath)];
		};
		void (^statsCallback)(id) = ^(id stats) {
			double timeMs = rygCallDoubleGetter(stats, @"getTime");
			if (timeMs > 0) {
				float enc = (float)MIN(1.0, MAX(0.0, timeMs / durationMs));
				report(0.5f + 0.5f * enc, [NSString stringWithFormat:RYGLocalized(@"Encoding %d%%"), (int)(enc * 100)]);
			}
		};
		void (^onSID)(long) = ^(long sid) { ffmpegSidRef = sid; };

		NSString *ffOutput = nil;
		RYGMuxRun run = RYGMuxRunFailed;
		NSTimeInterval stall = kRYGMuxStallSeconds;
		for (int attempt = 0; attempt < 3; attempt++) {
			BOOL wantSW = vtPreferred && swVenc && (attempt == 2 || rygAppInBackground());
			NSString *v = wantSW ? swVenc : venc;
			BOOL vt = !wantSW && vtPreferred;
			if (attempt > 0) {
				outputPath = [RYGTempFiles claimNamedFile:[NSString stringWithFormat:@"%@.mp4", stem] ttl:900 tag:@"mux"].path;
				report(0.5f, RYGLocalized(@"Encoding…"));
			}
			BOOL bgKilled = NO;
			run = rygRunMuxCommand(buildCmd(v, outputPath), vt, stall, statsCallback, onSID, &ffOutput, &bgKilled);
			if (run == RYGMuxRunOK || cancelled()) break;
			if (![aenc isEqualToString:@"-c:a copy"] && rygOutputLooksLikeAudioDecodeFail(ffOutput)) {
				NSLog(@"[RyukGram][FFmpeg] photo-mux audio can't be decoded (likely xHE-AAC) — retrying with stream copy");
				aenc = @"-c:a copy";
				continue;
			}
			BOOL vtDeath = vt && (bgKilled || run == RYGMuxRunStalled || rygOutputLooksLikeVTDeath(ffOutput));
			if (!vtDeath || !swVenc) break;
			stall = (run == RYGMuxRunStalled) ? kRYGRetryStartupStallSeconds : kRYGMuxStallSeconds;
			NSLog(@"[RyukGram][FFmpeg] VT photo encode died (attempt=%d run=%ld bgKilled=%d) — retrying", attempt + 1, (long)run, bgKilled);
			if (bgKilled) [NSThread sleepForTimeInterval:2.0];
			if (cancelled()) break;
		}
		cleanup(NO);
		if (cancelled()) { cleanup(YES); finish(nil, cancelledError()); return; }
		if (run == RYGMuxRunOK && [NSFileManager.defaultManager fileExistsAtPath:outputPath]) finish([NSURL fileURLWithPath:outputPath], nil);
		else { cleanup(YES); finish(nil, rygError(3, run == RYGMuxRunStalled ? RYGLocalized(@"Video encoder locked up — restart Instagram to encode again") : (ffOutput ?: RYGLocalized(@"FFmpeg mux failed")))); }
	});
}

+ (BOOL)hasEncoder:(NSString *)encoderName {
	if (!encoderName.length) return NO;
	dispatch_once(&rygEncoderOnce, ^{
		if (![self isAvailable]) { rygEncoderSet = [NSSet set]; return; }
		SEL executeSel = NSSelectorFromString(@"execute:");
		if (![FFmpegKitClass respondsToSelector:executeSel]) { rygEncoderSet = [NSSet set]; return; }
		NSMutableSet *set = [NSMutableSet set];
		@try {
			id session = ((id(*)(id, SEL, id))objc_msgSend)(FFmpegKitClass, executeSel, @"-hide_banner -encoders");
			NSString *output = nil;
			rygSessionSuccess(session, &output);
			if (output.length) {
				for (NSString *line in [output componentsSeparatedByCharactersInSet:[NSCharacterSet newlineCharacterSet]]) {
					NSString *trimmed = [line stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceCharacterSet]];
					if (trimmed.length < 8) continue;
					NSArray *parts = [trimmed componentsSeparatedByCharactersInSet:[NSCharacterSet whitespaceCharacterSet]];
					if (parts.count < 2) continue;
					NSString *flags = parts[0];
					if (flags.length < 6) continue;
					if (![flags hasPrefix:@"V"] && ![flags hasPrefix:@"A"] && ![flags hasPrefix:@"S"]) continue;
					[set addObject:parts[1]];
				}
			}
		} @catch (__unused id e) {}
		rygEncoderSet = [set copy];
	});
	return [rygEncoderSet containsObject:encoderName];
}

// Background fallback: the user's encode settings translated onto libx264. Bitrate/CRF,
// profile, level, tune, pix_fmt and fps cap carry over — only the preset is forced fast.
+ (NSString *)softwareFallbackVideoArgsForPreset:(NSString *)fallbackPreset {
	NSMutableString *v = [NSMutableString stringWithString:@"-c:v libx264 -preset ultrafast"];
	if (![RYGUtils getBoolPref:@"adv_encoding_enabled"]) {
		NSString *preset = fallbackPreset.length ? fallbackPreset : [RYGUtils getStringPref:@"ffmpeg_encoding_speed"];
		NSString *bv = @"8M";
		if ([preset isEqualToString:@"max"]) bv = @"50M";
		else if ([preset isEqualToString:@"fast"]) bv = @"20M";
		else if ([preset isEqualToString:@"veryfast"]) bv = @"12M";
		[v appendFormat:@" -b:v %@ -pix_fmt yuv420p", bv];
		return v;
	}
	NSString *profile = [RYGUtils getStringPref:@"adv_h264_profile"];
	if (profile.length) [v appendFormat:@" -profile:v %@", profile];
	NSString *level = [RYGUtils getStringPref:@"adv_h264_level"];
	if (level.length && ![level isEqualToString:@"auto"]) [v appendFormat:@" -level %@", level];
	NSString *tune = [RYGUtils getStringPref:@"adv_tune"];
	if (tune.length && ![tune isEqualToString:@"none"]) [v appendFormat:@" -tune %@", tune];
	NSString *bitrate = [[RYGUtils getStringPref:@"adv_video_bitrate"] stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceCharacterSet]];
	if (bitrate.length) [v appendFormat:@" -b:v %@", bitrate];
	else {
		NSString *crfStr = [RYGUtils getStringPref:@"adv_crf"];
		NSInteger crf = crfStr.length ? crfStr.integerValue : 18;
		if (crf < 0 || crf > 51) crf = 18;
		[v appendFormat:@" -crf %ld", (long)crf];
	}
	NSString *pixFmt = [RYGUtils getStringPref:@"adv_pixel_format"];
	[v appendFormat:@" -pix_fmt %@", pixFmt.length ? pixFmt : @"yuv420p"];
	NSString *fps = [RYGUtils getStringPref:@"adv_fps"];
	if (fps.length && ![fps isEqualToString:@"original"]) [v appendFormat:@" -r %@", fps];
	return v;
}

+ (NSDictionary<NSString *, NSString *> *)encodingArgsForFallbackPreset:(NSString *)fallbackPreset {
	BOOL advanced = [RYGUtils getBoolPref:@"adv_encoding_enabled"];
	if (!advanced) {
		// Simple mode: preset menu drives bitrate on hardware h264. Tuned for IG source (8-12 Mbit).
		NSString *preset = fallbackPreset.length ? fallbackPreset : [RYGUtils getStringPref:@"ffmpeg_encoding_speed"];
		if (!preset.length) preset = @"ultrafast";
		NSString *encFlags = @"-b:v 8M";
		if ([preset isEqualToString:@"max"]) encFlags = @"-b:v 50M -profile:v high -level 5.1 -coder cabac";
		else if ([preset isEqualToString:@"fast"]) encFlags = @"-b:v 20M";
		else if ([preset isEqualToString:@"veryfast"]) encFlags = @"-b:v 12M";
		return @{
			@"video": [NSString stringWithFormat:@"-c:v h264_videotoolbox %@ -allow_sw 1", encFlags],
			@"audio": @"-c:a copy",
			@"container": @"-movflags +faststart",
			@"filter": @"",
		};
	}

	// libx264 pix_fmt must match profile (yuv420p10le→high10, yuv422p→high422, yuv444p→high444).
	// scale "-2:N" only downscales taller-than-target, even width.
	NSString *codec = [RYGUtils getStringPref:@"adv_video_codec"];
	if (!codec.length) codec = @"h264_videotoolbox";
	if (![codec isEqualToString:@"h264_videotoolbox"] && ![self hasEncoder:codec]) {
		NSLog(@"[RyukGram][FFmpeg] Encoder '%@' not available — falling back to h264_videotoolbox", codec);
		static dispatch_once_t warnOnce;
		dispatch_once(&warnOnce, ^{
			dispatch_async(dispatch_get_main_queue(), ^{
				RYGNotifyWarning(RYG_NOTIF_GENERIC,
					RYGLocalized(@"Encoder unavailable"),
					([NSString stringWithFormat:RYGLocalized(@"'%@' is not in this FFmpegKit build — using hardware h264 instead."), codec]));
			});
		});
		codec = @"h264_videotoolbox";
	}
	BOOL isHW = [codec isEqualToString:@"h264_videotoolbox"];

	NSMutableString *video = [NSMutableString stringWithFormat:@"-c:v %@", codec];

	NSString *profile = [RYGUtils getStringPref:@"adv_h264_profile"];
	if (profile.length) [video appendFormat:@" -profile:v %@", profile];

	NSString *level = [RYGUtils getStringPref:@"adv_h264_level"];
	if (level.length && ![level isEqualToString:@"auto"]) [video appendFormat:@" -level %@", level];

	NSString *bitrate = [[RYGUtils getStringPref:@"adv_video_bitrate"] stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceCharacterSet]];
	NSString *crfStr = [RYGUtils getStringPref:@"adv_crf"];
	NSInteger crf = crfStr.length ? crfStr.integerValue : 18;
	if (crf < 0 || crf > 51) crf = 18;

	if (!isHW) {
		NSString *preset = [RYGUtils getStringPref:@"adv_preset"];
		if (!preset.length) preset = @"medium";
		[video appendFormat:@" -preset %@", preset];
		NSString *tune = [RYGUtils getStringPref:@"adv_tune"];
		if (tune.length && ![tune isEqualToString:@"none"]) [video appendFormat:@" -tune %@", tune];
		// User bitrate wins over CRF (default 18, visually lossless).
		if (bitrate.length) [video appendFormat:@" -b:v %@", bitrate];
		else [video appendFormat:@" -crf %ld", (long)crf];
		NSString *pixFmt = [RYGUtils getStringPref:@"adv_pixel_format"];
		if (!pixFmt.length) pixFmt = @"yuv420p";
		[video appendFormat:@" -pix_fmt %@", pixFmt];
	} else {
		// VT always needs -b:v; fall back to 8M when blank.
		[video appendFormat:@" -b:v %@", bitrate.length ? bitrate : @"8M"];
		[video appendFormat:@" -crf %ld", (long)crf];
		[video appendString:@" -allow_sw 1"];
		NSString *pixFmt = [RYGUtils getStringPref:@"adv_pixel_format"];
		if (pixFmt.length && ![pixFmt isEqualToString:@"yuv420p"]) {
			static dispatch_once_t pixWarn;
			NSString *picked = pixFmt;
			dispatch_once(&pixWarn, ^{
				dispatch_async(dispatch_get_main_queue(), ^{
					RYGNotifyWarning(RYG_NOTIF_GENERIC,
						RYGLocalized(@"Pixel format ignored"),
						([NSString stringWithFormat:RYGLocalized(@"Hardware (VideoToolbox) only supports yuv420p — '%@' was ignored. Switch to Software (libx264) to use it."), picked]));
				});
			});
		}
	}

	// Output frame-rate cap (applies to both encoders).
	NSString *fps = [RYGUtils getStringPref:@"adv_fps"];
	if (fps.length && ![fps isEqualToString:@"original"]) [video appendFormat:@" -r %@", fps];

	NSString *audioCodec = [RYGUtils getStringPref:@"adv_audio_codec"];
	if (!audioCodec.length) audioCodec = @"copy";
	NSMutableString *audio = [NSMutableString stringWithFormat:@"-c:a %@", audioCodec];
	if (![audioCodec isEqualToString:@"copy"]) {
		NSString *abr = [RYGUtils getStringPref:@"adv_audio_bitrate"];
		if (abr.length) [audio appendFormat:@" -b:a %@", abr];
		NSString *channels = [RYGUtils getStringPref:@"adv_audio_channels"];
		if ([channels isEqualToString:@"stereo"]) [audio appendString:@" -ac 2"];
		else if ([channels isEqualToString:@"mono"]) [audio appendString:@" -ac 1"];
		NSString *ar = [RYGUtils getStringPref:@"adv_audio_samplerate"];
		if (ar.length && ![ar isEqualToString:@"original"]) [audio appendFormat:@" -ar %@", ar];
	}

	NSString *maxRes = [RYGUtils getStringPref:@"adv_max_resolution"];
	NSString *filter = @"";
	if (maxRes.length && ![maxRes isEqualToString:@"original"]) {
		filter = [NSString stringWithFormat:@"-vf scale=-2:%@", maxRes];
	}

	NSMutableString *container = [NSMutableString stringWithString:[RYGUtils getBoolPref:@"adv_faststart"] ? @"-movflags +faststart" : @""];
	if ([RYGUtils getBoolPref:@"adv_strip_metadata"]) {
		if (container.length) [container appendString:@" "];
		[container appendString:@"-map_metadata -1"];
	}

	return @{
		@"video": [video copy],
		@"audio": [audio copy],
		@"container": container,
		@"filter": filter,
	};
}

@end
