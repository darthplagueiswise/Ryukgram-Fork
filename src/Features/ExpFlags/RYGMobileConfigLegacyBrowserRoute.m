#import "RYGMobileConfigToolsViewController.h"
#import <Foundation/Foundation.h>
#import <objc/runtime.h>

// RYGMobileConfigNativeBrowser installs its persistence hooks at constructor
// priority 135 and also swaps the MobileConfig tools route so the "Open live
// MobileConfig browser" row points at the replacement browser. Keep the
// persistence hooks, but restore the original tools route immediately after it.
//
// The original RYGMobileConfigViewController remains the intended browser UI
// and already renders BOOL parameters with native UISwitch controls.
__attribute__((constructor(136))) static void RYGRestoreLegacyMobileConfigBrowserRoute(void) {
    @autoreleasepool {
        Class cls = RYGMobileConfigToolsViewController.class;
        SEL rebuildSelector = NSSelectorFromString(@"rebuildSections");
        SEL replacementSelector = NSSelectorFromString(@"ryg_nativeBrowser_rebuildSections");
        Method rebuildMethod = class_getInstanceMethod(cls, rebuildSelector);
        Method replacementMethod = class_getInstanceMethod(cls, replacementSelector);

        // Priority 135 exchanged these two implementations. Exchanging the same
        // pair once more restores the pre-redesign MobileConfig browser route.
        if (rebuildMethod && replacementMethod) {
            method_exchangeImplementations(rebuildMethod, replacementMethod);
        }
    }
}
