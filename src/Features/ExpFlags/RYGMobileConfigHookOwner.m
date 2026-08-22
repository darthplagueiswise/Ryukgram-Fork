#import "RYGMobileConfig.h"
#import "../../Utils.h"
#import <UIKit/UIKit.h>
#import <objc/runtime.h>
#import <mach-o/dyld.h>
#import <dlfcn.h>
#include <stdatomic.h>
#include <string.h>

// Compatibility bootstrap for persisted MobileConfig state. RYGMobileConfig.xm
// remains the primary getter owner when its explicit feature switch is enabled.
// When that switch is off but mc_overrides.plist contains values, this file owns
// the same exact getter selectors directly. It never asks the Runtime Browser to
// enumerate images/configs/classes and it never performs disk I/O from dyld's
// callback.

static atomic_bool gRYGMCWanted = false;
static atomic_bool gRYGMCScheduled = false;
static atomic_uint_fast64_t gRYGMCGeneration = 1;

static IMP gRYGMCUpBool;
static IMP gRYGMCUpBoolDef;
static IMP gRYGMCUpBoolOpts;
static IMP gRYGMCUpBoolOptsDef;
static IMP gRYGMCUpInt;
static IMP gRYGMCUpIntDef;
static IMP gRYGMCUpIntOpts;
static IMP gRYGMCUpIntOptsDef;
static IMP gRYGMCUpDouble;
static IMP gRYGMCUpDoubleDef;
static IMP gRYGMCUpDoubleOpts;
static IMP gRYGMCUpDoubleOptsDef;
static IMP gRYGMCUpString;
static IMP gRYGMCUpStringDef;
static IMP gRYGMCUpStringOpts;
static IMP gRYGMCUpStringOptsDef;

static dispatch_queue_t RYGMCOwnerQueue(void) {
    static dispatch_queue_t queue;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{ queue = dispatch_queue_create("com.ryukgram.mobileconfig-owner", DISPATCH_QUEUE_SERIAL); });
    return queue;
}

static unsigned long long RYGMCForceCanonicalPID(unsigned long long pid) {
    if (!pid) return 0;
    unsigned long long type = (pid >> 48) & 0x0fULL;
    return (pid & 0x0000FFFFFFFFFFFFULL) | ((0x40ULL | type) << 48);
}

static NSDictionary<NSNumber *, id> *RYGMCOwnedOverrideDictionary(void) {
    RYGMobileConfig *mobileConfig = RYGMobileConfig.shared;
    Ivar ivar = class_getInstanceVariable(RYGMobileConfig.class, "_overrides");
    id value = ivar ? object_getIvar(mobileConfig, ivar) : nil;
    return [value isKindOfClass:NSDictionary.class] ? value : @{};
}

static id RYGMCOwnedOverride(unsigned long long pid) {
    if (!pid) return nil;
    NSDictionary *overrides = RYGMCOwnedOverrideDictionary();
    id value = overrides[@(RYGMCForceCanonicalPID(pid))];
    return value ?: overrides[@(pid)];
}

static const char *RYGMCUnqualified(const char *type) {
    while (type && *type && strchr("rnNoORV", *type)) type++;
    return type;
}

static BOOL RYGMCOwnerTypeMatches(const char *raw, char expected) {
    const char *type = RYGMCUnqualified(raw);
    if (!type || !*type) return NO;
    switch (expected) {
        case 'P': return *type == 'Q' || *type == 'q' || (*type == '{' && (strstr(type, "=Q}") || strstr(type, "=q}")));
        case 'B': return *type == 'B' || *type == 'c' || *type == 'C';
        case 'Q': return *type == 'q' || *type == 'Q';
        case 'D': return *type == 'd';
        case '@': return *type == '@';
        default: return NO;
    }
}

