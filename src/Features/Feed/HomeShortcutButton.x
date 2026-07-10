// Shortcut button injected into the home feed header (IG 437). The header is a 0x0
// anchor with dead slot-frame methods, so on its layoutSubviews we place our
// SCIChromeButton in window space next to a settled native button — robust to which
// buttons a given account/A-B shows.

#import "../../Utils.h"
#import "../../SCIChrome.h"
#import "../../UI/SCIIcon.h"
#import "SCIHomeShortcutCatalog.h"
#import <objc/runtime.h>
#import <substrate.h>

static const void *kBtnKey = &kBtnKey;
static const void *kSigKey = &kSigKey;
static const void *kFrameKey = &kFrameKey;

static CGFloat const kPointSize = 20.0;
static CGFloat const kGap = 8.0;

static NSHashTable<UIView *> *sciHeaders(void) {
    static NSHashTable *hosts; static dispatch_once_t once;
    dispatch_once(&once, ^{ hosts = [NSHashTable weakObjectsHashTable]; });
    return hosts;
}

static UIView *sciGetBtn(id header, SEL sel) {
    if (![header respondsToSelector:sel]) return nil;
    UIView *v = ((UIView *(*)(id, SEL))objc_msgSend)(header, sel);
    return [v isKindOfClass:UIView.class] ? v : nil;
}

static NSString *sciSymbol(NSArray<NSString *> *ids) {
    NSString *userIcon = [SCIUtils getStringPref:kSCIHomeShortcutIconPrefKey];
    if (userIcon.length && ![userIcon isEqualToString:@"auto"]) return userIcon;
    if (ids.count == 1) {
        SCIHomeShortcutAction *a = [SCIHomeShortcutCatalog actionForID:ids.firstObject];
        return a.symbol.length ? a.symbol : @"ellipsis.circle.fill";
    }
    return @"ellipsis.circle.fill";
}

static void sciWire(UIButton *button, NSArray<NSString *> *ids) {
    NSString *sig = [NSString stringWithFormat:@"%@|%@", sciSymbol(ids), [ids componentsJoinedByString:@","]];
    if ([objc_getAssociatedObject(button, kSigKey) isEqualToString:sig]) return;
    objc_setAssociatedObject(button, kSigKey, sig, OBJC_ASSOCIATION_COPY_NONATOMIC);

    button.menu = nil;
    button.showsMenuAsPrimaryAction = NO;
    [button removeActionForIdentifier:@"sci.home.shortcut" forControlEvents:UIControlEventTouchUpInside];

    if ([button isKindOfClass:SCIChromeButton.class]) {
        SCIChromeButton *chrome = (SCIChromeButton *)button;
        chrome.iconTint = UIColor.labelColor;
        chrome.symbolPointSize = kPointSize;
        chrome.symbolName = sciSymbol(ids);
    }

    __weak UIButton *wb = button;
    if (ids.count == 1) {
        NSString *actionID = ids.firstObject;
        UIAction *tap = [UIAction actionWithTitle:@"" image:nil identifier:@"sci.home.shortcut" handler:^(__unused UIAction *ac) {
            [SCIHomeShortcutCatalog fireActionID:actionID contextView:wb];
        }];
        [button addAction:tap forControlEvents:UIControlEventTouchUpInside];
    } else {
        NSMutableArray<UIAction *> *items = [NSMutableArray array];
        for (NSString *actionID in ids) {
            SCIHomeShortcutAction *e = [SCIHomeShortcutCatalog actionForID:actionID];
            if (!e) continue;
            UIImage *icon = e.symbol.length ? [SCIIcon imageNamed:e.symbol pointSize:18.0 weight:UIImageSymbolWeightRegular] : nil;
            [items addObject:[UIAction actionWithTitle:(e.title ?: actionID) image:icon identifier:nil handler:^(__unused UIAction *ac) {
                [SCIHomeShortcutCatalog fireActionID:actionID contextView:wb];
            }]];
        }
        button.menu = [UIMenu menuWithTitle:@"" children:items];
        button.showsMenuAsPrimaryAction = YES;
    }
}

