// DM "draw" doodle: send an image (gallery / Photos / stickers / paste) as the
// doodle by swapping the rendered canvas image, routed through RYGImageEditor.

#import <UIKit/UIKit.h>
#import <PhotosUI/PhotosUI.h>
#import <objc/runtime.h>
#import <objc/message.h>
#import "../../Utils.h"
#import "../../UI/RYGImageEditor.h"
#import "../../UI/RYGStickerSearchPicker.h"
#import "../../Gallery/RYGGalleryViewController.h"
#import "../../Gallery/RYGGalleryFile.h"

static UIImage *gDoodleSource;
static BOOL gDoodleResending;
static BOOL gDoodlePassthrough;

static UIViewController *rygDoodleTopPresenter(void) {
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

static UIImage *rygAspectFit(UIImage *src, CGSize target) {
    if (!src || target.width < 1 || target.height < 1) return src;
    CGFloat s = MIN(target.width / src.size.width, target.height / src.size.height);
    CGSize d = CGSizeMake(src.size.width * s, src.size.height * s);
    CGRect r = CGRectMake((target.width - d.width) / 2, (target.height - d.height) / 2, d.width, d.height);
    UIGraphicsImageRendererFormat *f = [UIGraphicsImageRendererFormat preferredFormat];
    f.opaque = NO;
    UIGraphicsImageRenderer *rr = [[UIGraphicsImageRenderer alloc] initWithSize:target format:f];
    return [rr imageWithActions:^(UIGraphicsImageRendererContext *c) { [src drawInRect:r]; }];
}

@interface RYGDoodlePhotosDelegate : NSObject <PHPickerViewControllerDelegate>
@property (nonatomic, copy) void (^completion)(UIImage *);
@end
@implementation RYGDoodlePhotosDelegate
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
static RYGDoodlePhotosDelegate *gPhotosDelegate;

static void rygEditThenArm(id drawVC, UIImage *img) {
    if (!img) return;
    __weak id wvc = drawVC;
    [RYGImageEditor presentForImage:img from:rygDoodleTopPresenter() onDone:^(UIImage *edited) {
        if (!edited) return;
        gDoodleSource = edited;
        gDoodleResending = YES;
        [wvc _send];
    }];
}

static void rygPickFromPhotos(id drawVC) {
    PHPickerConfiguration *cfg = [[PHPickerConfiguration alloc] init];
    cfg.filter = PHPickerFilter.imagesFilter;
    cfg.selectionLimit = 1;
    PHPickerViewController *p = [[PHPickerViewController alloc] initWithConfiguration:cfg];
    gPhotosDelegate = [RYGDoodlePhotosDelegate new];
    gPhotosDelegate.completion = ^(UIImage *img) { rygEditThenArm(drawVC, img); };
    p.delegate = gPhotosDelegate;
    p.modalPresentationStyle = UIModalPresentationFullScreen;
    [rygDoodleTopPresenter() presentViewController:p animated:YES completion:nil];
}

static void rygPickFromGallery(id drawVC) {
    [RYGGalleryViewController presentPickerWithMediaTypes:@[@(RYGGalleryMediaTypeImage)]
                                                    title:RYGLocalized(@"In-app Gallery")
                                                   fromVC:rygDoodleTopPresenter()
                                               completion:^(NSURL *u, __unused RYGGalleryFile *f) {
        UIImage *img = u.path.length ? [UIImage imageWithContentsOfFile:u.path] : nil;
        rygEditThenArm(drawVC, img);
    }];
}

%group RYGDoodleImageGroup

%hook IGDirectThreadViewDrawingViewController

- (UIImage *)drawingImage {
    UIImage *orig = %orig;
    if (gDoodleSource && orig) return rygAspectFit(gDoodleSource, orig.size);
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
    UIAlertController *sheet = [UIAlertController alertControllerWithTitle:RYGLocalized(@"Send drawing")
                                                                  message:nil
                                                           preferredStyle:UIAlertControllerStyleAlert];

    [sheet addAction:[UIAlertAction actionWithTitle:RYGLocalized(@"Send my drawing") style:UIAlertActionStyleDefault handler:^(__unused UIAlertAction *a) {
        gDoodlePassthrough = YES;
        [ws _send];
    }]];
    if ([RYGUtils getBoolPref:@"ryg_gallery_enabled"]) {
        [sheet addAction:[UIAlertAction actionWithTitle:RYGLocalized(@"In-app Gallery") style:UIAlertActionStyleDefault handler:^(__unused UIAlertAction *a) {
            rygPickFromGallery(ws);
        }]];
    }
    [sheet addAction:[UIAlertAction actionWithTitle:RYGLocalized(@"Photos library") style:UIAlertActionStyleDefault handler:^(__unused UIAlertAction *a) {
        rygPickFromPhotos(ws);
    }]];
    [sheet addAction:[UIAlertAction actionWithTitle:RYGLocalized(@"Stickers") style:UIAlertActionStyleDefault handler:^(__unused UIAlertAction *a) {
        [RYGStickerSearchPicker presentFrom:rygDoodleTopPresenter() onPick:^(UIImage *img) { rygEditThenArm(ws, img); }];
    }]];
    if (UIPasteboard.generalPasteboard.hasImages) {
        [sheet addAction:[UIAlertAction actionWithTitle:RYGLocalized(@"Paste image / sticker") style:UIAlertActionStyleDefault handler:^(__unused UIAlertAction *a) {
            rygEditThenArm(ws, UIPasteboard.generalPasteboard.image);
        }]];
    }
    [sheet addAction:[UIAlertAction actionWithTitle:RYGLocalized(@"Cancel") style:UIAlertActionStyleCancel handler:nil]];

    [rygDoodleTopPresenter() presentViewController:sheet animated:YES completion:nil];
}

%end

%end

%ctor {
    if ([RYGUtils getBoolPref:@"ryg_doodle_image_enabled"]) %init(RYGDoodleImageGroup);
}
