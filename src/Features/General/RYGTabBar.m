#import "RYGTabBar.h"
#import "../../Utils.h"
#import "../../InstagramHeaders.h"
#import <objc/runtime.h>
#import <objc/message.h>

NSString *const RYGTabKeyFeed     = @"FEED";
NSString *const RYGTabKeyReels    = @"CLIPS";
NSString *const RYGTabKeyMessages = @"DIRECT";
NSString *const RYGTabKeyExplore  = @"SEARCH";
NSString *const RYGTabKeyProfile  = @"PROFILE";
NSString *const RYGTabKeyCreate   = @"SHARE";

@implementation RYGTabBar

+ (NSArray<NSString *> *)catalogTabKeys {
    return @[ RYGTabKeyFeed, RYGTabKeyReels, RYGTabKeyMessages,
              RYGTabKeyExplore, RYGTabKeyProfile, RYGTabKeyCreate ];
}

+ (NSString *)hidePrefForTabKey:(NSString *)tabKey {
    static NSDictionary *map;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        map = @{
            RYGTabKeyFeed:     @"hide_feed_tab",
            RYGTabKeyReels:    @"hide_reels_tab",
            RYGTabKeyMessages: @"hide_messages_tab",
            RYGTabKeyExplore:  @"hide_explore_tab",
            RYGTabKeyProfile:  @"hide_profile_tab",
            RYGTabKeyCreate:   @"hide_create_tab",
        };
    });
    return map[tabKey ?: @""];
}

+ (NSString *)tabKeyForLaunchTabValue:(NSString *)value {
    static NSDictionary *map;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        map = @{
            @"feed":    RYGTabKeyFeed,
            @"reels":   RYGTabKeyReels,
            @"inbox":   RYGTabKeyMessages,
            @"explore": RYGTabKeyExplore,
            @"profile": RYGTabKeyProfile,
        };
    });
    return map[value ?: @""];
}

+ (BOOL)messagesOnlyActive {
    return [RYGUtils getBoolPref:@"messages_only"];
}

// Messages-only strips its own buttons, so the hide prefs stay out of its way.
+ (BOOL)isTabKeyVisible:(NSString *)tabKey {
    if ([self messagesOnlyActive]) return YES;
    NSString *pref = [self hidePrefForTabKey:tabKey];
    return !(pref.length && [RYGUtils getBoolPref:pref]);
}

+ (NSArray<NSString *> *)orderedTabKeys {
    NSString *orderPref = [RYGUtils getStringPref:@"nav_tab_order"];
    NSMutableArray *shown = [NSMutableArray array];
    NSMutableArray *hidden = [NSMutableArray array];

    for (NSString *key in [orderPref componentsSeparatedByString:@","]) {
        if (![[self catalogTabKeys] containsObject:key]) continue;
        if ([shown containsObject:key] || [hidden containsObject:key]) continue;
        [[self isTabKeyVisible:key] ? shown : hidden addObject:key];
    }
    for (NSString *key in [self catalogTabKeys]) {
        if ([shown containsObject:key] || [hidden containsObject:key]) continue;
        [[self isTabKeyVisible:key] ? shown : hidden addObject:key];
    }

    [shown addObjectsFromArray:hidden];
    return shown;
}

// Create has no stable tab string across builds — keyed by subtype instead.
+ (NSString *)tabKeyForSurface:(id)surface {
    if (![surface isKindOfClass:NSClassFromString(@"IGMainAppSurfaceIntent")]) return nil;

    Ivar iv = class_getInstanceVariable([surface class], "_subtype");
    if (iv) {
        NSUInteger subtype = *(NSUInteger *)((char *)(__bridge void *)surface + ivar_getOffset(iv));
        if (subtype == 3) return RYGTabKeyCreate;
    }
    if (![surface respondsToSelector:@selector(tabStringFromSurfaceIntent)]) return nil;
    id key = ((id (*)(id, SEL))objc_msgSend)(surface, @selector(tabStringFromSurfaceIntent));
    return [key isKindOfClass:NSString.class] ? key : nil;
}

