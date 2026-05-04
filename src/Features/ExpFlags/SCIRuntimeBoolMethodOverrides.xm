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
    NSValue *origValue = key ? gSCIDexKitOriginalBoolIMPs[key] : nil;
    BOOL original = NO;

    if (origValue) {
        BOOL (*orig)(id, SEL) = (BOOL (*)(id, SEL))origValue.pointerValue;
        if (orig) original = orig(self, _cmd);
    }

    if (key.length) {
        [SCIDexKitStore setObservedBoolGetterValue:original forKey:key];
        SCIExpFlagOverride override = [SCIDexKitStore overrideForKey:key];
        if (override == SCIExpFlagOverrideTrue) return YES;
        if (override == SCIExpFlagOverrideFalse) return NO;
    }
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

%ctor {
    NSLog(@"[RyukGram][DexKitRouter] ready; no runtime sweep is installed from ctor");
}
