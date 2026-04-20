// Hooks installed iff sci_exp_flags_enabled.
// Override: MetaLocalExperiment group{,Peek}Name — substring-match _experimentName, return "test"/nil.
// View-only: IGMobileConfigContextManager get{Bool,Int64,Double,String}[:withDefault:] — record, no override.

#import "../../Utils.h"
#import "SCIExpFlags.h"
#import <objc/runtime.h>
#import <objc/message.h>
#import <substrate.h>

static NSString *experimentNameOf(id obj) {
    if (!obj) return nil;
    Ivar iv = class_getInstanceVariable(object_getClass(obj), "_experimentName");
    if (!iv) return nil;
    @try {
        id v = object_getIvar(obj, iv);
        if ([v isKindOfClass:[NSString class]]) return v;
    } @catch (__unused id e) {}
    return nil;
}

static id overrideGroupFor(NSString *expName, id origGroup) {
    if (!expName.length) return origGroup;
    NSString *lower = expName.lowercaseString;
    for (NSString *key in [SCIExpFlags allOverriddenNames]) {
        if (![lower containsString:key.lowercaseString]) continue;
        SCIExpFlagOverride o = [SCIExpFlags overrideForName:key];
        if (o == SCIExpFlagOverrideTrue) return @"test";
        if (o == SCIExpFlagOverrideFalse) return nil;
    }
    return origGroup;
}

static id (*orig_groupName)(id, SEL);
static id new_groupName(id self, SEL _cmd) {
    id orig = orig_groupName ? orig_groupName(self, _cmd) : nil;
    NSString *name = experimentNameOf(self);
    [SCIExpFlags recordExperimentName:name group:[orig isKindOfClass:[NSString class]] ? orig : nil];
    return overrideGroupFor(name, orig);
}

static id (*orig_peekGroupName)(id, SEL);
static id new_peekGroupName(id self, SEL _cmd) {
    id orig = orig_peekGroupName ? orig_peekGroupName(self, _cmd) : nil;
    NSString *name = experimentNameOf(self);
    [SCIExpFlags recordExperimentName:name group:[orig isKindOfClass:[NSString class]] ? orig : nil];
    return overrideGroupFor(name, orig);
}

static void installHook(Class cls, NSString *selName, IMP newImp, IMP *origOut) {
    if (!cls) return;
    SEL s = NSSelectorFromString(selName);
    if (!class_getInstanceMethod(cls, s)) return;
    MSHookMessageEx(cls, s, newImp, origOut);
}

%ctor {
    if (![SCIUtils getBoolPref:@"sci_exp_flags_enabled"]) return;

    if ([SCIExpFlags checkAndHandleCrashLoop]) {
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(5 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
            [SCIUtils showToastForDuration:4.0 title:@"Exp flags reset after repeated crashes"];
        });
    }

    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(30 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
        [SCIExpFlags markLaunchStable];
    });

    Class meta = NSClassFromString(@"MetaLocalExperiment");
    installHook(meta, @"groupName", (IMP)new_groupName, (IMP *)&orig_groupName);
    installHook(meta, @"peekGroupName", (IMP)new_peekGroupName, (IMP *)&orig_peekGroupName);
}
