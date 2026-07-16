#import "../../Utils.h"

void SCIInstallInternalDevMenuHooksIfNeeded(void);
static BOOL SCIDevMenuOn(void) { return [SCIUtils getBoolPref:@"sci_force_rct_dev_menu"]; }
static BOOL sSCIDevMenuInstalled = NO;

%group SCIInternalDevMenuGroup
%hook RCTDevMenu
- (BOOL)devMenuEnabled {
	if (SCIDevMenuOn()) return YES;
	return %orig;
}
- (BOOL)shakeToShow {
	if (SCIDevMenuOn()) return YES;
	return %orig;
}
- (BOOL)hotLoadingEnabled {
	if (SCIDevMenuOn()) return YES;
	return %orig;
}
- (BOOL)hotkeysEnabled {
	if (SCIDevMenuOn()) return YES;
	return %orig;
}
- (BOOL)keyboardShortcutsEnabled {
	if (SCIDevMenuOn()) return YES;
	return %orig;
}
%end
%end

void SCIInstallInternalDevMenuHooksIfNeeded(void) {
	if (sSCIDevMenuInstalled || !SCIDevMenuOn()) return;
	sSCIDevMenuInstalled = YES;
	%init(SCIInternalDevMenuGroup);
}

%ctor {
	@autoreleasepool {
		SCIInstallInternalDevMenuHooksIfNeeded();
	}
}
