#import "../../Utils.h"
#import "RYGTabBar.h"

%hook IGTabBarControllerSwipeCoordinator
- (id)initWithSurfaces:(id)surfaces parentViewController:(id)controller enableHaptics:(_Bool)haptics launcherSet:(id)set {
    // Keeps the swipeable page order in step with the tab bar.
    return %orig([RYGTabBar visibleSurfaces:surfaces], controller, haptics, set);
}

// IG re-pushes the full list after button rebuilds; unfiltered, the pager keeps
// a page and a nav stack per hidden tab.
- (void)updateSurfaces:(id)surfaces {
    %orig([surfaces isKindOfClass:NSArray.class] ? [RYGTabBar visibleSurfaces:surfaces] : surfaces);
}
%end

%hook IGTabBarController
- (void)viewDidLoad {
    [RYGTabBar applyOrderToController:self];
    %orig;
}

- (void)_initializeAndConfigureBarButtonsIfNeeded {
    [RYGTabBar applyOrderToController:self];
    %orig;
}

- (void)_updateTabBarButtonsAndUpdateViewControllersIfNeeded {
    [RYGTabBar applyOrderToController:self];
    %orig;
}

- (void)_layoutTabBar {
    [RYGTabBar applyOrderToController:self];
    %orig;
}

- (id)_resolvedDefaultSurfaceIntentInTabSet {
    return [RYGTabBar coerceToVisibleSurface:%orig inController:self];
}

- (void)_setSelectedTabBarSurface:(id)surface isTabBarAction:(BOOL)action animated:(BOOL)animated navigationAction:(unsigned long long)navAction skipMainFeedFetch:(BOOL)fetch {
    %orig([RYGTabBar coerceToVisibleSurface:surface inController:self], action, animated, navAction, fetch);
}

- (void)_setSelectedTabBarSurface:(id)surface isTabBarAction:(BOOL)action animated:(BOOL)animated navigationAction:(unsigned long long)navAction skipMainFeedFetch:(BOOL)fetch animateIndicator:(BOOL)indicator {
    %orig([RYGTabBar coerceToVisibleSurface:surface inController:self], action, animated, navAction, fetch, indicator);
}

// A nil button is how a hidden tab leaves the bar; the surface itself stays.
- (id)_buttonForTabBarSurface:(id)surface {
    id button = %orig(surface);
    return [RYGTabBar isSurfaceVisible:surface] ? button : nil;
}
%end

// Demangled name: IGNavConfiguration.IGNavConfiguration
%hook _TtC18IGNavConfiguration18IGNavConfiguration
- (BOOL)isTabSwipingEnabled {
    // Swipe lands on stripped tabs in messages-only.
    if ([RYGUtils getBoolPref:@"messages_only"]) return NO;
    if ([[RYGUtils getStringPref:@"swipe_nav_tabs"] isEqualToString:@"enabled"]) return YES;
    else if ([[RYGUtils getStringPref:@"swipe_nav_tabs"] isEqualToString:@"disabled"]) return NO;
    return %orig;
}
- (void)setIsTabSwipingEnabled:(BOOL)arg1 {
    return;
}
%end