#import "RYGMediaViewer.h"
#import "../Utils.h"
#import "../PhotoAlbum.h"
#import "../RYGImageCache.h"
#import "../Gallery/RYGGalleryFile.h"
#import "../Gallery/RYGGallerySaveMetadata.h"
#import "../RYGFileNaming.h"
#import "../Downloader/Download.h"
#import "../UI/Notification/RYGNotificationActions.h"
#import "../UI/RYGIcon.h"
#import <AVFoundation/AVFoundation.h>
#import <AVKit/AVKit.h>
#import <ImageIO/ImageIO.h>

#pragma mark - Helpers

static UIImageSymbolConfiguration *RYGSymbolConfig(CGFloat pointSize, UIImageSymbolWeight weight) {
	return [UIImageSymbolConfiguration configurationWithPointSize:pointSize weight:weight];
}

static void RYGSetPlaybackSession(AVAudioSessionMode mode) {
	[[AVAudioSession sharedInstance] setCategory:AVAudioSessionCategoryPlayback mode:mode options:0 error:nil];
	[[AVAudioSession sharedInstance] setActive:YES error:nil];
}

static void RYGDeactivateAudioSession(void) {
	[[AVAudioSession sharedInstance] setActive:NO withOptions:AVAudioSessionSetActiveOptionNotifyOthersOnDeactivation error:nil];
}

static NSString *RYGSniffImageExt(NSData *data, BOOL *needsTranscode) {
	if (needsTranscode) *needsTranscode = NO;
	if (data.length < 12) return @"jpg";

	const uint8_t *b = data.bytes;
	if (b[0] == 0xFF && b[1] == 0xD8 && b[2] == 0xFF) return @"jpg";
	if (b[0] == 0x89 && b[1] == 0x50 && b[2] == 0x4E && b[3] == 0x47) return @"png";
	if (b[0] == 0x47 && b[1] == 0x49 && b[2] == 0x46) return @"gif";

	if (b[4] == 'f' && b[5] == 't' && b[6] == 'y' && b[7] == 'p') {
		if ((b[8] == 'h' && (b[9] == 'e' || b[9] == 'v')) || (b[8] == 'm' && (b[9] == 'i' || b[9] == 's'))) return @"heic";
	}

	if (b[0] == 'R' && b[1] == 'I' && b[2] == 'F' && b[3] == 'F' &&
		b[8] == 'W' && b[9] == 'E' && b[10] == 'B' && b[11] == 'P') {
		if (needsTranscode) *needsTranscode = YES;
		return @"png";
	}

	return @"jpg";
}

static NSString *RYGTimeString(double seconds) {
	if (!isfinite(seconds) || seconds < 0) seconds = 0;
	NSInteger s = (NSInteger)round(seconds);
	return [NSString stringWithFormat:@"%ld:%02ld", (long)(s / 60), (long)(s % 60)];
}

@protocol RYGMediaPlaybackPage <NSObject>
- (void)playPlayback;
- (void)pausePlayback;
- (void)stopPlayback;
@optional
- (CMTime)currentPlaybackTime;
- (void)seekToPlaybackTime:(CMTime)time;
@end

#pragma mark - Data model

@implementation RYGMediaViewerItem

+ (instancetype)itemWithVideoURL:(NSURL *)videoURL photoURL:(NSURL *)photoURL caption:(NSString *)caption {
	RYGMediaViewerItem *item = RYGMediaViewerItem.new;
	item.videoURL = videoURL;
	item.photoURL = photoURL;
	item.caption = caption;
	return item;
}

+ (instancetype)itemWithAudioURL:(NSURL *)audioURL caption:(NSString *)caption {
	RYGMediaViewerItem *item = RYGMediaViewerItem.new;
	item.audioURL = audioURL;
	item.caption = caption;
	return item;
}

+ (instancetype)itemWithAnimatedImageURL:(NSURL *)animatedURL caption:(NSString *)caption {
	RYGMediaViewerItem *item = RYGMediaViewerItem.new;
	item.animatedImageURL = animatedURL;
	item.caption = caption;
	return item;
}

@end

#pragma mark - Photo page

@interface _RYGPhotoPageVC : UIViewController <UIScrollViewDelegate>
@property (nonatomic, strong) NSURL *photoURL;
@property (nonatomic, strong) UIScrollView *scrollView;
@property (nonatomic, strong) UIImageView *imageView;
@property (nonatomic, strong) UIActivityIndicatorView *spinner;
@end

@implementation _RYGPhotoPageVC

- (void)viewDidLoad {
	[super viewDidLoad];

	self.view.backgroundColor = UIColor.blackColor;

	self.scrollView = [[UIScrollView alloc] initWithFrame:self.view.bounds];
	self.scrollView.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
	self.scrollView.delegate = self;
	self.scrollView.minimumZoomScale = 1.0;
	self.scrollView.maximumZoomScale = 5.0;
	self.scrollView.showsVerticalScrollIndicator = NO;
	self.scrollView.showsHorizontalScrollIndicator = NO;
	[self.view addSubview:self.scrollView];

	self.imageView = [[UIImageView alloc] initWithFrame:self.scrollView.bounds];
	self.imageView.contentMode = UIViewContentModeScaleAspectFit;
	self.imageView.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
	[self.scrollView addSubview:self.imageView];

	self.spinner = [[UIActivityIndicatorView alloc] initWithActivityIndicatorStyle:UIActivityIndicatorViewStyleMedium];
	self.spinner.color = UIColor.whiteColor;
	self.spinner.center = self.view.center;
	self.spinner.autoresizingMask = UIViewAutoresizingFlexibleTopMargin | UIViewAutoresizingFlexibleBottomMargin | UIViewAutoresizingFlexibleLeftMargin | UIViewAutoresizingFlexibleRightMargin;
	[self.view addSubview:self.spinner];
	[self.spinner startAnimating];

	__weak typeof(self) weakSelf = self;
	[RYGImageCache loadImageFromURL:self.photoURL completion:^(UIImage *image) {
		dispatch_async(dispatch_get_main_queue(), ^{
			__strong typeof(weakSelf) self = weakSelf;
			if (!self) return;
			[self.spinner stopAnimating];
			if (image) self.imageView.image = image;
		});
	}];

	UITapGestureRecognizer *doubleTap = [[UITapGestureRecognizer alloc] initWithTarget:self action:@selector(handleDoubleTap:)];
	doubleTap.numberOfTapsRequired = 2;
	[self.scrollView addGestureRecognizer:doubleTap];
}

- (UIView *)viewForZoomingInScrollView:(UIScrollView *)scrollView {
	return self.imageView;
}

- (void)handleDoubleTap:(UITapGestureRecognizer *)gesture {
	if (self.scrollView.zoomScale > 1.0) {
		[self.scrollView setZoomScale:1.0 animated:YES];
		return;
	}

	CGPoint point = [gesture locationInView:self.imageView];
	[self.scrollView zoomToRect:CGRectMake(point.x - 50.0, point.y - 50.0, 100.0, 100.0) animated:YES];
}

