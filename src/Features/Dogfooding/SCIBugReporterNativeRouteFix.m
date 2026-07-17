#import "SCIDogfoodObjectRuntime.h"
#import "SCIInternalGatePrefs.h"
#import "../../Utils.h"
#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>
#import <mach-o/dyld.h>
#import <objc/message.h>
#import <objc/runtime.h>
#import <substrate.h>
#import <os/log.h>
#import <string.h>

#define BRLOG(fmt, ...) os_log(OS_LOG_DEFAULT, "[SCIGate] BugReporterRoutes " fmt, ##__VA_ARGS__)

static BOOL BRMasterOn(void) {
    return [SCIInternalGatePrefs employeeInternalMasterEnabled];
}

static BOOL BRInternalOn(void) {
    return BRMasterOn() ||
        [SCIUtils getBoolPref:@"sci_force_internal_settings_menu"] ||
        [SCIUtils getBoolPref:@"sci_force_internal_settings_availability"] ||
        [SCIUtils getBoolPref:@"sci_force_internal_settings_loggedout"];
}

static NSString *BRNormalizedEncoding(const char *encoding) {
    if (!encoding) return @"";
    NSMutableString *out = [NSMutableString string];
    const char *p = encoding;
    while (*p) {
        if (*p != '@') { [out appendFormat:@"%c", *p++]; continue; }
        [out appendString:@"@"]; p++;
        if (*p == '"') {
            for (p++; *p && *p != '"'; p++) {}
            if (*p) p++;
        } else if (*p == '?') {
            [out appendString:@"?"]; p++;
            if (*p == '<') {
                NSInteger depth = 0;
                do { if (*p == '<') depth++; else if (*p == '>') depth--; p++; }
                while (*p && depth > 0);
            }
        }
    }
    return out;
}

static BOOL BRMethodMatches(Method method, const char *expected) {
    return method && expected &&
        [BRNormalizedEncoding(method_getTypeEncoding(method))
            isEqualToString:BRNormalizedEncoding(expected)];
}

// LIEF/ObjC metadata for the audited binary gives exact offsets. Swift emits an
// empty type encoding for these stored properties, so validate class, name and
// offset instead of guessing from an unavailable ivar-size API.
static Ivar BRExactIvar(id object, const char *name, ptrdiff_t expectedOffset) {
    if (!object || !name) return NULL;
    Class cls = [object class];
    NSString *className = NSStringFromClass(cls) ?: @"";
    if (![className containsString:@"IGBugReportMenuViewController"]) return NULL;
    Ivar ivar = class_getInstanceVariable(cls, name);
    if (!ivar || ivar_getOffset(ivar) != expectedOffset) return NULL;
    return ivar;
}

static NSInteger BRReadInteger(id object, const char *name,
                               ptrdiff_t offset, NSInteger fallback) {
    if (!BRExactIvar(object, name, offset)) return fallback;
    NSInteger value = fallback;
    uint8_t *base = (__bridge void *)object;
    memcpy(&value, base + offset, sizeof(value));
    return value;
}

static BOOL BRWriteInteger(id object, const char *name,
                           ptrdiff_t offset, NSInteger value) {
    if (!BRExactIvar(object, name, offset)) return NO;
    uint8_t *base = (__bridge void *)object;
    memcpy(base + offset, &value, sizeof(value));
    return YES;
}

static BOOL BRWriteBool(id object, const char *name,
                        ptrdiff_t offset, BOOL value) {
    if (!BRExactIvar(object, name, offset)) return NO;
    uint8_t *base = (__bridge void *)object;
    BOOL normalized = value ? YES : NO;
    memcpy(base + offset, &normalized, sizeof(normalized));
    return YES;
}

static id BRReadObject(id object, const char *name, ptrdiff_t offset) {
    Ivar ivar = BRExactIvar(object, name, offset);
    if (!ivar) return nil;
    @try { return object_getIvar(object, ivar); }
    @catch (__unused id exception) { return nil; }
}

static BOOL BRWriteObject(id object, const char *name,
                          ptrdiff_t offset, id value) {
    Ivar ivar = BRExactIvar(object, name, offset);
    if (!ivar) return NO;
    @try {
        object_setIvar(object, ivar, value);
        return YES;
    } @catch (__unused id exception) {
        return NO;
    }
}

