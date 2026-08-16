// Messages-only mode: trim unwanted tabs, force inbox at launch, add inbox-header shortcuts.

#import "../../Utils.h"
#import "../../InstagramHeaders.h"
#import "../../RYGChrome.h"
#import "../../RYGURLOpener.h"
#import "RYGInboxHeaderKit.h"
#import "RYGMessagesOnlySchedule.h"
#import "../Feed/RYGHomeShortcutCatalog.h"
#import <objc/runtime.h>
#import <objc/message.h>

static BOOL rygMsgOnly(void) { return [RYGUtils getBoolPref:@"messages_only"]; }
static BOOL rygMsgOnlyHideTabBar(void) {
    return rygMsgOnly() && [RYGUtils getBoolPref:@"messages_only_hide_tabbar"];
}
static BOOL rygMsgOnlyHideSearch(void) {
    return rygMsgOnly() && [RYGUtils getBoolPref:@"messages_only_hide_search"];
}
static BOOL rygMsgOnlyHome(void) {
    return rygMsgOnly() && [RYGUtils getBoolPref:@"messages_only_home_shortcut"]
        && [RYGUtils getBoolPref:kRYGHomeShortcutEnabledPrefKey];
}

static const void *kRYGMsgOnlyNewsKey = &kRYGMsgOnlyNewsKey;
static const void *kRYGMsgOnlyGearKey = &kRYGMsgOnlyGearKey;
static const void *kRYGMsgOnlyHomeKey = &kRYGMsgOnlyHomeKey;

static BOOL sRYGMsgOnlyHooksActive = NO;

// MARK: - Live apply

static UIViewController *rygFindTabBarController(void) {
    Class cls = NSClassFromString(@"IGTabBarController");
    if (!cls) return nil;
    NSMutableArray<UIViewController *> *queue = [NSMutableArray array];
    for (UIScene *scene in UIApplication.sharedApplication.connectedScenes) {
        if (![scene isKindOfClass:UIWindowScene.class]) continue;
        for (UIWindow *w in ((UIWindowScene *)scene).windows)
            if (w.rootViewController) [queue addObject:w.rootViewController];
    }
    while (queue.count) {
        UIViewController *vc = queue.firstObject;
        [queue removeObjectAtIndex:0];
        if ([vc isKindOfClass:cls]) return vc;
        [queue addObjectsFromArray:vc.childViewControllers];
        if (vc.presentedViewController) [queue addObject:vc.presentedViewController];
    }
    return nil;
}

static NSArray<UIViewController *> *rygFindInboxControllers(UIViewController *root) {
    Class cls = NSClassFromString(@"IGDirectInboxViewController");
    NSMutableArray<UIViewController *> *found = [NSMutableArray array];
    if (!cls || !root) return found;
    NSMutableArray<UIViewController *> *queue = [NSMutableArray arrayWithObject:root];
    while (queue.count) {
        UIViewController *vc = queue.firstObject;
        [queue removeObjectAtIndex:0];
        if ([vc isKindOfClass:cls]) [found addObject:vc];
        [queue addObjectsFromArray:vc.childViewControllers];
        if (vc.presentedViewController) [queue addObject:vc.presentedViewController];
    }
    return found;
}

static NSArray<NSString *> *rygStrippedButtonIvarNames(void) {
    NSMutableArray *names = [@[ @"_timelineButton", @"_discoverVideoButton", @"_cameraButton",
                               @"_dynamicTabButton", @"_newsButton", @"_streamsButton" ] mutableCopy];
    if (rygMsgOnlyHideSearch()) [names addObject:@"_exploreButton"];
    return names;
}

static NSString *rygSurfaceTabString(id surface) {
    if (![surface respondsToSelector:@selector(tabStringFromSurfaceIntent)]) return nil;
    return ((id(*)(id, SEL))objc_msgSend)(surface, @selector(tabStringFromSurfaceIntent));
}

static void rygSetIvarDouble(id obj, const char *name, double value) {
    Ivar iv = obj ? class_getInstanceVariable([obj class], name) : NULL;
    if (!iv) return;
    *(double *)((char *)(__bridge void *)obj + ivar_getOffset(iv)) = value;
}

