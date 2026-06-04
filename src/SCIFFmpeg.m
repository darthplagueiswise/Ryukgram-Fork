#import "SCIFFmpeg.h"
#import "ActionButton/SCIMediaActions.h"
#import "Utils.h"
#import "SCITempFiles.h"
#import <UIKit/UIKit.h>
#import <objc/runtime.h>
#import <objc/message.h>
#import <dlfcn.h>
#import <stdatomic.h>

static Class FFmpegKitClass;
static Class FFprobeKitClass;
static Class ReturnCodeClass;
static BOOL sciFFmpegLoaded;
static BOOL sciFFmpegChecked;
static atomic_bool sciCancelRequested;
static NSHashTable<NSURLSession *> *sciActiveURLSessions;
static NSSet<NSString *> *sciEncoderSet;
static dispatch_once_t sciEncoderOnce;

static dispatch_queue_t sciCancelQueue(void) {
	static dispatch_queue_t q;
	static dispatch_once_t once;
	dispatch_once(&once, ^{
		q = dispatch_queue_create("com.ryuk.scinsta.ffmpeg.cancel", DISPATCH_QUEUE_SERIAL);
		sciActiveURLSessions = [NSHashTable weakObjectsHashTable];
		atomic_init(&sciCancelRequested, false);
	});
	return q;
}

static void sciRegisterSession(NSURLSession *session) {
	if (!session) return;
	dispatch_sync(sciCancelQueue(), ^{ [sciActiveURLSessions addObject:session]; });
}

static void sciUnregisterSession(NSURLSession *session) {
	if (!session) return;
	dispatch_sync(sciCancelQueue(), ^{ [sciActiveURLSessions removeObject:session]; });
}

static NSArray<NSURLSession *> *sciActiveSessionsSnapshot(void) {
	__block NSArray *out = @[];
	dispatch_sync(sciCancelQueue(), ^{ out = sciActiveURLSessions.allObjects ?: @[]; });
	return out;
}

static NSString *sciDylibDir(void) {
	Dl_info info;
	if (dladdr((void *)sciDylibDir, &info) && info.dli_fname) {
		return [[NSString stringWithUTF8String:info.dli_fname] stringByDeletingLastPathComponent];
	}
	return nil;
}

static NSString *sciQuote(NSString *path) {
	if (![path isKindOfClass:NSString.class] || !path.length) return @"''";
	return [NSString stringWithFormat:@"'%@'", [path stringByReplacingOccurrencesOfString:@"'" withString:@"'\\''"]];
}

static NSError *sciError(NSInteger code, NSString *message) {
	return [NSError errorWithDomain:@"SCIFFmpeg" code:code userInfo:@{NSLocalizedDescriptionKey: message ?: SCILocalized(@"Unknown error")}];
}

static NSString *sciSafeFileStem(NSString *stem) {
	if (![stem isKindOfClass:NSString.class] || !stem.length) return [NSString stringWithFormat:@"sci_muxed_%@", NSUUID.UUID.UUIDString];
	NSCharacterSet *bad = [NSCharacterSet characterSetWithCharactersInString:@"/:\\?%*|\"<>\n\r\t"];
	NSArray *parts = [stem componentsSeparatedByCharactersInSet:bad];
	NSString *clean = [[parts componentsJoinedByString:@"_"] stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet];
	return clean.length ? clean : [NSString stringWithFormat:@"sci_muxed_%@", NSUUID.UUID.UUIDString];
}

