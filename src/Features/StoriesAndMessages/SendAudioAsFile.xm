// Send audio/video files as voice messages in DMs. Adds an Upload Audio item to
// the DM plus menu, trims + transcodes to AAC m4a, then feeds IG's voice pipeline.

#import "../../Utils.h"
#import "../../InstagramHeaders.h"
#import "../../RYGFFmpeg.h"
#import "../../RYGTempFiles.h"
#import "../../Background/RYGBackgroundActivity.h"
#import "../../RYGTrimViewController.h"
#import "../../Tweak.h"
#import "../../Gallery/RYGGalleryViewController.h"
#import "../../Gallery/RYGGalleryFile.h"

#import <objc/runtime.h>
#import <objc/message.h>
#import <AVFoundation/AVFoundation.h>
#import <PhotosUI/PhotosUI.h>

typedef id (*RYGObjMsgSend)(id, SEL);

static inline id rygCall(id obj, SEL sel) {
	if (!obj || ![obj respondsToSelector:sel]) return nil;
	return ((RYGObjMsgSend)objc_msgSend)(obj, sel);
}

static __weak UIViewController *rygAudioThreadVC = nil;
static BOOL rygDMMenuPending = NO;

#pragma mark - Small helpers

static NSString *rygLowerExt(NSURL *url) {
	return url.pathExtension.lowercaseString ?: @"";
}

static BOOL rygHasValidTrim(CMTimeRange range) {
	return CMTIMERANGE_IS_VALID(range) &&
		!CMTIMERANGE_IS_EMPTY(range) &&
		CMTimeGetSeconds(range.duration) > 0.0;
}

static UIViewController *rygTopPresenter(UIViewController *vc) {
	UIViewController *top = vc ?: UIApplication.sharedApplication.keyWindow.rootViewController;
	while (top.presentedViewController) top = top.presentedViewController;
	return top;
}

static UIViewController *rygThreadVCForButton(UIButton *button) {
	UIViewController *cached = rygAudioThreadVC;
	if (cached && cached.view.window) return cached;

	for (UIResponder *r = button; r; r = r.nextResponder) {
		if ([r isKindOfClass:NSClassFromString(@"IGDirectThreadViewController")]) {
			return (UIViewController *)r;
		}
	}

	return nil;
}

static NSSet<NSString *> *rygPassthroughAudioExts(void) {
	static NSSet *set;
	static dispatch_once_t once;
	dispatch_once(&once, ^{
		set = [NSSet setWithArray:@[@"m4a", @"aac", @"ogg", @"opus"]];
	});
	return set;
}

static CGFloat rygAudioDurationFromAsset(AVAsset *asset) {
	Float64 duration = CMTimeGetSeconds(asset.duration);
	return (duration > 0.0 && !isnan(duration) && isfinite(duration)) ? (CGFloat)duration : 1.0;
}

static CGFloat rygAudioDuration(NSURL *url) {
	return rygAudioDurationFromAsset([AVAsset assetWithURL:url]);
}

static BOOL rygAssetHasAudio(AVAsset *asset) {
	return [[asset tracksWithMediaType:AVMediaTypeAudio] firstObject] != nil;
}

#pragma mark - Waveform

static NSArray *rygFallbackWaveform(CGFloat duration) {
	NSInteger count = MAX(10, MIN((NSInteger)(duration * 10.0), 300));
	NSMutableArray *items = [NSMutableArray arrayWithCapacity:count];

	for (NSInteger i = 0; i < count; i++) {
		[items addObject:@(0.12 + (arc4random_uniform(70) / 100.0))];
	}

	return items;
}

