#import "RYGCFunctionOverrideEngine.h"
#import "../../modules/fishhook/fishhook.h"
#import <stdatomic.h>
#import <stdbool.h>
#import <string.h>

typedef NS_ENUM(NSInteger, RYGCFunctionProfile) {
    RYGCFunctionProfileUnknown = 0,
    RYGCFunctionProfileEasyGatingBool8,
    RYGCFunctionProfileMSGCSessionedBool3,
    RYGCFunctionProfileNoArgBool,
};

typedef struct {
    char name[160];
    void *original;
    RYGCFunctionProfile profile;
    atomic_int force;      // -1 native, 0 false, 1 true
    atomic_int observed;   // -1 unknown, 0 false, 1 true
    atomic_uint hits;
} RYGCFunctionSlot;

#define RYG_CBOOL_SLOTS 12
static RYGCFunctionSlot gSlots[RYG_CBOOL_SLOTS];
static int gSlotCount = 0;
static NSString *const kRYGCFunctionOverridesKey = @"ryg_c_function_bool_overrides";

static NSString *RYGNormalizeCSymbol(NSString *symbol) {
    if (![symbol isKindOfClass:NSString.class] || !symbol.length) return @"";
    return [symbol hasPrefix:@"_"] ? [symbol substringFromIndex:1] : symbol;
}

static RYGCFunctionProfile RYGProfileForName(NSString *name) {
    NSString *n = RYGNormalizeCSymbol(name);
    if ([n isEqualToString:@"EasyGatingGetBoolean_Internal_DoNotUseOrMock"] ||
        [n isEqualToString:@"EasyGatingGetBooleanUsingAuthDataContext_Internal_DoNotUseOrMock"] ||
        [n isEqualToString:@"MCQEasyGatingGetBooleanInternalDoNotUseOrMock"]) return RYGCFunctionProfileEasyGatingBool8;
    if ([n isEqualToString:@"MSGCSessionedMobileConfigGetBoolean"]) return RYGCFunctionProfileMSGCSessionedBool3;
    if ([n isEqualToString:@"MEBIsMinosDogfoodMekEncryptionVersionEnabled"] ||
        [n isEqualToString:@"IGAppIsInstagramInternalAppsInstalledAndNotHiddenAfteriOS18"]) return RYGCFunctionProfileNoArgBool;
    return RYGCFunctionProfileUnknown;
}

static NSDictionary<NSString *, NSNumber *> *RYGStoredCOverrides(void) {
    id value = [NSUserDefaults.standardUserDefaults objectForKey:kRYGCFunctionOverridesKey];
    if (![value isKindOfClass:NSDictionary.class]) return @{};
    NSMutableDictionary *clean = [NSMutableDictionary dictionary];
    [(NSDictionary *)value enumerateKeysAndObjectsUsingBlock:^(id key, id obj, BOOL *stop) {
        if ([key isKindOfClass:NSString.class] && [obj isKindOfClass:NSNumber.class]) clean[key] = @([obj boolValue]);
    }];
    return clean.copy;
}

static RYGCFunctionSlot *RYGSlotForName(const char *name) {
    if (!name) return NULL;
    for (int i = 0; i < gSlotCount; i++) if (strcmp(gSlots[i].name, name) == 0) return &gSlots[i];
    return NULL;
}

static bool RYGCallOriginal(RYGCFunctionSlot *slot,
                            void *a0, void *a1, void *a2, void *a3,
                            void *a4, void *a5, void *a6, void *a7) {
    if (!slot || !slot->original) return false;
    switch (slot->profile) {
        case RYGCFunctionProfileEasyGatingBool8:
            return ((bool (*)(void *,void *,void *,void *,void *,void *,void *,void *))slot->original)(a0,a1,a2,a3,a4,a5,a6,a7);
        case RYGCFunctionProfileMSGCSessionedBool3:
            return ((bool (*)(void *,void *,void *))slot->original)(a0,a1,a2);
        case RYGCFunctionProfileNoArgBool:
            return ((bool (*)(void))slot->original)();
        default: return false;
    }
}

#define DEFINE_RYG_CBOOL_STUB(I) \
static bool RYGCStub##I(void *a0,void *a1,void *a2,void *a3,void *a4,void *a5,void *a6,void *a7) { \
    RYGCFunctionSlot *s = &gSlots[I]; \
    atomic_fetch_add(&s->hits, 1); \
    bool native = RYGCallOriginal(s,a0,a1,a2,a3,a4,a5,a6,a7); \
    atomic_store(&s->observed, native ? 1 : 0); \
    int forced = atomic_load(&s->force); \
    return forced < 0 ? native : forced != 0; \
}
DEFINE_RYG_CBOOL_STUB(0) DEFINE_RYG_CBOOL_STUB(1) DEFINE_RYG_CBOOL_STUB(2)
DEFINE_RYG_CBOOL_STUB(3) DEFINE_RYG_CBOOL_STUB(4) DEFINE_RYG_CBOOL_STUB(5)
DEFINE_RYG_CBOOL_STUB(6) DEFINE_RYG_CBOOL_STUB(7) DEFINE_RYG_CBOOL_STUB(8)
DEFINE_RYG_CBOOL_STUB(9) DEFINE_RYG_CBOOL_STUB(10) DEFINE_RYG_CBOOL_STUB(11)

