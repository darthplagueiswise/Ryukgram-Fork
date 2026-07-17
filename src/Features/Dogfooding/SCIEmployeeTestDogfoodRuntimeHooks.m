#import "SCIInternalGatePrefs.h"
#import "../Gating/SCICSymbolStub.h"
#import <Foundation/Foundation.h>
#import <mach-o/dyld.h>
#import <objc/runtime.h>
#import <substrate.h>
#import <os/log.h>
#import <stdlib.h>
#import <string.h>

#define ETDLOG(fmt, ...) os_log(OS_LOG_DEFAULT, "[SCIGate] EmployeeTestDogfood " fmt, ##__VA_ARGS__)

// Runtime-only extension for identity aliases that genuinely exist in the
// loaded Instagram build. No method is added and no DATA symbol is treated as a
// function. Every replacement reads the consolidated Employee / Internal master
// live, so the hook can be installed before the preference is enabled.

static BOOL ETDMasterOn(void) {
    return [SCIInternalGatePrefs employeeInternalMasterEnabled];
}

static NSMutableDictionary<NSString *, NSValue *> *ETDGetterOriginals(void) {
    static NSMutableDictionary<NSString *, NSValue *> *store;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{ store = [NSMutableDictionary dictionary]; });
    return store;
}

static NSMutableDictionary<NSString *, NSValue *> *ETDSetterOriginals(void) {
    static NSMutableDictionary<NSString *, NSValue *> *store;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{ store = [NSMutableDictionary dictionary]; });
    return store;
}

static NSString *ETDKey(Class cls, SEL selector) {
    return [NSString stringWithFormat:@"%@#%@",
        NSStringFromClass(cls) ?: @"<nil>",
        NSStringFromSelector(selector) ?: @"<nil>"];
}

static BOOL ETDGetterABI(Method method) {
    const char *encoding = method ? method_getTypeEncoding(method) : NULL;
    return encoding &&
        (strcmp(encoding, "B16@0:8") == 0 ||
         strcmp(encoding, "c16@0:8") == 0 ||
         strcmp(encoding, "C16@0:8") == 0);
}

static BOOL ETDSetterABI(Method method) {
    const char *encoding = method ? method_getTypeEncoding(method) : NULL;
    return encoding &&
        (strcmp(encoding, "v20@0:8B16") == 0 ||
         strcmp(encoding, "v20@0:8c16") == 0 ||
         strcmp(encoding, "v20@0:8C16") == 0);
}

static Class ETDDeclaringClass(Class cls, SEL selector) {
    for (Class current = cls; current; current = class_getSuperclass(current)) {
        unsigned int count = 0;
        Method *methods = class_copyMethodList(current, &count);
        BOOL declares = NO;
        for (unsigned int i = 0; methods && i < count; i++) {
            if (method_getName(methods[i]) == selector) {
                declares = YES;
                break;
            }
        }
        if (methods) free(methods);
        if (declares) return current;
    }
    return Nil;
}

static IMP ETDOriginalForReceiver(id receiver, SEL selector,
                                  NSMutableDictionary<NSString *, NSValue *> *store) {
    for (Class cls = object_getClass(receiver); cls; cls = class_getSuperclass(cls)) {
        NSValue *value = store[ETDKey(cls, selector)];
        if (value) return value.pointerValue;
    }
    return NULL;
}

static BOOL ETDForcedGetter(id self, SEL _cmd) {
    if (ETDMasterOn()) return YES;
    IMP original = NULL;
    NSMutableDictionary<NSString *, NSValue *> *store = ETDGetterOriginals();
    @synchronized (store) {
        original = ETDOriginalForReceiver(self, _cmd, store);
    }
    return original ? ((BOOL (*)(id, SEL))original)(self, _cmd) : NO;
}

