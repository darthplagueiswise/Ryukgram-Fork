#import "SCIInternalGatePrefs.h"
#import "SCIDogfoodObjectRuntime.h"
#import "../../Utils.h"
#import <UIKit/UIKit.h>
#import <objc/message.h>
#import <objc/runtime.h>
#import <substrate.h>
#import <os/log.h>
#import <stdint.h>
#import <string.h>

#define BMACTLOG(fmt, ...) os_log(OS_LOG_DEFAULT, "[SCIGate] BugMenuActivation " fmt, ##__VA_ARGS__)

// Revalidated against Instagram SHA-256
// a562b3626c663eec47b41ed1bca7a7af6aa00cc30bada3293046f7cce1a555aa.
//
// IGBugReportMenuViewController stores:
//   style                              q @ 0x20
//   internalSettingsAvailabilityStatus q @ 0x78
//   showInternalSettings               B @ 0x80
//   showLoggedOutInternalSettings      B @ 0x81
//   showShakeToReportPreferenceToggle  B @ 0x82
//   showDogfoodingAssistant             B @ 0x83
//   maisaUXVariant                      byte @ 0x84
//
// Native cell construction for action 6 (Dogfooding Assistant) and action 7
// (Internal Settings) enables the row only when maisaUXVariant is neither
// control(0) nor additive(3). Swift reflection names the four cases:
// control(0), rowsGrouped(1), pills(2), additive(3).
// The earlier patch exposed both rows but left raw 0/3 untouched, so they were
// visually present and deliberately disabled by Instagram itself.

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
    NSInteger value = (NSInteger)[SCIUtils getDoublePref:@"sci_internal_settings_availability_raw_value"];
    if (value < 0) return 0;
    if (value > 2) return 2;
    return value;
}

static Ivar BMFindIvar(id object, const char *name) {
    if (!object || !name) return NULL;
    for (Class cls = object_getClass(object); cls; cls = class_getSuperclass(cls)) {
        Ivar ivar = class_getInstanceVariable(cls, name);
        if (ivar) return ivar;
    }
    return NULL;
}

static id BMReadObjectIvar(id object, const char *name) {
    Ivar ivar = BMFindIvar(object, name);
    if (!ivar) return nil;
    const char *encoding = ivar_getTypeEncoding(ivar);
    if (!encoding || encoding[0] != '@') return nil;
    @try { return object_getIvar(object, ivar); }
    @catch (__unused id exception) { return nil; }
}

static BOOL BMWriteIntegerIvar(id object, const char *name, NSInteger value) {
    Ivar ivar = BMFindIvar(object, name);
    if (!ivar) return NO;
    const char *encoding = ivar_getTypeEncoding(ivar);
    if (!encoding || !strchr("qQlL", encoding[0])) return NO;
    uint8_t *base = (__bridge void *)object;
    memcpy(base + ivar_getOffset(ivar), &value, sizeof(value));
    return YES;
}

static BOOL BMWriteByteIvar(id object, const char *name, uint8_t value) {
    Ivar ivar = BMFindIvar(object, name);
    if (!ivar) return NO;
    uint8_t *base = (__bridge void *)object;
    memcpy(base + ivar_getOffset(ivar), &value, sizeof(value));
    return YES;
}

static void BMCaptureSessions(id controller) {
    id deviceSession = BMReadObjectIvar(controller, "deviceSession");
    id userSession = BMReadObjectIvar(controller, "userSession");
    if (deviceSession && deviceSession != sBMDeviceSession) {
        sBMDeviceSession = deviceSession;
        [SCIDogfoodObjectRuntime noteObject:deviceSession
                                       role:@"IGDeviceSession"
                                     source:@"IGBugReportMenuViewController.deviceSession"];
    }
    if (userSession && userSession != sBMUserSession) {
        sBMUserSession = userSession;
        [SCIDogfoodObjectRuntime noteLiveUserSession:userSession
                                              source:@"IGBugReportMenuViewController.userSession"];
    }
}

