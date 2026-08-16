#import "../../Utils.h"

// Create has no stable tab string across builds — keyed by subtype instead.
static NSString *rygTabKeyForSurface(IGMainAppSurfaceIntent *surface) {
    if ([(NSNumber *)[surface valueForKey:@"_subtype"] unsignedIntegerValue] == 3) return @"SHARE";
    return [surface tabStringFromSurfaceIntent];
}

static BOOL ryg_surfaceVisible(IGMainAppSurfaceIntent *surface) {
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

    NSString *hidePref = hidePrefForKey[rygTabKeyForSurface(surface) ?: @""];
    return !(hidePref.length && [RYGUtils getBoolPref:hidePref]);
}

// nav_tab_order keys first, unknown surfaces appended in original order.
static NSArray *rygOrderSurfacesArray(NSArray *surfaces) {
    NSString *orderPref = [RYGUtils getStringPref:@"nav_tab_order"];
    if (!orderPref.length) return surfaces;

    NSMutableArray *remaining = [surfaces mutableCopy];
    NSMutableArray *ordered = [NSMutableArray array];

    for (NSString *key in [orderPref componentsSeparatedByString:@","]) {
        for (IGMainAppSurfaceIntent *surface in [remaining copy]) {
            if ([rygTabKeyForSurface(surface) isEqualToString:key]) {
                [ordered addObject:surface];
                [remaining removeObjectIdenticalTo:surface];
            }
        }
    }

    [ordered addObjectsFromArray:remaining];
    return ordered;
}

static NSArray *ryg_filterSurfaces(NSArray *surfaces) {
    // Messages-only owns tab visibility — hide prefs must not remove
    // DIRECT/PROFILE from under it. Order still applies.
    if ([RYGUtils getBoolPref:@"messages_only"]) return rygOrderSurfacesArray(surfaces);

    NSMutableArray *kept = [NSMutableArray array];
    for (IGMainAppSurfaceIntent *surface in surfaces) {
        if (![surface isKindOfClass:%c(IGMainAppSurfaceIntent)]) break;
        if (ryg_surfaceVisible(surface)) [kept addObject:surface];
    }

    // All tabs hidden would leave an empty tab bar — fall back to stock.
    return rygOrderSurfacesArray(kept.count ? kept : surfaces);
}

// Buttons are built lazily from _tabBarSurfaces, so the custom order has to be
// in place before every build/layout pass — _layoutTabBar alone is too late
// (buttons already positioned, only the selection mapping would shift).
static void rygApplyTabBarSurfaces(id ctrl) {
    NSArray *current = [RYGUtils getIvarForObj:ctrl name:"_tabBarSurfaces"];
    if (![current isKindOfClass:NSArray.class] || !current.count) return;
    NSArray *applied = ryg_filterSurfaces(current);
    if (![applied isEqualToArray:current]) {
        [RYGUtils setIvarForObj:ctrl name:"_tabBarSurfaces" value:applied];
    }
}


%hook IGTabBarControllerSwipeCoordinator
- (id)initWithSurfaces:(id)surfaces parentViewController:(id)controller enableHaptics:(_Bool)haptics launcherSet:(id)set {
    // Keeps the swipeable page order in step with the tab bar
    return %orig(ryg_filterSurfaces(surfaces), controller, haptics, set);
}
%end

%hook IGTabBarController
- (void)viewDidLoad {
    rygApplyTabBarSurfaces(self);
    %orig;
}

- (void)_initializeAndConfigureBarButtonsIfNeeded {
    rygApplyTabBarSurfaces(self);
    %orig;
}

- (void)_updateTabBarButtonsAndUpdateViewControllersIfNeeded {
    rygApplyTabBarSurfaces(self);
    %orig;
}

- (void)_layoutTabBar {
    rygApplyTabBarSurfaces(self);
    %orig;
}

- (id)_buttonForTabBarSurface:(id)surface {
    // Prevents the button from being added to the tab bar
    id button = %orig(surface);

    // Messages-only manages its own buttons — don't nil DIRECT/PROFILE under it.
    if (!ryg_surfaceVisible(surface) && ![RYGUtils getBoolPref:@"messages_only"]) {
        return nil;
    }

    return button;
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