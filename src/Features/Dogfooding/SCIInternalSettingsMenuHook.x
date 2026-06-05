// ============================================================================
// SCIInternalSettingsMenuHook.x
// ============================================================================
// Makes IG's own internal/debug entries appear inside the native Bug Reporter
// menu. This does NOT block IGWindow.showDebugMenu; it only forces the menu VC's
// constructor/getters to expose internal rows.

#import <Foundation/Foundation.h>
#import <objc/runtime.h>
#import <substrate.h>
#import <os/log.h>
#import "SCIInternalGatePrefs.h"
#import "SCIDogfoodObjectRuntime.h"

#define BLOG(fmt, ...) os_log(OS_LOG_DEFAULT, "[SCIGate] InternalMenu " fmt, ##__VA_ARGS__)
static inline BOOL ON(NSString *k){ return [SCIInternalGatePrefs objCGateEnabledForKey:k]; }
static NSString *const kForce  = @"sci_force_internal_settings_menu";
static NSString *const kLogged = @"sci_force_internal_settings_loggedout";

typedef id (*InitT)(id, SEL, id, id, id, id, id, id, long, long, BOOL, BOOL, BOOL);
static InitT gOrig = NULL;
static SEL gSel = NULL;
static BOOL (*orig_showInternal)(id, SEL) = NULL;
static BOOL (*orig_showLoggedOut)(id, SEL) = NULL;
static BOOL (*orig_showShake)(id, SEL) = NULL;
static BOOL (*orig_showAssistant)(id, SEL) = NULL;

static Class SCIClassByNames(NSArray<NSString *> *names) {
    for (NSString *n in names) { if (!n.length) continue; Class c = NSClassFromString(n); if (c) return c; c = objc_getClass(n.UTF8String); if (c) return c; }
    unsigned int count = 0; Class *classes = objc_copyClassList(&count); Class found = Nil;
    for (unsigned int i=0; classes && i<count && !found; i++) { const char *cn = class_getName(classes[i]); if (!cn) continue; NSString *s = [NSString stringWithUTF8String:cn]; for (NSString *n in names) if ([s isEqualToString:n] || [s hasSuffix:n] || [s containsString:n]) { found = classes[i]; break; } }
    if (classes) free(classes); return found;
}

static BOOL new_showInternal(id self, SEL _cmd) { return ON(kForce) ? YES : (orig_showInternal ? orig_showInternal(self,_cmd) : NO); }
static BOOL new_showLoggedOut(id self, SEL _cmd) { return (ON(kForce) && ON(kLogged)) ? YES : (orig_showLoggedOut ? orig_showLoggedOut(self,_cmd) : NO); }
static BOOL new_showShake(id self, SEL _cmd) { return ON(kForce) ? YES : (orig_showShake ? orig_showShake(self,_cmd) : NO); }
static BOOL new_showAssistant(id self, SEL _cmd) { return ON(kForce) ? YES : (orig_showAssistant ? orig_showAssistant(self,_cmd) : NO); }

static void SCIHookBoolGetter(Class C, NSString *name, IMP newImp, IMP *orig) {
    SEL s = NSSelectorFromString(name);
    if (*orig || !class_getInstanceMethod(C, s)) return;
    MSHookMessageEx(C, s, newImp, orig);
    [SCIDogfoodObjectRuntime noteAction:@"Internal menu getter hook" status:(*orig ? @"hooked" : @"failed") detail:[NSString stringWithFormat:@"%s#%@", class_getName(C), name]];
}

static void installInternalSettingsMenuHook(void) {
    static BOOL initDone = NO;
    Class C = SCIClassByNames(@[@"_TtC17IGBugReporterMenu29IGBugReportMenuViewController", @"IGBugReporterMenu.IGBugReportMenuViewController", @"IGBugReportMenuViewController"]);
    if (!C) { [SCIDogfoodObjectRuntime noteAction:@"Internal menu hook" status:@"class not loaded" detail:@"IGBugReportMenuViewController"]; return; }

    if (!initDone) {
        gSel = NSSelectorFromString(@"initWithDeviceSession:userSession:reliabilityLogging:navChain:endpoint:entryPoint:style:internalSettingsAvailabilityStatus:showInternalSettings:showLoggedOutInternalSettings:showShakeToReportPreferenceToggle:");
        if (class_getInstanceMethod(C, gSel)) {
            IMP newImp = imp_implementationWithBlock(^id(id me, id deviceSession, id userSession, id reliabilityLogging, id navChain, id endpoint, id entryPoint, long style, long status, BOOL showInternal, BOOL showLoggedOut, BOOL showShake) {
                BOOL fi = showInternal, fl = showLoggedOut, fs = showShake;
                if (ON(kForce)) { fi = YES; fs = YES; if (ON(kLogged)) fl = YES; }
                return gOrig ? gOrig(me, gSel, deviceSession, userSession, reliabilityLogging, navChain, endpoint, entryPoint, style, status, fi, fl, fs) : me;
            });
            IMP orig = NULL; MSHookMessageEx(C, gSel, newImp, &orig); gOrig = (InitT)orig; initDone = (orig != NULL);
            [SCIDogfoodObjectRuntime noteAction:@"Internal menu init hook" status:(orig?@"hooked":@"failed") detail:NSStringFromClass(C)];
        }
    }

    SCIHookBoolGetter(C, @"showInternalSettings", (IMP)new_showInternal, (IMP *)&orig_showInternal);
    SCIHookBoolGetter(C, @"showLoggedOutInternalSettings", (IMP)new_showLoggedOut, (IMP *)&orig_showLoggedOut);
    SCIHookBoolGetter(C, @"showShakeToReportPreferenceToggle", (IMP)new_showShake, (IMP *)&orig_showShake);
    SCIHookBoolGetter(C, @"showDogfoodingAssistant", (IMP)new_showAssistant, (IMP *)&orig_showAssistant);
}

%ctor {
    @autoreleasepool {
        [SCIInternalGatePrefs installCrashGuardIfNeeded];
        installInternalSettingsMenuHook();
        double d[] = {1.0, 3.0, 6.0, 10.0};
        for (NSUInteger i=0;i<sizeof(d)/sizeof(d[0]);i++) dispatch_after(dispatch_time(DISPATCH_TIME_NOW,(int64_t)(d[i]*NSEC_PER_SEC)),dispatch_get_main_queue(),^{ installInternalSettingsMenuHook(); });
    }
}
