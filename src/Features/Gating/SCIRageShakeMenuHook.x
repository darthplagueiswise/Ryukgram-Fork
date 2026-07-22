// SCIRageShakeMenuHook.x — RyukGram-Fork
//
// THE missing piece: placing an override file sets the underlying gates, but the
// rage-shake menu rows (Internal Settings / Logged Out Internal Settings /
// Dogfooding Assistant) are decided at the CALLSITE that builds
// IGBugReportMenuViewController — and that callsite reads
// `internalSettingsAvailabilityStatus:` from a SERVER fragment
// (IGInternalSettingsAvailabilityFragment). For a non-employee account the server
// answers "not available", so the show* flags come through NO no matter what the
// local MobileConfig says. That is why "just dropping mc_overrides.json" does not
// make the menu appear.
//
// Fix (client-side, sideload-safe — MSHookMessageEx on an ObjC init, __DATA method
// list; no __TEXT patch): hook the menu's designated initializer and force the row
// flags YES. Two signatures are handled — the current build adds
// `showDogfoodingAssistant:maisaUXVariantRawValue:`, older builds don't.
//
// Verified against the v439 binary (__objc_methname):
//   initWithDeviceSession:userSession:reliabilityLogging:navChain:endpoint:
//     entryPoint:style:internalSettingsAvailabilityStatus:showInternalSettings:
//     showLoggedOutInternalSettings:showShakeToReportPreferenceToggle:
//     showDogfoodingAssistant:maisaUXVariantRawValue:
//
// This complements SCIEmployeeGateHook.x (which forces the EasyGating employee/
// dogfooding gates 2336/309/1315/2886). The gate hook flips the identity; this
// hook guarantees the rows render even when availabilityStatus is server-denied.

#import <Foundation/Foundation.h>

#ifndef SCI_RAGESHAKE_DEBUG
#define SCI_RAGESHAKE_DEBUG 1
#endif
#if SCI_RAGESHAKE_DEBUG
  #define SCI_LOG(...) NSLog(@"[SCIRageShakeMenu] " __VA_ARGS__)
#else
  #define SCI_LOG(...) do{}while(0)
#endif

// Force the availability enum to "available" as well. IGInternalSettingsAvailabilityStatus
// is a small enum; on this build "available" is the nonzero case. If a build flips
// this, the show* flags below still force the rows — this is belt-and-suspenders.
#ifndef SCI_INTERNAL_AVAIL_STATUS
#define SCI_INTERNAL_AVAIL_STATUS 1
#endif

%hook IGBugReportMenuViewController

// Current build (with Dogfooding Assistant row)
- (id)initWithDeviceSession:(id)ds userSession:(id)us reliabilityLogging:(id)rl
                   navChain:(id)nc endpoint:(id)ep entryPoint:(NSInteger)entry
                      style:(NSInteger)style
 internalSettingsAvailabilityStatus:(NSInteger)status
       showInternalSettings:(BOOL)showInternal
 showLoggedOutInternalSettings:(BOOL)showLoggedOut
 showShakeToReportPreferenceToggle:(BOOL)showShake
      showDogfoodingAssistant:(BOOL)showDogfood
        maisaUXVariantRawValue:(NSInteger)maisa {
    SCI_LOG(@"orig: avail=%ld internal=%d loggedOut=%d dogfood=%d -> forcing all YES",
            (long)status, showInternal, showLoggedOut, showDogfood);
    return %orig(ds, us, rl, nc, ep, entry, style,
                 SCI_INTERNAL_AVAIL_STATUS, /* availability */
                 YES,   /* showInternalSettings */
                 YES,   /* showLoggedOutInternalSettings */
                 showShake,
                 YES,   /* showDogfoodingAssistant */
                 maisa);
}

// Older build (no Dogfooding Assistant row)
- (id)initWithDeviceSession:(id)ds userSession:(id)us reliabilityLogging:(id)rl
                   navChain:(id)nc endpoint:(id)ep entryPoint:(NSInteger)entry
                      style:(NSInteger)style
 internalSettingsAvailabilityStatus:(NSInteger)status
       showInternalSettings:(BOOL)showInternal
 showLoggedOutInternalSettings:(BOOL)showLoggedOut
 showShakeToReportPreferenceToggle:(BOOL)showShake {
    SCI_LOG(@"orig(old): avail=%ld internal=%d loggedOut=%d -> forcing YES",
            (long)status, showInternal, showLoggedOut);
    return %orig(ds, us, rl, nc, ep, entry, style,
                 SCI_INTERNAL_AVAIL_STATUS, YES, YES, showShake);
}

%end
