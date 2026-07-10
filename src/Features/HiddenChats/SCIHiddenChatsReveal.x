// Long-press the DM inbox account name to toggle hidden chats in/out of the list.
#import "SCIHiddenChats.h"
#import "../../Utils.h"
#import <objc/runtime.h>
#import <substrate.h>

static const void *kSCIRevealGestureKey = &kSCIRevealGestureKey;

@interface SCIHiddenChatsRevealHandler : NSObject
+ (instancetype)shared;
- (void)handleLongPress:(UILongPressGestureRecognizer *)g;
@end

@implementation SCIHiddenChatsRevealHandler

+ (instancetype)shared {
    static SCIHiddenChatsRevealHandler *h;
    static dispatch_once_t once;
    dispatch_once(&once, ^{ h = [SCIHiddenChatsRevealHandler new]; });
    return h;
}

- (void)handleLongPress:(UILongPressGestureRecognizer *)g {
    if (g.state != UIGestureRecognizerStateBegan) return;
    if ([SCIHiddenChats allThreadIDs].count == 0) return;
    [[[UIImpactFeedbackGenerator alloc] initWithStyle:UIImpactFeedbackStyleMedium] impactOccurred];
    [SCIHiddenChats toggleRevealFrom:nil];
}

@end

static UIView *sci_findChevronButton(UIView *v) {
    Class target = NSClassFromString(@"IGChevronTitleButton");
    if (!target || !v) return nil;
    if ([v isKindOfClass:target]) return v;
    for (UIView *s in v.subviews) {
        UIView *found = sci_findChevronButton(s);
        if (found) return found;
    }
    return nil;
}

static void (*orig_headerLayout)(id, SEL);
static void new_headerLayout(id self, SEL _cmd) {
    orig_headerLayout(self, _cmd);
    if (![SCIUtils getBoolPref:@"hidden_chats_reveal_on_hold"]) return;

    UIView *button = sci_findChevronButton(self);
    if (!button || objc_getAssociatedObject(button, kSCIRevealGestureKey)) return;

    UILongPressGestureRecognizer *lp = [[UILongPressGestureRecognizer alloc]
        initWithTarget:[SCIHiddenChatsRevealHandler shared] action:@selector(handleLongPress:)];
    [button addGestureRecognizer:lp];
    objc_setAssociatedObject(button, kSCIRevealGestureKey, lp, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
}

%ctor {
    Class header = NSClassFromString(@"_TtC33IGDirectInboxNavigationHeaderView33IGDirectInboxNavigationHeaderView");
    if (!header) header = NSClassFromString(@"IGDirectInboxNavigationHeaderView");
    if (header && class_getInstanceMethod(header, @selector(layoutSubviews)))
        MSHookMessageEx(header, @selector(layoutSubviews), (IMP)new_headerLayout, (IMP *)&orig_headerLayout);

    [[NSNotificationCenter defaultCenter] addObserverForName:UIApplicationDidEnterBackgroundNotification
                                                      object:nil queue:nil
                                                  usingBlock:^(__unused NSNotification *n) {
        [SCIHiddenChats handleAppBackground];
    }];
}
