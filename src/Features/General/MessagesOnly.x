// Messages-only mode — trim unwanted tabs, force inbox at launch, add inbox-header shortcuts.

#import "../../Utils.h"
#import "../../InstagramHeaders.h"
#import "../../SCIChrome.h"
#import "../../SCIURLOpener.h"
#import <objc/runtime.h>
#import <objc/message.h>

static BOOL sciMsgOnly(void) { return [SCIUtils getBoolPref:@"messages_only"]; }
static BOOL sciMsgOnlyHideTabBar(void) {
    return sciMsgOnly() && [SCIUtils getBoolPref:@"messages_only_hide_tabbar"];
}
static BOOL sciMsgOnlyHideSearch(void) {
    return sciMsgOnly() && [SCIUtils getBoolPref:@"messages_only_hide_search"];
}

%hook IGTabBarController

// Block tab creation entirely so they never enter the buttons array (no gaps).
- (void)_createAndConfigureTimelineButtonIfNeeded   {
	if (sciMsgOnly()) return;
	%orig;
}
- (void)_createAndConfigureReelsButtonIfNeeded      {
	if (sciMsgOnly()) return;
	%orig;
}
- (void)_createAndConfigureExploreButtonIfNeeded    {
	if (sciMsgOnlyHideSearch()) return;
	%orig;
}
- (void)_createAndConfigureCameraButtonIfNeeded     {
	if (sciMsgOnly()) return;
	%orig;
}
- (void)_createAndConfigureDynamicTabButtonIfNeeded {
	if (sciMsgOnly()) return;
	%orig;
}
- (void)_createAndConfigureNewsButtonIfNeeded       {
	if (sciMsgOnly()) return;
	%orig;
}
- (void)_createAndConfigureStreamsButtonIfNeeded    {
	if (sciMsgOnly()) return;
	%orig;
}

// LaunchTab forces the content; we just sync the indicator once laid out.
- (void)viewDidAppear:(BOOL)animated {
    %orig;
    static BOOL launched = NO;
    if (sciMsgOnly() && !launched) {
        launched = YES;
        ((void(*)(id, SEL, id))objc_msgSend)(self, @selector(sciSyncTabBarSelection:), @"inbox");
    }
}

// Keep the indicator in step with the selected surface (incl. IG's late restore).
- (void)setSelectedTabBarSurface:(id)surface animated:(BOOL)animated animateIndicator:(BOOL)animateIndicator {
    %orig;
    if (!sciMsgOnly()) return;
    id cur = [self respondsToSelector:@selector(selectedTabBarSurface)] ? [self selectedTabBarSurface] : surface;
    NSString *str = [cur respondsToSelector:@selector(tabStringFromSurfaceIntent)] ? [cur tabStringFromSurfaceIntent] : nil;
    NSString *which = @"inbox";
    if ([str isEqualToString:@"PROFILE"]) which = @"profile";
    else if ([str isEqualToString:@"SEARCH"]) which = @"explore";
    ((void(*)(id, SEL, id))objc_msgSend)(self, @selector(sciSyncTabBarSelection:), which);
}

- (void)viewDidLayoutSubviews {
    %orig;
    if (!sciMsgOnlyHideTabBar()) return;
    Ivar tbIv = class_getInstanceVariable([self class], "_tabBar");
    UIView *tabBar = tbIv ? object_getIvar(self, tbIv) : nil;
    if (tabBar) {
        tabBar.hidden = YES;
        tabBar.alpha = 0.0;
    }
    UIViewController *selected = [self valueForKey:@"selectedViewController"];
    if (selected.isViewLoaded) {
        selected.view.frame = self.view.bounds;
    }
}