static id rygMakeWaveform(NSURL *audioURL, CGFloat duration) {
	Class wfClass = NSClassFromString(@"IGDirectAudioWaveform");
	NSArray *raw = rygFallbackWaveform(duration);

	if (!wfClass) return raw;

	SEL genSel = @selector(generateWaveformDataFromAudioFile:maxLength:);
	if ([wfClass respondsToSelector:genSel]) {
		typedef id (*GenFn)(id, SEL, id, NSInteger);
		NSArray *generated = ((GenFn)objc_msgSend)(wfClass, genSel, audioURL, (NSInteger)(duration * 10.0));
		if (generated.count) raw = generated;
	}

	SEL scaleSel = @selector(scaledArrayOfNumbers:);
	if ([wfClass respondsToSelector:scaleSel]) {
		typedef id (*ScaleFn)(id, SEL, id);
		NSArray *scaled = ((ScaleFn)objc_msgSend)(wfClass, scaleSel, raw);
		if (scaled.count) raw = scaled;
	}

	SEL initSel = @selector(initWithVolumeRecordingInterval:averageVolume:);
	if ([wfClass instancesRespondToSelector:initSel]) {
		typedef id (*InitFn)(id, SEL, double, id);
		id waveform = ((InitFn)objc_msgSend)([wfClass alloc], initSel, 0.1, raw);
		if (waveform) return waveform;
	}

	id waveform = [[wfClass alloc] init];
	for (NSString *ivarName in @[@"_averageVolume", @"_waveformData", @"_data", @"_volumes"]) {
		Ivar ivar = class_getInstanceVariable(wfClass, ivarName.UTF8String);
		if (!ivar) continue;

		object_setIvar(waveform, ivar, raw);
		return waveform;
	}

	return raw;
}

#pragma mark - Native voice send

static id rygFeatureManagerForThreadVC(UIViewController *threadVC) {
	if (!threadVC) return nil;

	@try {
		id manager = [threadVC valueForKey:@"featureManager"];
		if (manager) return manager;
	} @catch (__unused id e) {}

	Ivar ivar = class_getInstanceVariable([threadVC class], "_featureManager");
	return ivar ? object_getIvar(threadVC, ivar) : nil;
}

static id rygVoiceControllerForThreadVC(UIViewController *threadVC) {
	id voiceController = rygCall(threadVC, @selector(voiceController));
	if (voiceController) return voiceController;

	id manager = rygFeatureManagerForThreadVC(threadVC);
	voiceController = rygCall(manager, @selector(voiceController));
	if (voiceController) return voiceController;

	Ivar ivar = manager ? class_getInstanceVariable([manager class], "_voiceController") : NULL;
	return ivar ? object_getIvar(manager, ivar) : nil;
}

static id rygVoiceRecordVC(UIViewController *threadVC) {
	id voiceController = rygVoiceControllerForThreadVC(threadVC);
	if (!voiceController) return nil;

	Ivar ivar = class_getInstanceVariable([voiceController class], "_voiceRecordViewController");
	return ivar ? object_getIvar(voiceController, ivar) : nil;
}

static BOOL rygSendToTarget(id target, id voiceRecordVC, NSURL *audioURL, id waveform, CGFloat duration) {
	if (!target) return NO;

	SEL v430Sel = @selector(voiceRecordViewController:didRecordAudioClipWithURL:waveform:duration:entryPoint:aiVoiceEffectApplied:aiVoiceEffectType:sendButtonTypeTapped:);
	if ([target respondsToSelector:v430Sel]) {
		typedef void (*Fn)(id, SEL, id, id, id, CGFloat, NSInteger, id, id, NSInteger);
		((Fn)objc_msgSend)(target, v430Sel, voiceRecordVC, audioURL, waveform, duration, 2, nil, nil, 0);
		return YES;
	}

	SEL oldSevenSel = @selector(voiceRecordViewController:didRecordAudioClipWithURL:waveform:duration:entryPoint:aiVoiceEffectApplied:sendButtonTypeTapped:);
	if ([target respondsToSelector:oldSevenSel]) {
		typedef void (*Fn)(id, SEL, id, id, id, CGFloat, NSInteger, id, id);
		((Fn)objc_msgSend)(target, oldSevenSel, voiceRecordVC, audioURL, waveform, duration, 2, nil, nil);
		return YES;
	}

	SEL oldFiveSel = @selector(voiceRecordViewController:didRecordAudioClipWithURL:waveform:duration:entryPoint:);
	if ([target respondsToSelector:oldFiveSel]) {
		typedef void (*Fn)(id, SEL, id, id, id, CGFloat, NSInteger);
		((Fn)objc_msgSend)(target, oldFiveSel, voiceRecordVC, audioURL, waveform, duration, 2);
		return YES;
	}

	return NO;
}

