#import "SCIStickerSearchPicker.h"
#import "../Networking/SCIInstagramAPI.h"
#import <ImageIO/ImageIO.h>
#import <objc/message.h>
#import <objc/runtime.h>

static UIImage *sciDecodeStickerData(NSData *data) {
    if (!data.length) return nil;
    UIImage *img = [UIImage imageWithData:data];
    if (img.CGImage) return img;
    CGImageSourceRef src = CGImageSourceCreateWithData((__bridge CFDataRef)data, NULL);
    if (!src) return nil;
    CGImageRef cg = CGImageSourceCreateImageAtIndex(src, 0, NULL);
    CFRelease(src);
    if (!cg) return nil;
    UIImage *out = [UIImage imageWithCGImage:cg];
    CGImageRelease(cg);
    return out;
}

static void sciCollectStickerURLs(id node, NSString *key, NSMutableArray *out) {
    if ([node isKindOfClass:NSDictionary.class]) {
        for (NSString *k in (NSDictionary *)node) sciCollectStickerURLs(node[k], k, out);
    } else if ([node isKindOfClass:NSArray.class]) {
        for (id v in (NSArray *)node) sciCollectStickerURLs(v, key, out);
    } else if ([node isKindOfClass:NSString.class]) {
        NSString *s = node;
        if ([key isEqualToString:@"image_url"] && [s hasPrefix:@"http"]) [out addObject:s];
    }
}

@interface SCIStickerCell : UICollectionViewCell
@property (nonatomic, strong) UIImageView *imageView;
@property (nonatomic, copy) NSString *loadingURL;
@end
@implementation SCIStickerCell
- (instancetype)initWithFrame:(CGRect)frame {
    if ((self = [super initWithFrame:frame])) {
        self.backgroundColor = [UIColor colorWithWhite:1 alpha:0.06];
        self.layer.cornerRadius = 8;
        self.clipsToBounds = YES;
        _imageView = [[UIImageView alloc] initWithFrame:self.contentView.bounds];
        _imageView.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
        _imageView.contentMode = UIViewContentModeScaleAspectFit;
        [self.contentView addSubview:_imageView];
    }
    return self;
}
- (void)prepareForReuse { [super prepareForReuse]; _imageView.image = nil; _loadingURL = nil; }
@end

@interface SCIStickerSearchController : UIViewController <UICollectionViewDataSource, UICollectionViewDelegateFlowLayout, UITextViewDelegate>
@property (nonatomic, copy) void (^onPick)(UIImage *);
@end

@implementation SCIStickerSearchController {
    UISegmentedControl *_tabs;
    UICollectionView *_collection;
    UIActivityIndicatorView *_spinner;
    UILabel *_empty;
    UITextView *_iosField;
    UILabel *_iosHint;
    UIImageView *_iosIcon;
    NSMutableArray<NSString *> *_items;
    NSCache *_thumbCache;
}

