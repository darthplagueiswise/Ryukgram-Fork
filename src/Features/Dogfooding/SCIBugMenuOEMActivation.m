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

// Revalidated with radare2 5.9.8 and independently with Capstone 5.0.7
// against Instagram SHA-256
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
// The Swift jump-table action tags are 6 (Dogfooding Assistant) and 7
// (Internal Settings). They are NOT NSIndexPath.section values. The native
// shouldHighlight implementation explicitly rejects both tags through mask
// 0xe017, so merely setting show* ivars can render disabled-looking rows without
// ever reaching didSelect. We identify the rendered cells by their exact current
// binary titles, tag those cell objects, make only those cells interactive, and
// still forward execution to Instagram's original Swift handler.

static __weak id sBMDeviceSession;
static __weak id sBMUserSession;

id SCIEmployeeInternalCapturedDeviceSession(void) { return sBMDeviceSession; }
id SCIEmployeeInternalCapturedUserSession(void) { return sBMUserSession; }

typedef NS_ENUM(NSInteger, BMTargetKind) {
    BMTargetKindNone = 0,
    BMTargetKindDogfoodingAssistant = 1,
    BMTargetKindInternalSettings = 2,
};

static const void *kBMTargetKindKey = &kBMTargetKindKey;

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

static NSString *BMNormalizedEncoding(const char *encoding) {
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

static BOOL BMEncodingMatches(Method method, const char *expected) {
    return method && expected &&
        [BMNormalizedEncoding(method_getTypeEncoding(method))
            isEqualToString:BMNormalizedEncoding(expected)];
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
    id userSession = BMReadObject(controller, "userSession", 0x18) ?:
        [SCIDogfoodObjectRuntime activeUserSession];
    id deviceSession = BMReadObject(controller, "deviceSession", 0x10);
    if (!deviceSession) {
        deviceSession = BMDeviceSessionFromUserSession(userSession);
        if (deviceSession) BMWriteObject(controller, "deviceSession", 0x10, deviceSession);
    }

    if (deviceSession && deviceSession != sBMDeviceSession) {
        sBMDeviceSession = deviceSession;
        [SCIDogfoodObjectRuntime noteObject:deviceSession
                                       role:@"IGDeviceSession"
                                     source:@"IGBugReportMenu exact Swift slots"];
    }
    if (userSession && userSession != sBMUserSession) {
        sBMUserSession = userSession;
        [SCIDogfoodObjectRuntime noteLiveUserSession:userSession
                                              source:@"IGBugReportMenu exact Swift slots"];
    }
}

static void BMApplyNativeState(id controller) {
    if (!controller || !BMAnyOn()) return;
    BMCaptureSessions(controller);

    id userSession = BMReadObject(controller, "userSession", 0x18) ?:
        sBMUserSession;
    if (BMAvailabilityOn()) {
        BMWriteInteger(controller, "internalSettingsAvailabilityStatus", 0x78,
                       BMAvailabilityRaw());
    }
    if (BMMenuOn()) {
        BMWriteByte(controller, "showInternalSettings", 0x80, 1);
        BMWriteByte(controller, "showShakeToReportPreferenceToggle", 0x82, 1);
    }
    if (BMLoggedOutOn()) {
        BMWriteByte(controller, "showLoggedOutInternalSettings", 0x81, 1);
    }
    if (BMMasterOn()) {
        BMWriteByte(controller, "showDogfoodingAssistant", 0x83, 1);
    }

    // rowsGrouped(1) satisfies both native action-cell enabled predicates.
    BMWriteByte(controller, "maisaUXVariant", 0x84, 1);

    NSInteger oldStyle = BMReadInteger(controller, "style", 0x20, 0);
    NSInteger newStyle = oldStyle;
    if (userSession && BMMenuOn()) newStyle = 0;
    else if (!userSession && (BMLoggedOutOn() || BMMenuOn())) newStyle = 2;
    else if (oldStyle != 0 && oldStyle != 2) newStyle = userSession ? 0 : 2;
    if (newStyle != oldStyle && BMWriteInteger(controller, "style", 0x20, newStyle)) {
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
    if (!cell) return nil;
    NSString *title = cell.textLabel.text;
    if (!title.length) {
        id configuration = cell.contentConfiguration;
        SEL textSelector = NSSelectorFromString(@"text");
        if ([configuration respondsToSelector:textSelector]) {
            @try {
                id value = ((id (*)(id, SEL))objc_msgSend)(configuration, textSelector);
                if ([value isKindOfClass:NSString.class]) title = value;
            } @catch (__unused id exception) {}
        }
    }
    if (!title.length) title = BMTextInView(cell.contentView);
    if (!title.length) title = cell.accessibilityLabel;
    return [title stringByTrimmingCharactersInSet:
        NSCharacterSet.whitespaceAndNewlineCharacterSet];
}

static BMTargetKind BMTargetFromTitle(NSString *title) {
    if (!title.length) return BMTargetKindNone;
    if ([title caseInsensitiveCompare:@"Dogfooding Assistant"] == NSOrderedSame) {
        return BMTargetKindDogfoodingAssistant;
    }
    if ([title caseInsensitiveCompare:@"Internal Settings"] == NSOrderedSame) {
        return BMTargetKindInternalSettings;
    }
    return BMTargetKindNone;
}

static BMTargetKind BMTagCell(UITableViewCell *cell) {
    if (!cell) return BMTargetKindNone;
    BMTargetKind target = BMTargetFromTitle(BMCellTitle(cell));
    objc_setAssociatedObject(cell, kBMTargetKindKey, @(target),
                             OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    return target;
}

static BMTargetKind BMTargetForCell(UITableViewCell *cell) {
    NSNumber *tag = objc_getAssociatedObject(cell, kBMTargetKindKey);
    BMTargetKind target = tag ? (BMTargetKind)tag.integerValue : BMTargetKindNone;
    return target != BMTargetKindNone ? target : BMTagCell(cell);
}

static BOOL BMTargetEnabled(BMTargetKind target) {
    switch (target) {
        case BMTargetKindDogfoodingAssistant: return BMMasterOn();
        case BMTargetKindInternalSettings:
            return BMMenuOn() || BMAvailabilityOn() || BMLoggedOutOn();
        default: return NO;
    }
}

static void BMEnableCell(UITableViewCell *cell, BMTargetKind target) {
    if (!cell || !BMTargetEnabled(target)) return;
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
    BMTargetKind target = BMTagCell(cell);
    BMEnableCell(cell, target);
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
    BMTargetKind target = BMTargetForCell(cell);
    if (BMTargetEnabled(target)) {
        BMEnableCell(cell, target);
        return YES;
    }
    return nativeValue;
}

static void BMPrepareExactTarget(id controller, BMTargetKind target) {
    BMApplyNativeState(controller);
    BMCaptureSessions(controller);

    if (target == BMTargetKindDogfoodingAssistant && BMMasterOn()) {
        BMWriteByte(controller, "showDogfoodingAssistant", 0x83, 1);
        BMWriteByte(controller, "maisaUXVariant", 0x84, 1);
        return;
    }

    if (target != BMTargetKindInternalSettings || !BMTargetEnabled(target)) return;

    // didSelect action 7 is exact: raw 0 opens, raw 1/3 silently return and raw
    // 2 presents access denied. A forced actionable tap must therefore use 0,
    // regardless of the diagnostic stepper value used while inspecting rows.
    BMWriteInteger(controller, "internalSettingsAvailabilityStatus", 0x78, 0);
    BMWriteByte(controller, "showInternalSettings", 0x80, 1);
    BMWriteByte(controller, "showShakeToReportPreferenceToggle", 0x82, 1);
    BMWriteByte(controller, "maisaUXVariant", 0x84, 1);

    id userSession = BMReadObject(controller, "userSession", 0x18) ?:
        sBMUserSession;
    if (userSession) {
        BMWriteInteger(controller, "style", 0x20, 0);
    } else {
        BMWriteInteger(controller, "style", 0x20, 2);
        BMWriteByte(controller, "showLoggedOutInternalSettings", 0x81, 1);
    }
}

static void (*origDidSelect)(id, SEL, UITableView *, NSIndexPath *);
static void newDidSelect(id self, SEL _cmd, UITableView *tableView,
                         NSIndexPath *indexPath) {
    UITableViewCell *cell = [tableView cellForRowAtIndexPath:indexPath];
    BMTargetKind target = BMTargetForCell(cell);
    if (BMTargetEnabled(target)) {
        BMPrepareExactTarget(self, target);
        [SCIDogfoodObjectRuntime noteAction:
            target == BMTargetKindDogfoodingAssistant
                ? @"Dogfooding Assistant native tap"
                : @"Internal Settings native tap"
                                      status:@"forwarded to original Swift handler"
                                      detail:@{ @"title": BMCellTitle(cell) ?: @"",
                                                @"section": @(indexPath.section),
                                                @"row": @(indexPath.row) }];
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
