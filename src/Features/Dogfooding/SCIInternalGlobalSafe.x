// Consolidated new-IG internal/employee implementation.
// Kept as one Logos translation unit; split includes only avoid GitHub Contents
// API size/race issues while preserving exact compile order and static scope.

#include "SCIInternalGlobalSafeParts/part00.inc"
#include "SCIInternalGlobalSafeParts/part01.inc"
#include "SCIInternalGlobalSafeParts/part02.inc"
#include "SCIInternalGlobalSafeParts/part03.inc"
#include "SCIInternalGlobalSafeParts/part04.inc"

// Exact class/selector installation can legitimately run before Instagram has
// realised every target class. Retry a small, bounded number of times instead of
// registering a global dyld callback or scanning the runtime on every image load.
static void SCIInternalGlobalInstallAttempt(NSUInteger attempt) {
    if (!SCIInternalMenuOn() && !SCIEmployeeInternalMasterOn()) return;

    BOOL ready = SCIInstallInternalGlobalHooksIfNeeded();
    if (ready || attempt >= 5) return;

    static const NSTimeInterval delays[] = { 0.25, 0.75, 1.5, 3.0, 6.0 };
    NSTimeInterval delay = delays[MIN(attempt, (NSUInteger)4)];
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(delay * NSEC_PER_SEC)),
                   dispatch_get_main_queue(), ^{
        SCIInternalGlobalInstallAttempt(attempt + 1);
    });
}

void SCIRequestInternalGlobalHooksInstall(void) {
    dispatch_async(dispatch_get_main_queue(), ^{
        SCIInternalGlobalInstallAttempt(0);
    });
}

NSString *SCIInternalGlobalHookStatus(void) {
    NSUInteger mcCount = 0;
    mcCount += orig_MCGetBool != NULL;
    mcCount += orig_MCGetBoolDefault != NULL;
    mcCount += orig_MCGetBoolOptions != NULL;
    mcCount += orig_MCGetBoolOptionsDefault != NULL;
    mcCount += orig_MCGetBoolNoLog != NULL;
    mcCount += orig_MCGetBoolNoLogDefault != NULL;

    NSUInteger menuCount = 0;
    menuCount += orig_SafeBugMenuLegacy != NULL;
    menuCount += orig_SafeBugMenuCurrent != NULL;
    menuCount += orig_SafeBugMenuViewDidLoad != NULL;
    menuCount += orig_SafeBugMenuViewDidAppear != NULL;
    menuCount += orig_SafeBugMenuDidSelect != NULL;

    NSUInteger openerCount = 0;
    openerCount += orig_TryOpenNativeDogfoodSettings != NULL;
    openerCount += orig_OpenDogfoodingSettingsVC != NULL;
    openerCount += orig_OpenInstagramDebugMenu != NULL;

    return [NSString stringWithFormat:
        @"Employee master: %@\n"
         @"Internal menu: %@\n"
         @"MobileConfig employee readers: %lu/6\n"
         @"Bug Reporter hooks: %lu/5\n"
         @"Native opener bridges: %lu/3\n"
         @"XPlugins internal_only payload: %@\n"
         @"XPlugins Dogfooding payload: %@",
        SCIEmployeeInternalMasterOn() ? @"ON" : @"OFF",
        SCIInternalMenuOn() ? @"ON" : @"OFF",
        (unsigned long)mcCount,
        (unsigned long)menuCount,
        (unsigned long)openerCount,
        SCIInternalOnlyPayloadAvailable() ? @"available" : @"empty/unavailable",
        SCIDogfoodAssistantPayloadAvailable() ? @"available" : @"empty/unavailable"];
}

// Logos directives must live in the .x translation unit. The C preprocessor
// expands the .inc files only after Logos has parsed this file, so placing %ctor
// inside an included fragment would leave raw Logos syntax for clang.
%ctor {
    @autoreleasepool {
        SCIRequestInternalGlobalHooksInstall();
    }
}
