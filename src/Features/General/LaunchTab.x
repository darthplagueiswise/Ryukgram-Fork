// Force launch into a chosen tab. IG restores its last tab asynchronously, so the
// surface setter stays coerced until the first deliberate tab tap.

#import "../../Utils.h"
#import "../../InstagramHeaders.h"
#import "RYGTabBar.h"
#import <objc/runtime.h>

static NSString *rygDesiredSurfaceString(void) {
    if ([RYGTabBar messagesOnlyActive]) return RYGTabKeyMessages;
    NSString *key = [RYGTabBar tabKeyForLaunchTabValue:[RYGUtils getStringPref:@"launch_tab"]];
    // A hidden tab has no button to get back from.
    return [RYGTabBar isTabKeyVisible:key] ? key : nil;
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
    for (id s in surfaces)
        if ([[RYGTabBar tabKeyForSurface:s] isEqualToString:want]) return s;
    return nil;
}

static id rygCoerceSurface(id ctrl, id surface) {
    NSString *want = rygDesiredSurfaceString();
    if (!want || rygLaunchLockReleased(ctrl)) return surface;
    if ([[RYGTabBar tabKeyForSurface:surface] isEqualToString:want]) return surface;
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
    // Coercion already handled it if IG set the surface itself.
    id cur = [self respondsToSelector:@selector(selectedTabBarSurface)] ? [self selectedTabBarSurface] : nil;
    if ([[RYGTabBar tabKeyForSurface:cur] isEqualToString:want]) return;
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
