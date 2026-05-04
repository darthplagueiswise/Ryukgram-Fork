#import "SCIExpFlags.h"
#import <Foundation/Foundation.h>
#import <objc/runtime.h>
#import <dlfcn.h>
#import <substrate.h>

static NSString *const kSCIDexKitObservedDefaultsKey = @"sci_enabled_experiment_observed_defaults";
static NSMutableDictionary<NSString *, NSValue *> *gSCIDexKitOriginalBoolIMPs;
static NSMutableSet<NSString *> *gSCIDexKitInstalledKeys;

static NSString *SCIDexKitBasename(const char *path) {
    if (!path) return @"";
    const char *slash = strrchr(path, '/');
    return [NSString stringWithUTF8String:(slash ? slash + 1 : path)] ?: @"";
}

static NSString *SCIDexKitKey(BOOL classMethod, NSString *className, NSString *methodName) {
    return [NSString stringWithFormat:@"objc-enabled:%@%@ %@",
            classMethod ? @"+" : @"-",
            className ?: @"",
            methodName ?: @""];
}

static BOOL SCIDexKitMethodReturnsBool(Method m) {
    if (!m) return NO;

    char rt[32] = {0};
    method_getReturnType(m, rt, sizeof(rt));
    return rt[0] == 'B' || rt[0] == 'c';
}

static void SCIDexKitSaveObserved(NSString *key, BOOL value) {
    if (!key.length) return;

    NSUserDefaults *ud = [NSUserDefaults standardUserDefaults];
    NSDictionary *existing = [ud dictionaryForKey:kSCIDexKitObservedDefaultsKey];
    NSMutableDictionary *dict = existing ? [existing mutableCopy] : [NSMutableDictionary dictionary];

    NSNumber *old = dict[key];
    if (old && old.boolValue == value) return;

    dict[key] = @(value);
    [ud setObject:dict forKey:kSCIDexKitObservedDefaultsKey];
}

static NSString *SCIDexKitKeyForReceiver(id receiver, SEL sel) {
    NSString *methodName = NSStringFromSelector(sel);
    BOOL classMethod = object_isClass(receiver);
    Class cls = classMethod ? (Class)receiver : object_getClass(receiver);

    while (cls) {
        NSString *className = NSStringFromClass(cls);
        NSString *key = SCIDexKitKey(classMethod, className, methodName);
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
        SCIDexKitSaveObserved(key, original);

        SCIExpFlagOverride state = [SCIExpFlags overrideForName:key];
        if (state == SCIExpFlagOverrideTrue) return YES;
        if (state == SCIExpFlagOverrideFalse) return NO;
    }

    return original;
}

extern "C" BOOL SCIDexKitInstallBoolGetterHook(NSString *key,
                                               NSString *className,
                                               NSString *methodName,
                                               BOOL classMethod) {
    if (!key.length || !className.length || !methodName.length) return NO;

    @synchronized([SCIExpFlags class]) {
        if (!gSCIDexKitOriginalBoolIMPs) {
            gSCIDexKitOriginalBoolIMPs = [NSMutableDictionary dictionary];
        }

        if (!gSCIDexKitInstalledKeys) {
            gSCIDexKitInstalledKeys = [NSMutableSet set];
        }

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
        NSString *mainImageName = NSBundle.mainBundle.executablePath.lastPathComponent ?: @"";

        if (![imageName isEqualToString:mainImageName]) {
            NSLog(@"[RyukGram][DexKitRouter] refused non-main-exec getter %@ image=%@", key, imageName);
            return NO;
        }

        NSString *expected = SCIDexKitKey(classMethod, className, methodName);
        if (![expected isEqualToString:key]) return NO;

        Class hookClass = classMethod ? object_getClass(cls) : cls;
        IMP original = NULL;

        MSHookMessageEx(hookClass, sel, (IMP)SCIDexKitBoolGetterReplacement, &original);

        if (!original) return NO;

        gSCIDexKitOriginalBoolIMPs[key] = [NSValue valueWithPointer:(const void *)original];
        [gSCIDexKitInstalledKeys addObject:key];

        NSLog(@"[RyukGram][DexKitRouter] installed %@", key);
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
