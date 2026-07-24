#import "../../Utils.h"
#import <UIKit/UIKit.h>
#import "SCIInternalGatePrefs.h"
#import <objc/runtime.h>
#import <substrate.h>
#import <os/log.h>
#import <string.h>

#define DGFLOG(fmt, ...) os_log(OS_LOG_DEFAULT, "[SCIGate] GraphQLDogfoodForce " fmt, ##__VA_ARGS__)

void SCIInstallGraphQLDogfoodQueryBridgeIfNeeded(void);

static volatile BOOL sDGForceEnabled = NO;

void SCIRefreshGraphQLDogfoodForceEnabled(void) {
    sDGForceEnabled = [SCIInternalGatePrefs employeeInternalMasterEnabled];
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

// Revalidated in Instagram(4), SHA-256
// a562b3626c663eec47b41ed1bca7a7af6aa00cc30bada3293046f7cce1a555aa:
//
// DogfoodingEligibilityQueryResponse
//   -> xdtApi_V1_Dogfooding_EligibilityStatus
//   -> exact nested model -status
//   -> -boolValue
//   -> tbnz: YES skips the show-issue path; NO enters it.
//
// There is no third GraphQL warning status in this path. Warning expiration is
// a separate local coordinator callback, hooked independently below. Returning
// @YES here is therefore the exact local eligible/pass value, not a guessed
// enum or a global -status override.
__attribute__((unused)) static id DGExactEligibilityStatus(id self, SEL _cmd) {
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

// DogfoodingProductionLockoutViewController is the screen IG shows when a
// production (IGDistributedMobileBuild) user is denied dogfooding. Unlike the
// eligibility RESPONSE (a runtime Swift GQLModel that is NOT a static ObjC class
// and therefore cannot be swizzled), this lockout VC is a real Swift @objc
// UIViewController (_TtC17IGDogfoodingFirst41...), so -viewDidLoad is hookable.
// Bypassing it removes the block on internal access. This replaces the previous
// eligibility-status observer, whose target class does not exist at runtime
// (that was the persistent "missing=1" in the dogfood snapshot).
static void (*orig_DGLockoutViewDidLoad)(id, SEL) = NULL;
static void DGLockoutViewDidLoad(id self, SEL _cmd) {
    if (orig_DGLockoutViewDidLoad) orig_DGLockoutViewDidLoad(self, _cmd);
    if (!DGForceOn()) return;
    __weak UIViewController *weakVC = (UIViewController *)self;
    dispatch_async(dispatch_get_main_queue(), ^{
        UIViewController *vc = weakVC;
        if (!vc) return;
        UINavigationController *nav = vc.navigationController;
        if (nav && nav.viewControllers.count > 1) {
            [nav popViewControllerAnimated:NO];
        } else if (vc.presentingViewController) {
            [vc dismissViewControllerAnimated:NO completion:nil];
        } else {
            vc.view.hidden = YES;
        }
    });
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
        Class baseUser = objc_getClass("IGBaseUser");
        Method showIssueMethod = baseUser
            ? class_getInstanceMethod(baseUser,
                NSSelectorFromString(@"asIGDogfoodingFirstShowIssueFragmentImmutableModel"))
            : NULL;
        if (DGMethodMatches(showIssueMethod, "@16@0:8")) {
            %init(SCIGraphQLDogfoodLocalDecisionGroup);
            objcGroupInstalled = YES;
        } else if (showIssueMethod) {
            DGFLOG("skip local show-issue fragment; ABI=%{public}s",
                   method_getTypeEncoding(showIssueMethod));
        }
    }

    // Eligibility RESPONSE is a runtime Swift GQLModel (no static ObjC class) and
    // cannot be swizzled; targeting it was the "missing=1". The real, hookable gate
    // is the production lockout VC below.
    if (!statusInstalled) {
        Class lockout = objc_getClass(
            "_TtC17IGDogfoodingFirst41DogfoodingProductionLockoutViewController"
        );
        SEL vdlSel = @selector(viewDidLoad);
        Method vdl = lockout ? class_getInstanceMethod(lockout, vdlSel) : NULL;
        if (DGMethodMatches(vdl, "v16@0:8")) {
            MSHookMessageEx(lockout, vdlSel,
                            (IMP)DGLockoutViewDidLoad,
                            (IMP *)&orig_DGLockoutViewDidLoad);
            statusInstalled = (orig_DGLockoutViewDidLoad != NULL);
        } else if (vdl) {
            DGFLOG("skip lockout bypass; ABI=%{public}s",
                   method_getTypeEncoding(vdl));
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