// Surface enum no longer maps cleanly to the trimmed _buttons array, so flip
// the selected state ourselves and nudge the liquid-glass indicator.
%new - (void)sciSyncTabBarSelection:(NSString *)which {
    Class c = [self class];
    Ivar ibIv = class_getInstanceVariable(c, "_directInboxButton");
    Ivar pbIv = class_getInstanceVariable(c, "_profileButton");
    Ivar ebIv = class_getInstanceVariable(c, "_exploreButton");
    UIButton *inbox = ibIv ? object_getIvar(self, ibIv) : nil;
    UIButton *profile = pbIv ? object_getIvar(self, pbIv) : nil;
    UIButton *explore = ebIv ? object_getIvar(self, ebIv) : nil;

    UIButton *active = inbox;
    if ([which isEqualToString:@"profile"]) active = profile;
    else if ([which isEqualToString:@"explore"]) active = explore;

    if ([inbox respondsToSelector:@selector(setSelected:)]) inbox.selected = (active == inbox);
    if ([profile respondsToSelector:@selector(setSelected:)]) profile.selected = (active == profile);
    if ([explore respondsToSelector:@selector(setSelected:)]) explore.selected = (active == explore);

    // No-op on classic tab bar (selector only exists on IGLiquidGlassInteractiveTabBar).
    // Indicator index is visual order — derive from on-screen x, not the _buttons array.
    Ivar tbIv = class_getInstanceVariable(c, "_tabBar");
    id tabBar = tbIv ? object_getIvar(self, tbIv) : nil;
    NSMutableArray<UIButton *> *ordered = [NSMutableArray array];
    for (UIButton *b in @[ explore ?: NSNull.null, inbox ?: NSNull.null, profile ?: NSNull.null ]) {
        if ([b isKindOfClass:[UIButton class]] && b.window) [ordered addObject:b];
    }
    [ordered sortUsingComparator:^NSComparisonResult(UIButton *a, UIButton *b) {
        CGFloat xa = [a convertRect:a.bounds toView:nil].origin.x;
        CGFloat xb = [b convertRect:b.bounds toView:nil].origin.x;
        return xa < xb ? NSOrderedAscending : (xa > xb ? NSOrderedDescending : NSOrderedSame);
    }];
    NSInteger idx = active ? [ordered indexOfObjectIdenticalTo:active] : NSNotFound;
    if (idx == NSNotFound) idx = 0;
    SEL setIdx = NSSelectorFromString(@"setSelectedTabBarItemIndex:animateIndicator:");
    if ([tabBar respondsToSelector:setIdx])
        ((void(*)(id, SEL, NSInteger, BOOL))objc_msgSend)(tabBar, setIdx, idx, YES);
}

- (void)_directInboxButtonPressed {
    %orig;
    if (sciMsgOnly())
        ((void(*)(id, SEL, id))objc_msgSend)(self, @selector(sciSyncTabBarSelection:), @"inbox");
}
- (void)_profileButtonPressed {
    %orig;
    if (sciMsgOnly())
        ((void(*)(id, SEL, id))objc_msgSend)(self, @selector(sciSyncTabBarSelection:), @"profile");
}
- (void)_exploreButtonPressed {
    %orig;
    if (sciMsgOnly())
        ((void(*)(id, SEL, id))objc_msgSend)(self, @selector(sciSyncTabBarSelection:), @"explore");
}

%end

// Inbox-header shortcuts, parented to IG's nav header so they collapse with it:
// Activity (the news tab is gone in messages-only) + a gear when the tab bar is hidden.
static const void *kSCIMsgOnlyNewsKey = &kSCIMsgOnlyNewsKey;
static const void *kSCIMsgOnlyGearKey = &kSCIMsgOnlyGearKey;

static UIView *sciFindInboxHeaderView(UIView *root) {
    if (!root) return nil;
    if ([NSStringFromClass([root class]) containsString:@"NavigationHeaderView"]) return root;
    for (UIView *sub in root.subviews) {
        UIView *r = sciFindInboxHeaderView(sub);
        if (r) return r;
    }
    return nil;
}

// IG buries its trailing buttons inside zero-frame wrappers; recurse for the
// UIButtons in the header's right third, sorted left→right in header space.
static NSArray<UIView *> *sciHeaderTrailingButtons(UIView *header, NSArray<UIView *> *skip) {
    NSMutableArray<UIView *> *out = [NSMutableArray array];
    NSMutableArray *stack = [NSMutableArray arrayWithObject:header];
    while (stack.count) {
        UIView *v = stack.lastObject;
        [stack removeLastObject];
        if (v != header && ![skip containsObject:v]
            && [v isKindOfClass:[UIButton class]] && !CGRectIsEmpty(v.bounds)
            && CGRectGetMinX([v convertRect:v.bounds toView:header]) > header.bounds.size.width * 0.6) {
            [out addObject:v];
        }
        for (UIView *s in v.subviews) [stack addObject:s];
    }
    [out sortUsingComparator:^NSComparisonResult(UIView *a, UIView *b) {
        CGFloat xa = CGRectGetMinX([a convertRect:a.bounds toView:header]);
        CGFloat xb = CGRectGetMinX([b convertRect:b.bounds toView:header]);
        return xa < xb ? NSOrderedAscending : (xa > xb ? NSOrderedDescending : NSOrderedSame);
    }];
    return out;
}