static void ETDForcedSetter(id self, SEL _cmd, BOOL value) {
    IMP original = NULL;
    NSMutableDictionary<NSString *, NSValue *> *store = ETDSetterOriginals();
    @synchronized (store) {
        original = ETDOriginalForReceiver(self, _cmd, store);
    }
    if (original) {
        ((void (*)(id, SEL, BOOL))original)(self, _cmd,
            ETDMasterOn() ? YES : value);
    }
}

static BOOL ETDRelevantClass(Class cls) {
    NSString *name = NSStringFromClass(cls).lowercaseString ?: @"";
    return [name containsString:@"user"] ||
           [name containsString:@"session"] ||
           [name containsString:@"account"] ||
           [name containsString:@"employee"] ||
           [name containsString:@"testuser"] ||
           [name containsString:@"dogfood"] ||
           [name containsString:@"internal"] ||
           [name containsString:@"identity"] ||
           [name containsString:@"bugreport"];
}

static BOOL ETDInstallGetter(Class cls, NSString *name) {
    SEL selector = NSSelectorFromString(name);
    Class owner = ETDDeclaringClass(cls, selector);
    if (!owner) return NO;
    Method method = class_getInstanceMethod(owner, selector);
    if (!ETDGetterABI(method)) return NO;

    NSString *key = ETDKey(owner, selector);
    NSMutableDictionary<NSString *, NSValue *> *store = ETDGetterOriginals();
    @synchronized (store) {
        if (store[key]) return YES;
    }

    IMP original = NULL;
    MSHookMessageEx(owner, selector, (IMP)ETDForcedGetter, &original);
    if (!original) return NO;
    @synchronized (store) { store[key] = [NSValue valueWithPointer:original]; }
    ETDLOG("getter %{public}s.%{public}s ABI=%{public}s",
        class_getName(owner), sel_getName(selector), method_getTypeEncoding(method));
    return YES;
}

static BOOL ETDInstallSetter(Class cls, NSString *name) {
    SEL selector = NSSelectorFromString(name);
    Class owner = ETDDeclaringClass(cls, selector);
    if (!owner) return NO;
    Method method = class_getInstanceMethod(owner, selector);
    if (!ETDSetterABI(method)) return NO;

    NSString *key = ETDKey(owner, selector);
    NSMutableDictionary<NSString *, NSValue *> *store = ETDSetterOriginals();
    @synchronized (store) {
        if (store[key]) return YES;
    }

    IMP original = NULL;
    MSHookMessageEx(owner, selector, (IMP)ETDForcedSetter, &original);
    if (!original) return NO;
    @synchronized (store) { store[key] = [NSValue valueWithPointer:original]; }
    ETDLOG("setter %{public}s.%{public}s ABI=%{public}s",
        class_getName(owner), sel_getName(selector), method_getTypeEncoding(method));
    return YES;
}

static void ETDScanLoadedClasses(void) {
    static NSArray<NSString *> *getters;
    static NSArray<NSString *> *setters;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        getters = @[
            @"isTestUser", @"isTestAccount",
            @"isEmployeeOrTestUser", @"isEmployeeOrTestAccount",
            @"isDogfooder", @"isDogfood", @"isDogfooding",
            @"isInternalUser", @"isInternal",
            @"isMetaEmployee", @"isFacebookEmployee"
        ];
        setters = @[
            @"setIsTestUser:", @"setIsTestAccount:",
            @"setIsEmployeeOrTestUser:", @"setIsEmployeeOrTestAccount:",
            @"setIsDogfooder:", @"setIsDogfood:", @"setIsDogfooding:",
            @"setIsInternalUser:", @"setIsInternal:",
            @"setIsMetaEmployee:", @"setIsFacebookEmployee:"
        ];
    });

    int count = objc_getClassList(NULL, 0);
    if (count <= 0) return;
    __unsafe_unretained Class *classes =
        (__unsafe_unretained Class *)calloc((size_t)count, sizeof(Class));
    count = objc_getClassList(classes, count);
    NSUInteger installed = 0;
    for (int i = 0; i < count; i++) {
        Class cls = classes[i];
        if (!ETDRelevantClass(cls)) continue;
        for (NSString *name in getters) installed += ETDInstallGetter(cls, name);
        for (NSString *name in setters) installed += ETDInstallSetter(cls, name);
    }
    free(classes);
    ETDLOG("runtime aliases installed/active=%lu classes=%d",
        (unsigned long)installed, count);
}