- (UIImage *)currentImage {
	return self.imageView.image;
}

@end

#pragma mark - Video page

@interface _RYGVideoPageVC : UIViewController <RYGMediaPlaybackPage>
@property (nonatomic, strong) NSURL *videoURL;
@property (nonatomic, strong) AVPlayerViewController *playerVC;
@property (nonatomic, strong) AVQueuePlayer *player;
@property (nonatomic, strong) AVPlayerLooper *looper;
@property (nonatomic, assign) BOOL didPrepare;
@end

@implementation _RYGVideoPageVC

- (void)viewDidLoad {
	[super viewDidLoad];
	self.view.backgroundColor = UIColor.blackColor;
	[self preparePlayerIfNeeded];
}

- (void)preparePlayerIfNeeded {
	if (self.didPrepare || !self.videoURL) return;

	self.didPrepare = YES;
	RYGSetPlaybackSession(AVAudioSessionModeMoviePlayback);

	AVPlayerItem *item = [AVPlayerItem playerItemWithURL:self.videoURL];
	self.player = [AVQueuePlayer queuePlayerWithItems:@[item]];
	self.player.muted = [RYGUtils getBoolPref:@"media_zoom_start_muted"];
	self.looper = [AVPlayerLooper playerLooperWithPlayer:self.player templateItem:item];

	self.playerVC = AVPlayerViewController.new;
	self.playerVC.player = self.player;
	self.playerVC.showsPlaybackControls = YES;
	self.playerVC.videoGravity = AVLayerVideoGravityResizeAspect;
	self.playerVC.allowsPictureInPicturePlayback = YES;

	[self addChildViewController:self.playerVC];
	self.playerVC.view.frame = self.view.bounds;
	self.playerVC.view.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
	[self.view addSubview:self.playerVC.view];
	[self.playerVC didMoveToParentViewController:self];
}

- (void)playPlayback {
	[self preparePlayerIfNeeded];
	[self.player play];
}

- (void)pausePlayback {
	[self.player pause];
}

- (void)stopPlayback {
	[self.player pause];
	self.looper = nil;
	self.playerVC.player = nil;
	self.player = nil;
	self.didPrepare = NO;
	RYGDeactivateAudioSession();
}

- (CMTime)currentPlaybackTime {
	return self.player ? self.player.currentTime : kCMTimeZero;
}

- (void)seekToPlaybackTime:(CMTime)time {
	if (!self.player || !CMTIME_IS_VALID(time) || CMTIME_COMPARE_INLINE(time, <=, kCMTimeZero)) return;
	[self.player seekToTime:time toleranceBefore:kCMTimeZero toleranceAfter:kCMTimeZero];
}

- (void)viewDidDisappear:(BOOL)animated {
	[super viewDidDisappear:animated];
	[self pausePlayback];
}

- (void)dealloc {
	[self stopPlayback];
}

@end

#pragma mark - Audio page

@interface _RYGAudioPageVC : UIViewController <RYGMediaPlaybackPage>
@property (nonatomic, strong) NSURL *audioURL;
@property (nonatomic, strong) AVPlayer *player;
@property (nonatomic, strong) id timeObserver;
@property (nonatomic, strong) UIImageView *glyphView;
@property (nonatomic, strong) UILabel *titleLabel;
@property (nonatomic, strong) UIButton *playButton;
@property (nonatomic, strong) UISlider *slider;
@property (nonatomic, strong) UILabel *elapsedLabel;
@property (nonatomic, strong) UILabel *totalLabel;
@property (nonatomic, assign) BOOL scrubbing;
@property (nonatomic, assign) BOOL wasPlayingBeforeScrub;
@property (nonatomic, assign) double durationSeconds;
@end

@implementation _RYGAudioPageVC

- (void)viewDidLoad {
	[super viewDidLoad];

	self.view.backgroundColor = UIColor.blackColor;
	RYGSetPlaybackSession(AVAudioSessionModeDefault);

	self.player = [AVPlayer playerWithURL:self.audioURL];

	[self setupViews];
	[self setupConstraints];
	[self setupObserver];
}

- (UILabel *)labelWithFont:(UIFont *)font color:(UIColor *)color {
	UILabel *label = UILabel.new;
	label.translatesAutoresizingMaskIntoConstraints = NO;
	label.font = font;
	label.textColor = color;
	label.numberOfLines = 1;
	return label;
}

- (void)setupViews {
	UIColor *white = UIColor.whiteColor;

	self.glyphView = UIImageView.new;
	self.glyphView.translatesAutoresizingMaskIntoConstraints = NO;
	self.glyphView.contentMode = UIViewContentModeScaleAspectFit;
	self.glyphView.tintColor = [UIColor colorWithWhite:1.0 alpha:0.18];
	self.glyphView.image = [UIImage systemImageNamed:@"waveform" withConfiguration:RYGSymbolConfig(200.0, UIImageSymbolWeightBold)];
	[self.view addSubview:self.glyphView];

	self.titleLabel = [self labelWithFont:[UIFont systemFontOfSize:14.0 weight:UIFontWeightSemibold] color:[UIColor colorWithWhite:1.0 alpha:0.6]];
	self.titleLabel.textAlignment = NSTextAlignmentCenter;
	self.titleLabel.text = self.audioURL.lastPathComponent;
	[self.view addSubview:self.titleLabel];

	self.playButton = [UIButton buttonWithType:UIButtonTypeSystem];
	self.playButton.translatesAutoresizingMaskIntoConstraints = NO;
	self.playButton.tintColor = white;
	[self.playButton setPreferredSymbolConfiguration:RYGSymbolConfig(44.0, UIImageSymbolWeightSemibold) forImageInState:UIControlStateNormal];
	[self.playButton setImage:[UIImage systemImageNamed:@"play.circle.fill"] forState:UIControlStateNormal];
	[self.playButton addTarget:self action:@selector(togglePlay) forControlEvents:UIControlEventTouchUpInside];
	[self.view addSubview:self.playButton];

	self.elapsedLabel = [self labelWithFont:[UIFont monospacedDigitSystemFontOfSize:12.0 weight:UIFontWeightMedium] color:white];
	self.elapsedLabel.text = @"0:00";
	[self.view addSubview:self.elapsedLabel];

	self.totalLabel = [self labelWithFont:[UIFont monospacedDigitSystemFontOfSize:12.0 weight:UIFontWeightMedium] color:[UIColor colorWithWhite:1.0 alpha:0.7]];
	self.totalLabel.textAlignment = NSTextAlignmentRight;
	self.totalLabel.text = @"--:--";
	[self.view addSubview:self.totalLabel];

	self.slider = UISlider.new;
	self.slider.translatesAutoresizingMaskIntoConstraints = NO;
	self.slider.minimumValue = 0.0;
	self.slider.maximumValue = 1.0;
	self.slider.value = 0.0;
	self.slider.minimumTrackTintColor = white;
	self.slider.maximumTrackTintColor = [UIColor colorWithWhite:1.0 alpha:0.25];
	self.slider.thumbTintColor = white;
	[self.slider addTarget:self action:@selector(scrubBegan:) forControlEvents:UIControlEventTouchDown];
	[self.slider addTarget:self action:@selector(scrubChanged:) forControlEvents:UIControlEventValueChanged];
	[self.slider addTarget:self action:@selector(scrubEnded:) forControlEvents:UIControlEventTouchUpInside | UIControlEventTouchUpOutside | UIControlEventTouchCancel];
	[self.view addSubview:self.slider];
}

