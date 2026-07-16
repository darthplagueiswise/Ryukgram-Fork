#import "../../Utils.h"
#import <objc/runtime.h>
#import <substrate.h>
#import <os/log.h>
#import <string.h>

#define DGFLOG(fmt, ...) os_log(OS_LOG_DEFAULT, "[SCIGate] GraphQLDogfoodForce " fmt, ##__VA_ARGS__)

void SCIInstallGraphQLDogfoodQueryBridgeIfNeeded(void);

static volatile BOOL sDGForceEnabled = NO;

void SCIRefreshGraphQLDogfoodForceEnabled(void) {
    sDGForceEnabled = [SCIUtils getBoolPref:@"sci_employee_internal"];
}

static inline BOOL DGForceOn(void) {
    return sDGForceEnabled;
}

BOOL SCIIsGraphQLDogfoodForceEnabled(void) {
    return DGForceOn();
}

%group SCIGraphQLDogfoodLocalDecisionGroup

%hook IGBaseUser

- (id)asIGDogfoodingFirstShowIssueFragmentImmutableModel {
    if (DGForceOn()) return nil;
    return %orig;
}

%end
%end

static id (*orig_DGExactEligibilityStatus)(id, SEL) = NULL;
static void (*orig_DGWarningExpiration)(id, SEL, id) = NULL;

static id DGExactEligibilityStatus(id self, SEL _cmd) {
    if (DGForceOn()) return @YES;
    return orig_DGExactEligibilityStatus
        ? orig_DGExactEligibilityStatus(self, _cmd)
        : nil;
}

static void DGWarningExpiration(id self, SEL _cmd, id user) {
    if (DGForceOn()) return;
    if (orig_DGWarningExpiration) {
        orig_DGWarningExpiration(self, _cmd, user);
    }
}

static NSString *DGNormalizedEncoding(const char *encoding) {
    if (!encoding) return @"";
    NSMutableString *out = [NSMutableString string];
    const char *p = encoding;
    while (*p) {
        if (*p != '@') {
            [out appendFormat:@"%c", *p++];
            continue;
        }
        [out appendString:@"@"];
        p++;
        if (*p == '"') {
            p++;
            while (*p && *p != '"') p++;
            if (*p == '"') p++;
        } else if (*p == '?') {
            [out appendString:@"?"];
            p++;
            if (*p == '<') {
                NSInteger depth = 0;
                do {
                    if (*p == '<') depth++;
                    else if (*p == '>') depth--;
                    p++;
                } while (*p && depth > 0);
            }
        }
    }
    return out;
}

static BOOL DGMethodMatches(Method method, const char *expected) {
    if (!method || !expected) return NO;
    return [DGNormalizedEncoding(method_getTypeEncoding(method))
        isEqualToString:DGNormalizedEncoding(expected)];
}

void SCIInstallGraphQLDogfoodForceHooksIfNeeded(void) {
    static BOOL objcGroupInstalled = NO;
    static BOOL statusInstalled = NO;
    static BOOL warningInstalled = NO;

    SCIRefreshGraphQLDogfoodForceEnabled();
    if (!DGForceOn()) return;

    // Targeted class-method hook only. It performs no global scan at launch;
    // the generated-model resolver runs later when IG builds the real query.
    SCIInstallGraphQLDogfoodQueryBridgeIfNeeded();

    if (!objcGroupInstalled) {
        objcGroupInstalled = YES;
        %init(SCIGraphQLDogfoodLocalDecisionGroup);
    }

    if (!statusInstalled) {
        Class statusClass = objc_getClass(
            "DogfoodingEligibilityQuery_xdtApi_V1_Dogfooding_EligibilityStatusResponseImpl"
        );
        SEL statusSel = NSSelectorFromString(@"status");
        Method statusMethod = statusClass ? class_getInstanceMethod(statusClass, statusSel) : NULL;
        if (DGMethodMatches(statusMethod, "@16@0:8")) {
            MSHookMessageEx(statusClass, statusSel,
                            (IMP)DGExactEligibilityStatus,
                            (IMP *)&orig_DGExactEligibilityStatus);
            statusInstalled = (orig_DGExactEligibilityStatus != NULL);
        } else if (statusMethod) {
            DGFLOG("skip exact eligibility status; ABI=%{public}s",
                   method_getTypeEncoding(statusMethod));
        }
    }

    if (!warningInstalled) {
        Class coordinator = objc_getClass(
            "_TtC17IGDogfoodingFirst26DogfoodingFirstCoordinator"
        );
        SEL warningSel = NSSelectorFromString(@"didPassWarningExpirationForUser:");
        Method warningMethod = coordinator ? class_getInstanceMethod(coordinator, warningSel) : NULL;
        if (DGMethodMatches(warningMethod, "v24@0:8@16")) {
            MSHookMessageEx(coordinator, warningSel,
                            (IMP)DGWarningExpiration,
                            (IMP *)&orig_DGWarningExpiration);
            warningInstalled = (orig_DGWarningExpiration != NULL);
        } else if (warningMethod) {
            DGFLOG("skip warning expiration; ABI=%{public}s",
                   method_getTypeEncoding(warningMethod));
        }
    }

    DGFLOG("installed local=%d status=%d warning=%d",
           objcGroupInstalled, statusInstalled, warningInstalled);
}

%ctor {
    @autoreleasepool {
        SCIRefreshGraphQLDogfoodForceEnabled();
        if (!DGForceOn()) return;
        SCIInstallGraphQLDogfoodForceHooksIfNeeded();
    }
}
