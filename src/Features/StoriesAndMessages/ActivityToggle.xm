// Activity status toggle — a dot in the inbox header that flips IG's native
// "Show activity status" via IGActivityStatusSettingService, keyed per account.

#import "../../Utils.h"
#import "../../InstagramHeaders.h"
#import "../../RYGChrome.h"
#import "../General/RYGInboxHeaderKit.h"
#import "../../UI/Notification/RYGNotificationActions.h"
#import "../../Observers/RYGObservers.h"
#import <objc/runtime.h>
#import <objc/message.h>

static BOOL rygActivityToggleOn(void) { return [RYGUtils getBoolPref:@"activity_toggle_enabled"]; }

static const void *kRYGActivityBtnKey = &kRYGActivityBtnKey;

static NSMutableDictionary<NSString *, NSNumber *> *rygEnabledByPK(void) {
    static NSMutableDictionary *d; static dispatch_once_t o;
    dispatch_once(&o, ^{ d = [NSMutableDictionary dictionary]; });
    return d;
}
static NSMapTable *rygServicesByPK(void) {
    static NSMapTable *m; static dispatch_once_t o;
    dispatch_once(&o, ^{ m = [NSMapTable strongToWeakObjectsMapTable]; });
    return m;
}
static __weak id rygCapturedService = nil;

static NSString *rygCurPK(void) { return [RYGUtils currentUserPK]; }
static int rygEnabledFor(NSString *pk) {
    NSNumber *n = pk.length ? rygEnabledByPK()[pk] : nil;
    return n ? [n intValue] : -1;
}
static void rygSetEnabled(NSString *pk, int v) { if (pk.length && v >= 0) rygEnabledByPK()[pk] = @(v); }

// BFS an object graph (following object-typed ivars) for the first instance of `cls`.
static id rygScanForClass(id root, Class cls, int maxLevel) {
    if (!cls || !root) return nil;
    NSMutableArray *queue = [NSMutableArray arrayWithObject:root];
    NSMutableSet *seen = [NSMutableSet set];
    int budget = 6000;
    for (int level = 0; level < maxLevel && queue.count; level++) {
        NSMutableArray *next = [NSMutableArray array];
        for (id obj in queue) {
            if (!obj || --budget < 0) return nil;
            NSValue *key = [NSValue valueWithNonretainedObject:obj];
            if ([seen containsObject:key]) continue;
            [seen addObject:key];
            if ([obj isKindOfClass:cls]) return obj;
            Class c = object_getClass(obj);
            while (c && c != [NSObject class]) {
                unsigned int ic = 0;
                Ivar *ivars = class_copyIvarList(c, &ic);
                for (unsigned int i = 0; i < ic; i++) {
                    const char *t = ivar_getTypeEncoding(ivars[i]);
                    if (t && t[0] == '@') {
                        id child = object_getIvar(obj, ivars[i]);
                        if (child) [next addObject:child];
                    }
                }
                if (ivars) free(ivars);
                c = class_getSuperclass(c);
            }
        }
        queue = next;
    }
    return nil;
}

// The account PK a service belongs to — read from the IGUserSession in its own graph.
static NSString *rygActPKForService(id service) {
    id session = rygScanForClass(service, NSClassFromString(@"IGUserSession"), 4);
    if (!session) return nil;
    @try {
        id user = [session valueForKey:@"user"];
        if (!user) return nil;
        Ivar iv = class_getInstanceVariable([user class], "_pk");
        if (!iv) return nil;
        id pk = object_getIvar(user, iv);
        return pk ? [pk description] : nil;
    } @catch (__unused id e) { return nil; }
}

static int rygActReadEnabled(id service) {
    if (![service respondsToSelector:@selector(cachedActivityStatusSetting)]) return -1;
    id setting = ((id(*)(id, SEL))objc_msgSend)(service, @selector(cachedActivityStatusSetting));
    if (!setting) return -1;
    @try {
        id v = [setting valueForKey:@"activityStatusEnabled"];
        if ([v respondsToSelector:@selector(boolValue)]) return [v boolValue] ? 1 : 0;
    } @catch (__unused id e) {}
    return -1;
}

