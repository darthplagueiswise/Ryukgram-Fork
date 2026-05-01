/*
 * SCIEmployeeBootstrap.xm
 * Ryukgram
 *
 * iOS equivalent of InstaEclipse's MobileConfig boolean override and 
 * InstaMoon's Shx.A00.A02 developer options bootstrap.
 *
 * This file implements the "bootstrap" strategy to unlock native developer/dogfood 
 * menus by hooking MobileConfig C-gates and IGUserSession ObjC methods.
 */

#import "../../Utils.h"
#import "SCIExpFlags.h"
#import <Foundation/Foundation.h>
#import <objc/message.h>
#import <dlfcn.h>
#include "../../../modules/fishhook/fishhook.h"

// Constants from InternalModeHooks.xm
static const unsigned long long kIGMCEmployeeSpecifierA = 0x0081030f00000a95ULL; // ig_is_employee
static const unsigned long long kIGMCEmployeeSpecifierB = 0x0081030f00010a96ULL; // ig_is_employee
static const unsigned long long kIGMCEmployeeOrTestUserSpecifier = 0x008100b200000161ULL; // ig_is_employee_or_test_user

// Helper functions (reused from InternalModeHooks.xm logic)
static BOOL rgEmployeeMasterEnabled(void) { 
    return [SCIUtils getBoolPref:@"igt_employee_master"] || 
           [SCIUtils getBoolPref:@"igt_employee"] || 
           [SCIUtils getBoolPref:@"igt_employee_devoptions_gate"]; 
}

static BOOL rgEmployeeMCEnabled(void) { 
    return rgEmployeeMasterEnabled() || [SCIUtils getBoolPref:@"igt_employee_mc"]; 
}

static BOOL rgEmployeeOrTestUserMCEnabled(void) { 
    return rgEmployeeMasterEnabled() || [SCIUtils getBoolPref:@"igt_employee_or_test_user_mc"]; 
}

static BOOL rgInternalObserverEnabled(void) { 
    return [SCIUtils getBoolPref:@"igt_internaluse_observer"]; 
}

static BOOL rgShouldInstallInternalModeHooks(void) {
    return rgEmployeeMasterEnabled() ||
           rgEmployeeMCEnabled() ||
           rgEmployeeOrTestUserMCEnabled() ||
           [SCIUtils getBoolPref:@"igt_internal_apps_gate"] ||
           rgInternalObserverEnabled();
}

// Logic from specifierMatchesEmployee() in InternalModeHooks.xm
static BOOL specifierMatchesEmployeeBootstrap(unsigned long long specifier) {
    if (!rgEmployeeMasterEnabled()) return NO;
    
    if (specifier == kIGMCEmployeeSpecifierA || specifier == kIGMCEmployeeSpecifierB) return YES;
    if (specifier == kIGMCEmployeeOrTestUserSpecifier) return YES;
    
    // We don't have the full name resolver here without duplicating more code, 
    // but the master toggle and explicit specifiers cover the core bootstrap.
    return NO;
}

// --- Fishhook C-level Hook ---

typedef BOOL (*IGMCBoolInternalFn)(id, BOOL, unsigned long long);
static IGMCBoolInternalFn orig_IGMobileConfigBooleanValueForInternalUse_Bootstrap = NULL;

static BOOL hook_IGMobileConfigBooleanValueForInternalUse_Bootstrap(id ctx, BOOL defaultValue, unsigned long long specifier) {
    BOOL original = orig_IGMobileConfigBooleanValueForInternalUse_Bootstrap ?
        orig_IGMobileConfigBooleanValueForInternalUse_Bootstrap(ctx, defaultValue, specifier) : defaultValue;
    
    if (rgEmployeeMasterEnabled() && specifierMatchesEmployeeBootstrap(specifier)) {
        if (rgInternalObserverEnabled()) {
            NSLog(@"[RyukGram][EmployeeBootstrap] Intercepted MC InternalUse spec=0x%016llx -> returning YES", specifier);
        }
        return YES;
    }
    
    return original;
}

// --- ObjC Hooks for IGUserSession ---

%hook IGUserSession

- (BOOL)isEmployee {
    if (rgEmployeeMasterEnabled()) return YES;
    return %orig;
}

- (BOOL)isInternalUser {
    if (rgEmployeeMasterEnabled()) return YES;
    return %orig;
}

- (BOOL)isDogfooder {
    if (rgEmployeeMasterEnabled()) return YES;
    return %orig;
}

- (BOOL)isTestUser {
    if (rgEmployeeMasterEnabled()) return YES;
    return %orig;
}

- (BOOL)isEmployeeOrTestUser {
    if (rgEmployeeMasterEnabled() || [SCIUtils getBoolPref:@"igt_employee_or_test_user_mc"]) return YES;
    return %orig;
}

%end

// --- Constructor ---

%ctor {
    if (!rgShouldInstallInternalModeHooks()) return;

    // Fishhook rebinding with a short delay to ensure binary is loaded
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.5 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
        struct rebinding rebindings[] = {
            {"IGMobileConfigBooleanValueForInternalUse", (void *)hook_IGMobileConfigBooleanValueForInternalUse_Bootstrap, (void **)&orig_IGMobileConfigBooleanValueForInternalUse_Bootstrap},
        };
        rebind_symbols(rebindings, sizeof(rebindings) / sizeof(rebindings[0]));
        
        NSLog(@"[RyukGram][EmployeeBootstrap] Fishhook rebind complete. Master=%d", rgEmployeeMasterEnabled());
    });
}
