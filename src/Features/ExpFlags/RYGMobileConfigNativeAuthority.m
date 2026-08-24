#import "RYGMobileConfig.h"
#import "RYGMobileConfigNameMappingStore.h"
#import <Foundation/Foundation.h>
#import <objc/runtime.h>
#import <objc/message.h>
#import <dlfcn.h>
#include <stdint.h>
#include <stdlib.h>
#include <string.h>

// Native MobileConfig authority for the 2026-08-23 Instagram/FBShared pair.
//
// This file owns semantic adaptation only. It never hooks a MobileConfig getter
// and performs no work on the hot read path. RYGMobileConfigHookOwner.m remains
// the sole getter owner.
//
// Active session chain confirmed in the current binaries:
//   FBMobileConfigFBTGlobalSessionManager.sharedInstance
//     -> currentSessionContextManagerHolder
//     -> mcFbtManager
//     -> mobileconfig
//
// The resulting FB/IGMobileConfigContextManager is also the path and unit
// authority. No App Group UUID, user id, unit nibble, or mirrored PID is guessed.

static const char *RYGMCUnqualifiedType(const char *type) {
    while (type && *type && strchr("rnNoORV", *type)) type++;
    return type;
}

static BOOL RYGMCReturnsObjectNoArg(Method method) {
    if (!method || method_getNumberOfArguments(method) != 2) return NO;
    char type[32] = {0};
    method_getReturnType(method, type, sizeof(type));
    type[sizeof(type) - 1] = 0;
    const char *raw = RYGMCUnqualifiedType(type);
    return raw && *raw == '@';
}

static BOOL RYGMCReturnsIntegerNoArg(Method method) {
    if (!method || method_getNumberOfArguments(method) != 2) return NO;
    char type[32] = {0};
    method_getReturnType(method, type, sizeof(type));
    const char *raw = RYGMCUnqualifiedType(type);
    return raw && strchr("cCsSiIlLqQB", *raw) != NULL;
}

static BOOL RYGMCReturnsIntegerWithSpecifier(Method method) {
    if (!method || method_getNumberOfArguments(method) != 3) return NO;
    char type[96] = {0};
    method_getReturnType(method, type, sizeof(type));
    const char *ret = RYGMCUnqualifiedType(type);
    if (!ret || !strchr("cCsSiIlLqQ", *ret)) return NO;
    memset(type, 0, sizeof(type));
    method_getArgumentType(method, 2, type, sizeof(type));
    const char *arg = RYGMCUnqualifiedType(type);
    return arg && (*arg == 'Q' || *arg == 'q' || (*arg == '{' && (strstr(arg, "=Q}") || strstr(arg, "=q}"))));
}

static id RYGMCCallObjectNoArg(id receiver, BOOL classMethod, const char *selectorName) {
    if (!receiver || !selectorName) return nil;
    SEL selector = sel_registerName(selectorName);
    Method method = classMethod ? class_getClassMethod((Class)receiver, selector)
                                : class_getInstanceMethod([receiver class], selector);
    if (!RYGMCReturnsObjectNoArg(method)) return nil;
    return ((id (*)(id, SEL))objc_msgSend)(receiver, selector);
}

static uint64_t RYGMCCallIntegerNoArg(id receiver, const char *selectorName) {
    if (!receiver || !selectorName) return 0;
    SEL selector = sel_registerName(selectorName);
    Method method = class_getInstanceMethod([receiver class], selector);
    if (!RYGMCReturnsIntegerNoArg(method)) return 0;
    return ((uint64_t (*)(id, SEL))objc_msgSend)(receiver, selector);
}

static id RYGMCActiveSessionContextManager(void) {
    Class globalClass = objc_lookUpClass("FBMobileConfigFBTGlobalSessionManager");
    if (!globalClass) return nil;
    id global = RYGMCCallObjectNoArg((id)globalClass, YES, "sharedInstance");
    id holder = RYGMCCallObjectNoArg(global, NO, "currentSessionContextManagerHolder");
    id fbtManager = RYGMCCallObjectNoArg(holder, NO, "mcFbtManager");
    id manager = RYGMCCallObjectNoArg(fbtManager, NO, "mobileconfig");
    if (!manager) return nil;
    Method pathMethod = class_getInstanceMethod([manager class], sel_registerName("getOverridesTablePath"));
    return RYGMCReturnsObjectNoArg(pathMethod) ? manager : nil;
}