static BOOL sETDScanScheduled = NO;
static void ETDScheduleScan(void) {
    @synchronized (ETDGetterOriginals()) {
        if (sETDScanScheduled) return;
        sETDScanScheduled = YES;
    }
    dispatch_async(dispatch_get_main_queue(), ^{
        @synchronized (ETDGetterOriginals()) { sETDScanScheduled = NO; }
        ETDScanLoadedClasses();
    });
}

#pragma mark - Pointer-filtered MobileConfig descriptor gates

static NSString *const kETDOwnerKey =
    @"sci_employee_test_dogfood_descriptor_owner";
static NSString *const kETDPreviousKey =
    @"sci_employee_test_dogfood_descriptor_previous";
static BOOL sETDSyncing = NO;

static NSArray<NSString *> *ETDDescriptors(void) {
    return @[@"ig_is_employee", @"ig_is_employee_or_test_user"];
}

static BOOL ETDNumbersEqual(NSNumber *a, NSNumber *b) {
    if (!a && !b) return YES;
    return a && b && [a isEqualToNumber:b];
}

static void ETDSyncDescriptorForces(void) {
    @synchronized (SCICSymbolStub.class) {
        if (sETDSyncing) return;
        sETDSyncing = YES;

        NSUserDefaults *defaults = NSUserDefaults.standardUserDefaults;
        BOOL owner = [defaults boolForKey:kETDOwnerKey];
        if (ETDMasterOn()) {
            if (!owner) {
                NSMutableDictionary *previous = [NSMutableDictionary dictionary];
                for (NSString *symbol in ETDDescriptors()) {
                    NSNumber *value = [SCICSymbolStub forceForParamDescriptorSymbol:symbol];
                    previous[symbol] = value ?: [NSNull null];
                }
                [defaults setObject:previous forKey:kETDPreviousKey];
                [defaults setBool:YES forKey:kETDOwnerKey];
            }
            for (NSString *symbol in ETDDescriptors()) {
                NSNumber *current = [SCICSymbolStub forceForParamDescriptorSymbol:symbol];
                if (![current isEqualToNumber:@YES]) {
                    [SCICSymbolStub setParamDescriptorForce:@YES forSymbol:symbol];
                }
            }
        } else if (owner) {
            NSDictionary *previous = [defaults dictionaryForKey:kETDPreviousKey];
            for (NSString *symbol in ETDDescriptors()) {
                id saved = previous[symbol];
                NSNumber *restore = [saved isKindOfClass:NSNumber.class] ? saved : nil;
                NSNumber *current = [SCICSymbolStub forceForParamDescriptorSymbol:symbol];
                if (!ETDNumbersEqual(current, restore)) {
                    [SCICSymbolStub setParamDescriptorForce:restore forSymbol:symbol];
                }
            }
            [defaults removeObjectForKey:kETDPreviousKey];
            [defaults removeObjectForKey:kETDOwnerKey];
        }

        sETDSyncing = NO;
    }
}

static void ETDImageLoaded(const struct mach_header *header, intptr_t slide) {
    (void)header; (void)slide;
    ETDScheduleScan();
}

__attribute__((constructor))
static void SCIEmployeeTestDogfoodRuntimeHooksCtor(void) {
    @autoreleasepool {
        ETDScanLoadedClasses();
        ETDSyncDescriptorForces();
        _dyld_register_func_for_add_image(ETDImageLoaded);
        [NSNotificationCenter.defaultCenter
            addObserverForName:NSUserDefaultsDidChangeNotification
                        object:nil
                         queue:NSOperationQueue.mainQueue
                    usingBlock:^(__unused NSNotification *notification) {
                        ETDSyncDescriptorForces();
                    }];
    }
}