static BOOL rygTrySendThroughThreadVC(UIViewController *threadVC, NSURL *audioURL, id waveform, CGFloat duration) {
	id voiceController = rygVoiceControllerForThreadVC(threadVC);
	id voiceRecordVC = rygVoiceRecordVC(threadVC);

	if (rygSendToTarget(voiceController, voiceRecordVC, audioURL, waveform, duration)) return YES;
	if (rygSendToTarget(threadVC, voiceRecordVC, audioURL, waveform, duration)) return YES;

	SEL vmSel = @selector(visualMessageViewerPresentationManagerDidRecordAudioClipWithURL:waveform:duration:entryPoint:toReplyToMessageWithID:);
	if ([threadVC respondsToSelector:vmSel]) {
		typedef void (*Fn)(id, SEL, id, id, double, NSInteger, id);
		((Fn)objc_msgSend)(threadVC, vmSel, audioURL, waveform, (double)duration, 2, nil);
		return YES;
	}

	return NO;
}

static void rygSendAudioFile(NSURL *audioURL, UIViewController *threadVC) {
	[RYGBackgroundActivity setSource:@"audio_send" active:NO];
	if (!audioURL || !threadVC) return;

	CGFloat duration = rygAudioDuration(audioURL);
	id waveform = rygMakeWaveform(audioURL, duration);

	@try {
		if (rygTrySendThroughThreadVC(threadVC, audioURL, waveform, duration)) {
			RYGNotifySuccess(RYG_NOTIF_VOICE_SEND, RYGLocalized(@"Audio sent"), nil);
			return;
		}

		[RYGUtils showErrorHUDWithDescription:RYGLocalized(@"No voice send method found")];
	} @catch (NSException *e) {
		[RYGUtils showErrorHUDWithDescription:[NSString stringWithFormat:RYGLocalized(@"Send failed: %@"), e.reason ?: @""]];
	}
}

#pragma mark - Conversion

static void rygShowUnsupportedAlert(NSURL *url, NSString *reason, UIViewController *threadVC) {
	[RYGBackgroundActivity setSource:@"audio_send" active:NO];

	NSString *ext = rygLowerExt(url);
	NSString *display = ext.length ? [NSString stringWithFormat:@".%@", ext] : RYGLocalized(@"This file");
	NSString *title = [NSString stringWithFormat:RYGLocalized(@"%@ can't be converted"), display];

	NSString *body = [NSString stringWithFormat:
		RYGLocalized(@"iOS audio APIs couldn't process this file%@%@\n\nYou can try sending it to Instagram as-is, or open a support issue."),
		reason.length ? @":\n" : @".",
		reason.length ? reason : @""];

	UIAlertController *alert = [UIAlertController alertControllerWithTitle:title
																   message:body
															preferredStyle:UIAlertControllerStyleAlert];

	__weak UIViewController *weakVC = threadVC;

	[alert addAction:[UIAlertAction actionWithTitle:RYGLocalized(@"Send anyway")
											  style:UIAlertActionStyleDefault
											handler:^(UIAlertAction *a) {
		(void)a;

		UIViewController *vc = weakVC;
		if (vc) rygSendAudioFile(url, vc);
	}]];

	[alert addAction:[UIAlertAction actionWithTitle:RYGLocalized(@"Open GitHub")
											  style:UIAlertActionStyleDefault
											handler:^(UIAlertAction *a) {
		(void)a;

		NSURL *issueURL = [NSURL URLWithString:RYGRepoIssuesURL];
		if (issueURL) [UIApplication.sharedApplication openURL:issueURL options:@{} completionHandler:nil];
	}]];

	[alert addAction:[UIAlertAction actionWithTitle:RYGLocalized(@"Cancel")
											  style:UIAlertActionStyleCancel
											handler:nil]];

	[rygTopPresenter(threadVC) presentViewController:alert animated:YES completion:nil];
}