// Left x for the dot, past any other chrome buttons in the left cluster so it
// never overlaps them; the +1 offsets the dot's smaller glyph for an even gap.
static CGFloat rygActLeftAnchor(UIView *header, UIView *myBtn) {
    CGFloat anchor = 12;
    NSMutableArray *stack = [NSMutableArray arrayWithObject:header];
    while (stack.count) {
        UIView *v = stack.lastObject;
        [stack removeLastObject];
        for (UIView *s in v.subviews) [stack addObject:s];
        if (v == header || v == myBtn || v.hidden) continue;
        if (![v isKindOfClass:[RYGChromeButton class]]) continue;
        CGRect f = [v convertRect:v.bounds toView:header];
        if (CGRectIsEmpty(f) || CGRectGetMinX(f) > header.bounds.size.width * 0.5) continue;
        anchor = MAX(anchor, CGRectGetMaxX(f) + 1);
    }
    return anchor;
}

static void rygActApplyIcon(RYGChromeButton *btn) {
    int en = rygEnabledFor(rygCurPK());
    if (en == 1) {
        btn.symbolName = @"circle.fill";
        btn.iconTint = [UIColor systemGreenColor];
    } else if (en == 0) {
        btn.symbolName = @"circle.slash";
        btn.iconTint = [UIColor secondaryLabelColor];
    } else {
        btn.symbolName = @"circle.dotted";
        btn.iconTint = [UIColor secondaryLabelColor];
    }
}

static void rygActRefreshVisibleDot(void) {
    for (UIScene *scene in UIApplication.sharedApplication.connectedScenes) {
        if (![scene isKindOfClass:UIWindowScene.class]) continue;
        for (UIWindow *w in ((UIWindowScene *)scene).windows) {
            UIView *header = RYGInboxHeaderView(w);
            RYGChromeButton *btn = header ? objc_getAssociatedObject(header, kRYGActivityBtnKey) : nil;
            if (btn) rygActApplyIcon(btn);
        }
    }
}

@interface IGDirectInboxViewController (RYGActivityToggle)
- (id)rygActivityService;
- (void)rygActivityRefreshFromButton:(RYGChromeButton *)sender;
- (void)rygActivitySetNative:(BOOL)enabled button:(RYGChromeButton *)sender;
- (void)rygActivityTapped:(RYGChromeButton *)sender;
@end

%group RYGActivityToggle

%hook IGActivityStatusSettingService
- (id)initWithPresenceActions:(id)pa directUserActions:(id)dua userDefaults:(id)ud {
    id r = %orig;
    if (r) {
        rygCapturedService = r;
        NSString *pk = rygActPKForService(r) ?: rygCurPK();
        if (pk.length) [rygServicesByPK() setObject:r forKey:pk];
        rygSetEnabled(pk, rygActReadEnabled(r));
    }
    return r;
}
%end

%hook IGDirectInboxViewController