static void BMApplyNativeState(id controller) {
    if (!controller || !BMAnyOn()) return;
    BMCaptureSessions(controller);

    id userSession = BMReadObjectIvar(controller, "userSession");
    if (BMAvailabilityOn()) {
        BMWriteIntegerIvar(controller, "internalSettingsAvailabilityStatus", BMAvailabilityRaw());
    }
    if (BMMenuOn()) {
        BMWriteByteIvar(controller, "showInternalSettings", 1);
        BMWriteByteIvar(controller, "showShakeToReportPreferenceToggle", 1);
    }
    if (BMLoggedOutOn()) {
        BMWriteByteIvar(controller, "showLoggedOutInternalSettings", 1);
    }
    if (BMMasterOn()) {
        BMWriteByteIvar(controller, "showDogfoodingAssistant", 1);
    }

    // rowsGrouped(1) keeps the native rows while satisfying both native enabled
    // predicates. Do not use control(0) or additive(3): both disable actions 6/7.
    BMWriteByteIvar(controller, "maisaUXVariant", 1);

    // Native Internal Settings action 7 is a style switch:
    // style 0 presents logged-in Internal Settings; style 1 returns; style 2
    // presents Logged Out Internal Settings. Preserve that semantic split.
    if (BMMenuOn() && userSession) {
        BMWriteIntegerIvar(controller, "style", 0);
    } else if (BMLoggedOutOn() && !userSession) {
        BMWriteIntegerIvar(controller, "style", 2);
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
    return [title stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet];
}

static void BMEnsureActionCellInteractive(UITableViewCell *cell) {
    NSString *title = BMCellTitle(cell);
    if (![title isEqualToString:@"Internal Settings"] &&
        ![title isEqualToString:@"Dogfooding Assistant"]) return;
    cell.userInteractionEnabled = YES;
    cell.contentView.userInteractionEnabled = YES;
    cell.selectionStyle = UITableViewCellSelectionStyleDefault;
    cell.accessibilityTraits &= ~UIAccessibilityTraitNotEnabled;
}

static id (*orig_BMCellForRow)(id, SEL, UITableView *, NSIndexPath *) = NULL;
static id new_BMCellForRow(id self, SEL _cmd, UITableView *tableView, NSIndexPath *indexPath) {
    BMApplyNativeState(self);
    UITableViewCell *cell = orig_BMCellForRow
        ? orig_BMCellForRow(self, _cmd, tableView, indexPath)
        : nil;
    BMEnsureActionCellInteractive(cell);
    return cell;
}

static BOOL (*orig_BMShouldHighlight)(id, SEL, UITableView *, NSIndexPath *) = NULL;
static BOOL new_BMShouldHighlight(id self, SEL _cmd, UITableView *tableView, NSIndexPath *indexPath) {
    BMApplyNativeState(self);
    BOOL nativeValue = orig_BMShouldHighlight
        ? orig_BMShouldHighlight(self, _cmd, tableView, indexPath)
        : NO;
    UITableViewCell *cell = [tableView cellForRowAtIndexPath:indexPath];
    NSString *title = BMCellTitle(cell);
    if ([title isEqualToString:@"Internal Settings"] ||
        [title isEqualToString:@"Dogfooding Assistant"]) {
        return YES;
    }
    return nativeValue;
}

static BOOL BMEncodingMatches(Method method, const char *expected) {
    const char *encoding = method ? method_getTypeEncoding(method) : NULL;
    return encoding && expected && strcmp(encoding, expected) == 0;
}

static BOOL BMInstall(void) {
    Class cls = objc_getClass("_TtC17IGBugReporterMenu29IGBugReportMenuViewController");
    if (!cls) cls = objc_getClass("IGBugReportMenuViewController");
    if (!cls) return NO;

    SEL selector = @selector(tableView:cellForRowAtIndexPath:);
    Method method = class_getInstanceMethod(cls, selector);
    if (!BMEncodingMatches(method, "@32@0:8@16@24")) {
        BMACTLOG("cellForRow ABI=%{public}s", method ? method_getTypeEncoding(method) : "missing");
        return NO;
    }
    if (!orig_BMCellForRow) {
        MSHookMessageEx(cls, selector, (IMP)new_BMCellForRow, (IMP *)&orig_BMCellForRow);
    }

    SEL highlightSelector = @selector(tableView:shouldHighlightRowAtIndexPath:);
    Method highlightMethod = class_getInstanceMethod(cls, highlightSelector);
    if (!orig_BMShouldHighlight &&
        BMEncodingMatches(highlightMethod, "B32@0:8@16@24")) {
        MSHookMessageEx(cls, highlightSelector, (IMP)new_BMShouldHighlight,
                        (IMP *)&orig_BMShouldHighlight);
    }
    BMACTLOG("installed cell=%d highlight=%d",
        orig_BMCellForRow != NULL, orig_BMShouldHighlight != NULL);
    return orig_BMCellForRow != NULL && orig_BMShouldHighlight != NULL;
}

__attribute__((constructor))
static void SCIBugMenuOEMActivationCtor(void) {
    @autoreleasepool {
        if (BMInstall()) return;
        __block id token = [[NSNotificationCenter defaultCenter]
            addObserverForName:UIApplicationDidFinishLaunchingNotification
                        object:nil
                         queue:NSOperationQueue.mainQueue
                    usingBlock:^(__unused NSNotification *note) {
            BMInstall();
            if (token) {
                [[NSNotificationCenter defaultCenter] removeObserver:token];
                token = nil;
            }
        }];
    }
}