static BOOL sciSessionSuccess(id session, NSString **outputOut) {
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
static double sciCallDoubleGetter(id obj, NSString *selName) {
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

static void sciPreloadFFmpegDeps(NSString *fwPath) {
	NSString *fwDir = [[fwPath stringByDeletingLastPathComponent] stringByDeletingLastPathComponent];
	NSArray *deps = @[@"libavutil", @"libswresample", @"libswscale", @"libavcodec", @"libavformat", @"libavfilter", @"libavdevice"];
	NSFileManager *fm = NSFileManager.defaultManager;
	for (NSString *dep in deps) {
		NSString *path = [NSString stringWithFormat:@"%@/%@.framework/%@", fwDir, dep, dep];
		if ([fm fileExistsAtPath:path]) dlopen(path.UTF8String, RTLD_NOW | RTLD_GLOBAL);
	}
}

static void sciPresentFFmpegDebug(NSArray *paths, NSArray *errors) {
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
		UIAlertController *alert = [UIAlertController alertControllerWithTitle:SCILocalized(@"FFmpegKit Debug") message:msg preferredStyle:UIAlertControllerStyleAlert];
		NSString *copyMsg = msg.copy;
		[alert addAction:[UIAlertAction actionWithTitle:SCILocalized(@"Copy") style:UIAlertActionStyleDefault handler:^(__unused UIAlertAction *a) {
			UIPasteboard.generalPasteboard.string = copyMsg;
			SCINotifySuccess(SCI_NOTIF_GENERIC, SCILocalized(@"FFmpeg log copied"), nil);
		}]];
		[alert addAction:[UIAlertAction actionWithTitle:SCILocalized(@"OK") style:UIAlertActionStyleCancel handler:nil]];
		dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(1.0 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
			UIViewController *root = UIApplication.sharedApplication.keyWindow.rootViewController;
			while (root.presentedViewController) root = root.presentedViewController;
			[root presentViewController:alert animated:YES completion:nil];
		});
	});
}

static void sciLoadFFmpegKit(void) {
	@synchronized([SCIFFmpeg class]) {
		if (sciFFmpegChecked) return;
		sciFFmpegChecked = YES;
		NSMutableArray *paths = [NSMutableArray array];
		NSString *dylibDir = sciDylibDir();
		if (dylibDir.length) [paths addObject:[dylibDir stringByAppendingPathComponent:@"ffmpegkit.framework/ffmpegkit"]];
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
			sciPreloadFFmpegDeps(fwPath);
			handle = dlopen(fwPath.UTF8String, RTLD_NOW | RTLD_GLOBAL);
			if (handle) { NSLog(@"[RyukGram] FFmpegKit loaded from %@", fwPath); break; }
			const char *err = dlerror();
			[errors addObject:[NSString stringWithFormat:@"%@\n%s", fwPath.lastPathComponent, err ?: "unknown"]];
		}
		if (!handle) {
			NSLog(@"[RyukGram] FFmpegKit not available");
			for (NSString *e in errors) NSLog(@"[RyukGram] dlopen: %@", e);
			sciPresentFFmpegDebug(paths, errors);
			return;
		}
		FFmpegKitClass = NSClassFromString(@"FFmpegKit");
		FFprobeKitClass = NSClassFromString(@"FFprobeKit");
		ReturnCodeClass = NSClassFromString(@"ReturnCode");
		if (FFmpegKitClass) {
			sciFFmpegLoaded = YES;
			NSLog(@"[RyukGram] FFmpegKit ready");
		} else {
			NSLog(@"[RyukGram] FFmpegKit classes not found after dlopen");
			dlclose(handle);
		}
	}
}

static BOOL sciMoveDownload(NSURL *location, NSString *path) {
	if (!location || !path.length) return NO;
	NSFileManager *fm = NSFileManager.defaultManager;
	NSURL *dest = [NSURL fileURLWithPath:path];
	[fm removeItemAtURL:dest error:nil];
	if ([fm moveItemAtURL:location toURL:dest error:nil]) return YES;
	[fm removeItemAtURL:dest error:nil];
	return [fm copyItemAtURL:location toURL:dest error:nil];
}

