// ============================================================================
// SCIIGPlusEligibilityHook.x
// ============================================================================
// Lower-level IGPlus eligibility/data-provider forcing, validated against the
// live binary (igconsumer_validation_report.md). These sit UNDER the benefit
// getters and are consulted by several IGConsumer paths:
//   - SUBSBenefitDataProvider.isBenefitActiveWithBenefitType:        (instance B@:@)
//   - IGConsumerSubsStoryPeekEligibility.is{,Upsell,Any}PeekEligible…(CLASS methods)
//   - IGConsumerSubsDirectChatPeekEligibility.isChatPeekFeatureEligible…(CLASS)
//   - IGConsumerSubsCustomAppIconHelper.isCustomAppIconAvailableWithUserSession:(CLASS)
//
// All return BOOL. We force YES. Because several take multiple args, we use
// INSTALL-TIME gating: the hook is only installed when the pref is ON at launch
// (settings mark requiresRestart), so the forced block can simply return YES and
// never needs to trampoline the original with its argument list.
//
// Named classes only, hooked at %ctor (+cheap retries). No scanning.

#import <Foundation/Foundation.h>
#import <objc/runtime.h>
#import <substrate.h>
#import <os/log.h>
#import "SCIInternalGatePrefs.h"
#import "SCIInternalSettingsApplier.h"
#import "SCIInstallOnce.h"

#define ELOG(fmt, ...) os_log(OS_LOG_DEFAULT, "[SCIGate] IGPlusElig " fmt, ##__VA_ARGS__)
static inline BOOL ON(NSString *k){ return [SCIInternalGatePrefs individualGateEnabledForKey:@"sci_force_igplus_all"] || [SCIInternalGatePrefs individualGateEnabledForKey:k]; }

static NSMutableSet<NSString *> *gDone;

// Force a BOOL-returning method to YES. instance==NO -> hook the class method (metaclass).
static void forceYES(NSString *clsName, NSString *selName, BOOL instance) {
    Class cls = NSClassFromString(clsName);
    if (!cls) return;
    Class target = instance ? cls : object_getClass(cls); // metaclass for class methods
    SEL sel = NSSelectorFromString(selName);
    Method m = instance ? class_getInstanceMethod(cls, sel) : class_getClassMethod(cls, sel);
    if (!m) return;
    NSString *tag = [NSString stringWithFormat:@"%@%@#%@", instance?@"-":@"+", clsName, selName];
    if ([gDone containsObject:tag]) return;
    IMP newImp = imp_implementationWithBlock(^BOOL(__unused id self){ return YES; }); // extra args ignored
    IMP orig = NULL; MSHookMessageEx(target, sel, newImp, &orig);
    [gDone addObject:tag]; ELOG("%{public}@ -> YES (%{public}s)", tag, orig?"ok":"noorig");
}

static void install(void) {
    if (!gDone) gDone = [NSMutableSet set];
    if (!ON(@"sci_igplus_eligibility")) return; // install-time gate (master also flips this via ON())

    forceYES(@"_TtC23SUBSBenefitDataProvider23SUBSBenefitDataProvider", @"isBenefitActiveWithBenefitType:", YES); // INSTANCE — confirmado B24@0:8@16

    // SCI-FIX 2026-07-11: os 4 abaixo estavam com instance=YES (BUG REAL — nunca
    // corrigido pelas sessões anteriores). Verificado contra Instagram 433.0.283:
    // esses 4 seletores SÓ existem como método de CLASSE (metaclasse), não de
    // instância. Com instance=YES, class_getInstanceMethod() retornava nil e
    // forceYES() saía sem instalar nada — 4 dos 6 hooks de IGPlus Eligibility
    // eram no-op silencioso desde sempre. Trocado para instance=NO (hookeia a
    // metaclasse via object_getClass, como o helper já suporta).
    NSString *peek = @"_TtC34IGConsumerSubsStoryPeekEligibility34IGConsumerSubsStoryPeekEligibility";
    forceYES(peek, @"isPeekEligibleForEntryPoint:viewModelType:consumerSubsService:launcherSet:", NO); // CLASS: B48@0:8q16q24@32@40
    forceYES(peek, @"isUpsellPeekEligibleForEntryPoint:viewModelType:consumerSubsService:launcherSet:", NO); // CLASS
    forceYES(peek, @"isAnyPeekEligibleForEntryPoint:viewModelType:consumerSubsService:launcherSet:", NO); // CLASS

    NSString *chatPeek = @"_TtC29IGConsumerSubsDirectChatPeeks39IGConsumerSubsDirectChatPeekEligibility";
    forceYES(chatPeek, @"isChatPeekFeatureEligibleWithLauncherSet:consumerSubsService:", NO); // CLASS: B32@0:8@16@24
    // SCI-FIX 2026-07-11: bônus — 2 seletores da mesma classe que faziam falta e
    // cobrem a mesma superfície de Direct Chat Peek (também CLASS methods, confirmados):
    forceYES(chatPeek, @"isUpsellEligibleWithLauncherSet:consumerSubsService:", NO); // CLASS: B32@0:8@16@24
    forceYES(chatPeek, @"isThreadEligibleForPreview:", NO); // CLASS: B24@0:8@16

    forceYES(@"_TtC27IGConsumerSubsCustomAppIcon33IGConsumerSubsCustomAppIconHelper",
             @"isCustomAppIconAvailableWithUserSession:", NO); // CLASS: B24@0:8@16
}

%ctor {
    @autoreleasepool {
        [SCIInternalGatePrefs installCrashGuardIfNeeded];
        // SCI-FIX 2026-06-11: single deterministic install at DidBecomeActive,
        // replacing static-init install() + 2s/5s dispatch_after ladder.
        SCIInstallOnceOnActive(^{ install(); });
        [SCIInternalSettingsApplier scheduleAutoApplyIfEnabled];
    }
}