- (void)setupConstraints {
	[NSLayoutConstraint activateConstraints:@[
		[self.glyphView.centerXAnchor constraintEqualToAnchor:self.view.centerXAnchor],
		[self.glyphView.centerYAnchor constraintEqualToAnchor:self.view.centerYAnchor constant:-80.0],
		[self.glyphView.widthAnchor constraintEqualToConstant:220.0],
		[self.glyphView.heightAnchor constraintEqualToConstant:220.0],

		[self.titleLabel.leadingAnchor constraintEqualToAnchor:self.view.leadingAnchor constant:24.0],
		[self.titleLabel.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor constant:-24.0],
		[self.titleLabel.topAnchor constraintEqualToAnchor:self.glyphView.bottomAnchor constant:12.0],

		[self.playButton.centerXAnchor constraintEqualToAnchor:self.view.centerXAnchor],
		[self.playButton.bottomAnchor constraintEqualToAnchor:self.view.safeAreaLayoutGuide.bottomAnchor constant:-72.0],
		[self.playButton.widthAnchor constraintEqualToConstant:60.0],
		[self.playButton.heightAnchor constraintEqualToConstant:60.0],

		[self.elapsedLabel.leadingAnchor constraintEqualToAnchor:self.view.leadingAnchor constant:24.0],
		[self.elapsedLabel.bottomAnchor constraintEqualToAnchor:self.playButton.topAnchor constant:-16.0],
		[self.elapsedLabel.widthAnchor constraintGreaterThanOrEqualToConstant:36.0],

		[self.totalLabel.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor constant:-24.0],
		[self.totalLabel.centerYAnchor constraintEqualToAnchor:self.elapsedLabel.centerYAnchor],
		[self.totalLabel.widthAnchor constraintGreaterThanOrEqualToConstant:36.0],

		[self.slider.leadingAnchor constraintEqualToAnchor:self.elapsedLabel.trailingAnchor constant:8.0],
		[self.slider.trailingAnchor constraintEqualToAnchor:self.totalLabel.leadingAnchor constant:-8.0],
		[self.slider.centerYAnchor constraintEqualToAnchor:self.elapsedLabel.centerYAnchor],
	]];
}

- (void)setupObserver {
	__weak typeof(self) weakSelf = self;
	self.timeObserver = [self.player addPeriodicTimeObserverForInterval:CMTimeMakeWithSeconds(0.1, 600)
																  queue:dispatch_get_main_queue()
															 usingBlock:^(CMTime time) {
		[weakSelf tickWithTime:time];
	}];

	[NSNotificationCenter.defaultCenter addObserver:self
										   selector:@selector(playbackEnded:)
											   name:AVPlayerItemDidPlayToEndTimeNotification
											 object:self.player.currentItem];
}

- (void)tickWithTime:(CMTime)time {
	if (self.durationSeconds <= 0.0) {
		double duration = CMTimeGetSeconds(self.player.currentItem.duration);
		if (isfinite(duration) && duration > 0.0) {
			self.durationSeconds = duration;
			self.slider.maximumValue = (float)duration;
			self.totalLabel.text = RYGTimeString(duration);
		}
	}

	if (self.scrubbing) return;

	double current = CMTimeGetSeconds(time);
	if (!isfinite(current)) current = 0.0;

	self.slider.value = (float)current;
	self.elapsedLabel.text = RYGTimeString(current);
}

- (void)setPlayingUI:(BOOL)playing {
	[self.playButton setImage:[UIImage systemImageNamed:(playing ? @"pause.circle.fill" : @"play.circle.fill")] forState:UIControlStateNormal];
}

- (void)togglePlay {
	BOOL playing = self.player.timeControlStatus == AVPlayerTimeControlStatusPlaying;
	if (playing) {
		[self pausePlayback];
		return;
	}

	if (self.durationSeconds > 0.0 && CMTimeGetSeconds(self.player.currentTime) >= self.durationSeconds) {
		[self.player seekToTime:kCMTimeZero];
	}

	[self playPlayback];
}

- (void)scrubBegan:(UISlider *)slider {
	self.scrubbing = YES;
	self.wasPlayingBeforeScrub = self.player.timeControlStatus == AVPlayerTimeControlStatusPlaying;
	[self.player pause];
}

- (void)scrubChanged:(UISlider *)slider {
	self.elapsedLabel.text = RYGTimeString(slider.value);
	[self.player seekToTime:CMTimeMakeWithSeconds(slider.value, 600) toleranceBefore:kCMTimePositiveInfinity toleranceAfter:kCMTimePositiveInfinity];
}

- (void)scrubEnded:(UISlider *)slider {
	__weak typeof(self) weakSelf = self;
	[self.player seekToTime:CMTimeMakeWithSeconds(slider.value, 600)
			toleranceBefore:kCMTimePositiveInfinity
			 toleranceAfter:kCMTimePositiveInfinity
		  completionHandler:^(__unused BOOL finished) {
		__strong typeof(weakSelf) self = weakSelf;
		if (!self) return;
		self.scrubbing = NO;
		if (self.wasPlayingBeforeScrub) [self playPlayback];
	}];
}

- (void)playbackEnded:(NSNotification *)notification {
	[self setPlayingUI:NO];
}

- (void)playPlayback {
	[self.player play];
	[self setPlayingUI:YES];
}

- (void)pausePlayback {
	[self.player pause];
	[self setPlayingUI:NO];
}

- (void)stopPlayback {
	if (self.timeObserver && self.player) {
		[self.player removeTimeObserver:self.timeObserver];
		self.timeObserver = nil;
	}

	[NSNotificationCenter.defaultCenter removeObserver:self];
	[self.player pause];
	self.player = nil;
	RYGDeactivateAudioSession();
}

- (CMTime)currentPlaybackTime {
	return self.player ? self.player.currentTime : kCMTimeZero;
}

- (void)seekToPlaybackTime:(CMTime)time {
	if (!self.player || !CMTIME_IS_VALID(time) || CMTIME_COMPARE_INLINE(time, <=, kCMTimeZero)) return;
	[self.player seekToTime:time toleranceBefore:kCMTimeZero toleranceAfter:kCMTimeZero];
}

- (void)viewDidDisappear:(BOOL)animated {
	[super viewDidDisappear:animated];
	[self pausePlayback];
}

- (void)dealloc {
	[self stopPlayback];
}

@end

#pragma mark - Animated image page

@interface _RYGAnimatedPageVC : UIViewController <RYGMediaPlaybackPage>
@property (nonatomic, strong) NSURL *animatedURL;
@property (nonatomic, strong) UIImageView *imageView;
@end

@implementation _RYGAnimatedPageVC

