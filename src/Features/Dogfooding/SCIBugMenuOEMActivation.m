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

#define BMACTLOG(fmt, ...) os_log(OS_LOG_DEFAULT, "[SCIGate] BugMenuActivation " fmt, ##__VA_ARGS__)

// Revalidated with LIEF + Capstone + radare2 against Instagram SHA-256
// a562b3626c663eec47b41ed1bca7a7af6aa00cc30bada3293046f7cce1a555aa.
//
// Exact Swift stored-property offsets:
//   deviceSession                      object @ 0x10
//   userSession                        object @ 0x18
//   style                              q      @ 0x20
//   internalSettingsAvailabilityStatus q      @ 0x78
//   showInternalSettings               byte   @ 0x80
//   showLoggedOutInternalSettings      byte   @ 0x81
//   showShakeToReportPreferenceToggle  byte   @ 0x82
//   showDogfoodingAssistant             byte   @ 0x83
//   maisaUXVariant                      byte   @ 0x84
//   lazy dogfoodingAssistantSocket      byte   @ 0x85 (never an ObjC id)
//
// Action 6 is Dogfooding Assistant; action 7 is Internal Settings. The native
// cell predicates disable both when maisaUXVariant is control(0) or additive(3).
// The Internal Settings handler additionally switches on style: 0 and 2 execute
// native routes; style 1 reaches the exact no-op branch.

static __weak id sBMDeviceSession;
static __weak id sBMUserSession;

id SCIEmployeeInternalCapturedDeviceSession(void) { return sBMDeviceSession; }
id SCIEmployeeInternalCapturedUserSession(void) { return sBMUserSession; }

static BOOL BMMasterOn(void) {
    return [SCIInternalGatePrefs employeeInternalMasterEnabled];
}

static BOOL BMMenuOn(void) {
    return BMMasterOn() || [SCIUtils getBoolPref:@"sci_force_internal_settings_menu"];
}

static BOOL BMAvailabilityOn(void) {
    return BMMenuOn() || [SCIUtils getBoolPref:@"sci_force_internal_settings_availability"];
}

static BOOL BMLoggedOutOn(void) {
    return [SCIUtils getBoolPref:@"sci_force_internal_settings_loggedout"];
}

static BOOL BMAnyOn(void) {
    return BMMasterOn() || BMMenuOn() || BMAvailabilityOn() || BMLoggedOutOn();
}

static NSInteger BMAvailabilityRaw(void) {
    NSInteger value = (NSInteger)[SCIUtils getDoublePref:
        @"sci_internal_settings_availability_raw_value"];
    if (value < 0) return 0;
    if (value > 2) return 2;
    return value;
}

static Class BMMenuClass(void) {
    return objc_getClass("_TtC17IGBugReporterMenu29IGBugReportMenuViewController") ?:
        objc_getClass("IGBugReportMenuViewController");
}

static Ivar BMExactIvar(id object, const char *name, ptrdiff_t expectedOffset) {
    if (!object || !name) return NULL;
    NSString *className = NSStringFromClass([object class]) ?: @"";
    if (![className containsString:@"IGBugReportMenuViewController"]) return NULL;
    Ivar ivar = class_getInstanceVariable([object class], name);
    if (!ivar || ivar_getOffset(ivar) != expectedOffset) return NULL;
    return ivar;
}

static id BMReadObject(id object, const char *name, ptrdiff_t offset) {
    Ivar ivar = BMExactIvar(object, name, offset);
    if (!ivar) return nil;
    // Swift emits an empty ivar type encoding here, but object_getIvar still
    // preserves the runtime's strong-object semantics for these exact slots.
    @try { return object_getIvar(object, ivar); }
    @catch (__unused id exception) { return nil; }
}

static BOOL BMWriteObject(id object, const char *name,
                          ptrdiff_t offset, id value) {
    Ivar ivar = BMExactIvar(object, name, offset);
    if (!ivar) return NO;
    @try {
        object_setIvar(object, ivar, value);
        return YES;
    } @catch (__unused id exception) {
        return NO;
    }
}

static NSInteger BMReadInteger(id object, const char *name,
                               ptrdiff_t offset, NSInteger fallback) {
    if (!BMExactIvar(object, name, offset)) return fallback;
    NSInteger value = fallback;
    uint8_t *base = (__bridge void *)object;
    memcpy(&value, base + offset, sizeof(value));
    return value;
}