static id BRDeviceSessionForUserSession(id userSession) {
    if (!userSession) return nil;
    SEL selector = NSSelectorFromString(@"deviceSession");
    Method method = class_getInstanceMethod([userSession class], selector);
    if (!BRMethodMatches(method, "@16@0:8")) return nil;
    @try { return ((id (*)(id, SEL))objc_msgSend)(userSession, selector); }
    @catch (__unused id exception) { return nil; }
}

static NSInteger BRSupportedInternalStyle(NSInteger style) {
    // r2/Capstone at 0x104aaf69c/0x104aafbec: style 2 and style 0 reach
    // native handlers; any other nonzero style reaches the exact no-op branch.
    return (style == 0 || style == 2) ? style : 0;
}

static void BRApplyLiveDependencies(id controller) {
    if (!controller || !BRInternalOn()) return;

    NSInteger style = BRReadInteger(controller, "style", 32, 0);
    NSInteger normalized = BRSupportedInternalStyle(style);
    if (style != normalized && BRWriteInteger(controller, "style", 32, normalized)) {
        [SCIDogfoodObjectRuntime noteAction:@"Internal Settings route"
                                      status:@"normalized unsupported style to native style 0"
                                      detail:@(style)];
        BRLOG("normalized style %ld -> %ld", (long)style, (long)normalized);
    }

    id deviceSession = BRReadObject(controller, "deviceSession", 16);
    id userSession = BRReadObject(controller, "userSession", 24) ?:
        [SCIDogfoodObjectRuntime activeUserSession];
    if (!deviceSession) {
        deviceSession = BRDeviceSessionForUserSession(userSession);
        if (deviceSession && BRWriteObject(controller, "deviceSession", 16, deviceSession)) {
            [SCIDogfoodObjectRuntime noteObject:deviceSession
                                           role:@"IGDeviceSession"
                                         source:@"IGBugReportMenu.userSession.deviceSession"];
        }
    }

    BRWriteBool(controller, "showInternalSettings", 128, YES);
    BRWriteBool(controller, "showShakeToReportPreferenceToggle", 130, YES);
    if ([SCIUtils getBoolPref:@"sci_force_internal_settings_loggedout"]) {
        BRWriteBool(controller, "showLoggedOutInternalSettings", 129, YES);
    }
    if (BRMasterOn()) BRWriteBool(controller, "showDogfoodingAssistant", 131, YES);
}

typedef id (*BRLegacyInitIMP)(id, SEL, id, id, id, id, id, id,
                              NSInteger, NSInteger, BOOL, BOOL, BOOL);
typedef id (*BRCurrentInitIMP)(id, SEL, id, id, id, id, id, id,
                               NSInteger, NSInteger, BOOL, BOOL, BOOL, BOOL,
                               NSInteger);

static BRLegacyInitIMP origLegacyInit;
static id newLegacyInit(id self, SEL _cmd, id deviceSession, id userSession,
                        id reliabilityLogging, id navChain, id endpoint,
                        id entryPoint, NSInteger style,
                        NSInteger availabilityStatus, BOOL showInternalSettings,
                        BOOL showLoggedOutInternalSettings, BOOL showShakeToggle) {
    if (BRInternalOn()) {
        deviceSession = deviceSession ?: BRDeviceSessionForUserSession(userSession);
        style = BRSupportedInternalStyle(style);
        showInternalSettings = YES;
        showShakeToggle = YES;
    }
    if ([SCIUtils getBoolPref:@"sci_force_internal_settings_loggedout"]) {
        showLoggedOutInternalSettings = YES;
    }
    id result = origLegacyInit ? origLegacyInit(self, _cmd, deviceSession,
        userSession, reliabilityLogging, navChain, endpoint, entryPoint, style,
        availabilityStatus, showInternalSettings,
        showLoggedOutInternalSettings, showShakeToggle) : nil;
    BRApplyLiveDependencies(result);
    return result;
}

static BRCurrentInitIMP origCurrentInit;
static id newCurrentInit(id self, SEL _cmd, id deviceSession, id userSession,
                         id reliabilityLogging, id navChain, id endpoint,
                         id entryPoint, NSInteger style,
                         NSInteger availabilityStatus, BOOL showInternalSettings,
                         BOOL showLoggedOutInternalSettings, BOOL showShakeToggle,
                         BOOL showDogfoodingAssistant,
                         NSInteger maisaUXVariantRawValue) {
    if (BRInternalOn()) {
        deviceSession = deviceSession ?: BRDeviceSessionForUserSession(userSession);
        style = BRSupportedInternalStyle(style);
        showInternalSettings = YES;
        showShakeToggle = YES;
    }
    if ([SCIUtils getBoolPref:@"sci_force_internal_settings_loggedout"]) {
        showLoggedOutInternalSettings = YES;
    }
    if (BRMasterOn()) showDogfoodingAssistant = YES;
    id result = origCurrentInit ? origCurrentInit(self, _cmd, deviceSession,
        userSession, reliabilityLogging, navChain, endpoint, entryPoint, style,
        availabilityStatus, showInternalSettings,
        showLoggedOutInternalSettings, showShakeToggle,
        showDogfoodingAssistant, maisaUXVariantRawValue) : nil;
    BRApplyLiveDependencies(result);
    return result;
}

