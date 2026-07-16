#import "../../Utils.h"

void SCIInstallInternalDevMenuHooksIfNeeded(void);
static BOOL SCIDevMenuOn(void) { return [SCIUtils getBoolPref:@"sci_force_rct_dev_menu"]; }
static BOOL sSCIDevMenuInstalled = NO;

%group SCIInternalDevMenuGroup
%hook RCTDevMenu
- (BOOL)devMenuEnabled { return SCIDevMenuOn() ? YES : %orig; }
- (BOOL)shakeToShow { return SCIDevMenuOn() ? YES : %orig; }
- (BOOL)hotLoadingEnabled { return SCIDevMenuOn() ? YES : %orig; }
- (BOOL)hotkeysEnabled { return SCIDevMenuOn() ? YES : %orig; }
- (BOOL)keyboardShortcutsEnabled { return SCIDevMenuOn() ? YES : %orig; }
%end
%end

void SCIInstallInternalDevMenuHooksIfNeeded(void) {
	if (sSCIDevMenuInstalled || !SCIDevMenuOn()) return;
	sSCIDevMenuInstalled = YES;
	%init(SCIInternalDevMenuGroup);
}

%ctor { @autoreleasepool { SCIInstallInternalDevMenuHooksIfNeeded(); } }