static BOOL BMWriteInteger(id object, const char *name,
                           ptrdiff_t offset, NSInteger value) {
    if (!BMExactIvar(object, name, offset)) return NO;
    uint8_t *base = (__bridge void *)object;
    memcpy(base + offset, &value, sizeof(value));
    return YES;
}

static BOOL BMWriteByte(id object, const char *name,
                        ptrdiff_t offset, uint8_t value) {
    if (!BMExactIvar(object, name, offset)) return NO;
    uint8_t *base = (__bridge void *)object;
    memcpy(base + offset, &value, sizeof(value));
    return YES;
}

static BOOL BMEncodingMatches(Method method, const char *expected) {
    const char *encoding = method ? method_getTypeEncoding(method) : NULL;
    return encoding && expected && strcmp(encoding, expected) == 0;
}

static id BMDeviceSessionFromUserSession(id userSession) {
    if (!userSession) return nil;
    SEL selector = NSSelectorFromString(@"deviceSession");
    Method method = class_getInstanceMethod([userSession class], selector);
    if (!BMEncodingMatches(method, "@16@0:8")) return nil;
    @try { return ((id (*)(id, SEL))objc_msgSend)(userSession, selector); }
    @catch (__unused id exception) { return nil; }
}

static void BMCaptureSessions(id controller) {
    id userSession = BMReadObject(controller, "userSession", 24) ?:
        [SCIDogfoodObjectRuntime activeUserSession];
    id deviceSession = BMReadObject(controller, "deviceSession", 16);
    if (!deviceSession) {
        deviceSession = BMDeviceSessionFromUserSession(userSession);
        if (deviceSession) BMWriteObject(controller, "deviceSession", 16, deviceSession);
    }

    if (deviceSession && deviceSession != sBMDeviceSession) {
        sBMDeviceSession = deviceSession;
        [SCIDogfoodObjectRuntime noteObject:deviceSession
                                       role:@"IGDeviceSession"
                                     source:@"IGBugReportMenu native dependencies"];
    }
    if (userSession && userSession != sBMUserSession) {
        sBMUserSession = userSession;
        [SCIDogfoodObjectRuntime noteLiveUserSession:userSession
                                              source:@"IGBugReportMenu native dependencies"];
    }
}

static void BMApplyNativeState(id controller) {
    if (!controller || !BMAnyOn()) return;
    BMCaptureSessions(controller);

    id userSession = BMReadObject(controller, "userSession", 24) ?:
        sBMUserSession;
    if (BMAvailabilityOn()) {
        BMWriteInteger(controller, "internalSettingsAvailabilityStatus", 120,
                       BMAvailabilityRaw());
    }
    if (BMMenuOn()) {
        BMWriteByte(controller, "showInternalSettings", 128, 1);
        BMWriteByte(controller, "showShakeToReportPreferenceToggle", 130, 1);
    }
    if (BMLoggedOutOn()) {
        BMWriteByte(controller, "showLoggedOutInternalSettings", 129, 1);
    }
    if (BMMasterOn()) {
        BMWriteByte(controller, "showDogfoodingAssistant", 131, 1);
    }

    // rowsGrouped(1) passes both native action-cell enabled predicates.
    BMWriteByte(controller, "maisaUXVariant", 132, 1);

    NSInteger oldStyle = BMReadInteger(controller, "style", 32, 0);
    NSInteger newStyle = oldStyle;
    if (BMMenuOn() && userSession) newStyle = 0;
    else if (BMLoggedOutOn() && !userSession) newStyle = 2;
    else if (oldStyle != 0 && oldStyle != 2) newStyle = 0;
    if (newStyle != oldStyle && BMWriteInteger(controller, "style", 32, newStyle)) {
        [SCIDogfoodObjectRuntime noteAction:@"Internal Settings route"
                                      status:@"normalized native style"
                                      detail:@{ @"from": @(oldStyle), @"to": @(newStyle) }];
    }
}

static NSString *BMTextInView(UIView *view) {
    if ([view isKindOfClass:UILabel.class] && ((UILabel *)view).text.length) {
        return ((UILabel *)view).text;
    }
    for (UIView *child in view.subviews) {
        NSString *value = BMTextInView(child);
        if (value.length) return value;
    }
    return nil;
}