static void *RYGStubForIndex(int index) {
    static void *stubs[RYG_CBOOL_SLOTS] = {
        (void *)RYGCStub0,(void *)RYGCStub1,(void *)RYGCStub2,(void *)RYGCStub3,
        (void *)RYGCStub4,(void *)RYGCStub5,(void *)RYGCStub6,(void *)RYGCStub7,
        (void *)RYGCStub8,(void *)RYGCStub9,(void *)RYGCStub10,(void *)RYGCStub11,
    };
    return index >= 0 && index < RYG_CBOOL_SLOTS ? stubs[index] : NULL;
}

static BOOL RYGEnsureCFunctionInstalled(NSString *symbol) {
    NSString *name = RYGNormalizeCSymbol(symbol);
    RYGCFunctionProfile profile = RYGProfileForName(name);
    if (!name.length || profile == RYGCFunctionProfileUnknown) return NO;
    @synchronized(RYGCFunctionOverrideEngine.class) {
        RYGCFunctionSlot *existing = RYGSlotForName(name.UTF8String);
        if (existing) return existing->original != NULL;
        if (gSlotCount >= RYG_CBOOL_SLOTS) return NO;
        int index = gSlotCount++;
        RYGCFunctionSlot *slot = &gSlots[index];
        memset(slot, 0, sizeof(*slot));
        strncpy(slot->name, name.UTF8String, sizeof(slot->name)-1);
        slot->profile = profile;
        atomic_store(&slot->force, -1);
        atomic_store(&slot->observed, -1);
        NSNumber *stored = RYGStoredCOverrides()[name];
        if (stored) atomic_store(&slot->force, stored.boolValue ? 1 : 0);

        struct rebinding rb = {0};
        rb.name = slot->name;
        rb.replacement = RYGStubForIndex(index);
        rb.replaced = &slot->original;
        int rc = rebind_symbols(&rb, 1);
        if (rc != 0 || !slot->original) {
            gSlotCount--;
            memset(slot, 0, sizeof(*slot));
            return NO;
        }
        return YES;
    }
}

@implementation RYGCFunctionOverrideEngine

+ (BOOL)isKnownBoolFunctionSymbol:(NSString *)symbol {
    return RYGProfileForName(symbol) != RYGCFunctionProfileUnknown;
}

+ (NSNumber *)forceForSymbol:(NSString *)symbol {
    NSString *name = RYGNormalizeCSymbol(symbol);
    RYGCFunctionSlot *slot = RYGSlotForName(name.UTF8String);
    if (slot) { int value = atomic_load(&slot->force); return value < 0 ? nil : @(value != 0); }
    return RYGStoredCOverrides()[name];
}

+ (NSNumber *)observedValueForSymbol:(NSString *)symbol {
    RYGCFunctionSlot *slot = RYGSlotForName(RYGNormalizeCSymbol(symbol).UTF8String);
    if (!slot) return nil;
    int value = atomic_load(&slot->observed);
    return value < 0 ? nil : @(value != 0);
}

+ (NSUInteger)callCountForSymbol:(NSString *)symbol {
    RYGCFunctionSlot *slot = RYGSlotForName(RYGNormalizeCSymbol(symbol).UTF8String);
    return slot ? atomic_load(&slot->hits) : 0;
}

+ (BOOL)setForce:(NSNumber *)value forSymbol:(NSString *)symbol {
    NSString *name = RYGNormalizeCSymbol(symbol);
    if (![self isKnownBoolFunctionSymbol:name]) return NO;
    if (!RYGEnsureCFunctionInstalled(name)) return NO;
    RYGCFunctionSlot *slot = RYGSlotForName(name.UTF8String);
    if (!slot) return NO;

    NSMutableDictionary *stored = [RYGStoredCOverrides() mutableCopy];
    if (value) {
        stored[name] = @([value boolValue]);
        atomic_store(&slot->force, value.boolValue ? 1 : 0);
    } else {
        [stored removeObjectForKey:name];
        atomic_store(&slot->force, -1);
    }
    [NSUserDefaults.standardUserDefaults setObject:stored.copy forKey:kRYGCFunctionOverridesKey];
    return YES;
}

@end

__attribute__((constructor(118))) static void RYGReinstallPersistedCFunctionOverrides(void) {
    @autoreleasepool {
        for (NSString *name in RYGStoredCOverrides()) RYGEnsureCFunctionInstalled(name);
    }
}
