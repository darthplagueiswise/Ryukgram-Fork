#import "../../Utils.h"
#import <objc/runtime.h>
#import <substrate.h>

static BOOL SCIIsMutualInterestOn(void) {
    return [SCIUtils getBoolPref:@"igt_mutual_interest"];
}

static BOOL SCIIsIcebreakerOn(void) {
    return [SCIUtils getBoolPref:@"igt_icebreaker"];
}

static BOOL SCIForceYES(id self, SEL _cmd) { return YES; }

static void SCIHookMutualBool(NSString *selectorName, IMP replacement) {
    Class cls = NSClassFromString(@"_TtC32IGDirectMutualInterestIcebreaker42IGDirectMutualInterestFeatureGatingService");
    if (!cls) return;
    SEL sel = NSSelectorFromString(selectorName);
    if (!class_getInstanceMethod(cls, sel)) return;
    IMP original = NULL;
    MSHookMessageEx(cls, sel, replacement, &original);
}

%ctor {
    if (!SCIIsMutualInterestOn() && !SCIIsIcebreakerOn()) return;

    if (SCIIsMutualInterestOn() || SCIIsIcebreakerOn()) {
        SCIHookMutualBool(@"isMutualFollowEnabled", (IMP)SCIForceYES);
        SCIHookMutualBool(@"isMutuallyLikedReelsIcebreakerEnabled", (IMP)SCIForceYES);
    }
    if (SCIIsIcebreakerOn()) {
        SCIHookMutualBool(@"isLargerCardEnabled", (IMP)SCIForceYES);
        SCIHookMutualBool(@"isInfiniteReelsChainingEnabled", (IMP)SCIForceYES);
    }
}
