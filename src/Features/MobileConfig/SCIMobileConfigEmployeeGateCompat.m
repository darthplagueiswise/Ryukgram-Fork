#import <Foundation/Foundation.h>

void SCIInstallMobileConfigInternalUseGateIfNeeded(void);

// Kept for Tweak.x compatibility. The actual evaluator rebindings are already
// registered from SCIInternalUseGateHook's constructor; this call only refreshes
// the atomically cached preference and descriptor indices.
void SCIInstallMobileConfigEmployeeGateIfNeeded(void) {
	SCIInstallMobileConfigInternalUseGateIfNeeded();
}

__attribute__((constructor)) static void SCIObserveEmployeeGatePreferences(void) {
	@autoreleasepool {
		[[NSNotificationCenter defaultCenter]
			addObserverForName:NSUserDefaultsDidChangeNotification
			object:nil
			queue:nil
			usingBlock:^(__unused NSNotification *note) {
				SCIInstallMobileConfigInternalUseGateIfNeeded();
			}];
	}
}