static NSString *RYGMCNativeDataDirectoryFromValue(id value) {
    NSString *path = nil;
    if ([value isKindOfClass:NSURL.class]) path = [(NSURL *)value path];
    else if ([value isKindOfClass:NSString.class]) path = value;
    if ([path hasPrefix:@"file://"]) path = [NSURL URLWithString:path].path;
    path = path.stringByStandardizingPath;
    if (!path.length) return nil;
    if ([path.pathExtension.lowercaseString isEqualToString:@"data"]) return path;
    NSString *parent = path.stringByDeletingLastPathComponent;
    return [parent.pathExtension.lowercaseString isEqualToString:@"data"] ? parent : nil;
}

static NSString *RYGMCDataDirectoryFromManager(id manager, BOOL create) {
    if (!manager) return nil;
    SEL selector = sel_registerName("getOverridesTablePath");
    Method method = class_getInstanceMethod([manager class], selector);
    if (!RYGMCReturnsObjectNoArg(method)) return nil;
    id value = ((id (*)(id, SEL))objc_msgSend)(manager, selector);
    NSString *path = RYGMCNativeDataDirectoryFromValue(value);
    if (!path.length) return nil;
    BOOL isDirectory = NO;
    if ([NSFileManager.defaultManager fileExistsAtPath:path isDirectory:&isDirectory]) return isDirectory ? path : nil;
    if (!create) return nil;
    return [NSFileManager.defaultManager createDirectoryAtPath:path withIntermediateDirectories:YES attributes:nil error:nil] ? path : nil;
}

// getUnitType has existed with both enum-style (4/8) and already-shifted
// representations across MobileConfig generations. We accept only the two
// forms that map to the known unit nibble and then validate the resulting
// specifier through the live manager before returning it.
static uint64_t RYGMCActiveUnitBase(id manager) {
    uint64_t raw = RYGMCCallIntegerNoArg(manager, "getUnitType");
    if (raw == 4 || raw == 8) return raw << 4;
    uint64_t nibble = raw & 0xF0ULL;
    if ((nibble == 0x40ULL || nibble == 0x80ULL) && (raw & ~0xFFULL) == 0) return nibble;
    return 0;
}

static int (*RYGMCTypeFromParameter(void))(uint64_t) {
    static int (*fn)(uint64_t);
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        fn = (int (*)(uint64_t))dlsym(RTLD_DEFAULT, "_ZN12mobileconfig17typeFromParameterEy");
    });
    return fn;
}

static uint64_t RYGMCStableIdForSpecifier(id manager, uint64_t specifier) {
    if (!manager || !specifier) return 0;
    SEL selector = sel_registerName("getStableIdFromParamSpecifier:");
    Method method = class_getInstanceMethod([manager class], selector);
    if (!RYGMCReturnsIntegerWithSpecifier(method)) return UINT64_MAX; // validation unavailable, not failed
    return ((uint64_t (*)(id, SEL, uint64_t))objc_msgSend)(manager, selector, specifier);
}

static uint64_t RYGMCResolveExactPID(id manager,
                                     unsigned int ordinal,
                                     unsigned int paramIndex,
                                     unsigned int serial,
                                     RYGMCType type) {
    if (!manager || !RYGMCTypeIsRuntimeValue(type)) return 0;
    uint64_t unitBase = RYGMCActiveUnitBase(manager);
    if (unitBase != 0x40ULL && unitBase != 0x80ULL) return 0;

    uint64_t pid = ((unitBase | ((uint64_t)type & 0x0FULL)) << 48)
                 | ((uint64_t)ordinal << 32)
                 | ((uint64_t)paramIndex << 16)
                 | (uint64_t)serial;

    int (*typeFromParameter)(uint64_t) = RYGMCTypeFromParameter();
    if (!typeFromParameter || typeFromParameter(pid) != (int)type) return 0;

    // When the current manager exposes stable-id translation, use it as the
    // live round-trip guard. A zero stable id means this specifier is not valid
    // for the active unit/session and must not be applied.
    uint64_t stable = RYGMCStableIdForSpecifier(manager, pid);
    if (stable != UINT64_MAX && stable == 0) return 0;
    return pid;
}

