#import "SCIImageEditor.h"
#import <Vision/Vision.h>

// VNInstanceMaskObservation / VNGenerateForegroundInstanceMaskRequest agora vem do SDK 26.2 <Vision/Vision.h>

static UIImage *sciNormalizeUp(UIImage *img) {
    if (!img || img.imageOrientation == UIImageOrientationUp) return img;
    UIGraphicsImageRendererFormat *f = [UIGraphicsImageRendererFormat preferredFormat];
    f.opaque = NO;
    UIGraphicsImageRenderer *r = [[UIGraphicsImageRenderer alloc] initWithSize:img.size format:f];
    return [r imageWithActions:^(UIGraphicsImageRendererContext *c) { [img drawInRect:(CGRect){CGPointZero, img.size}]; }];
}

static void sciRemoveBackground(UIImage *image, void (^done)(UIImage *result)) {
    if (@available(iOS 17.0, *)) {
        UIImage *img = sciNormalizeUp(image);
        CIImage *ci = img.CIImage ?: (img.CGImage ? [[CIImage alloc] initWithCGImage:img.CGImage] : nil);
        if (!ci) { done(nil); return; }
        VNRequest *req = [[NSClassFromString(@"VNGenerateForegroundInstanceMaskRequest") alloc] init];
        if (!req) { done(nil); return; }
        VNImageRequestHandler *handler = [[VNImageRequestHandler alloc] initWithCIImage:ci orientation:kCGImagePropertyOrientationUp options:@{}];
        dispatch_async(dispatch_get_global_queue(QOS_CLASS_USER_INITIATED, 0), ^{
            NSError *err = nil;
            [handler performRequests:@[req] error:&err];
            VNInstanceMaskObservation *obs = (VNInstanceMaskObservation *)req.results.firstObject;
            if (!obs) { dispatch_async(dispatch_get_main_queue(), ^{ done(nil); }); return; }
            NSError *err2 = nil;
            CVPixelBufferRef out = [obs generateMaskedImageOfInstances:obs.allInstances
                                                    fromRequestHandler:handler
                                              croppedToInstancesExtent:NO
                                                                 error:&err2];
            if (!out) { dispatch_async(dispatch_get_main_queue(), ^{ done(nil); }); return; }
            CIImage *masked = [CIImage imageWithCVPixelBuffer:out];
            CIContext *ctx = [CIContext contextWithOptions:nil];
            CGImageRef cg = [ctx createCGImage:masked fromRect:masked.extent];
            CVPixelBufferRelease(out);
            UIImage *res = cg ? [UIImage imageWithCGImage:cg scale:1.0 orientation:UIImageOrientationUp] : nil;
            if (cg) CGImageRelease(cg);
            dispatch_async(dispatch_get_main_queue(), ^{ done(res); });
        });
    } else {
        done(nil);
    }
}

@interface SCIImageEditorController : UIViewController <UIScrollViewDelegate>
@property (nonatomic, strong) UIImage *sourceImage;
@property (nonatomic) CGFloat fixedAspect;
@property (nonatomic, copy) void (^onDone)(UIImage *edited);
@end

@implementation SCIImageEditorController {
    UIScrollView *_scroll;
    UIImageView *_imageView;
    UIView *_overlay;
    CAShapeLayer *_dimLayer;
    CAShapeLayer *_borderLayer;
    UISegmentedControl *_aspect;
    UIButton *_removeBGButton;
    UIButton *_resetButton;
    UIButton *_cancelButton;
    UIButton *_doneButton;
    UIActivityIndicatorView *_spinner;
    UIImage *_originalImage;
    NSArray<UIView *> *_handles;
    CGRect _cropRect;
    CGRect _areaRect;
    BOOL _needsConfigure;
    BOOL _freeInit;
}

static const CGFloat kAspects[] = { -1.0f, 0.0f, 1.0f, 0.8f, 9.0f/16.0f };  // Free, Original, 1:1, 4:5, 9:16 (w/h)