static void (*origViewDidLoad)(id, SEL);
static void newViewDidLoad(id self, SEL _cmd) {
    BRApplyLiveDependencies(self);
    if (origViewDidLoad) origViewDidLoad(self, _cmd);
    BRApplyLiveDependencies(self);
}

static void (*origViewDidAppear)(id, SEL, BOOL);
static void newViewDidAppear(id self, SEL _cmd, BOOL animated) {
    BRApplyLiveDependencies(self);
    if (origViewDidAppear) origViewDidAppear(self, _cmd, animated);
    BRApplyLiveDependencies(self);
}

static void (*origDidSelect)(id, SEL, UITableView *, NSIndexPath *);
static void newDidSelect(id self, SEL _cmd, UITableView *tableView,
                         NSIndexPath *indexPath) {
    // Current jump table: section 6 = Dogfooding Assistant, section 7 =
    // Internal Settings. Keep the original Swift route authoritative.
    if (indexPath.section == 6 || indexPath.section == 7) {
        BRApplyLiveDependencies(self);
        [SCIDogfoodObjectRuntime noteAction:
            indexPath.section == 6 ? @"Dogfooding Assistant native tap" :
                                     @"Internal Settings native tap"
                                      status:@"forwarded to original Swift route"
                                      detail:@(indexPath.section)];
    }
    if (origDidSelect) origDidSelect(self, _cmd, tableView, indexPath);
}

static Class BRMenuClass(void) {
    return NSClassFromString(@"_TtC17IGBugReporterMenu29IGBugReportMenuViewController") ?:
        NSClassFromString(@"IGBugReportMenuViewController");
}

static void BRHook(Class cls, NSString *name, const char *encoding,
                   IMP replacement, IMP *original) {
    if (!cls || !name.length || !replacement || !original || *original) return;
    SEL selector = NSSelectorFromString(name);
    Method method = class_getInstanceMethod(cls, selector);
    if (!BRMethodMatches(method, encoding)) return;
    MSHookMessageEx(cls, selector, replacement, original);
}

static void BRInstall(void) {
    @synchronized (SCIDogfoodObjectRuntime.class) {
        Class cls = BRMenuClass();
        BRHook(cls,
            @"initWithDeviceSession:userSession:reliabilityLogging:navChain:endpoint:entryPoint:style:internalSettingsAvailabilityStatus:showInternalSettings:showLoggedOutInternalSettings:showShakeToReportPreferenceToggle:",
            "@92@0:8@16@24@32@40@48@56q64q72B80B84B88",
            (IMP)newLegacyInit, (IMP *)&origLegacyInit);
        BRHook(cls,
            @"initWithDeviceSession:userSession:reliabilityLogging:navChain:endpoint:entryPoint:style:internalSettingsAvailabilityStatus:showInternalSettings:showLoggedOutInternalSettings:showShakeToReportPreferenceToggle:showDogfoodingAssistant:maisaUXVariantRawValue:",
            "@104@0:8@16@24@32@40@48@56q64q72B80B84B88B92q96",
            (IMP)newCurrentInit, (IMP *)&origCurrentInit);
        BRHook(cls, @"viewDidLoad", "v16@0:8",
            (IMP)newViewDidLoad, (IMP *)&origViewDidLoad);
        BRHook(cls, @"viewDidAppear:", "v20@0:8B16",
            (IMP)newViewDidAppear, (IMP *)&origViewDidAppear);
        BRHook(cls, @"tableView:didSelectRowAtIndexPath:", "v32@0:8@16@24",
            (IMP)newDidSelect, (IMP *)&origDidSelect);
    }
}

static void BRImageLoaded(const struct mach_header *header, intptr_t slide) {
    (void)header; (void)slide;
    BRInstall();
}

__attribute__((constructor))
static void SCIBugReporterNativeRouteFixCtor(void) {
    @autoreleasepool {
        BRInstall();
        _dyld_register_func_for_add_image(BRImageLoaded);
    }
}
