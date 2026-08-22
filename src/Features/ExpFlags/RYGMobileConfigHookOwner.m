#import "RYGMobileConfig.h"
#import "../../Utils.h"

// RYGMobileConfig.xm already owns the ABI-validated FB/IG getter chain.  The
// historical persistence shim installed a second set of getter replacements,
// creating two competing ownership chains.  Persisted state only needs to arm
// the original owner before its Logos %ctor checks ryg_metaconfig_enabled.
//
// RYGMobileConfig.shared init is intentionally cheap here: it reads the tiny
// mc_overrides.plist/mc_notes.plist and activates exact persisted parameter IDs.
// It does NOT call -prepare, enumerate the MobileConfig descriptor table, resolve
// names, or involve the Runtime Browser.
__attribute__((constructor(101))) static void RYGArmPersistedMobileConfigOwner(void) {
    @autoreleasepool {
        RYGMobileConfig *mobileConfig = RYGMobileConfig.shared;
        if (mobileConfig.overrideCount == 0) return;
        if (![RYGUtils getBoolPref:@"ryg_metaconfig_enabled"]) {
            [RYGUtils setPref:@YES forKey:@"ryg_metaconfig_enabled"];
        }
    }
}
