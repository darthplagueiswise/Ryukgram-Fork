#import "SCITrimViewController.h"
#import "Utils.h"

static const CGFloat kMargin = 24.0;
static const CGFloat kTrackH = 56.0;
static const CGFloat kHandleW = 46.0;
static const CGFloat kMinTrim = 0.5;
static const NSInteger kWaveTag = 8801;

@interface SCITrimViewController ()
@property (nonatomic, strong) AVPlayer *player;
@property (nonatomic, strong) AVPlayerLayer *playerLayer;
@property (nonatomic, strong) id observer;
@property (nonatomic, strong) UIView *preview;
@property (nonatomic, strong) UILabel *durationLabel;
@property (nonatomic, strong) UILabel *rangeLabel;
@property (nonatomic, strong) UIView *track;
@property (nonatomic, strong) UIView *selected;
@property (nonatomic, strong) UIView *leftHandle;
@property (nonatomic, strong) UIView *rightHandle;
@property (nonatomic, strong) UIView *playhead;
@property (nonatomic, strong) UIButton *closeButton;
@property (nonatomic, strong) UIButton *playButton;
@property (nonatomic, strong) UIButton *stopButton;
@property (nonatomic, strong) UIButton *sendButton;
@property (nonatomic) double totalDuration;
@property (nonatomic) double startTime;
@property (nonatomic) double endTime;
@property (nonatomic) BOOL playing;
@property (nonatomic) CGFloat lastTrackWidth;
@end

@implementation SCITrimViewController

- (void)viewDidLoad {
	[super viewDidLoad];
	SCIUIKit26ConfigureViewController(self);

	self.overrideUserInterfaceStyle = UIUserInterfaceStyleDark;
	self.view.backgroundColor = [UIColor colorWithRed:0.055 green:0.055 blue:0.075 alpha:1.0];

	[self prepareTime];
	[self preparePlayer];
	[self buildUI];
	[self updateUI];
}

- (void)viewDidLayoutSubviews {
	[super viewDidLayoutSubviews];

	CGRect b = self.view.bounds;
	UIEdgeInsets s = self.view.safeAreaInsets;
	CGFloat w = CGRectGetWidth(b), h = CGRectGetHeight(b), cw = w - kMargin * 2.0;

	self.closeButton.frame = CGRectMake(14.0, s.top + 10.0, 38.0, 38.0);
	self.sendButton.frame = CGRectMake(kMargin, h - s.bottom - 66.0, cw, 52.0);
	self.playButton.frame = CGRectMake((w - 58.0) * 0.5, CGRectGetMinY(self.sendButton.frame) - 76.0, 58.0, 58.0);
	self.stopButton.frame = CGRectMake(CGRectGetMaxX(self.playButton.frame) + 16.0, CGRectGetMidY(self.playButton.frame) - 21.0, 42.0, 42.0);
	self.rangeLabel.frame = CGRectMake(kMargin, CGRectGetMinY(self.playButton.frame) - 38.0, cw, 22.0);
	self.track.frame = CGRectMake(kMargin, CGRectGetMinY(self.rangeLabel.frame) - kTrackH - 20.0, cw, kTrackH);
	self.durationLabel.frame = CGRectMake(kMargin, CGRectGetMinY(self.track.frame) - 24.0, cw, 16.0);

	CGFloat top = s.top + 62.0;
	CGFloat bottom = CGRectGetMinY(self.durationLabel.frame) - 20.0;
	CGFloat ph = MAX(92.0, bottom - top);
	CGFloat audioH = MIN(150.0, MAX(110.0, ph));

	self.preview.frame = self.isVideo ? CGRectMake(kMargin, top, cw, ph) : CGRectMake(kMargin, top + (ph - audioH) * 0.5, cw, audioH);
	self.playerLayer.frame = self.preview.bounds;

	[self layoutWaveIcon];
	[self rebuildWaveformIfNeeded];
	[self updateUI];
}

- (void)dealloc {
	[self cleanup];
}

- (UIStatusBarStyle)preferredStatusBarStyle {
	return UIStatusBarStyleLightContent;
}

#pragma mark - Setup

- (void)prepareTime {
	AVAsset *asset = [AVAsset assetWithURL:self.mediaURL];
	double d = CMTimeGetSeconds(asset.duration);

	self.totalDuration = (d > 0.0 && isfinite(d)) ? d : 1.0;
	self.startTime = 0.0;
	self.endTime = self.maxDurationSecs > 0.0 ? MIN(self.totalDuration, self.maxDurationSecs) : self.totalDuration;
}