static BOOL RYGMCOwnerMethodMatches(Method method, char returnType, const char *arguments) {
    if (!method || !arguments || method_getNumberOfArguments(method) != strlen(arguments) + 2) return NO;
    char encoded[128] = {0};
    method_getReturnType(method, encoded, sizeof(encoded));
    if (!RYGMCOwnerTypeMatches(encoded, returnType)) return NO;
    for (unsigned int index = 0; arguments[index]; index++) {
        memset(encoded, 0, sizeof(encoded));
        method_getArgumentType(method, index + 2, encoded, sizeof(encoded));
        if (!RYGMCOwnerTypeMatches(encoded, arguments[index])) return NO;
    }
    return YES;
}

static Method RYGMCOwnerDirectMethod(Class cls, SEL selector) {
    if (!cls || !selector) return NULL;
    unsigned int count = 0;
    Method *methods = class_copyMethodList(cls, &count);
    Method found = NULL;
    for (unsigned int index = 0; methods && index < count; index++) {
        if (method_getName(methods[index]) == selector) { found = methods[index]; break; }
    }
    if (methods) free(methods);
    return found;
}

static BOOL RYGMCIMPIsAlreadyRyukGram(IMP implementation) {
    if (!implementation) return NO;
    Dl_info info = {0};
    if (!dladdr((const void *)implementation, &info) || !info.dli_fname) return NO;
    NSString *name = [[NSString stringWithUTF8String:info.dli_fname] lastPathComponent].lowercaseString;
    return [name containsString:@"ryukgram"];
}

static BOOL RYGMCOwnerInstallOne(Class cls,
                                  NSString *selectorName,
                                  IMP replacement,
                                  IMP *upstream,
                                  char returnType,
                                  const char *arguments) {
    if (!cls || !selectorName.length || !replacement || !upstream) return NO;
    SEL selector = NSSelectorFromString(selectorName);
    Method method = RYGMCOwnerDirectMethod(cls, selector);
    if (!RYGMCOwnerMethodMatches(method, returnType, arguments)) return NO;
    IMP current = method_getImplementation(method);
    if (!current) return NO;
    if (current == replacement) return YES;

    // RYGMobileConfig.xm may already own this exact getter when its explicit
    // switch is enabled. Do not stack a second RyukGram getter wrapper over it.
    if (RYGMCIMPIsAlreadyRyukGram(current)) return YES;

    if (*upstream) return NO;
    *upstream = current;
    (void)method_setImplementation(method, replacement);
    if (method_getImplementation(method) == replacement) return YES;
    *upstream = NULL;
    return NO;
}

