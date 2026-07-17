#import "SCIInternalGatePrefs.h"
#import "SCIDogfoodObjectRuntime.h"
#import "../../Utils.h"
#import <UIKit/UIKit.h>
#import <mach-o/dyld.h>
#import <objc/message.h>
#import <objc/runtime.h>
#import <substrate.h>
#import <os/log.h>
#import <stdint.h>
#import <string.h>

#define ACCELLLOG(fmt, ...) os_log(OS_LOG_DEFAULT, "[SCIGate] BugMenuActionCells " fmt, ##__VA_ARGS__)

// Revalidated with radare2 6.1.8 (Capstone 5 backend) and independently with
// Python Capstone 5.0.7 against Instagram SHA-256
// a562b3626c663eec47b41ed1bca7a7af6aa00cc30bada3293046f7cce1a555aa.
//
// The two native rows are IGTextButton-backed cells. Their exact setters are:
//   IGBugReportActionCell     -setEnabled:  VA 0x10970f808
//   IGBugReportLinkActionCell -setEnabled:  VA 0x10970f85c
// Both forward x2 to the embedded button. UITableView selection/highlight alone
// therefore cannot enable the tap. The button calls the controller through:
//   -bugReportingActionCellButtonTapped:     VA 0x1084c3a94
//   -bugReportingLinkActionCellButtonTapped: VA 0x10851549c
// Those delegate methods, not tableView:didSelectRowAtIndexPath:, are the
// authoritative tap route for these cells.

typedef NS_ENUM(NSInteger, ACRowTarget) {
    ACRowTargetNone = 0,
    ACRowTargetDogfoodingAssistant = 1,
    ACRowTargetInternalSettings = 2,
};

static const void *kACRowTargetKey = &kACRowTargetKey;

id SCIEmployeeInternalCapturedDeviceSession(void);
id SCIEmployeeInternalCapturedUserSession(void);

static BOOL ACMasterOn(void) {
    return [SCIInternalGatePrefs employeeInternalMasterEnabled];
}

static BOOL ACInternalOn(void) {
    return ACMasterOn() ||
        [SCIUtils getBoolPref:@"sci_force_internal_settings_menu"] ||
        [SCIUtils getBoolPref:@"sci_force_internal_settings_availability"] ||
        [SCIUtils getBoolPref:@"sci_force_internal_settings_loggedout"];
}