+ (void)loadAnimatedURL:(NSURL *)url completion:(void (^)(NSArray<UIImage *> *frames, NSTimeInterval duration))completion {
	if (!url) { if (completion) completion(nil, 0.0); return; }

	dispatch_async(dispatch_get_global_queue(QOS_CLASS_USER_INITIATED, 0), ^{
		CGImageSourceRef source = CGImageSourceCreateWithURL((__bridge CFURLRef)url, NULL);
		if (!source) {
			dispatch_async(dispatch_get_main_queue(), ^{ if (completion) completion(nil, 0.0); });
			return;
		}

		size_t count = CGImageSourceGetCount(source);
		NSMutableArray<UIImage *> *frames = [NSMutableArray arrayWithCapacity:count];
		NSTimeInterval total = 0.0;

		for (size_t i = 0; i < count; i++) {
			CGImageRef cg = CGImageSourceCreateImageAtIndex(source, i, NULL);
			if (!cg) continue;

			UIImage *image = [UIImage imageWithCGImage:cg];
			CGImageRelease(cg);
			if (image) [frames addObject:image];

			NSTimeInterval delay = 0.1;
			CFDictionaryRef props = CGImageSourceCopyPropertiesAtIndex(source, i, NULL);
			if (props) {
				CFDictionaryRef gif = CFDictionaryGetValue(props, kCGImagePropertyGIFDictionary);
				if (gif) {
					NSNumber *value = CFDictionaryGetValue(gif, kCGImagePropertyGIFUnclampedDelayTime);
					if (![value respondsToSelector:@selector(doubleValue)] || value.doubleValue <= 0.0) value = CFDictionaryGetValue(gif, kCGImagePropertyGIFDelayTime);
					if ([value respondsToSelector:@selector(doubleValue)] && value.doubleValue > 0.0) delay = value.doubleValue;
				}
				CFRelease(props);
			}

			total += delay;
		}

		CFRelease(source);
		if (total < 0.04) total = MAX(0.04, frames.count * 0.05);

		dispatch_async(dispatch_get_main_queue(), ^{
			if (completion) completion(frames, total);
		});
	});
}

- (void)viewDidLoad {
	[super viewDidLoad];

	self.view.backgroundColor = UIColor.blackColor;

	self.imageView = UIImageView.new;
	self.imageView.translatesAutoresizingMaskIntoConstraints = NO;
	self.imageView.contentMode = UIViewContentModeScaleAspectFit;
	[self.view addSubview:self.imageView];

	[NSLayoutConstraint activateConstraints:@[
		[self.imageView.topAnchor constraintEqualToAnchor:self.view.topAnchor],
		[self.imageView.bottomAnchor constraintEqualToAnchor:self.view.bottomAnchor],
		[self.imageView.leadingAnchor constraintEqualToAnchor:self.view.leadingAnchor],
		[self.imageView.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor],
	]];

	__weak typeof(self) weakSelf = self;
	[_RYGAnimatedPageVC loadAnimatedURL:self.animatedURL completion:^(NSArray<UIImage *> *frames, NSTimeInterval duration) {
		__strong typeof(weakSelf) self = weakSelf;
		if (!self || !frames.count) return;

		self.imageView.animationImages = frames;
		self.imageView.animationDuration = duration;
		self.imageView.animationRepeatCount = 0;
		self.imageView.image = frames.firstObject;
		[self.imageView startAnimating];
	}];
}

- (void)playPlayback {
	[self.imageView startAnimating];
}

- (void)pausePlayback {
	[self.imageView stopAnimating];
}

- (void)stopPlayback {
	[self.imageView stopAnimating];
	self.imageView.animationImages = nil;
}

- (void)viewDidDisappear:(BOOL)animated {
	[super viewDidDisappear:animated];
	[self pausePlayback];
}

@end

#pragma mark - Container

@interface _RYGMediaViewerContainerVC : UIViewController <UIPageViewControllerDataSource, UIPageViewControllerDelegate, UIGestureRecognizerDelegate>
@property (nonatomic, strong) NSArray<RYGMediaViewerItem *> *items;
@property (nonatomic, assign) NSUInteger currentIndex;
@property (nonatomic, strong) UIPageViewController *pageVC;
@property (nonatomic, strong) UIView *topBar;
@property (nonatomic, strong) UIButton *closeBtn;
@property (nonatomic, strong) UILabel *counterLabel;
@property (nonatomic, strong) UIButton *shareBtn;
@property (nonatomic, strong) UIView *bottomBar;
@property (nonatomic, strong) UILabel *captionLabel;
@property (nonatomic, strong) UIView *topShade;
@property (nonatomic, strong) CAGradientLayer *topShadeLayer;
@property (nonatomic, strong) NSMutableDictionary<NSNumber *, UIViewController *> *pageCache;
@property (nonatomic, strong) NSMutableDictionary<NSNumber *, NSValue *> *playbackTimes;
@property (nonatomic, assign) BOOL chromeVisible;
@property (nonatomic, assign) BOOL captionExpanded;
@property (nonatomic, assign) BOOL shareSheetOnly;
@end

@implementation _RYGMediaViewerContainerVC

- (void)viewDidLoad {
	[super viewDidLoad];

	self.view.backgroundColor = UIColor.blackColor;
	self.chromeVisible = YES;
	self.pageCache = NSMutableDictionary.dictionary;
	self.playbackTimes = NSMutableDictionary.dictionary;

	[self setupPageController];
	[self setupTopChrome];
	[self setupBottomChrome];
	[self setupGestures];
	[self updateChrome];
}

- (RYGMediaViewerItem *)currentItem {
	return self.currentIndex < self.items.count ? self.items[self.currentIndex] : nil;
}

- (UIViewController *)currentPage {
	return self.pageVC.viewControllers.firstObject;
}

- (NSURL *)sourceURLForItem:(RYGMediaViewerItem *)item {
	return item.photoURL ?: item.videoURL ?: item.audioURL ?: item.animatedImageURL;
}

#pragma mark - Setup

- (void)setupPageController {
	self.pageVC = [[UIPageViewController alloc] initWithTransitionStyle:UIPageViewControllerTransitionStyleScroll
												  navigationOrientation:UIPageViewControllerNavigationOrientationHorizontal
																options:nil];
	self.pageVC.dataSource = self.items.count > 1 ? self : nil;
	self.pageVC.delegate = self;

	UIViewController *first = [self viewControllerForIndex:self.currentIndex];
	if (first) {
		[self.pageVC setViewControllers:@[first] direction:UIPageViewControllerNavigationDirectionForward animated:NO completion:nil];
	}

	[self addChildViewController:self.pageVC];
	self.pageVC.view.frame = self.view.bounds;
	self.pageVC.view.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
	[self.view addSubview:self.pageVC.view];
	[self.pageVC didMoveToParentViewController:self];
}

