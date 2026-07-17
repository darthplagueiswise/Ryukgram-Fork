#import "SCIInternalGatePrefs.h"
#import <Foundation/Foundation.h>
#import <objc/runtime.h>
#import <substrate.h>
#import <os/log.h>
#import <stdint.h>
#import <string.h>

#define EICLOG(fmt, ...) os_log(OS_LOG_DEFAULT, "[SCIGate] IdentityConsumers " fmt, ##__VA_ARGS__)

static BOOL EICMasterOn(void) {
    return [SCIInternalGatePrefs employeeInternalMasterEnabled];
}

static BOOL EICMethodMatches(Method method, const char *expected) {
    if (!method || !expected) return NO;
    const char *actual = method_getTypeEncoding(method);
    return actual && strcmp(actual, expected) == 0;
}

#pragma mark - Actual employee/test-user consumers in this binary

static id (*origFeedQPInit)(id, SEL, BOOL, id, id, BOOL, BOOL, BOOL, BOOL) = NULL;
static id newFeedQPInit(id self, SEL _cmd,
                        BOOL shouldIncludeRequestId,
                        id instancesManager,
                        id persistentFailureTracker,
                        BOOL deferredNppTap,
                        BOOL cacheLoad,
                        BOOL isEmployee,
                        BOOL isTestUser) {
    if (EICMasterOn()) {
        isEmployee = YES;
        isTestUser = YES;
    }
    return origFeedQPInit
        ? origFeedQPInit(self, _cmd, shouldIncludeRequestId,
            instancesManager, persistentFailureTracker, deferredNppTap,
            cacheLoad, isEmployee, isTestUser)
        : nil;
}

static id (*origSeenLoggerInit)(id, SEL, BOOL, id) = NULL;
static id newSeenLoggerInit(id self, SEL _cmd, BOOL isEmployee,
                            id analyticsLogger) {
    return origSeenLoggerInit
        ? origSeenLoggerInit(self, _cmd,
            EICMasterOn() ? YES : isEmployee, analyticsLogger)
        : nil;
}

static id (*origSeenStoreInit)(id, SEL, id, BOOL) = NULL;
static id newSeenStoreInit(id self, SEL _cmd, id dependencies,
                           BOOL isEmployee) {
    return origSeenStoreInit
        ? origSeenStoreInit(self, _cmd, dependencies,
            EICMasterOn() ? YES : isEmployee)
        : nil;
}

static id (*origLeadGenInit)(id, SEL, id, int64_t, BOOL) = NULL;
static id newLeadGenInit(id self, SEL _cmd, id analyticsLogger,
                         int64_t userFbidV2, BOOL isEmployee) {
    return origLeadGenInit
        ? origLeadGenInit(self, _cmd, analyticsLogger, userFbidV2,
            EICMasterOn() ? YES : isEmployee)
        : nil;
}

// This selector is a class method on the Swift helper metaclass.
static void (*origBloksLabProcess)(id, SEL, id, id, BOOL, BOOL, BOOL, id, id) = NULL;
static void newBloksLabProcess(id self, SEL _cmd,
                               id deeplink,
                               id foaObjectSet,
                               BOOL passPrototypeShortcode,
                               BOOL useInternalNetworkCheck,
                               BOOL isEmployee,
                               id session,
                               id containerConfigProvider) {
    if (origBloksLabProcess) {
        origBloksLabProcess(self, _cmd, deeplink, foaObjectSet,
            passPrototypeShortcode, useInternalNetworkCheck,
            EICMasterOn() ? YES : isEmployee,
            session, containerConfigProvider);
    }
}

static void (*origMarkInternalEnabled)(id, SEL, BOOL) = NULL;
static void newMarkInternalEnabled(id self, SEL _cmd, BOOL enabled) {
    if (origMarkInternalEnabled) {
        origMarkInternalEnabled(self, _cmd, EICMasterOn() ? YES : enabled);
    }
}

#pragma mark - Real employee and dogfood feature getters

static BOOL (*origIdentitySwitcherDogfood)(id, SEL) = NULL;
static BOOL newIdentitySwitcherDogfood(id self, SEL _cmd) {
    if (EICMasterOn()) return YES;
    return origIdentitySwitcherDogfood
        ? origIdentitySwitcherDogfood(self, _cmd)
        : NO;
}

static BOOL (*origSearchDogfoodFeedback)(id, SEL) = NULL;
static BOOL newSearchDogfoodFeedback(id self, SEL _cmd) {
    if (EICMasterOn()) return YES;
    return origSearchDogfoodFeedback
        ? origSearchDogfoodFeedback(self, _cmd)
        : NO;
}

// This selector is also a class method on the Swift helper metaclass.
static BOOL (*origSmartSuggestionsDogfood)(id, SEL, id) = NULL;
static BOOL newSmartSuggestionsDogfood(id self, SEL _cmd, id context) {
    if (EICMasterOn()) return YES;
    return origSmartSuggestionsDogfood
        ? origSmartSuggestionsDogfood(self, _cmd, context)
        : NO;
}

static BOOL (*origForceRestoreRecentsForEmployee)(id, SEL) = NULL;
static BOOL newForceRestoreRecentsForEmployee(id self, SEL _cmd) {
    if (EICMasterOn()) return YES;
    return origForceRestoreRecentsForEmployee
        ? origForceRestoreRecentsForEmployee(self, _cmd)
        : NO;
}

static void (*origSetForceRestoreRecentsForEmployee)(id, SEL, BOOL) = NULL;
static void newSetForceRestoreRecentsForEmployee(id self, SEL _cmd, BOOL value) {
    if (origSetForceRestoreRecentsForEmployee) {
        origSetForceRestoreRecentsForEmployee(self, _cmd,
            EICMasterOn() ? YES : value);
    }
}