static BOOL RYGMCOwnerBool(id self, SEL cmd, unsigned long long pid) {
    id value = RYGMCOwnedOverride(pid);
    return value ? [value boolValue] : (gRYGMCUpBool ? ((BOOL (*)(id,SEL,unsigned long long))gRYGMCUpBool)(self,cmd,pid) : NO);
}
static BOOL RYGMCOwnerBoolDef(id self, SEL cmd, unsigned long long pid, BOOL def) {
    id value = RYGMCOwnedOverride(pid);
    return value ? [value boolValue] : (gRYGMCUpBoolDef ? ((BOOL (*)(id,SEL,unsigned long long,BOOL))gRYGMCUpBoolDef)(self,cmd,pid,def) : def);
}
static BOOL RYGMCOwnerBoolOpts(id self, SEL cmd, unsigned long long pid, id opts) {
    id value = RYGMCOwnedOverride(pid);
    return value ? [value boolValue] : (gRYGMCUpBoolOpts ? ((BOOL (*)(id,SEL,unsigned long long,id))gRYGMCUpBoolOpts)(self,cmd,pid,opts) : NO);
}
static BOOL RYGMCOwnerBoolOptsDef(id self, SEL cmd, unsigned long long pid, id opts, BOOL def) {
    id value = RYGMCOwnedOverride(pid);
    return value ? [value boolValue] : (gRYGMCUpBoolOptsDef ? ((BOOL (*)(id,SEL,unsigned long long,id,BOOL))gRYGMCUpBoolOptsDef)(self,cmd,pid,opts,def) : def);
}
static long long RYGMCOwnerInt(id self, SEL cmd, unsigned long long pid) {
    id value = RYGMCOwnedOverride(pid);
    return value ? [value longLongValue] : (gRYGMCUpInt ? ((long long (*)(id,SEL,unsigned long long))gRYGMCUpInt)(self,cmd,pid) : 0);
}
static long long RYGMCOwnerIntDef(id self, SEL cmd, unsigned long long pid, long long def) {
    id value = RYGMCOwnedOverride(pid);
    return value ? [value longLongValue] : (gRYGMCUpIntDef ? ((long long (*)(id,SEL,unsigned long long,long long))gRYGMCUpIntDef)(self,cmd,pid,def) : def);
}
static long long RYGMCOwnerIntOpts(id self, SEL cmd, unsigned long long pid, id opts) {
    id value = RYGMCOwnedOverride(pid);
    return value ? [value longLongValue] : (gRYGMCUpIntOpts ? ((long long (*)(id,SEL,unsigned long long,id))gRYGMCUpIntOpts)(self,cmd,pid,opts) : 0);
}
static long long RYGMCOwnerIntOptsDef(id self, SEL cmd, unsigned long long pid, id opts, long long def) {
    id value = RYGMCOwnedOverride(pid);
    return value ? [value longLongValue] : (gRYGMCUpIntOptsDef ? ((long long (*)(id,SEL,unsigned long long,id,long long))gRYGMCUpIntOptsDef)(self,cmd,pid,opts,def) : def);
}
static double RYGMCOwnerDouble(id self, SEL cmd, unsigned long long pid) {
    id value = RYGMCOwnedOverride(pid);
    return value ? [value doubleValue] : (gRYGMCUpDouble ? ((double (*)(id,SEL,unsigned long long))gRYGMCUpDouble)(self,cmd,pid) : 0.0);
}
static double RYGMCOwnerDoubleDef(id self, SEL cmd, unsigned long long pid, double def) {
    id value = RYGMCOwnedOverride(pid);
    return value ? [value doubleValue] : (gRYGMCUpDoubleDef ? ((double (*)(id,SEL,unsigned long long,double))gRYGMCUpDoubleDef)(self,cmd,pid,def) : def);
}
static double RYGMCOwnerDoubleOpts(id self, SEL cmd, unsigned long long pid, id opts) {
    id value = RYGMCOwnedOverride(pid);
    return value ? [value doubleValue] : (gRYGMCUpDoubleOpts ? ((double (*)(id,SEL,unsigned long long,id))gRYGMCUpDoubleOpts)(self,cmd,pid,opts) : 0.0);
}
static double RYGMCOwnerDoubleOptsDef(id self, SEL cmd, unsigned long long pid, id opts, double def) {
    id value = RYGMCOwnedOverride(pid);
    return value ? [value doubleValue] : (gRYGMCUpDoubleOptsDef ? ((double (*)(id,SEL,unsigned long long,id,double))gRYGMCUpDoubleOptsDef)(self,cmd,pid,opts,def) : def);
}
static id RYGMCOwnerString(id self, SEL cmd, unsigned long long pid) {
    id value = RYGMCOwnedOverride(pid);
    return [value isKindOfClass:NSString.class] ? value : (gRYGMCUpString ? ((id (*)(id,SEL,unsigned long long))gRYGMCUpString)(self,cmd,pid) : nil);
}
static id RYGMCOwnerStringDef(id self, SEL cmd, unsigned long long pid, id def) {
    id value = RYGMCOwnedOverride(pid);
    return [value isKindOfClass:NSString.class] ? value : (gRYGMCUpStringDef ? ((id (*)(id,SEL,unsigned long long,id))gRYGMCUpStringDef)(self,cmd,pid,def) : def);
}
static id RYGMCOwnerStringOpts(id self, SEL cmd, unsigned long long pid, id opts) {
    id value = RYGMCOwnedOverride(pid);
    return [value isKindOfClass:NSString.class] ? value : (gRYGMCUpStringOpts ? ((id (*)(id,SEL,unsigned long long,id))gRYGMCUpStringOpts)(self,cmd,pid,opts) : nil);
}
static id RYGMCOwnerStringOptsDef(id self, SEL cmd, unsigned long long pid, id opts, id def) {
    id value = RYGMCOwnedOverride(pid);
    return [value isKindOfClass:NSString.class] ? value : (gRYGMCUpStringOptsDef ? ((id (*)(id,SEL,unsigned long long,id,id))gRYGMCUpStringOptsDef)(self,cmd,pid,opts,def) : def);
}