- (UIButton *)chromeButtonWithSymbol:(NSString *)symbol action:(SEL)action {
	UIButton *button = [UIButton buttonWithType:UIButtonTypeSystem];
	button.translatesAutoresizingMaskIntoConstraints = NO;
	button.tintColor = UIColor.whiteColor;
	button.backgroundColor = [UIColor colorWithWhite:0.0 alpha:0.28];
	button.layer.cornerRadius = 18.0;
	button.layer.cornerCurve = kCACornerCurveContinuous;
	button.clipsToBounds = YES;
	[button setImage:[UIImage systemImageNamed:symbol withConfiguration:RYGSymbolConfig(16.0, UIImageSymbolWeightSemibold)] forState:UIControlStateNormal];
	if (action) [button addTarget:self action:action forControlEvents:UIControlEventTouchUpInside];
	return button;
}

- (void)setupTopChrome {
	self.topShade = UIView.new;
	self.topShade.translatesAutoresizingMaskIntoConstraints = NO;
	self.topShade.userInteractionEnabled = NO;
	[self.view addSubview:self.topShade];

	self.topShadeLayer = CAGradientLayer.layer;
	self.topShadeLayer.colors = @[(id)[[UIColor colorWithWhite:0.0 alpha:0.55] CGColor], (id)UIColor.clearColor.CGColor];
	self.topShadeLayer.startPoint = CGPointMake(0.5, 0.0);
	self.topShadeLayer.endPoint = CGPointMake(0.5, 1.0);
	[self.topShade.layer addSublayer:self.topShadeLayer];

	self.topBar = UIView.new;
	self.topBar.translatesAutoresizingMaskIntoConstraints = NO;
	self.topBar.userInteractionEnabled = YES;
	[self.view addSubview:self.topBar];

	self.closeBtn = [self chromeButtonWithSymbol:@"xmark" action:@selector(closeTapped)];
	self.shareBtn = [self chromeButtonWithSymbol:@"square.and.arrow.up" action:nil];

	self.counterLabel = UILabel.new;
	self.counterLabel.translatesAutoresizingMaskIntoConstraints = NO;
	self.counterLabel.textColor = UIColor.whiteColor;
	self.counterLabel.font = [UIFont systemFontOfSize:15.0 weight:UIFontWeightSemibold];
	self.counterLabel.textAlignment = NSTextAlignmentCenter;

	[self configureShareButton];

	[self.topBar addSubview:self.closeBtn];
	[self.topBar addSubview:self.shareBtn];
	[self.topBar addSubview:self.counterLabel];

	[NSLayoutConstraint activateConstraints:@[
		[self.topShade.topAnchor constraintEqualToAnchor:self.view.topAnchor],
		[self.topShade.leadingAnchor constraintEqualToAnchor:self.view.leadingAnchor],
		[self.topShade.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor],
		[self.topShade.heightAnchor constraintEqualToConstant:120.0],

		[self.topBar.topAnchor constraintEqualToAnchor:self.view.safeAreaLayoutGuide.topAnchor],
		[self.topBar.leadingAnchor constraintEqualToAnchor:self.view.leadingAnchor],
		[self.topBar.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor],
		[self.topBar.heightAnchor constraintEqualToConstant:48.0],

		[self.closeBtn.leadingAnchor constraintEqualToAnchor:self.topBar.leadingAnchor constant:16.0],
		[self.closeBtn.centerYAnchor constraintEqualToAnchor:self.topBar.centerYAnchor],
		[self.closeBtn.widthAnchor constraintEqualToConstant:36.0],
		[self.closeBtn.heightAnchor constraintEqualToConstant:36.0],

		[self.shareBtn.trailingAnchor constraintEqualToAnchor:self.topBar.trailingAnchor constant:-16.0],
		[self.shareBtn.centerYAnchor constraintEqualToAnchor:self.topBar.centerYAnchor],
		[self.shareBtn.widthAnchor constraintEqualToConstant:36.0],
		[self.shareBtn.heightAnchor constraintEqualToConstant:36.0],

		[self.counterLabel.centerXAnchor constraintEqualToAnchor:self.topBar.centerXAnchor],
		[self.counterLabel.centerYAnchor constraintEqualToAnchor:self.topBar.centerYAnchor],
	]];
}

- (void)configureShareButton {
	if (!self.shareSheetOnly) {
		self.shareBtn.showsMenuAsPrimaryAction = YES;

		__weak typeof(self) weakSelf = self;
		UIDeferredMenuElement *deferred = [UIDeferredMenuElement elementWithUncachedProvider:^(void (^completion)(NSArray<UIMenuElement *> *items)) {
			__strong typeof(weakSelf) self = weakSelf;
			completion(self ? [self shareMenuChildren] : @[]);
		}];

		self.shareBtn.menu = [UIMenu menuWithChildren:@[deferred]];
		return;
	}

	[self.shareBtn addTarget:self action:@selector(shareTapped) forControlEvents:UIControlEventTouchUpInside];
}

- (void)setupBottomChrome {
	self.bottomBar = UIView.new;
	self.bottomBar.translatesAutoresizingMaskIntoConstraints = NO;
	self.bottomBar.backgroundColor = [UIColor colorWithWhite:0.0 alpha:0.6];
	[self.view addSubview:self.bottomBar];

	self.captionLabel = UILabel.new;
	self.captionLabel.translatesAutoresizingMaskIntoConstraints = NO;
	self.captionLabel.textColor = UIColor.whiteColor;
	self.captionLabel.font = [UIFont systemFontOfSize:14.0];
	self.captionLabel.numberOfLines = 3;
	self.captionLabel.userInteractionEnabled = YES;
	[self.bottomBar addSubview:self.captionLabel];

	UITapGestureRecognizer *tap = [[UITapGestureRecognizer alloc] initWithTarget:self action:@selector(toggleCaption)];
	[self.captionLabel addGestureRecognizer:tap];

	[NSLayoutConstraint activateConstraints:@[
		[self.bottomBar.leadingAnchor constraintEqualToAnchor:self.view.leadingAnchor],
		[self.bottomBar.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor],
		[self.bottomBar.bottomAnchor constraintEqualToAnchor:self.view.bottomAnchor],

		[self.captionLabel.topAnchor constraintEqualToAnchor:self.bottomBar.topAnchor constant:12.0],
		[self.captionLabel.leadingAnchor constraintEqualToAnchor:self.bottomBar.leadingAnchor constant:16.0],
		[self.captionLabel.trailingAnchor constraintEqualToAnchor:self.bottomBar.trailingAnchor constant:-16.0],
		[self.captionLabel.bottomAnchor constraintEqualToAnchor:self.view.safeAreaLayoutGuide.bottomAnchor constant:-8.0],
	]];
}

- (void)setupGestures {
	UIPanGestureRecognizer *pan = [[UIPanGestureRecognizer alloc] initWithTarget:self action:@selector(handleDismissPan:)];
	pan.delegate = self;
	[self.view addGestureRecognizer:pan];

	UITapGestureRecognizer *tap = [[UITapGestureRecognizer alloc] initWithTarget:self action:@selector(toggleChrome)];
	tap.cancelsTouchesInView = NO;
	[self.pageVC.view addGestureRecognizer:tap];
}

#pragma mark - Layout / Chrome

