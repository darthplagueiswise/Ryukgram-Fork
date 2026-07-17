#import "SCIInternalGatePrefs.h"
#import "SCIDogfoodObjectRuntime.h"
#import <Foundation/Foundation.h>
#import <mach-o/dyld.h>
#import <objc/runtime.h>
#import <substrate.h>
#import <os/log.h>
#import <string.h>

#define PANDOLOG(fmt, ...) os_log(OS_LOG_DEFAULT, "[SCIGate] PandoIdentity " fmt, ##__VA_ARGS__)

// Static metadata revalidated in the uploaded Instagram/FBSharedFramework pair:
//
// IGBaseUser categories actually implement:
//   asIGUserIsEmployeeOrTestUserFragmentImmutableModel  @16@0:8
//   asIGDogfooderInformationFragmentImmutableModel      @16@0:8
//   asIGFirstTimeDogfooderFragmentImmutableModel        @16@0:8
//
// FBSharedFramework actually implements accountBadges (@16@0:8) on IGBaseUser
// and IGAPIUserDict. GraphQL represents the relevant enum values as
// IS_EMPLOYEE and IS_TEST_USER. No selector is fabricated: returned fragment
// classes are inspected and only already-existing ABI-compatible methods are
// hooked.

static NSMutableDictionary<NSString *, NSValue *> *sEIPAccountBadgeOriginals;
static NSMutableDictionary<NSString *, NSValue *> *sEIPFragmentOriginals;
static NSMutableDictionary<NSString *, NSValue *> *sEIPBoolOriginals;

static BOOL EIPMasterOn(void) {
    return [SCIInternalGatePrefs employeeInternalMasterEnabled];
}

static NSString *EIPMethodKey(Class cls, SEL selector) {
    return [NSString stringWithFormat:@"%p#%s", cls,
            selector ? sel_getName(selector) : "<nil>"];
}

static BOOL EIPBoolEncoding(Method method) {
    const char *encoding = method ? method_getTypeEncoding(method) : NULL;
    return encoding &&
        (strcmp(encoding, "B16@0:8") == 0 ||
         strcmp(encoding, "c16@0:8") == 0);
}

static BOOL EIPObjectEncoding(Method method) {
    const char *encoding = method ? method_getTypeEncoding(method) : NULL;
    return encoding && strcmp(encoding, "@16@0:8") == 0;
}

static Class EIPDeclaringClass(Class cls, SEL selector) {
    for (Class current = cls; current; current = class_getSuperclass(current)) {
        unsigned int count = 0;
        Method *methods = class_copyMethodList(current, &count);
        BOOL found = NO;
        for (unsigned int i = 0; methods && i < count; i++) {
            if (method_getName(methods[i]) == selector) {
                found = YES;
                break;
            }
        }
        if (methods) free(methods);
        if (found) return current;
    }
    return Nil;
}

static IMP EIPOriginalForObject(id object, SEL selector,
                                NSMutableDictionary<NSString *, NSValue *> *store) {
    if (!object || !selector || !store) return NULL;
    @synchronized (store) {
        for (Class cls = object_getClass(object); cls; cls = class_getSuperclass(cls)) {
            NSValue *value = store[EIPMethodKey(cls, selector)];
            if (value) return value.pointerValue;
        }
    }
    return NULL;
}

static id EIPBadgesWithInternalIdentity(id original) {
    if (!EIPMasterOn()) return original;
    NSString *employee = @"IS_EMPLOYEE";
    NSString *testUser = @"IS_TEST_USER";

    if (!original) return @[employee, testUser];

    if ([original isKindOfClass:NSArray.class]) {
        NSMutableArray *values = [original mutableCopy];
        if (![values containsObject:employee]) [values addObject:employee];
        if (![values containsObject:testUser]) [values addObject:testUser];
        return values.copy;
    }
    if ([original isKindOfClass:NSSet.class]) {
        NSMutableSet *values = [original mutableCopy];
        [values addObject:employee];
        [values addObject:testUser];
        return values.copy;
    }
    if ([original isKindOfClass:NSOrderedSet.class]) {
        NSMutableOrderedSet *values = [original mutableCopy];
        [values addObject:employee];
        [values addObject:testUser];
        return values.copy;
    }

    // Unknown Pando collection representation: preserve the native object rather
    // than substitute an ABI-incompatible container.
    return original;
}

static id newEIPAccountBadges(id self, SEL _cmd) {
    IMP original = EIPOriginalForObject(self, _cmd, sEIPAccountBadgeOriginals);
    id value = original ? ((id (*)(id, SEL))original)(self, _cmd) : nil;
    return EIPBadgesWithInternalIdentity(value);
}

