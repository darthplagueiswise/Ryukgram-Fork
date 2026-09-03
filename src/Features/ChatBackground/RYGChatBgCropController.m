#import "RYGChatBgCropController.h"
#import "../../Utils.h"

@implementation RYGChatBgCropController {
	UIScrollView *_scroll;
	UIImageView *_imageView;
	UIView *_overlay;
	CAShapeLayer *_dimLayer;
	CAShapeLayer *_borderLayer;
	UIButton *_cancelBtn;
	UIButton *_useBtn;
	UILabel *_hint;
	CGRect _cropRect;
	BOOL _configured;
}

- (void)viewDidLoad {
	[super viewDidLoad];

	self.view.backgroundColor = UIColor.blackColor;
	self.modalPresentationStyle = UIModalPresentationFullScreen;

	_scroll = [UIScrollView new];
	_scroll.delegate = self;
	_scroll.bounces = NO;
	_scroll.bouncesZoom = YES;
	_scroll.clipsToBounds = YES;
	_scroll.showsHorizontalScrollIndicator = NO;
	_scroll.showsVerticalScrollIndicator = NO;
	_scroll.decelerationRate = UIScrollViewDecelerationRateFast;
	_scroll.backgroundColor = UIColor.blackColor;
	[self.view addSubview:_scroll];

	_imageView = [[UIImageView alloc] initWithImage:[self normalizedImage:self.sourceImage]];
	_imageView.contentMode = UIViewContentModeScaleToFill;
	[_scroll addSubview:_imageView];

	_overlay = [UIView new];
	_overlay.userInteractionEnabled = NO;
	[self.view addSubview:_overlay];

	_dimLayer = [CAShapeLayer layer];
	_dimLayer.fillColor = [UIColor colorWithWhite:0 alpha:0.68].CGColor;
	_dimLayer.fillRule = kCAFillRuleEvenOdd;
	[_overlay.layer addSublayer:_dimLayer];

	_borderLayer = [CAShapeLayer layer];
	_borderLayer.fillColor = UIColor.clearColor.CGColor;
	_borderLayer.strokeColor = [UIColor colorWithWhite:1 alpha:0.85].CGColor;
	_borderLayer.lineWidth = 1.5;
	[_overlay.layer addSublayer:_borderLayer];

	_hint = [UILabel new];
	_hint.text = RYGLocalized(@"Pinch + drag to position");
	_hint.textColor = [UIColor colorWithWhite:1 alpha:0.72];
	_hint.font = [UIFont systemFontOfSize:13 weight:UIFontWeightMedium];
	_hint.textAlignment = NSTextAlignmentCenter;
	[self.view addSubview:_hint];

	_cancelBtn = [self buttonWithTitle:RYGLocalized(@"Cancel") action:@selector(cancelTapped) bold:NO];
	_useBtn = [self buttonWithTitle:RYGLocalized(@"Use") action:@selector(useTapped) bold:YES];
	[self.view addSubview:_cancelBtn];
	[self.view addSubview:_useBtn];
}

- (UIButton *)buttonWithTitle:(NSString *)title action:(SEL)action bold:(BOOL)bold {
	UIButton *b = [UIButton buttonWithType:UIButtonTypeSystem];
	[b setTitle:title forState:UIControlStateNormal];
	b.tintColor = UIColor.whiteColor;
	b.backgroundColor = [UIColor colorWithWhite:1 alpha:0.12];
	b.layer.cornerRadius = 20;
	b.layer.cornerCurve = kCACornerCurveContinuous;
	b.titleLabel.font = [UIFont systemFontOfSize:17 weight:bold ? UIFontWeightSemibold : UIFontWeightMedium];
	[b addTarget:self action:action forControlEvents:UIControlEventTouchUpInside];
	return b;
}