- (void)viewDidLayoutSubviews {
	[super viewDidLayoutSubviews];
	self.topShadeLayer.frame = self.topShade.bounds;
}

- (void)updateChrome {
	RYGMediaViewerItem *item = self.currentItem;
	BOOL hasCaption = item.caption.length > 0;
	BOOL isVideo = item.videoURL != nil;

	self.counterLabel.hidden = self.items.count <= 1;
	if (self.items.count > 1) {
		self.counterLabel.text = [NSString stringWithFormat:@"%lu / %lu", (unsigned long)(self.currentIndex + 1), (unsigned long)self.items.count];
	}

	self.closeBtn.alpha = 1.0;
	self.shareBtn.alpha = 1.0;
	self.topShade.alpha = self.chromeVisible ? 1.0 : 0.0;
	self.topBar.alpha = self.chromeVisible ? 1.0 : 0.0;
	self.closeBtn.userInteractionEnabled = YES;
	self.shareBtn.userInteractionEnabled = YES;

	if (hasCaption && !isVideo) {
		self.captionLabel.text = item.caption;
		self.bottomBar.hidden = NO;
		self.bottomBar.alpha = self.chromeVisible ? 1.0 : 0.0;
	} else {
		self.bottomBar.hidden = YES;
	}
}

- (void)toggleChrome {
	self.chromeVisible = !self.chromeVisible;

	[UIView animateWithDuration:0.2 animations:^{
		CGFloat alpha = self.chromeVisible ? 1.0 : 0.0;
		self.topBar.alpha = alpha;
		self.topShade.alpha = alpha;
		if (!self.bottomBar.hidden) self.bottomBar.alpha = alpha;
	}];
}

- (void)toggleCaption {
	self.captionExpanded = !self.captionExpanded;

	[UIView animateWithDuration:0.25 animations:^{
		self.captionLabel.numberOfLines = self.captionExpanded ? 0 : 3;
		[self.view layoutIfNeeded];
	}];
}

#pragma mark - Dismiss / Playback

- (BOOL)gestureRecognizerShouldBegin:(UIGestureRecognizer *)gestureRecognizer {
	if (![gestureRecognizer isKindOfClass:UIPanGestureRecognizer.class]) return YES;

	CGPoint velocity = [(UIPanGestureRecognizer *)gestureRecognizer velocityInView:self.view];
	return fabs(velocity.y) > fabs(velocity.x) && velocity.y > 0.0;
}

- (void)handleDismissPan:(UIPanGestureRecognizer *)gesture {
	CGFloat y = [gesture translationInView:self.view].y;
	CGFloat height = MAX(self.view.bounds.size.height, 1.0);
	CGFloat progress = MIN(MAX(y / height, 0.0), 1.0);

	switch (gesture.state) {
		case UIGestureRecognizerStateChanged:
			self.view.transform = CGAffineTransformMakeTranslation(0.0, MAX(y, 0.0));
			self.view.alpha = 1.0 - progress * 0.5;
			break;

		case UIGestureRecognizerStateEnded:
		case UIGestureRecognizerStateCancelled: {
			CGFloat velocity = [gesture velocityInView:self.view].y;
			if (progress > 0.25 || velocity > 800.0) {
				[UIView animateWithDuration:0.2 animations:^{
					self.view.transform = CGAffineTransformMakeTranslation(0.0, height);
					self.view.alpha = 0.0;
				} completion:^(__unused BOOL finished) {
					[self stopAllCachedPages];
					[self dismissViewControllerAnimated:NO completion:nil];
				}];
			} else {
				[UIView animateWithDuration:0.25 delay:0.0 usingSpringWithDamping:0.8 initialSpringVelocity:0.0 options:0 animations:^{
					self.view.transform = CGAffineTransformIdentity;
					self.view.alpha = 1.0;
				} completion:nil];
			}
			break;
		}

		default:
			break;
	}
}

- (void)savePlaybackTimeForPage:(UIViewController *)page {
	if (![page conformsToProtocol:@protocol(RYGMediaPlaybackPage)]) return;
	if (![(id)page respondsToSelector:@selector(currentPlaybackTime)]) return;

	CMTime time = [(id<RYGMediaPlaybackPage>)page currentPlaybackTime];
	if (!CMTIME_IS_VALID(time)) return;

	self.playbackTimes[@(page.view.tag)] = [NSValue valueWithCMTime:time];
}

- (void)restorePlaybackTimeForPage:(UIViewController *)page {
	if (![page conformsToProtocol:@protocol(RYGMediaPlaybackPage)]) return;
	if (![(id)page respondsToSelector:@selector(seekToPlaybackTime:)]) return;

	NSValue *value = self.playbackTimes[@(page.view.tag)];
	if (!value) return;

	[(id<RYGMediaPlaybackPage>)page seekToPlaybackTime:value.CMTimeValue];
}

- (void)pausePage:(UIViewController *)page {
	if (![page conformsToProtocol:@protocol(RYGMediaPlaybackPage)]) return;
	[self savePlaybackTimeForPage:page];
	[(id<RYGMediaPlaybackPage>)page pausePlayback];
}

- (void)playPage:(UIViewController *)page {
	if (![page conformsToProtocol:@protocol(RYGMediaPlaybackPage)]) return;
	[self restorePlaybackTimeForPage:page];
	[(id<RYGMediaPlaybackPage>)page playPlayback];
}

- (void)stopPage:(UIViewController *)page {
	if (![page conformsToProtocol:@protocol(RYGMediaPlaybackPage)]) return;
	[(id<RYGMediaPlaybackPage>)page stopPlayback];
}

- (void)stopAllCachedPages {
	for (UIViewController *page in self.pageCache.allValues) {
		[self savePlaybackTimeForPage:page];
		[self stopPage:page];
	}

	[self.pageCache removeAllObjects];
}

- (void)closeTapped {
	[self stopAllCachedPages];
	[self dismissViewControllerAnimated:YES completion:nil];
}

- (void)viewDidAppear:(BOOL)animated {
	[super viewDidAppear:animated];
	[self playPage:self.currentPage];
}

- (void)viewWillDisappear:(BOOL)animated {
	[super viewWillDisappear:animated];
	[self pausePage:self.currentPage];
}

- (void)dealloc {
	[self stopAllCachedPages];
}

#pragma mark - Share / Save

- (NSArray<UIMenuElement *> *)shareMenuChildren {
	__weak typeof(self) weakSelf = self;
	NSMutableArray<UIMenuElement *> *children = [NSMutableArray array];

	// Photos library rejects audio.
	if (!self.currentItem.audioURL) {
		[children addObject:[UIAction actionWithTitle:RYGLocalized(@"Save to Photos")
												image:[UIImage systemImageNamed:@"square.and.arrow.down"]
										   identifier:nil
											  handler:^(__unused UIAction *action) {
			[weakSelf saveCurrentToPhotos];
		}]];
	}

	if ([RYGUtils getBoolPref:@"ryg_gallery_enabled"]) {
		[children addObject:[UIAction actionWithTitle:RYGLocalized(@"Save to Gallery")
												image:[RYGIcon menuImageNamed:@"ig_icon_photo_gallery_prism_outline_24" pointSize:18]
										   identifier:nil
											  handler:^(__unused UIAction *action) {
			[weakSelf saveCurrentToGallery];
		}]];
	}

	[children addObject:[UIAction actionWithTitle:RYGLocalized(@"Share")
											image:[UIImage systemImageNamed:@"square.and.arrow.up"]
									   identifier:nil
										  handler:^(__unused UIAction *action) {
		[weakSelf shareTapped];
	}]];

	return children;
}

