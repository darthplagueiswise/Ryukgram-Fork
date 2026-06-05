// ============================================================================
// SCIInternalSettingsMenuHook.x
// ============================================================================
// Makes IG's own "Internal Settings" entry appear inside the Bug Reporter menu
// (the shake-to-report menu that hosts AutofillInternalSettings,
// IGAutofillTokenizationInternalSettingsViewController, CLSurfaceConfigInternalSettings,
// IGReelsInternalSettings, NativeTwilightFFDBInternalSettings, ...).
//
// VALIDATED in the binary:
//   -[IGBugReportMenuViewController
//       initWithDeviceSession:userSession:reliabilityLogging:navChain:endpoint:
//       entryPoint:style:internalSettingsAvailabilityStatus:
//       showInternalSettings:showLoggedOutInternalSettings:
//       showShakeToReportPreferenceToggle:]            (imp 0x102bfdf9c)
//
// Disassembly shows the three trailing BOOLs are packed into a flags word
// (showInternalSettings -> bit 0x100) that drives row visibility, and the
// availabilityStatus enum is only forwarded, NOT compared to a constant here.
// => Forcing showInternalSettings = YES in the initializer surfaces the menu,
//    regardless of the server availability fragment. No status guessing needed.
//
// We pass through every other argument untouched (smallest possible change).

#import <Foundation/Foundation.h>
#import <objc/runtime.h>
#import <substrate.h>
#import <os/log.h>
#import "SCIInternalGatePrefs.h"

#define BLOG(fmt, ...) os_log(OS_LOG_DEFAULT, "[SCIGate] InternalMenu " fmt, ##__VA_ARGS__)
static inline BOOL ON(NSString *k){ return [SCIInternalGatePrefs objCGateEnabledForKey:k]; }
static NSString *const kForce  = @"sci_force_internal_settings_menu";
static NSString *const kLogged = @"sci_force_internal_settings_loggedout";

typedef id (*InitT)(id, SEL,
                    id, id, id, id, id, id,        // deviceSession..entryPoint
                    long, long,                    // style, internalSettingsAvailabilityStatus
                    BOOL, BOOL, BOOL);             // showInternalSettings, showLoggedOut, showShake
static InitT gOrig = NULL;
static SEL   gSel  = NULL;

static void installInternalSettingsMenuHook(void) {
    static BOOL done = NO; if (done) return;
    Class C = NSClassFromString(@"IGBugReporterMenu.IGBugReportMenuViewController");
    if (!C) C = NSClassFromString(@"IGBugReportMenuViewController");
    if (!C) C = NSClassFromString(@"_TtC17IGBugReporterMenu29IGBugReportMenuViewController");
    if (!C) return;
    gSel = NSSelectorFromString(@"initWithDeviceSession:userSession:reliabilityLogging:navChain:endpoint:entryPoint:style:internalSettingsAvailabilityStatus:showInternalSettings:showLoggedOutInternalSettings:showShakeToReportPreferenceToggle:");
    if (!class_getInstanceMethod(C, gSel)) return;

    IMP newImp = imp_implementationWithBlock(^id(id me,
            id deviceSession, id userSession, id reliabilityLogging, id navChain, id endpoint, id entryPoint,
            long style, long status,
            BOOL showInternal, BOOL showLoggedOut, BOOL showShake) {
        BOOL fi = showInternal, fl = showLoggedOut;
        if (ON(kForce)) {
            fi = YES;
            if (ON(kLogged)) fl = YES;
            BLOG("forcing showInternalSettings=YES (was %d), status=%ld", (int)showInternal, status);
        }
        if (!gOrig) return me;
        return gOrig(me, gSel, deviceSession, userSession, reliabilityLogging, navChain, endpoint, entryPoint,
                     style, status, fi, fl, showShake);
    });
    IMP orig = NULL; MSHookMessageEx(C, gSel, newImp, &orig); gOrig = (InitT)orig;
    done = YES; BLOG("hook installed: %{public}s", orig ? "OK" : "FAIL");
}

%ctor {
    @autoreleasepool {
        [SCIInternalGatePrefs installCrashGuardIfNeeded];
        installInternalSettingsMenuHook();
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW,(int64_t)(3.0*NSEC_PER_SEC)),dispatch_get_main_queue(),^{ installInternalSettingsMenuHook(); });
    }
}