static void RYGMCOverlayMappingEntries(id json, NSMutableDictionary<NSNumber *, NSDictionary *> *catalog) {
    NSArray *entries = nil;
    if ([json isKindOfClass:NSArray.class]) entries = json;
    else if ([json isKindOfClass:NSDictionary.class]) {
        id names = ((NSDictionary *)json)[@"id_to_names"];
        if ([names isKindOfClass:NSArray.class]) entries = names;
    }
    for (id raw in entries) {
        if (![raw isKindOfClass:NSString.class]) continue;
        NSArray<NSString *> *parts = [(NSString *)raw componentsSeparatedByString:@":"];
        if (parts.count < 2) continue;
        char *end = NULL;
        unsigned long long config = strtoull(parts[0].UTF8String, &end, 10);
        if (!config || config > UINT32_MAX || end == parts[0].UTF8String || *end != '\0') continue;

        NSNumber *key = @((unsigned int)config);
        NSDictionary *previous = [catalog[key] isKindOfClass:NSDictionary.class] ? catalog[key] : nil;
        NSMutableDictionary<NSNumber *, NSString *> *params = [NSMutableDictionary dictionaryWithDictionary:
            [previous[@"params"] isKindOfClass:NSDictionary.class] ? previous[@"params"] : @{}];
        for (NSUInteger index = 2; index + 1 < parts.count; index += 2) {
            char *paramEnd = NULL;
            unsigned long long param = strtoull(parts[index].UTF8String, &paramEnd, 10);
            NSString *name = parts[index + 1];
            if (param <= UINT32_MAX && paramEnd != parts[index].UTF8String && *paramEnd == '\0' && name.length)
                params[@((unsigned int)param)] = name;
        }
        NSString *configName = parts[1].length ? parts[1] : ([previous[@"name"] isKindOfClass:NSString.class] ? previous[@"name"] : @"");
        catalog[key] = @{@"name":configName ?: @"", @"params":params.copy};
    }
}

static void RYGMCOverlayMappingFile(NSString *path, NSMutableDictionary<NSNumber *, NSDictionary *> *catalog) {
    NSData *data = path.length ? [NSData dataWithContentsOfFile:path] : nil;
    if (!data.length) return;
    id json = [NSJSONSerialization JSONObjectWithData:data options:0 error:nil];
    if (json) RYGMCOverlayMappingEntries(json, catalog);
}

static NSDictionary *RYGMCActiveMappingCatalog(NSDictionary *fallback) {
    NSMutableDictionary<NSNumber *, NSDictionary *> *catalog = [NSMutableDictionary dictionary];
    if ([fallback isKindOfClass:NSDictionary.class]) [catalog addEntriesFromDictionary:fallback];

    // The active App Group document is authoritative for names imported by the
    // user. Overlay it after the local cache so it always wins.
    NSString *directory = RYGMCDataDirectoryFromManager(RYGMCActiveSessionContextManager(), NO);
    if (directory.length) {
        NSString *mapping = [directory stringByAppendingPathComponent:@"id_name_mapping.json"];
        RYGMCOverlayMappingFile(mapping, catalog);
        for (NSString *name in [NSFileManager.defaultManager contentsOfDirectoryAtPath:directory error:nil]) {
            if ([name hasPrefix:@"mc_sync_response_dump"])
                RYGMCOverlayMappingFile([directory stringByAppendingPathComponent:name], catalog);
        }
    }
    return catalog.copy;
}

@interface RYGMobileConfig (RYGNativeAuthorityPrivate)
- (NSString *)ryg_nativeDataDirectory;
- (NSString *)ryg_authorityNativeDataDirectory;
- (NSString *)mcDirectory;
- (NSString *)ryg_authorityMCDirectory;
- (NSDictionary *)loadNameCatalog;
- (NSDictionary *)ryg_authorityLoadNameCatalog;
- (unsigned long long)validParamIDForOrdinal:(unsigned int)ordinal index:(unsigned int)paramIndex serial:(unsigned int)serial type:(RYGMCType)type;
- (unsigned long long)ryg_authorityParamIDForOrdinal:(unsigned int)ordinal index:(unsigned int)paramIndex serial:(unsigned int)serial type:(RYGMCType)type;
- (BOOL)writeNativeForPid:(unsigned long long)pid value:(id)value;
- (BOOL)writeNativeBothUnitsForPid:(unsigned long long)pid value:(id)value;
- (BOOL)ryg_authorityWriteNativeForPid:(unsigned long long)pid value:(id)value;
- (BOOL)removeNativeForPid:(unsigned long long)pid;
- (void)removeNativeBothUnitsForPid:(unsigned long long)pid;
- (void)ryg_authorityRemoveNativeForPid:(unsigned long long)pid;
- (unsigned long long)bestParamIDFor:(RYGMCParam *)param;
- (unsigned long long)ryg_authorityBestParamIDFor:(RYGMCParam *)param;
- (id)managerForPid:(unsigned long long)pid;
- (id)ryg_authorityManagerForPid:(unsigned long long)pid;
@end