- (void)viewDidLoad {
    [super viewDidLoad];
    self.view.backgroundColor = UIColor.blackColor;
    _items = [NSMutableArray array];
    _thumbCache = [NSCache new];

    _tabs = [[UISegmentedControl alloc] initWithItems:@[ @"Instagram", @"iOS" ]];
    _tabs.selectedSegmentIndex = 0;
    [_tabs addTarget:self action:@selector(tabChanged) forControlEvents:UIControlEventValueChanged];
    self.navigationItem.titleView = _tabs;

    UICollectionViewFlowLayout *layout = [UICollectionViewFlowLayout new];
    layout.minimumInteritemSpacing = 8;
    layout.minimumLineSpacing = 8;
    layout.sectionInset = UIEdgeInsetsMake(12, 12, 24, 12);
    _collection = [[UICollectionView alloc] initWithFrame:CGRectZero collectionViewLayout:layout];
    _collection.backgroundColor = UIColor.clearColor;
    _collection.dataSource = self;
    _collection.delegate = self;
    [_collection registerClass:SCIStickerCell.class forCellWithReuseIdentifier:@"c"];
    [self.view addSubview:_collection];

    _empty = [UILabel new];
    _empty.text = SCILocalized(@"No stickers yet");
    _empty.textColor = [UIColor colorWithWhite:1 alpha:0.5];
    _empty.textAlignment = NSTextAlignmentCenter;
    _empty.hidden = YES;
    [self.view addSubview:_empty];

    _iosField = [[UITextView alloc] init];
    _iosField.allowsEditingTextAttributes = YES;
    _iosField.backgroundColor = UIColor.clearColor;
    _iosField.textColor = UIColor.clearColor;
    _iosField.tintColor = UIColor.clearColor;
    _iosField.font = [UIFont systemFontOfSize:1];
    _iosField.delegate = self;
    _iosField.hidden = YES;
    _iosField.scrollEnabled = NO;
    _iosField.autocorrectionType = UITextAutocorrectionTypeNo;
    if ([_iosField respondsToSelector:@selector(setSupportsAdaptiveImageGlyph:)])
        ((void (*)(id, SEL, BOOL))objc_msgSend)(_iosField, @selector(setSupportsAdaptiveImageGlyph:), YES);
    [self.view addSubview:_iosField];

    _iosIcon = [[UIImageView alloc] initWithImage:[UIImage systemImageNamed:@"hand.tap.fill"]];
    _iosIcon.tintColor = [UIColor colorWithWhite:1 alpha:0.85];
    _iosIcon.contentMode = UIViewContentModeScaleAspectFit;
    _iosIcon.hidden = YES;
    [self.view addSubview:_iosIcon];

    _iosHint = [UILabel new];
    _iosHint.text = SCILocalized(@"Tap any sticker on your keyboard\nto add it to your drawing");
    _iosHint.textColor = [UIColor colorWithWhite:1 alpha:0.6];
    _iosHint.font = [UIFont systemFontOfSize:16 weight:UIFontWeightMedium];
    _iosHint.textAlignment = NSTextAlignmentCenter;
    _iosHint.numberOfLines = 0;
    _iosHint.hidden = YES;
    [self.view addSubview:_iosHint];

    UIBarButtonItem *close = [[UIBarButtonItem alloc] initWithBarButtonSystemItem:UIBarButtonSystemItemClose target:self action:@selector(closeTapped)];
    close.tintColor = UIColor.whiteColor;
    self.navigationItem.leftBarButtonItem = close;

    _spinner = [[UIActivityIndicatorView alloc] initWithActivityIndicatorStyle:UIActivityIndicatorViewStyleLarge];
    _spinner.color = UIColor.whiteColor;
    _spinner.hidesWhenStopped = YES;
    [self.view addSubview:_spinner];

    [self fetch];
}

- (void)viewDidLayoutSubviews {
    [super viewDidLayoutSubviews];
    _collection.frame = self.view.bounds;
    _iosField.frame = self.view.bounds;
    _spinner.center = _empty.center = CGPointMake(self.view.bounds.size.width * 0.5, self.view.bounds.size.height * 0.4);
    [_empty sizeToFit]; _empty.center = _spinner.center;
    CGFloat w = self.view.bounds.size.width;
    UINavigationBar *bar = self.navigationController.navigationBar;
    CGFloat navBottom = bar ? CGRectGetMaxY([bar convertRect:bar.bounds toView:self.view]) : self.view.safeAreaInsets.top;
    CGFloat top = navBottom + 48;
    _iosIcon.frame = CGRectMake(w / 2 - 30, top, 60, 60);
    _iosHint.frame = CGRectMake(24, top + 72, w - 48, 60);
}

- (void)tabChanged {
    BOOL ios = _tabs.selectedSegmentIndex == 1;
    _collection.hidden = ios;
    _empty.hidden = YES;
    _iosField.hidden = !ios;
    _iosHint.hidden = !ios;
    _iosIcon.hidden = !ios;
    if (ios) { _iosField.attributedText = [NSAttributedString new]; [_iosField becomeFirstResponder]; }
    else { [_iosField resignFirstResponder]; }
}

- (void)textViewDidChange:(UITextView *)tv {
    __block UIImage *found = nil;
    NSAttributedString *attr = tv.attributedText;
    [attr enumerateAttributesInRange:NSMakeRange(0, attr.length) options:0
                          usingBlock:^(NSDictionary<NSAttributedStringKey, id> *attrs, NSRange range, BOOL *stop) {
        id glyph = attrs[@"CTAdaptiveImageProvider"] ?: attrs[@"NSAdaptiveImageGlyph"];
        if (glyph) {
            NSData *d = nil;
            for (NSString *k in @[ @"imageContent", @"imageData", @"data" ]) {
                @try { id v = [glyph valueForKey:k]; if ([v isKindOfClass:NSData.class]) { d = v; break; } } @catch (__unused id e) {}
            }
            UIImage *img = d ? [UIImage imageWithData:d] : nil;
            if (img) { found = img; *stop = YES; return; }
        }
        NSTextAttachment *att = attrs[NSAttachmentAttributeName];
        if ([att isKindOfClass:NSTextAttachment.class]) {
            UIImage *img = att.image ?: [att imageForBounds:CGRectMake(0, 0, 512, 512) textContainer:nil characterIndex:range.location];
            if (!img && att.contents) img = [UIImage imageWithData:att.contents];
            if (img) { found = img; *stop = YES; }
        }
    }];
    if (!found) {
        if (attr.length) tv.attributedText = [NSAttributedString new];
        return;
    }
    void (^cb)(UIImage *) = self.onPick;
    tv.attributedText = [NSAttributedString new];
    [tv resignFirstResponder];
    [self dismissViewControllerAnimated:YES completion:^{ if (cb) cb(found); }];
}

