// DM "draw" doodle: send an image (gallery / Photos / stickers / paste) as the
// doodle by swapping the rendered canvas image, routed through SCIImageEditor.

#import <UIKit/UIKit.h>
#import <PhotosUI/PhotosUI.h>
#import <objc/runtime.h>
#import <objc/message.h>
#import "../../Utils.h"
#import "../../UI/SCIImageEditor.h"
#import "../../UI/SCIStickerSearchPicker.h"
#import "../../Gallery/SCIGalleryViewController.h"
#import "../../Gallery/SCIGalleryFile.h"

static UIImage *gDoodleSource;
static BOOL gDoodleResending;
static BOOL gDoodlePassthrough;

static UIViewController *sciDoodleTopPresenter(void) {
    UIViewController *root = nil;
    for (UIScene *scene in [UIApplication sharedApplication].connectedScenes) {
        if (![scene isKindOfClass:[UIWindowScene class]]) continue;
        for (UIWindow *w in ((UIWindowScene *)scene).windows) {
            if (w.isKeyWindow) { root = w.rootViewController; break; }
            if (!root) root = w.rootViewController;
        }
    }
    while (root.presentedViewController) root = root.presentedViewController;
    return root;
}

static UIImage *sciAspectFit(UIImage *src, CGSize target) {
    if (!src || target.width < 1 || target.height < 1) return src;
    CGFloat s = MIN(target.width / src.size.width, target.height / src.size.height);
    CGSize d = CGSizeMake(src.size.width * s, src.size.height * s);
    CGRect r = CGRectMake((target.width - d.width) / 2, (target.height - d.height) / 2, d.width, d.height);
    UIGraphicsImageRendererFormat *f = [UIGraphicsImageRendererFormat preferredFormat];
    f.opaque = NO;
    UIGraphicsImageRenderer *rr = [[UIGraphicsImageRenderer alloc] initWithSize:target format:f];
    return [rr imageWithActions:^(UIGraphicsImageRendererContext *c) { [src drawInRect:r]; }];
}

@interface SCIDoodlePhotosDelegate : NSObject <PHPickerViewControllerDelegate>
@property (nonatomic, copy) void (^completion)(UIImage *);
@end
@implementation SCIDoodlePhotosDelegate
- (void)picker:(PHPickerViewController *)picker didFinishPicking:(NSArray<PHPickerResult *> *)results {
    void (^comp)(UIImage *) = self.completion;
    [picker dismissViewControllerAnimated:YES completion:^{
        NSItemProvider *prov = results.firstObject.itemProvider;
        if (!prov || ![prov canLoadObjectOfClass:UIImage.class]) return;
        [prov loadObjectOfClass:UIImage.class completionHandler:^(id obj, __unused NSError *e) {
            UIImage *img = [obj isKindOfClass:UIImage.class] ? obj : nil;
            dispatch_async(dispatch_get_main_queue(), ^{ if (comp && img) comp(img); });
        }];
    }];
}
@end
static SCIDoodlePhotosDelegate *gPhotosDelegate;

static void sciEditThenArm(id drawVC, UIImage *img) {
    if (!img) return;
    __weak id wvc = drawVC;
    [SCIImageEditor presentForImage:img from:sciDoodleTopPresenter() onDone:^(UIImage *edited) {
        if (!edited) return;
        gDoodleSource = edited;
        gDoodleResending = YES;
        [wvc _send];
    }];
}

static void sciPickFromPhotos(id drawVC) {
    PHPickerConfiguration *cfg = [[PHPickerConfiguration alloc] init];
    cfg.filter = PHPickerFilter.imagesFilter;
    cfg.selectionLimit = 1;
    PHPickerViewController *p = [[PHPickerViewController alloc] initWithConfiguration:cfg];
    gPhotosDelegate = [SCIDoodlePhotosDelegate new];
    gPhotosDelegate.completion = ^(UIImage *img) { sciEditThenArm(drawVC, img); };
    p.delegate = gPhotosDelegate;
    p.modalPresentationStyle = UIModalPresentationFullScreen;
    [sciDoodleTopPresenter() presentViewController:p animated:YES completion:nil];
}

static void sciPickFromGallery(id drawVC) {
    [SCIGalleryViewController presentPickerWithMediaTypes:@[@(SCIGalleryMediaTypeImage)]
                                                    title:SCILocalized(@"In-app Gallery")
                                                   fromVC:sciDoodleTopPresenter()
                                               completion:^(NSURL *u, __unused SCIGalleryFile *f) {
        UIImage *img = u.path.length ? [UIImage imageWithContentsOfFile:u.path] : nil;
        sciEditThenArm(drawVC, img);
    }];
}

%group SCIDoodleImageGroup

%hook IGDirectThreadViewDrawingViewController

- (UIImage *)drawingImage {
    UIImage *orig = %orig;
    if (gDoodleSource && orig) return sciAspectFit(gDoodleSource, orig.size);
    return orig;
}

- (void)_send {
    if (gDoodlePassthrough) {
    	gDoodlePassthrough = NO;
    	%orig;
    	return;
    }
    if (gDoodleResending) {
    	%orig;
    	gDoodleResending = NO;
    	gDoodleSource = nil;
    	return;
    }

    __weak typeof(self) ws = self;
    UIAlertController *sheet = [UIAlertController alertControllerWithTitle:SCILocalized(@"Send drawing")
                                                                  message:nil
                                                           preferredStyle:UIAlertControllerStyleAlert];

    [sheet addAction:[UIAlertAction actionWithTitle:SCILocalized(@"Send my drawing") style:UIAlertActionStyleDefault handler:^(__unused UIAlertAction *a) {
        gDoodlePassthrough = YES;
        [ws _send];
    }]];
    if ([SCIUtils getBoolPref:@"sci_gallery_enabled"]) {
        [sheet addAction:[UIAlertAction actionWithTitle:SCILocalized(@"In-app Gallery") style:UIAlertActionStyleDefault handler:^(__unused UIAlertAction *a) {
            sciPickFromGallery(ws);
        }]];
    }
    [sheet addAction:[UIAlertAction actionWithTitle:SCILocalized(@"Photos library") style:UIAlertActionStyleDefault handler:^(__unused UIAlertAction *a) {
        sciPickFromPhotos(ws);
    }]];
    [sheet addAction:[UIAlertAction actionWithTitle:SCILocalized(@"Stickers") style:UIAlertActionStyleDefault handler:^(__unused UIAlertAction *a) {
        [SCIStickerSearchPicker presentFrom:sciDoodleTopPresenter() onPick:^(UIImage *img) { sciEditThenArm(ws, img); }];
    }]];
    if (UIPasteboard.generalPasteboard.hasImages) {
        [sheet addAction:[UIAlertAction actionWithTitle:SCILocalized(@"Paste image / sticker") style:UIAlertActionStyleDefault handler:^(__unused UIAlertAction *a) {
            sciEditThenArm(ws, UIPasteboard.generalPasteboard.image);
        }]];
    }
    [sheet addAction:[UIAlertAction actionWithTitle:SCILocalized(@"Cancel") style:UIAlertActionStyleCancel handler:nil]];

    [sciDoodleTopPresenter() presentViewController:sheet animated:YES completion:nil];
}

%end

%end

%ctor {
    if ([SCIUtils getBoolPref:@"sci_doodle_image_enabled"]) %init(SCIDoodleImageGroup);
}