- (void)viewDidLayoutSubviews {
	[super viewDidLayoutSubviews];
	if (!_imageView.image.CGImage) return;

	CGSize bs = self.view.bounds.size;
	UIEdgeInsets safe = self.view.safeAreaInsets;
	if (bs.width <= 0 || bs.height <= 0) return;

	CGFloat aspect = bs.width / MAX(bs.height, 1.0);
	CGFloat cropW = bs.width * 0.88;
	CGFloat cropH = cropW / MAX(aspect, 0.01);
	CGFloat maxH = bs.height - safe.top - safe.bottom - 138.0;

	if (cropH > maxH) {
		cropH = maxH;
		cropW = cropH * aspect;
	}

	_cropRect = CGRectMake((bs.width - cropW) * 0.5, safe.top + 46.0, cropW, cropH);

	_scroll.frame = _cropRect;
	_overlay.frame = self.view.bounds;
	_hint.frame = CGRectMake(20.0, safe.top + 14.0, bs.width - 40.0, 22.0);
	_cancelBtn.frame = CGRectMake(20.0, bs.height - safe.bottom - 58.0, 104.0, 44.0);
	_useBtn.frame = CGRectMake(bs.width - 124.0, bs.height - safe.bottom - 58.0, 104.0, 44.0);

	[self updateOverlay];
	if (!_configured) [self configureScrollForImage];
}

- (void)updateOverlay {
	UIBezierPath *path = [UIBezierPath bezierPathWithRect:self.view.bounds];
	[path appendPath:[UIBezierPath bezierPathWithRoundedRect:_cropRect cornerRadius:3.0]];
	_dimLayer.path = path.CGPath;
	_borderLayer.path = [UIBezierPath bezierPathWithRoundedRect:_cropRect cornerRadius:3.0].CGPath;
}

- (void)configureScrollForImage {
	_configured = YES;

	UIImage *img = _imageView.image;
	CGSize is = img.size;
	_imageView.frame = (CGRect){CGPointZero, is};
	_scroll.contentSize = is;

	CGFloat cover = MAX(_cropRect.size.width / MAX(is.width, 1.0), _cropRect.size.height / MAX(is.height, 1.0));
	_scroll.minimumZoomScale = cover;
	_scroll.maximumZoomScale = MAX(cover * 6.0, cover + 1.0);
	_scroll.zoomScale = cover;

	CGFloat x = MAX((is.width * cover - _cropRect.size.width) * 0.5, 0.0);
	CGFloat y = MAX((is.height * cover - _cropRect.size.height) * 0.5, 0.0);
	_scroll.contentOffset = CGPointMake(x, y);
}

- (UIView *)viewForZoomingInScrollView:(__unused UIScrollView *)scrollView {
	return _imageView;
}

#pragma mark - Actions

- (void)finish:(UIImage *)image {
	void (^cb)(UIImage *) = self.onConfirm;
	self.onConfirm = nil;
	[self dismissViewControllerAnimated:YES completion:^{ if (cb) cb(image); }];
}

- (void)cancelTapped {
	[self finish:nil];
}

- (void)useTapped {
	[self finish:[self croppedImageFromSource]];
}

#pragma mark - Crop

- (UIImage *)normalizedImage:(UIImage *)image {
	if (!image.CGImage || image.imageOrientation == UIImageOrientationUp) return image;

	UIGraphicsImageRendererFormat *fmt = UIGraphicsImageRendererFormat.preferredFormat;
	fmt.scale = image.scale;
	fmt.opaque = NO;

	return [[[UIGraphicsImageRenderer alloc] initWithSize:image.size format:fmt] imageWithActions:^(__unused UIGraphicsImageRendererContext *ctx) {
		[image drawInRect:(CGRect){CGPointZero, image.size}];
	}];
}

- (UIImage *)croppedImageFromSource {
	UIImage *image = _imageView.image;
	if (!image.CGImage) return nil;

	CGRect crop = [_imageView convertRect:_scroll.bounds fromView:_scroll];
	crop = CGRectIntersection(crop, (CGRect){CGPointZero, image.size});
	if (CGRectIsEmpty(crop)) return nil;

	CGFloat scale = image.scale;
	CGRect px = CGRectIntegral(CGRectMake(crop.origin.x * scale, crop.origin.y * scale, crop.size.width * scale, crop.size.height * scale));
	CGImageRef cg = CGImageCreateWithImageInRect(image.CGImage, px);
	if (!cg) return nil;

	UIImage *out = [UIImage imageWithCGImage:cg scale:scale orientation:UIImageOrientationUp];
	CGImageRelease(cg);
	return out;
}

@end