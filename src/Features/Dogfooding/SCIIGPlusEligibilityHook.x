// ============================================================================
// SCIIGPlusEligibilityHook.x
// ============================================================================
// Lower-level IGPlus eligibility/data-provider forcing.

#import <Foundation/Foundation.h>
#import <objc/runtime.h>
#import <substrate.h>
#import <os/log.h>
#import "SCIInternalGatePrefs.h"
#import "SCIInternalSettingsApplier.h"
#import "SCIDogfoodObjectRuntime.h"

#define ELOG(fmt, ...) os_log(OS_LOG_DEFAULT, "[SCIGate] IGPlusElig " fmt, ##__VA_ARGS__)
static inline BOOL ON(NSString *k){ return [SCIInternalGatePrefs individualGateEnabledForKey:@"sci_force_igplus_all"] || [SCIInternalGatePrefs individualGateEnabledForKey:k]; }
static NSMutableSet<NSString *> *gDone;

static Class SCIClassByNames(NSArray<NSString *> *names) {
    for (NSString *n in names) { if (!n.length) continue; Class c = NSClassFromString(n); if (c) return c; c = objc_getClass(n.UTF8String); if (c) return c; }
    unsigned int count = 0; Class *classes = objc_copyClassList(&count); Class found = Nil;
    for (unsigned int i=0; classes && i<count && !found; i++) { const char *cn = class_getName(classes[i]); if (!cn) continue; NSString *s = [NSString stringWithUTF8String:cn]; for (NSString *n in names) if ([s isEqualToString:n] || [s hasSuffix:n] || [s containsString:n]) { found = classes[i]; break; } }
    if (classes) free(classes); return found;
}

static void forceYES(NSArray<NSString *> *names, NSString *selName, BOOL instance) {
    Class cls = SCIClassByNames(names);
    if (!cls) { [SCIDogfoodObjectRuntime noteAction:@"IGPlus eligibility hook" status:@"class not loaded" detail:names.firstObject ?: @""]; return; }
    Class target = instance ? cls : object_getClass(cls);
    SEL sel = NSSelectorFromString(selName);
    Method m = instance ? class_getInstanceMethod(cls, sel) : class_getClassMethod(cls, sel);
    if (!m) { [SCIDogfoodObjectRuntime noteAction:@"IGPlus eligibility hook" status:@"selector missing" detail:[NSString stringWithFormat:@"%s#%@", class_getName(cls), selName]]; return; }
    NSString *tag = [NSString stringWithFormat:@"%@%s#%@", instance?@"-":@"+", class_getName(cls), selName];
    if ([gDone containsObject:tag]) return;
    IMP newImp = imp_implementationWithBlock(^BOOL(__unused id self){ return YES; });
    IMP orig = NULL; MSHookMessageEx(target, sel, newImp, &orig);
    [gDone addObject:tag];
    ELOG("%{public}@ -> YES (%{public}s)", tag, orig ? "ok" : "noorig");
    [SCIDogfoodObjectRuntime noteAction:@"IGPlus eligibility hook" status:(orig?@"hooked":@"failed") detail:tag];
}

static void install(void) {
    if (!gDone) gDone = [NSMutableSet set];
    if (!ON(@"sci_igplus_eligibility") && !ON(@"sci_force_igplus_all")) return;
    forceYES(@[@"_TtC23SUBSBenefitDataProvider23SUBSBenefitDataProvider", @"SUBSBenefitDataProvider.SUBSBenefitDataProvider", @"SUBSBenefitDataProvider"], @"isBenefitActiveWithBenefitType:", YES);
    forceYES(@[@"_TtC34IGConsumerSubsStoryPeekEligibility34IGConsumerSubsStoryPeekEligibility", @"IGConsumerSubsStoryPeekEligibility.IGConsumerSubsStoryPeekEligibility", @"IGConsumerSubsStoryPeekEligibility"], @"isPeekEligibleForEntryPoint:viewModelType:consumerSubsService:launcherSet:", NO);
    forceYES(@[@"_TtC34IGConsumerSubsStoryPeekEligibility34IGConsumerSubsStoryPeekEligibility", @"IGConsumerSubsStoryPeekEligibility.IGConsumerSubsStoryPeekEligibility", @"IGConsumerSubsStoryPeekEligibility"], @"isUpsellPeekEligibleForEntryPoint:viewModelType:consumerSubsService:launcherSet:", NO);
    forceYES(@[@"_TtC34IGConsumerSubsStoryPeekEligibility34IGConsumerSubsStoryPeekEligibility", @"IGConsumerSubsStoryPeekEligibility.IGConsumerSubsStoryPeekEligibility", @"IGConsumerSubsStoryPeekEligibility"], @"isAnyPeekEligibleForEntryPoint:viewModelType:consumerSubsService:launcherSet:", NO);
    forceYES(@[@"_TtC29IGConsumerSubsDirectChatPeeks39IGConsumerSubsDirectChatPeekEligibility", @"IGConsumerSubsDirectChatPeeks.IGConsumerSubsDirectChatPeekEligibility", @"IGConsumerSubsDirectChatPeekEligibility"], @"isChatPeekFeatureEligibleWithLauncherSet:consumerSubsService:", NO);
    forceYES(@[@"_TtC27IGConsumerSubsCustomAppIcon33IGConsumerSubsCustomAppIconHelper", @"IGConsumerSubsCustomAppIcon.IGConsumerSubsCustomAppIconHelper", @"IGConsumerSubsCustomAppIconHelper"], @"isCustomAppIconAvailableWithUserSession:", NO);
}

%ctor {
    @autoreleasepool {
        [SCIInternalGatePrefs installCrashGuardIfNeeded];
        install();
        double d[] = {1.0, 3.0, 6.0, 10.0};
        for (NSUInteger i=0;i<sizeof(d)/sizeof(d[0]);i++) dispatch_after(dispatch_time(DISPATCH_TIME_NOW,(int64_t)(d[i]*NSEC_PER_SEC)),dispatch_get_main_queue(),^{ install(); });
        [SCIInternalSettingsApplier scheduleAutoApplyIfEnabled];
    }
}
