#import "SCIDexKitBoolRouter.h"
#import "SCIDexKitStore.h"
#import "SCIDexKitImagePolicy.h"
#import "../../Core/SCIBoolOverrideResolver.h"
#import <Foundation/Foundation.h>
#import <objc/runtime.h>
#import <dlfcn.h>
#import <substrate.h>

static NSMutableDictionary<NSString *, NSValue *> *gOriginalIMPs;
static NSMutableDictionary<NSString *, NSString *> *gSelectorToKey;
static NSMutableSet<NSString *> *gInstalledKeys;
static NSMutableSet<NSString *> *gSessionObserveKeys;

static NSString *SelectorMapKey(Class cls, SEL sel, BOOL classMethod) {
    return [NSString stringWithFormat:@"%@|%@|%@", classMethod ? @"+" : @"-", NSStringFromClass(cls), NSStringFromSelector(sel)];
}

static Method ExactMethod(Class methodClass, SEL sel) {
    unsigned int count = 0;
    Method *methods = class_copyMethodList(methodClass, &count);
    Method found = NULL;
    for (unsigned int i = 0; i < count; i++) {
        if (method_getName(methods[i]) == sel) { found = methods[i]; break; }
    }
    if (methods) free(methods);
    return found;
}

static BOOL ReturnIsDefaultBool(Method m) {
    if (!m || method_getNumberOfArguments(m) != 2) return NO;
    char rt[32] = {0};
    method_getReturnType(m, rt, sizeof(rt));
    return rt[0] == 'B';
}

static NSString *LookupOverrideKeyForReceiver(id self, SEL _cmd) {
    BOOL classMethod = object_isClass(self);
    Class cls = classMethod ? (Class)self : object_getClass(self);
    @synchronized([SCIDexKitDescriptor class]) {
        Class walk = cls;
        while (walk) {
            NSString *mapKey = SelectorMapKey(walk, _cmd, classMethod);
            NSString *key = gSelectorToKey[mapKey];
            if (key.length) return key;
            walk = class_getSuperclass(walk);
        }
    }
    return nil;
}

static BOOL SCIDexKitBoolGetterRouter(id self, SEL _cmd) {
    NSString *overrideKey = LookupOverrideKeyForReceiver(self, _cmd);
    if (!overrideKey.length) return NO;

    NSNumber *forced = [SCIBoolOverrideResolver overrideValueForKey:overrideKey];
    if (forced) return forced.boolValue;

    NSValue *origValue = nil;
    @synchronized([SCIDexKitDescriptor class]) { origValue = gOriginalIMPs[overrideKey]; }
    if (!origValue) return NO;

    NSString *reentryKey = [@"scidexkit.reentry." stringByAppendingString:overrideKey];
    NSMutableDictionary *td = NSThread.currentThread.threadDictionary;
    if ([td[reentryKey] boolValue]) {
        NSNumber *obs = [SCIDexKitStore observedValueForKey:[SCIDexKitStore observedKeyForOverrideKey:overrideKey]];
        return obs ? obs.boolValue : NO;
    }

    BOOL original = NO;
    td[reentryKey] = @YES;
    @try {
        BOOL (*orig)(id, SEL) = (BOOL (*)(id, SEL))origValue.pointerValue;
        if (orig) original = orig(self, _cmd);
    } @finally {
        [td removeObjectForKey:reentryKey];
    }
    [SCIDexKitStore noteObservedValue:original forKey:[SCIDexKitStore observedKeyForOverrideKey:overrideKey]];
    return original;
}