static NSString *ACNormalizedEncoding(const char *encoding) {
    if (!encoding) return @"";
    NSMutableString *result = [NSMutableString string];
    const char *p = encoding;
    while (*p) {
        if (*p != '@') {
            [result appendFormat:@"%c", *p++];
            continue;
        }
        [result appendString:@"@"]; p++;
        if (*p == '"') {
            for (p++; *p && *p != '"'; p++) {}
            if (*p) p++;
        } else if (*p == '?') {
            [result appendString:@"?"]; p++;
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
    return result;
}

static BOOL ACEncodingMatches(Method method, const char *expected) {
    return method && expected &&
        [ACNormalizedEncoding(method_getTypeEncoding(method))
            isEqualToString:ACNormalizedEncoding(expected)];
}

static ACRowTarget ACTargetFromText(id text) {
    if (![text isKindOfClass:NSString.class]) return ACRowTargetNone;
    NSString *value = [(NSString *)text stringByTrimmingCharactersInSet:
        NSCharacterSet.whitespaceAndNewlineCharacterSet];
    if ([value caseInsensitiveCompare:@"Dogfooding Assistant"] == NSOrderedSame) {
        return ACRowTargetDogfoodingAssistant;
    }
    if ([value caseInsensitiveCompare:@"Internal Settings"] == NSOrderedSame) {
        return ACRowTargetInternalSettings;
    }
    return ACRowTargetNone;
}

static ACRowTarget ACTargetForCell(id cell) {
    if (!cell) return ACRowTargetNone;
    NSNumber *stored = objc_getAssociatedObject(cell, kACRowTargetKey);
    if (stored) return (ACRowTarget)stored.integerValue;

    id text = nil;
    SEL getter = NSSelectorFromString(@"cellText");
    Method method = class_getInstanceMethod([cell class], getter);
    if (ACEncodingMatches(method, "@16@0:8")) {
        @try { text = ((id (*)(id, SEL))objc_msgSend)(cell, getter); }
        @catch (__unused id exception) {}
    }
    if (!text && [cell isKindOfClass:UITableViewCell.class]) {
        UITableViewCell *tableCell = cell;
        text = tableCell.textLabel.text ?: tableCell.accessibilityLabel;
    }
    ACRowTarget target = ACTargetFromText(text);
    objc_setAssociatedObject(cell, kACRowTargetKey, @(target),
                             OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    return target;
}

static void ACStoreTarget(id cell, id text) {
    if (!cell) return;
    objc_setAssociatedObject(cell, kACRowTargetKey,
        @(ACTargetFromText(text)), OBJC_ASSOCIATION_RETAIN_NONATOMIC);
}

static BOOL ACTargetEnabled(ACRowTarget target) {
    if (target == ACRowTargetDogfoodingAssistant) return ACMasterOn();
    if (target == ACRowTargetInternalSettings) return ACInternalOn();
    return NO;
}

static Ivar ACExactMenuIvar(id controller, const char *name,
                            ptrdiff_t expectedOffset) {
    if (!controller || !name) return NULL;
    NSString *className = NSStringFromClass([controller class]) ?: @"";
    if (![className containsString:@"IGBugReportMenuViewController"]) return NULL;
    Ivar ivar = class_getInstanceVariable([controller class], name);
    return ivar && ivar_getOffset(ivar) == expectedOffset ? ivar : NULL;
}

static id ACReadObject(id controller, const char *name, ptrdiff_t offset) {
    Ivar ivar = ACExactMenuIvar(controller, name, offset);
    if (!ivar) return nil;
    @try { return object_getIvar(controller, ivar); }
    @catch (__unused id exception) { return nil; }
}

static BOOL ACWriteObject(id controller, const char *name,
                          ptrdiff_t offset, id value) {
    Ivar ivar = ACExactMenuIvar(controller, name, offset);
    if (!ivar) return NO;
    @try { object_setIvar(controller, ivar, value); return YES; }
    @catch (__unused id exception) { return NO; }
}

static BOOL ACWriteInteger(id controller, const char *name,
                           ptrdiff_t offset, NSInteger value) {
    if (!ACExactMenuIvar(controller, name, offset)) return NO;
    uint8_t *base = (__bridge void *)controller;
    memcpy(base + offset, &value, sizeof(value));
    return YES;
}

static BOOL ACWriteByte(id controller, const char *name,
                        ptrdiff_t offset, uint8_t value) {
    if (!ACExactMenuIvar(controller, name, offset)) return NO;
    uint8_t *base = (__bridge void *)controller;
    memcpy(base + offset, &value, sizeof(value));
    return YES;
}

static id ACDeviceSessionForUserSession(id userSession) {
    if (!userSession) return nil;
    SEL selector = NSSelectorFromString(@"deviceSession");
    Method method = class_getInstanceMethod([userSession class], selector);
    if (!ACEncodingMatches(method, "@16@0:8")) return nil;
    @try { return ((id (*)(id, SEL))objc_msgSend)(userSession, selector); }
    @catch (__unused id exception) { return nil; }
}

static void ACPrepareController(id controller, ACRowTarget target) {
    if (!controller || !ACTargetEnabled(target)) return;

    id userSession = ACReadObject(controller, "userSession", 0x18) ?:
        SCIEmployeeInternalCapturedUserSession() ?:
        [SCIDogfoodObjectRuntime activeUserSession];
    if (userSession && !ACReadObject(controller, "userSession", 0x18)) {
        ACWriteObject(controller, "userSession", 0x18, userSession);
    }

    id deviceSession = ACReadObject(controller, "deviceSession", 0x10) ?:
        SCIEmployeeInternalCapturedDeviceSession() ?:
        ACDeviceSessionForUserSession(userSession);
    if (deviceSession && !ACReadObject(controller, "deviceSession", 0x10)) {
        ACWriteObject(controller, "deviceSession", 0x10, deviceSession);
    }

    // rowsGrouped(1) satisfies the native enabled predicate for both cells.
    ACWriteByte(controller, "maisaUXVariant", 0x84, 1);

    if (target == ACRowTargetDogfoodingAssistant) {
        ACWriteByte(controller, "showDogfoodingAssistant", 0x83, 1);
    } else if (target == ACRowTargetInternalSettings) {
        // Native action tag 7: raw 0 opens, 1/3 return silently and 2 denies.
        ACWriteInteger(controller, "internalSettingsAvailabilityStatus", 0x78, 0);
        ACWriteByte(controller, "showInternalSettings", 0x80, 1);
        ACWriteByte(controller, "showShakeToReportPreferenceToggle", 0x82, 1);
        if (userSession) {
            ACWriteInteger(controller, "style", 0x20, 0);
        } else {
            ACWriteInteger(controller, "style", 0x20, 2);
            ACWriteByte(controller, "showLoggedOutInternalSettings", 0x81, 1);
        }
    }

    [SCIDogfoodObjectRuntime noteAction:
        target == ACRowTargetDogfoodingAssistant
            ? @"Dogfooding Assistant button route"
            : @"Internal Settings button route"
                                  status:@"native cell enabled and controller normalized"
                                  detail:@{ @"userSession": userSession ? @"present" : @"nil",
                                            @"deviceSession": deviceSession ? @"present" : @"nil" }];
}

#pragma mark - Exact action cell hooks

static void (*origActionSetCellText)(id, SEL, id) = NULL;
static void (*origLinkSetCellText)(id, SEL, id) = NULL;
static void (*origActionSetEnabled)(id, SEL, BOOL) = NULL;
static void (*origLinkSetEnabled)(id, SEL, BOOL) = NULL;
static BOOL (*origActionEnabled)(id, SEL) = NULL;
static BOOL (*origLinkEnabled)(id, SEL) = NULL;

static void ACForceEnabledViaSelector(id cell) {
    if (!cell || !ACTargetEnabled(ACTargetForCell(cell))) return;
    SEL selector = NSSelectorFromString(@"setEnabled:");
    @try { ((void (*)(id, SEL, BOOL))objc_msgSend)(cell, selector, YES); }
    @catch (__unused id exception) {}
}

static void newActionSetCellText(id self, SEL _cmd, id text) {
    ACStoreTarget(self, text);
    if (origActionSetCellText) origActionSetCellText(self, _cmd, text);
    ACForceEnabledViaSelector(self);
}

static void newLinkSetCellText(id self, SEL _cmd, id text) {
    ACStoreTarget(self, text);
    if (origLinkSetCellText) origLinkSetCellText(self, _cmd, text);
    ACForceEnabledViaSelector(self);
}

static void newActionSetEnabled(id self, SEL _cmd, BOOL enabled) {
    if (ACTargetEnabled(ACTargetForCell(self))) enabled = YES;
    if (origActionSetEnabled) origActionSetEnabled(self, _cmd, enabled);
}

static void newLinkSetEnabled(id self, SEL _cmd, BOOL enabled) {
    if (ACTargetEnabled(ACTargetForCell(self))) enabled = YES;
    if (origLinkSetEnabled) origLinkSetEnabled(self, _cmd, enabled);
}

static BOOL newActionEnabled(id self, SEL _cmd) {
    if (ACTargetEnabled(ACTargetForCell(self))) return YES;
    return origActionEnabled ? origActionEnabled(self, _cmd) : NO;
}

static BOOL newLinkEnabled(id self, SEL _cmd) {
    if (ACTargetEnabled(ACTargetForCell(self))) return YES;
    return origLinkEnabled ? origLinkEnabled(self, _cmd) : NO;
}

#pragma mark - Exact native button delegate hooks

static void (*origActionButtonTapped)(id, SEL, id) = NULL;
static void (*origLinkButtonTapped)(id, SEL, id) = NULL;

static void newActionButtonTapped(id self, SEL _cmd, id cell) {
    ACRowTarget target = ACTargetForCell(cell);
    if (ACTargetEnabled(target)) {
        ACPrepareController(self, target);
        ACForceEnabledViaSelector(cell);
    }
    if (origActionButtonTapped) origActionButtonTapped(self, _cmd, cell);
}

static void newLinkButtonTapped(id self, SEL _cmd, id cell) {
    ACRowTarget target = ACTargetForCell(cell);
    if (ACTargetEnabled(target)) {
        ACPrepareController(self, target);
        ACForceEnabledViaSelector(cell);
    }
    if (origLinkButtonTapped) origLinkButtonTapped(self, _cmd, cell);
}

static void ACHookInstance(Class cls, NSString *name, const char *encoding,
                           IMP replacement, IMP *original) {
    if (!cls || !name.length || !replacement || !original || *original) return;
    SEL selector = NSSelectorFromString(name);
    Method method = class_getInstanceMethod(cls, selector);
    if (!ACEncodingMatches(method, encoding)) {
        if (method) ACCELLLOG("skip %{public}@.%{public}@ ABI=%{public}s",
            NSStringFromClass(cls), name, method_getTypeEncoding(method));
        return;
    }
    MSHookMessageEx(cls, selector, replacement, original);
}

static Class ACClass(NSString *mangled, NSString *qualified) {
    return NSClassFromString(mangled) ?: NSClassFromString(qualified);
}

static void ACInstall(void) {
    @synchronized (SCIDogfoodObjectRuntime.class) {
        Class action = ACClass(
            @"_TtC17IGBugReporterMenu21IGBugReportActionCell",
            @"IGBugReporterMenu.IGBugReportActionCell");
        Class link = ACClass(
            @"_TtC17IGBugReporterMenu25IGBugReportLinkActionCell",
            @"IGBugReporterMenu.IGBugReportLinkActionCell");
        Class menu = ACClass(
            @"_TtC17IGBugReporterMenu29IGBugReportMenuViewController",
            @"IGBugReporterMenu.IGBugReportMenuViewController");

        ACHookInstance(action, @"setCellText:", "v24@0:8@16",
            (IMP)newActionSetCellText, (IMP *)&origActionSetCellText);
        ACHookInstance(link, @"setCellText:", "v24@0:8@16",
            (IMP)newLinkSetCellText, (IMP *)&origLinkSetCellText);
        ACHookInstance(action, @"setEnabled:", "v20@0:8B16",
            (IMP)newActionSetEnabled, (IMP *)&origActionSetEnabled);
        ACHookInstance(link, @"setEnabled:", "v20@0:8B16",
            (IMP)newLinkSetEnabled, (IMP *)&origLinkSetEnabled);
        ACHookInstance(action, @"enabled", "B16@0:8",
            (IMP)newActionEnabled, (IMP *)&origActionEnabled);
        ACHookInstance(link, @"enabled", "B16@0:8",
            (IMP)newLinkEnabled, (IMP *)&origLinkEnabled);
        ACHookInstance(menu, @"bugReportingActionCellButtonTapped:",
            "v24@0:8@16", (IMP)newActionButtonTapped,
            (IMP *)&origActionButtonTapped);
        ACHookInstance(menu, @"bugReportingLinkActionCellButtonTapped:",
            "v24@0:8@16", (IMP)newLinkButtonTapped,
            (IMP *)&origLinkButtonTapped);
    }
}

static void ACImageLoaded(const struct mach_header *header, intptr_t slide) {
    (void)header; (void)slide;
    ACInstall();
}

__attribute__((constructor))
static void SCIBugMenuActionCellsCtor(void) {
    @autoreleasepool {
        ACInstall();
        _dyld_register_func_for_add_image(ACImageLoaded);
    }
}