- (void)closeTapped { [_iosField resignFirstResponder]; [self dismissViewControllerAnimated:YES completion:nil]; }

- (void)fetch {
    [_spinner startAnimating];
    __weak typeof(self) ws = self;
    [SCIInstagramAPI sendRequestWithMethod:@"GET" path:@"creatives/sticker_tray/" body:nil completion:^(NSDictionary *resp, NSError *err) {
        __strong typeof(ws) ss = ws; if (!ss) return;
        [ss->_spinner stopAnimating];
        if (err || ![resp isKindOfClass:NSDictionary.class]) return;
        NSMutableArray *found = [NSMutableArray array];
        sciCollectStickerURLs(resp[@"sticker_tray"] ?: resp, nil, found);
        [ss->_items setArray:found];
        ss->_empty.hidden = ss->_items.count > 0 || ss->_tabs.selectedSegmentIndex == 1;
        [ss->_collection reloadData];
    }];
}

- (NSInteger)collectionView:(UICollectionView *)cv numberOfItemsInSection:(NSInteger)s { return _items.count; }

- (CGSize)collectionView:(UICollectionView *)cv layout:(UICollectionViewLayout *)l sizeForItemAtIndexPath:(NSIndexPath *)ip {
    CGFloat w = (cv.bounds.size.width - 24 - 16) / 3.0;
    return CGSizeMake(w, w);
}

- (UICollectionViewCell *)collectionView:(UICollectionView *)cv cellForItemAtIndexPath:(NSIndexPath *)ip {
    SCIStickerCell *cell = [cv dequeueReusableCellWithReuseIdentifier:@"c" forIndexPath:ip];
    NSString *url = _items[ip.item];
    cell.loadingURL = url;
    UIImage *cached = [_thumbCache objectForKey:url];
    if (cached) { cell.imageView.image = cached; return cell; }
    __weak SCIStickerCell *wcell = cell;
    __weak typeof(self) ws = self;
    [[[NSURLSession sharedSession] dataTaskWithURL:[NSURL URLWithString:url] completionHandler:^(NSData *data, NSURLResponse *r, NSError *e) {
        UIImage *img = sciDecodeStickerData(data);
        if (!img) return;
        dispatch_async(dispatch_get_main_queue(), ^{
            __strong typeof(ws) ss = ws; if (ss) [ss->_thumbCache setObject:img forKey:url];
            __strong SCIStickerCell *sc = wcell;
            if (sc && [sc.loadingURL isEqualToString:url]) sc.imageView.image = img;
        });
    }] resume];
    return cell;
}

- (void)collectionView:(UICollectionView *)cv didSelectItemAtIndexPath:(NSIndexPath *)ip {
    NSString *url = _items[ip.item];
    [_spinner startAnimating];
    void (^cb)(UIImage *) = self.onPick;
    __weak typeof(self) ws = self;
    [[[NSURLSession sharedSession] dataTaskWithURL:[NSURL URLWithString:url] completionHandler:^(NSData *data, NSURLResponse *r, NSError *e) {
        UIImage *img = sciDecodeStickerData(data);
        dispatch_async(dispatch_get_main_queue(), ^{
            __strong typeof(ws) ss = ws; if (!ss) return;
            [ss->_spinner stopAnimating];
            if (!img) return;
            [ss dismissViewControllerAnimated:YES completion:^{ if (cb) cb(img); }];
        });
    }] resume];
}

@end

@implementation SCIStickerSearchPicker
+ (void)presentFrom:(UIViewController *)presenter onPick:(void (^)(UIImage *))onPick {
    if (!presenter) return;
    SCIStickerSearchController *vc = [SCIStickerSearchController new];
    vc.onPick = onPick;
    UINavigationController *nav = [[UINavigationController alloc] initWithRootViewController:vc];
    nav.navigationBar.barStyle = UIBarStyleBlack;
    nav.modalPresentationStyle = UIModalPresentationPageSheet;
    nav.modalInPresentation = YES;
    if (@available(iOS 15.0, *)) {
        UISheetPresentationController *sheet = nav.sheetPresentationController;
        sheet.detents = @[ UISheetPresentationControllerDetent.mediumDetent, UISheetPresentationControllerDetent.largeDetent ];
        sheet.prefersGrabberVisible = YES;
    }
    [presenter presentViewController:nav animated:YES completion:nil];
}
@end