static void rygFFmpegConvertAndSend(NSURL *url, UIViewController *threadVC, CMTimeRange trimRange) {
	NSURL *outURL = [RYGTempFiles claimWithExt:@"m4a" ttl:300 tag:@"ffaudio"];

	NSMutableString *cmd = [NSMutableString stringWithFormat:@"-y -i \"%@\"", url.path];

	if (rygHasValidTrim(trimRange)) {
		[cmd appendFormat:@" -ss %.3f -t %.3f",
			CMTimeGetSeconds(trimRange.start),
			CMTimeGetSeconds(trimRange.duration)];
	}

	[cmd appendFormat:@" -vn -c:a aac -b:a 128k -ar 44100 -ac 1 \"%@\"", outURL.path];

	[RYGFFmpeg executeCommand:cmd completion:^(BOOL success, NSString *output) {
		(void)output;

		dispatch_async(dispatch_get_main_queue(), ^{
			if (success && [NSFileManager.defaultManager fileExistsAtPath:outURL.path]) {
				rygSendAudioFile(outURL, threadVC);
			} else {
				[RYGTempFiles releaseURL:outURL];
				rygShowUnsupportedAlert(url, RYGLocalized(@"FFmpeg conversion failed"), threadVC);
			}
		});
	}];
}

static void rygAVConvertAndSend(NSURL *url, UIViewController *threadVC, CMTimeRange trimRange, void (^failure)(NSError *error)) {
	dispatch_async(dispatch_get_global_queue(QOS_CLASS_USER_INITIATED, 0), ^{
		AVAsset *asset = [AVAsset assetWithURL:url];

		if (!rygAssetHasAudio(asset)) {
			dispatch_async(dispatch_get_main_queue(), ^{
				if (failure) failure(nil);
			});
			return;
		}

		NSURL *outURL = [RYGTempFiles claimWithExt:@"m4a" ttl:300 tag:@"exp"];

		AVAssetExportSession *exporter = [AVAssetExportSession exportSessionWithAsset:asset presetName:AVAssetExportPresetAppleM4A];
		if (!exporter) {
			// nil exporter never fires completion — bail via failure so keep-alive clears.
			[RYGTempFiles releaseURL:outURL];
			dispatch_async(dispatch_get_main_queue(), ^{ if (failure) failure(nil); });
			return;
		}

		exporter.outputURL = outURL;
		exporter.outputFileType = AVFileTypeAppleM4A;

		if (rygHasValidTrim(trimRange)) {
			exporter.timeRange = trimRange;
		}

		[exporter exportAsynchronouslyWithCompletionHandler:^{
			dispatch_async(dispatch_get_main_queue(), ^{
				if (exporter.status == AVAssetExportSessionStatusCompleted) {
					rygSendAudioFile(outURL, threadVC);
				} else {
					[RYGTempFiles releaseURL:outURL];
					if (failure) failure(exporter.error);
				}
			});
		}];
	});
}

static void rygExportAndSend(NSURL *url, UIViewController *threadVC, BOOL isVideo, CMTimeRange trimRange) {
	if (!url || !threadVC) return;

	BOOL hasTrim = rygHasValidTrim(trimRange);
	NSString *ext = rygLowerExt(url);

	if (!isVideo && !hasTrim && [rygPassthroughAudioExts() containsObject:ext]) {
		rygSendAudioFile(url, threadVC);
		return;
	}

	// Conversion can run a while — both terminals (send / unsupported alert) clear it.
	[RYGBackgroundActivity setSource:@"audio_send" active:YES];

	RYGNotifyInfo(RYG_NOTIF_AUDIO_EXTRACT, isVideo ? RYGLocalized(@"Extracting audio…") : RYGLocalized(@"Converting…"), nil);

	rygAVConvertAndSend(url, threadVC, trimRange, ^(NSError *error) {
		if ([RYGFFmpeg isAvailable]) {
			rygFFmpegConvertAndSend(url, threadVC, trimRange);
			return;
		}

		if (!isVideo && [rygPassthroughAudioExts() containsObject:ext]) {
			rygSendAudioFile(url, threadVC);
			return;
		}

		rygShowUnsupportedAlert(url, error.localizedDescription ?: RYGLocalized(@"no audio track could be read"), threadVC);
	});
}

#pragma mark - Trim preparation

static void rygShowUploadAudioOptions(UIViewController *threadVC);

static void rygShowTrimVC(NSURL *url, BOOL isVideo, UIViewController *threadVC) {
	if (!url || !threadVC) return;

	RYGTrimViewController *trimVC = [[RYGTrimViewController alloc] init];
	trimVC.mediaURL = url;
	trimVC.isVideo = isVideo;
	trimVC.sendButtonTitle = RYGLocalized(@"Send Audio");
	trimVC.modalPresentationStyle = UIModalPresentationFullScreen;

	__weak UIViewController *weakThread = threadVC;
	trimVC.onSend = ^(CMTimeRange trimRange) {
		UIViewController *vc = weakThread;
		if (vc) rygExportAndSend(url, vc, isVideo, trimRange);
	};
	trimVC.onBack = ^{
		UIViewController *vc = weakThread;
		if (vc) rygShowUploadAudioOptions(vc);
	};

	[threadVC presentViewController:trimVC animated:YES completion:nil];
}