- (void)viewDidLoad {
    [super viewDidLoad];
    self.view.backgroundColor = UIColor.blackColor;
    self.modalPresentationStyle = UIModalPresentationFullScreen;
    _originalImage = self.sourceImage;

    _scroll = [UIScrollView new];
    _scroll.delegate = self;
    _scroll.bouncesZoom = YES;
    _scroll.clipsToBounds = YES;
    _scroll.backgroundColor = UIColor.blackColor;
    _scroll.showsHorizontalScrollIndicator = NO;
    _scroll.showsVerticalScrollIndicator = NO;
    _scroll.contentInsetAdjustmentBehavior = UIScrollViewContentInsetAdjustmentNever;
    [self.view addSubview:_scroll];

    _imageView = [[UIImageView alloc] initWithImage:self.sourceImage];
    _imageView.contentMode = UIViewContentModeScaleToFill;
    [_scroll addSubview:_imageView];

    _overlay = [UIView new];
    _overlay.userInteractionEnabled = NO;
    [self.view addSubview:_overlay];

    _dimLayer = [CAShapeLayer layer];
    _dimLayer.fillColor = [UIColor colorWithWhite:0 alpha:0.6].CGColor;
    _dimLayer.fillRule = kCAFillRuleEvenOdd;
    [_overlay.layer addSublayer:_dimLayer];

    _borderLayer = [CAShapeLayer layer];
    _borderLayer.fillColor = UIColor.clearColor.CGColor;
    _borderLayer.strokeColor = UIColor.whiteColor.CGColor;
    _borderLayer.lineWidth = 2.0;
    [_overlay.layer addSublayer:_borderLayer];

    _aspect = [[UISegmentedControl alloc] initWithItems:@[ SCILocalized(@"Free"), SCILocalized(@"Original"), @"1:1", @"4:5", @"9:16" ]];
    _aspect.selectedSegmentIndex = 1;
    _aspect.selectedSegmentTintColor = UIColor.whiteColor;
    [_aspect setTitleTextAttributes:@{ NSForegroundColorAttributeName: UIColor.whiteColor } forState:UIControlStateNormal];
    [_aspect setTitleTextAttributes:@{ NSForegroundColorAttributeName: UIColor.blackColor } forState:UIControlStateSelected];
    [_aspect addTarget:self action:@selector(aspectChanged) forControlEvents:UIControlEventValueChanged];
    _aspect.hidden = self.fixedAspect > 0;
    [self.view addSubview:_aspect];

    _removeBGButton = [UIButton buttonWithType:UIButtonTypeSystem];
    [_removeBGButton setTitle:SCILocalized(@"Remove background") forState:UIControlStateNormal];
    _removeBGButton.tintColor = UIColor.whiteColor;
    _removeBGButton.titleLabel.font = [UIFont systemFontOfSize:15 weight:UIFontWeightMedium];
    [_removeBGButton addTarget:self action:@selector(removeBGTapped) forControlEvents:UIControlEventTouchUpInside];
    if (@available(iOS 17.0, *)) {} else { _removeBGButton.hidden = YES; }
    [self.view addSubview:_removeBGButton];

    _resetButton = [UIButton buttonWithType:UIButtonTypeSystem];
    [_resetButton setTitle:SCILocalized(@"Reset") forState:UIControlStateNormal];
    _resetButton.tintColor = UIColor.whiteColor;
    _resetButton.titleLabel.font = [UIFont systemFontOfSize:15 weight:UIFontWeightMedium];
    [_resetButton addTarget:self action:@selector(resetTapped) forControlEvents:UIControlEventTouchUpInside];
    [self.view addSubview:_resetButton];

    _cancelButton = [UIButton buttonWithType:UIButtonTypeSystem];
    [_cancelButton setTitle:SCILocalized(@"Cancel") forState:UIControlStateNormal];
    _cancelButton.tintColor = UIColor.whiteColor;
    _cancelButton.titleLabel.font = [UIFont systemFontOfSize:17 weight:UIFontWeightMedium];
    [_cancelButton addTarget:self action:@selector(cancelTapped) forControlEvents:UIControlEventTouchUpInside];
    [self.view addSubview:_cancelButton];

    _doneButton = [UIButton buttonWithType:UIButtonTypeSystem];
    [_doneButton setTitle:SCILocalized(@"Done") forState:UIControlStateNormal];
    _doneButton.tintColor = UIColor.whiteColor;
    _doneButton.titleLabel.font = [UIFont systemFontOfSize:17 weight:UIFontWeightSemibold];
    [_doneButton addTarget:self action:@selector(doneTapped) forControlEvents:UIControlEventTouchUpInside];
    [self.view addSubview:_doneButton];

    _spinner = [[UIActivityIndicatorView alloc] initWithActivityIndicatorStyle:UIActivityIndicatorViewStyleLarge];
    _spinner.color = UIColor.whiteColor;
    _spinner.hidesWhenStopped = YES;
    [self.view addSubview:_spinner];

    NSMutableArray *handles = [NSMutableArray array];
    for (int i = 0; i < 4; i++) {
        UIView *h = [[UIView alloc] initWithFrame:CGRectMake(0, 0, 26, 26)];
        h.backgroundColor = UIColor.clearColor;
        h.layer.borderColor = UIColor.whiteColor.CGColor;
        h.layer.borderWidth = 3.0;
        h.layer.cornerRadius = 3.0;
        h.tag = i;
        h.hidden = YES;
        UIPanGestureRecognizer *pan = [[UIPanGestureRecognizer alloc] initWithTarget:self action:@selector(handlePan:)];
        [h addGestureRecognizer:pan];
        [self.view addSubview:h];
        [handles addObject:h];
    }
    _handles = handles;

    _needsConfigure = YES;
}

