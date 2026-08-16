#import "RYGStoryMediaCell.h"
#import <AVFoundation/AVFoundation.h>

@interface RYGStoryMediaCell () <UIScrollViewDelegate>
@property (nonatomic, strong) UIScrollView *scrollView;
@property (nonatomic, strong) UIImageView *imageView;
@property (nonatomic, strong) AVPlayer *player;
@property (nonatomic, strong) AVPlayerLayer *playerLayer;
@property (nonatomic, strong) id loopObserver;
@property (nonatomic, strong) id timeObserver;
@property (nonatomic, strong) UISlider *scrubber;
@property (nonatomic, strong) UIImageView *playIcon;
@property (nonatomic, assign) BOOL isVideo;
@property (nonatomic, assign) BOOL seeking;
@property (nonatomic, assign) BOOL resumeAfterSeek;
@property (nonatomic, copy) NSString *mediaPath;
@end

@implementation RYGStoryMediaCell

- (instancetype)initWithFrame:(CGRect)frame {
	if (!(self = [super initWithFrame:frame])) return nil;
	self.backgroundColor = UIColor.blackColor;

	_scrollView = [[UIScrollView alloc] initWithFrame:self.contentView.bounds];
	_scrollView.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
	_scrollView.delegate = self;
	_scrollView.minimumZoomScale = 1.0;
	_scrollView.maximumZoomScale = 4.0;
	_scrollView.showsHorizontalScrollIndicator = NO;
	_scrollView.showsVerticalScrollIndicator = NO;
	[self.contentView addSubview:_scrollView];

	_imageView = [[UIImageView alloc] initWithFrame:_scrollView.bounds];
	_imageView.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
	_imageView.contentMode = UIViewContentModeScaleAspectFit;
	[_scrollView addSubview:_imageView];

	_playIcon = [[UIImageView alloc] initWithImage:[[UIImage systemImageNamed:@"play.fill"] imageWithConfiguration:[UIImageSymbolConfiguration configurationWithPointSize:44 weight:UIImageSymbolWeightSemibold]]];
	_playIcon.tintColor = [UIColor.whiteColor colorWithAlphaComponent:0.9];
	_playIcon.translatesAutoresizingMaskIntoConstraints = NO;
	_playIcon.hidden = YES;
	_playIcon.layer.shadowColor = UIColor.blackColor.CGColor;
	_playIcon.layer.shadowOpacity = 0.4;
	_playIcon.layer.shadowRadius = 6;
	_playIcon.layer.shadowOffset = CGSizeZero;
	[self.contentView addSubview:_playIcon];

	_scrubber = [UISlider new];
	_scrubber.translatesAutoresizingMaskIntoConstraints = NO;
	_scrubber.minimumValue = 0;
	_scrubber.maximumValue = 1;
	_scrubber.minimumTrackTintColor = UIColor.whiteColor;
	_scrubber.maximumTrackTintColor = [UIColor.whiteColor colorWithAlphaComponent:0.3];
	_scrubber.hidden = YES;
	[_scrubber setThumbImage:[self scrubberThumb] forState:UIControlStateNormal];
	[_scrubber addTarget:self action:@selector(scrubBegan) forControlEvents:UIControlEventTouchDown];
	[_scrubber addTarget:self action:@selector(scrubChanged) forControlEvents:UIControlEventValueChanged];
	[_scrubber addTarget:self action:@selector(scrubEnded) forControlEvents:UIControlEventTouchUpInside | UIControlEventTouchUpOutside | UIControlEventTouchCancel];
	[self.contentView addSubview:_scrubber];

	[NSLayoutConstraint activateConstraints:@[
		[_playIcon.centerXAnchor constraintEqualToAnchor:self.contentView.centerXAnchor],
		[_playIcon.centerYAnchor constraintEqualToAnchor:self.contentView.centerYAnchor],
		[_scrubber.leadingAnchor constraintEqualToAnchor:self.contentView.leadingAnchor constant:14],
		[_scrubber.trailingAnchor constraintEqualToAnchor:self.contentView.trailingAnchor constant:-14],
		[_scrubber.bottomAnchor constraintEqualToAnchor:self.contentView.bottomAnchor constant:-10],
	]];

	UITapGestureRecognizer *doubleTap = [[UITapGestureRecognizer alloc] initWithTarget:self action:@selector(handleDoubleTap:)];
	doubleTap.numberOfTapsRequired = 2;
	[self.contentView addGestureRecognizer:doubleTap];

	UITapGestureRecognizer *singleTap = [[UITapGestureRecognizer alloc] initWithTarget:self action:@selector(handleSingleTap:)];
	[singleTap requireGestureRecognizerToFail:doubleTap];
	[self.contentView addGestureRecognizer:singleTap];
	return self;
}

- (UIImage *)scrubberThumb {
	CGFloat d = 12;
	UIGraphicsImageRenderer *r = [[UIGraphicsImageRenderer alloc] initWithSize:CGSizeMake(d, d)];
	return [r imageWithActions:^(UIGraphicsImageRendererContext *ctx) {
		[UIColor.whiteColor setFill];
		[[UIBezierPath bezierPathWithOvalInRect:CGRectMake(0, 0, d, d)] fill];
	}];
}

