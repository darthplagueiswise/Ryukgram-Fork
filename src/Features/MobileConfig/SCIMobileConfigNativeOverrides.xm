// SCIMobileConfigNativeOverrides.xm
// Experimental, guarded bridge for FBMobileConfigOverridesTable::updateOverrideForParam.
// This does NOT fishhook readers and does not run from hot paths. It is called only
// from the Dogfood Browser UI after the user chooses an override for a captured param.

#import "SCIMobileConfigNativeOverrides.h"
#import "SCIMobileConfigRuntime.h"
#import "../../Utils.h"
#import <dlfcn.h>
#import <objc/runtime.h>
#import <objc/message.h>
#import <memory>
#import <string>

namespace mobileconfig {
class FBMobileConfigManager;
class FBMobileConfigOverridesTable;
}

using SCISharedManager = std::shared_ptr<mobileconfig::FBMobileConfigManager>;
using SCISharedOverrides = std::shared_ptr<mobileconfig::FBMobileConfigOverridesTable>;
using SCIGetManagerFn = SCISharedManager (*)(id);
using SCIGetOverridesTableFn = SCISharedOverrides (*)(mobileconfig::FBMobileConfigManager *, bool);
using SCIUpdateBoolFn = void (*)(mobileconfig::FBMobileConfigOverridesTable *, unsigned long long, bool, bool);
using SCIUpdateInt64Fn = void (*)(mobileconfig::FBMobileConfigOverridesTable *, unsigned long long, long long, bool);
using SCIUpdateDoubleFn = void (*)(mobileconfig::FBMobileConfigOverridesTable *, unsigned long long, double, bool);
using SCIUpdateStringFn = void (*)(mobileconfig::FBMobileConfigOverridesTable *, unsigned long long, const std::string &, bool);
using SCIRemoveFn = void (*)(mobileconfig::FBMobileConfigOverridesTable *, unsigned long long, bool);

template<typename T>
static T SCINativeSym(const char *a, const char *b) {
    void *p = a ? dlsym(RTLD_DEFAULT, a) : NULL;
    if (!p && b) p = dlsym(RTLD_DEFAULT, b);
    return reinterpret_cast<T>(p);
}

static NSError *SCINativeError(NSString *reason) {
    return [NSError errorWithDomain:@"RyukGram.NativeMobileConfig" code:1 userInfo:@{NSLocalizedDescriptionKey: reason ?: @"Native MobileConfig override unavailable"}];
}

@implementation SCIMobileConfigNativeOverrides

+ (SCIGetManagerFn)getManagerFn {
    return SCINativeSym<SCIGetManagerFn>("_Z22getMobileConfigManagerPU32objcproto21FBMobileConfigContext11objc_object", "__Z22getMobileConfigManagerPU32objcproto21FBMobileConfigContext11objc_object");
}

+ (SCIGetOverridesTableFn)getOverridesTableFn {
    return SCINativeSym<SCIGetOverridesTableFn>("_ZN12mobileconfig21FBMobileConfigManager25getOrCreateOverridesTableEb", "__ZN12mobileconfig21FBMobileConfigManager25getOrCreateOverridesTableEb");
}

+ (SCIUpdateBoolFn)updateBoolFn {
    return SCINativeSym<SCIUpdateBoolFn>("_ZN12mobileconfig28FBMobileConfigOverridesTable22updateOverrideForParamEybb", "__ZN12mobileconfig28FBMobileConfigOverridesTable22updateOverrideForParamEybb");
}

+ (SCIUpdateInt64Fn)updateInt64Fn {
    return SCINativeSym<SCIUpdateInt64Fn>("_ZN12mobileconfig28FBMobileConfigOverridesTable22updateOverrideForParamEyxb", "__ZN12mobileconfig28FBMobileConfigOverridesTable22updateOverrideForParamEyxb");
}

+ (SCIUpdateDoubleFn)updateDoubleFn {
    return SCINativeSym<SCIUpdateDoubleFn>("_ZN12mobileconfig28FBMobileConfigOverridesTable22updateOverrideForParamEydb", "__ZN12mobileconfig28FBMobileConfigOverridesTable22updateOverrideForParamEydb");
}