static NSUInteger RYGMCOwnerScore(Class cls) {
    if (!cls) return 0;
    NSUInteger score = 0;
    for (NSString *name in @[@"getBool:", @"getInt64:", @"getDouble:", @"getString:"])
        if (RYGMCOwnerDirectMethod(cls, NSSelectorFromString(name))) score++;
    return score;
}

static void RYGMCOwnerInstallHooks(void) {
    if (!atomic_load_explicit(&gRYGMCWanted, memory_order_acquire)) return;
    Class fb = objc_lookUpClass("FBMobileConfigContextManager");
    Class ig = objc_lookUpClass("IGMobileConfigContextManager");
    Class cls = RYGMCOwnerScore(fb) >= RYGMCOwnerScore(ig) ? fb : ig;
    if (!cls) return;

    RYGMCOwnerInstallOne(cls,@"getBool:",(IMP)RYGMCOwnerBool,&gRYGMCUpBool,'B',"P");
    RYGMCOwnerInstallOne(cls,@"getBool:withDefault:",(IMP)RYGMCOwnerBoolDef,&gRYGMCUpBoolDef,'B',"PB");
    RYGMCOwnerInstallOne(cls,@"getBool:withOptions:",(IMP)RYGMCOwnerBoolOpts,&gRYGMCUpBoolOpts,'B',"P@");
    RYGMCOwnerInstallOne(cls,@"getBool:withOptions:withDefault:",(IMP)RYGMCOwnerBoolOptsDef,&gRYGMCUpBoolOptsDef,'B',"P@B");
    RYGMCOwnerInstallOne(cls,@"getInt64:",(IMP)RYGMCOwnerInt,&gRYGMCUpInt,'Q',"P");
    RYGMCOwnerInstallOne(cls,@"getInt64:withDefault:",(IMP)RYGMCOwnerIntDef,&gRYGMCUpIntDef,'Q',"PQ");
    RYGMCOwnerInstallOne(cls,@"getInt64:withOptions:",(IMP)RYGMCOwnerIntOpts,&gRYGMCUpIntOpts,'Q',"P@");
    RYGMCOwnerInstallOne(cls,@"getInt64:withOptions:withDefault:",(IMP)RYGMCOwnerIntOptsDef,&gRYGMCUpIntOptsDef,'Q',"P@Q");
    RYGMCOwnerInstallOne(cls,@"getDouble:",(IMP)RYGMCOwnerDouble,&gRYGMCUpDouble,'D',"P");
    RYGMCOwnerInstallOne(cls,@"getDouble:withDefault:",(IMP)RYGMCOwnerDoubleDef,&gRYGMCUpDoubleDef,'D',"PD");
    RYGMCOwnerInstallOne(cls,@"getDouble:withOptions:",(IMP)RYGMCOwnerDoubleOpts,&gRYGMCUpDoubleOpts,'D',"P@");
    RYGMCOwnerInstallOne(cls,@"getDouble:withOptions:withDefault:",(IMP)RYGMCOwnerDoubleOptsDef,&gRYGMCUpDoubleOptsDef,'D',"P@D");
    RYGMCOwnerInstallOne(cls,@"getString:",(IMP)RYGMCOwnerString,&gRYGMCUpString,'@',"P");
    RYGMCOwnerInstallOne(cls,@"getString:withDefault:",(IMP)RYGMCOwnerStringDef,&gRYGMCUpStringDef,'@',"P@");
    RYGMCOwnerInstallOne(cls,@"getString:withOptions:",(IMP)RYGMCOwnerStringOpts,&gRYGMCUpStringOpts,'@',"P@");
    RYGMCOwnerInstallOne(cls,@"getString:withOptions:withDefault:",(IMP)RYGMCOwnerStringOptsDef,&gRYGMCUpStringOptsDef,'@',"P@@");
}