- (UIView *)viewForZoomingInScrollView:(UIScrollView *)scrollView { return self.imageView; }

- (void)handleDoubleTap:(UITapGestureRecognizer *)gr {
	if (self.isVideo) return;
	[self.scrollView setZoomScale:self.scrollView.zoomScale > 1.0 ? 1.0 : 2.5 animated:YES];
}

- (void)handleSingleTap:(UITapGestureRecognizer *)gr {
	if (!self.isVideo) return;
	if (self.player.rate > 0) { [self.player pause]; self.playIcon.hidden = NO; }
	else { [self.player play]; self.playIcon.hidden = YES; }
}

#pragma mark - Scrubbing

- (void)scrubBegan {
	self.seeking = YES;
	self.resumeAfterSeek = self.player.rate > 0;
	[self.player pause];
}

- (void)scrubChanged {
	CMTime dur = self.player.currentItem.duration;
	if (CMTIME_IS_INDEFINITE(dur) || CMTIME_IS_INVALID(dur)) return;
	Float64 t = CMTimeGetSeconds(dur) * self.scrubber.value;
	[self.player seekToTime:CMTimeMakeWithSeconds(t, 600)];
}

- (void)scrubEnded {
	self.seeking = NO;
	if (self.resumeAfterSeek) { [self.player play]; self.playIcon.hidden = YES; }
	else self.playIcon.hidden = NO;
}

#pragma mark - Media

- (void)prepareForReuse {
	[super prepareForReuse];
	[self teardownVideo];
	_imageView.image = nil;
	_scrollView.zoomScale = 1.0;
	_scrubber.hidden = YES;
	_playIcon.hidden = YES;
}

- (void)teardownVideo {
	if (_loopObserver) { [NSNotificationCenter.defaultCenter removeObserver:_loopObserver]; _loopObserver = nil; }
	if (_timeObserver && _player) { [_player removeTimeObserver:_timeObserver]; _timeObserver = nil; }
	[_player pause];
	[_playerLayer removeFromSuperlayer];
	_playerLayer = nil;
	_player = nil;
}

- (void)configureWithMediaPath:(NSString *)mediaPath isVideo:(BOOL)isVideo {
	self.mediaPath = mediaPath;
	self.isVideo = isVideo;
	[self teardownVideo];
	_scrubber.hidden = !isVideo;
	_playIcon.hidden = YES;

	if (!mediaPath) return;

	if (isVideo) {
		_imageView.hidden = YES;
		NSURL *url = [NSURL fileURLWithPath:mediaPath];
		_player = [AVPlayer playerWithURL:url];
		_player.muted = NO;
		_playerLayer = [AVPlayerLayer playerLayerWithPlayer:_player];
		_playerLayer.videoGravity = AVLayerVideoGravityResizeAspect;
		_playerLayer.frame = self.contentView.bounds;
		[self.contentView.layer insertSublayer:_playerLayer atIndex:0];

		__weak typeof(self) weakSelf = self;
		_loopObserver = [NSNotificationCenter.defaultCenter addObserverForName:AVPlayerItemDidPlayToEndTimeNotification object:_player.currentItem queue:NSOperationQueue.mainQueue usingBlock:^(NSNotification *n) {
			[weakSelf.player seekToTime:kCMTimeZero];
			[weakSelf.player play];
		}];
		_timeObserver = [_player addPeriodicTimeObserverForInterval:CMTimeMake(1, 20) queue:dispatch_get_main_queue() usingBlock:^(CMTime time) {
			typeof(self) s = weakSelf;
			if (!s || s.seeking) return;
			CMTime dur = s.player.currentItem.duration;
			if (CMTIME_IS_INDEFINITE(dur) || CMTIME_IS_INVALID(dur)) return;
			Float64 d = CMTimeGetSeconds(dur);
			if (d > 0) s.scrubber.value = CMTimeGetSeconds(time) / d;
		}];
	} else {
		_imageView.hidden = NO;
		dispatch_async(dispatch_get_global_queue(QOS_CLASS_USER_INITIATED, 0), ^{
			UIImage *img = [UIImage imageWithContentsOfFile:mediaPath];
			dispatch_async(dispatch_get_main_queue(), ^{
				if ([self.mediaPath isEqualToString:mediaPath]) self.imageView.image = img;
			});
		});
	}
}

- (void)layoutSubviews {
	[super layoutSubviews];
	_playerLayer.frame = self.contentView.bounds;
}

- (void)setActive:(BOOL)active {
	if (!self.isVideo) return;
	if (active) { [self.player seekToTime:kCMTimeZero]; [self.player play]; self.playIcon.hidden = YES; }
	else { [self.player pause]; }
}

- (BOOL)isZoomed { return self.scrollView.zoomScale > 1.01; }

- (void)dealloc { [self teardownVideo]; }

@end