+ (SCIUpdateStringFn)updateStringFn {
    return SCINativeSym<SCIUpdateStringFn>("_ZN12mobileconfig28FBMobileConfigOverridesTable22updateOverrideForParamEyRKNSt3__112basic_stringIcNS1_11char_traitsIcEENS1_9allocatorIcEEEEb", "__ZN12mobileconfig28FBMobileConfigOverridesTable22updateOverrideForParamEyRKNSt3__112basic_stringIcNS1_11char_traitsIcEENS1_9allocatorIcEEEEb");
}

+ (SCIRemoveFn)removeFn {
    return SCINativeSym<SCIRemoveFn>("_ZN12mobileconfig28FBMobileConfigOverridesTable22removeOverrideForParamEyb", "__ZN12mobileconfig28FBMobileConfigOverridesTable22removeOverrideForParamEyb");
}

+ (NSDictionary<NSString *, id> *)symbolStatus {
    return @{
        @"getMobileConfigManager": @([self getManagerFn] != NULL),
        @"getOrCreateOverridesTable": @([self getOverridesTableFn] != NULL),
        @"updateBool": @([self updateBoolFn] != NULL),
        @"updateInt64": @([self updateInt64Fn] != NULL),
        @"updateDouble": @([self updateDoubleFn] != NULL),
        @"updateString": @([self updateStringFn] != NULL),
        @"remove": @([self removeFn] != NULL),
    };
}

+ (BOOL)canAttemptNativeOverride {
    NSDictionary *s = [self symbolStatus];
    return [s[@"getMobileConfigManager"] boolValue] && [s[@"getOrCreateOverridesTable"] boolValue];
}

+ (BOOL)objectLooksLikeMobileConfigContext:(id)obj {
    if (!obj) return NO;
    Protocol *p = objc_getProtocol("FBMobileConfigContext");
    if (p && [obj conformsToProtocol:p]) return YES;
    NSString *cls = NSStringFromClass([obj class]);
    return [cls containsString:@"MobileConfig"] && [cls containsString:@"Context"];
}

+ (BOOL)withOverridesTable:(BOOL (^)(mobileconfig::FBMobileConfigOverridesTable *table, NSString **reason))block reason:(NSString **)reasonOut {
    SCIGetManagerFn getMgr = [self getManagerFn];
    SCIGetOverridesTableFn getTable = [self getOverridesTableFn];
    if (!getMgr || !getTable) {
        if (reasonOut) *reasonOut = @"Native symbols not resolved";
        return NO;
    }
    NSArray *objects = [SCIMobileConfigRuntime liveContextObjects];
    if (!objects.count) {
        if (reasonOut) *reasonOut = @"No live FBMobileConfigContext captured. Turn on Runtime capture and open a surface that reads MobileConfig first.";
        return NO;
    }
    for (id obj in objects) {
        if (![self objectLooksLikeMobileConfigContext:obj]) continue;
        try {
            SCISharedManager mgr = getMgr(obj);
            if (!mgr.get()) continue;
            SCISharedOverrides table = getTable(mgr.get(), true);
            if (!table.get()) continue;
            NSString *localReason = nil;
            BOOL ok = block ? block(table.get(), &localReason) : NO;
            if (ok) return YES;
            if (localReason.length && reasonOut) *reasonOut = localReason;
        } catch (...) {
            if (reasonOut) *reasonOut = @"C++ exception while resolving overrides table";
            return NO;
        }
    }
    if (reasonOut && !*reasonOut) *reasonOut = @"No usable FBMobileConfigOverridesTable from captured contexts";
    return NO;
}

+ (BOOL)applyBoolOverrideForParamID:(unsigned long long)paramID value:(BOOL)value error:(NSError **)error {
    SCIUpdateBoolFn fn = [self updateBoolFn];
    if (!fn) { if (error) *error = SCINativeError(@"updateOverrideForParam<bool> not resolved"); return NO; }
    NSString *reason = nil;
    BOOL ok = [self withOverridesTable:^BOOL(mobileconfig::FBMobileConfigOverridesTable *table, NSString **r) {
        try { fn(table, paramID, value, true); return YES; } catch (...) { if (r) *r = @"C++ exception in bool override"; return NO; }
    } reason:&reason];
    if (!ok && error) *error = SCINativeError(reason);
    return ok;
}

