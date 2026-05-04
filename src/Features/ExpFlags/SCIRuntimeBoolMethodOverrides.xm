#import "SCIExpFlags.h"
#import <Foundation/Foundation.h>
#import <objc/runtime.h>
#import <substrate.h>

static NSString *const kSCIRuntimeObjCOverridePrefix = @"objc:";
static NSString *const kSCIRuntimeBoolObservedDefaultsKey = @"sci_runtime_bool_observed_defaults";
static NSMutableDictionary<NSString *, NSValue *> *gSCIRuntimeOriginalBoolIMPs = nil;
static dispatch_once_t gSCIRuntimeInstallOnce;

static BOOL SCIRuntimeMethodReturnsBool(Method m) {
    if (!m) return NO;
    char rt[64] = {0};
    method_getReturnType(m, rt, sizeof(rt));
    return rt[0] == 'B' || rt[0] == 'c';
}

static NSString *SCIRuntimeOverrideKey(BOOL isClassMethod, NSString *className, NSString *methodName) {
    return [NSString stringWithFormat:@"objc:%@%@ %@", isClassMethod ? @"+" : @"-", className ?: @"", methodName ?: @""];
}

static BOOL SCIRuntimeStringLooksInteresting(NSString *className, NSString *methodName) {
    NSString *s = [NSString stringWithFormat:@"%@ %@", className ?: @"", methodName ?: @""].lowercaseString;
    return [s containsString:@"experiment"] || [s containsString:@"enabled"] || [s containsString:@"isenabled"] || [s containsString:@"shouldenable"] || [s containsString:@"shouldshow"] || [s containsString:@"eligib"] || [s containsString:@"launcher"] || [s containsString:@"dogfood"] || [s containsString:@"internal"] || [s containsString:@"mobileconfig"] || [s containsString:@"easygating"] || [s containsString:@"blend"] || [s containsString:@"autofill"];
}

static NSMutableDictionary *SCIRuntimeLoadObservedDefaults(void) {
    NSDictionary *d = [[NSUserDefaults standardUserDefaults] dictionaryForKey:kSCIRuntimeBoolObservedDefaultsKey];
    return d ? [d mutableCopy] : [NSMutableDictionary dictionary];
}

static void SCIRuntimePersistObservedDefault(NSString *key, BOOL value) {
    if (!key.length) return;
    NSMutableDictionary *d = SCIRuntimeLoadObservedDefaults();
    NSNumber *old = d[key];
    if (old && old.boolValue == value) return;
    d[key] = @(value);
    [[NSUserDefaults standardUserDefaults] setObject:d forKey:kSCIRuntimeBoolObservedDefaultsKey];
}

static NSString *SCIRuntimeKeyForReceiver(id receiver, SEL sel) {
    NSString *methodName = NSStringFromSelector(sel);
    BOOL isClassMethod = object_isClass(receiver);
    Class cls = isClassMethod ? (Class)receiver : object_getClass(receiver);
    while (cls) {
        NSString *className = NSStringFromClass(cls);
        NSString *key = SCIRuntimeOverrideKey(isClassMethod, className, methodName);
        if (gSCIRuntimeOriginalBoolIMPs[key]) return key;
        cls = class_getSuperclass(cls);
    }
    return nil;
}

static BOOL SCIRuntimeObservedBoolIMP(id self, SEL _cmd) {
    NSString *key = SCIRuntimeKeyForReceiver(self, _cmd);
    NSValue *origValue = key ? gSCIRuntimeOriginalBoolIMPs[key] : nil;

    BOOL original = NO;
    if (origValue) {
        BOOL (*orig)(id, SEL) = (BOOL (*)(id, SEL))origValue.pointerValue;
        if (orig) original = orig(self, _cmd);
    }

    if (key) {
        SCIRuntimePersistObservedDefault(key, original);
        SCIExpFlagOverride override = [SCIExpFlags overrideForName:key];
        if (override == SCIExpFlagOverrideTrue) return YES;
        if (override == SCIExpFlagOverrideFalse) return NO;
    }
    return original;
}

static void SCIInstallRuntimeBoolMethodOverrides(void) {
    dispatch_once(&gSCIRuntimeInstallOnce, ^{
        gSCIRuntimeOriginalBoolIMPs = [NSMutableDictionary dictionary];
        NSUInteger installed = 0;

        unsigned int classCount = 0;
        Class *classes = objc_copyClassList(&classCount);
        for (unsigned int c = 0; c < classCount; c++) {
            Class cls = classes[c];
            NSString *className = NSStringFromClass(cls);
            if (!className.length) continue;

            for (int pass = 0; pass < 2; pass++) {
                BOOL isClassMethod = (pass == 1);
                Class methodClass = isClassMethod ? object_getClass(cls) : cls;
                if (!methodClass) continue;

                unsigned int methodCount = 0;
                Method *methods = class_copyMethodList(methodClass, &methodCount);
                for (unsigned int i = 0; i < methodCount; i++) {
                    Method method = methods[i];
                    if (!SCIRuntimeMethodReturnsBool(method)) continue;
                    if (method_getNumberOfArguments(method) != 2) continue;

                    SEL sel = method_getName(method);
                    NSString *methodName = NSStringFromSelector(sel);
                    if (!SCIRuntimeStringLooksInteresting(className, methodName)) continue;

                    NSString *key = SCIRuntimeOverrideKey(isClassMethod, className, methodName);
                    if (gSCIRuntimeOriginalBoolIMPs[key]) continue;

                    IMP original = NULL;
                    MSHookMessageEx(methodClass, sel, (IMP)SCIRuntimeObservedBoolIMP, &original);
                    if (original) {
                        gSCIRuntimeOriginalBoolIMPs[key] = [NSValue valueWithPointer:(const void *)original];
                        installed++;
                    }
                }
                if (methods) free(methods);
            }
        }
        if (classes) free(classes);

        NSLog(@"[RyukGram][RuntimeExperiments] installed %lu observed BOOL getter hooks", (unsigned long)installed);
    });
}

%ctor {
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.8 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
        SCIInstallRuntimeBoolMethodOverrides();
    });
}