static void rygFFmpegPreConvertForTrim(NSURL *url, BOOL sourceHasAudio, UIViewController *threadVC) {
	NSURL *outURL = [RYGTempFiles claimWithExt:@"m4a" ttl:600 tag:@"pre"];

	NSString *cmd = [NSString stringWithFormat:@"-y -i \"%@\" -vn -c:a aac -b:a 128k -ar 44100 \"%@\"", url.path, outURL.path];

	[RYGFFmpeg executeCommand:cmd completion:^(BOOL success, NSString *output) {
		BOOL noStream = [output containsString:@"does not contain any stream"];
		dispatch_async(dispatch_get_main_queue(), ^{
			if (success && [NSFileManager.defaultManager fileExistsAtPath:outURL.path]) {
				rygShowTrimVC(outURL, NO, threadVC);
			} else {
				[RYGTempFiles releaseURL:outURL];
				NSString *msg = (noStream || !sourceHasAudio)
					? RYGLocalized(@"No audio track found")
					: RYGLocalized(@"FFmpeg conversion failed");
				rygShowUnsupportedAlert(url, msg, threadVC);
			}
		});
	}];
}

static void rygPrepareAndShowTrim(NSURL *url, UIViewController *threadVC) {
	if (!url || !threadVC) return;

	RYGNotifyInfo(RYG_NOTIF_AUDIO_EXTRACT, RYGLocalized(@"Converting…"), nil);

	dispatch_async(dispatch_get_global_queue(QOS_CLASS_USER_INITIATED, 0), ^{
		AVAsset *asset = [AVAsset assetWithURL:url];
		BOOL canRead = rygAssetHasAudio(asset) && rygAudioDurationFromAsset(asset) > 0.0;

		if (!canRead) {
			BOOL hasAudio = rygAssetHasAudio(asset);
			dispatch_async(dispatch_get_main_queue(), ^{
				if ([RYGFFmpeg isAvailable]) {
					rygFFmpegPreConvertForTrim(url, hasAudio, threadVC);
				} else {
					rygShowUnsupportedAlert(url, RYGLocalized(@"Format not supported without FFmpegKit"), threadVC);
				}
			});
			return;
		}

		NSURL *outURL = [RYGTempFiles claimWithExt:@"m4a" ttl:600 tag:@"pre"];

		AVAssetExportSession *exporter = [AVAssetExportSession exportSessionWithAsset:asset presetName:AVAssetExportPresetAppleM4A];
		if (!exporter) {
			// nil exporter never fires completion — fall back instead of hanging on "Converting…".
			[RYGTempFiles releaseURL:outURL];

			dispatch_async(dispatch_get_main_queue(), ^{
				if ([RYGFFmpeg isAvailable]) {
					rygFFmpegPreConvertForTrim(url, YES, threadVC);
				} else {
					rygShowUnsupportedAlert(url, RYGLocalized(@"Format not supported without FFmpegKit"), threadVC);
				}
			});
			return;
		}

		exporter.outputURL = outURL;
		exporter.outputFileType = AVFileTypeAppleM4A;

		[exporter exportAsynchronouslyWithCompletionHandler:^{
			dispatch_async(dispatch_get_main_queue(), ^{
				if (exporter.status == AVAssetExportSessionStatusCompleted) {
					rygShowTrimVC(outURL, NO, threadVC);
				} else {
					[RYGTempFiles releaseURL:outURL];

					if ([RYGFFmpeg isAvailable]) {
						rygFFmpegPreConvertForTrim(url, YES, threadVC);
					} else {
						rygShowUnsupportedAlert(url, exporter.error.localizedDescription ?: RYGLocalized(@"no audio track could be read"), threadVC);
					}
				}
			});
		}];
	});
}

#pragma mark - Picker UI