static void rygSetIvarRect(id obj, const char *name, CGRect value) {
    Ivar iv = obj ? class_getInstanceVariable([obj class], name) : NULL;
    if (!iv) return;
    *(CGRect *)((char *)(__bridge void *)obj + ivar_getOffset(iv)) = value;
}

// On-screen order lives in _tabBarSurfaces, not in the rebuilt _buttons array.
static NSArray *rygOrderedButtons(UIViewController *ctrl) {
    NSArray *buttons = [RYGUtils getIvarForObj:ctrl name:"_buttons"];
    NSArray *surfaces = [RYGUtils getIvarForObj:ctrl name:"_tabBarSurfaces"];
    SEL btnSel = @selector(buttonForTabBarSurface:);
    if (!surfaces.count || ![ctrl respondsToSelector:btnSel]) return buttons;

    NSMutableArray *ordered = [NSMutableArray array];
    NSMutableArray *order = [NSMutableArray array];
    for (id surface in surfaces) {
        UIView *b = ((id(*)(id, SEL, id))objc_msgSend)(ctrl, btnSel, surface);
        if (!b || [buttons indexOfObjectIdenticalTo:b] == NSNotFound) continue;
        if ([ordered indexOfObjectIdenticalTo:b] != NSNotFound) continue;
        [ordered addObject:b];
        [order addObject:rygSurfaceTabString(surface) ?: @"?"];
    }
    for (UIView *b in buttons)
        if ([ordered indexOfObjectIdenticalTo:b] == NSNotFound) {
            [ordered addObject:b];
            [order addObject:@"unmapped"];
        }

    if (ordered.count != buttons.count) return buttons;
    [RYGUtils setIvarForObj:ctrl name:"_buttons" value:ordered];
    return ordered;
}

// The glass bar owns its own button container, so _buttons alone never reaches it.
static void rygRebuildTabBarButtons(UIViewController *ctrl) {
    UIView *tabBar = [RYGUtils getIvarForObj:ctrl name:"_tabBar"];
    NSArray *buttons = rygOrderedButtons(ctrl);
    SEL clearSel = NSSelectorFromString(@"clearTabButtons");
    SEL addSel = NSSelectorFromString(@"addTabButton:");
    if (!tabBar || !buttons.count) {
        return;
    }
    if (![tabBar respondsToSelector:clearSel] || ![tabBar respondsToSelector:addSel]) {
        return;
    }

    ((void(*)(id, SEL))objc_msgSend)(tabBar, clearSel);
    for (UIView *b in buttons)
        ((void(*)(id, SEL, id))objc_msgSend)(tabBar, addSel, b);

    // Button and pill sizing is cached per bounds, so a count change alone is skipped.
    UIView *container = [RYGUtils getIvarForObj:tabBar name:"_buttonContainerView"];
    if (container) {
        rygSetIvarDouble(container, "_cachedRestingSizeForButtonLayout", 0);
        rygSetIvarRect(container, "_previousBoundsBeforeSettingIndicatorPosition", CGRectZero);
        [container setNeedsLayout];
    }

    SEL refreshSel = NSSelectorFromString(@"refreshAppearance");
    if ([tabBar respondsToSelector:refreshSel])
        ((void(*)(id, SEL))objc_msgSend)(tabBar, refreshSel);
    [tabBar setNeedsLayout];

    SEL layoutSel = NSSelectorFromString(@"_layoutTabBar");
    if ([ctrl respondsToSelector:layoutSel])
        ((void(*)(id, SEL))objc_msgSend)(ctrl, layoutSel);
    [tabBar layoutIfNeeded];

}

