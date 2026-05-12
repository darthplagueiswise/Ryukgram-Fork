#import <Foundation/Foundation.h>
#import <objc/runtime.h>
#import <substrate.h>

// ─────────────────────────────────────────────────────────────────────────────
// SCIDirectNotesDogfoodingHooks.xm  (beta2)
//
// DESIGN RULE: No hook is installed at startup.
//
// The DirectNotes dogfooding path is:
//   User taps "Open Direct Notes Dogfood" in Developer Mode
//   → +[_TtC31IGDirectNotesDogfoodingSettings42IGDirectNotesDogfoodingSettingsStaticFuncs
//        notesDogfoodingSettingsOpenOnViewController:userSession:]
//   → Native dogfooding VC opens
//   → User makes a selection inside that VC
//   → VC calls internal commit/apply path (observed via hook below, installed
//     only AFTER the user explicitly triggers the flow)
//
// Diagnostic state (read by the Developer Mode menu to show truth):
//   sci.dn_dog.native_menu_opened    BOOL — was the VC opened at least once?
//   sci.dn_dog.selection_observed    BOOL — was a selection made?
//   sci.dn_dog.persist_confirmed     BOOL — was a persist/commit path observed?
//   sci.dn_dog.override_wired        BOOL — is a RyukGram override in place?
// ─────────────────────────────────────────────────────────────────────────────

static NSString * const kDNMenuOpened      = @"sci.dn_dog.native_menu_opened";
static NSString * const kDNSelectionObsrv  = @"sci.dn_dog.selection_observed";
static NSString * const kDNPersistConfirmd = @"sci.dn_dog.persist_confirmed";
static NSString * const kDNOverrideWired   = @"sci.dn_dog.override_wired";

// Resolved at runtime — not at constructor time.
static Class  gDNDogStaticFuncsClass  = nil;
static SEL    gDNDogOpenSel           = nil;

// ── C-exported entry points ───────────────────────────────────────────────────

#ifdef __cplusplus
extern "C" {
#endif

// Called by SCIDogfoodVCCacheNativeHooks when the user taps the menu button.
// This just records that the native VC was opened; the VC itself is opened by
// the caller via the confirmed selector.
void SCIInstallDirectNotesDogfoodingHooksWhenRequested(void) {
    NSUserDefaults *ud = [NSUserDefaults standardUserDefaults];
    [ud setBool:YES forKey:kDNMenuOpened];
    [ud synchronize];
    NSLog(@"[RyukGram][DNDogfood] native menu opened; recording state");

    // Mark override NOT wired (truth: we open the native VC only; no MC override
    // is applied by RyukGram in beta2).
    [ud setBool:NO forKey:kDNOverrideWired];
    [ud synchronize];
}

// Returns a dictionary with the current diagnostic state.
NSDictionary<NSString *, id> *SCIDirectNotesDogfoodingDiagnostics(void) {
    NSUserDefaults *ud = [NSUserDefaults standardUserDefaults];
    return @{
        @"native_menu_opened"   : @([ud boolForKey:kDNMenuOpened]),
        @"selection_observed"   : @([ud boolForKey:kDNSelectionObsrv]),
        @"persist_confirmed"    : @([ud boolForKey:kDNPersistConfirmd]),
        @"override_wired"       : @([ud boolForKey:kDNOverrideWired]),
        @"ryukgram_status"      : @"Native menu only — no MC override wired in beta2",
    };
}

#ifdef __cplusplus
}
#endif

// ── Constructor ───────────────────────────────────────────────────────────────
// Inert at startup: only resolves class/selector references so callers can
// verify them without triggering any hooks.
__attribute__((constructor))
static void RYDNDirectNotesDogfoodingInit(void) {
    @autoreleasepool {
        // Confirmed ✅ in Instagram arm64 binary:
        //   _TtC31IGDirectNotesDogfoodingSettings42IGDirectNotesDogfoodingSettingsStaticFuncs
        gDNDogStaticFuncsClass = NSClassFromString(
            @"_TtC31IGDirectNotesDogfoodingSettings42IGDirectNotesDogfoodingSettingsStaticFuncs");
        gDNDogOpenSel = NSSelectorFromString(
            @"notesDogfoodingSettingsOpenOnViewController:userSession:");

        BOOL classOK = gDNDogStaticFuncsClass != nil;
        BOOL selOK   = gDNDogStaticFuncsClass != nil &&
                       class_getClassMethod(gDNDogStaticFuncsClass, gDNDogOpenSel) != nil;

        NSLog(@"[RyukGram][DNDogfood] resolved: class=%@ sel=%@ classOK=%d selOK=%d",
              NSStringFromClass(gDNDogStaticFuncsClass),
              NSStringFromSelector(gDNDogOpenSel),
              classOK, selOK);
        // No hooks, no timers, no observers.
    }
}