static NSString *BMCellTitle(UITableViewCell *cell) {
    NSString *title = cell.textLabel.text;
    if (!title.length) title = BMTextInView(cell.contentView);
    if (!title.length) title = cell.accessibilityLabel;
    return [title stringByTrimmingCharactersInSet:
        NSCharacterSet.whitespaceAndNewlineCharacterSet];
}

static BOOL BMIsTargetCell(UITableViewCell *cell, NSIndexPath *indexPath) {
    // Prefer exact current-binary sections; title is only a localization-safe
    // fallback for a future layout change.
    if (indexPath.section == 6 || indexPath.section == 7) return YES;
    NSString *title = BMCellTitle(cell);
    return [title isEqualToString:@"Internal Settings"] ||
        [title isEqualToString:@"Dogfooding Assistant"];
}

static void BMEnsureActionCellInteractive(UITableViewCell *cell,
                                          NSIndexPath *indexPath) {
    if (!cell || !BMIsTargetCell(cell, indexPath)) return;
    cell.userInteractionEnabled = YES;
    cell.contentView.userInteractionEnabled = YES;
    cell.selectionStyle = UITableViewCellSelectionStyleDefault;
    cell.accessibilityTraits &= ~UIAccessibilityTraitNotEnabled;
}

static id (*origCellForRow)(id, SEL, UITableView *, NSIndexPath *);
static id newCellForRow(id self, SEL _cmd, UITableView *tableView,
                        NSIndexPath *indexPath) {
    BMApplyNativeState(self);
    UITableViewCell *cell = origCellForRow
        ? origCellForRow(self, _cmd, tableView, indexPath)
        : nil;
    BMEnsureActionCellInteractive(cell, indexPath);
    return cell;
}

static BOOL (*origShouldHighlight)(id, SEL, UITableView *, NSIndexPath *);
static BOOL newShouldHighlight(id self, SEL _cmd, UITableView *tableView,
                               NSIndexPath *indexPath) {
    BMApplyNativeState(self);
    BOOL nativeValue = origShouldHighlight
        ? origShouldHighlight(self, _cmd, tableView, indexPath)
        : NO;
    UITableViewCell *cell = [tableView cellForRowAtIndexPath:indexPath];
    return BMIsTargetCell(cell, indexPath) ? YES : nativeValue;
}

static void (*origDidSelect)(id, SEL, UITableView *, NSIndexPath *);
static void newDidSelect(id self, SEL _cmd, UITableView *tableView,
                         NSIndexPath *indexPath) {
    if (indexPath.section == 6 || indexPath.section == 7) {
        BMApplyNativeState(self);
        [SCIDogfoodObjectRuntime noteAction:
            indexPath.section == 6 ? @"Dogfooding Assistant native tap" :
                                     @"Internal Settings native tap"
                                      status:@"forwarded to original Swift handler"
                                      detail:@(indexPath.section)];
    }
    if (origDidSelect) origDidSelect(self, _cmd, tableView, indexPath);
}

static void BMHook(Class cls, SEL selector, const char *encoding,
                   IMP replacement, IMP *original) {
    if (!cls || !selector || !replacement || !original || *original) return;
    Method method = class_getInstanceMethod(cls, selector);
    if (!BMEncodingMatches(method, encoding)) {
        if (method) BMACTLOG("skip %{public}s ABI=%{public}s",
            sel_getName(selector), method_getTypeEncoding(method));
        return;
    }
    MSHookMessageEx(cls, selector, replacement, original);
}

static void BMInstall(void) {
    @synchronized (SCIDogfoodObjectRuntime.class) {
        Class cls = BMMenuClass();
        BMHook(cls, @selector(tableView:cellForRowAtIndexPath:),
            "@32@0:8@16@24", (IMP)newCellForRow, (IMP *)&origCellForRow);
        BMHook(cls, @selector(tableView:shouldHighlightRowAtIndexPath:),
            "B32@0:8@16@24", (IMP)newShouldHighlight,
            (IMP *)&origShouldHighlight);
        BMHook(cls, @selector(tableView:didSelectRowAtIndexPath:),
            "v32@0:8@16@24", (IMP)newDidSelect, (IMP *)&origDidSelect);
    }
}

static void BMImageLoaded(const struct mach_header *header, intptr_t slide) {
    (void)header; (void)slide;
    BMInstall();
}

__attribute__((constructor))
static void SCIBugMenuOEMActivationCtor(void) {
    @autoreleasepool {
        BMInstall();
        _dyld_register_func_for_add_image(BMImageLoaded);
    }
}
