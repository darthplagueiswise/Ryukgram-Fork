// SCIMCLiveApply.h — RyukGram-Fork
//
// Applies MobileConfig overrides LIVE, in-process, via the exact C++ overrides
// table API that Instagram's own FBShared exports (the same path the Facebook
// Debug UI VCs drive under the hood). No network fetch, no params-list call, no
// relaunch — so it never hits the abort() precondition in
// _IGMobileConfigTryUpdateConfigsWithCompletion.
//
// Confirmed ABI (FBSharedFramework, disassembled with radare2):
//   mobileconfig::FBMobileConfigManager::getOrCreateOverridesTable(bool)
//     symbol: _ZN12mobileconfig21FBMobileConfigManager25getOrCreateOverridesTableEb
//     x0 = FBMobileConfigManager* (raw), w1 = bool, x8 = sret -> shared_ptr (16B)
//   mobileconfig::FBMobileConfigOverridesTable::updateOverrideForParam(unsigned long long, bool, bool)
//     symbol: _ZN12mobileconfig28FBMobileConfigOverridesTable22updateOverrideForParamEybb
//     x0 = OverridesTable* (raw), x1 = paramID (u64), w2 = value, w3 = persist
//   removeOverrideForParam(unsigned long long, bool)
//     symbol: _ZN12mobileconfig28FBMobileConfigOverridesTable22removeOverrideForParamEyb
//
// paramID note: this is the 64-bit MobileConfig descriptor value (the SAME
// identifier the native reader consumes). It must be resolved from the running
// image because it changes between Instagram builds; it is not the local build
// ordinal from params_map.txt.

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

typedef NS_ENUM(NSInteger, SCIMCLiveResult) {
    SCIMCLiveOK = 0,
    SCIMCLiveNoManager,      // could not resolve the live FBMobileConfigManager
    SCIMCLiveNoTable,        // getOrCreateOverridesTable returned null
    SCIMCLiveNoSymbol,       // a required C++ symbol was not found
};

@interface SCIMCLiveApply : NSObject

/// One-line status for a settings-row accessory: "ready", "no manager",
/// "no symbols". Cheap; safe to call on every cell render.
+ (NSString *)wiringStatus;

/// Read an exported MobileConfig DATA descriptor from the running image. Returns
/// zero when the symbol is absent in this app version.
+ (uint64_t)paramIDForDescriptorSymbol:(NSString *)symbolName;

/// Set (value) or clear (remove) a single override live. paramID is the 64-bit
/// MobileConfig param hash. Returns SCIMCLiveOK on success.
+ (SCIMCLiveResult)setOverrideForParamID:(uint64_t)paramID value:(BOOL)value;
+ (SCIMCLiveResult)clearOverrideForParamID:(uint64_t)paramID;

/// Validation entry point: resolves this build's ig_is_employee descriptor and
/// forces it true through the live overrides table.
+ (NSString *)applyIsEmployeeProbe;

@end

NS_ASSUME_NONNULL_END
