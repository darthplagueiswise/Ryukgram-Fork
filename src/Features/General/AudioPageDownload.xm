// Audio page download — injects a button next to share/save on the reels
// audio detail page header bar. Routes through SCIDownloadMenu (gallery / share).

#import "../../Utils.h"
#import "../../InstagramHeaders.h"
#import "../../SCIChrome.h"
#import "../../Downloader/Download.h"
#import "../../UI/SCIDownloadMenu.h"
#import "../../UI/SCIIcon.h"
#import "../../SCIDashParser.h"
#import "../../Gallery/SCIGalleryFile.h"
#import "../../Gallery/SCIGallerySaveMetadata.h"
#import "../../ActionButton/SCIMediaActions.h"
#import <objc/runtime.h>
#import <objc/message.h>
#import <substrate.h>

#define SCI_AUDIOPAGE_DL_TAG 1351

typedef id (*SCIMsgSendId)(id, SEL);

static inline id sciAPCall(id obj, SEL sel) {
    if (!obj || ![obj respondsToSelector:sel]) return nil;
    return ((SCIMsgSendId)objc_msgSend)(obj, sel);
}

static id sciAPReadIvar(id obj, const char *name) {
    if (!obj || !name) return nil;
    Class cls = [obj class];
    while (cls && cls != [NSObject class]) {
        Ivar iv = class_getInstanceVariable(cls, name);
        if (iv) return object_getIvar(obj, iv);
        cls = class_getSuperclass(cls);
    }
    return nil;
}

static NSURL *sciAPProbeURL(id obj, NSArray<NSString *> *selectors) {
    if (!obj) return nil;
    for (NSString *name in selectors) {
        SEL s = NSSelectorFromString(name);
        if (![obj respondsToSelector:s]) continue;
        id v = nil;
        @try { v = ((SCIMsgSendId)objc_msgSend)(obj, s); } @catch (__unused id e) { continue; }
        if ([v isKindOfClass:[NSURL class]]) return v;
        if ([v isKindOfClass:[NSString class]] && [(NSString *)v length] > 0) {
            NSURL *u = [NSURL URLWithString:v];
            if (u) return u;
        }
    }
    return nil;
}

static NSString *sciAPProbeString(id obj, NSArray<NSString *> *selectors) {
    if (!obj) return nil;
    for (NSString *name in selectors) {
        SEL s = NSSelectorFromString(name);
        if (![obj respondsToSelector:s]) continue;
        id v = nil;
        @try { v = ((SCIMsgSendId)objc_msgSend)(obj, s); } @catch (__unused id e) { continue; }
        if ([v isKindOfClass:[NSString class]] && [(NSString *)v length] > 0) return v;
    }
    return nil;
}

static IGAudioPageViewController *sciAPFindAudioPageVC(UIView *view) {
    Class cls = NSClassFromString(@"IGAudioPageViewController");
    if (!cls) return nil;
    UIResponder *r = view;
    while (r) {
        if ([r isKindOfClass:cls]) return (IGAudioPageViewController *)r;
        r = [r nextResponder];
    }
    UIViewController *root = view.window.rootViewController;
    while (root.presentedViewController) root = root.presentedViewController;
    if ([root isKindOfClass:cls]) return (IGAudioPageViewController *)root;
    if ([root isKindOfClass:[UINavigationController class]]) {
        UIViewController *top = [(UINavigationController *)root topViewController];
        if ([top isKindOfClass:cls]) return (IGAudioPageViewController *)top;
    }
    return nil;
}

// IGSundialMusicAsset / IGSundialOriginalAudioAsset expose `audioFileUrl`.
// Falls back to the DASH manifest on `_dashManifestData` when missing.
static NSURL *sciAPResolveAudioURL(id asset) {
    if (!asset) return nil;

    NSURL *url = sciAPProbeURL(asset, @[ @"audioFileUrl", @"audioFileURL", @"_progressiveAudioUrl", @"progressiveDownloadURL" ]);
    if (url) return url;

    NSData *manifestData = sciAPReadIvar(asset, "_dashManifestData");
    if ([manifestData isKindOfClass:[NSData class]] && manifestData.length > 0) {
        NSString *xml = [[NSString alloc] initWithData:manifestData encoding:NSUTF8StringEncoding];
        if (xml.length) {
            NSArray *reps = [SCIDashParser parseManifest:xml];
            SCIDashRepresentation *best = [SCIDashParser bestAudioFromRepresentations:reps];
            if (best.url) return best.url;
        }
    }
    return nil;
}

