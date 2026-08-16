// Confirmation dialog before pull-to-refresh wipes preserved unsent
// messages. Gated by keep_deleted_message + warn_refresh_clears_preserved.
#import "../../Utils.h"
#import "../../InstagramHeaders.h"
#import <objc/runtime.h>
#import <objc/message.h>
#import <substrate.h>

extern NSMutableSet *rygGetPreservedIds(void);
extern void rygClearPreservedIds(void);

static BOOL rygRefreshConfirmInFlight = NO;
static BOOL rygRefreshAlertVisible = NO;

static UIRefreshControl *rygFindRefreshControl(UIViewController *vc) {
    Class igRC = NSClassFromString(@"IGRefreshControl");
    NSMutableArray *stack = [NSMutableArray arrayWithObject:vc.view];
    while (stack.count > 0) {
        UIView *v = stack.lastObject;
        [stack removeLastObject];
        if ((igRC && [v isKindOfClass:igRC]) || [v isKindOfClass:[UIRefreshControl class]]) {
            return (UIRefreshControl *)v;
        }
        for (UIView *sub in v.subviews) [stack addObject:sub];
    }
    return nil;
}

// Cancel path resets the refresh control's state and animates the scroll
// view's contentInset back to its idle value (IG leaves it expanded otherwise).
static void rygCancelRefresh(UIViewController *vc) {
    UIRefreshControl *rc = rygFindRefreshControl(vc);
    if (!rc) return;

    Ivar stateIvar = class_getInstanceVariable([rc class], "_refreshState");
    if (stateIvar) {
        ptrdiff_t off = ivar_getOffset(stateIvar);
        *(NSInteger *)((char *)(__bridge void *)rc + off) = 0;
    }
    Ivar animIvar = class_getInstanceVariable([rc class], "_swiftAnimationInfo");
    if (animIvar) object_setIvar(rc, animIvar, nil);
    if ([rc respondsToSelector:@selector(endRefreshing)]) [rc endRefreshing];

    SEL didEnd = NSSelectorFromString(@"refreshControlDidEndFinishLoadingAnimation:");
    if ([vc respondsToSelector:didEnd]) {
        ((void(*)(id, SEL, id))objc_msgSend)(vc, didEnd, rc);
    }

    UIScrollView *scroll = nil;
    UIView *cur = rc.superview;
    while (cur) {
        if ([cur isKindOfClass:[UIScrollView class]]) { scroll = (UIScrollView *)cur; break; }
        cur = cur.superview;
    }
    if (scroll) {
        SEL idleSel = NSSelectorFromString(@"idleTopContentInsetForRefreshControl:");
        CGFloat idleInset = scroll.contentInset.top;
        if ([vc respondsToSelector:idleSel]) {
            idleInset = ((CGFloat(*)(id, SEL, id))objc_msgSend)(vc, idleSel, rc);
        }
        UIEdgeInsets insets = scroll.contentInset;
        insets.top = idleInset;
        [UIView animateWithDuration:0.25 animations:^{
            scroll.contentInset = insets;
            CGPoint o = scroll.contentOffset;
            if (o.y < -idleInset) o.y = -idleInset;
            scroll.contentOffset = o;
        }];
    }
}

static void (*orig_pullToRefresh)(id self, SEL _cmd);
static void new_pullToRefresh(id self, SEL _cmd) {
    if (rygRefreshConfirmInFlight ||
        ![RYGUtils getBoolPref:@"keep_deleted_message"] ||
        ![RYGUtils getBoolPref:@"warn_refresh_clears_preserved"]) {
        orig_pullToRefresh(self, _cmd);
        return;
    }

    // Drop re-entrant calls — IG fires this repeatedly during the gesture.
    if (rygRefreshAlertVisible) return;

    NSUInteger count = rygGetPreservedIds().count;
    if (count == 0) {
        orig_pullToRefresh(self, _cmd);
        return;
    }

    UIViewController *vc = (UIViewController *)self;
    NSString *fmt = (count == 1)
        ? RYGLocalized(@"Refreshing the DMs tab will clear %lu preserved unsent message. This cannot be undone.")
        : RYGLocalized(@"Refreshing the DMs tab will clear %lu preserved unsent messages. This cannot be undone.");
    NSString *msg = [NSString stringWithFormat:fmt, (unsigned long)count];

    UIAlertController *alert = [UIAlertController alertControllerWithTitle:RYGLocalized(@"Clear preserved messages?")
                                                                  message:msg
                                                           preferredStyle:UIAlertControllerStyleAlert];

    __weak UIViewController *weakSelf = vc;
    [alert addAction:[UIAlertAction actionWithTitle:RYGLocalized(@"Cancel") style:UIAlertActionStyleCancel
                                            handler:^(UIAlertAction *a) {
        rygCancelRefresh(weakSelf);
        rygRefreshAlertVisible = NO;
    }]];

    [alert addAction:[UIAlertAction actionWithTitle:RYGLocalized(@"Refresh") style:UIAlertActionStyleDestructive
                                            handler:^(UIAlertAction *a) {
        rygRefreshAlertVisible = NO;
        id strongSelf = weakSelf;
        if (!strongSelf) return;
        rygClearPreservedIds();
        rygRefreshConfirmInFlight = YES;
        ((void(*)(id, SEL))objc_msgSend)(strongSelf, _cmd);
        rygRefreshConfirmInFlight = NO;
    }]];

    rygRefreshAlertVisible = YES;
    UIViewController *top = [UIApplication sharedApplication].keyWindow.rootViewController;
    while (top.presentedViewController) top = top.presentedViewController;
    [top presentViewController:alert animated:YES completion:nil];
}

%ctor {
    Class cls = NSClassFromString(@"IGDirectInboxViewController");
    if (!cls) return;
    SEL sel = NSSelectorFromString(@"pullToRefreshIfPossible");
    if (!class_getInstanceMethod(cls, sel))
        sel = NSSelectorFromString(@"_pullToRefreshIfPossible");
    if (class_getInstanceMethod(cls, sel))
        MSHookMessageEx(cls, sel, (IMP)new_pullToRefresh, (IMP *)&orig_pullToRefresh);
}