- (void)preparePlayer {
	[[AVAudioSession sharedInstance] setCategory:AVAudioSessionCategoryPlayback error:nil];
	[[AVAudioSession sharedInstance] setActive:YES error:nil];

	self.player = [AVPlayer playerWithURL:self.mediaURL];

	__weak typeof(self) weakSelf = self;
	self.observer = [self.player addPeriodicTimeObserverForInterval:CMTimeMakeWithSeconds(0.03, 600) queue:dispatch_get_main_queue() usingBlock:^(CMTime time) {
		__strong typeof(weakSelf) self = weakSelf;
		if (!self || !self.playing) return;

		double now = CMTimeGetSeconds(time);
		if (!isfinite(now)) return;

		if (now >= self.endTime) {
			[self pause];
			[self seek:self.endTime show:YES];
		} else {
			[self movePlayhead:now];
		}
	}];
}

- (void)buildUI {
	self.closeButton = [self button:@"xmark" size:16.0 bg:0.09 radius:19.0];
	[self.closeButton addTarget:self action:@selector(cancelTapped) forControlEvents:UIControlEventTouchUpInside];
	[self.view addSubview:self.closeButton];

	self.preview = UIView.new;
	self.preview.backgroundColor = self.isVideo ? UIColor.blackColor : [UIColor colorWithWhite:1.0 alpha:0.055];
	self.preview.layer.cornerRadius = 18.0;
	self.preview.layer.cornerCurve = kCACornerCurveContinuous;
	self.preview.clipsToBounds = YES;
	[self.view addSubview:self.preview];

	if (self.isVideo) {
		self.playerLayer = [AVPlayerLayer playerLayerWithPlayer:self.player];
		self.playerLayer.videoGravity = AVLayerVideoGravityResizeAspect;
		[self.preview.layer addSublayer:self.playerLayer];
	} else {
		UIImageView *icon = [[UIImageView alloc] initWithImage:[UIImage systemImageNamed:@"waveform" withConfiguration:[UIImageSymbolConfiguration configurationWithPointSize:46.0 weight:UIImageSymbolWeightLight]]];
		icon.tag = 9001;
		icon.tintColor = [UIColor colorWithWhite:1.0 alpha:0.55];
		icon.contentMode = UIViewContentModeScaleAspectFit;
		[self.preview addSubview:icon];
	}

	self.durationLabel = [self label:12.0 weight:UIFontWeightRegular color:0.32 mono:NO];
	self.durationLabel.text = [NSString stringWithFormat:SCILocalized(@"Total: %@"), [self timeText:self.totalDuration]];

	self.rangeLabel = [self label:15.0 weight:UIFontWeightMedium color:1.0 mono:YES];

	[self.view addSubview:self.durationLabel];
	[self.view addSubview:self.rangeLabel];

	self.track = UIView.new;
	self.track.backgroundColor = [UIColor colorWithWhite:1.0 alpha:0.08];
	self.track.layer.cornerRadius = 12.0;
	self.track.layer.cornerCurve = kCACornerCurveContinuous;
	self.track.clipsToBounds = YES;
	[self.view addSubview:self.track];

	self.selected = UIView.new;
	self.selected.backgroundColor = [UIColor.systemBlueColor colorWithAlphaComponent:0.28];
	self.selected.userInteractionEnabled = NO;
	[self.track addSubview:self.selected];

	self.leftHandle = [self handle:YES];
	self.rightHandle = [self handle:NO];
	[self.track addSubview:self.leftHandle];
	[self.track addSubview:self.rightHandle];

	[self.leftHandle addGestureRecognizer:[[UIPanGestureRecognizer alloc] initWithTarget:self action:@selector(leftPan:)]];
	[self.rightHandle addGestureRecognizer:[[UIPanGestureRecognizer alloc] initWithTarget:self action:@selector(rightPan:)]];

	self.playhead = UIView.new;
	self.playhead.backgroundColor = UIColor.whiteColor;
	self.playhead.layer.cornerRadius = 1.25;
	self.playhead.hidden = YES;
	[self.track addSubview:self.playhead];

	self.playButton = [self button:@"play.fill" size:22.0 bg:0.11 radius:29.0];
	self.stopButton = [self button:@"stop.fill" size:17.0 bg:0.085 radius:21.0];
	self.stopButton.tintColor = [UIColor colorWithWhite:1.0 alpha:0.72];

	[self.playButton addTarget:self action:@selector(playTapped) forControlEvents:UIControlEventTouchUpInside];
	[self.stopButton addTarget:self action:@selector(stopTapped) forControlEvents:UIControlEventTouchUpInside];

	self.sendButton = [UIButton buttonWithType:UIButtonTypeSystem];
	self.sendButton.backgroundColor = UIColor.systemBlueColor;
	self.sendButton.layer.cornerRadius = 16.0;
	self.sendButton.layer.cornerCurve = kCACornerCurveContinuous;
	self.sendButton.titleLabel.font = [UIFont systemFontOfSize:17.0 weight:UIFontWeightSemibold];
	[self.sendButton setTitle:self.sendButtonTitle ?: SCILocalized(@"Send") forState:UIControlStateNormal];
	[self.sendButton setTitleColor:UIColor.whiteColor forState:UIControlStateNormal];
	[self.sendButton addTarget:self action:@selector(sendTapped) forControlEvents:UIControlEventTouchUpInside];

	[self.view addSubview:self.playButton];
	[self.view addSubview:self.stopButton];
	[self.view addSubview:self.sendButton];
}