- (void)viewDidLayoutSubviews {
    [super viewDidLayoutSubviews];
    CGSize size = self.view.bounds.size;
    if (size.width <= 0 || size.height <= 0 || !self.sourceImage.CGImage) return;
    UIEdgeInsets safe = self.view.safeAreaInsets;

    CGFloat topY = safe.top + 12.0;
    CGFloat bottomChrome = 120.0 + safe.bottom;
    CGRect area = CGRectMake(16, topY, size.width - 32, size.height - topY - bottomChrome);
    _areaRect = area;

    BOOL freeMode = (self.fixedAspect <= 0) && (_aspect.selectedSegmentIndex == 0);
    if (freeMode) {
        if (!_freeInit) {
            _cropRect = CGRectInset(area, area.size.width * 0.1, area.size.height * 0.1);
            _freeInit = YES;
        } else {
            _cropRect = CGRectIntersection(_cropRect, area);
        }
    } else {
        CGFloat ar = self.fixedAspect > 0 ? self.fixedAspect : kAspects[_aspect.selectedSegmentIndex];
        if (ar <= 0) {
            CGSize is = self.sourceImage.size;
            ar = is.height > 0 ? is.width / is.height : 1.0;
        }
        CGFloat cw = area.size.width, ch = cw / ar;
        if (ch > area.size.height) { ch = area.size.height; cw = ch * ar; }
        _cropRect = CGRectMake(CGRectGetMidX(area) - cw / 2, CGRectGetMidY(area) - ch / 2, cw, ch);
    }
    _scroll.frame = _cropRect;

    for (UIView *h in _handles) {
        h.hidden = !freeMode;
        CGPoint c;
        switch (h.tag) {
            case 0: c = CGPointMake(CGRectGetMinX(_cropRect), CGRectGetMinY(_cropRect)); break;
            case 1: c = CGPointMake(CGRectGetMaxX(_cropRect), CGRectGetMinY(_cropRect)); break;
            case 2: c = CGPointMake(CGRectGetMinX(_cropRect), CGRectGetMaxY(_cropRect)); break;
            default: c = CGPointMake(CGRectGetMaxX(_cropRect), CGRectGetMaxY(_cropRect)); break;
        }
        h.center = c;
    }

    _overlay.frame = self.view.bounds;
    UIBezierPath *hole = [UIBezierPath bezierPathWithRect:_cropRect];
    UIBezierPath *dim = [UIBezierPath bezierPathWithRect:_overlay.bounds];
    [dim appendPath:hole];
    dim.usesEvenOddFillRule = YES;
    _dimLayer.frame = _overlay.bounds;
    _dimLayer.path = dim.CGPath;
    _borderLayer.frame = _overlay.bounds;
    _borderLayer.path = hole.CGPath;

    CGFloat rowY = size.height - safe.bottom - 52.0;
    _aspect.frame = CGRectMake(24, rowY - 44, size.width - 48, 32);
    CGSize rmSize = [_removeBGButton sizeThatFits:CGSizeZero];
    CGSize rsSize = [_resetButton sizeThatFits:CGSizeZero];
    CGFloat gap = 28.0;
    CGFloat rmW = _removeBGButton.hidden ? 0 : rmSize.width;
    CGFloat totalW = rmW + (rmW > 0 ? gap : 0) + rsSize.width;
    CGFloat startX = (size.width - totalW) * 0.5;
    if (rmW > 0) {
        _removeBGButton.frame = CGRectMake(startX, rowY + 2, rmSize.width, 28);
        startX += rmW + gap;
    }
    _resetButton.frame = CGRectMake(startX, rowY + 2, rsSize.width, 28);

    CGSize c = _cancelButton.intrinsicContentSize, d = _doneButton.intrinsicContentSize;
    CGFloat by = size.height - safe.bottom - 12.0;
    _cancelButton.frame = CGRectMake(safe.left + 24, by - c.height, c.width, c.height);
    _doneButton.frame = CGRectMake(size.width - safe.right - 24 - d.width, by - d.height, d.width, d.height);
    _spinner.center = CGPointMake(size.width * 0.5, CGRectGetMidY(_cropRect));

    if (_needsConfigure) { _needsConfigure = NO; [self configureZoom]; }
}