BOOL SCIDexKitInstallHookForDescriptor(SCIDexKitDescriptor *descriptor, SCIDexKitInstallReason reason, NSError **error) {
    if (!descriptor.overrideKey.length || !descriptor.className.length || !descriptor.selectorName.length) return NO;
    @synchronized([SCIDexKitDescriptor class]) {
        if (!gOriginalIMPs) gOriginalIMPs = [NSMutableDictionary dictionary];
        if (!gSelectorToKey) gSelectorToKey = [NSMutableDictionary dictionary];
        if (!gInstalledKeys) gInstalledKeys = [NSMutableSet set];
        if (!gSessionObserveKeys) gSessionObserveKeys = [NSMutableSet set];
        if ([gInstalledKeys containsObject:descriptor.overrideKey]) {
            if (reason == SCIDexKitInstallReasonSessionObserve) [gSessionObserveKeys addObject:descriptor.overrideKey];
            return YES;
        }
    }

    Class cls = NSClassFromString(descriptor.className);
    if (!cls) {
        [SCIDexKitImagePolicy addPendingOverrideKey:descriptor.overrideKey forImage:descriptor.imageBasename];
        return NO;
    }
    SEL sel = NSSelectorFromString(descriptor.selectorName);
    Class methodClass = descriptor.classMethod ? object_getClass(cls) : cls;
    Method method = ExactMethod(methodClass, sel);
    if (!ReturnIsDefaultBool(method)) return NO;

    Dl_info info; memset(&info, 0, sizeof(info));
    if (dladdr((void *)method_getImplementation(method), &info) == 0) return NO;
    NSString *impImage = info.dli_fname ? @(info.dli_fname).lastPathComponent : @"";
    if (![impImage isEqualToString:descriptor.imageBasename] || ![SCIDexKitImagePolicy isAllowedImageBasename:impImage]) return NO;

    [SCIDexKitStore noteApplyingOverrideKey:descriptor.overrideKey];
    IMP original = NULL;
    MSHookMessageEx(methodClass, sel, (IMP)SCIDexKitBoolGetterRouter, &original);
    if (!original) return NO;

    @synchronized([SCIDexKitDescriptor class]) {
        gOriginalIMPs[descriptor.overrideKey] = [NSValue valueWithPointer:(const void *)original];
        gSelectorToKey[SelectorMapKey(cls, sel, descriptor.classMethod)] = descriptor.overrideKey;
        [gInstalledKeys addObject:descriptor.overrideKey];
        if (reason == SCIDexKitInstallReasonSessionObserve) [gSessionObserveKeys addObject:descriptor.overrideKey];
    }
    NSLog(@"[RyukGram][DexKitRouter] installed %@ reason=%ld", descriptor.overrideKey, (long)reason);
    return YES;
}

BOOL SCIDexKitIsHookInstalled(NSString *overrideKey) {
    @synchronized([SCIDexKitDescriptor class]) { return overrideKey.length && [gInstalledKeys containsObject:overrideKey]; }
}
NSUInteger SCIDexKitInstalledHookCount(void) {
    @synchronized([SCIDexKitDescriptor class]) { return gInstalledKeys.count; }
}

static SCIDexKitDescriptor *DescriptorFromOverrideKey(NSString *key) {
    NSString *image = nil, *sign = nil, *cls = nil, *sel = nil;
    if (![SCIDexKitStore parseBoolKey:key image:&image sign:&sign className:&cls selector:&sel]) return nil;
    SCIDexKitDescriptor *d = [SCIDexKitDescriptor new];
    d.imageBasename = image ?: @"";
    d.className = cls ?: @"";
    d.selectorName = sel ?: @"";
    d.classMethod = [sign isEqualToString:@"+"];
    d.overrideKey = key;
    d.observedKey = [SCIDexKitStore observedKeyForOverrideKey:key];
    return d;
}

void SCIDexKitReapplySavedOverrides(void) {
    NSUInteger attempted = 0, installed = 0, pending = 0;
    for (NSString *key in [SCIDexKitStore activeOverrideKeys]) {
        if ([SCIDexKitStore isOverrideQuarantined:key]) continue;
        SCIDexKitDescriptor *d = DescriptorFromOverrideKey(key);
        if (!d) continue;
        attempted++;
        if (SCIDexKitInstallHookForDescriptor(d, SCIDexKitInstallReasonStartupOverride, nil)) installed++;
        else { [SCIDexKitImagePolicy addPendingOverrideKey:key forImage:d.imageBasename]; pending++; }
    }
    NSLog(@"[RyukGram][DexKitRouter] startup overrides attempted=%lu installed=%lu pending=%lu", (unsigned long)attempted, (unsigned long)installed, (unsigned long)pending);
}

void SCIDexKitRetryPendingOverridesForImage(NSString *imageBasename) {
    NSArray *keys = [SCIDexKitImagePolicy drainPendingOverrideKeysForImage:imageBasename];
    for (NSString *key in keys) {
        SCIDexKitDescriptor *d = DescriptorFromOverrideKey(key);
        if (d) SCIDexKitInstallHookForDescriptor(d, SCIDexKitInstallReasonStartupOverride, nil);
    }
}

void SCIDexKitEnableSessionObservationForDescriptors(NSArray<SCIDexKitDescriptor *> *descriptors) {
    NSUInteger limit = MIN((NSUInteger)50, descriptors.count);
    for (NSUInteger i = 0; i < limit; i++) {
        SCIDexKitInstallHookForDescriptor(descriptors[i], SCIDexKitInstallReasonSessionObserve, nil);
    }
}
