#import "../Gating/SCICRuntimePatchResolver.h"
#import <Foundation/Foundation.h>
#import <objc/runtime.h>
#import <substrate.h>
#import <os/log.h>

#define DATASAFELOG(fmt, ...) os_log(OS_LOG_DEFAULT, "[SCIGate] DataPatchSafety " fmt, ##__VA_ARGS__)

static BOOL SCIIsMutableDataSection(NSString *section) {
    NSString *value = [section stringByTrimmingCharactersInSet:
        NSCharacterSet.whitespaceAndNewlineCharacterSet] ?: @"";
    // __DATA_CONST and every __TEXT section are deliberately excluded.
    return [value hasPrefix:@"__DATA,"] || [value hasPrefix:@"__DATA_DIRTY,"];
}

static void SCISanitizeDataPatchPlan(SCICRuntimePatchPlan *plan) {
    if (!plan || plan.strategy != SCICRuntimePatchStrategyDataPatchBytes ||
        SCIIsMutableDataSection(plan.section)) return;

    NSString *section = plan.section.length ? plan.section : @"unknown section";
    plan.strategy = SCICRuntimePatchStrategyNone;
    plan.strategyName = @"none (read-only Mach-O data)";
    plan.shortStrategyName = @"resolve only";
    plan.reason = [NSString stringWithFormat:
        @"%@ is not mutable __DATA/__DATA_DIRTY. Resolve and hook the typed consumer/reader instead.",
        section];
    plan.inlineToggleSafe = NO;
    plan.safeAtLaunch = NO;
    plan.requiresPromptValue = NO;
    plan.requiresConfirmedConsumer = YES;
}

static SCICRuntimePatchPlan *(*origResolvePlan)(id, SEL, NSDictionary *, NSArray *) = NULL;
static SCICRuntimePatchPlan *SCIResolvePlan(id self, SEL _cmd,
                                            NSDictionary *entryInfo,
                                            NSArray *xrefHits) {
    SCICRuntimePatchPlan *plan = origResolvePlan
        ? origResolvePlan(self, _cmd, entryInfo, xrefHits)
        : nil;
    SCISanitizeDataPatchPlan(plan);
    return plan;
}

static BOOL (*origApplyPlan)(id, SEL, SCICRuntimePatchPlan *, id, NSError **) = NULL;
static BOOL SCIApplyPlan(id self, SEL _cmd, SCICRuntimePatchPlan *plan,
                         id value, NSError **error) {
    if (plan.strategy == SCICRuntimePatchStrategyDataPatchBytes &&
        !SCIIsMutableDataSection(plan.section)) {
        if (error) {
            *error = [NSError errorWithDomain:@"SCICRuntimePatchResolver"
                                         code:31
                                     userInfo:@{NSLocalizedDescriptionKey:
                [NSString stringWithFormat:
                    @"Refused byte patch in read-only/constant section %@.",
                    plan.section ?: @"unknown"]}];
        }
        return NO;
    }
    return origApplyPlan ? origApplyPlan(self, _cmd, plan, value, error) : NO;
}

static void SCIScrubUnsafePersistedPlans(void) {
    NSDictionary *plans = [SCICRuntimePatchResolver persistedPatchPlans];
    for (NSString *symbol in plans.allKeys.copy) {
        NSDictionary *entry = plans[symbol];
        NSString *strategy = [entry[@"strategy"] isKindOfClass:NSString.class]
            ? entry[@"strategy"] : @"";
        NSString *section = [entry[@"section"] isKindOfClass:NSString.class]
            ? entry[@"section"] : @"";
        if ([strategy isEqualToString:@"data.patch.bytes"] &&
            !SCIIsMutableDataSection(section)) {
            [SCICRuntimePatchResolver forgetPatchPlanForSymbol:symbol];
            DATASAFELOG("removed persisted plan %{public}@ (%{public}@)", symbol, section);
        }
    }
}

static void (*origReinstallPlans)(id, SEL) = NULL;
static void SCIReinstallPlans(id self, SEL _cmd) {
    SCIScrubUnsafePersistedPlans();
    if (origReinstallPlans) origReinstallPlans(self, _cmd);
}

static BOOL SCIHookClassMethod(Class cls, NSString *name,
                               IMP replacement, IMP *original) {
    if (!cls || !name.length || !replacement || !original) return NO;
    SEL selector = NSSelectorFromString(name);
    if (!class_getClassMethod(cls, selector)) return NO;
    MSHookMessageEx(object_getClass(cls), selector, replacement, original);
    return *original != NULL;
}

__attribute__((constructor))
static void SCIRuntimeDataPatchSafetyCtor(void) {
    @autoreleasepool {
        BOOL resolve = SCIHookClassMethod(SCICRuntimePatchResolver.class,
            @"resolvePlanForEntryInfo:xrefHits:", (IMP)SCIResolvePlan,
            (IMP *)&origResolvePlan);
        BOOL apply = SCIHookClassMethod(SCICRuntimePatchResolver.class,
            @"applyPlan:value:error:", (IMP)SCIApplyPlan,
            (IMP *)&origApplyPlan);
        BOOL reinstall = SCIHookClassMethod(SCICRuntimePatchResolver.class,
            @"reinstallSafePersistedPatchPlansAtLaunch", (IMP)SCIReinstallPlans,
            (IMP *)&origReinstallPlans);
        SCIScrubUnsafePersistedPlans();
        DATASAFELOG("installed resolve=%d apply=%d reinstall=%d",
                    resolve, apply, reinstall);
    }
}