#pragma mark - UI

- (UILabel *)label:(CGFloat)size weight:(UIFontWeight)weight color:(CGFloat)alpha mono:(BOOL)mono {
	UILabel *label = UILabel.new;
	label.font = mono ? [UIFont monospacedDigitSystemFontOfSize:size weight:weight] : [UIFont systemFontOfSize:size weight:weight];
	label.textColor = [UIColor colorWithWhite:1.0 alpha:alpha];
	label.textAlignment = NSTextAlignmentCenter;
	return label;
}

- (UIButton *)button:(NSString *)symbol size:(CGFloat)size bg:(CGFloat)alpha radius:(CGFloat)radius {
	UIButton *button = [UIButton buttonWithType:UIButtonTypeCustom];
	button.backgroundColor = [UIColor colorWithWhite:1.0 alpha:alpha];
	button.tintColor = UIColor.whiteColor;
	button.layer.cornerRadius = radius;
	button.layer.cornerCurve = kCACornerCurveContinuous;
	[button setImage:[UIImage systemImageNamed:symbol withConfiguration:[UIImageSymbolConfiguration configurationWithPointSize:size weight:UIImageSymbolWeightMedium]] forState:UIControlStateNormal];
	return button;
}

- (UIView *)handle:(BOOL)left {
	UIView *hit = UIView.new;
	hit.backgroundColor = UIColor.clearColor;

	UIView *body = [[UIView alloc] initWithFrame:CGRectMake((kHandleW - 16.0) * 0.5, 0.0, 16.0, kTrackH)];
	body.backgroundColor = UIColor.systemBlueColor;
	body.layer.cornerRadius = 5.0;
	body.layer.cornerCurve = kCACornerCurveContinuous;
	body.layer.maskedCorners = left ? (kCALayerMinXMinYCorner | kCALayerMinXMaxYCorner) : (kCALayerMaxXMinYCorner | kCALayerMaxXMaxYCorner);
	body.userInteractionEnabled = NO;

	for (NSInteger i = 0; i < 2; i++) {
		UIView *line = [[UIView alloc] initWithFrame:CGRectMake(5.0 + i * 4.0, 20.0, 1.5, 16.0)];
		line.backgroundColor = [UIColor colorWithWhite:1.0 alpha:0.72];
		line.layer.cornerRadius = 0.75;
		[body addSubview:line];
	}

	[hit addSubview:body];
	return hit;
}

- (void)layoutWaveIcon {
	UIView *icon = [self.preview viewWithTag:9001];
	if (!icon) return;

	icon.frame = CGRectMake((CGRectGetWidth(self.preview.bounds) - 72.0) * 0.5, (CGRectGetHeight(self.preview.bounds) - 72.0) * 0.5, 72.0, 72.0);
}

#pragma mark - Waveform