static BOOL sciDownloadToPath(NSURLSession *session, NSURL *url, NSString *path, BOOL (^cancelled)(void), void (^progress)(float)) {
	if (!session || !url || !path.length) return NO;
	dispatch_semaphore_t sem = dispatch_semaphore_create(0);
	__block BOOL ok = NO;
	__block NSError *err = nil;
	NSURLSessionDownloadTask *task = [session downloadTaskWithURL:url completionHandler:^(NSURL *loc, __unused NSURLResponse *resp, NSError *error) {
		err = error;
		if (!err && loc) ok = sciMoveDownload(loc, path);
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

@implementation SCIFFmpeg

+ (BOOL)isAvailable {
	sciLoadFFmpegKit();
	return sciFFmpegLoaded;
}

+ (BOOL)isCancelled {
	return atomic_load(&sciCancelRequested);
}

+ (void)cancelAll {
	atomic_store(&sciCancelRequested, true);
	for (NSURLSession *s in sciActiveSessionsSnapshot()) {
		@try { [s invalidateAndCancel]; } @catch (__unused id e) {}
	}
	if (FFmpegKitClass) {
		SEL cancelSel = NSSelectorFromString(@"cancel");
		if ([FFmpegKitClass respondsToSelector:cancelSel]) {
			@try { ((void(*)(id, SEL))objc_msgSend)(FFmpegKitClass, cancelSel); } @catch (__unused id e) {}
		}
	}
	dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(1.0 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
		atomic_store(&sciCancelRequested, false);
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
			BOOL success = sciSessionSuccess(session, &output);
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
			BOOL success = sciSessionSuccess(session, &output);
			dispatch_async(dispatch_get_main_queue(), ^{ if (completion) completion(success, output); });
		} @catch (NSException *e) {
			dispatch_async(dispatch_get_main_queue(), ^{ if (completion) completion(NO, e.reason); });
		}
	});
}

+ (void)convertAudioAtPath:(NSString *)inputPath toFormat:(NSString *)format bitrate:(NSString *)bitrate completion:(void(^)(NSURL *outputURL, NSError *error))completion {
	if (![self isAvailable]) { if (completion) completion(nil, sciError(1, @"FFmpegKit not available")); return; }
	NSString *fmt = format.length ? format.lowercaseString : @"m4a";
	NSString *outputPath = [SCITempFiles claimWithExt:fmt ttl:600 tag:@"audio"].path;
	NSString *br = bitrate ?: @"192k";
	NSString *codecFlag = [fmt isEqualToString:@"mp3"] ? [NSString stringWithFormat:@"-c:a libmp3lame -b:a %@", br] : [NSString stringWithFormat:@"-c:a aac -b:a %@", br];
	NSString *cmd = [NSString stringWithFormat:@"-y -hide_banner -loglevel error -i %@ -vn -map a %@ %@", sciQuote(inputPath), codecFlag, sciQuote(outputPath)];
	[self executeCommand:cmd completion:^(BOOL success, NSString *output) {
		if (success && [NSFileManager.defaultManager fileExistsAtPath:outputPath]) {
			if (completion) completion([NSURL fileURLWithPath:outputPath], nil);
		} else {
			if (completion) completion(nil, sciError(4, output ?: SCILocalized(@"Audio conversion failed")));
		}
	}];
}

+ (void)muxVideoURL:(NSURL *)videoURL audioURL:(NSURL *)audioURL preset:(NSString *)preset progress:(void(^)(float progress, NSString *stage))progressBlock completion:(void(^)(NSURL *outputURL, NSError *error))completion {
	[self muxVideoURL:videoURL audioURL:audioURL preset:preset progress:progressBlock completion:completion cancelOut:nil];
}

+ (void)muxVideoURL:(NSURL *)videoURL audioURL:(NSURL *)audioURL preset:(NSString *)preset progress:(void(^)(float progress, NSString *stage))progressBlock completion:(void(^)(NSURL *outputURL, NSError *error))completion cancelOut:(void(^)(void (^cancelBlock)(void)))cancelOut {
	if (![self isAvailable]) { if (completion) completion(nil, sciError(1, @"FFmpegKit not available")); return; }
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
		NSString *videoPath = [SCITempFiles claimWithExt:@"mp4" ttl:300 tag:@"video"].path;
		NSString *audioPath = [SCITempFiles claimWithExt:@"m4a" ttl:300 tag:@"audio"].path;
		NSString *stem = sciSafeFileStem([SCIMediaActions currentFilenameStem]);
		NSString *outputPath = [SCITempFiles claimWithExt:@"mp4" ttl:900 tag:stem].path;
		NSError *(^cancelledError)(void) = ^NSError *{ return sciError(NSUserCancelledError, SCILocalized(@"Cancelled")); };
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
		sciRegisterSession(session);
		// Download fills 0…0.5, encoding fills 0.5…1.0.
		report(0.0f, SCILocalized(@"Downloading video…"));
		BOOL videoOK = sciDownloadToPath(session, videoURL, videoPath, cancelled, ^(float p) { report(p * 0.45f, SCILocalized(@"Downloading video…")); });
		if (cancelled()) { sciUnregisterSession(session); [session invalidateAndCancel]; cleanup(YES); finish(nil, cancelledError()); return; }
		if (!videoOK || ![NSFileManager.defaultManager fileExistsAtPath:videoPath]) { sciUnregisterSession(session); [session invalidateAndCancel]; cleanup(YES); finish(nil, sciError(2, SCILocalized(@"Failed to download video"))); return; }
		report(0.45f, SCILocalized(@"Downloading audio…"));
		BOOL hasAudio = audioURL != nil;
		if (hasAudio) hasAudio = sciDownloadToPath(session, audioURL, audioPath, cancelled, nil) && [NSFileManager.defaultManager fileExistsAtPath:audioPath];
		sciUnregisterSession(session);
		[session invalidateAndCancel];
		if (cancelled()) { cleanup(YES); finish(nil, cancelledError()); return; }

		// Probe total duration so encode statistics map to a real %.
		double durationMs = 0;
		SEL probeSel = NSSelectorFromString(@"execute:");
		if (FFprobeKitClass && [FFprobeKitClass respondsToSelector:probeSel]) {
			NSString *pcmd = [NSString stringWithFormat:@"-v error -show_entries format=duration -of default=nw=1:nk=1 %@", sciQuote(videoPath)];
			@try {
				id ps = ((id(*)(id, SEL, id))objc_msgSend)(FFprobeKitClass, probeSel, pcmd);
				NSString *pout = nil; sciSessionSuccess(ps, &pout);
				durationMs = [[pout stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet] doubleValue] * 1000.0;
			} @catch (__unused id e) {}
		}

		report(0.5f, SCILocalized(@"Encoding…"));
		NSDictionary *args = [self encodingArgsForFallbackPreset:preset];
		NSString *vArgs = args[@"video"];
		NSString *aArgs = args[@"audio"];
		NSString *cArgs = args[@"container"];
		NSString *fArgs = args[@"filter"];
		// No -shortest: it can cut libx264's buffered tail before flush, freezing the
		// last frame. Same-source DASH a/v are equal length, so both end together.
		NSString *cmd = hasAudio
			? [NSString stringWithFormat:@"-y -hide_banner -analyzeduration 100M -probesize 100M -fflags +genpts -i %@ -i %@ -map 0:v:0 -map 1:a:0 %@ %@ %@ %@ %@", sciQuote(videoPath), sciQuote(audioPath), fArgs, vArgs, aArgs, cArgs, sciQuote(outputPath)]
			: [NSString stringWithFormat:@"-y -hide_banner -analyzeduration 100M -probesize 100M -fflags +genpts -i %@ %@ %@ %@ %@", sciQuote(videoPath), fArgs, vArgs, cArgs, sciQuote(outputPath)];
		__block BOOL ffSuccess = NO;
		__block NSString *ffOutput = nil;
		dispatch_semaphore_t ffSem = dispatch_semaphore_create(0);
		void (^ffCallback)(id) = ^(id ffSession) {
			ffSuccess = sciSessionSuccess(ffSession, &ffOutput);
			dispatch_semaphore_signal(ffSem);
		};
		// Real encode % from the statistics callback: time processed / total duration.
		void (^statsCallback)(id) = ^(id stats) {
			double timeMs = sciCallDoubleGetter(stats, @"getTime");
			if (durationMs > 0 && timeMs > 0) {
				float enc = (float)MIN(1.0, MAX(0.0, timeMs / durationMs));
				report(0.5f + 0.5f * enc, [NSString stringWithFormat:SCILocalized(@"Encoding %d%%"), (int)(enc * 100)]);
			}
		};

		SEL statsSel = NSSelectorFromString(@"executeAsync:withCompleteCallback:withLogCallback:withStatisticsCallback:");
		SEL asyncSel = NSSelectorFromString(@"executeAsync:withCompleteCallback:");
		SEL sidSel = NSSelectorFromString(@"getSessionId");
		if ([FFmpegKitClass respondsToSelector:statsSel]) {
			id ffSession = ((id(*)(id, SEL, id, id, id, id))objc_msgSend)(FFmpegKitClass, statsSel, cmd, ffCallback, (id)nil, statsCallback);
			if (ffSession && [ffSession respondsToSelector:sidSel]) ffmpegSidRef = ((long(*)(id, SEL))objc_msgSend)(ffSession, sidSel);
			dispatch_semaphore_wait(ffSem, DISPATCH_TIME_FOREVER);
		} else if ([FFmpegKitClass respondsToSelector:asyncSel]) {
			id ffSession = ((id(*)(id, SEL, id, id))objc_msgSend)(FFmpegKitClass, asyncSel, cmd, ffCallback);
			if (ffSession && [ffSession respondsToSelector:sidSel]) ffmpegSidRef = ((long(*)(id, SEL))objc_msgSend)(ffSession, sidSel);
			dispatch_semaphore_wait(ffSem, DISPATCH_TIME_FOREVER);
		} else {
			[SCIFFmpeg executeCommand:cmd completion:^(BOOL ok, NSString *out) {
				ffSuccess = ok;
				ffOutput = out;
				dispatch_semaphore_signal(ffSem);
			}];
			dispatch_semaphore_wait(ffSem, DISPATCH_TIME_FOREVER);
		}
		cleanup(NO);
		if (cancelled()) { cleanup(YES); finish(nil, cancelledError()); return; }
		if (ffSuccess && [NSFileManager.defaultManager fileExistsAtPath:outputPath]) finish([NSURL fileURLWithPath:outputPath], nil);
		else { cleanup(YES); finish(nil, sciError(3, ffOutput ?: SCILocalized(@"FFmpeg mux failed"))); }
	});
}