static void rygSyncIndicatorToSelection(UIViewController *ctrl) {
    NSArray *buttons = [RYGUtils getIvarForObj:ctrl name:"_buttons"];
    UIView *tabBar = [RYGUtils getIvarForObj:ctrl name:"_tabBar"];
    SEL surfSel = @selector(selectedTabBarSurface);
    SEL btnSel = @selector(buttonForTabBarSurface:);
    if (![ctrl respondsToSelector:surfSel] || ![ctrl respondsToSelector:btnSel]) return;

    id surface = ((id(*)(id, SEL))objc_msgSend)(ctrl, surfSel);
    UIButton *active = ((id(*)(id, SEL, id))objc_msgSend)(ctrl, btnSel, surface);
    for (UIButton *b in buttons)
        if ([b respondsToSelector:@selector(setSelected:)]) b.selected = (b == active);

    NSInteger idx = active ? [buttons indexOfObjectIdenticalTo:active] : NSNotFound;
    if (idx == NSNotFound) {
        return;
    }
    SEL setIdx = NSSelectorFromString(@"setSelectedTabBarItemIndex:animateIndicator:");
    if ([tabBar respondsToSelector:setIdx])
        ((void(*)(id, SEL, NSInteger, BOOL))objc_msgSend)(tabBar, setIdx, idx, NO);

    UIView *container = [RYGUtils getIvarForObj:tabBar name:"_buttonContainerView"];
    SEL trackSel = NSSelectorFromString(@"setTrackedSelectedButton:");
    SEL contIdxSel = NSSelectorFromString(@"setSelectedIndex:");
    SEL updSel = NSSelectorFromString(@"updateIndicatorPositionAnimated:");
    if ([container respondsToSelector:trackSel])
        ((void(*)(id, SEL, id))objc_msgSend)(container, trackSel, active);
    if ([container respondsToSelector:contIdxSel])
        ((void(*)(id, SEL, NSInteger))objc_msgSend)(container, contIdxSel, idx);
    [container layoutIfNeeded];
    if ([container respondsToSelector:updSel])
        ((void(*)(id, SEL, BOOL))objc_msgSend)(container, updSel, NO);

}

static void rygSelectSurfaceIfStripped(UIViewController *ctrl) {
    SEL selSel = @selector(selectedTabBarSurface);
    id current = [ctrl respondsToSelector:selSel] ? ((id(*)(id, SEL))objc_msgSend)(ctrl, selSel) : nil;
    NSString *cur = rygSurfaceTabString(current);
    NSSet *kept = rygMsgOnlyHideSearch() ? [NSSet setWithArray:@[ @"DIRECT", @"PROFILE" ]]
                                         : [NSSet setWithArray:@[ @"DIRECT", @"PROFILE", @"SEARCH" ]];
    if (cur && [kept containsObject:cur]) {
        return;
    }

    SEL allSel = @selector(allTabBarSurfaces);
    NSArray *surfaces = [ctrl respondsToSelector:allSel] ? ((id(*)(id, SEL))objc_msgSend)(ctrl, allSel) : nil;
    for (id s in surfaces) {
        if (![rygSurfaceTabString(s) isEqualToString:@"DIRECT"]) continue;
        SEL setSel = @selector(setSelectedTabBarSurface:animated:animateIndicator:);
        if ([ctrl respondsToSelector:setSel])
            ((void(*)(id, SEL, id, BOOL, BOOL))objc_msgSend)(ctrl, setSel, s, NO, YES);
        return;
    }
}

