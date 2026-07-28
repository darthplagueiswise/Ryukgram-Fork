// SCIInternalBugMenuPreflight.x
// Outermost Bug Reporter guard for the new Instagram build.
//
// SCIEmployeeInternal.x was written before the XPlugins provider ABI was fully
// recovered and can force showDogfoodingAssistant=YES while the Assistant socket
// provider is { NULL, 0 }. This guard is installed one main-queue turn after the
// other constructors, so it remains outermost and prevents the native lifecycle
// from ever observing that unsafe scalar.

#import "../../Utils.h"
#import "SCIDogfoodObjectRuntime.h"
#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>
#import <objc/message.h>
#import <objc/runtime.h>
#import <substrate.h>
#import <dlfcn.h>
#import <stdint.h>
#import <string.h>

typedef struct {
    const void *data;
    uintptr_t count;
} SCIPreflightXPluginsPair;

typedef SCIPreflightXPluginsPair (*SCIPreflightProvider)(void);
typedef void *(*SCIPreflightGetter)(uint32_t hash);

typedef id (*SCIPreflightLegacyInit)(
    id, SEL, id, id, id, id, id, id,
    NSInteger, NSInteger, BOOL, BOOL, BOOL
);

typedef id (*SCIPreflightCurrentInit)(
    id, SEL, id, id, id, id, id, id,
    NSInteger, NSInteger, BOOL, BOOL, BOOL, BOOL, NSInteger
);

static const uint32_t kSCIPreflightAssistantHash = 0x7FBC8058U;
static __thread BOOL sSCIPreflightSuppressLegacyMaster = NO;

static BOOL SCIPreflightMasterOn(void) {
    return [SCIUtils getBoolPref:@"sci_employee_internal"] ||
           [SCIUtils getBoolPref:@"sci_force_ig_internal_employee"] ||
           [SCIUtils getBoolPref:@"sci_force_ig_is_employee"];
}

static BOOL SCIPreflightMenuOn(void) {
    return SCIPreflightMasterOn() ||
           [SCIUtils getBoolPref:@"sci_force_internal_settings_menu"] ||
           [SCIUtils getBoolPref:@"sci_force_internal_settings_availability"];
}

static BOOL SCIPreflightEncoding(Method method, const char *expected) {
    if (!method || !expected) return NO;
    const char *encoding = method_getTypeEncoding(method);
    return encoding && strcmp(encoding, expected) == 0;
}

static SCIPreflightGetter SCIPreflightResolveGetter(void) {
    static SCIPreflightGetter getter = NULL;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        void *symbol = dlsym(RTLD_DEFAULT, "XPluginsGetDataFuncOrAbort");
        if (!symbol) symbol = MSFindSymbol(NULL, "_XPluginsGetDataFuncOrAbort");
        getter = (SCIPreflightGetter)symbol;
    });
    return getter;
}

static BOOL SCIPreflightAssistantPayloadAvailable(void) {
    static BOOL available = NO;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        SCIPreflightGetter getter = SCIPreflightResolveGetter();
        if (!getter) return;
        SCIPreflightProvider provider =
            (SCIPreflightProvider)getter(kSCIPreflightAssistantHash);
        if (!provider) return;
        SCIPreflightXPluginsPair pair = provider();
        available = pair.data != NULL && pair.count != 0;
    });
    return available;
}

static BOOL (*orig_SCIPreflightEmployeeMaster)(id, SEL) = NULL;

static BOOL SCIPreflightEmployeeMaster(id self, SEL _cmd) {
    if (sSCIPreflightSuppressLegacyMaster) return NO;
    return orig_SCIPreflightEmployeeMaster
        ? orig_SCIPreflightEmployeeMaster(self, _cmd)
        : NO;
}