- (void)saveCurrentToPhotos {
	RYGMediaViewerItem *item = self.currentItem;
	NSURL *source = [self sourceURLForItem:item];

	if (!source) {
		RYGNotifyError(RYG_NOTIF_DOWNLOAD, RYGLocalized(@"Save failed"), RYGLocalized(@"Nothing to save"));
		return;
	}

	RYGGallerySaveMetadata *metadata = item.metadata ?: RYGGallerySaveMetadata.new;
	NSString *ext = source.pathExtension.lowercaseString;
	if (!ext.length) ext = item.videoURL ? @"mp4" : @"jpg";

	if (source.isFileURL) {
		// Copy so Photos' move-on-import can't eat the file the viewer is playing.
		NSString *name = [[RYGFileName stemForURL:source metadata:metadata] stringByAppendingPathExtension:ext];
		NSURL *copy = [RYGTempFiles claimNamedFile:name ttl:300 tag:@"save"];
		if (![NSFileManager.defaultManager copyItemAtURL:source toURL:copy error:nil]) {
			[RYGTempFiles releaseURL:copy];
			RYGNotifyError(RYG_NOTIF_DOWNLOAD, RYGLocalized(@"Save failed"), RYGLocalized(@"Failed to save"));
			return;
		}
		RYGDownloadDelegate *dl = [[RYGDownloadDelegate alloc] initWithAction:saveToPhotos showProgress:NO];
		dl.pendingGallerySaveMetadata = metadata;
		[dl saveLocalFileURL:copy hudLabel:nil];
		return;
	}

	RYGDownloadDelegate *dl = [[RYGDownloadDelegate alloc] initWithAction:saveToPhotos showProgress:YES];
	dl.pendingGallerySaveMetadata = metadata;
	[dl downloadFileWithURL:source fileExtension:ext hudLabel:nil];
}

- (void)notifySaveResult:(RYGGalleryFile *)file error:(NSError *)error metadata:(RYGGallerySaveMetadata *)metadata {
	if (file) {
		NSString *username = metadata.sourceUsername;
		NSString *subtitle = username.length ? [@"@" stringByAppendingString:username] : nil;
		RYGNotifySuccess(RYG_NOTIF_GALLERY_SAVE, RYGLocalized(@"Saved to Gallery"), subtitle);
		return;
	}

	RYGNotifyError(RYG_NOTIF_GALLERY_SAVE, RYGLocalized(@"Save failed"), error.localizedDescription ?: RYGLocalized(@"Failed to save"));
}

- (void)saveFileURLToGallery:(NSURL *)url item:(RYGMediaViewerItem *)item mediaType:(RYGGalleryMediaType)mediaType metadata:(RYGGallerySaveMetadata *)metadata removeAfterSave:(BOOL)removeAfterSave {
	NSError *error = nil;
	RYGGalleryFile *file = [RYGGalleryFile saveFileToGallery:url source:(RYGGallerySource)metadata.source mediaType:mediaType folderPath:nil metadata:metadata error:&error];
	if (removeAfterSave) [NSFileManager.defaultManager removeItemAtURL:url error:nil];
	[self notifySaveResult:file error:error metadata:metadata];
}

- (void)saveCurrentToGallery {
	RYGMediaViewerItem *item = self.currentItem;
	NSURL *source = [self sourceURLForItem:item];

	if (!source) {
		RYGNotifyError(RYG_NOTIF_GALLERY_SAVE, RYGLocalized(@"Save failed"), RYGLocalized(@"Nothing to save"));
		return;
	}

	RYGGallerySaveMetadata *metadata = item.metadata ?: RYGGallerySaveMetadata.new;
	NSString *ext = source.pathExtension.lowercaseString ?: @"";
	RYGGalleryMediaType mediaType = item.audioURL ? RYGGalleryMediaTypeAudio : item.videoURL ? RYGGalleryMediaTypeVideo : item.animatedImageURL ? RYGGalleryMediaTypeGIF : RYGGalleryMediaTypeForExtension(ext);

	if (source.isFileURL) {
		[self saveFileURLToGallery:source item:item mediaType:mediaType metadata:metadata removeAfterSave:NO];
		return;
	}

	__weak typeof(self) weakSelf = self;
	[RYGImageCache loadDataFromURL:source completion:^(NSData *data) {
		__strong typeof(weakSelf) self = weakSelf;
		if (!self) return;

		if (!data.length) {
			RYGNotifyError(RYG_NOTIF_GALLERY_SAVE, RYGLocalized(@"Save failed"), RYGLocalized(@"Nothing to save"));
			return;
		}

		NSString *useExt = ext.length ? ext : @"jpg";
		NSURL *tempURL = [RYGTempFiles claimWithExt:useExt ttl:300 tag:@"save"];

		if (![data writeToURL:tempURL atomically:YES]) {
			RYGNotifyError(RYG_NOTIF_GALLERY_SAVE, RYGLocalized(@"Save failed"), RYGLocalized(@"Failed to save"));
			return;
		}

		NSURL *safeURL = [RYGUtils photoSafeImageFileURL:tempURL];
		RYGGalleryMediaType type = [safeURL isEqual:tempURL] ? mediaType : RYGGalleryMediaTypeForExtension(safeURL.pathExtension);
		[self saveFileURLToGallery:safeURL item:item mediaType:type metadata:metadata removeAfterSave:YES];
	}];
}

- (void)presentActivityWithItems:(NSArray *)items cleanupURL:(NSURL *)cleanupURL {
	if (!items.count) return;

	UIActivityViewController *controller = [[UIActivityViewController alloc] initWithActivityItems:items applicationActivities:nil];
	controller.popoverPresentationController.sourceView = self.shareBtn;

	if (cleanupURL) {
		controller.completionWithItemsHandler = ^(__unused UIActivityType type, __unused BOOL completed, __unused NSArray *returnedItems, __unused NSError *error) {
			[RYGTempFiles releaseURL:cleanupURL];
		};
	}

	[RYGPhotoAlbum armWatcherIfEnabled];
	[self presentViewController:controller animated:YES completion:nil];
}

- (void)shareFileURL:(NSURL *)url {
	if (url) [self presentActivityWithItems:@[url] cleanupURL:nil];
}

