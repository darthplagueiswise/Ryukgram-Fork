#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

// Native MobileConfig override applier.
//
// This is the ROBUST path (doc 03 §12): instead of only intercepting the reader
// (which forces a value only while our hook runs, and only for the classes we
// hooked), this writes the override into the app's OWN overrides table via the
// native ObjC API:
//
//   [[FBMobileConfigStartupConfigs getInstance] setOverrideForParam:pid andValue:val]
//
// then calls IGMobileConfigForceUpdateConfigs to make the app re-read. This
// persists inside the app and affects EVERY reader (including ones we do not
// hook), exactly like Facebook's internal-settings submenu does.
//
// ABI confirmed by disassembly of FBSharedFramework:
//   +[FBMobileConfigStartupConfigs getInstance]        -> singleton (class method)
//   -setOverrideForParam:andValue:  v32@0:8Q16@24      -> uint64 paramID + id value
//   -removeOverrideForParam:        v24@0:8Q16         -> uint64 paramID
//   -getBool:withDefault:           B28@0:8{mc_bool_param_t=Q}16B24
//   {mc_bool_param_t=Q} is ABI-identical to a bare uint64 on arm64 AAPCS.
@interface SCINativeMobileConfigOverride : NSObject

// Whether the native path is available in this build (class + selectors present).
+ (BOOL)available;

// Apply/remove a single native override. type is @"bool"/@"int"/@"double"/@"string".
// Returns YES if the native call was made.
+ (BOOL)applyNativeOverrideForParamID:(unsigned long long)paramID
                                 type:(NSString *)type
                                value:(nullable id)value;

// Re-read configs after writing overrides (IGMobileConfigForceUpdateConfigs).
// Safe no-op if the symbol is unavailable.
+ (void)forceUpdateConfigs;

// Apply ALL persisted native overrides at launch. Reads the same persisted dict
// the runtime uses (via SCIMobileConfigRuntime), writes each into the native
// table, then forces one update. Cheap-guarded by the caller.
+ (NSUInteger)applyAllPersistedNativeOverrides;

@end

NS_ASSUME_NONNULL_END