static void SCIPreflightInstallMasterSuppression(void) {
    static BOOL installed = NO;
    if (installed) return;

    Class cls = objc_getClass("SCIInternalGatePrefs");
    Class meta = cls ? object_getClass(cls) : Nil;
    SEL selector = @selector(employeeInternalMasterEnabled);
    Method method = meta ? class_getInstanceMethod(meta, selector) : NULL;
    const char *encoding = method ? method_getTypeEncoding(method) : NULL;
    if (!method || !encoding ||
        (strcmp(encoding, "B16@0:8") != 0 &&
         strcmp(encoding, "c16@0:8") != 0)) {
        return;
    }

    MSHookMessageEx(meta, selector, (IMP)SCIPreflightEmployeeMaster,
                    (IMP *)&orig_SCIPreflightEmployeeMaster);
    installed = orig_SCIPreflightEmployeeMaster != NULL;
}

static BOOL SCIPreflightWriteAssistant(id controller, BOOL value) {
    if (!controller) return NO;
    Ivar ivar = class_getInstanceVariable(
        [controller class], "showDogfoodingAssistant");
    if (!ivar) return NO;
    BOOL normalized = value ? YES : NO;
    uint8_t *bytes = (uint8_t *)(__bridge void *)controller;
    memcpy(bytes + ivar_getOffset(ivar), &normalized, sizeof(normalized));
    return YES;
}

static UITableView *SCIPreflightTable(id controller) {
    if (!controller) return nil;
    Ivar ivar = class_getInstanceVariable([controller class], "tableView");
    if (!ivar) ivar = class_getInstanceVariable([controller class], "_tableView");
    if (!ivar) return nil;
    id value = object_getIvar(controller, ivar);
    return [value isKindOfClass:UITableView.class] ? value : nil;
}

static void SCIPreflightApplyAssistantState(id controller, BOOL reload) {
    if (!controller || SCIPreflightAssistantPayloadAvailable()) return;
    BOOL changed = SCIPreflightWriteAssistant(controller, NO);
    if (changed && reload) {
        UITableView *table = SCIPreflightTable(controller);
        [table reloadData];
        [table setNeedsLayout];
    }
}

static NSString *SCIPreflightText(UIView *view) {
    if ([view isKindOfClass:UILabel.class] && ((UILabel *)view).text.length) {
        return ((UILabel *)view).text;
    }
    for (UIView *child in view.subviews) {
        NSString *text = SCIPreflightText(child);
        if (text.length) return text;
    }
    return nil;
}

static NSString *SCIPreflightCellTitle(UITableViewCell *cell) {
    NSString *title = cell.textLabel.text;
    if (!title.length) title = SCIPreflightText(cell.contentView);
    if (!title.length) title = cell.accessibilityLabel;
    return [title stringByTrimmingCharactersInSet:
        NSCharacterSet.whitespaceAndNewlineCharacterSet];
}

static BOOL SCIPreflightIsAssistantTitle(NSString *title) {
    return title.length &&
        [title caseInsensitiveCompare:@"Dogfooding Assistant"] == NSOrderedSame;
}

static SCIPreflightLegacyInit orig_SCIPreflightLegacy = NULL;
static SCIPreflightCurrentInit orig_SCIPreflightCurrent = NULL;
static void (*orig_SCIPreflightViewDidLoad)(id, SEL) = NULL;
static void (*orig_SCIPreflightViewDidAppear)(id, SEL, BOOL) = NULL;
static void (*orig_SCIPreflightDidSelect)(id, SEL, UITableView *, NSIndexPath *) = NULL;

static id SCIPreflightLegacy(
    id self, SEL _cmd,
    id deviceSession, id userSession, id reliabilityLogging,
    id navChain, id endpoint, id entryPoint,
    NSInteger style, NSInteger availabilityStatus,
    BOOL showInternalSettings, BOOL showLoggedOutInternalSettings,
    BOOL showShakeToReportPreferenceToggle
) {
    if (SCIPreflightMenuOn()) {
        availabilityStatus = 0;
        showInternalSettings = YES;
        showShakeToReportPreferenceToggle = YES;
    }
    if ([SCIUtils getBoolPref:@"sci_force_internal_settings_loggedout"]) {
        showLoggedOutInternalSettings = YES;
    }

    BOOL previous = sSCIPreflightSuppressLegacyMaster;
    sSCIPreflightSuppressLegacyMaster = YES;
    id result = nil;
    @try {
        if (orig_SCIPreflightLegacy) {
            result = orig_SCIPreflightLegacy(
                self, _cmd, deviceSession, userSession, reliabilityLogging,
                navChain, endpoint, entryPoint, style, availabilityStatus,
                showInternalSettings, showLoggedOutInternalSettings,
                showShakeToReportPreferenceToggle);
        }
    } @finally {
        sSCIPreflightSuppressLegacyMaster = previous;
    }
    SCIPreflightApplyAssistantState(result, NO);
    return result;
}

