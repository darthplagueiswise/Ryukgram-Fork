#import "SCIVideoEditor.h"
#import <AVFoundation/AVFoundation.h>
#import "../Features/Instants/SCIInstantsPath.h"
#import "../SCITempFiles.h"
#import "../Localization/SCILocalization.h"

static const NSTimeInterval kSCIMinTrim = 1.0;
static const CGFloat kSCITrimBarH = 56.0;
static const NSTimeInterval kSCIStripWindowSecs = 25.0;

@interface SCIVideoEditorController : UIViewController <UIScrollViewDelegate>
@property (nonatomic, strong) NSURL *assetURL;
@property (nonatomic) NSTimeInterval maxDuration;
@property (nonatomic) CGFloat aspectW;
@property (nonatomic) CGFloat aspectH;
@property (nonatomic, copy) void (^onDone)(NSURL *edited);
@end

@implementation SCIVideoEditorController {
	AVURLAsset *_asset;
	AVAssetTrack *_track;
	CGSize _orientedSize;
	NSTimeInterval _duration;

	UIScrollView *_scroll;
	UIView *_contentView;
	AVPlayer *_player;
	AVPlayerLayer *_playerLayer;
	id _timeObserver;

	UIView *_overlay;
	CAShapeLayer *_dimLayer;
	CAShapeLayer *_borderLayer;
	CGFloat _cropW;
	CGFloat _cropH;
	BOOL _configured;

	UIView *_trimBar;
	UIScrollView *_stripScroll;
	UIView *_stripContent;
	UIView *_leftHandle;
	UIView *_rightHandle;
	UIView *_selBorder;
	UIView *_dimLeft;
	UIView *_dimRight;
	UIView *_playhead;
	NSTimeInterval _trimStart;
	NSTimeInterval _trimEnd;

	CGFloat _selLeftX;
	CGFloat _selRightX;
	CGFloat _maxSelPx;
	CGFloat _stripInset;
	CGFloat _stripVisibleW;
	BOOL _stripConfigured;

	UIButton *_cancelButton;
	UIButton *_useButton;
	UIButton *_playButton;
	UIButton *_restartButton;
	UILabel *_infoLabel;
	NSTimeInterval _playT;
	BOOL _playing;
	BOOL _exporting;
}