+ (BOOL)isSurfaceVisible:(id)surface {
    NSString *key = [self tabKeyForSurface:surface];
    return key.length ? [self isTabKeyVisible:key] : YES;
}

// Shown first, hidden at the tail: bar items map back by index, so a hidden tab
// left in the middle shifts every surface after it onto the wrong button.
+ (NSArray *)orderedSurfaces:(NSArray *)surfaces {
    if (![surfaces isKindOfClass:NSArray.class] || !surfaces.count) return surfaces;

    NSMutableArray *remaining = [surfaces mutableCopy];
    NSMutableArray *shown = [NSMutableArray array];
    NSMutableArray *hidden = [NSMutableArray array];

    for (NSString *key in [self orderedTabKeys]) {
        for (id surface in [remaining copy]) {
            if (![[self tabKeyForSurface:surface] isEqualToString:key]) continue;
            [[self isSurfaceVisible:surface] ? shown : hidden addObject:surface];
            [remaining removeObjectIdenticalTo:surface];
        }
    }
    for (id surface in remaining)
        [[self isSurfaceVisible:surface] ? shown : hidden addObject:surface];

    // Everything hidden would leave an empty bar.
    if (!shown.count) return surfaces;

    [shown addObjectsFromArray:hidden];
    return shown;
}

+ (NSArray *)visibleSurfaces:(NSArray *)surfaces {
    NSArray *ordered = [self orderedSurfaces:surfaces];
    NSMutableArray *kept = [NSMutableArray array];
    for (id surface in ordered)
        if ([self isSurfaceVisible:surface]) [kept addObject:surface];
    return kept.count ? kept : ordered;
}

// A hidden tab has no button, and IG would resolve tab bar visibility against
// its nav stack instead of the one on screen.
+ (id)coerceToVisibleSurface:(id)surface inController:(id)ctrl {
    if (!surface || [self isSurfaceVisible:surface]) return surface;

    NSArray *all = [RYGUtils getIvarForObj:ctrl name:"_tabBarSurfaces"];
    if (![all isKindOfClass:NSArray.class]) return surface;
    for (id candidate in [self orderedSurfaces:all])
        if ([self isSurfaceVisible:candidate]) return candidate;
    return surface;
}

+ (UIViewController *)liveController {
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

// Reordered, never trimmed: IG builds its static view controllers from this, and
// an empty result leaves the controller "not initialized" forever, so every push
// re-runs the init and stacks up another tab bar view.
+ (void)applyOrderToController:(id)ctrl {
    NSArray *current = [RYGUtils getIvarForObj:ctrl name:"_tabBarSurfaces"];
    if (![current isKindOfClass:NSArray.class] || !current.count) return;

    NSArray *ordered = [self orderedSurfaces:current];
    if (![ordered isEqualToArray:current])
        [RYGUtils setIvarForObj:ctrl name:"_tabBarSurfaces" value:ordered];

    // IG restores its last surface straight into the ivar, past the setters.
    id selected = [RYGUtils getIvarForObj:ctrl name:"_selectedTabBarSurface"];
    if (!selected) return;
    id fixed = [self coerceToVisibleSurface:selected inController:ctrl];
    if (fixed != selected)
        [RYGUtils setIvarForObj:ctrl name:"_selectedTabBarSurface" value:fixed];
}

+ (NSArray<UIView *> *)orderedVisibleButtonsForController:(id)ctrl {
    NSArray *surfaces = [RYGUtils getIvarForObj:ctrl name:"_tabBarSurfaces"];
    SEL btnSel = @selector(buttonForTabBarSurface:);
    if (![surfaces isKindOfClass:NSArray.class] || ![ctrl respondsToSelector:btnSel]) return nil;

    NSMutableArray<UIView *> *ordered = [NSMutableArray array];
    for (id surface in [self orderedSurfaces:surfaces]) {
        if (![self isSurfaceVisible:surface]) continue;
        UIView *button = ((id (*)(id, SEL, id))objc_msgSend)(ctrl, btnSel, surface);
        if (!button || [ordered indexOfObjectIdenticalTo:button] != NSNotFound) continue;
        [ordered addObject:button];
    }
    return ordered;
}

@end
