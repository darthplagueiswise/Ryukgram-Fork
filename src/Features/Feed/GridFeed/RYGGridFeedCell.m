#import "RYGGridFeedCell.h"
#import "RYGGridFeedOverlayView.h"
#import "../../../RYGImageCache.h"

@interface RYGGridFeedCell ()
@property (nonatomic, strong) UIImageView *imageView;
@property (nonatomic, strong) RYGGridFeedOverlayView *overlay;
@property (nonatomic, strong) CAGradientLayer *shimmer;
@property (nonatomic, copy) NSString *loadingCode;
@end

@implementation RYGGridFeedCell

- (instancetype)initWithFrame:(CGRect)frame {
	if (!(self = [super initWithFrame:frame])) return self;
	self.contentView.backgroundColor = [UIColor secondarySystemBackgroundColor];
	self.contentView.clipsToBounds = YES;

	_imageView = [[UIImageView alloc] initWithFrame:self.contentView.bounds];
	_imageView.contentMode = UIViewContentModeScaleAspectFill;
	_imageView.clipsToBounds = YES;
	_imageView.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
	[self.contentView addSubview:_imageView];

	_overlay = [[RYGGridFeedOverlayView alloc] initWithFrame:self.contentView.bounds];
	_overlay.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
	[self.contentView addSubview:_overlay];
	return self;
}

- (void)configureWithPost:(RYGGridFeedPost *)post {
	self.loadingCode = post.pk.length ? post.pk : post.code;
	self.imageView.image = nil;
	self.imageView.alpha = 0;
	self.overlay.avatarImage = nil;
	[self.overlay configureWithPost:post];
	[self startShimmer];

	NSString *code = self.loadingCode;
	if (post.thumbURLString.length) {
		// Key by pk, not the URL: IG CDN thumb URLs expire, so a URL-keyed cache goes
		// black on a later boot. pk is stable. Downsampled to the tile size for smooth scroll.
		CGFloat px = MAX(220.0, self.contentView.bounds.size.width * UIScreen.mainScreen.scale);
		[RYGImageCache loadThumbnailFromURL:[NSURL URLWithString:post.thumbURLString] cacheKey:(post.pk.length ? post.pk : post.code) maxPixel:px completion:^(UIImage *img) {
			if (![self.loadingCode isEqualToString:code]) return;
			if (!img) return; // leave the shimmer skeleton up rather than a black tile
			[self stopShimmer];
			self.imageView.image = img;
			[UIView animateWithDuration:0.15 animations:^{ self.imageView.alpha = 1; }];
		}];
	}
	if (post.avatarURLString.length) {
		[RYGImageCache loadImageFromURL:[NSURL URLWithString:post.avatarURLString] completion:^(UIImage *image) {
			if (![self.loadingCode isEqualToString:code]) return;
			self.overlay.avatarImage = image;
		}];
	}
}

- (void)refreshOverlayWithPost:(RYGGridFeedPost *)post {
	[self.overlay configureWithPost:post];
}

- (void)configureSkeleton {
	self.loadingCode = nil;
	self.imageView.image = nil;
	self.imageView.alpha = 0;
	self.overlay.hidden = YES;
	self.contentView.backgroundColor = [UIColor secondarySystemBackgroundColor];
	[self startShimmer];
}

- (void)startShimmer {
	if (!self.shimmer) {
		self.shimmer = [CAGradientLayer layer];
		self.shimmer.startPoint = CGPointMake(0, 0.5);
		self.shimmer.endPoint = CGPointMake(1, 0.5);
		self.shimmer.colors = @[(id)[UIColor clearColor].CGColor,
		                        (id)[UIColor colorWithWhite:1 alpha:0.07].CGColor,
		                        (id)[UIColor clearColor].CGColor];
		self.shimmer.locations = @[@0, @0.5, @1];
	}
	self.shimmer.frame = self.contentView.bounds;
	[self.contentView.layer insertSublayer:self.shimmer atIndex:0];
	CABasicAnimation *a = [CABasicAnimation animationWithKeyPath:@"locations"];
	a.fromValue = @[@(-1.0), @(-0.5), @(0.0)];
	a.toValue = @[@(1.0), @(1.5), @(2.0)];
	a.duration = 1.6;
	a.repeatCount = HUGE_VALF;
	[self.shimmer addAnimation:a forKey:@"ryg_shimmer"];
}

- (void)stopShimmer {
	[self.shimmer removeAnimationForKey:@"ryg_shimmer"];
	[self.shimmer removeFromSuperlayer];
}

- (void)layoutSubviews {
	[super layoutSubviews];
	if (self.shimmer.superlayer) self.shimmer.frame = self.contentView.bounds;
}

- (void)prepareForReuse {
	[super prepareForReuse];
	[self stopShimmer];
	self.loadingCode = nil;
	self.imageView.image = nil;
	self.overlay.hidden = NO;
	self.overlay.avatarImage = nil;
	self.contentView.backgroundColor = [UIColor secondarySystemBackgroundColor];
}

@end
