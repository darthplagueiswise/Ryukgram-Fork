#import "SCIExpFlags.h"
#import <Foundation/Foundation.h>
#import <objc/runtime.h>
#import <substrate.h>

static NSString *const kSCIRuntimeObjCOverridePrefix = @"objc:";
static NSDictionary<NSString *, NSNumber *> *gSCIRuntimeForcedBoolValues = nil;

static BOOL SCIRuntimeMethodReturnsBool(Method m) {
    if (!m) return NO;
    char rt[64] = {0};
    method_getReturnType(m, rt, sizeof(rt));
    return rt[0] == 'B' || rt[0] == 'c';
}

static BOOL SCIRuntimeForcedBoolIMP(id self, SEL _cmd, ...) {
    BOOL isClassMethod = object_isClass(self);
    NSString *className = isClassMethod ? NSStringFromClass((Class)self) : NSStringFromClass(object_getClass(self));
    NSString *methodName = NSStringFromSelector(_cmd);
    NSString *key = [NSString stringWithFormat:@"objc:%@%@ %@", isClassMethod ? @"+" : @"-", className ?: @"", methodName ?: @""];
    NSNumber *forced = gSCIRuntimeForcedBoolValues[key];
    if (forced) return forced.boolValue;

    // If an instance is a subclass of the class that was hooked, walk upward and
    // resolve the persisted key for the declaring superclass.
    if (!isClassMethod) {
        Class cls = object_getClass(self);
        while ((cls = class_getSuperclass(cls))) {
            NSString *superKey = [NSString stringWithFormat:@"objc:-%@ %@", NSStringFromClass(cls), methodName ?: @""];
            forced = gSCIRuntimeForcedBoolValues[superKey];
            if (forced) return forced.boolValue;
        }
    }

    return NO;
}

static BOOL SCIParseRuntimeOverrideKey(NSString *key, BOOL *isClassMethod, NSString **className, NSString **methodName) {
    if (![key hasPrefix:kSCIRuntimeObjCOverridePrefix]) return NO;
    NSString *body = [key substringFromIndex:kSCIRuntimeObjCOverridePrefix.length];
    if (body.length < 3) return NO;
    unichar kind = [body characterAtIndex:0];
    if (kind != '+' && kind != '-') return NO;
    NSRange space = [body rangeOfString:@" "];
    if (space.location == NSNotFound || space.location <= 1 || space.location + 1 >= body.length) return NO;
    if (isClassMethod) *isClassMethod = (kind == '+');
    if (className) *className = [body substringWithRange:NSMakeRange(1, space.location - 1)];
    if (methodName) *methodName = [body substringFromIndex:space.location + 1];
    return YES;
}

static void SCIInstallRuntimeBoolMethodOverrides(void) {
    NSArray<NSString *> *names = [SCIExpFlags allOverriddenNames];
    NSMutableDictionary<NSString *, NSNumber *> *forcedValues = [NSMutableDictionary dictionary];

    for (NSString *key in names) {
        if (![key hasPrefix:kSCIRuntimeObjCOverridePrefix]) continue;
        SCIExpFlagOverride override = [SCIExpFlags overrideForName:key];
        if (override != SCIExpFlagOverrideTrue && override != SCIExpFlagOverrideFalse) continue;
        forcedValues[key] = @(override == SCIExpFlagOverrideTrue);
    }
    gSCIRuntimeForcedBoolValues = [forcedValues copy];
    if (!gSCIRuntimeForcedBoolValues.count) return;

    NSUInteger installed = 0;
    for (NSString *key in gSCIRuntimeForcedBoolValues) {
        BOOL isClassMethod = NO;
        NSString *className = nil;
        NSString *methodName = nil;
        if (!SCIParseRuntimeOverrideKey(key, &isClassMethod, &className, &methodName)) continue;

        Class cls = NSClassFromString(className);
        if (!cls) continue;
        SEL sel = NSSelectorFromString(methodName);
        Method method = isClassMethod ? class_getClassMethod(cls, sel) : class_getInstanceMethod(cls, sel);
        if (!SCIRuntimeMethodReturnsBool(method)) continue;

        Class hookClass = isClassMethod ? object_getClass(cls) : cls;
        if (!hookClass) continue;
        MSHookMessageEx(hookClass, sel, (IMP)SCIRuntimeForcedBoolIMP, NULL);
        installed++;
    }
    NSLog(@"[RyukGram][RuntimeExperiments] installed %lu forced BOOL method overrides", (unsigned long)installed);
}

%ctor {
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.8 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
        SCIInstallRuntimeBoolMethodOverrides();
    });
}