+ (BOOL)applyInt64OverrideForParamID:(unsigned long long)paramID value:(long long)value error:(NSError **)error {
    SCIUpdateInt64Fn fn = [self updateInt64Fn];
    if (!fn) { if (error) *error = SCINativeError(@"updateOverrideForParam<int64> not resolved"); return NO; }
    NSString *reason = nil;
    BOOL ok = [self withOverridesTable:^BOOL(mobileconfig::FBMobileConfigOverridesTable *table, NSString **r) {
        try { fn(table, paramID, value, true); return YES; } catch (...) { if (r) *r = @"C++ exception in int64 override"; return NO; }
    } reason:&reason];
    if (!ok && error) *error = SCINativeError(reason);
    return ok;
}

+ (BOOL)applyDoubleOverrideForParamID:(unsigned long long)paramID value:(double)value error:(NSError **)error {
    SCIUpdateDoubleFn fn = [self updateDoubleFn];
    if (!fn) { if (error) *error = SCINativeError(@"updateOverrideForParam<double> not resolved"); return NO; }
    NSString *reason = nil;
    BOOL ok = [self withOverridesTable:^BOOL(mobileconfig::FBMobileConfigOverridesTable *table, NSString **r) {
        try { fn(table, paramID, value, true); return YES; } catch (...) { if (r) *r = @"C++ exception in double override"; return NO; }
    } reason:&reason];
    if (!ok && error) *error = SCINativeError(reason);
    return ok;
}

+ (BOOL)applyStringOverrideForParamID:(unsigned long long)paramID value:(NSString *)value error:(NSError **)error {
    SCIUpdateStringFn fn = [self updateStringFn];
    if (!fn) { if (error) *error = SCINativeError(@"updateOverrideForParam<string> not resolved"); return NO; }
    std::string s(value.UTF8String ?: "");
    NSString *reason = nil;
    BOOL ok = [self withOverridesTable:^BOOL(mobileconfig::FBMobileConfigOverridesTable *table, NSString **r) {
        try { fn(table, paramID, s, true); return YES; } catch (...) { if (r) *r = @"C++ exception in string override"; return NO; }
    } reason:&reason];
    if (!ok && error) *error = SCINativeError(reason);
    return ok;
}

+ (BOOL)removeOverrideForParamID:(unsigned long long)paramID error:(NSError **)error {
    SCIRemoveFn fn = [self removeFn];
    if (!fn) { if (error) *error = SCINativeError(@"removeOverrideForParam not resolved"); return NO; }
    NSString *reason = nil;
    BOOL ok = [self withOverridesTable:^BOOL(mobileconfig::FBMobileConfigOverridesTable *table, NSString **r) {
        try { fn(table, paramID, true); return YES; } catch (...) { if (r) *r = @"C++ exception in remove override"; return NO; }
    } reason:&reason];
    if (!ok && error) *error = SCINativeError(reason);
    return ok;
}

+ (BOOL)applyRuntimeFallbackOverrideForParamID:(unsigned long long)paramID type:(NSString *)type value:(id)value error:(NSError **)error {
    if (!type.length || !value) { if (error) *error = SCINativeError(@"Missing type/value"); return NO; }
    [SCIMobileConfigRuntime setRuntimeCaptureActive:YES];
    [SCIUtils setPref:@YES forKey:@"sci_mc_runtime_manual_overrides_enabled"];
    [SCIMobileConfigRuntime setManualOverride:value paramID:paramID type:type];
    extern void SCIInstallMobileConfigRuntimeHooksIfNeeded(void);
    SCIInstallMobileConfigRuntimeHooksIfNeeded();
    return YES;
}

+ (BOOL)removeRuntimeFallbackOverrideForParamID:(unsigned long long)paramID type:(NSString *)type {
    if (!type.length) return NO;
    [SCIMobileConfigRuntime removeManualOverrideForParamID:paramID type:type];
    return YES;
}

@end