static NSString *sciAPResolveArtist(id asset, IGAudioPageViewController *vc) {
    NSString *s = sciAPProbeString(asset, @[ @"artistDisplayName", @"username", @"displayArtist", @"artist" ]);
    if (s.length) return s;
    id artist = sciAPCall(asset, @selector(artist));
    s = sciAPProbeString(artist, @[ @"username", @"fullName", @"displayName" ]);
    if (s.length) return s;
    id viewModel = sciAPReadIvar(vc, "_viewModel");
    return sciAPProbeString(viewModel, @[ @"title" ]);
}

static NSString *sciAPResolveAudioId(id asset, IGAudioPageViewController *vc) {
    NSString *s = sciAPProbeString(asset, @[ @"audioAssetId", @"pk" ]);
    if (s.length) return s;
    id viewModel = sciAPReadIvar(vc, "_viewModel");
    return sciAPProbeString(viewModel, @[ @"audioId" ]);
}

static void sciAPDownload(NSURL *url, NSString *ext, SCIGallerySaveMetadata *md, NSInteger forceTarget) {
    [SCIDownloadMenu downloadURL:url
                   fileExtension:ext.length ? ext : @"m4a"
                        hudLabel:SCILocalized(@"Download audio")
                        metadata:md
                     forceTarget:forceTarget];
}

static void sciAPPresentMenu(NSURL *url, NSString *ext, SCIGallerySaveMetadata *md) {
    BOOL galleryOn = [SCIUtils getBoolPref:@"sci_gallery_enabled"];

    UIAlertController *sheet = [UIAlertController
        alertControllerWithTitle:SCILocalized(@"Download audio")
                         message:nil
                  preferredStyle:UIAlertControllerStyleActionSheet];

    [sheet addAction:[UIAlertAction actionWithTitle:SCILocalized(@"Copy audio URL")
                                              style:UIAlertActionStyleDefault
                                            handler:^(__unused UIAlertAction *_) {
        [UIPasteboard generalPasteboard].string = [url absoluteString];
        SCINotifySuccess(SCI_NOTIF_COPY_AUDIO_URL, SCILocalized(@"Copied audio URL"), nil);
    }]];

    [sheet addAction:[UIAlertAction actionWithTitle:SCILocalized(@"Download and share")
                                              style:UIAlertActionStyleDefault
                                            handler:^(__unused UIAlertAction *_) {
        sciAPDownload(url, ext, md, 2);
    }]];

    if (galleryOn) {
        NSString *title = [NSString stringWithFormat:@"%@ %@", SCILocalized(@"Download"), SCILocalized(@"to Gallery")];
        [sheet addAction:[UIAlertAction actionWithTitle:title
                                                  style:UIAlertActionStyleDefault
                                                handler:^(__unused UIAlertAction *_) {
            sciAPDownload(url, ext, md, 1);
        }]];
    }

    [sheet addAction:[UIAlertAction actionWithTitle:SCILocalized(@"Cancel") style:UIAlertActionStyleCancel handler:nil]];

    [topMostController() presentViewController:sheet animated:YES completion:nil];
}

static void sciAPHandleDownload(UIView *button) {
    if (![SCIUtils getBoolPref:@"audio_page_download"]) return;

    IGAudioPageViewController *vc = sciAPFindAudioPageVC(button);
    if (!vc) return;

    id asset = sciAPReadIvar(vc, "_audioAsset")
        ?: sciAPReadIvar(vc, "_music")
        ?: sciAPReadIvar(vc, "_originalAudio");

    NSURL *url = sciAPResolveAudioURL(asset);
    if (!url) {
        [SCIUtils showErrorHUDWithDescription:SCILocalized(@"Could not extract audio URL")];
        return;
    }

    NSString *artist = sciAPResolveArtist(asset, vc) ?: @"audio";
    NSString *audioId = sciAPResolveAudioId(asset, vc);

    SCIGallerySaveMetadata *md = [[SCIGallerySaveMetadata alloc] init];
    md.sourceUsername = artist;
    md.sourceMediaPK = audioId;

    NSString *ext = [[[url path] pathExtension] lowercaseString];
    if (!SCIGalleryExtensionIsAudio(ext)) ext = @"m4a";

    [SCIMediaActions setCurrentFilenameStem:
        [SCIMediaActions filenameStemForUsername:artist contextLabel:@"audio_page"]];

    sciAPPresentMenu(url, ext, md);
}

@interface SCIAudioPageDLTarget : NSObject
+ (instancetype)shared;
- (void)tap:(id)sender;
@end
@implementation SCIAudioPageDLTarget
+ (instancetype)shared {
    static SCIAudioPageDLTarget *t;
    static dispatch_once_t once;
    dispatch_once(&once, ^{ t = [SCIAudioPageDLTarget new]; });
    return t;
}
- (void)tap:(id)sender {
    UIView *btn = [sender isKindOfClass:[UIView class]] ? sender : nil;
    sciAPHandleDownload(btn);
}
@end

