// Send audio/video files as voice messages in DMs. Adds an Upload Audio item to
// the DM plus menu, trims + transcodes to AAC m4a, then feeds IG's voice pipeline.

#import "../../Utils.h"
#import "../../InstagramHeaders.h"
#import "../../SCIFFmpeg.h"
#import "../../SCITempFiles.h"
#import "../../Background/SCIBackgroundActivity.h"
#import "../../SCITrimViewController.h"
#import "../../Tweak.h"
#import "../../Gallery/SCIGalleryViewController.h"
#import "../../Gallery/SCIGalleryFile.h"

#import <objc/runtime.h>
#import <objc/message.h>
#import <AVFoundation/AVFoundation.h>
#import <PhotosUI/PhotosUI.h>

typedef id (*SCIObjMsgSend)(id, SEL);

static inline id sciCall(id obj, SEL sel) {
	if (!obj || ![obj respondsToSelector:sel]) return nil;
	return ((SCIObjMsgSend)objc_msgSend)(obj, sel);
}

static __weak UIViewController *sciAudioThreadVC = nil;
static BOOL sciDMMenuPending = NO;

#pragma mark - Small helpers

static NSString *sciLowerExt(NSURL *url) {
	return url.pathExtension.lowercaseString ?: @"";
}

static BOOL sciHasValidTrim(CMTimeRange range) {
	return CMTIMERANGE_IS_VALID(range) &&
		!CMTIMERANGE_IS_EMPTY(range) &&
		CMTimeGetSeconds(range.duration) > 0.0;
}

static UIViewController *sciTopPresenter(UIViewController *vc) {
	UIViewController *top = vc ?: UIApplication.sharedApplication.keyWindow.rootViewController;
	while (top.presentedViewController) top = top.presentedViewController;
	return top;
}

static UIViewController *sciThreadVCForButton(UIButton *button) {
	UIViewController *cached = sciAudioThreadVC;
	if (cached && cached.view.window) return cached;

	for (UIResponder *r = button; r; r = r.nextResponder) {
		if ([r isKindOfClass:NSClassFromString(@"IGDirectThreadViewController")]) {
			return (UIViewController *)r;
		}
	}

	return nil;
}

static NSSet<NSString *> *sciPassthroughAudioExts(void) {
	static NSSet *set;
	static dispatch_once_t once;
	dispatch_once(&once, ^{
		set = [NSSet setWithArray:@[@"m4a", @"aac", @"ogg", @"opus"]];
	});
	return set;
}

static CGFloat sciAudioDurationFromAsset(AVAsset *asset) {
	Float64 duration = CMTimeGetSeconds(asset.duration);
	return (duration > 0.0 && !isnan(duration) && isfinite(duration)) ? (CGFloat)duration : 1.0;
}

static CGFloat sciAudioDuration(NSURL *url) {
	return sciAudioDurationFromAsset([AVAsset assetWithURL:url]);
}

static BOOL sciAssetHasAudio(AVAsset *asset) {
	return [[asset tracksWithMediaType:AVMediaTypeAudio] firstObject] != nil;
}

#pragma mark - Waveform

static NSArray *sciFallbackWaveform(CGFloat duration) {
	NSInteger count = MAX(10, MIN((NSInteger)(duration * 10.0), 300));
	NSMutableArray *items = [NSMutableArray arrayWithCapacity:count];

	for (NSInteger i = 0; i < count; i++) {
		[items addObject:@(0.12 + (arc4random_uniform(70) / 100.0))];
	}

	return items;
}

