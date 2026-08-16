// Force launch into a chosen tab (messages_only inbox, or the launch_tab pref).
// IG restores its last tab asynchronously, so we coerce the surface setter until
// the user's first deliberate tab tap rather than forcing the tab just once.

#import "../../Utils.h"
#import "../../InstagramHeaders.h"
#import <objc/runtime.h>
#import <objc/message.h>

static NSString *rygDesiredSurfaceString(void) {
    if ([RYGUtils getBoolPref:@"messages_only"]) return @"DIRECT";
    NSString *p = [RYGUtils getStringPref:@"launch_tab"];
    if ([p isEqualToString:@"feed"])    return @"FEED";
    if ([p isEqualToString:@"explore"]) return @"SEARCH";
    if ([p isEqualToString:@"reels"])   return @"CLIPS";
    if ([p isEqualToString:@"inbox"])   return @"DIRECT";
    if ([p isEqualToString:@"profile"]) return @"PROFILE";
    return nil;
}

static const void *kRYGLaunchLockReleasedKey = &kRYGLaunchLockReleasedKey;

static BOOL rygLaunchLockReleased(id ctrl) {
    return [objc_getAssociatedObject(ctrl, &kRYGLaunchLockReleasedKey) boolValue];
}

void rygReleaseLaunchTabLock(id ctrl) {
    objc_setAssociatedObject(ctrl, &kRYGLaunchLockReleasedKey, @YES, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
}

static id rygSurfaceObjectForString(id ctrl, NSString *want) {
    if (!want) return nil;
    NSArray *surfaces = nil;
    if ([ctrl respondsToSelector:@selector(allTabBarSurfaces)])
        surfaces = [ctrl allTabBarSurfaces];
    if (![surfaces isKindOfClass:[NSArray class]])
        surfaces = [RYGUtils getIvarForObj:ctrl name:"_tabBarSurfaces"];
    for (id s in surfaces) {
        if ([s respondsToSelector:@selector(tabStringFromSurfaceIntent)] &&
            [[s tabStringFromSurfaceIntent] isEqualToString:want])
            return s;
    }
    return nil;
}

static id rygCoerceSurface(id ctrl, id surface) {
    NSString *want = rygDesiredSurfaceString();
    if (!want || rygLaunchLockReleased(ctrl)) return surface;
    if (![surface respondsToSelector:@selector(tabStringFromSurfaceIntent)]) return surface;
    NSString *got = [surface tabStringFromSurfaceIntent];
    if ([got isEqualToString:want]) return surface;
    id desired = rygSurfaceObjectForString(ctrl, want);
    return desired ?: surface;
}

%hook IGTabBarController

- (void)setSelectedTabBarSurface:(id)surface animated:(BOOL)animated animateIndicator:(BOOL)animateIndicator {
    %orig(rygCoerceSurface(self, surface), animated, animateIndicator);
}

- (void)setSelectedTabBarSurface:(id)surface animated:(BOOL)animated {
    %orig(rygCoerceSurface(self, surface), animated);
}

- (void)viewWillAppear:(BOOL)animated {
    %orig;
    static BOOL forced = NO;
    if (forced) return;
    NSString *want = rygDesiredSurfaceString();
    if (!want) return;
    forced = YES;
    // Only force when IG never set the surface itself — otherwise coercion
    // already handled it and re-selecting mid-appearance is a redundant transition.
    id cur = [self respondsToSelector:@selector(selectedTabBarSurface)] ? [self selectedTabBarSurface] : nil;
    NSString *curStr = [cur respondsToSelector:@selector(tabStringFromSurfaceIntent)] ? [cur tabStringFromSurfaceIntent] : nil;
    if ([curStr isEqualToString:want]) return;
    id desired = rygSurfaceObjectForString(self, want);
    if (desired)
        [self setSelectedTabBarSurface:desired animated:NO animateIndicator:NO];
}

- (void)_timelineButtonPressed      { rygReleaseLaunchTabLock(self); %orig; }
- (void)_exploreButtonPressed       { rygReleaseLaunchTabLock(self); %orig; }
- (void)_discoverVideoButtonPressed { rygReleaseLaunchTabLock(self); %orig; }
- (void)_directInboxButtonPressed   { rygReleaseLaunchTabLock(self); %orig; }
- (void)_profileButtonPressed       { rygReleaseLaunchTabLock(self); %orig; }
- (void)_cameraButtonPressed        { rygReleaseLaunchTabLock(self); %orig; }
- (void)_newsButtonPressed          { rygReleaseLaunchTabLock(self); %orig; }
- (void)_streamsButtonPressed       { rygReleaseLaunchTabLock(self); %orig; }

%end