static UIImage *sciAPDownloadIcon(CGFloat pointSize) {
    UIImage *img = [SCIIcon imageNamed:@"ig_icon_download_filled_24" pointSize:pointSize];
    if (!img) img = [SCIIcon imageNamed:@"download_filled" pointSize:pointSize];
    if (!img) img = [SCIIcon sfImageNamed:@"arrow.down" pointSize:pointSize weight:UIImageSymbolWeightSemibold];
    return [img imageWithRenderingMode:UIImageRenderingModeAlwaysTemplate];
}

static SCIChromeButton *sciAPInjectButton(UIView *bar) {
    if (!bar) return nil;
    SCIChromeButton *existing = (SCIChromeButton *)[bar viewWithTag:SCI_AUDIOPAGE_DL_TAG];
    if ([existing isKindOfClass:[SCIChromeButton class]]) return existing;

    SCIChromeButton *button = [[SCIChromeButton alloc] initWithSymbol:@"" pointSize:22.0 diameter:32.0];
    button.tag = SCI_AUDIOPAGE_DL_TAG;
    button.translatesAutoresizingMaskIntoConstraints = YES;
    [button addTarget:[SCIAudioPageDLTarget shared]
               action:@selector(tap:)
     forControlEvents:UIControlEventTouchUpInside];
    [bar addSubview:button];
    return button;
}

// Mirror the share/save button's frame + background so the new button blends
// in. Tint stays on labelColor so it follows light/dark.
static void sciAPMatchStyle(SCIChromeButton *button, UIView *anchor) {
    if (!anchor) return;

    UIColor *bg = anchor.backgroundColor;
    if (!bg || CGColorGetAlpha(bg.CGColor) == 0) {
        if (anchor.layer.backgroundColor && CGColorGetAlpha(anchor.layer.backgroundColor) > 0) {
            bg = [UIColor colorWithCGColor:anchor.layer.backgroundColor];
        }
    }
    if (!bg) bg = [UIColor secondarySystemFillColor];
    button.bubbleColor = bg;

    button.iconTint = [UIColor labelColor];
    button.tintColor = [UIColor labelColor];
    button.iconView.tintColor = [UIColor labelColor];

    CGFloat side = MAX(anchor.frame.size.height, 28.0);
    if (side <= 0) side = 32.0;
    button.iconView.image = sciAPDownloadIcon(MIN(22.0, side - 10.0));

    CGRect f = button.frame;
    f.size = CGSizeMake(side, side);
    button.frame = f;
}

static void sciAPLayoutButton(UIView *bar, SCIChromeButton *button) {
    if (!button) return;

    UIView *shareButton = sciAPReadIvar(bar, "shareButton");
    UIView *saveButton  = sciAPReadIvar(bar, "saveButton");

    UIView *anchor = nil;
    if (shareButton && saveButton) {
        anchor = (CGRectGetMinX(saveButton.frame) <= CGRectGetMinX(shareButton.frame)) ? saveButton : shareButton;
    } else {
        anchor = saveButton ?: shareButton;
    }
    if (!anchor || anchor.frame.size.width == 0 || anchor.hidden) {
        button.hidden = YES;
        return;
    }
    button.hidden = NO;

    sciAPMatchStyle(button, anchor);

    CGFloat side = button.frame.size.width;
    CGFloat spacing = 8.0;
    CGFloat x = CGRectGetMinX(anchor.frame) - spacing - side;
    CGFloat y = CGRectGetMidY(anchor.frame) - side / 2.0;
    button.frame = CGRectMake(x, y, side, side);
    [bar bringSubviewToFront:button];
}

static void (*orig_actionBar_layoutSubviews)(UIView *, SEL);
static void new_actionBar_layoutSubviews(UIView *self, SEL _cmd) {
    orig_actionBar_layoutSubviews(self, _cmd);
    if (![SCIUtils getBoolPref:@"audio_page_download"]) {
        UIView *existing = [self viewWithTag:SCI_AUDIOPAGE_DL_TAG];
        if (existing) [existing removeFromSuperview];
        return;
    }
    SCIChromeButton *button = sciAPInjectButton(self);
    sciAPLayoutButton(self, button);
}

%ctor {
    @autoreleasepool {
        Class actionBar = objc_getClass("_TtC16IGAudioPageSwift26IGAudioPageHeaderActionBar");
        if (!actionBar) return;
        SEL sel = @selector(layoutSubviews);
        if (![actionBar instancesRespondToSelector:sel]) return;
        MSHookMessageEx(actionBar, sel,
                        (IMP)new_actionBar_layoutSubviews,
                        (IMP *)&orig_actionBar_layoutSubviews);
    }
}
