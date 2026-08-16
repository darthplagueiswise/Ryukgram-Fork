// Long-press the DM inbox account name to toggle hidden chats in/out of the list.
#import "RYGHiddenChats.h"
#import "../../Utils.h"
#import <objc/runtime.h>
#import <substrate.h>

static const void *kRYGRevealGestureKey = &kRYGRevealGestureKey;

@interface RYGHiddenChatsRevealHandler : NSObject
+ (instancetype)shared;
- (void)handleLongPress:(UILongPressGestureRecognizer *)g;
@end

@implementation RYGHiddenChatsRevealHandler

+ (instancetype)shared {
    static RYGHiddenChatsRevealHandler *h;
    static dispatch_once_t once;
    dispatch_once(&once, ^{ h = [RYGHiddenChatsRevealHandler new]; });
    return h;
}

- (void)handleLongPress:(UILongPressGestureRecognizer *)g {
    if (g.state != UIGestureRecognizerStateBegan) return;
    if ([RYGHiddenChats allThreadIDs].count == 0) return;
    [[[UIImpactFeedbackGenerator alloc] initWithStyle:UIImpactFeedbackStyleMedium] impactOccurred];
    [RYGHiddenChats toggleRevealFrom:nil];
}

@end

static UIView *ryg_findChevronButton(UIView *v) {
    Class target = NSClassFromString(@"IGChevronTitleButton");
    if (!target || !v) return nil;
    if ([v isKindOfClass:target]) return v;
    for (UIView *s in v.subviews) {
        UIView *found = ryg_findChevronButton(s);
        if (found) return found;
    }
    return nil;
}

static void (*orig_headerLayout)(id, SEL);
static void new_headerLayout(id self, SEL _cmd) {
    orig_headerLayout(self, _cmd);
    if (![RYGUtils getBoolPref:@"hidden_chats_reveal_on_hold"]) return;

    UIView *button = ryg_findChevronButton(self);
    if (!button || objc_getAssociatedObject(button, kRYGRevealGestureKey)) return;

    UILongPressGestureRecognizer *lp = [[UILongPressGestureRecognizer alloc]
        initWithTarget:[RYGHiddenChatsRevealHandler shared] action:@selector(handleLongPress:)];
    [button addGestureRecognizer:lp];
    objc_setAssociatedObject(button, kRYGRevealGestureKey, lp, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
}

%ctor {
    Class header = NSClassFromString(@"_TtC33IGDirectInboxNavigationHeaderView33IGDirectInboxNavigationHeaderView");
    if (!header) header = NSClassFromString(@"IGDirectInboxNavigationHeaderView");
    if (header && class_getInstanceMethod(header, @selector(layoutSubviews)))
        MSHookMessageEx(header, @selector(layoutSubviews), (IMP)new_headerLayout, (IMP *)&orig_headerLayout);

    [[NSNotificationCenter defaultCenter] addObserverForName:UIApplicationDidEnterBackgroundNotification
                                                      object:nil queue:nil
                                                  usingBlock:^(__unused NSNotification *n) {
        [RYGHiddenChats handleAppBackground];
    }];
}