- (void)configureZoom {
    CGSize imageSize = self.sourceImage.size;
    if (imageSize.width < 1 || imageSize.height < 1) return;
    _imageView.image = self.sourceImage;
    _imageView.frame = (CGRect){ CGPointZero, imageSize };
    _scroll.contentInset = UIEdgeInsetsZero;
    _scroll.contentSize = imageSize;

    CGFloat fit  = MIN(_cropRect.size.width / imageSize.width, _cropRect.size.height / imageSize.height);
    CGFloat fill = MAX(_cropRect.size.width / imageSize.width, _cropRect.size.height / imageSize.height);
    _scroll.minimumZoomScale = fit * 0.5;
    _scroll.maximumZoomScale = MAX(fill * 8.0, fit + 0.01);
    _scroll.zoomScale = fill;
    _scroll.contentOffset = CGPointMake((imageSize.width * fill - _cropRect.size.width) * 0.5,
                                        (imageSize.height * fill - _cropRect.size.height) * 0.5);
}

- (UIView *)viewForZoomingInScrollView:(UIScrollView *)scrollView { return _imageView; }

- (void)aspectChanged { _needsConfigure = YES; [self.view setNeedsLayout]; }

- (void)handlePan:(UIPanGestureRecognizer *)g {
    CGPoint p = [g locationInView:self.view];
    CGFloat minX = CGRectGetMinX(_cropRect), minY = CGRectGetMinY(_cropRect);
    CGFloat maxX = CGRectGetMaxX(_cropRect), maxY = CGRectGetMaxY(_cropRect);
    CGFloat aMinX = CGRectGetMinX(_areaRect), aMinY = CGRectGetMinY(_areaRect);
    CGFloat aMaxX = CGRectGetMaxX(_areaRect), aMaxY = CGRectGetMaxY(_areaRect);
    p.x = MAX(aMinX, MIN(aMaxX, p.x));
    p.y = MAX(aMinY, MIN(aMaxY, p.y));
    CGFloat m = 80.0;  // minimum crop side
    switch (g.view.tag) {
        case 0: minX = MIN(p.x, maxX - m); minY = MIN(p.y, maxY - m); break;
        case 1: maxX = MAX(p.x, minX + m); minY = MIN(p.y, maxY - m); break;
        case 2: minX = MIN(p.x, maxX - m); maxY = MAX(p.y, minY + m); break;
        default: maxX = MAX(p.x, minX + m); maxY = MAX(p.y, minY + m); break;
    }
    _cropRect = CGRectMake(minX, minY, maxX - minX, maxY - minY);
    [self.view setNeedsLayout];
}