BOOL RYGMessagesOnlyApplyLive(void) {
    if (!NSThread.isMainThread) {
        __block BOOL ok = NO;
        dispatch_sync(dispatch_get_main_queue(), ^{ ok = RYGMessagesOnlyApplyLive(); });
        return ok;
    }

    BOOL on = rygMsgOnly();
    if (!sRYGMsgOnlyHooksActive) return NO;

    UIViewController *ctrl = rygFindTabBarController();
    if (!ctrl || !ctrl.isViewLoaded) return NO;

    NSMutableSet *removed = [NSMutableSet set];
    if (on) {
        for (NSString *name in rygStrippedButtonIvarNames()) {
            UIView *b = [RYGUtils getIvarForObj:ctrl name:name.UTF8String];
            if (!b) continue;
            [removed addObject:b];
            [b removeFromSuperview];
            [RYGUtils setIvarForObj:ctrl name:name.UTF8String value:nil];
        }
    }

    for (NSString *sel in @[ @"_initializeAndConfigureBarButtonsIfNeeded",
                             @"_updateTabBarButtonsAndUpdateViewControllersIfNeeded",
                             @"_layoutTabBar" ]) {
        SEL s = NSSelectorFromString(sel);
        if ([ctrl respondsToSelector:s]) ((void(*)(id, SEL))objc_msgSend)(ctrl, s);
    }

    if (on && removed.count) {
        NSArray *buttons = [RYGUtils getIvarForObj:ctrl name:"_buttons"];
        NSMutableArray *kept = [NSMutableArray array];
        for (UIView *b in buttons) {
            if ([removed containsObject:b]) continue;
            [kept addObject:b];
        }
        if (kept.count != buttons.count) {
            [RYGUtils setIvarForObj:ctrl name:"_buttons" value:kept];
        }
    }

    rygRebuildTabBarButtons(ctrl);

    UIView *tabBar = [RYGUtils getIvarForObj:ctrl name:"_tabBar"];
    if (tabBar) {
        if (rygMsgOnlyHideTabBar()) {
            tabBar.hidden = YES;
            tabBar.alpha = 0.0;
        } else {
            // A thread or viewer may have hidden it already, so let IG decide.
            UIViewController *selected = [ctrl valueForKey:@"selectedViewController"];
            UIViewController *top = [selected isKindOfClass:UINavigationController.class]
                ? ((UINavigationController *)selected).topViewController : selected;
            SEL shouldSel = NSSelectorFromString(@"_shouldTabBarBeHiddenForController:");
            BOOL shouldHide = tabBar.hidden;
            if (top && [ctrl respondsToSelector:shouldSel])
                shouldHide = ((BOOL(*)(id, SEL, id))objc_msgSend)(ctrl, shouldSel, top);
            tabBar.hidden = shouldHide;
            if (!shouldHide && tabBar.alpha == 0.0 &&
                ![[RYGUtils getStringPref:@"liquid_glass_tabbar_mode"] isEqualToString:@"hide"])
                tabBar.alpha = 1.0;
        }
    }

    if (on) rygSelectSurfaceIfStripped(ctrl);

    UIViewController *selected = [ctrl valueForKey:@"selectedViewController"];
    if (selected.isViewLoaded) [selected.view setNeedsLayout];
    [ctrl.view setNeedsLayout];
    [ctrl.view layoutIfNeeded];

    NSArray<UIViewController *> *inboxes = rygFindInboxControllers(ctrl);
    SEL headerSel = NSSelectorFromString(@"rygMsgOnlyLayoutHeaderButtons");
    for (UIViewController *inbox in inboxes) {
        if (!inbox.isViewLoaded || ![inbox respondsToSelector:headerSel]) continue;
        [inbox.view setNeedsLayout];
        [inbox.view layoutIfNeeded];
        // Other features place header buttons relative to ours in the same callback.
        SEL layoutSel = @selector(viewDidLayoutSubviews);
        ((void(*)(id, SEL))objc_msgSend)(inbox, layoutSel);
        dispatch_async(dispatch_get_main_queue(), ^{
            ((void(*)(id, SEL))objc_msgSend)(inbox, layoutSel);
        });
    }

    rygSyncIndicatorToSelection(ctrl);

    return YES;
}

// MARK: - Hooks

%group RYGMessagesOnlyGroup

%hook IGTabBarController

// Block tab creation entirely so they never enter the buttons array (no gaps).
- (void)_createAndConfigureTimelineButtonIfNeeded   { if (rygMsgOnly()) return; %orig; }
- (void)_createAndConfigureReelsButtonIfNeeded      { if (rygMsgOnly()) return; %orig; }
- (void)_createAndConfigureExploreButtonIfNeeded    { if (rygMsgOnlyHideSearch()) return; %orig; }
- (void)_createAndConfigureCameraButtonIfNeeded     { if (rygMsgOnly()) return; %orig; }
- (void)_createAndConfigureDynamicTabButtonIfNeeded { if (rygMsgOnly()) return; %orig; }
- (void)_createAndConfigureNewsButtonIfNeeded       { if (rygMsgOnly()) return; %orig; }
- (void)_createAndConfigureStreamsButtonIfNeeded    { if (rygMsgOnly()) return; %orig; }