- (void)sharePhotoItem:(RYGMediaViewerItem *)item currentPage:(UIViewController *)page {
	if (!item.photoURL) return;

	UIImage *fallbackImage = [page isKindOfClass:_RYGPhotoPageVC.class] ? [(_RYGPhotoPageVC *)page currentImage] : nil;
	__weak typeof(self) weakSelf = self;

	[RYGImageCache loadDataFromURL:item.photoURL completion:^(NSData *data) {
		__strong typeof(weakSelf) self = weakSelf;
		if (!self) return;

		NSMutableArray *items = NSMutableArray.array;
		NSURL *tempURL = nil;

		if (data.length) {
			BOOL transcode = NO;
			NSString *ext = RYGSniffImageExt(data, &transcode);
			NSData *output = data;

			if (transcode) {
				UIImage *decoded = [UIImage imageWithData:data];
				NSData *png = decoded ? UIImagePNGRepresentation(decoded) : nil;
				if (png) output = png;
				else ext = @"webp";
			}

			NSString *name = [[RYGFileName stemForURL:item.photoURL metadata:item.metadata] stringByAppendingPathExtension:ext];
			tempURL = [RYGTempFiles claimNamedFile:name ttl:600 tag:@"share"];
			if ([output writeToURL:tempURL atomically:YES]) [items addObject:tempURL];
		}

		if (!items.count && fallbackImage) [items addObject:fallbackImage];
		if (!items.count && item.photoURL) [items addObject:item.photoURL];

		[self presentActivityWithItems:items cleanupURL:tempURL];
	}];
}

- (void)shareTapped {
	RYGMediaViewerItem *item = self.currentItem;
	UIViewController *page = self.currentPage;

	if (item.audioURL || item.animatedImageURL) {
		[self shareFileURL:(item.audioURL ?: item.animatedImageURL)];
		return;
	}

	if (item.videoURL) {
		[self shareFileURL:item.videoURL];
		return;
	}

	[self sharePhotoItem:item currentPage:page];
}

#pragma mark - Page data source

- (UIViewController *)viewControllerForIndex:(NSUInteger)index {
	if (index >= self.items.count) return nil;

	NSNumber *key = @(index);
	UIViewController *cached = self.pageCache[key];
	if (cached) {
		cached.view.tag = (NSInteger)index;
		[self restorePlaybackTimeForPage:cached];
		return cached;
	}

	RYGMediaViewerItem *item = self.items[index];
	UIViewController *vc = nil;

	if (item.videoURL) {
		_RYGVideoPageVC *page = _RYGVideoPageVC.new;
		page.videoURL = item.videoURL;
		vc = page;
	} else if (item.audioURL) {
		_RYGAudioPageVC *page = _RYGAudioPageVC.new;
		page.audioURL = item.audioURL;
		vc = page;
	} else if (item.animatedImageURL) {
		_RYGAnimatedPageVC *page = _RYGAnimatedPageVC.new;
		page.animatedURL = item.animatedImageURL;
		vc = page;
	} else if (item.photoURL) {
		_RYGPhotoPageVC *page = _RYGPhotoPageVC.new;
		page.photoURL = item.photoURL;
		vc = page;
	}

	if (!vc) return nil;

	vc.view.tag = (NSInteger)index;
	self.pageCache[key] = vc;
	return vc;
}

- (UIViewController *)pageViewController:(UIPageViewController *)pageViewController viewControllerBeforeViewController:(UIViewController *)viewController {
	NSInteger index = viewController.view.tag;
	return index > 0 ? [self viewControllerForIndex:(NSUInteger)(index - 1)] : nil;
}

- (UIViewController *)pageViewController:(UIPageViewController *)pageViewController viewControllerAfterViewController:(UIViewController *)viewController {
	NSInteger index = viewController.view.tag;
	return index + 1 < (NSInteger)self.items.count ? [self viewControllerForIndex:(NSUInteger)(index + 1)] : nil;
}

- (void)pageViewController:(UIPageViewController *)pageViewController willTransitionToViewControllers:(NSArray<UIViewController *> *)pendingViewControllers {
	[self pausePage:self.currentPage];
}

- (void)pageViewController:(UIPageViewController *)pageViewController didFinishAnimating:(BOOL)finished previousViewControllers:(NSArray<UIViewController *> *)previousViewControllers transitionCompleted:(BOOL)completed {
	if (!completed) {
		[self playPage:self.currentPage];
		return;
	}

	for (UIViewController *page in previousViewControllers) {
		[self pausePage:page];
	}

	UIViewController *current = pageViewController.viewControllers.firstObject;
	self.currentIndex = (NSUInteger)current.view.tag;

	[self playPage:current];
	[self updateChrome];
}

- (BOOL)prefersStatusBarHidden {
	return YES;
}

- (BOOL)prefersHomeIndicatorAutoHidden {
	return YES;
}

@end

#pragma mark - Public API

@implementation RYGMediaViewer

+ (void)presentNativeVideoPlayer:(NSURL *)url {
	if (!url) return;

	dispatch_async(dispatch_get_main_queue(), ^{
		AVPlayerViewController *playerVC = AVPlayerViewController.new;
		playerVC.player = [AVPlayer playerWithURL:url];
		playerVC.player.muted = [RYGUtils getBoolPref:@"media_zoom_start_muted"];
		playerVC.modalPresentationStyle = UIModalPresentationFullScreen;

		[topMostController() presentViewController:playerVC animated:YES completion:^{
			[playerVC.player play];
		}];
	});
}

+ (void)showItem:(RYGMediaViewerItem *)item {
	if (!item) {
		[RYGUtils showErrorHUDWithDescription:RYGLocalized(@"No media to show")];
		return;
	}

	if (item.videoURL) {
		[self presentNativeVideoPlayer:item.videoURL];
		return;
	}

	[self showItems:@[item] startIndex:0 shareSheetOnly:NO];
}

+ (void)showItems:(NSArray<RYGMediaViewerItem *> *)items startIndex:(NSUInteger)index {
	[self showItems:items startIndex:index shareSheetOnly:NO];
}

+ (void)showItems:(NSArray<RYGMediaViewerItem *> *)items startIndex:(NSUInteger)index shareSheetOnly:(BOOL)shareSheetOnly {
	if (!items.count) {
		[RYGUtils showErrorHUDWithDescription:RYGLocalized(@"No media to show")];
		return;
	}

	if (index >= items.count) index = 0;

	if (items.count == 1 && items.firstObject.videoURL) {
		[self presentNativeVideoPlayer:items.firstObject.videoURL];
		return;
	}

	dispatch_async(dispatch_get_main_queue(), ^{
		_RYGMediaViewerContainerVC *viewer = _RYGMediaViewerContainerVC.new;
		viewer.items = items;
		viewer.currentIndex = index;
		viewer.shareSheetOnly = shareSheetOnly;
		viewer.modalPresentationStyle = UIModalPresentationOverFullScreen;
		viewer.modalTransitionStyle = UIModalTransitionStyleCrossDissolve;

		[topMostController() presentViewController:viewer animated:YES completion:nil];
	});
}

+ (void)showWithVideoURL:(NSURL *)videoURL photoURL:(NSURL *)photoURL caption:(NSString *)caption {
	[self showItem:[RYGMediaViewerItem itemWithVideoURL:videoURL photoURL:photoURL caption:caption]];
}

@end