#pragma mark - Installation

static void EICHookInstance(Class cls, NSString *selectorName,
                            const char *encoding,
                            IMP replacement, IMP *original) {
    if (!cls || !selectorName.length || !replacement || !original || *original) return;
    SEL selector = NSSelectorFromString(selectorName);
    Method method = class_getInstanceMethod(cls, selector);
    if (!EICMethodMatches(method, encoding)) {
        if (method) {
            EICLOG("skip instance %{public}@.%{public}@ ABI=%{public}s",
                   NSStringFromClass(cls), selectorName,
                   method_getTypeEncoding(method));
        }
        return;
    }
    MSHookMessageEx(cls, selector, replacement, original);
}

static void EICHookClass(Class cls, NSString *selectorName,
                         const char *encoding,
                         IMP replacement, IMP *original) {
    if (!cls || !selectorName.length || !replacement || !original || *original) return;
    SEL selector = NSSelectorFromString(selectorName);
    Method method = class_getClassMethod(cls, selector);
    if (!EICMethodMatches(method, encoding)) {
        if (method) {
            EICLOG("skip class %{public}@.%{public}@ ABI=%{public}s",
                   NSStringFromClass(cls), selectorName,
                   method_getTypeEncoding(method));
        }
        return;
    }
    Class meta = object_getClass(cls);
    if (!meta) return;
    MSHookMessageEx(meta, selector, replacement, original);
}

static void EICInstall(void) {
    @synchronized (SCIInternalGatePrefs.class) {
        EICHookInstance(NSClassFromString(@"IGFeedRequestQPLogger"),
            @"initWithShouldIncludeRequestId:instancesManager:persistentFailureTracker:isDeferredNppTapEnabled:isCacheLoadEnabled:isEmployee:isTestUser:",
            "@52@0:8B16@20@28B36B40B44B48",
            (IMP)newFeedQPInit, (IMP *)&origFeedQPInit);

        EICHookInstance(NSClassFromString(@"IGSeenStateLogger"),
            @"initWithIsEmployee:analyticsLogger:",
            "@28@0:8B16@20",
            (IMP)newSeenLoggerInit, (IMP *)&origSeenLoggerInit);

        EICHookInstance(NSClassFromString(@"IGSeenStateStore"),
            @"initWithDependencies:isEmployee:",
            "@28@0:8@16B24",
            (IMP)newSeenStoreInit, (IMP *)&origSeenStoreInit);

        EICHookInstance(NSClassFromString(@"IGLeadGenAnalyticsLogger"),
            @"initWithAnalyticsLogger:userFbidV2:isEmployee:",
            "@36@0:8@16q24B32",
            (IMP)newLeadGenInit, (IMP *)&origLeadGenInit);

        EICHookClass(NSClassFromString(
            @"_TtC24BKBloksLabDeeplinkHelper24BKBloksLabDeeplinkHelper"),
            @"processDeeplinkWith:foaObjectSet:passPrototypeShortcode:useInternalNetworkCheck:isEmployee:session:containerConfigProvider:",
            "v60@0:8@16@24B32B36B40@44@?52",
            (IMP)newBloksLabProcess, (IMP *)&origBloksLabProcess);

        EICHookInstance(NSClassFromString(
            @"_TtC17IGBugReportingKit32IGBugReportMenuReliabilityLogger"),
            @"markInternalSettingsEnabled:",
            "v20@0:8B16",
            (IMP)newMarkInternalEnabled, (IMP *)&origMarkInternalEnabled);

        EICHookInstance(NSClassFromString(
            @"_TtC24IGIdentitySwitcherGating30IGIdentitySwitcherGatingHelper"),
            @"isFbAcquisitionEpDogfoodModeEnabled",
            "B16@0:8",
            (IMP)newIdentitySwitcherDogfood,
            (IMP *)&origIdentitySwitcherDogfood);

        EICHookInstance(NSClassFromString(
            @"_TtC21IGSearchSerpMediaGrid41IGSearchSerpMediaGridRowSectionController"),
            @"showDogfoodFeedback",
            "B16@0:8",
            (IMP)newSearchDogfoodFeedback,
            (IMP *)&origSearchDogfoodFeedback);

        EICHookClass(NSClassFromString(
            @"_TtC46IGDirectSmartSuggestionsSuggestedActionHelpers46IGDirectSmartSuggestionsSuggestedActionHelpers"),
            @"directSmartSuggestionsIsForceBannerForDogfoodingEnabled:",
            "B24@0:8@16",
            (IMP)newSmartSuggestionsDogfood,
            (IMP *)&origSmartSuggestionsDogfood);

        Class recentStore = NSClassFromString(
            @"_TtC20IGRecentSearchStores36IGBlendedSearchRecentItemsOrderStore");
        EICHookInstance(recentStore,
            @"shouldAttemptToForceRestoreRecentsForEmployee",
            "B16@0:8",
            (IMP)newForceRestoreRecentsForEmployee,
            (IMP *)&origForceRestoreRecentsForEmployee);
        EICHookInstance(recentStore,
            @"setShouldAttemptToForceRestoreRecentsForEmployee:",
            "v20@0:8B16",
            (IMP)newSetForceRestoreRecentsForEmployee,
            (IMP *)&origSetForceRestoreRecentsForEmployee);
    }
}

void SCIInstallEmployeeIdentityConsumerHooks(void) {
    // One exact installation pass. The centralized bootstrap performs one
    // post-launch retry instead of registering a callback for every dyld image.
    EICInstall();
}