+ (BOOL)hasEncoder:(NSString *)encoderName {
	if (!encoderName.length) return NO;
	dispatch_once(&sciEncoderOnce, ^{
		if (![self isAvailable]) { sciEncoderSet = [NSSet set]; return; }
		SEL executeSel = NSSelectorFromString(@"execute:");
		if (![FFmpegKitClass respondsToSelector:executeSel]) { sciEncoderSet = [NSSet set]; return; }
		NSMutableSet *set = [NSMutableSet set];
		@try {
			id session = ((id(*)(id, SEL, id))objc_msgSend)(FFmpegKitClass, executeSel, @"-hide_banner -encoders");
			NSString *output = nil;
			sciSessionSuccess(session, &output);
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
		sciEncoderSet = [set copy];
	});
	return [sciEncoderSet containsObject:encoderName];
}

+ (NSDictionary<NSString *, NSString *> *)encodingArgsForFallbackPreset:(NSString *)fallbackPreset {
	BOOL advanced = [SCIUtils getBoolPref:@"adv_encoding_enabled"];
	if (!advanced) {
		// Simple mode: preset menu drives bitrate on hardware h264. Tuned for IG source (8-12 Mbit).
		NSString *preset = fallbackPreset.length ? fallbackPreset : [SCIUtils getStringPref:@"ffmpeg_encoding_speed"];
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
	NSString *codec = [SCIUtils getStringPref:@"adv_video_codec"];
	if (!codec.length) codec = @"h264_videotoolbox";
	if (![codec isEqualToString:@"h264_videotoolbox"] && ![self hasEncoder:codec]) {
		NSLog(@"[SCInsta][FFmpeg] Encoder '%@' not available — falling back to h264_videotoolbox", codec);
		static dispatch_once_t warnOnce;
		dispatch_once(&warnOnce, ^{
			dispatch_async(dispatch_get_main_queue(), ^{
				SCINotifyWarning(SCI_NOTIF_GENERIC,
					SCILocalized(@"Encoder unavailable"),
					([NSString stringWithFormat:SCILocalized(@"'%@' is not in this FFmpegKit build — using hardware h264 instead."), codec]));
			});
		});
		codec = @"h264_videotoolbox";
	}
	BOOL isHW = [codec isEqualToString:@"h264_videotoolbox"];

	NSMutableString *video = [NSMutableString stringWithFormat:@"-c:v %@", codec];

	NSString *profile = [SCIUtils getStringPref:@"adv_h264_profile"];
	if (profile.length) [video appendFormat:@" -profile:v %@", profile];

	NSString *level = [SCIUtils getStringPref:@"adv_h264_level"];
	if (level.length && ![level isEqualToString:@"auto"]) [video appendFormat:@" -level %@", level];

	NSString *bitrate = [[SCIUtils getStringPref:@"adv_video_bitrate"] stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceCharacterSet]];
	NSString *crfStr = [SCIUtils getStringPref:@"adv_crf"];
	NSInteger crf = crfStr.length ? crfStr.integerValue : 18;
	if (crf < 0 || crf > 51) crf = 18;

	if (!isHW) {
		NSString *preset = [SCIUtils getStringPref:@"adv_preset"];
		if (!preset.length) preset = @"medium";
		[video appendFormat:@" -preset %@", preset];
		NSString *tune = [SCIUtils getStringPref:@"adv_tune"];
		if (tune.length && ![tune isEqualToString:@"none"]) [video appendFormat:@" -tune %@", tune];
		// User bitrate wins over CRF (default 18, visually lossless).
		if (bitrate.length) [video appendFormat:@" -b:v %@", bitrate];
		else [video appendFormat:@" -crf %ld", (long)crf];
		NSString *pixFmt = [SCIUtils getStringPref:@"adv_pixel_format"];
		if (!pixFmt.length) pixFmt = @"yuv420p";
		[video appendFormat:@" -pix_fmt %@", pixFmt];
	} else {
		// VT always needs -b:v; fall back to 8M when blank.
		[video appendFormat:@" -b:v %@", bitrate.length ? bitrate : @"8M"];
		[video appendFormat:@" -crf %ld", (long)crf];
		[video appendString:@" -allow_sw 1"];
		NSString *pixFmt = [SCIUtils getStringPref:@"adv_pixel_format"];
		if (pixFmt.length && ![pixFmt isEqualToString:@"yuv420p"]) {
			static dispatch_once_t pixWarn;
			NSString *picked = pixFmt;
			dispatch_once(&pixWarn, ^{
				dispatch_async(dispatch_get_main_queue(), ^{
					SCINotifyWarning(SCI_NOTIF_GENERIC,
						SCILocalized(@"Pixel format ignored"),
						([NSString stringWithFormat:SCILocalized(@"Hardware (VideoToolbox) only supports yuv420p — '%@' was ignored. Switch to Software (libx264) to use it."), picked]));
				});
			});
		}
	}

	// Output frame-rate cap (applies to both encoders).
	NSString *fps = [SCIUtils getStringPref:@"adv_fps"];
	if (fps.length && ![fps isEqualToString:@"original"]) [video appendFormat:@" -r %@", fps];

	NSString *audioCodec = [SCIUtils getStringPref:@"adv_audio_codec"];
	if (!audioCodec.length) audioCodec = @"copy";
	NSMutableString *audio = [NSMutableString stringWithFormat:@"-c:a %@", audioCodec];
	if (![audioCodec isEqualToString:@"copy"]) {
		NSString *abr = [SCIUtils getStringPref:@"adv_audio_bitrate"];
		if (abr.length) [audio appendFormat:@" -b:a %@", abr];
		NSString *channels = [SCIUtils getStringPref:@"adv_audio_channels"];
		if ([channels isEqualToString:@"stereo"]) [audio appendString:@" -ac 2"];
		else if ([channels isEqualToString:@"mono"]) [audio appendString:@" -ac 1"];
		NSString *ar = [SCIUtils getStringPref:@"adv_audio_samplerate"];
		if (ar.length && ![ar isEqualToString:@"original"]) [audio appendFormat:@" -ar %@", ar];
	}

	NSString *maxRes = [SCIUtils getStringPref:@"adv_max_resolution"];
	NSString *filter = @"";
	if (maxRes.length && ![maxRes isEqualToString:@"original"]) {
		filter = [NSString stringWithFormat:@"-vf scale=-2:%@", maxRes];
	}

	NSMutableString *container = [NSMutableString stringWithString:[SCIUtils getBoolPref:@"adv_faststart"] ? @"-movflags +faststart" : @""];
	if ([SCIUtils getBoolPref:@"adv_strip_metadata"]) {
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