- (void)rebuildWaveformIfNeeded {
	CGFloat w = CGRectGetWidth(self.track.bounds);
	if (w <= 0.0 || fabs(w - self.lastTrackWidth) < 1.0) return;

	self.lastTrackWidth = w;

	for (UIView *view in self.track.subviews.copy) {
		if (view.tag == kWaveTag) [view removeFromSuperview];
	}

	NSInteger count = MAX(24, (NSInteger)(w / 4.0));
	CGFloat barW = 2.0;
	CGFloat gap = count > 1 ? (w - count * barW) / (count - 1) : 0.0;

	for (NSInteger i = 0; i < count; i++) {
		CGFloat n = 0.25 + ((i * 37) % 70) / 100.0;
		CGFloat h = MAX(8.0, MIN(kTrackH - 14.0, n * (kTrackH - 8.0)));
		UIView *bar = [[UIView alloc] initWithFrame:CGRectMake(i * (barW + gap), (kTrackH - h) * 0.5, barW, h)];
		bar.tag = kWaveTag;
		bar.backgroundColor = [UIColor colorWithWhite:1.0 alpha:0.16];
		bar.layer.cornerRadius = 1.0;
		[self.track insertSubview:bar atIndex:0];
	}

	[self.track bringSubviewToFront:self.selected];
	[self.track bringSubviewToFront:self.leftHandle];
	[self.track bringSubviewToFront:self.rightHandle];
	[self.track bringSubviewToFront:self.playhead];
}

#pragma mark - Time

- (CGFloat)xForTime:(double)time {
	CGFloat w = CGRectGetWidth(self.track.bounds);
	return self.totalDuration > 0.0 ? (CGFloat)(MAX(0.0, MIN(time, self.totalDuration)) / self.totalDuration) * w : 0.0;
}

- (double)timeForX:(CGFloat)x {
	CGFloat w = CGRectGetWidth(self.track.bounds);
	return (w > 0.0 && self.totalDuration > 0.0) ? MAX(0.0, MIN((x / w) * self.totalDuration, self.totalDuration)) : 0.0;
}

- (NSString *)timeText:(double)seconds {
	if (!isfinite(seconds) || seconds < 0.0) seconds = 0.0;
	NSInteger total = (NSInteger)floor(seconds);
	return [NSString stringWithFormat:@"%ld:%02ld", (long)(total / 60), (long)(total % 60)];
}

- (NSString *)durationText:(double)seconds {
	if (!isfinite(seconds) || seconds < 0.0) seconds = 0.0;
	if (seconds < 60.0) return [NSString stringWithFormat:@"%.1fs", seconds];

	NSInteger minutes = (NSInteger)(seconds / 60.0);
	NSInteger secs = (NSInteger)round(seconds - minutes * 60.0);
	return [NSString stringWithFormat:@"%ldm %lds", (long)minutes, (long)secs];
}

#pragma mark - Range

- (void)updateUI {
	if (!self.track) return;

	CGFloat left = [self xForTime:self.startTime];
	CGFloat right = [self xForTime:self.endTime];

	self.selected.frame = CGRectMake(left, 0.0, MAX(0.0, right - left), kTrackH);
	self.leftHandle.frame = CGRectMake(left - kHandleW * 0.5, 0.0, kHandleW, kTrackH);
	self.rightHandle.frame = CGRectMake(right - kHandleW * 0.5, 0.0, kHandleW, kTrackH);
	self.rangeLabel.text = [NSString stringWithFormat:@"%@  —  %@   (%@)", [self timeText:self.startTime], [self timeText:self.endTime], [self durationText:self.endTime - self.startTime]];

	[self movePlayhead:[self currentTime]];
}

- (void)movePlayhead:(double)time {
	CGFloat x = [self xForTime:MAX(self.startTime, MIN(time, self.endTime))];
	self.playhead.frame = CGRectMake(x - 1.25, 3.0, 2.5, kTrackH - 6.0);
}

- (void)leftPan:(UIPanGestureRecognizer *)pan {
	[self handlePan:pan left:YES];
}

- (void)rightPan:(UIPanGestureRecognizer *)pan {
	[self handlePan:pan left:NO];
}