static void rygShowUploadAudioOptions(UIViewController *threadVC) {
	if (!threadVC) return;

	rygAudioThreadVC = threadVC;

	UIAlertController *alert = [UIAlertController alertControllerWithTitle:RYGLocalized(@"Upload Audio")
																  message:nil
														   preferredStyle:UIAlertControllerStyleActionSheet];

	__weak UIViewController *weakVC = threadVC;

	[alert addAction:[UIAlertAction actionWithTitle:RYGLocalized(@"Audio/Video from Files")
											  style:UIAlertActionStyleDefault
											handler:^(UIAlertAction *a) {
		(void)a;

		UIViewController *vc = weakVC;
		if (!vc) return;

#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wdeprecated-declarations"
		NSArray *types = [RYGFFmpeg isAvailable]
			? @[@"public.audio", @"public.audiovisual-content"]
			: @[@"public.audio", @"public.mpeg-4-audio", @"public.mp3",
				@"com.microsoft.waveform-audio", @"public.aiff-audio",
				@"com.apple.m4a-audio", @"public.movie", @"public.mpeg-4",
				@"com.apple.quicktime-movie"];

		UIDocumentPickerViewController *picker = [[UIDocumentPickerViewController alloc] initWithDocumentTypes:types
																										inMode:UIDocumentPickerModeImport];
#pragma clang diagnostic pop

		picker.delegate = (id<UIDocumentPickerDelegate>)vc;
		[vc presentViewController:picker animated:YES completion:nil];
	}]];

	[alert addAction:[UIAlertAction actionWithTitle:RYGLocalized(@"Video from Library")
											  style:UIAlertActionStyleDefault
											handler:^(UIAlertAction *a) {
		(void)a;

		UIViewController *vc = weakVC;
		if (!vc) return;

		PHPickerConfiguration *config = [[PHPickerConfiguration alloc] init];
		config.filter = [PHPickerFilter videosFilter];
		config.selectionLimit = 1;
		config.preferredAssetRepresentationMode = PHPickerConfigurationAssetRepresentationModeCurrent;

		PHPickerViewController *picker = [[PHPickerViewController alloc] initWithConfiguration:config];
		picker.delegate = (id<PHPickerViewControllerDelegate>)vc;

		[vc presentViewController:picker animated:YES completion:nil];
	}]];

	[alert addAction:[UIAlertAction actionWithTitle:RYGLocalized(@"From RyukGram Gallery")
											  style:UIAlertActionStyleDefault
											handler:^(UIAlertAction *a) {
		(void)a;

		UIViewController *vc = weakVC;
		if (!vc) return;

		// AVAssetExportSession + AppleM4A pulls the audio track out of video picks.
		[RYGGalleryViewController presentPickerWithMediaTypes:@[@(RYGGalleryMediaTypeAudio), @(RYGGalleryMediaTypeVideo)]
														title:RYGLocalized(@"Pick audio or video")
													   fromVC:vc
												   completion:^(NSURL *pickedURL, RYGGalleryFile *pickedFile) {
			(void)pickedFile;

			if (!pickedURL) return;

			UIViewController *threadVC = rygAudioThreadVC ?: vc;
			if (threadVC) rygPrepareAndShowTrim(pickedURL, threadVC);
		}];
	}]];

	[alert addAction:[UIAlertAction actionWithTitle:RYGLocalized(@"Cancel")
											  style:UIAlertActionStyleCancel
											handler:nil]];

	[threadVC presentViewController:alert animated:YES completion:nil];
}

#pragma mark - Hooks

%group RYGSendAudioAsVoice

%hook IGDirectThreadViewController

- (void)viewDidAppear:(BOOL)animated {
	%orig;
	rygAudioThreadVC = (UIViewController *)self;
}

- (void)viewDidDisappear:(BOOL)animated {
	%orig;

	if (rygAudioThreadVC == (UIViewController *)self) {
		rygAudioThreadVC = nil;
	}
}

- (void)composerOverflowButtonMenuWillPrepareExpandWithPlusButton:(id)plusButton {
	%orig;

	rygAudioThreadVC = (UIViewController *)self;
	rygDMMenuPending = YES;
}

%new - (void)documentPicker:(UIDocumentPickerViewController *)controller didPickDocumentsAtURLs:(NSArray<NSURL *> *)urls {
	(void)controller;

	NSURL *url = urls.firstObject;
	if (!url) return;

	rygPrepareAndShowTrim(url, (UIViewController *)self);
}