- (void)viewDidLoad {
	[super viewDidLoad];

	self.view.backgroundColor = [UIColor colorWithRed:0.055 green:0.055 blue:0.075 alpha:1.0];
	self.overrideUserInterfaceStyle = UIUserInterfaceStyleDark;
	self.modalPresentationStyle = UIModalPresentationFullScreen;

	_asset = [AVURLAsset URLAssetWithURL:self.assetURL options:nil];
	_track = [_asset tracksWithMediaType:AVMediaTypeVideo].firstObject;
	_duration = CMTimeGetSeconds(_asset.duration);

	CGRect oriented = CGRectApplyAffineTransform(CGRectMake(0, 0, _track.naturalSize.width, _track.naturalSize.height), _track.preferredTransform);
	_orientedSize = CGSizeMake(fabs(oriented.size.width), fabs(oriented.size.height));
	if (_orientedSize.width < 1 || _orientedSize.height < 1) _orientedSize = _track.naturalSize;

	_trimStart = 0;
	_trimEnd = MIN(_duration, self.maxDuration);
	_stripInset = 22.0;

	_scroll = [UIScrollView new];
	_scroll.delegate = self;
	_scroll.bouncesZoom = YES;
	_scroll.clipsToBounds = YES;
	_scroll.backgroundColor = UIColor.blackColor;
	_scroll.showsHorizontalScrollIndicator = NO;
	_scroll.showsVerticalScrollIndicator = NO;
	[self.view addSubview:_scroll];

	_contentView = [[UIView alloc] initWithFrame:(CGRect){ CGPointZero, _orientedSize }];
	_contentView.backgroundColor = UIColor.blackColor;
	[_scroll addSubview:_contentView];

	AVPlayerItem *item = [AVPlayerItem playerItemWithAsset:_asset];
	_player = [AVPlayer playerWithPlayerItem:item];
	_player.actionAtItemEnd = AVPlayerActionAtItemEndNone;
	_playerLayer = [AVPlayerLayer playerLayerWithPlayer:_player];
	_playerLayer.videoGravity = AVLayerVideoGravityResize;
	_playerLayer.frame = _contentView.bounds;
	[_contentView.layer addSublayer:_playerLayer];

	_overlay = [UIView new];
	_overlay.userInteractionEnabled = NO;
	[self.view addSubview:_overlay];

	_dimLayer = [CAShapeLayer layer];
	_dimLayer.fillColor = [UIColor colorWithWhite:0 alpha:0.55].CGColor;
	_dimLayer.fillRule = kCAFillRuleEvenOdd;
	[_overlay.layer addSublayer:_dimLayer];

	_borderLayer = [CAShapeLayer layer];
	_borderLayer.fillColor = UIColor.clearColor.CGColor;
	_borderLayer.strokeColor = [UIColor colorWithWhite:1 alpha:0.55].CGColor;
	_borderLayer.lineWidth = 1.0;
	[_overlay.layer addSublayer:_borderLayer];

	[self setupTrimBar];

	_infoLabel = [UILabel new];
	_infoLabel.textColor = UIColor.whiteColor;
	_infoLabel.font = [UIFont monospacedDigitSystemFontOfSize:15 weight:UIFontWeightMedium];
	_infoLabel.textAlignment = NSTextAlignmentCenter;
	_infoLabel.numberOfLines = 1;
	_infoLabel.adjustsFontSizeToFitWidth = YES;
	_infoLabel.minimumScaleFactor = 0.7;
	[self.view addSubview:_infoLabel];

	_cancelButton = [self circleButton:@"chevron.left" size:17 bgAlpha:0.09 radius:19];
	[_cancelButton addTarget:self action:@selector(cancelTapped) forControlEvents:UIControlEventTouchUpInside];
	[self.view addSubview:_cancelButton];

	_useButton = [UIButton buttonWithType:UIButtonTypeSystem];
	_useButton.backgroundColor = UIColor.systemBlueColor;
	_useButton.layer.cornerRadius = 16;
	_useButton.layer.cornerCurve = kCACornerCurveContinuous;
	_useButton.titleLabel.font = [UIFont systemFontOfSize:17 weight:UIFontWeightSemibold];
	[_useButton setTitle:SCILocalized(@"Use") forState:UIControlStateNormal];
	[_useButton setTitleColor:UIColor.whiteColor forState:UIControlStateNormal];
	[_useButton addTarget:self action:@selector(useTapped) forControlEvents:UIControlEventTouchUpInside];
	[self.view addSubview:_useButton];

	_playButton = [self circleButton:@"play.fill" size:22 bgAlpha:0.11 radius:29];
	[_playButton addTarget:self action:@selector(togglePlay) forControlEvents:UIControlEventTouchUpInside];
	[self.view addSubview:_playButton];

	_restartButton = [self circleButton:@"backward.end.fill" size:17 bgAlpha:0.085 radius:21];
	_restartButton.tintColor = [UIColor colorWithWhite:1.0 alpha:0.72];
	[_restartButton addTarget:self action:@selector(restartTapped) forControlEvents:UIControlEventTouchUpInside];
	[self.view addSubview:_restartButton];

	UITapGestureRecognizer *tap = [[UITapGestureRecognizer alloc] initWithTarget:self action:@selector(togglePlay)];
	[_scroll addGestureRecognizer:tap];

	[[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(appActive) name:UIApplicationDidBecomeActiveNotification object:nil];
}

- (UIButton *)circleButton:(NSString *)symbol size:(CGFloat)size bgAlpha:(CGFloat)alpha radius:(CGFloat)radius {
	UIButton *button = [UIButton buttonWithType:UIButtonTypeCustom];
	button.backgroundColor = [UIColor colorWithWhite:1.0 alpha:alpha];
	button.tintColor = UIColor.whiteColor;
	button.layer.cornerRadius = radius;
	button.layer.cornerCurve = kCACornerCurveContinuous;
	[button setImage:[UIImage systemImageNamed:symbol withConfiguration:[UIImageSymbolConfiguration configurationWithPointSize:size weight:UIImageSymbolWeightMedium]] forState:UIControlStateNormal];
	return button;
}

- (void)setPlaying:(BOOL)playing {
	_playing = playing;
	if (playing) [_player play]; else [_player pause];
	UIImageSymbolConfiguration *cfg = [UIImageSymbolConfiguration configurationWithPointSize:22 weight:UIImageSymbolWeightSemibold];
	NSString *sym = playing ? @"pause.fill" : @"play.fill";
	[_playButton setImage:[UIImage systemImageNamed:sym withConfiguration:cfg] forState:UIControlStateNormal];
}

- (void)togglePlay { [self setPlaying:!_playing]; }

- (void)restartTapped {
	[self seekPreviewTo:_trimStart];
	[self setPlaying:YES];
}

- (void)viewDidAppear:(BOOL)animated {
	[super viewDidAppear:animated];
	[self startLoopObserver];
	[self setPlaying:YES];
}

- (void)appActive { if (_playing) [_player play]; }

- (void)dealloc {
	if (_timeObserver) [_player removeTimeObserver:_timeObserver];
	[[NSNotificationCenter defaultCenter] removeObserver:self];
}

#pragma mark - Trim bar

- (void)setupTrimBar {
	_trimBar = [UIView new];
	_trimBar.backgroundColor = [UIColor colorWithWhite:1.0 alpha:0.08];
	_trimBar.layer.cornerRadius = 12;
	_trimBar.layer.cornerCurve = kCACornerCurveContinuous;
	_trimBar.clipsToBounds = YES;
	[self.view addSubview:_trimBar];

	_stripScroll = [UIScrollView new];
	_stripScroll.delegate = self;
	_stripScroll.showsHorizontalScrollIndicator = NO;
	_stripScroll.showsVerticalScrollIndicator = NO;
	_stripScroll.alwaysBounceHorizontal = YES;
	_stripScroll.decelerationRate = UIScrollViewDecelerationRateFast;
	_stripScroll.clipsToBounds = YES;
	if (@available(iOS 11.0, *)) _stripScroll.contentInsetAdjustmentBehavior = UIScrollViewContentInsetAdjustmentNever;
	[_trimBar addSubview:_stripScroll];

	_stripContent = [UIView new];
	[_stripScroll addSubview:_stripContent];

	_dimLeft = [self makeDimView];
	_dimRight = [self makeDimView];

	_selBorder = [UIView new];
	_selBorder.layer.borderColor = UIColor.systemBlueColor.CGColor;
	_selBorder.layer.borderWidth = 2.5;
	_selBorder.layer.cornerRadius = 6;
	_selBorder.layer.cornerCurve = kCACornerCurveContinuous;
	[_selBorder addGestureRecognizer:[[UIPanGestureRecognizer alloc] initWithTarget:self action:@selector(windowPan:)]];
	[_trimBar addSubview:_selBorder];

	_playhead = [UIView new];
	_playhead.backgroundColor = UIColor.whiteColor;
	_playhead.layer.cornerRadius = 1.25;
	_playhead.userInteractionEnabled = NO;
	_playhead.hidden = YES;
	[_trimBar addSubview:_playhead];

	_leftHandle = [self makeHandle:YES];
	_rightHandle = [self makeHandle:NO];
}

- (UIView *)makeDimView {
	UIView *v = [UIView new];
	v.backgroundColor = [UIColor colorWithWhite:0 alpha:0.5];
	v.userInteractionEnabled = NO;
	[_trimBar addSubview:v];
	return v;
}

- (UIView *)makeHandle:(BOOL)left {
	UIView *h = [UIView new];
	h.backgroundColor = UIColor.systemBlueColor;
	h.layer.cornerRadius = 6;
	h.layer.cornerCurve = kCACornerCurveContinuous;
	h.layer.maskedCorners = left ? (kCALayerMinXMinYCorner | kCALayerMinXMaxYCorner) : (kCALayerMaxXMinYCorner | kCALayerMaxXMaxYCorner);

	for (NSInteger i = 0; i < 2; i++) {
		UIView *line = [[UIView alloc] init];
		line.tag = 700 + i;
		line.backgroundColor = [UIColor colorWithWhite:1.0 alpha:0.85];
		line.layer.cornerRadius = 0.75;
		[h addSubview:line];
	}

	[h addGestureRecognizer:[[UIPanGestureRecognizer alloc] initWithTarget:self action:@selector(handlePan:)]];
	[_trimBar addSubview:h];
	return h;
}

- (void)layoutHandleGrips:(UIView *)h {
	CGFloat w = h.bounds.size.width, hgt = h.bounds.size.height;
	for (NSInteger i = 0; i < 2; i++) {
		[h viewWithTag:700 + i].frame = CGRectMake(w * 0.5 - 3.5 + i * 4.0, hgt * 0.5 - 8.0, 1.5, 16.0);
	}
}

- (void)configureStrip {
	CGFloat Wv = _stripVisibleW, H = _trimBar.bounds.size.height;
	if (Wv < 1 || H < 1 || _duration < 0.01) return;

	CGFloat factor = MAX(1.0, _duration / kSCIStripWindowSecs);
	CGFloat Wc = Wv * factor;
	_maxSelPx = MIN(Wv, (CGFloat)(self.maxDuration * Wc / _duration));

	_selLeftX = 0;
	_selRightX = _maxSelPx;

	_stripScroll.frame = CGRectMake(_stripInset, 0, Wv, H);
	_stripContent.frame = CGRectMake(0, 0, Wc, H);
	_stripScroll.contentSize = CGSizeMake(Wc, H);
	_stripScroll.contentOffset = CGPointZero;

	[self reloadThumbsForContentWidth:Wc height:H];
	[self layoutSelection];
}

- (void)reloadThumbsForContentWidth:(CGFloat)Wc height:(CGFloat)h {
	if (Wc < 1 || h < 1) return;
	for (UIView *v in _stripContent.subviews.copy) [v removeFromSuperview];

	CGFloat cellW = h;
	NSInteger count = MAX(1, MIN(400, (NSInteger)ceil(Wc / cellW)));
	cellW = Wc / count;

	for (NSInteger i = 0; i < count; i++) {
		UIImageView *iv = [[UIImageView alloc] initWithFrame:CGRectMake(i * cellW, 0, cellW + 0.5, h)];
		iv.contentMode = UIViewContentModeScaleAspectFill;
		iv.clipsToBounds = YES;
		iv.backgroundColor = [UIColor colorWithWhite:1.0 alpha:0.05];
		iv.tag = 5000 + i;
		[_stripContent addSubview:iv];
	}

	AVAssetImageGenerator *gen = [AVAssetImageGenerator assetImageGeneratorWithAsset:_asset];
	gen.appliesPreferredTrackTransform = YES;
	gen.requestedTimeToleranceBefore = kCMTimePositiveInfinity;
	gen.requestedTimeToleranceAfter = kCMTimePositiveInfinity;
	gen.maximumSize = CGSizeMake(h * 2, h * 2);

	NSMutableArray<NSValue *> *times = [NSMutableArray array];
	for (NSInteger i = 0; i < count; i++) {
		[times addObject:[NSValue valueWithCMTime:CMTimeMakeWithSeconds(_duration * ((i + 0.5) / count), 600)]];
	}

	[gen generateCGImagesAsynchronouslyForTimes:times completionHandler:^(CMTime requestedTime, CGImageRef image, __unused CMTime actualTime, AVAssetImageGeneratorResult result, __unused NSError *error) {
		if (result != AVAssetImageGeneratorSucceeded || !image) return;
		CGImageRef retained = CGImageRetain(image);
		NSInteger idx = (NSInteger)round(CMTimeGetSeconds(requestedTime) / _duration * count - 0.5);
		dispatch_async(dispatch_get_main_queue(), ^{
			if (idx < 0 || idx >= count) { CGImageRelease(retained); return; }
			((UIImageView *)[_stripContent viewWithTag:5000 + idx]).image = [UIImage imageWithCGImage:retained];
			CGImageRelease(retained);
		});
	}];
}

- (NSTimeInterval)timeForFrameX:(CGFloat)fx {
	CGFloat Wc = _stripScroll.contentSize.width;
	if (Wc < 1) return 0;
	CGFloat cx = fx + _stripScroll.contentOffset.x;
	return MAX(0, MIN(_duration, _duration * cx / Wc));
}

- (CGFloat)frameXForTime:(NSTimeInterval)t {
	CGFloat Wc = _stripScroll.contentSize.width;
	if (_duration < 0.001) return 0;
	return (CGFloat)(t / _duration) * Wc - _stripScroll.contentOffset.x;
}

- (void)syncTrimTimes {
	_trimStart = [self timeForFrameX:_selLeftX];
	_trimEnd = [self timeForFrameX:_selRightX];
}

- (void)scrollStripBy:(CGFloat)d {
	CGFloat maxOff = MAX(0, _stripScroll.contentSize.width - _stripVisibleW);
	_stripScroll.contentOffset = CGPointMake(MAX(0, MIN(_stripScroll.contentOffset.x + d, maxOff)), 0);
}

- (void)moveWindowByFrameDelta:(CGFloat)d {
	CGFloat width = _selRightX - _selLeftX;
	CGFloat newLeft = _selLeftX + d;
	CGFloat maxLeft = _stripVisibleW - width;
	CGFloat scrollDelta = 0;
	if (newLeft < 0) { scrollDelta = newLeft; newLeft = 0; }
	else if (newLeft > maxLeft) { scrollDelta = newLeft - maxLeft; newLeft = maxLeft; }
	_selLeftX = newLeft;
	_selRightX = newLeft + width;
	if (scrollDelta != 0) [self scrollStripBy:scrollDelta];
}

- (void)windowPan:(UIPanGestureRecognizer *)pan {
	if (pan.state == UIGestureRecognizerStateBegan) [self setPlaying:NO];
	if (_stripVisibleW < 1) return;

	CGFloat dx = [pan translationInView:self.view].x;
	[pan setTranslation:CGPointZero inView:self.view];

	[self moveWindowByFrameDelta:dx];
	[self layoutSelection];
	[self seekPreviewTo:_trimStart];
}

- (void)layoutSelection {
	CGFloat Lx = _stripInset, H = _trimBar.bounds.size.height;
	CGFloat leftEdge = Lx + _selLeftX;
	CGFloat rightEdge = Lx + _selRightX;

	_dimLeft.frame = CGRectMake(Lx, 0, MAX(0, _selLeftX), H);
	_dimRight.frame = CGRectMake(rightEdge, 0, MAX(0, _stripVisibleW - _selRightX), H);
	_selBorder.frame = CGRectMake(leftEdge, 0, MAX(0, rightEdge - leftEdge), H);
	_leftHandle.frame = CGRectMake(leftEdge - _stripInset, 0, _stripInset, H);
	_rightHandle.frame = CGRectMake(rightEdge, 0, _stripInset, H);
	[self layoutHandleGrips:_leftHandle];
	[self layoutHandleGrips:_rightHandle];

	[_trimBar bringSubviewToFront:_selBorder];
	[_trimBar bringSubviewToFront:_playhead];
	[_trimBar bringSubviewToFront:_leftHandle];
	[_trimBar bringSubviewToFront:_rightHandle];

	[self syncTrimTimes];
	[self movePlayheadTo:_playT];
	[self updateInfoLabel];
}

- (void)handlePan:(UIPanGestureRecognizer *)pan {
	if (pan.state == UIGestureRecognizerStateBegan) [self setPlaying:NO];
	if (_stripVisibleW < 1) return;

	CGFloat dx = [pan translationInView:self.view].x;
	[pan setTranslation:CGPointZero inView:self.view];

	CGFloat Wc = _stripScroll.contentSize.width;
	CGFloat minDist = (_duration > 0.001) ? (CGFloat)(kSCIMinTrim * Wc / _duration) : 20.0;

	if (pan.view == _leftHandle) {
		CGFloat lo = MAX(0, _selRightX - _maxSelPx), hi = _selRightX - minDist;
		CGFloat newLeft = MAX(lo, MIN(_selLeftX + dx, hi));
		CGFloat leftover = (_selLeftX + dx) - newLeft;
		_selLeftX = newLeft;
		if (leftover != 0) [self moveWindowByFrameDelta:leftover];
		[self layoutSelection];
		[self seekPreviewTo:[self timeForFrameX:_selLeftX]];
	} else {
		CGFloat lo = _selLeftX + minDist, hi = MIN(_stripVisibleW, _selLeftX + _maxSelPx);
		CGFloat newRight = MAX(lo, MIN(_selRightX + dx, hi));
		CGFloat leftover = (_selRightX + dx) - newRight;
		_selRightX = newRight;
		if (leftover != 0) [self moveWindowByFrameDelta:leftover];
		[self layoutSelection];
		[self seekPreviewTo:[self timeForFrameX:_selRightX]];
	}
}

- (void)seekPreviewTo:(NSTimeInterval)t {
	[_player seekToTime:CMTimeMakeWithSeconds(t, 600) toleranceBefore:CMTimeMakeWithSeconds(0.05, 600) toleranceAfter:CMTimeMakeWithSeconds(0.05, 600)];
}

- (void)startLoopObserver {
	if (_timeObserver) return;
	__weak typeof(self) weakSelf = self;
	_timeObserver = [_player addPeriodicTimeObserverForInterval:CMTimeMake(1, 30) queue:dispatch_get_main_queue() usingBlock:^(CMTime time) {
		typeof(self) s = weakSelf;
		if (!s) return;
		NSTimeInterval now = CMTimeGetSeconds(time);
		if (now >= s->_trimEnd - 0.03 || now < s->_trimStart - 0.1) {
			[s seekPreviewTo:s->_trimStart];
			if (s->_playing) [s->_player play];
			return;
		}
		[s movePlayheadTo:now];
	}];
}

- (void)movePlayheadTo:(NSTimeInterval)t {
	_playT = t;
	if (!_stripConfigured || _duration < 0.01) return;
	CGFloat fx = [self frameXForTime:t];
	BOOL visible = fx >= _selLeftX - 0.5 && fx <= _selRightX + 0.5;
	_playhead.hidden = !visible;
	if (visible) _playhead.frame = CGRectMake(_stripInset + fx - 1.25, 3, 2.5, _trimBar.bounds.size.height - 6);
}

#pragma mark - Strip scroll

- (void)scrollViewWillBeginDragging:(UIScrollView *)scrollView {
	if (scrollView == _stripScroll) [self setPlaying:NO];
}

- (void)scrollViewDidScroll:(UIScrollView *)scrollView {
	if (scrollView != _stripScroll || !_stripConfigured) return;
	[self syncTrimTimes];
	[self updateInfoLabel];
	if (scrollView.tracking || scrollView.decelerating) [self seekPreviewTo:_trimStart];
	[self movePlayheadTo:_trimStart];
}

- (NSString *)timeText:(NSTimeInterval)seconds {
	if (!isfinite(seconds) || seconds < 0) seconds = 0;
	NSInteger total = (NSInteger)floor(seconds);
	return [NSString stringWithFormat:@"%ld:%02ld", (long)(total / 60), (long)(total % 60)];
}

- (NSString *)durText:(NSTimeInterval)seconds {
	if (!isfinite(seconds) || seconds < 0) seconds = 0;
	if (seconds < 60.0) return [NSString stringWithFormat:@"%.1fs", seconds];
	NSInteger m = (NSInteger)(seconds / 60.0);
	NSInteger s = (NSInteger)round(seconds - m * 60.0);
	return [NSString stringWithFormat:@"%ldm %lds", (long)m, (long)s];
}

- (void)updateInfoLabel {
	NSString *range = [NSString stringWithFormat:@"%@ — %@  (%@)", [self timeText:_trimStart], [self timeText:_trimEnd], [self durText:_trimEnd - _trimStart]];
	NSString *total = [NSString stringWithFormat:@"    %@", [NSString stringWithFormat:SCILocalized(@"Total: %@"), [self timeText:_duration]]];

	NSMutableAttributedString *s = [[NSMutableAttributedString alloc] initWithString:range attributes:@{NSForegroundColorAttributeName: UIColor.whiteColor}];
	[s appendAttributedString:[[NSAttributedString alloc] initWithString:total attributes:@{NSForegroundColorAttributeName: [UIColor colorWithWhite:1.0 alpha:0.4]}]];
	_infoLabel.attributedText = s;
}

#pragma mark - Layout

- (void)viewDidLayoutSubviews {
	[super viewDidLayoutSubviews];

	CGSize size = self.view.bounds.size;
	if (size.width <= 0 || size.height <= 0) return;

	UIEdgeInsets safe = self.view.safeAreaInsets;
	CGFloat m = 20.0;
	CGFloat leftX = safe.left + m;
	CGFloat cw = size.width - safe.left - safe.right - m * 2.0;
	CGFloat trimH = kSCITrimBarH;

	_cancelButton.frame = CGRectMake(safe.left + 14, safe.top + 10, 38, 38);

	_useButton.frame = CGRectMake(leftX, size.height - safe.bottom - 66, cw, 52);

	CGFloat playD = 58;
	_playButton.frame = CGRectMake((size.width - playD) * 0.5, CGRectGetMinY(_useButton.frame) - 74, playD, playD);
	_restartButton.frame = CGRectMake(CGRectGetMaxX(_playButton.frame) + 16, CGRectGetMidY(_playButton.frame) - 21, 42, 42);

	_trimBar.frame = CGRectMake(leftX, CGRectGetMinY(_playButton.frame) - 18 - trimH, cw, trimH);
	_stripVisibleW = cw - _stripInset * 2.0;
	_infoLabel.frame = CGRectMake(leftX, CGRectGetMinY(_trimBar.frame) - 24, cw, 20);

	CGFloat imageTop = safe.top + 56.0;
	CGFloat imageH = CGRectGetMinY(_infoLabel.frame) - 14.0 - imageTop;
	if (imageH < 1) imageH = 1;

	_scroll.frame = CGRectMake(0, imageTop, size.width, imageH);
	_overlay.frame = _scroll.frame;

	CGFloat availW = size.width - 56.0;
	CGFloat availH = imageH - 56.0;
	CGFloat ar = (_aspectW > 0 && _aspectH > 0) ? (_aspectW / _aspectH) : 1.0;
	_cropW = availW;
	_cropH = _cropW / ar;
	if (_cropH > availH) { _cropH = availH; _cropW = _cropH * ar; }
	CGRect crop = CGRectMake((size.width - _cropW) * 0.5, (imageH - _cropH) * 0.5, _cropW, _cropH);

	// Square (Instants) keeps the squircle; non-square (chat bg) uses a plain rounded rect.
	BOOL squircle = (_aspectW <= 0 || _aspectH <= 0 || fabs(_aspectW / _aspectH - 1.0) < 0.02);
	UIBezierPath *hole = squircle ? SCIInstantsSquirclePathInRect(crop) : [UIBezierPath bezierPathWithRoundedRect:crop cornerRadius:14];
	UIBezierPath *dim = [UIBezierPath bezierPathWithRect:_overlay.bounds];
	[dim appendPath:hole];
	dim.usesEvenOddFillRule = YES;

	_dimLayer.frame = _overlay.bounds;
	_dimLayer.path = dim.CGPath;
	_borderLayer.frame = _overlay.bounds;
	_borderLayer.path = hole.CGPath;

	if (_configured) return;
	_configured = YES;

	_contentView.frame = (CGRect){ CGPointZero, _orientedSize };
	_playerLayer.frame = _contentView.bounds;
	_scroll.contentSize = _orientedSize;

	CGFloat minZoom = MAX(_cropW / _orientedSize.width, _cropH / _orientedSize.height);
	_scroll.minimumZoomScale = minZoom;
	_scroll.maximumZoomScale = MAX(minZoom * 4.0, 1.0);
	_scroll.zoomScale = minZoom;
	_scroll.contentInset = UIEdgeInsetsMake(crop.origin.y, crop.origin.x, crop.origin.y, crop.origin.x);
	_scroll.contentOffset = CGPointMake((_orientedSize.width * minZoom - size.width) * 0.5, (_orientedSize.height * minZoom - imageH) * 0.5);

	_stripConfigured = YES;
	[self configureStrip];
}

- (UIView *)viewForZoomingInScrollView:(UIScrollView *)scrollView { return scrollView == _scroll ? _contentView : nil; }

- (void)scrollViewDidZoom:(UIScrollView *)scrollView {
	if (scrollView != _scroll) return;
	[CATransaction begin];
	[CATransaction setDisableActions:YES];
	_playerLayer.frame = _contentView.bounds;
	[CATransaction commit];
}

#pragma mark - Actions

- (void)cancelTapped {
	[_player pause];
	[self dismissViewControllerAnimated:YES completion:nil];
}

// Crop rect in oriented-video pixel coordinates.
- (CGRect)cropRectInVideo {
	CGFloat zoom = _scroll.zoomScale;
	CGFloat x = ((_scroll.bounds.size.width - _cropW) * 0.5 + _scroll.contentOffset.x) / zoom;
	CGFloat y = ((_scroll.bounds.size.height - _cropH) * 0.5 + _scroll.contentOffset.y) / zoom;
	CGFloat w = _cropW / zoom;
	CGFloat h = _cropH / zoom;

	x = MAX(0, MIN(x, _orientedSize.width - w));
	y = MAX(0, MIN(y, _orientedSize.height - h));
	return CGRectMake(x, y, w, h);
}

- (void)useTapped {
	if (_exporting) return;
	_exporting = YES;
	_useButton.enabled = NO;
	[_player pause];

	CGRect cropRect = [self cropRectInVideo];

	CGAffineTransform pt = _track.preferredTransform;
	CGRect oriented = CGRectApplyAffineTransform(CGRectMake(0, 0, _track.naturalSize.width, _track.naturalSize.height), pt);
	CGAffineTransform normalize = CGAffineTransformMakeTranslation(-oriented.origin.x, -oriented.origin.y);
	CGAffineTransform crop = CGAffineTransformMakeTranslation(-cropRect.origin.x, -cropRect.origin.y);
	CGAffineTransform final = CGAffineTransformConcat(CGAffineTransformConcat(pt, normalize), crop);

	int32_t outW = (int32_t)floor(cropRect.size.width);
	int32_t outH = (int32_t)floor(cropRect.size.height);
	if (outW % 2) outW -= 1;
	if (outH % 2) outH -= 1;
	if (outW < 2 || outH < 2) { _exporting = NO; return; }

	AVMutableVideoCompositionLayerInstruction *layer = [AVMutableVideoCompositionLayerInstruction videoCompositionLayerInstructionWithAssetTrack:_track];
	[layer setTransform:final atTime:kCMTimeZero];

	CMTime start = CMTimeMakeWithSeconds(_trimStart, 600);
	CMTime end = CMTimeMakeWithSeconds(_trimEnd, 600);
	CMTimeRange range = CMTimeRangeFromTimeToTime(start, end);

	// Instruction lives in the SOURCE timeline; session.timeRange does the trim.
	AVMutableVideoCompositionInstruction *inst = [AVMutableVideoCompositionInstruction videoCompositionInstruction];
	inst.timeRange = CMTimeRangeMake(kCMTimeZero, _asset.duration);
	inst.layerInstructions = @[layer];

	AVMutableVideoComposition *comp = [AVMutableVideoComposition videoComposition];
	comp.instructions = @[inst];
	comp.renderSize = CGSizeMake(outW, outH);
	CGFloat fps = _track.nominalFrameRate > 1 ? _track.nominalFrameRate : 30;
	comp.frameDuration = CMTimeMake(1, (int32_t)round(fps));

	NSURL *out = [SCITempFiles claimWithExt:@"mp4" ttl:900 tag:@"video-edit"];
	AVAssetExportSession *session = [[AVAssetExportSession alloc] initWithAsset:_asset presetName:AVAssetExportPresetHighestQuality];
	session.outputURL = out;
	session.outputFileType = AVFileTypeMPEG4;
	session.videoComposition = comp;
	session.timeRange = range;

	void (^done)(NSURL *) = self.onDone;
	[session exportAsynchronouslyWithCompletionHandler:^{
		dispatch_async(dispatch_get_main_queue(), ^{
			BOOL ok = session.status == AVAssetExportSessionStatusCompleted;
			if (!ok) { NSLog(@"[SCInsta][VideoEditor] export failed %ld %@", (long)session.status, session.error); [SCITempFiles releaseURL:out]; }
			[self dismissViewControllerAnimated:YES completion:^{
				if (ok && done) done(out);
			}];
		});
	}];
}

@end

@implementation SCIVideoEditor

+ (void)presentForVideoURL:(NSURL *)url from:(UIViewController *)presenter maxDuration:(NSTimeInterval)maxDuration onDone:(void (^)(NSURL *))onDone {
	[self presentForVideoURL:url from:presenter maxDuration:maxDuration aspectW:1.0 aspectH:1.0 onDone:onDone];
}

+ (void)presentForVideoURL:(NSURL *)url from:(UIViewController *)presenter maxDuration:(NSTimeInterval)maxDuration aspectW:(CGFloat)aspectW aspectH:(CGFloat)aspectH onDone:(void (^)(NSURL *))onDone {
	if (!url) return;
	SCIVideoEditorController *vc = [SCIVideoEditorController new];
	vc.assetURL = url;
	vc.maxDuration = maxDuration > 0 ? maxDuration : 7.0;
	vc.aspectW = aspectW;
	vc.aspectH = aspectH;
	vc.onDone = onDone;
	[presenter presentViewController:vc animated:YES completion:nil];
}

@end