static void RYGMCOwnerDrain(void) {
    for (;;) {
        uint64_t generation = atomic_load_explicit(&gRYGMCGeneration, memory_order_relaxed);
        @autoreleasepool { RYGMCOwnerInstallHooks(); }
        if (generation == atomic_load_explicit(&gRYGMCGeneration, memory_order_relaxed)) break;
    }
    atomic_store_explicit(&gRYGMCScheduled, false, memory_order_release);
}

static void RYGMCOwnerSchedule(void) {
    if (!atomic_load_explicit(&gRYGMCWanted, memory_order_acquire)) return;
    atomic_fetch_add_explicit(&gRYGMCGeneration, 1, memory_order_relaxed);
    bool expected = false;
    if (!atomic_compare_exchange_strong_explicit(&gRYGMCScheduled, &expected, true,
                                                  memory_order_acq_rel, memory_order_acquire)) return;
    dispatch_async(RYGMCOwnerQueue(), ^{ RYGMCOwnerDrain(); });
}

static void RYGMCOwnerImageDidLoad(const struct mach_header *header, intptr_t slide) {
    (void)header; (void)slide;
    // Zero file I/O and zero Runtime Browser work while dyld is notifying us.
    RYGMCOwnerSchedule();
}

@implementation RYGMobileConfig (RYGMobileConfigHookOwner)

+ (void)load {
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        Method original = class_getInstanceMethod(self, @selector(setOverride:for:));
        Method owned = class_getInstanceMethod(self, @selector(ryg_owner_setOverride:for:));
        if (original && owned) method_exchangeImplementations(original, owned);
    });
}

- (BOOL)ryg_owner_setOverride:(id)value for:(RYGMCParam *)param {
    BOOL success = [self ryg_owner_setOverride:value for:param];
    if (success) {
        atomic_store_explicit(&gRYGMCWanted, true, memory_order_release);
        RYGMCOwnerSchedule();
    }
    return success;
}

@end

__attribute__((constructor)) static void RYGInstallMobileConfigHookOwner(void) {
    @autoreleasepool {
        // RYGMobileConfig init reads mc_overrides.plist exactly once and activates
        // those exact PIDs in memory; no schema/config-name scan is involved.
        RYGMobileConfig *mobileConfig = RYGMobileConfig.shared;
        BOOL wanted = mobileConfig.overrideCount > 0 || [RYGUtils getBoolPref:@"ryg_metaconfig_enabled"];
        atomic_store_explicit(&gRYGMCWanted, wanted, memory_order_release);
    }
    if (!atomic_load_explicit(&gRYGMCWanted, memory_order_acquire)) return;

    _dyld_register_func_for_add_image(RYGMCOwnerImageDidLoad);
    RYGMCOwnerSchedule();
    dispatch_async(dispatch_get_main_queue(), ^{
        [NSNotificationCenter.defaultCenter addObserverForName:UIApplicationDidBecomeActiveNotification
                                                         object:nil
                                                          queue:NSOperationQueue.mainQueue
                                                     usingBlock:^(__unused NSNotification *note) {
            RYGMCOwnerSchedule();
        }];
    });
}