static id SCIPreflightCurrent(
    id self, SEL _cmd,
    id deviceSession, id userSession, id reliabilityLogging,
    id navChain, id endpoint, id entryPoint,
    NSInteger style, NSInteger availabilityStatus,
    BOOL showInternalSettings, BOOL showLoggedOutInternalSettings,
    BOOL showShakeToReportPreferenceToggle,
    BOOL showDogfoodingAssistant, NSInteger maisaUXVariantRawValue
) {
    if (SCIPreflightMenuOn()) {
        availabilityStatus = 0;
        showInternalSettings = YES;
        showShakeToReportPreferenceToggle = YES;
    }
    if ([SCIUtils getBoolPref:@"sci_force_internal_settings_loggedout"]) {
        showLoggedOutInternalSettings = YES;
    }
    if (SCIPreflightMasterOn()) {
        showDogfoodingAssistant = SCIPreflightAssistantPayloadAvailable();
    }

    BOOL previous = sSCIPreflightSuppressLegacyMaster;
    sSCIPreflightSuppressLegacyMaster = YES;
    id result = nil;
    @try {
        if (orig_SCIPreflightCurrent) {
            result = orig_SCIPreflightCurrent(
                self, _cmd, deviceSession, userSession, reliabilityLogging,
                navChain, endpoint, entryPoint, style, availabilityStatus,
                showInternalSettings, showLoggedOutInternalSettings,
                showShakeToReportPreferenceToggle, showDogfoodingAssistant,
                maisaUXVariantRawValue);
        }
    } @finally {
        sSCIPreflightSuppressLegacyMaster = previous;
    }
    SCIPreflightApplyAssistantState(result, NO);
    return result;
}

static void SCIPreflightViewDidLoad(id self, SEL _cmd) {
    SCIPreflightApplyAssistantState(self, NO);
    BOOL previous = sSCIPreflightSuppressLegacyMaster;
    sSCIPreflightSuppressLegacyMaster = YES;
    @try {
        if (orig_SCIPreflightViewDidLoad) {
            orig_SCIPreflightViewDidLoad(self, _cmd);
        }
    } @finally {
        sSCIPreflightSuppressLegacyMaster = previous;
    }
    SCIPreflightApplyAssistantState(self, YES);
}

static void SCIPreflightViewDidAppear(id self, SEL _cmd, BOOL animated) {
    SCIPreflightApplyAssistantState(self, NO);
    BOOL previous = sSCIPreflightSuppressLegacyMaster;
    sSCIPreflightSuppressLegacyMaster = YES;
    @try {
        if (orig_SCIPreflightViewDidAppear) {
            orig_SCIPreflightViewDidAppear(self, _cmd, animated);
        }
    } @finally {
        sSCIPreflightSuppressLegacyMaster = previous;
    }
    SCIPreflightApplyAssistantState(self, YES);
}

static void SCIPreflightDidSelect(
    id self, SEL _cmd, UITableView *tableView, NSIndexPath *indexPath
) {
    UITableViewCell *cell = [tableView cellForRowAtIndexPath:indexPath];
    NSString *title = SCIPreflightCellTitle(cell);
    if (SCIPreflightIsAssistantTitle(title) &&
        !SCIPreflightAssistantPayloadAvailable()) {
        [tableView deselectRowAtIndexPath:indexPath animated:YES];
        [SCIDogfoodObjectRuntime noteAction:@"Dogfooding Assistant"
            status:@"blocked before native handler: empty XPlugins provider"
            detail:@"hash=0x7FBC8058; pair={NULL,0}; brk initializer skipped"];
        return;
    }

    SCIPreflightApplyAssistantState(self, NO);
    BOOL previous = sSCIPreflightSuppressLegacyMaster;
    sSCIPreflightSuppressLegacyMaster = YES;
    @try {
        if (orig_SCIPreflightDidSelect) {
            orig_SCIPreflightDidSelect(self, _cmd, tableView, indexPath);
        }
    } @finally {
        sSCIPreflightSuppressLegacyMaster = previous;
    }
}

