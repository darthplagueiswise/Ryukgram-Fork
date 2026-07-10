#import "../../Utils.h"
#import "../../InstagramHeaders.h"
#import <objc/runtime.h>
#import <substrate.h>

// IGMainStoryTrayDataSource is Swift-mangled on IG 434+ — hook via runtime.
static BOOL (*orig_trayIsEmpty)(id, SEL);
static BOOL hook_trayIsEmpty(id self, SEL _cmd) {
    if ([SCIUtils getBoolPref:@"hide_stories_tray"]) return YES;
    return orig_trayIsEmpty(self, _cmd);
}

// Expiring-soon stories tray has its own fetch path.
%hook IGStoryExpiringSoonTrayFetcher
- (BOOL)fetchTray {
    if ([SCIUtils getBoolPref:@"hide_stories_tray"]) return NO;
    return %orig;
}
%end

%ctor {
    Class trayDS = NSClassFromString(@"_TtC25IGMainStoryTrayDataSource25IGMainStoryTrayDataSource")
                   ?: NSClassFromString(@"IGMainStoryTrayDataSource");
    if (!trayDS) return;
    SEL sel = NSSelectorFromString(@"isEmpty");
    if (!class_getInstanceMethod(trayDS, sel)) return;
    MSHookMessageEx(trayDS, sel, (IMP)hook_trayIsEmpty, (IMP *)&orig_trayIsEmpty);
}
