/*
 * SCIEmployeeBootstrap.xm
 * RyukGram
 *
 * Safe ObjC identity bootstrap only.
 *
 * C-level MobileConfig/InternalUse hooks live in InternalModeHooks.xm.
 * This file intentionally does not fishhook IGMobileConfigBooleanValueForInternalUse
 * or IGMobileConfigSessionlessBooleanValueForInternalUse, because duplicate rebinds
 * can chain orig pointers incorrectly and cause recursion/early-session instability.
 */

#import "../../Utils.h"
#import <Foundation/Foundation.h>
#import <objc/runtime.h>
#import <substrate.h>

static BOOL rgEmployeeMasterEnabled(void) {
    return [SCIUtils getBoolPref:@"igt_employee_master"] ||
           [SCIUtils getBoolPref:@"igt_employee"] ||
           [SCIUtils getBoolPref:@"igt_employee_devoptions_gate"] ||
           [SCIUtils getBoolPref:@"igt_employee_mc"] ||
           [SCIUtils getBoolPref:@"igt_employee_or_test_user_mc"];
}

static BOOL (*orig_IGUserSession_isEmployee)(id, SEL);
static BOOL hook_IGUserSession_isEmployee(id self, SEL _cmd) {
    if (rgEmployeeMasterEnabled()) return YES;
    return orig_IGUserSession_isEmployee ? orig_IGUserSession_isEmployee(self, _cmd) : NO;
}

static BOOL (*orig_IGUserSession_isDogfooder)(id, SEL);
static BOOL hook_IGUserSession_isDogfooder(id self, SEL _cmd) {
    if (rgEmployeeMasterEnabled()) return YES;
    return orig_IGUserSession_isDogfooder ? orig_IGUserSession_isDogfooder(self, _cmd) : NO;
}

static BOOL (*orig_IGUserSession_isTestUser)(id, SEL);
static BOOL hook_IGUserSession_isTestUser(id self, SEL _cmd) {
    if (rgEmployeeMasterEnabled()) return YES;
    return orig_IGUserSession_isTestUser ? orig_IGUserSession_isTestUser(self, _cmd) : NO;
}

static BOOL (*orig_IGUserSession_isEmployeeOrTestUser)(id, SEL);
static BOOL hook_IGUserSession_isEmployeeOrTestUser(id self, SEL _cmd) {
    if (rgEmployeeMasterEnabled() || [SCIUtils getBoolPref:@"igt_employee_or_test_user_mc"]) return YES;
    return orig_IGUserSession_isEmployeeOrTestUser ? orig_IGUserSession_isEmployeeOrTestUser(self, _cmd) : NO;
}

static BOOL (*orig_IGUserSession_isInternalUser)(id, SEL);
static BOOL hook_IGUserSession_isInternalUser(id self, SEL _cmd) {
    if (rgEmployeeMasterEnabled()) return YES;
    return orig_IGUserSession_isInternalUser ? orig_IGUserSession_isInternalUser(self, _cmd) : NO;
}

static BOOL (*orig_IGDeviceSession_isEmployee)(id, SEL);
static BOOL hook_IGDeviceSession_isEmployee(id self, SEL _cmd) {
    if (rgEmployeeMasterEnabled()) return YES;
    return orig_IGDeviceSession_isEmployee ? orig_IGDeviceSession_isEmployee(self, _cmd) : NO;
}

static BOOL (*orig_IGDeviceSession_isInternalUser)(id, SEL);
static BOOL hook_IGDeviceSession_isInternalUser(id self, SEL _cmd) {
    if (rgEmployeeMasterEnabled()) return YES;
    return orig_IGDeviceSession_isInternalUser ? orig_IGDeviceSession_isInternalUser(self, _cmd) : NO;
}

static void RYHookBoolMethod(Class cls, SEL sel, IMP replacement, IMP *original) {
    if (!cls || !sel || !replacement || !original) return;

    Method m = class_getInstanceMethod(cls, sel);
    if (!m) {
        NSLog(@"[RyukGram][EmployeeBootstrap] skip missing %@ - %@", NSStringFromClass(cls), NSStringFromSelector(sel));
        return;
    }

    MSHookMessageEx(cls, sel, replacement, original);
    NSLog(@"[RyukGram][EmployeeBootstrap] hooked %@ - %@", NSStringFromClass(cls), NSStringFromSelector(sel));
}

__attribute__((constructor))
static void RYEmployeeBootstrapInit(void) {
    @autoreleasepool {
        Class userSession = NSClassFromString(@"IGUserSession");
        RYHookBoolMethod(userSession, @selector(isEmployee), (IMP)hook_IGUserSession_isEmployee, (IMP *)&orig_IGUserSession_isEmployee);
        RYHookBoolMethod(userSession, @selector(isDogfooder), (IMP)hook_IGUserSession_isDogfooder, (IMP *)&orig_IGUserSession_isDogfooder);
        RYHookBoolMethod(userSession, @selector(isTestUser), (IMP)hook_IGUserSession_isTestUser, (IMP *)&orig_IGUserSession_isTestUser);
        RYHookBoolMethod(userSession, @selector(isEmployeeOrTestUser), (IMP)hook_IGUserSession_isEmployeeOrTestUser, (IMP *)&orig_IGUserSession_isEmployeeOrTestUser);
        RYHookBoolMethod(userSession, @selector(isInternalUser), (IMP)hook_IGUserSession_isInternalUser, (IMP *)&orig_IGUserSession_isInternalUser);

        Class deviceSession = NSClassFromString(@"IGDeviceSession");
        RYHookBoolMethod(deviceSession, @selector(isEmployee), (IMP)hook_IGDeviceSession_isEmployee, (IMP *)&orig_IGDeviceSession_isEmployee);
        RYHookBoolMethod(deviceSession, @selector(isInternalUser), (IMP)hook_IGDeviceSession_isInternalUser, (IMP *)&orig_IGDeviceSession_isInternalUser);

        NSLog(@"[RyukGram][EmployeeBootstrap] ObjC identity bootstrap loaded. master=%d", rgEmployeeMasterEnabled());
    }
}