- (UIImage *)croppedImage {
    UIImage *src = self.sourceImage;
    if (!src.CGImage) return src;
    CGFloat zoom = _scroll.zoomScale;
    if (zoom <= 0) return src;
    CGSize imgSize = src.size;
    CGRect rect = CGRectMake(_scroll.contentOffset.x / zoom,
                             _scroll.contentOffset.y / zoom,
                             _scroll.bounds.size.width / zoom,
                             _scroll.bounds.size.height / zoom);
    rect = CGRectIntersection(rect, CGRectMake(0, 0, imgSize.width, imgSize.height));
    if (CGRectIsNull(rect) || rect.size.width < 1 || rect.size.height < 1) return src;

    CGFloat scale = src.scale;
    CGRect px = CGRectMake(rect.origin.x * scale, rect.origin.y * scale, rect.size.width * scale, rect.size.height * scale);
    CGImageRef cg = CGImageCreateWithImageInRect(src.CGImage, px);
    if (!cg) return src;
    UIImage *out = [UIImage imageWithCGImage:cg scale:scale orientation:src.imageOrientation];
    CGImageRelease(cg);
    return out;
}

- (void)removeBGTapped {
    UIImage *current = [self croppedImage];
    [_spinner startAnimating];
    self.view.userInteractionEnabled = NO;
    __weak typeof(self) ws = self;
    sciRemoveBackground(current, ^(UIImage *result) {
        __strong typeof(ws) ss = ws;
        if (!ss) return;
        [ss->_spinner stopAnimating];
        ss.view.userInteractionEnabled = YES;
        if (!result) {
            UIAlertController *a = [UIAlertController alertControllerWithTitle:SCILocalized(@"No subject found") message:nil preferredStyle:UIAlertControllerStyleAlert];
            [a addAction:[UIAlertAction actionWithTitle:SCILocalized(@"OK") style:UIAlertActionStyleDefault handler:nil]];
            [ss presentViewController:a animated:YES completion:nil];
            return;
        }
        ss.sourceImage = result;
        ss->_aspect.selectedSegmentIndex = 0;
        ss->_needsConfigure = YES;
        [ss.view setNeedsLayout];
    });
}

- (void)resetTapped {
    if (!_originalImage) return;
    self.sourceImage = _originalImage;
    _aspect.selectedSegmentIndex = 0;
    _needsConfigure = YES;
    [self.view setNeedsLayout];
}

- (void)cancelTapped { [self dismissViewControllerAnimated:YES completion:nil]; }

- (void)doneTapped {
    UIImage *out = [self croppedImage];
    void (^cb)(UIImage *) = self.onDone;
    [self dismissViewControllerAnimated:YES completion:^{ if (cb && out) cb(out); }];
}

@end

@implementation SCIImageEditor
+ (void)presentForImage:(UIImage *)image from:(UIViewController *)presenter onDone:(void (^)(UIImage *))onDone {
    [self presentForImage:image from:presenter fixedAspect:0 onDone:onDone];
}

+ (void)presentForImage:(UIImage *)image from:(UIViewController *)presenter fixedAspect:(CGFloat)fixedAspect onDone:(void (^)(UIImage *))onDone {
    if (image && !image.CGImage) {
        UIImage *n = sciNormalizeUp(image);
        if (n.CGImage) image = n;
    }
    if (!image || !image.CGImage || !presenter) return;
    SCIImageEditorController *vc = [SCIImageEditorController new];
    vc.sourceImage = image;
    vc.fixedAspect = fixedAspect;
    vc.onDone = onDone;
    [presenter presentViewController:vc animated:YES completion:nil];
}
@end
