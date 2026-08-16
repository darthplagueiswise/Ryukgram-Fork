// Audio page download — injects a button next to share/save on the reels
// audio detail page header bar. Routes through RYGDownloadMenu (gallery / share).

#import "../../Utils.h"
#import "../../InstagramHeaders.h"
#import "../../RYGChrome.h"
#import "../../Downloader/Download.h"
#import "../../UI/RYGDownloadMenu.h"
#import "../../UI/RYGIcon.h"
#import "../../RYGDashParser.h"
#import "../../Gallery/RYGGalleryFile.h"
#import "../../Gallery/RYGGallerySaveMetadata.h"
#import "../../ActionButton/RYGMediaActions.h"
#import <objc/runtime.h>
#import <objc/message.h>
#import <substrate.h>

#define RYG_AUDIOPAGE_DL_TAG 1351

typedef id (*RYGMsgSendId)(id, SEL);

static inline id rygAPCall(id obj, SEL sel) {
    if (!obj || ![obj respondsToSelector:sel]) return nil;
    return ((RYGMsgSendId)objc_msgSend)(obj, sel);
}

static id rygAPReadIvar(id obj, const char *name) {
    if (!obj || !name) return nil;
    Class cls = [obj class];
    while (cls && cls != [NSObject class]) {
        Ivar iv = class_getInstanceVariable(cls, name);
        if (iv) return object_getIvar(obj, iv);
        cls = class_getSuperclass(cls);
    }
    return nil;
}

static NSURL *rygAPProbeURL(id obj, NSArray<NSString *> *selectors) {
    if (!obj) return nil;
    for (NSString *name in selectors) {
        SEL s = NSSelectorFromString(name);
        if (![obj respondsToSelector:s]) continue;
        id v = nil;
        @try { v = ((RYGMsgSendId)objc_msgSend)(obj, s); } @catch (__unused id e) { continue; }
        if ([v isKindOfClass:[NSURL class]]) return v;
        if ([v isKindOfClass:[NSString class]] && [(NSString *)v length] > 0) {
            NSURL *u = [NSURL URLWithString:v];
            if (u) return u;
        }
    }
    return nil;
}

static NSString *rygAPProbeString(id obj, NSArray<NSString *> *selectors) {
    if (!obj) return nil;
    for (NSString *name in selectors) {
        SEL s = NSSelectorFromString(name);
        if (![obj respondsToSelector:s]) continue;
        id v = nil;
        @try { v = ((RYGMsgSendId)objc_msgSend)(obj, s); } @catch (__unused id e) { continue; }
        if ([v isKindOfClass:[NSString class]] && [(NSString *)v length] > 0) return v;
    }
    return nil;
}

