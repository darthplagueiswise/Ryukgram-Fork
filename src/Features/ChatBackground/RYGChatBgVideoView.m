#import "RYGChatBgVideoView.h"
#import <AVFoundation/AVFoundation.h>

@interface RYGChatBgVideoView ()
@property (nonatomic, strong) AVPlayer *player;
@property (nonatomic, strong) AVPlayerItem *item;
@property (nonatomic, strong) UIVisualEffectView *blurView;
@property (nonatomic, strong) UIViewPropertyAnimator *blurAnimator;
@property (nonatomic, strong) UIView *dimView;
@property (nonatomic) CGFloat blurRadius;
@property (nonatomic) BOOL observingLayer;
@end

static void *kRYGReadyCtx = &kRYGReadyCtx;

@implementation RYGChatBgVideoView

+ (Class)layerClass { return AVPlayerLayer.class; }

- (AVPlayerLayer *)playerLayer { return (AVPlayerLayer *)self.layer; }

- (BOOL)isReadyForDisplay { return self.playerLayer.readyForDisplay; }

- (instancetype)initWithFrame:(CGRect)frame {
	if ((self = [super initWithFrame:frame])) {
		self.userInteractionEnabled = NO;
		self.playerLayer.videoGravity = AVLayerVideoGravityResizeAspectFill;
		self.backgroundColor = UIColor.clearColor;

		_blurView = [[UIVisualEffectView alloc] initWithEffect:nil];
		_blurView.userInteractionEnabled = NO;
		_blurView.hidden = YES;
		[self addSubview:_blurView];

		_dimView = [UIView new];
		_dimView.backgroundColor = UIColor.blackColor;
		_dimView.userInteractionEnabled = NO;
		_dimView.hidden = YES;
		[self addSubview:_dimView];

		[NSNotificationCenter.defaultCenter addObserver:self selector:@selector(ryg_appPaused)
			name:UIApplicationDidEnterBackgroundNotification object:nil];
		[NSNotificationCenter.defaultCenter addObserver:self selector:@selector(ryg_appResumed)
			name:UIApplicationWillEnterForegroundNotification object:nil];
	}
	return self;
}

- (void)dealloc {
	[NSNotificationCenter.defaultCenter removeObserver:self];
	if (_observingLayer) {
		[self.playerLayer removeObserver:self forKeyPath:@"readyForDisplay" context:kRYGReadyCtx];
		_observingLayer = NO;
	}
	[_blurAnimator stopAnimation:YES];
	[_player pause];
	((AVPlayerLayer *)self.layer).player = nil;
}

- (void)layoutSubviews {
	[super layoutSubviews];
	_blurView.frame = self.bounds;
	_dimView.frame = self.bounds;
}

- (void)setBlurRadius:(CGFloat)blur dim:(CGFloat)dim {
	_dimView.hidden = dim <= 0.001;
	_dimView.alpha = dim;
	[self bringSubviewToFront:_blurView];
	[self bringSubviewToFront:_dimView];

	CGFloat frac = MAX(0.0, MIN(1.0, blur / 30.0));
	if (frac <= 0.001) {
		_blurView.hidden = YES;
		[_blurAnimator stopAnimation:YES];
		_blurAnimator = nil;
		_blurView.effect = nil;
		_blurRadius = 0;
		return;
	}

	_blurView.hidden = NO;
	if (!_blurAnimator) {
		__weak typeof(self) weak = self;
		_blurAnimator = [[UIViewPropertyAnimator alloc] initWithDuration:1.0 curve:UIViewAnimationCurveLinear animations:^{
			weak.blurView.effect = [UIBlurEffect effectWithStyle:UIBlurEffectStyleRegular];
		}];
		_blurAnimator.pausesOnCompletion = YES;
	}
	_blurAnimator.fractionComplete = frac;
	_blurRadius = blur;
}

- (void)setVideoURL:(NSURL *)videoURL {
	if ([videoURL.path isEqualToString:_videoURL.path]) {
		if (self.window) [self play];
		return;
	}
	_videoURL = [videoURL copy];
	[self teardownPlayer];
	if (self.window) [self play];
}

// Only alive while on-window, so leaving the chat frees the decoder + player.
- (void)loadPlayer {
	if (self.player || !_videoURL) return;

	AVURLAsset *asset = [AVURLAsset URLAssetWithURL:_videoURL options:nil];
	self.item = [AVPlayerItem playerItemWithAsset:asset];
	self.player = [AVPlayer playerWithPlayerItem:self.item];
	self.player.actionAtItemEnd = AVPlayerActionAtItemEndNone;
	self.player.muted = YES;
	if (@available(iOS 12.0, *)) self.player.preventsDisplaySleepDuringVideoPlayback = NO;
	self.playerLayer.player = self.player;

	if (!self.observingLayer) {
		[self.playerLayer addObserver:self forKeyPath:@"readyForDisplay" options:NSKeyValueObservingOptionNew context:kRYGReadyCtx];
		self.observingLayer = YES;
	}

	[NSNotificationCenter.defaultCenter addObserver:self selector:@selector(ryg_loop:)
		name:AVPlayerItemDidPlayToEndTimeNotification object:self.item];
}

- (void)observeValueForKeyPath:(NSString *)keyPath ofObject:(id)object change:(NSDictionary *)change context:(void *)context {
	if (context != kRYGReadyCtx) {
		[super observeValueForKeyPath:keyPath ofObject:object change:change context:context];
		return;
	}
	BOOL ready = self.playerLayer.readyForDisplay;
	if (self.onReadyForDisplayChanged) self.onReadyForDisplayChanged(ready);
}

- (void)teardownPlayer {
	if (self.observingLayer) {
		[self.playerLayer removeObserver:self forKeyPath:@"readyForDisplay" context:kRYGReadyCtx];
		self.observingLayer = NO;
	}
	if (self.item)
		[NSNotificationCenter.defaultCenter removeObserver:self name:AVPlayerItemDidPlayToEndTimeNotification object:self.item];
	[self.player pause];
	self.playerLayer.player = nil;
	self.player = nil;
	self.item = nil;
}

- (void)ryg_loop:(NSNotification *)note {
	[self.player seekToTime:kCMTimeZero];
	if (self.window) [self.player play];
}

- (void)play {
	if (!self.window || !_videoURL) return;
	[self loadPlayer];
	self.player.muted = YES;
	[self.player play];
}

- (void)pause { [self.player pause]; }

- (void)ryg_appPaused { [self teardownPlayer]; }
- (void)ryg_appResumed { [self play]; }

- (void)didMoveToWindow {
	[super didMoveToWindow];
	if (self.window) [self play]; else [self teardownPlayer];
}

@end