static id sciMakeWaveform(NSURL *audioURL, CGFloat duration) {
	Class wfClass = NSClassFromString(@"IGDirectAudioWaveform");
	NSArray *raw = sciFallbackWaveform(duration);

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

static id sciFeatureManagerForThreadVC(UIViewController *threadVC) {
	if (!threadVC) return nil;

	@try {
		id manager = [threadVC valueForKey:@"featureManager"];
		if (manager) return manager;
	} @catch (__unused id e) {}

	Ivar ivar = class_getInstanceVariable([threadVC class], "_featureManager");
	return ivar ? object_getIvar(threadVC, ivar) : nil;
}

static id sciVoiceControllerForThreadVC(UIViewController *threadVC) {
	id voiceController = sciCall(threadVC, @selector(voiceController));
	if (voiceController) return voiceController;

	id manager = sciFeatureManagerForThreadVC(threadVC);
	voiceController = sciCall(manager, @selector(voiceController));
	if (voiceController) return voiceController;

	Ivar ivar = manager ? class_getInstanceVariable([manager class], "_voiceController") : NULL;
	return ivar ? object_getIvar(manager, ivar) : nil;
}

static id sciVoiceRecordVC(UIViewController *threadVC) {
	id voiceController = sciVoiceControllerForThreadVC(threadVC);
	if (!voiceController) return nil;

	Ivar ivar = class_getInstanceVariable([voiceController class], "_voiceRecordViewController");
	return ivar ? object_getIvar(voiceController, ivar) : nil;
}

static BOOL sciSendToTarget(id target, id voiceRecordVC, NSURL *audioURL, id waveform, CGFloat duration) {
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

static BOOL sciTrySendThroughThreadVC(UIViewController *threadVC, NSURL *audioURL, id waveform, CGFloat duration) {
	id voiceController = sciVoiceControllerForThreadVC(threadVC);
	id voiceRecordVC = sciVoiceRecordVC(threadVC);

	if (sciSendToTarget(voiceController, voiceRecordVC, audioURL, waveform, duration)) return YES;
	if (sciSendToTarget(threadVC, voiceRecordVC, audioURL, waveform, duration)) return YES;

	SEL vmSel = @selector(visualMessageViewerPresentationManagerDidRecordAudioClipWithURL:waveform:duration:entryPoint:toReplyToMessageWithID:);
	if ([threadVC respondsToSelector:vmSel]) {
		typedef void (*Fn)(id, SEL, id, id, double, NSInteger, id);
		((Fn)objc_msgSend)(threadVC, vmSel, audioURL, waveform, (double)duration, 2, nil);
		return YES;
	}

	return NO;
}

static void sciSendAudioFile(NSURL *audioURL, UIViewController *threadVC) {
	[SCIBackgroundActivity setSource:@"audio_send" active:NO];
	if (!audioURL || !threadVC) return;

	CGFloat duration = sciAudioDuration(audioURL);
	id waveform = sciMakeWaveform(audioURL, duration);

	@try {
		if (sciTrySendThroughThreadVC(threadVC, audioURL, waveform, duration)) {
			SCINotifySuccess(SCI_NOTIF_VOICE_SEND, SCILocalized(@"Audio sent"), nil);
			return;
		}

		[SCIUtils showErrorHUDWithDescription:SCILocalized(@"No voice send method found")];
	} @catch (NSException *e) {
		[SCIUtils showErrorHUDWithDescription:[NSString stringWithFormat:SCILocalized(@"Send failed: %@"), e.reason ?: @""]];
	}
}

#pragma mark - Conversion

static void sciShowUnsupportedAlert(NSURL *url, NSString *reason, UIViewController *threadVC) {
	[SCIBackgroundActivity setSource:@"audio_send" active:NO];

	NSString *ext = sciLowerExt(url);
	NSString *display = ext.length ? [NSString stringWithFormat:@".%@", ext] : SCILocalized(@"This file");
	NSString *title = [NSString stringWithFormat:SCILocalized(@"%@ can't be converted"), display];

	NSString *body = [NSString stringWithFormat:
		SCILocalized(@"iOS audio APIs couldn't process this file%@%@\n\nYou can try sending it to Instagram as-is, or open a support issue."),
		reason.length ? @":\n" : @".",
		reason.length ? reason : @""];

	UIAlertController *alert = [UIAlertController alertControllerWithTitle:title
																   message:body
															preferredStyle:UIAlertControllerStyleAlert];

	__weak UIViewController *weakVC = threadVC;

	[alert addAction:[UIAlertAction actionWithTitle:SCILocalized(@"Send anyway")
											  style:UIAlertActionStyleDefault
											handler:^(UIAlertAction *a) {
		(void)a;

		UIViewController *vc = weakVC;
		if (vc) sciSendAudioFile(url, vc);
	}]];

	[alert addAction:[UIAlertAction actionWithTitle:SCILocalized(@"Open GitHub")
											  style:UIAlertActionStyleDefault
											handler:^(UIAlertAction *a) {
		(void)a;

		NSURL *issueURL = [NSURL URLWithString:SCIRepoIssuesURL];
		if (issueURL) [UIApplication.sharedApplication openURL:issueURL options:@{} completionHandler:nil];
	}]];

	[alert addAction:[UIAlertAction actionWithTitle:SCILocalized(@"Cancel")
											  style:UIAlertActionStyleCancel
											handler:nil]];

	[sciTopPresenter(threadVC) presentViewController:alert animated:YES completion:nil];
}

static void sciFFmpegConvertAndSend(NSURL *url, UIViewController *threadVC, CMTimeRange trimRange) {
	NSURL *outURL = [SCITempFiles claimWithExt:@"m4a" ttl:300 tag:@"ffaudio"];

	NSMutableString *cmd = [NSMutableString stringWithFormat:@"-y -i \"%@\"", url.path];

	if (sciHasValidTrim(trimRange)) {
		[cmd appendFormat:@" -ss %.3f -t %.3f",
			CMTimeGetSeconds(trimRange.start),
			CMTimeGetSeconds(trimRange.duration)];
	}

	[cmd appendFormat:@" -vn -c:a aac -b:a 128k -ar 44100 -ac 1 \"%@\"", outURL.path];

	[SCIFFmpeg executeCommand:cmd completion:^(BOOL success, NSString *output) {
		(void)output;

		dispatch_async(dispatch_get_main_queue(), ^{
			if (success && [NSFileManager.defaultManager fileExistsAtPath:outURL.path]) {
				sciSendAudioFile(outURL, threadVC);
			} else {
				[SCITempFiles releaseURL:outURL];
				sciShowUnsupportedAlert(url, SCILocalized(@"FFmpeg conversion failed"), threadVC);
			}
		});
	}];
}

static void sciAVConvertAndSend(NSURL *url, UIViewController *threadVC, CMTimeRange trimRange, void (^failure)(NSError *error)) {
	dispatch_async(dispatch_get_global_queue(QOS_CLASS_USER_INITIATED, 0), ^{
		AVAsset *asset = [AVAsset assetWithURL:url];

		if (!sciAssetHasAudio(asset)) {
			dispatch_async(dispatch_get_main_queue(), ^{
				if (failure) failure(nil);
			});
			return;
		}

		NSURL *outURL = [SCITempFiles claimWithExt:@"m4a" ttl:300 tag:@"exp"];

		AVAssetExportSession *exporter = [AVAssetExportSession exportSessionWithAsset:asset presetName:AVAssetExportPresetAppleM4A];
		if (!exporter) {
			// nil exporter never fires completion — bail via failure so keep-alive clears.
			[SCITempFiles releaseURL:outURL];
			dispatch_async(dispatch_get_main_queue(), ^{ if (failure) failure(nil); });
			return;
		}

		exporter.outputURL = outURL;
		exporter.outputFileType = AVFileTypeAppleM4A;

		if (sciHasValidTrim(trimRange)) {
			exporter.timeRange = trimRange;
		}

		[exporter exportAsynchronouslyWithCompletionHandler:^{
			dispatch_async(dispatch_get_main_queue(), ^{
				if (exporter.status == AVAssetExportSessionStatusCompleted) {
					sciSendAudioFile(outURL, threadVC);
				} else {
					[SCITempFiles releaseURL:outURL];
					if (failure) failure(exporter.error);
				}
			});
		}];
	});
}

static void sciExportAndSend(NSURL *url, UIViewController *threadVC, BOOL isVideo, CMTimeRange trimRange) {
	if (!url || !threadVC) return;

	BOOL hasTrim = sciHasValidTrim(trimRange);
	NSString *ext = sciLowerExt(url);

	if (!isVideo && !hasTrim && [sciPassthroughAudioExts() containsObject:ext]) {
		sciSendAudioFile(url, threadVC);
		return;
	}

	// Conversion can run a while — both terminals (send / unsupported alert) clear it.
	[SCIBackgroundActivity setSource:@"audio_send" active:YES];

	SCINotifyInfo(SCI_NOTIF_AUDIO_EXTRACT, isVideo ? SCILocalized(@"Extracting audio…") : SCILocalized(@"Converting…"), nil);

	sciAVConvertAndSend(url, threadVC, trimRange, ^(NSError *error) {
		if ([SCIFFmpeg isAvailable]) {
			sciFFmpegConvertAndSend(url, threadVC, trimRange);
			return;
		}

		if (!isVideo && [sciPassthroughAudioExts() containsObject:ext]) {
			sciSendAudioFile(url, threadVC);
			return;
		}

		sciShowUnsupportedAlert(url, error.localizedDescription ?: SCILocalized(@"no audio track could be read"), threadVC);
	});
}

#pragma mark - Trim preparation

static void sciShowUploadAudioOptions(UIViewController *threadVC);

static void sciShowTrimVC(NSURL *url, BOOL isVideo, UIViewController *threadVC) {
	if (!url || !threadVC) return;

	SCITrimViewController *trimVC = [[SCITrimViewController alloc] init];
	trimVC.mediaURL = url;
	trimVC.isVideo = isVideo;
	trimVC.sendButtonTitle = SCILocalized(@"Send Audio");
	trimVC.modalPresentationStyle = UIModalPresentationFullScreen;

	__weak UIViewController *weakThread = threadVC;
	trimVC.onSend = ^(CMTimeRange trimRange) {
		UIViewController *vc = weakThread;
		if (vc) sciExportAndSend(url, vc, isVideo, trimRange);
	};
	trimVC.onBack = ^{
		UIViewController *vc = weakThread;
		if (vc) sciShowUploadAudioOptions(vc);
	};

	[threadVC presentViewController:trimVC animated:YES completion:nil];
}

static void sciFFmpegPreConvertForTrim(NSURL *url, BOOL sourceHasAudio, UIViewController *threadVC) {
	NSURL *outURL = [SCITempFiles claimWithExt:@"m4a" ttl:600 tag:@"pre"];

	NSString *cmd = [NSString stringWithFormat:@"-y -i \"%@\" -vn -c:a aac -b:a 128k -ar 44100 \"%@\"", url.path, outURL.path];

	[SCIFFmpeg executeCommand:cmd completion:^(BOOL success, NSString *output) {
		BOOL noStream = [output containsString:@"does not contain any stream"];
		dispatch_async(dispatch_get_main_queue(), ^{
			if (success && [NSFileManager.defaultManager fileExistsAtPath:outURL.path]) {
				sciShowTrimVC(outURL, NO, threadVC);
			} else {
				[SCITempFiles releaseURL:outURL];
				NSString *msg = (noStream || !sourceHasAudio)
					? SCILocalized(@"No audio track found")
					: SCILocalized(@"FFmpeg conversion failed");
				sciShowUnsupportedAlert(url, msg, threadVC);
			}
		});
	}];
}

static void sciPrepareAndShowTrim(NSURL *url, UIViewController *threadVC) {
	if (!url || !threadVC) return;

	SCINotifyInfo(SCI_NOTIF_AUDIO_EXTRACT, SCILocalized(@"Converting…"), nil);

	dispatch_async(dispatch_get_global_queue(QOS_CLASS_USER_INITIATED, 0), ^{
		AVAsset *asset = [AVAsset assetWithURL:url];
		BOOL canRead = sciAssetHasAudio(asset) && sciAudioDurationFromAsset(asset) > 0.0;

		if (!canRead) {
			BOOL hasAudio = sciAssetHasAudio(asset);
			dispatch_async(dispatch_get_main_queue(), ^{
				if ([SCIFFmpeg isAvailable]) {
					sciFFmpegPreConvertForTrim(url, hasAudio, threadVC);
				} else {
					sciShowUnsupportedAlert(url, SCILocalized(@"Format not supported without FFmpegKit"), threadVC);
				}
			});
			return;
		}

		NSURL *outURL = [SCITempFiles claimWithExt:@"m4a" ttl:600 tag:@"pre"];

		AVAssetExportSession *exporter = [AVAssetExportSession exportSessionWithAsset:asset presetName:AVAssetExportPresetAppleM4A];
		if (!exporter) {
			// nil exporter never fires completion — fall back instead of hanging on "Converting…".
			[SCITempFiles releaseURL:outURL];

			dispatch_async(dispatch_get_main_queue(), ^{
				if ([SCIFFmpeg isAvailable]) {
					sciFFmpegPreConvertForTrim(url, YES, threadVC);
				} else {
					sciShowUnsupportedAlert(url, SCILocalized(@"Format not supported without FFmpegKit"), threadVC);
				}
			});
			return;
		}

		exporter.outputURL = outURL;
		exporter.outputFileType = AVFileTypeAppleM4A;

		[exporter exportAsynchronouslyWithCompletionHandler:^{
			dispatch_async(dispatch_get_main_queue(), ^{
				if (exporter.status == AVAssetExportSessionStatusCompleted) {
					sciShowTrimVC(outURL, NO, threadVC);
				} else {
					[SCITempFiles releaseURL:outURL];

					if ([SCIFFmpeg isAvailable]) {
						sciFFmpegPreConvertForTrim(url, YES, threadVC);
					} else {
						sciShowUnsupportedAlert(url, exporter.error.localizedDescription ?: SCILocalized(@"no audio track could be read"), threadVC);
					}
				}
			});
		}];
	});
}

#pragma mark - Picker UI

static void sciShowUploadAudioOptions(UIViewController *threadVC) {
	if (!threadVC) return;

	sciAudioThreadVC = threadVC;

	UIAlertController *alert = [UIAlertController alertControllerWithTitle:SCILocalized(@"Upload Audio")
																  message:nil
														   preferredStyle:UIAlertControllerStyleActionSheet];

	__weak UIViewController *weakVC = threadVC;

	[alert addAction:[UIAlertAction actionWithTitle:SCILocalized(@"Audio/Video from Files")
											  style:UIAlertActionStyleDefault
											handler:^(UIAlertAction *a) {
		(void)a;

		UIViewController *vc = weakVC;
		if (!vc) return;

#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wdeprecated-declarations"
		NSArray *types = [SCIFFmpeg isAvailable]
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

	[alert addAction:[UIAlertAction actionWithTitle:SCILocalized(@"Video from Library")
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

	[alert addAction:[UIAlertAction actionWithTitle:SCILocalized(@"From RyukGram Gallery")
											  style:UIAlertActionStyleDefault
											handler:^(UIAlertAction *a) {
		(void)a;

		UIViewController *vc = weakVC;
		if (!vc) return;

		// AVAssetExportSession + AppleM4A pulls the audio track out of video picks.
		[SCIGalleryViewController presentPickerWithMediaTypes:@[@(SCIGalleryMediaTypeAudio), @(SCIGalleryMediaTypeVideo)]
														title:SCILocalized(@"Pick audio or video")
													   fromVC:vc
												   completion:^(NSURL *pickedURL, SCIGalleryFile *pickedFile) {
			(void)pickedFile;

			if (!pickedURL) return;

			UIViewController *threadVC = sciAudioThreadVC ?: vc;
			if (threadVC) sciPrepareAndShowTrim(pickedURL, threadVC);
		}];
	}]];

	[alert addAction:[UIAlertAction actionWithTitle:SCILocalized(@"Cancel")
											  style:UIAlertActionStyleCancel
											handler:nil]];

	[threadVC presentViewController:alert animated:YES completion:nil];
}

#pragma mark - Hooks

%group SCISendAudioAsVoice

%hook IGDirectThreadViewController

- (void)viewDidAppear:(BOOL)animated {
	%orig;
	sciAudioThreadVC = (UIViewController *)self;
}

- (void)viewDidDisappear:(BOOL)animated {
	%orig;

	if (sciAudioThreadVC == (UIViewController *)self) {
		sciAudioThreadVC = nil;
	}
}

- (void)composerOverflowButtonMenuWillPrepareExpandWithPlusButton:(id)plusButton {
	%orig;

	sciAudioThreadVC = (UIViewController *)self;
	sciDMMenuPending = YES;
}

%new - (void)documentPicker:(UIDocumentPickerViewController *)controller didPickDocumentsAtURLs:(NSArray<NSURL *> *)urls {
	(void)controller;

	NSURL *url = urls.firstObject;
	if (!url) return;

	sciPrepareAndShowTrim(url, (UIViewController *)self);
}

%new - (void)documentPicker:(UIDocumentPickerViewController *)controller didPickDocumentAtURL:(NSURL *)url {
	(void)controller;

	if (!url) return;

	sciPrepareAndShowTrim(url, (UIViewController *)self);
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
		[SCIUtils showErrorHUDWithDescription:SCILocalized(@"No video selected")];
		return;
	}

	[provider loadFileRepresentationForTypeIdentifier:@"public.movie" completionHandler:^(NSURL *url, NSError *error) {
		(void)error;

		if (!url) {
			dispatch_async(dispatch_get_main_queue(), ^{
				[SCIUtils showErrorHUDWithDescription:SCILocalized(@"Could not extract video URL")];
			});
			return;
		}

		NSString *ext = sciLowerExt(url);
		NSURL *copyURL = [SCITempFiles claimWithExt:ext.length ? ext : @"mov" ttl:120 tag:@"pickvid"];

		BOOL copied = [NSFileManager.defaultManager copyItemAtURL:url toURL:copyURL error:nil];

		if (!copied) {
			[SCITempFiles releaseURL:copyURL];

			dispatch_async(dispatch_get_main_queue(), ^{
				[SCIUtils showErrorHUDWithDescription:SCILocalized(@"Could not copy selected video")];
			});
			return;
		}

		dispatch_async(dispatch_get_main_queue(), ^{
			sciShowTrimVC(copyURL, YES, (UIViewController *)self);
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

	UIButton *button = sciCall(self, @selector(cameraButton));
	UIViewController *threadVC = sciThreadVCForButton(button);

	if (!threadVC) {
		%orig;
		return;
	}

	sciAudioThreadVC = threadVC;
	sciShowUploadAudioOptions(threadVC);
}

%end

%hook IGDSMenu

- (id)initWithMenuItems:(NSArray *)items edr:(BOOL)edr headerLabelText:(id)header {
	if (!sciDMMenuPending) return %orig;

	sciDMMenuPending = NO;

	NSString *uploadTitle = SCILocalized(@"Upload Audio");

	for (id item in items) {
		id title = sciCall(item, @selector(title));
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
		UIViewController *threadVC = sciAudioThreadVC;
		if (threadVC) sciShowUploadAudioOptions(threadVC);
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
	if ([SCIUtils getBoolPref:@"send_audio_as_file"]) {
		%init(SCISendAudioAsVoice);
	}
}