- (void)handlePan:(UIPanGestureRecognizer *)pan left:(BOOL)left {
	if (pan.state == UIGestureRecognizerStateBegan) [self pause];

	CGFloat dx = [pan translationInView:self.track].x;
	[pan setTranslation:CGPointZero inView:self.track];

	if (left) {
		self.startTime = MAX(0.0, MIN([self timeForX:CGRectGetMidX(self.leftHandle.frame) + dx], self.endTime - kMinTrim));
		if (self.maxDurationSecs > 0.0 && self.endTime - self.startTime > self.maxDurationSecs) self.endTime = self.startTime + self.maxDurationSecs;
	} else {
		self.endTime = MIN(self.totalDuration, MAX([self timeForX:CGRectGetMidX(self.rightHandle.frame) + dx], self.startTime + kMinTrim));
		if (self.maxDurationSecs > 0.0 && self.endTime - self.startTime > self.maxDurationSecs) self.endTime = self.startTime + self.maxDurationSecs;
	}

	[self updateUI];

	if (pan.state == UIGestureRecognizerStateEnded || pan.state == UIGestureRecognizerStateCancelled) {
		[self seek:self.startTime show:NO];
	}
}

#pragma mark - Playback

- (double)currentTime {
	double time = CMTimeGetSeconds(self.player.currentTime);
	return isfinite(time) && time >= 0.0 ? time : self.startTime;
}

- (void)setPlaySymbol:(NSString *)symbol {
	[self.playButton setImage:[UIImage systemImageNamed:symbol withConfiguration:[UIImageSymbolConfiguration configurationWithPointSize:22.0 weight:UIImageSymbolWeightMedium]] forState:UIControlStateNormal];
}

- (void)playTapped {
	self.playing ? [self pause] : [self play];
}

- (void)play {
	double pos = [self currentTime];
	if (pos < self.startTime || pos >= self.endTime - 0.05) pos = self.startTime;

	self.playing = YES;
	self.playhead.hidden = NO;

	[self movePlayhead:pos];
	[self setPlaySymbol:@"pause.fill"];

	__weak typeof(self) weakSelf = self;
	[self.player seekToTime:CMTimeMakeWithSeconds(pos, 600) toleranceBefore:CMTimeMakeWithSeconds(0.04, 600) toleranceAfter:CMTimeMakeWithSeconds(0.04, 600) completionHandler:^(BOOL finished) {
		__strong typeof(weakSelf) self = weakSelf;
		if (self && finished && self.playing) [self.player play];
	}];
}

- (void)pause {
	self.playing = NO;
	[self.player pause];
	[self setPlaySymbol:@"play.fill"];
}

- (void)stopTapped {
	[self pause];
	[self seek:self.startTime show:NO];
	self.playhead.hidden = YES;
}

- (void)seek:(double)time show:(BOOL)show {
	double clamped = MAX(self.startTime, MIN(time, self.endTime));

	if (show) {
		self.playhead.hidden = NO;
		[self movePlayhead:clamped];
	}

	[self.player seekToTime:CMTimeMakeWithSeconds(clamped, 600) toleranceBefore:CMTimeMakeWithSeconds(0.04, 600) toleranceAfter:CMTimeMakeWithSeconds(0.04, 600)];
}

#pragma mark - Actions

- (void)cancelTapped {
	[self cleanup];
	[self deletePreConvertedTempIfNeeded];

	void (^callback)(void) = self.onCancel;
	[self dismissViewControllerAnimated:YES completion:^{
		if (callback) callback();
	}];
}

- (void)sendTapped {
	double duration = self.endTime - self.startTime;

	if (duration < kMinTrim) {
		[SCIUtils showErrorHUDWithDescription:SCILocalized(@"Selection too short (min 0.5s)")];
		return;
	}

	CMTimeRange range = CMTimeRangeMake(CMTimeMakeWithSeconds(self.startTime, 600), CMTimeMakeWithSeconds(duration, 600));
	void (^callback)(CMTimeRange) = self.onSend;

	[self cleanup];
	[self dismissViewControllerAnimated:YES completion:^{
		if (callback) callback(range);
	}];
}

#pragma mark - Cleanup

- (void)cleanup {
	if (self.observer && self.player) [self.player removeTimeObserver:self.observer];

	self.observer = nil;

	[self.player pause];
	self.player = nil;

	[self.playerLayer removeFromSuperlayer];
	self.playerLayer = nil;

	self.playing = NO;

	[[AVAudioSession sharedInstance] setActive:NO withOptions:AVAudioSessionSetActiveOptionNotifyOthersOnDeactivation error:nil];
}

- (void)deletePreConvertedTempIfNeeded {
	if (!self.mediaURL.isFileURL) return;

	NSString *name = self.mediaURL.lastPathComponent ?: @"";
	if ([name hasPrefix:@"ryuk_tmp_"] || [name hasPrefix:@"sci_tmp_"]) [SCITempFiles releaseURL:self.mediaURL];
}
@end