static IGAudioPageViewController *rygAPFindAudioPageVC(UIView *view) {
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
static NSURL *rygAPResolveAudioURL(id asset) {
    if (!asset) return nil;

    NSURL *url = rygAPProbeURL(asset, @[ @"audioFileUrl", @"audioFileURL", @"_progressiveAudioUrl", @"progressiveDownloadURL" ]);
    if (url) return url;

    NSData *manifestData = rygAPReadIvar(asset, "_dashManifestData");
    if ([manifestData isKindOfClass:[NSData class]] && manifestData.length > 0) {
        NSString *xml = [[NSString alloc] initWithData:manifestData encoding:NSUTF8StringEncoding];
        if (xml.length) {
            NSArray *reps = [RYGDashParser parseManifest:xml];
            RYGDashRepresentation *best = [RYGDashParser bestAudioFromRepresentations:reps];
            if (best.url) return best.url;
        }
    }
    return nil;
}

static NSString *rygAPResolveArtist(id asset, IGAudioPageViewController *vc) {
    NSString *s = rygAPProbeString(asset, @[ @"artistDisplayName", @"username", @"displayArtist", @"artist" ]);
    if (s.length) return s;
    id artist = rygAPCall(asset, @selector(artist));
    s = rygAPProbeString(artist, @[ @"username", @"fullName", @"displayName" ]);
    if (s.length) return s;
    id viewModel = rygAPReadIvar(vc, "_viewModel");
    return rygAPProbeString(viewModel, @[ @"title" ]);
}

static NSString *rygAPResolveAudioId(id asset, IGAudioPageViewController *vc) {
    NSString *s = rygAPProbeString(asset, @[ @"audioAssetId", @"pk" ]);
    if (s.length) return s;
    id viewModel = rygAPReadIvar(vc, "_viewModel");
    return rygAPProbeString(viewModel, @[ @"audioId" ]);
}

static void rygAPDownload(NSURL *url, NSString *ext, RYGGallerySaveMetadata *md, NSInteger forceTarget) {
    [RYGDownloadMenu downloadURL:url
                   fileExtension:ext.length ? ext : @"m4a"
                        hudLabel:RYGLocalized(@"Download audio")
                        metadata:md
                     forceTarget:forceTarget];
}

static void rygAPPresentMenu(NSURL *url, NSString *ext, RYGGallerySaveMetadata *md) {
    BOOL galleryOn = [RYGUtils getBoolPref:@"ryg_gallery_enabled"];

    UIAlertController *sheet = [UIAlertController
        alertControllerWithTitle:RYGLocalized(@"Download audio")
                         message:nil
                  preferredStyle:UIAlertControllerStyleActionSheet];

    [sheet addAction:[UIAlertAction actionWithTitle:RYGLocalized(@"Copy audio URL")
                                              style:UIAlertActionStyleDefault
                                            handler:^(__unused UIAlertAction *_) {
        [UIPasteboard generalPasteboard].string = [url absoluteString];
        RYGNotifySuccess(RYG_NOTIF_COPY_AUDIO_URL, RYGLocalized(@"Copied audio URL"), nil);
    }]];

    [sheet addAction:[UIAlertAction actionWithTitle:RYGLocalized(@"Download and share")
                                              style:UIAlertActionStyleDefault
                                            handler:^(__unused UIAlertAction *_) {
        rygAPDownload(url, ext, md, 2);
    }]];

    if (galleryOn) {
        NSString *title = [NSString stringWithFormat:@"%@ %@", RYGLocalized(@"Download"), RYGLocalized(@"to Gallery")];
        [sheet addAction:[UIAlertAction actionWithTitle:title
                                                  style:UIAlertActionStyleDefault
                                                handler:^(__unused UIAlertAction *_) {
            rygAPDownload(url, ext, md, 1);
        }]];
    }

    [sheet addAction:[UIAlertAction actionWithTitle:RYGLocalized(@"Cancel") style:UIAlertActionStyleCancel handler:nil]];

    [topMostController() presentViewController:sheet animated:YES completion:nil];
}

static void rygAPHandleDownload(UIView *button) {
    if (![RYGUtils getBoolPref:@"audio_page_download"]) return;

    IGAudioPageViewController *vc = rygAPFindAudioPageVC(button);
    if (!vc) return;

    id asset = rygAPReadIvar(vc, "_audioAsset")
        ?: rygAPReadIvar(vc, "_music")
        ?: rygAPReadIvar(vc, "_originalAudio");

    NSURL *url = rygAPResolveAudioURL(asset);
    if (!url) {
        [RYGUtils showErrorHUDWithDescription:RYGLocalized(@"Could not extract audio URL")];
        return;
    }

    NSString *artist = rygAPResolveArtist(asset, vc) ?: @"audio";
    NSString *audioId = rygAPResolveAudioId(asset, vc);

    RYGGallerySaveMetadata *md = [[RYGGallerySaveMetadata alloc] init];
    md.sourceUsername = artist;
    md.sourceMediaPK = audioId;

    NSString *ext = [[[url path] pathExtension] lowercaseString];
    if (!RYGGalleryExtensionIsAudio(ext)) ext = @"m4a";

    [RYGMediaActions setCurrentFilenameStem:
        [RYGMediaActions filenameStemForUsername:artist contextLabel:@"audio_page"]];

    rygAPPresentMenu(url, ext, md);
}

@interface RYGAudioPageDLTarget : NSObject
+ (instancetype)shared;
- (void)tap:(id)sender;
@end
@implementation RYGAudioPageDLTarget
+ (instancetype)shared {
    static RYGAudioPageDLTarget *t;
    static dispatch_once_t once;
    dispatch_once(&once, ^{ t = [RYGAudioPageDLTarget new]; });
    return t;
}
- (void)tap:(id)sender {
    UIView *btn = [sender isKindOfClass:[UIView class]] ? sender : nil;
    rygAPHandleDownload(btn);
}
@end

static UIImage *rygAPDownloadIcon(CGFloat pointSize) {
    UIImage *img = [RYGIcon imageNamed:@"ig_icon_download_filled_24" pointSize:pointSize];
    if (!img) img = [RYGIcon imageNamed:@"download_filled" pointSize:pointSize];
    if (!img) img = [RYGIcon sfImageNamed:@"arrow.down" pointSize:pointSize weight:UIImageSymbolWeightSemibold];
    return [img imageWithRenderingMode:UIImageRenderingModeAlwaysTemplate];
}

static RYGChromeButton *rygAPInjectButton(UIView *bar) {
    if (!bar) return nil;
    RYGChromeButton *existing = (RYGChromeButton *)[bar viewWithTag:RYG_AUDIOPAGE_DL_TAG];
    if ([existing isKindOfClass:[RYGChromeButton class]]) return existing;

    RYGChromeButton *button = [[RYGChromeButton alloc] initWithSymbol:@"" pointSize:22.0 diameter:32.0];
    button.tag = RYG_AUDIOPAGE_DL_TAG;
    button.translatesAutoresizingMaskIntoConstraints = YES;
    [button addTarget:[RYGAudioPageDLTarget shared]
               action:@selector(tap:)
     forControlEvents:UIControlEventTouchUpInside];
    [bar addSubview:button];
    return button;
}

// Mirror the share/save button's frame + background so the new button blends
// in. Tint stays on labelColor so it follows light/dark.
static void rygAPMatchStyle(RYGChromeButton *button, UIView *anchor) {
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
    button.iconView.image = rygAPDownloadIcon(MIN(22.0, side - 10.0));

    CGRect f = button.frame;
    f.size = CGSizeMake(side, side);
    button.frame = f;
}

static void rygAPLayoutButton(UIView *bar, RYGChromeButton *button) {
    if (!button) return;

    UIView *shareButton = rygAPReadIvar(bar, "shareButton");
    UIView *saveButton  = rygAPReadIvar(bar, "saveButton");

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

    rygAPMatchStyle(button, anchor);

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
    if (![RYGUtils getBoolPref:@"audio_page_download"]) {
        UIView *existing = [self viewWithTag:RYG_AUDIOPAGE_DL_TAG];
        if (existing) [existing removeFromSuperview];
        return;
    }
    RYGChromeButton *button = rygAPInjectButton(self);
    rygAPLayoutButton(self, button);
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
