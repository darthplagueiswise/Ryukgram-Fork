// Shortcut button injected into the home feed header. The header is a 0x0 anchor
// with dead slot-frame methods, so on its layoutSubviews we place our chrome
// button next to a native one — robust to which buttons an account/A-B shows.

#import "../../Utils.h"
#import "../../RYGChrome.h"
#import "RYGHomeShortcutCatalog.h"
#import "RYGHomeShortcutBadges.h"
#import <objc/runtime.h>
#import <substrate.h>

static const void *kBtnKey = &kBtnKey;
static const void *kFrameKey = &kFrameKey;

static CGFloat const kPointSize = 20.0;
static CGFloat const kGap = 8.0;

static NSHashTable<UIView *> *rygHeaders(void) {
    static NSHashTable *hosts; static dispatch_once_t once;
    dispatch_once(&once, ^{ hosts = [NSHashTable weakObjectsHashTable]; });
    return hosts;
}

static UIView *rygGetBtn(id header, SEL sel) {
    if (![header respondsToSelector:sel]) return nil;
    UIView *v = ((UIView *(*)(id, SEL))objc_msgSend)(header, sel);
    return [v isKindOfClass:UIView.class] ? v : nil;
}

static BOOL rygUsable(UIView *b) {
    return b && !b.hidden && b.alpha > 0.01 && b.superview && b.bounds.size.width >= 1 && b.bounds.size.height >= 1;
}

static void rygPlace(UIView *header) {
    UIButton *button = objc_getAssociatedObject(header, kBtnKey);
    NSArray<NSString *> *ids = [RYGHomeShortcutCatalog enabledActionIDs];
    if (!ids.count) { button.hidden = YES; return; }
    if (header.bounds.size.width < 1) return;

    // Window coords lie mid push/pop — the header rides an animated offset.
    UIView *anchor = nil; CGRect anchorHdr = CGRectZero;
    SEL preferred[] = { @selector(createButton), @selector(logoButton) };
    for (int i = 0; i < 2 && !anchor; i++) {
        UIView *b = rygGetBtn(header, preferred[i]);
        if (!rygUsable(b)) continue;
        anchor = b; anchorHdr = [b convertRect:b.bounds toView:header];
    }
    if (!anchor) {
        SEL cands[] = { @selector(quicksnapButton), @selector(friendsMapButton), @selector(homecomingButton),
                        @selector(storiesTabButton), @selector(streamsButton), @selector(yourAlgoButton),
                        @selector(activityButton), @selector(directButton) };
        for (int i = 0; i < 8; i++) {
            UIView *b = rygGetBtn(header, cands[i]);
            if (!rygUsable(b)) continue;
            CGRect r = [b convertRect:b.bounds toView:header];
            if (!anchor || r.origin.x < anchorHdr.origin.x) { anchor = b; anchorHdr = r; }
        }
    }

    // iPad's header exposes no native buttons — fall back to pinning at its trailing edge.
    CGFloat hdrH = MAX(header.bounds.size.height, 44.0);
    CGFloat side = anchor ? MAX(28.0, anchorHdr.size.height) : MAX(28.0, MIN(40.0, hdrH * 0.5));
    if (!button) {
        RYGChromeButton *chrome = [[RYGChromeButton alloc] initWithSymbol:[RYGHomeShortcutCatalog currentSymbol] pointSize:kPointSize diameter:side];
        chrome.translatesAutoresizingMaskIntoConstraints = YES;
        chrome.iconTint = UIColor.labelColor;
        chrome.bubbleColor = UIColor.clearColor;
        chrome.adjustsImageWhenHighlighted = NO;
        chrome.accessibilityLabel = @"RyukGram";
        button = chrome;
        objc_setAssociatedObject(header, kBtnKey, button, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    }
    UIView *parent = anchor ? anchor.superview : header;
    if (button.superview != parent) { [button removeFromSuperview]; [parent addSubview:button]; }

    [RYGHomeShortcutCatalog configureButton:(RYGChromeButton *)button];
    [RYGHomeShortcutCatalog updateBadgeOnButton:(RYGChromeButton *)button];
    button.hidden = NO;
    button.alpha = 1.0;

    CGRect targetHdr;
    if (anchor) {
        BOOL anchorOnLeft = CGRectGetMidX(anchorHdr) < header.bounds.size.width * 0.5;
        CGFloat x = anchorOnLeft ? CGRectGetMaxX(anchorHdr) + kGap : CGRectGetMinX(anchorHdr) - kGap - side;
        targetHdr = CGRectMake(x, CGRectGetMidY(anchorHdr) - side / 2.0, side, side);
    } else {
        targetHdr = CGRectMake(header.bounds.size.width - kGap - side, (hdrH - side) / 2.0, side, side);
    }
    NSValue *last = objc_getAssociatedObject(button, kFrameKey);
    if (last && CGRectEqualToRect(last.CGRectValue, targetHdr) && button.superview == parent) return;
    objc_setAssociatedObject(button, kFrameKey, [NSValue valueWithCGRect:targetHdr], OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    button.frame = [parent convertRect:targetHdr fromView:header];
    [parent bringSubviewToFront:button];
}

static void (*orig_layout)(id, SEL);
static void new_layout(id self, SEL _cmd) {
    orig_layout(self, _cmd);
    [rygHeaders() addObject:self];
    rygPlace(self);
}

%ctor {
    if (![RYGUtils getBoolPref:kRYGHomeShortcutEnabledPrefKey]) return;
    Class c = NSClassFromString(@"_TtC16IGHomeFeedHeader20IGHomeFeedHeaderView");
    if (c && class_getInstanceMethod(c, @selector(layoutSubviews)))
        MSHookMessageEx(c, @selector(layoutSubviews), (IMP)new_layout, (IMP *)&orig_layout);

    void (^refresh)(NSNotification *) = ^(__unused NSNotification *n) {
        for (UIView *h in rygHeaders().allObjects) {
            [RYGHomeShortcutCatalog invalidateButton:objc_getAssociatedObject(h, kBtnKey)];
            [h setNeedsLayout];
        }
    };
    [NSNotificationCenter.defaultCenter addObserverForName:RYGHomeShortcutConfigDidChangeNotification object:nil queue:NSOperationQueue.mainQueue usingBlock:refresh];
    [NSNotificationCenter.defaultCenter addObserverForName:RYGHomeShortcutBadgesDidChangeNotification object:nil queue:NSOperationQueue.mainQueue usingBlock:refresh];
}