// Mirror IG's scroll-collapse by matching a reference button's effective alpha + hidden.
static void sciMirrorHeaderChrome(UIView *btn, UIView *ref, UIView *header) {
    if (!ref) { btn.alpha = 1.0; btn.hidden = NO; return; }
    CGFloat eff = 1.0;
    BOOL hidden = NO;
    for (UIView *v = ref; v && v != header; v = v.superview) {
        if (v.hidden) hidden = YES;
        eff *= v.alpha;
    }
    btn.alpha = eff;
    btn.hidden = hidden;
}

static SCIChromeButton *sciEnsureHeaderButton(UIView *header, const void *key, NSString *resource,
                                              CGFloat pt, CGFloat diameter, id target, SEL action) {
    SCIChromeButton *btn = objc_getAssociatedObject(header, key);
    if (btn && btn.superview == header) return btn;
    btn = [[SCIChromeButton alloc] initWithSymbol:@"circle" pointSize:pt diameter:diameter];
    [btn setIconResource:resource pointSize:pt];
    btn.iconTint = [UIColor labelColor];
    btn.bubbleColor = [UIColor clearColor];
    btn.translatesAutoresizingMaskIntoConstraints = YES;
    [btn addTarget:target action:action forControlEvents:UIControlEventTouchUpInside];
    [header addSubview:btn];
    objc_setAssociatedObject(header, key, btn, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    return btn;
}

%hook IGDirectInboxViewController

- (void)viewDidLayoutSubviews {
    %orig;
    UIViewController *vc = (UIViewController *)self;
    if (!sciMsgOnly() || !vc.isViewLoaded) return;

    UIView *header = sciFindInboxHeaderView(vc.view);
    if (!header) return;

    SCIChromeButton *news = sciEnsureHeaderButton(header, kSCIMsgOnlyNewsKey, @"bcn_heart_outline_24", 24, 40,
                                                  self, @selector(sciMsgOnlyOpenActivity));
    SCIChromeButton *gear = sciMsgOnlyHideTabBar()
        ? sciEnsureHeaderButton(header, kSCIMsgOnlyGearKey, @"ig_icon_settings_outline_24", 24, 40,
                                self, @selector(sciMsgOnlyOpenSettings))
        : nil;

    UIView *ref = sciHeaderTrailingButtons(header, gear ? @[news, gear] : @[news]).lastObject;
    CGRect refFrame = ref ? [ref convertRect:ref.bounds toView:header] : CGRectZero;

    CGFloat side = 40, x = 12;
    CGFloat y = ref ? CGRectGetMidY(refFrame) - side * 0.5 : (header.bounds.size.height - side) * 0.5;
    for (SCIChromeButton *btn in @[ gear ?: NSNull.null, news ]) {
        if (![btn isKindOfClass:[SCIChromeButton class]]) continue;
        btn.frame = CGRectMake(x, y, side, side);
        sciMirrorHeaderChrome(btn, ref, header);
        [header bringSubviewToFront:btn];
        x += side + 4;
    }
}

%new - (void)sciMsgOnlyOpenActivity {
    UIViewController *inbox = (UIViewController *)self;
    UIViewController *p = inbox;
    while (p && ![p isKindOfClass:%c(IGTabBarController)]) p = p.parentViewController;
    if (!p) return;

    Ivar mgrIv = class_getInstanceVariable([p class], "_viewControllerManager");
    id mgr = mgrIv ? object_getIvar(p, mgrIv) : nil;
    SEL sel = @selector(activityFeedViewController);
    UIViewController *feed = [mgr respondsToSelector:sel] ? ((id(*)(id, SEL))objc_msgSend)(mgr, sel) : nil;
    if (!feed) return;

    UINavigationController *nav = inbox.navigationController;
    if (!nav) return;
    if ([nav.viewControllers containsObject:feed]) { [nav popToViewController:feed animated:YES]; return; }
    if (feed.navigationController && feed.navigationController != nav) {
        [feed willMoveToParentViewController:nil];
        [feed.view removeFromSuperview];
        [feed removeFromParentViewController];
    }
    [nav pushViewController:feed animated:YES];
}

%new - (void)sciMsgOnlyOpenSettings {
    UIViewController *vc = (UIViewController *)self;
    [SCIUtils showSettingsVC:vc.view.window];
}

%end
