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

#define ELOG(fmt, ...) os_log(OS_LOG_DEFAULT, "[SCIGate] IGPlusElig " fmt, ##__VA_ARGS__)
static inline BOOL ON(NSString *k){ return [SCIInternalGatePrefs objCGateEnabledForKey:@"sci_force_igplus_all"] || [SCIInternalGatePrefs objCGateEnabledForKey:k]; }

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

    forceYES(@"_TtC23SUBSBenefitDataProvider23SUBSBenefitDataProvider", @"isBenefitActiveWithBenefitType:", YES);

    NSString *peek = @"_TtC34IGConsumerSubsStoryPeekEligibility34IGConsumerSubsStoryPeekEligibility";
    forceYES(peek, @"isPeekEligibleForEntryPoint:viewModelType:consumerSubsService:launcherSet:", NO);
    forceYES(peek, @"isUpsellPeekEligibleForEntryPoint:viewModelType:consumerSubsService:launcherSet:", NO);
    forceYES(peek, @"isAnyPeekEligibleForEntryPoint:viewModelType:consumerSubsService:launcherSet:", NO);

    forceYES(@"_TtC29IGConsumerSubsDirectChatPeeks39IGConsumerSubsDirectChatPeekEligibility",
             @"isChatPeekFeatureEligibleWithLauncherSet:consumerSubsService:", NO);

    forceYES(@"_TtC27IGConsumerSubsCustomAppIcon33IGConsumerSubsCustomAppIconHelper",
             @"isCustomAppIconAvailableWithUserSession:", NO);
}

%ctor {
    @autoreleasepool {
        [SCIInternalGatePrefs installCrashGuardIfNeeded];
        install();
        double d[] = {2.0, 5.0};
        for (NSUInteger i=0;i<sizeof(d)/sizeof(d[0]);i++)
            dispatch_after(dispatch_time(DISPATCH_TIME_NOW,(int64_t)(d[i]*NSEC_PER_SEC)),dispatch_get_main_queue(),^{ install(); });
        [SCIInternalSettingsApplier scheduleAutoApplyIfEnabled];
    }
}