- (void)viewDidLayoutSubviews {
    %orig;
    if (!rygActivityToggleOn()) return;
    UIViewController *vc = (UIViewController *)self;
    if (!vc.isViewLoaded) return;

    UIView *header = RYGInboxHeaderView(vc.view);
    if (!header) header = RYGInboxHeaderView(vc.view.window);
    if (!header) return;

    RYGChromeButton *btn = objc_getAssociatedObject(header, kRYGActivityBtnKey);
    if (!btn || btn.superview != header) {
        btn = [[RYGChromeButton alloc] initWithSymbol:@"circle.dotted" pointSize:16.0 diameter:40.0];
        btn.bubbleColor = [UIColor clearColor];
        btn.translatesAutoresizingMaskIntoConstraints = YES;
        [btn addTarget:self action:@selector(rygActivityTapped:) forControlEvents:UIControlEventTouchUpInside];
        [header addSubview:btn];
        objc_setAssociatedObject(header, kRYGActivityBtnKey, btn, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        [self rygActivityRefreshFromButton:btn];
    }

    rygActApplyIcon(btn);

    UIView *rowRef = RYGInboxRowRef(header);
    CGFloat side = 40;
    CGFloat y = RYGInboxRowTop(header, rowRef, side);
    btn.frame = CGRectMake(rygActLeftAnchor(header, btn), y, side, side);
    RYGInboxMirrorChrome(btn, rowRef, header);
    [header bringSubviewToFront:btn];
}

- (void)viewDidAppear:(BOOL)animated {
    %orig;
    if (!rygActivityToggleOn()) return;
    UIView *header = RYGInboxHeaderView(((UIViewController *)self).view);
    if (!header) header = RYGInboxHeaderView(((UIViewController *)self).view.window);
    RYGChromeButton *btn = header ? objc_getAssociatedObject(header, kRYGActivityBtnKey) : nil;
    if (btn) [self rygActivityRefreshFromButton:btn];
}

%new - (id)rygActivityService {
    NSString *pk = rygCurPK();
    id perPK = pk.length ? [rygServicesByPK() objectForKey:pk] : nil;
    return perPK ?: rygCapturedService;
}

%new - (void)rygActivityRefreshFromButton:(RYGChromeButton *)sender {
    id service = [self rygActivityService];
    if (!service) return;
    NSString *pk = rygCurPK();
    int cached = rygActReadEnabled(service);
    if (cached >= 0) { rygSetEnabled(pk, cached); rygActApplyIcon(sender); }
    if (![service respondsToSelector:@selector(fetchActivityStatusSettingWithSuccessBlock:failureBlock:)]) return;
    __weak RYGChromeButton *wbtn = sender;
    void (^success)(id) = ^(id setting) {
        int en = -1;
        @try {
            id v = [setting valueForKey:@"activityStatusEnabled"];
            if ([v respondsToSelector:@selector(boolValue)]) en = [v boolValue] ? 1 : 0;
        } @catch (__unused id e) {}
        rygSetEnabled(pk, en);
        dispatch_async(dispatch_get_main_queue(), ^{ if (wbtn) rygActApplyIcon(wbtn); });
    };
    void (^failure)(id) = ^(id err) {};
    ((void(*)(id, SEL, id, id))objc_msgSend)(service, @selector(fetchActivityStatusSettingWithSuccessBlock:failureBlock:), success, failure);
}

%new - (void)rygActivitySetNative:(BOOL)enabled button:(RYGChromeButton *)sender {
    id service = [self rygActivityService];
    id session = [RYGUtils activeUserSession];
    NSString *pk = rygCurPK();
    if (!service || !session) {
        RYGNotifyError(RYG_NOTIF_ACTIVITY_TOGGLE, RYGLocalized(@"Couldn't change activity status"), RYGLocalized(@"Check your connection and try again"));
        return;
    }
    int prev = rygEnabledFor(pk);
    rygSetEnabled(pk, enabled ? 1 : 0);
    rygActApplyIcon(sender);
    [[[UIImpactFeedbackGenerator alloc] initWithStyle:UIImpactFeedbackStyleMedium] impactOccurred];

    __weak RYGChromeButton *wbtn = sender;
    void (^success)(void) = ^{
        RYGNotifySuccess(RYG_NOTIF_ACTIVITY_TOGGLE,
                         enabled ? RYGLocalized(@"Activity status on") : RYGLocalized(@"Activity status off"), @"");
    };
    void (^failure)(id) = ^(id err) {
        rygSetEnabled(pk, prev);
        dispatch_async(dispatch_get_main_queue(), ^{ if (wbtn) rygActApplyIcon(wbtn); });
        RYGNotifyError(RYG_NOTIF_ACTIVITY_TOGGLE, RYGLocalized(@"Couldn't change activity status"), RYGLocalized(@"Check your connection and try again"));
    };
    ((void(*)(id, SEL, BOOL, id, id, id))objc_msgSend)(service, @selector(setActivityStatusSetting:userSession:successBlock:failureBlock:), enabled, session, success, failure);
}

%new - (void)rygActivityTapped:(RYGChromeButton *)sender {
    BOOL cur = (rygEnabledFor(rygCurPK()) != 0);
    [self rygActivitySetNative:!cur button:sender];
}

%end
%end

%ctor {
    if (!rygActivityToggleOn()) return;
    %init(RYGActivityToggle);
    [[RYGObservers account] addChangeHandler:^(NSString *previousPK, NSString *currentPK) {
        rygActRefreshVisibleDot();
    }];
}
