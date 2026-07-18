#import "SCIInternalGatePrefs.h"
#import <Foundation/Foundation.h>
#import <objc/runtime.h>
#import <substrate.h>
#import <os/log.h>
#import <stdint.h>
#import <string.h>

#define EICLOG(fmt, ...) os_log(OS_LOG_DEFAULT, "[SCIGate] IdentityConsumers " fmt, ##__VA_ARGS__)

static BOOL sEICInstalled;

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

#pragma mark - Real dogfood feature getters

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

static BOOL (*origSmartSuggestionsDogfood)(id, SEL, id) = NULL;
static BOOL newSmartSuggestionsDogfood(id self, SEL _cmd, id context) {
    if (EICMasterOn()) return YES;
    return origSmartSuggestionsDogfood
        ? origSmartSuggestionsDogfood(self, _cmd, context)
        : NO;
}

#pragma mark - One-shot installation

static void EICHook(Class cls, NSString *selectorName, const char *encoding,
                    IMP replacement, IMP *original) {
    if (!cls || !selectorName.length || !replacement || !original || *original) return;
    SEL selector = NSSelectorFromString(selectorName);
    Method method = class_getInstanceMethod(cls, selector);
    if (!EICMethodMatches(method, encoding)) {
        if (method) {
            EICLOG("skip %{public}@.%{public}@ ABI=%{public}s",
                   NSStringFromClass(cls), selectorName,
                   method_getTypeEncoding(method));
        }
        return;
    }
    MSHookMessageEx(cls, selector, replacement, original);
}

void SCIEmployeeIdentityConsumerHooksInstall(void) {
    @synchronized (SCIInternalGatePrefs.class) {
        if (sEICInstalled) return;

        EICHook(NSClassFromString(@"IGFeedRequestQPLogger"),
            @"initWithShouldIncludeRequestId:instancesManager:persistentFailureTracker:isDeferredNppTapEnabled:isCacheLoadEnabled:isEmployee:isTestUser:",
            "@52@0:8B16@20@28B36B40B44B48",
            (IMP)newFeedQPInit, (IMP *)&origFeedQPInit);

        EICHook(NSClassFromString(@"IGSeenStateLogger"),
            @"initWithIsEmployee:analyticsLogger:",
            "@28@0:8B16@20",
            (IMP)newSeenLoggerInit, (IMP *)&origSeenLoggerInit);

        EICHook(NSClassFromString(@"IGSeenStateStore"),
            @"initWithDependencies:isEmployee:",
            "@28@0:8@16B24",
            (IMP)newSeenStoreInit, (IMP *)&origSeenStoreInit);

        EICHook(NSClassFromString(@"IGLeadGenAnalyticsLogger"),
            @"initWithAnalyticsLogger:userFbidV2:isEmployee:",
            "@36@0:8@16q24B32",
            (IMP)newLeadGenInit, (IMP *)&origLeadGenInit);

        EICHook(NSClassFromString(
            @"_TtC24BKBloksLabDeeplinkHelper24BKBloksLabDeeplinkHelper"),
            @"processDeeplinkWith:foaObjectSet:passPrototypeShortcode:useInternalNetworkCheck:isEmployee:session:containerConfigProvider:",
            "v60@0:8@16@24B32B36B40@44@?52",
            (IMP)newBloksLabProcess, (IMP *)&origBloksLabProcess);

        EICHook(NSClassFromString(
            @"_TtC17IGBugReportingKit32IGBugReportMenuReliabilityLogger"),
            @"markInternalSettingsEnabled:",
            "v20@0:8B16",
            (IMP)newMarkInternalEnabled, (IMP *)&origMarkInternalEnabled);

        EICHook(NSClassFromString(
            @"_TtC24IGIdentitySwitcherGating30IGIdentitySwitcherGatingHelper"),
            @"isFbAcquisitionEpDogfoodModeEnabled",
            "B16@0:8",
            (IMP)newIdentitySwitcherDogfood,
            (IMP *)&origIdentitySwitcherDogfood);

        EICHook(NSClassFromString(
            @"_TtC21IGSearchSerpMediaGrid41IGSearchSerpMediaGridRowSectionController"),
            @"showDogfoodFeedback",
            "B16@0:8",
            (IMP)newSearchDogfoodFeedback,
            (IMP *)&origSearchDogfoodFeedback);

        EICHook(NSClassFromString(
            @"_TtC46IGDirectSmartSuggestionsSuggestedActionHelpers46IGDirectSmartSuggestionsSuggestedActionHelpers"),
            @"directSmartSuggestionsIsForceBannerForDogfoodingEnabled:",
            "B24@0:8@16",
            (IMP)newSmartSuggestionsDogfood,
            (IMP *)&origSmartSuggestionsDogfood);

        sEICInstalled = YES;
        EICLOG("one-shot installer completed");
    }
}
