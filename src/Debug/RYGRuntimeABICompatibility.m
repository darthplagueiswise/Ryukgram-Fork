#import "RYGRuntimeBrowserEngine.h"

// Compatibility note
// ------------------
// This translation unit intentionally does not swizzle the runtime browser.
//
// Older dogfood builds used this file to replace boolMethodsForImagePath:scope:,
// overrideForKey:, setOverride:forMethod:, reinstallPersistedOverrides and the
// RYGRuntimeBoolMethod liveValue getter. Those replacements later competed with
// RYGRuntimeBrowserSafety, RYGRuntimeOverrideSafety and RYGRuntimeLiveObserver,
// making the effective implementation depend on constructor/link order.
//
// Current ownership is explicit:
//   * RYGRuntimeBrowserSafety.m   -> BOOL metadata enumeration
//   * RYGRuntimeOverrideSafety.m  -> persisted runtime overrides
//   * RYGRuntimeLiveObserver.m    -> opt-in native-value observation
//
// Keeping this file as a no-op preserves source-tree/build compatibility while
// removing the duplicate runtime implementation rather than stacking another
// corrective swizzle on top of it.