// LaunchTab forces the content; we just sync the indicator once laid out.
- (void)viewDidAppear:(BOOL)animated {
    %orig;
    static BOOL launched = NO;
    if (rygMsgOnly() && !launched) {
        launched = YES;
        ((void(*)(id, SEL, id))objc_msgSend)(self, @selector(rygSyncTabBarSelection:), @"inbox");
    }
}

// Keep the indicator in step with the selected surface (incl. IG's late restore).
- (void)setSelectedTabBarSurface:(id)surface animated:(BOOL)animated animateIndicator:(BOOL)animateIndicator {
    %orig;
    if (!rygMsgOnly()) return;
    id cur = [self respondsToSelector:@selector(selectedTabBarSurface)] ? [self selectedTabBarSurface] : surface;
    NSString *str = [cur respondsToSelector:@selector(tabStringFromSurfaceIntent)] ? [cur tabStringFromSurfaceIntent] : nil;
    NSString *which = @"inbox";
    if ([str isEqualToString:@"PROFILE"]) which = @"profile";
    else if ([str isEqualToString:@"SEARCH"]) which = @"explore";
    ((void(*)(id, SEL, id))objc_msgSend)(self, @selector(rygSyncTabBarSelection:), which);
}

- (void)viewDidLayoutSubviews {
    %orig;
    if (!rygMsgOnlyHideTabBar()) return;
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

// The surface enum no longer maps onto the trimmed _buttons array.
%new - (void)rygSyncTabBarSelection:(NSString *)which {
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
    else if ([which isEqualToString:@"feed"]) active = nil;

    if ([inbox respondsToSelector:@selector(setSelected:)]) inbox.selected = (active == inbox);
    if ([profile respondsToSelector:@selector(setSelected:)]) profile.selected = (active == profile);
    if ([explore respondsToSelector:@selector(setSelected:)]) explore.selected = (active == explore);
    if (!active) return;

    // Indicator index is visual order, so derive it from on-screen x.
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
    if (rygMsgOnly())
        ((void(*)(id, SEL, id))objc_msgSend)(self, @selector(rygSyncTabBarSelection:), @"inbox");
}
- (void)_profileButtonPressed {
    %orig;
    if (rygMsgOnly())
        ((void(*)(id, SEL, id))objc_msgSend)(self, @selector(rygSyncTabBarSelection:), @"profile");
}
- (void)_exploreButtonPressed {
    %orig;
    if (rygMsgOnly())
        ((void(*)(id, SEL, id))objc_msgSend)(self, @selector(rygSyncTabBarSelection:), @"explore");
}

%end

// Inbox-header shortcuts parented to IG's nav header: activity + gear on the
// left, the optional home shortcut on the right.

static RYGChromeButton *rygEnsureHeaderButton(UIView *header, const void *key, NSString *resource,
                                              CGFloat pt, CGFloat diameter, id target, SEL action) {
    RYGChromeButton *btn = objc_getAssociatedObject(header, key);
    if (btn && btn.superview == header) {
        btn.hidden = NO;
        return btn;
    }
    btn = [[RYGChromeButton alloc] initWithSymbol:@"circle" pointSize:pt diameter:diameter];
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
    ((void(*)(id, SEL))objc_msgSend)(self, @selector(rygMsgOnlyLayoutHeaderButtons));
}

// A live flip under a thread leaves the inbox laid out, so catch the return trip.
- (void)viewWillAppear:(BOOL)animated {
    %orig;
    ((void(*)(id, SEL))objc_msgSend)(self, @selector(rygMsgOnlyLayoutHeaderButtons));
}

- (void)viewDidAppear:(BOOL)animated {
    %orig;
    ((void(*)(id, SEL))objc_msgSend)(self, @selector(rygMsgOnlyLayoutHeaderButtons));
}

%new - (void)rygMsgOnlyLayoutHeaderButtons {
    UIViewController *vc = (UIViewController *)self;
    if (!vc.isViewLoaded) return;

    UIView *header = RYGInboxHeaderView(vc.view);
    if (!header) {
        return;
    }
    // IG has to re-lay its own header items first, ours anchor to them.
    [header setNeedsLayout];
    [header layoutIfNeeded];

    if (!rygMsgOnly()) {
        for (NSValue *key in @[ [NSValue valueWithPointer:kRYGMsgOnlyNewsKey],
                                [NSValue valueWithPointer:kRYGMsgOnlyGearKey],
                                [NSValue valueWithPointer:kRYGMsgOnlyHomeKey] ]) {
            UIView *b = objc_getAssociatedObject(header, key.pointerValue);
            b.hidden = YES;
        }
        return;
    }

    RYGChromeButton *news = rygEnsureHeaderButton(header, kRYGMsgOnlyNewsKey, @"bcn_heart_outline_24", 22, 40,
                                                  self, @selector(rygMsgOnlyOpenActivity));
    RYGChromeButton *gear = rygMsgOnlyHideTabBar()
        ? rygEnsureHeaderButton(header, kRYGMsgOnlyGearKey, @"ig_icon_settings_outline_24", 22, 40,
                                self, @selector(rygMsgOnlyOpenSettings))
        : nil;
    if (!gear) ((UIView *)objc_getAssociatedObject(header, kRYGMsgOnlyGearKey)).hidden = YES;

    NSArray<UIView *> *trailing = RYGInboxTrailingButtons(header);
    UIView *ref = trailing.lastObject;
    CGFloat side = 40, x = 12;
    CGFloat y = RYGInboxRowTop(header, ref, side);
    for (RYGChromeButton *btn in @[ gear ?: NSNull.null, news ]) {
        if (![btn isKindOfClass:[RYGChromeButton class]]) continue;
        btn.frame = CGRectMake(x, y, side, side);
        RYGInboxMirrorChrome(btn, ref, header);
        [header bringSubviewToFront:btn];
        x += side + 4;
    }

    RYGChromeButton *home = objc_getAssociatedObject(header, kRYGMsgOnlyHomeKey);
    if (!rygMsgOnlyHome() || ![RYGHomeShortcutCatalog enabledActionIDs].count) {
        home.hidden = YES;
    } else {
        if (!home || home.superview != header) {
            home = [[RYGChromeButton alloc] initWithSymbol:[RYGHomeShortcutCatalog currentSymbol] pointSize:22 diameter:side];
            home.iconTint = [UIColor labelColor];
            home.bubbleColor = [UIColor clearColor];
            home.translatesAutoresizingMaskIntoConstraints = YES;
            home.accessibilityLabel = @"RyukGram";
            [header addSubview:home];
            objc_setAssociatedObject(header, kRYGMsgOnlyHomeKey, home, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        }
        home.hidden = NO;
        [RYGHomeShortcutCatalog configureButton:home];
        [RYGHomeShortcutCatalog updateBadgeOnButton:home];

        UIView *leftNative = nil;
        for (UIView *b in trailing) {
            if (b.hidden || b.alpha < 0.05) continue;
            leftNative = b;
            break;
        }
        CGFloat rightEdge = leftNative ? CGRectGetMinX([leftNative convertRect:leftNative.bounds toView:header]) - 8
                                       : header.bounds.size.width - 12;
        home.frame = CGRectMake(rightEdge - side, y, side, side);
        RYGInboxMirrorChrome(home, ref, header);
        [header bringSubviewToFront:home];
    }

}

%new - (void)rygMsgOnlyOpenActivity {
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

%new - (void)rygMsgOnlyOpenSettings {
    UIViewController *vc = (UIViewController *)self;
    [RYGUtils showSettingsVC:vc.view.window];
}

%end

%end

%ctor {
    BOOL wanted = [RYGUtils getBoolPref:@"messages_only"] ||
                  [RYGUtils getBoolPref:@"messages_only_schedule_enabled"];
    if (!wanted) return;
    sRYGMsgOnlyHooksActive = YES;
    %init(RYGMessagesOnlyGroup);
}
