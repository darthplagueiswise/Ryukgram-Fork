#import "SCIExpFlags.h"
#import "SCIDexKitStore.h"
#import <Foundation/Foundation.h>
#import <objc/runtime.h>
#import <dlfcn.h>
#import <substrate.h>

static NSMutableDictionary<NSString *, NSValue *> *gSCIDexKitOriginalBoolIMPs;
static NSMutableSet<NSString *> *gSCIDexKitInstalledKeys;

static NSString *SCIDexKitBasename(const char *path) {
    if (!path) return @"";
    const char *slash = strrchr(path, '/');
    return [NSString stringWithUTF8String:(slash ? slash + 1 : path)] ?: @"";
}

static BOOL SCIDexKitImageAllowed(NSString *imageName) {
    if (!imageName.length) return NO;
    NSString *mainImageName = NSBundle.mainBundle.executablePath.lastPathComponent ?: @"";
    if ([imageName isEqualToString:mainImageName]) return YES;
    if ([imageName isEqualToString:@"FBSharedFramework"]) return YES;
    return NO;
}

static BOOL SCIDexKitMethodReturnsBool(Method m) {
    if (!m) return NO;
    char rt[32] = {0};
    method_getReturnType(m, rt, sizeof(rt));
    return rt[0] == 'B' || rt[0] == 'c';
}

static NSString *SCIDexKitKeyForReceiver(id receiver, SEL sel) {
    NSString *methodName = NSStringFromSelector(sel);
    BOOL classMethod = object_isClass(receiver);
    Class cls = classMethod ? (Class)receiver : object_getClass(receiver);

    while (cls) {
        NSString *className = NSStringFromClass(cls);
        NSString *key = [SCIDexKitStore boolGetterKeyWithClassName:className methodName:methodName classMethod:classMethod];
        if (gSCIDexKitOriginalBoolIMPs[key]) return key;
        cls = class_getSuperclass(cls);
    }
    return nil;
}

static BOOL SCIDexKitBoolGetterReplacement(id self, SEL _cmd) {
    NSString *key = SCIDexKitKeyForReceiver(self, _cmd);
    if (!key.length) return NO;

    // If the user explicitly changed the switch, do not call the original getter.
    // This prevents the classic loop/crash case where the original implementation
    // re-enters the same selector path while an override is already active.
    SCIExpFlagOverride override = [SCIDexKitStore overrideForKey:key];
    if (override == SCIExpFlagOverrideTrue) return YES;
    if (override == SCIExpFlagOverrideFalse) return NO;

    NSValue *origValue = gSCIDexKitOriginalBoolIMPs[key];
    if (!origValue) return NO;

    NSString *reentryKey = [@"sci.dexkit.reentry." stringByAppendingString:key];
    NSMutableDictionary *td = NSThread.currentThread.threadDictionary;
    if ([td[reentryKey] boolValue]) {
        NSNumber *known = [SCIDexKitStore observedBoolGetterValueForKey:key];
        return known ? known.boolValue : NO;
    }

    BOOL original = NO;
    td[reentryKey] = @YES;
    @try {
        BOOL (*orig)(id, SEL) = (BOOL (*)(id, SEL))origValue.pointerValue;
        if (orig) original = orig(self, _cmd);
    } @finally {
        [td removeObjectForKey:reentryKey];
    }

    [SCIDexKitStore setObservedBoolGetterValue:original forKey:key];
    return original;
}

extern "C" BOOL SCIDexKitInstallBoolGetterHook(NSString *key,
                                               NSString *className,
                                               NSString *methodName,
                                               BOOL classMethod) {
    if (!key.length || !className.length || !methodName.length) return NO;

    @synchronized([SCIExpFlags class]) {
        if (!gSCIDexKitOriginalBoolIMPs) gSCIDexKitOriginalBoolIMPs = [NSMutableDictionary dictionary];
        if (!gSCIDexKitInstalledKeys) gSCIDexKitInstalledKeys = [NSMutableSet set];
        if ([gSCIDexKitInstalledKeys containsObject:key]) return YES;

        Class cls = NSClassFromString(className);
        if (!cls) return NO;

        SEL sel = NSSelectorFromString(methodName);
        Method method = classMethod ? class_getClassMethod(cls, sel) : class_getInstanceMethod(cls, sel);
        if (!method) return NO;
        if (!SCIDexKitMethodReturnsBool(method)) return NO;
        if (method_getNumberOfArguments(method) != 2) return NO;

        Dl_info info;
        memset(&info, 0, sizeof(info));
        if (dladdr((void *)method_getImplementation(method), &info) == 0) return NO;

        NSString *imageName = SCIDexKitBasename(info.dli_fname);
        if (!SCIDexKitImageAllowed(imageName)) {
            NSLog(@"[RyukGram][DexKitRouter] refused unsafe/non-target getter %@ image=%@", key, imageName);
            return NO;
        }

        NSString *expected = [SCIDexKitStore boolGetterKeyWithClassName:className methodName:methodName classMethod:classMethod];
        if (![expected isEqualToString:key]) return NO;

        Class hookClass = classMethod ? object_getClass(cls) : cls;
        IMP original = NULL;
        MSHookMessageEx(hookClass, sel, (IMP)SCIDexKitBoolGetterReplacement, &original);
        if (!original) return NO;

        gSCIDexKitOriginalBoolIMPs[key] = [NSValue valueWithPointer:(const void *)original];
        [gSCIDexKitInstalledKeys addObject:key];
        NSLog(@"[RyukGram][DexKitRouter] installed %@ image=%@", key, imageName);
        return YES;
    }
}

extern "C" BOOL SCIDexKitIsBoolGetterHooked(NSString *key) {
    @synchronized([SCIExpFlags class]) {
        return key.length && [gSCIDexKitInstalledKeys containsObject:key];
    }
}

static void SCIDexKitReapplySavedGetterOverrides(void) {
    NSUInteger attempted = 0;
    NSUInteger installed = 0;
    for (NSString *key in [SCIDexKitStore allBoolGetterOverrideKeys]) {
        if ([SCIDexKitStore overrideForKey:key] == SCIExpFlagOverrideOff) continue;
        NSString *className = nil;
        NSString *methodName = nil;
        BOOL classMethod = NO;
        if (![SCIDexKitStore parseBoolGetterKey:key className:&className methodName:&methodName classMethod:&classMethod]) continue;
        attempted++;
        if (SCIDexKitInstallBoolGetterHook(key, className, methodName, classMethod)) installed++;
    }
    NSLog(@"[RyukGram][DexKitRouter] reapply saved getter overrides attempted=%lu installed=%lu", (unsigned long)attempted, (unsigned long)installed);
}

%ctor {
    NSLog(@"[RyukGram][DexKitRouter] ready; no runtime sweep is installed from ctor");
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.25 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
        SCIDexKitReapplySavedGetterOverrides();
    });
}
