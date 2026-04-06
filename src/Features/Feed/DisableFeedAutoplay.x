#import "../../Utils.h"
#import <objc/runtime.h>
#import <substrate.h>

// IGFeedPlayback.IGFeedPlaybackStrategy gained new init parameters in IG 423+.
// Both the 2-arg and 3-arg variants are hooked to force shouldDisableAutoplay=YES.
// Hooked via MSHookMessageEx in %ctor since the class has a Swift-mangled name.

static id (*orig_initStrategy2)(id, SEL, BOOL, BOOL);
static id new_initStrategy2(id self, SEL _cmd, BOOL shouldDisable, BOOL shouldClearStale) {
    if ([SCIUtils getBoolPref:@"disable_feed_autoplay"]) shouldDisable = YES;
    return orig_initStrategy2(self, _cmd, shouldDisable, shouldClearStale);
}

static id (*orig_initStrategy3)(id, SEL, BOOL, BOOL, BOOL);
static id new_initStrategy3(id self, SEL _cmd, BOOL shouldDisable, BOOL shouldClearStale, BOOL bypassForVoiceover) {
    if ([SCIUtils getBoolPref:@"disable_feed_autoplay"]) shouldDisable = YES;
    return orig_initStrategy3(self, _cmd, shouldDisable, shouldClearStale, bypassForVoiceover);
}

%ctor {
    Class cls = objc_getClass("IGFeedPlayback.IGFeedPlaybackStrategy");
    if (!cls) return;

    SEL sel2 = @selector(initWithShouldDisableAutoplay:shouldClearStaleReservation:);
    if ([cls instancesRespondToSelector:sel2])
        MSHookMessageEx(cls, sel2, (IMP)new_initStrategy2, (IMP *)&orig_initStrategy2);

    SEL sel3 = @selector(initWithShouldDisableAutoplay:shouldClearStaleReservation:shouldBypassDisabledAutoplayForVoiceover:);
    if ([cls instancesRespondToSelector:sel3])
        MSHookMessageEx(cls, sel3, (IMP)new_initStrategy3, (IMP *)&orig_initStrategy3);
}