static BOOL newEIPIdentityBool(id self, SEL _cmd) {
    if (EIPMasterOn()) return YES;
    IMP original = EIPOriginalForObject(self, _cmd, sEIPBoolOriginals);
    return original ? ((BOOL (*)(id, SEL))original)(self, _cmd) : NO;
}

static void EIPHookMethodOwner(Class candidate, SEL selector,
                               BOOL (*validator)(Method), IMP replacement,
                               NSMutableDictionary<NSString *, NSValue *> *store) {
    if (!candidate || !selector || !validator || !replacement || !store) return;
    Class owner = EIPDeclaringClass(candidate, selector);
    if (!owner) return;
    Method method = class_getInstanceMethod(owner, selector);
    if (!validator(method)) return;

    NSString *key = EIPMethodKey(owner, selector);
    @synchronized (store) {
        if (store[key]) return;
    }

    IMP original = NULL;
    MSHookMessageEx(owner, selector, replacement, &original);
    if (!original) return;
    @synchronized (store) {
        store[key] = [NSValue valueWithPointer:original];
    }
    PANDOLOG("hooked %{public}@.%{public}s ABI=%{public}s",
             NSStringFromClass(owner), sel_getName(selector),
             method_getTypeEncoding(method));
}

static void EIPInstallExistingIdentityMethodsOnClass(Class cls) {
    if (!cls) return;
    EIPHookMethodOwner(cls, NSSelectorFromString(@"accountBadges"),
        EIPObjectEncoding, (IMP)newEIPAccountBadges,
        sEIPAccountBadgeOriginals);

    for (NSString *name in @[
        @"isEmployee",
        @"isTestUser",
        @"isEmployeeOrTestUser",
        @"isDogfooder",
        @"isDogfood",
        @"isInternal",
        @"shouldSendEmployeeTag"
    ]) {
        EIPHookMethodOwner(cls, NSSelectorFromString(name),
            EIPBoolEncoding, (IMP)newEIPIdentityBool, sEIPBoolOriginals);
    }
}

static id newEIPFragmentConversion(id self, SEL _cmd) {
    IMP original = EIPOriginalForObject(self, _cmd, sEIPFragmentOriginals);
    id fragment = original ? ((id (*)(id, SEL))original)(self, _cmd) : nil;
    if (fragment) {
        EIPInstallExistingIdentityMethodsOnClass(object_getClass(fragment));
        [SCIDogfoodObjectRuntime noteObject:fragment
                                       role:NSStringFromSelector(_cmd)
                                     source:@"IGBaseUser Pando fragment conversion"];
    }
    return fragment;
}

static void EIPHookFragmentSelector(Class cls, NSString *name) {
    if (!cls || !name.length) return;
    EIPHookMethodOwner(cls, NSSelectorFromString(name),
        EIPObjectEncoding, (IMP)newEIPFragmentConversion,
        sEIPFragmentOriginals);
}

static void EIPInstall(void) {
    @synchronized (SCIDogfoodObjectRuntime.class) {
        if (!sEIPAccountBadgeOriginals) {
            sEIPAccountBadgeOriginals = [NSMutableDictionary dictionary];
            sEIPFragmentOriginals = [NSMutableDictionary dictionary];
            sEIPBoolOriginals = [NSMutableDictionary dictionary];
        }

        Class baseUser = NSClassFromString(@"IGBaseUser");
        Class apiUser = NSClassFromString(@"IGAPIUserDict");
        EIPInstallExistingIdentityMethodsOnClass(baseUser);
        EIPInstallExistingIdentityMethodsOnClass(apiUser);

        EIPHookFragmentSelector(baseUser,
            @"asIGUserIsEmployeeOrTestUserFragmentImmutableModel");
        EIPHookFragmentSelector(baseUser,
            @"asIGUserIsEmployeeOrTestUserFragment");
        EIPHookFragmentSelector(baseUser,
            @"asIGDogfooderInformationFragmentImmutableModel");
        EIPHookFragmentSelector(baseUser,
            @"asIGFirstTimeDogfooderFragmentImmutableModel");
    }
}

static void EIPImageLoaded(const struct mach_header *header, intptr_t slide) {
    (void)header;
    (void)slide;
    EIPInstall();
}

__attribute__((constructor))
static void SCIEmployeePandoIdentityHooksCtor(void) {
    @autoreleasepool {
        EIPInstall();
        _dyld_register_func_for_add_image(EIPImageLoaded);
    }
}