%new - (void)documentPicker:(UIDocumentPickerViewController *)controller didPickDocumentAtURL:(NSURL *)url {
	(void)controller;

	if (!url) return;

	rygPrepareAndShowTrim(url, (UIViewController *)self);
}

%new - (void)documentPickerWasCancelled:(UIDocumentPickerViewController *)controller {
	(void)controller;
}

%new - (void)picker:(PHPickerViewController *)picker didFinishPicking:(NSArray<PHPickerResult *> *)results {
	[picker dismissViewControllerAnimated:YES completion:nil];

	PHPickerResult *result = results.firstObject;
	if (!result) return;

	NSItemProvider *provider = result.itemProvider;
	if (![provider hasItemConformingToTypeIdentifier:@"public.movie"]) {
		[RYGUtils showErrorHUDWithDescription:RYGLocalized(@"No video selected")];
		return;
	}

	[provider loadFileRepresentationForTypeIdentifier:@"public.movie" completionHandler:^(NSURL *url, NSError *error) {
		(void)error;

		if (!url) {
			dispatch_async(dispatch_get_main_queue(), ^{
				[RYGUtils showErrorHUDWithDescription:RYGLocalized(@"Could not extract video URL")];
			});
			return;
		}

		NSString *ext = rygLowerExt(url);
		NSURL *copyURL = [RYGTempFiles claimWithExt:ext.length ? ext : @"mov" ttl:120 tag:@"pickvid"];

		BOOL copied = [NSFileManager.defaultManager copyItemAtURL:url toURL:copyURL error:nil];

		if (!copied) {
			[RYGTempFiles releaseURL:copyURL];

			dispatch_async(dispatch_get_main_queue(), ^{
				[RYGUtils showErrorHUDWithDescription:RYGLocalized(@"Could not copy selected video")];
			});
			return;
		}

		dispatch_async(dispatch_get_main_queue(), ^{
			rygShowTrimVC(copyURL, YES, (UIViewController *)self);
		});
	}];
}

%end

%hook IGDirectComposerButtonController

- (void)_didLongPressCameraButton:(id)arg0 {
	if ([arg0 isKindOfClass:UIGestureRecognizer.class] &&
		((UIGestureRecognizer *)arg0).state != UIGestureRecognizerStateBegan) {
		return;
	}

	UIButton *button = rygCall(self, @selector(cameraButton));
	UIViewController *threadVC = rygThreadVCForButton(button);

	if (!threadVC) {
		%orig;
		return;
	}

	rygAudioThreadVC = threadVC;
	rygShowUploadAudioOptions(threadVC);
}

%end

%hook IGDSMenu

- (id)initWithMenuItems:(NSArray *)items edr:(BOOL)edr headerLabelText:(id)header {
	if (!rygDMMenuPending) return %orig;

	rygDMMenuPending = NO;

	NSString *uploadTitle = RYGLocalized(@"Upload Audio");

	for (id item in items) {
		id title = rygCall(item, @selector(title));
		if ([title isKindOfClass:NSString.class] && [title isEqualToString:uploadTitle]) {
			return %orig;
		}
	}

	Class itemClass = NSClassFromString(@"IGDSMenuItem");
	if (!itemClass) return %orig;

	SEL initSel = @selector(initWithTitle:image:handler:);
	if (![itemClass instancesRespondToSelector:initSel]) return %orig;

	UIImage *image = [[UIImage systemImageNamed:@"waveform"] imageWithRenderingMode:UIImageRenderingModeAlwaysTemplate];

	void (^handler)(void) = ^{
		UIViewController *threadVC = rygAudioThreadVC;
		if (threadVC) rygShowUploadAudioOptions(threadVC);
	};

	typedef id (*InitFn)(id, SEL, id, id, id);
	id uploadItem = ((InitFn)objc_msgSend)([itemClass alloc], initSel, uploadTitle, image, handler);
	if (!uploadItem) return %orig;

	NSMutableArray *newItems = [NSMutableArray arrayWithObject:uploadItem];
	if (items.count) [newItems addObjectsFromArray:items];

	return %orig(newItems, edr, header);
}

%end

%end

%ctor {
	if ([RYGUtils getBoolPref:@"send_audio_as_file"]) {
		%init(RYGSendAudioAsVoice);
	}
}