static void SCIPreflightInstall(void) {
    static BOOL installed = NO;
    if (installed || !SCIPreflightMenuOn()) return;

    SCIPreflightInstallMasterSuppression();

    Class cls = objc_getClass(
        "_TtC17IGBugReporterMenu29IGBugReportMenuViewController");
    if (!cls) cls = objc_getClass("IGBugReportMenuViewController");
    if (!cls) return;

    SEL legacySelector = NSSelectorFromString(
        @"initWithDeviceSession:userSession:reliabilityLogging:navChain:endpoint:entryPoint:style:internalSettingsAvailabilityStatus:showInternalSettings:showLoggedOutInternalSettings:showShakeToReportPreferenceToggle:");
    Method legacyMethod = class_getInstanceMethod(cls, legacySelector);
    if (!orig_SCIPreflightLegacy && SCIPreflightEncoding(legacyMethod,
        "@92@0:8@16@24@32@40@48@56q64q72B80B84B88")) {
        MSHookMessageEx(cls, legacySelector, (IMP)SCIPreflightLegacy,
                        (IMP *)&orig_SCIPreflightLegacy);
    }

    SEL currentSelector = NSSelectorFromString(
        @"initWithDeviceSession:userSession:reliabilityLogging:navChain:endpoint:entryPoint:style:internalSettingsAvailabilityStatus:showInternalSettings:showLoggedOutInternalSettings:showShakeToReportPreferenceToggle:showDogfoodingAssistant:maisaUXVariantRawValue:");
    Method currentMethod = class_getInstanceMethod(cls, currentSelector);
    if (!orig_SCIPreflightCurrent && SCIPreflightEncoding(currentMethod,
        "@104@0:8@16@24@32@40@48@56q64q72B80B84B88B92q96")) {
        MSHookMessageEx(cls, currentSelector, (IMP)SCIPreflightCurrent,
                        (IMP *)&orig_SCIPreflightCurrent);
    }

    Method loadMethod = class_getInstanceMethod(cls, @selector(viewDidLoad));
    if (!orig_SCIPreflightViewDidLoad &&
        SCIPreflightEncoding(loadMethod, "v16@0:8")) {
        MSHookMessageEx(cls, @selector(viewDidLoad),
                        (IMP)SCIPreflightViewDidLoad,
                        (IMP *)&orig_SCIPreflightViewDidLoad);
    }

    Method appearMethod = class_getInstanceMethod(cls, @selector(viewDidAppear:));
    if (!orig_SCIPreflightViewDidAppear &&
        SCIPreflightEncoding(appearMethod, "v20@0:8B16")) {
        MSHookMessageEx(cls, @selector(viewDidAppear:),
                        (IMP)SCIPreflightViewDidAppear,
                        (IMP *)&orig_SCIPreflightViewDidAppear);
    }

    SEL select = @selector(tableView:didSelectRowAtIndexPath:);
    Method selectMethod = class_getInstanceMethod(cls, select);
    if (!orig_SCIPreflightDidSelect &&
        SCIPreflightEncoding(selectMethod, "v32@0:8@16@24")) {
        MSHookMessageEx(cls, select, (IMP)SCIPreflightDidSelect,
                        (IMP *)&orig_SCIPreflightDidSelect);
    }

    installed = orig_SCIPreflightLegacy || orig_SCIPreflightCurrent ||
                orig_SCIPreflightViewDidLoad ||
                orig_SCIPreflightViewDidAppear ||
                orig_SCIPreflightDidSelect;
}

%ctor {
    @autoreleasepool {
        // Two queue turns guarantee that the one-turn safe bridge and the older
        // synchronous Employee/Internal hook are already installed underneath.
        dispatch_async(dispatch_get_main_queue(), ^{
            dispatch_async(dispatch_get_main_queue(), ^{
                SCIPreflightInstall();
            });
        });
    }
}
