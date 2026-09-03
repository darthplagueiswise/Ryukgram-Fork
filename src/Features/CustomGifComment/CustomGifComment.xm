// Custom GIF in comments — long-press the comments composer GIF button to
// paste a Giphy URL/ID and post it as a sticker comment.

#import <UIKit/UIKit.h>
#import "../../Utils.h"
#import "../../InstagramHeaders.h"
#import <objc/runtime.h>
#import <objc/message.h>

static char kRYGGifLPKey;

@interface RYGGifCommentTarget : NSObject
+ (instancetype)shared;
- (void)handleLongPress:(UILongPressGestureRecognizer *)gr;
@end

#pragma mark - Helpers

static UIView *ryg_findGifButton(UIView *root) {
    if ([root.accessibilityIdentifier isEqualToString:@"gif-button"]) return root;
    for (UIView *sub in root.subviews) {
        UIView *r = ryg_findGifButton(sub);
        if (r) return r;
    }
    return nil;
}

static UIViewController *ryg_findHostVC(UIView *view) {
    UIResponder *r = view;
    while (r) {
        if ([r isKindOfClass:[UIViewController class]]) return (UIViewController *)r;
        r = [r nextResponder];
    }
    return nil;
}

// giphy.com/gifs/slug-ID, giphy.com/clips/ID, media.giphy.com/media/ID/...,
// or a raw alphanumeric ID.
static NSString *ryg_extractGiphyId(NSString *input) {
    NSString *s = [input stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
    if (!s.length) return nil;

    NSURL *u = [NSURL URLWithString:s];
    NSString *path = u.path;
    if (!path.length) {
        NSCharacterSet *invalid = [[NSCharacterSet alphanumericCharacterSet] invertedSet];
        if ([s rangeOfCharacterFromSet:invalid].location == NSNotFound && s.length >= 5)
            return s;
        return nil;
    }

    NSArray<NSString *> *parts = [path componentsSeparatedByString:@"/"];
    NSMutableArray<NSString *> *clean = [NSMutableArray array];
    for (NSString *p in parts) if (p.length) [clean addObject:p];
    if (!clean.count) return nil;

    NSUInteger mediaIdx = [clean indexOfObject:@"media"];
    if (mediaIdx != NSNotFound && mediaIdx + 1 < clean.count) {
        return clean[mediaIdx + 1];
    }
    NSString *last = clean.lastObject;
    NSRange dot = [last rangeOfString:@"." options:NSBackwardsSearch];
    if (dot.location != NSNotFound) last = [last substringToIndex:dot.location];
    NSRange dash = [last rangeOfString:@"-" options:NSBackwardsSearch];
    if (dash.location != NSNotFound) last = [last substringFromIndex:dash.location + 1];
    NSCharacterSet *invalid = [[NSCharacterSet alphanumericCharacterSet] invertedSet];
    if ([last rangeOfCharacterFromSet:invalid].location != NSNotFound) return nil;
    if (last.length < 5) return nil;
    return last;
}

#pragma mark - IG viewmodel

static id ryg_buildModeConfig(Class cfgCls, NSString *urlStr) {
    if (!cfgCls) return nil;
    SEL cfgInit = @selector(initWithUrl:dataSizeInByte:);
    if ([cfgCls instancesRespondToSelector:cfgInit]) {
        return ((id(*)(id, SEL, id, double))objc_msgSend)([cfgCls alloc], cfgInit, urlStr, 0.0);
    }
    id cfg = ((id(*)(id, SEL))objc_msgSend)([cfgCls alloc], @selector(init));
    Ivar uIvar = class_getInstanceVariable(cfgCls, "_url");
    if (uIvar) object_setIvar(cfg, uIvar, urlStr);
    return cfg;
}

// Mirrors the shape IG's native picker emits (format 2 = giphy GIF).
static id ryg_buildViewModel(NSString *giphyId) {
    Class cfgCls = NSClassFromString(@"IGGiphyGIFModelModeConfig");
    Class imgCls = NSClassFromString(@"IGGiphyImageModel");
    Class vmCls  = NSClassFromString(@"IGDirectAnimatedMediaViewModel");
    if (!cfgCls || !imgCls || !vmCls) return nil;

    NSString *gifURL  = [NSString stringWithFormat:@"https://media.giphy.com/media/%@/giphy.gif",  giphyId];
    NSString *mp4URL  = [NSString stringWithFormat:@"https://media.giphy.com/media/%@/giphy.mp4",  giphyId];
    NSString *webpURL = [NSString stringWithFormat:@"https://media.giphy.com/media/%@/giphy.webp", giphyId];

    id gifCfg  = ryg_buildModeConfig(cfgCls, gifURL);
    id mp4Cfg  = ryg_buildModeConfig(cfgCls, mp4URL);
    id webpCfg = ryg_buildModeConfig(cfgCls, webpURL);

    SEL imgInit = @selector(initWithGifConfig:mp4Config:webpConfig:width:height:);
    if (![imgCls instancesRespondToSelector:imgInit]) return nil;
    id imgModel = ((id(*)(id, SEL, id, id, id, double, double))objc_msgSend)(
        [imgCls alloc], imgInit, gifCfg, mp4Cfg, webpCfg, 200.0, 200.0);

    SEL vmInit = NSSelectorFromString(@"initWithPk:url:cacheIdentifier:width:height:format:backgroundColor:isSticker:imageModel:animatedImageResolver:previewImageSpecifier:creatorUsername:altText:");
    if (![vmCls instancesRespondToSelector:vmInit]) return nil;
    return ((id(*)(id, SEL, id, id, id, double, double, long long, id, BOOL, id, id, id, id, id))objc_msgSend)(
        [vmCls alloc], vmInit,
        giphyId, [NSURL URLWithString:mp4URL], mp4URL,
        200.0, 200.0, 2 /*format*/, nil, NO,
        imgModel, nil, nil, nil, @"");
}

#pragma mark - Long-press handler

@implementation RYGGifCommentTarget

+ (instancetype)shared {
    static RYGGifCommentTarget *t;
    static dispatch_once_t once;
    dispatch_once(&once, ^{ t = [RYGGifCommentTarget new]; });
    return t;
}

- (void)handleLongPress:(UILongPressGestureRecognizer *)gr {
    if (gr.state != UIGestureRecognizerStateBegan) return;

    UIView *btn = gr.view;
    UIView *composerView = btn;
    Class composerCls = NSClassFromString(@"IGCommentComposerView");
    while (composerView && ![composerView isKindOfClass:composerCls]) {
        composerView = composerView.superview;
    }
    if (!composerView) return;

    id composerCtrl = nil;
    @try { composerCtrl = [composerView valueForKey:@"delegate"]; } @catch (__unused id e) {}
    if (!composerCtrl) return;

    UIViewController *host = ryg_findHostVC(composerView);
    if (!host) return;

    UIAlertController *prompt = [UIAlertController
        alertControllerWithTitle:RYGLocalized(@"Paste Giphy Link")
                         message:RYGLocalized(@"Paste a giphy.com URL or media ID")
                  preferredStyle:UIAlertControllerStyleAlert];
    [prompt addTextFieldWithConfigurationHandler:^(UITextField *tf) {
        tf.placeholder = @"https://giphy.com/gifs/...";
        tf.autocapitalizationType = UITextAutocapitalizationTypeNone;
        tf.autocorrectionType = UITextAutocorrectionTypeNo;
        NSString *clip = [UIPasteboard generalPasteboard].string;
        if ([clip rangeOfString:@"giphy" options:NSCaseInsensitiveSearch].location != NSNotFound) {
            tf.text = clip;
        }
    }];
    [prompt addAction:[UIAlertAction actionWithTitle:RYGLocalized(@"Send")
                                               style:UIAlertActionStyleDefault
                                             handler:^(UIAlertAction *_) {
        NSString *gid = ryg_extractGiphyId(prompt.textFields.firstObject.text);
        if (!gid) {
            [RYGUtils showErrorHUDWithDescription:RYGLocalized(@"Invalid Giphy URL")];
            return;
        }
        SEL sel = @selector(gifSelectionViewController:didSelectGIFAnimatedViewModel:);
        if (![composerCtrl respondsToSelector:sel]) {
            [RYGUtils showErrorHUDWithDescription:RYGLocalized(@"Composer doesn't accept GIFs")];
            return;
        }
        id vm = ryg_buildViewModel(gid);
        if (!vm) {
            [RYGUtils showErrorHUDWithDescription:RYGLocalized(@"Failed to build GIF model")];
            return;
        }
        ((void(*)(id, SEL, id, id))objc_msgSend)(composerCtrl, sel, nil, vm);
        RYGNotifySuccess(RYG_NOTIF_GIF_SENT, RYGLocalized(@"GIF inserted"), nil);
    }]];
    [prompt addAction:[UIAlertAction actionWithTitle:RYGLocalized(@"Cancel")
                                               style:UIAlertActionStyleCancel
                                             handler:nil]];
    [host presentViewController:prompt animated:YES completion:nil];
}

@end

#pragma mark - Hook

static void ryg_attachLongPress(UIView *composerView) {
    if (![RYGUtils getBoolPref:@"custom_gif_comment"]) return;
    UIView *btn = ryg_findGifButton(composerView);
    if (!btn) return;
    if (objc_getAssociatedObject(btn, &kRYGGifLPKey)) return;
    UILongPressGestureRecognizer *lp = [[UILongPressGestureRecognizer alloc]
        initWithTarget:[RYGGifCommentTarget shared]
                action:@selector(handleLongPress:)];
    lp.minimumPressDuration = 0.45;
    [btn addGestureRecognizer:lp];
    objc_setAssociatedObject(btn, &kRYGGifLPKey, lp, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
}

%hook IGCommentComposerView
- (void)layoutSubviews {
    %orig;
    ryg_attachLongPress(self);
}
%end
