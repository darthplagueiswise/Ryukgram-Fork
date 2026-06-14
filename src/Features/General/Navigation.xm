#import "../../Utils.h"

// Create has no stable tab string across builds — keyed by subtype instead.
static NSString *sciTabKeyForSurface(IGMainAppSurfaceIntent *surface) {
    if ([(NSNumber *)[surface valueForKey:@"_subtype"] unsignedIntegerValue] == 3) return @"SHARE";
    return [surface tabStringFromSurfaceIntent];
}

BOOL isSurfaceShown(IGMainAppSurfaceIntent *surface) {
    static NSDictionary *hidePrefForKey;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        hidePrefForKey = @{
            @"FEED": @"hide_feed_tab",
            @"CLIPS": @"hide_reels_tab",
            @"DIRECT": @"hide_messages_tab",
            @"SEARCH": @"hide_explore_tab",
            @"SHARE": @"hide_create_tab",
            @"PROFILE": @"hide_profile_tab",
        };
    });

    NSString *hidePref = hidePrefForKey[sciTabKeyForSurface(surface) ?: @""];
    return !(hidePref && [SCIUtils getBoolPref:hidePref]);
}

// nav_tab_order keys first, unknown surfaces appended in original order.
static NSArray *sciOrderSurfacesArray(NSArray *surfaces) {
    NSString *orderPref = [SCIUtils getStringPref:@"nav_tab_order"];
    if (!orderPref.length) return surfaces;

    NSMutableArray *remaining = [surfaces mutableCopy];
    NSMutableArray *ordered = [NSMutableArray array];

    for (NSString *key in [orderPref componentsSeparatedByString:@","]) {
        for (IGMainAppSurfaceIntent *surface in [remaining copy]) {
            if ([sciTabKeyForSurface(surface) isEqualToString:key]) {
                [ordered addObject:surface];
                [remaining removeObjectIdenticalTo:surface];
            }
        }
    }

    [ordered addObjectsFromArray:remaining];
    return ordered;
}

NSArray *filterSurfacesArray(NSArray *surfaces) {
    // Messages-only owns tab visibility — hide prefs must not remove
    // DIRECT/PROFILE from under it. Order still applies.
    if ([SCIUtils getBoolPref:@"messages_only"]) {
        return sciOrderSurfacesArray(surfaces);
    }

    NSMutableArray *filteredSurfaces = [NSMutableArray array];

    for (IGMainAppSurfaceIntent *surface in surfaces) {
        if (![surface isKindOfClass:%c(IGMainAppSurfaceIntent)]) break;

        if (isSurfaceShown(surface)) {
            [filteredSurfaces addObject:surface];
        }
    }

    // All tabs hidden would leave an empty tab bar — fall back to stock.
    if (!filteredSurfaces.count && surfaces.count) {
        return sciOrderSurfacesArray(surfaces);
    }

    return sciOrderSurfacesArray(filteredSurfaces);
}

// Buttons are built lazily from _tabBarSurfaces, so the custom order has to be
// in place before every build/layout pass — _layoutTabBar alone is too late
// (buttons already positioned, only the selection mapping would shift).
static void sciApplyTabBarSurfaces(id ctrl) {
    NSArray *current = [SCIUtils getIvarForObj:ctrl name:"_tabBarSurfaces"];
    if (![current isKindOfClass:NSArray.class] || !current.count) return;
    NSArray *applied = filterSurfacesArray(current);
    if (![applied isEqualToArray:current]) {
        [SCIUtils setIvarForObj:ctrl name:"_tabBarSurfaces" value:applied];
    }
}

///////////////////////////////////////////////

%hook IGTabBarControllerSwipeCoordinator
- (id)initWithSurfaces:(id)surfaces parentViewController:(id)controller enableHaptics:(_Bool)haptics launcherSet:(id)set {
    // Keeps the swipeable page order in step with the tab bar
    return %orig(filterSurfacesArray(surfaces), controller, haptics, set);
}
%end

%hook IGTabBarController
- (void)viewDidLoad {
    sciApplyTabBarSurfaces(self);
    %orig;
}

- (void)_initializeAndConfigureBarButtonsIfNeeded {
    sciApplyTabBarSurfaces(self);
    %orig;
}

- (void)_updateTabBarButtonsAndUpdateViewControllersIfNeeded {
    sciApplyTabBarSurfaces(self);
    %orig;
}

- (void)_layoutTabBar {
    sciApplyTabBarSurfaces(self);
    %orig;
}

- (id)_buttonForTabBarSurface:(id)surface {
    // Prevents the button from being added to the tab bar
    id button = %orig(surface);

    // Messages-only manages its own buttons — don't nil DIRECT/PROFILE under it.
    if (!isSurfaceShown(surface) && ![SCIUtils getBoolPref:@"messages_only"]) {
        return nil;
    }

    return button;
}
%end

// Demangled name: IGNavConfiguration.IGNavConfiguration
%hook _TtC18IGNavConfiguration18IGNavConfiguration
- (BOOL)isTabSwipingEnabled {
    // Swipe lands on stripped tabs in messages-only.
    if ([SCIUtils getBoolPref:@"messages_only"]) return NO;
    if ([[SCIUtils getStringPref:@"swipe_nav_tabs"] isEqualToString:@"enabled"]) return YES;
    else if ([[SCIUtils getStringPref:@"swipe_nav_tabs"] isEqualToString:@"disabled"]) return NO;
    return %orig;
}
- (void)setIsTabSwipingEnabled:(BOOL)arg1 {
    return;
}
%end