@implementation RYGMobileConfig (RYGNativeAuthority)

- (NSString *)ryg_authorityNativeDataDirectory {
    return RYGMCDataDirectoryFromManager(RYGMCActiveSessionContextManager(), YES);
}

- (NSString *)ryg_authorityMCDirectory {
    return RYGMCDataDirectoryFromManager(RYGMCActiveSessionContextManager(), YES);
}

- (NSDictionary *)ryg_authorityLoadNameCatalog {
    // After exchange this invokes the original implementation. It may provide
    // the persistent cache, but active App Group names are always overlaid.
    NSDictionary *fallback = [self ryg_authorityLoadNameCatalog];
    return RYGMCActiveMappingCatalog(fallback ?: @{});
}

- (unsigned long long)ryg_authorityParamIDForOrdinal:(unsigned int)ordinal
                                               index:(unsigned int)paramIndex
                                              serial:(unsigned int)serial
                                                type:(RYGMCType)type {
    return RYGMCResolveExactPID(RYGMCActiveSessionContextManager(), ordinal, paramIndex, serial, type);
}

- (BOOL)ryg_authorityWriteNativeForPid:(unsigned long long)pid value:(id)value {
    if (!pid || !value) return NO;
    return [self writeNativeForPid:pid value:value];
}

- (void)ryg_authorityRemoveNativeForPid:(unsigned long long)pid {
    if (pid) (void)[self removeNativeForPid:pid];
}

- (unsigned long long)ryg_authorityBestParamIDFor:(RYGMCParam *)param {
    if (!param.runtimeBacked || !param.paramID) return 0;
    return param.paramID;
}

- (id)ryg_authorityManagerForPid:(unsigned long long)pid {
    (void)pid;
    return RYGMCActiveSessionContextManager();
}

@end

static BOOL RYGMCExchange(Class cls, SEL originalSelector, SEL authoritySelector) {
    Method original = class_getInstanceMethod(cls, originalSelector);
    Method authority = class_getInstanceMethod(cls, authoritySelector);
    if (!original || !authority) return NO;
    if (method_getNumberOfArguments(original) != method_getNumberOfArguments(authority)) return NO;
    method_exchangeImplementations(original, authority);
    return YES;
}

__attribute__((constructor(65470))) static void RYGMobileConfigInstallNativeAuthority(void) {
    Class cls = RYGMobileConfig.class;
    if (!cls) return;

    // Semantic adapters only; no MobileConfig getter is hooked here.
    RYGMCExchange(cls, @selector(ryg_nativeDataDirectory), @selector(ryg_authorityNativeDataDirectory));
    RYGMCExchange(cls, @selector(mcDirectory), @selector(ryg_authorityMCDirectory));
    RYGMCExchange(cls, @selector(loadNameCatalog), @selector(ryg_authorityLoadNameCatalog));
    RYGMCExchange(cls,
                  @selector(validParamIDForOrdinal:index:serial:type:),
                  @selector(ryg_authorityParamIDForOrdinal:index:serial:type:));
    RYGMCExchange(cls,
                  @selector(writeNativeBothUnitsForPid:value:),
                  @selector(ryg_authorityWriteNativeForPid:value:));
    RYGMCExchange(cls,
                  @selector(removeNativeBothUnitsForPid:),
                  @selector(ryg_authorityRemoveNativeForPid:));
    RYGMCExchange(cls, @selector(bestParamIDFor:), @selector(ryg_authorityBestParamIDFor:));
    RYGMCExchange(cls, @selector(managerForPid:), @selector(ryg_authorityManagerForPid:));
}