static void sciPlace(UIView *header) {
    UIButton *button = objc_getAssociatedObject(header, kBtnKey);
    NSArray<NSString *> *ids = [SCIHomeShortcutCatalog enabledActionIDs];
    if (!ids.count) { button.hidden = YES; return; }

    UIWindow *win = header.window;
    if (!win) { button.hidden = YES; return; }
    CGFloat halfW = win.bounds.size.width * 0.5;

    // Left cluster: prefer the + (create), else the logo, else the rightmost
    // left-half element. Placed to that anchor's right so it sits by the +.
    UIView *anchor = nil; CGRect anchorWin = CGRectZero;
    SEL preferred[] = { @selector(createButton), @selector(logoButton) };
    for (int i = 0; i < 2 && !anchor; i++) {
        UIView *b = sciGetBtn(header, preferred[i]);
        if (!b || b.hidden || !b.superview || b.bounds.size.width < 1) continue;
        CGRect w = [b convertRect:b.bounds toView:nil];
        if (w.origin.x >= halfW || w.size.height < 1) continue;
        anchor = b; anchorWin = w;
    }
    if (!anchor) {
        SEL cands[] = { @selector(quicksnapButton), @selector(friendsMapButton), @selector(homecomingButton),
                        @selector(activityButton), @selector(directButton) };
        for (int i = 0; i < 5; i++) {
            UIView *b = sciGetBtn(header, cands[i]);
            if (!b || b.hidden || !b.superview || b.bounds.size.width < 1) continue;
            CGRect w = [b convertRect:b.bounds toView:nil];
            if (w.origin.x >= halfW || w.size.height < 1) continue;
            if (!anchor || CGRectGetMaxX(w) > CGRectGetMaxX(anchorWin)) { anchor = b; anchorWin = w; }
        }
    }

    if (!anchor) { button.hidden = YES; return; }

    CGFloat side = MAX(28.0, anchorWin.size.height);
    if (!button) {
        SCIChromeButton *chrome = [[SCIChromeButton alloc] initWithSymbol:sciSymbol(ids) pointSize:kPointSize diameter:side];
        chrome.translatesAutoresizingMaskIntoConstraints = YES;
        chrome.iconTint = UIColor.labelColor;
        chrome.bubbleColor = UIColor.clearColor;
        chrome.adjustsImageWhenHighlighted = NO;
        chrome.accessibilityLabel = @"RyukGram";
        button = chrome;
        objc_setAssociatedObject(header, kBtnKey, button, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    }
    UIView *parent = anchor.superview;
    if (button.superview != parent) { [button removeFromSuperview]; [parent addSubview:button]; }

    sciWire(button, ids);
    button.hidden = NO;
    button.alpha = 1.0;
    CGRect targetWin = CGRectMake(CGRectGetMaxX(anchorWin) + kGap,
                                  CGRectGetMidY(anchorWin) - side / 2.0, side, side);
    NSValue *last = objc_getAssociatedObject(button, kFrameKey);
    if (last && CGRectEqualToRect(last.CGRectValue, targetWin) && button.superview == parent) return;
    objc_setAssociatedObject(button, kFrameKey, [NSValue valueWithCGRect:targetWin], OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    button.frame = [parent convertRect:targetWin fromView:nil];
    [parent bringSubviewToFront:button];
}

static void (*orig_layout)(id, SEL);
static void new_layout(id self, SEL _cmd) {
    orig_layout(self, _cmd);
    [sciHeaders() addObject:self];
    sciPlace(self);
}

%ctor {
    if (![SCIUtils getBoolPref:kSCIHomeShortcutEnabledPrefKey]) return;
    Class c = NSClassFromString(@"_TtC16IGHomeFeedHeader20IGHomeFeedHeaderView");
    if (c && class_getInstanceMethod(c, @selector(layoutSubviews)))
        MSHookMessageEx(c, @selector(layoutSubviews), (IMP)new_layout, (IMP *)&orig_layout);

    [NSNotificationCenter.defaultCenter addObserverForName:SCIHomeShortcutConfigDidChangeNotification object:nil queue:NSOperationQueue.mainQueue usingBlock:^(__unused NSNotification *n) {
        for (UIView *h in sciHeaders().allObjects) {
            objc_setAssociatedObject(objc_getAssociatedObject(h, kBtnKey), kSigKey, nil, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
            [h setNeedsLayout];
        }
    }];
}
