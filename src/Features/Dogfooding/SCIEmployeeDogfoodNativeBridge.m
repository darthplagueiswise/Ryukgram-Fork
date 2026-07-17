#import "SCIInternalGatePrefs.h"
#import "SCIDogfoodObjectRuntime.h"
#import "SCIInternalMenusLauncher.h"
#import "../Gating/SCICSymbolStub.h"
#import "../../Utils.h"
#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>
#import <objc/message.h>
#import <objc/runtime.h>
#import <substrate.h>
#import <os/log.h>
#import <string.h>

#define EDBLOG(fmt, ...) os_log(OS_LOG_DEFAULT, "[SCIGate] EmployeeDogfoodBridge " fmt, ##__VA_ARGS__)

#pragma mark - Live sessions consumed by the exact sessionless C bridge

static __weak id sEDBCapturedDeviceSession;
static __weak id sEDBCapturedUserSession;

id SCIEmployeeInternalCapturedDeviceSession(void) {
    return sEDBCapturedDeviceSession;
}

id SCIEmployeeInternalCapturedUserSession(void) {
    return sEDBCapturedUserSession;
}

static BOOL EDBMasterOn(void) {
    return [SCIInternalGatePrefs employeeInternalMasterEnabled];
}

static BOOL EDBMenuOn(void) {
    return EDBMasterOn() || [SCIUtils getBoolPref:@"sci_force_internal_settings_menu"];
}

static BOOL EDBAvailabilityOn(void) {
    return EDBMenuOn() || [SCIUtils getBoolPref:@"sci_force_internal_settings_availability"];
}

static BOOL EDBLoggedOutOn(void) {
    return [SCIUtils getBoolPref:@"sci_force_internal_settings_loggedout"];
}

static BOOL EDBAnyOn(void) {
    return EDBMasterOn() || EDBMenuOn() || EDBAvailabilityOn() || EDBLoggedOutOn();
}

static NSInteger EDBAvailabilityRawValue(void) {
    NSInteger raw = (NSInteger)[SCIUtils getDoublePref:@"sci_internal_settings_availability_raw_value"];
    if (raw < 0) return 0;
    if (raw > 2) return 2;
    return raw;
}

static void EDBCaptureSessions(id deviceSession, id userSession, NSString *source) {
    if (deviceSession) {
        sEDBCapturedDeviceSession = deviceSession;
        [SCIDogfoodObjectRuntime noteObject:deviceSession
                                       role:@"IGDeviceSession"
                                     source:source ?: @"IGBugReportMenuViewController"];
    }
    if (userSession) {
        sEDBCapturedUserSession = userSession;
        [SCIDogfoodObjectRuntime noteLiveUserSession:userSession
                                             source:source ?: @"IGBugReportMenuViewController"];
    }
}

#pragma mark - Exact ABI utilities

static NSString *EDBNormalizedEncoding(const char *encoding) {
    if (!encoding) return @"";
    NSMutableString *out = [NSMutableString string];
    const char *p = encoding;
    while (*p) {
        if (*p != '@') {
            [out appendFormat:@"%c", *p++];
            continue;
        }
        [out appendString:@"@"]; p++;
        if (*p == '"') {
            p++;
            while (*p && *p != '"') p++;
            if (*p == '"') p++;
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

static BOOL EDBMethodMatches(Method method, const char *expected) {
    return method && expected &&
        [EDBNormalizedEncoding(method_getTypeEncoding(method))
            isEqualToString:EDBNormalizedEncoding(expected)];
}

static BOOL EDBIsBoolGetter(Method method) {
    return EDBMethodMatches(method, "B16@0:8") ||
           EDBMethodMatches(method, "c16@0:8") ||
           EDBMethodMatches(method, "C16@0:8");
}

static BOOL EDBIsBoolSetter(Method method) {
    return EDBMethodMatches(method, "v20@0:8B16") ||
           EDBMethodMatches(method, "v20@0:8c16") ||
           EDBMethodMatches(method, "v20@0:8C16");
}

#pragma mark - Exact existing employee/test/dogfood/internal getters

static NSMutableDictionary<NSString *, NSValue *> *EDBGetterOriginals(void) {
    static NSMutableDictionary<NSString *, NSValue *> *store;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{ store = [NSMutableDictionary dictionary]; });
    return store;
}

static NSMutableDictionary<NSString *, NSValue *> *EDBSetterOriginals(void) {
    static NSMutableDictionary<NSString *, NSValue *> *store;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{ store = [NSMutableDictionary dictionary]; });
    return store;
}

static NSString *EDBMethodKey(Class cls, SEL selector) {
    return [NSString stringWithFormat:@"%@#%@",
        NSStringFromClass(cls) ?: @"<nil>",
        NSStringFromSelector(selector) ?: @"<nil>"];
}

static Class EDBDeclaringClass(Class cls, SEL selector) {
    for (Class current = cls; current; current = class_getSuperclass(current)) {
        unsigned int count = 0;
        Method *methods = class_copyMethodList(current, &count);
        BOOL found = NO;
        for (unsigned int i = 0; methods && i < count; i++) {
            if (method_getName(methods[i]) == selector) { found = YES; break; }
        }
        if (methods) free(methods);
        if (found) return current;
    }
    return Nil;
}

static IMP EDBOriginalForReceiver(id receiver, SEL selector,
                                  NSMutableDictionary<NSString *, NSValue *> *store) {
    for (Class cls = object_getClass(receiver); cls; cls = class_getSuperclass(cls)) {
        NSValue *value = store[EDBMethodKey(cls, selector)];
        if (value) return value.pointerValue;
    }
    return NULL;
}

static BOOL EDBForcedBoolGetter(id self, SEL _cmd) {
    if (EDBMasterOn()) return YES;
    IMP original = NULL;
    NSMutableDictionary<NSString *, NSValue *> *store = EDBGetterOriginals();
    @synchronized (store) {
        original = EDBOriginalForReceiver(self, _cmd, store);
    }
    return original ? ((BOOL (*)(id, SEL))original)(self, _cmd) : NO;
}

static void EDBForcedBoolSetter(id self, SEL _cmd, BOOL value) {
    IMP original = NULL;
    NSMutableDictionary<NSString *, NSValue *> *store = EDBSetterOriginals();
    @synchronized (store) {
        original = EDBOriginalForReceiver(self, _cmd, store);
    }
    if (original) ((void (*)(id, SEL, BOOL))original)(self, _cmd,
        EDBMasterOn() ? YES : value);
}

static BOOL EDBInstallGetterOnClass(Class cls, NSString *selectorName) {
    SEL selector = NSSelectorFromString(selectorName);
    Class owner = EDBDeclaringClass(cls, selector);
    if (!owner) return NO;

    Method method = class_getInstanceMethod(owner, selector);
    if (!EDBIsBoolGetter(method)) return NO;

    NSString *key = EDBMethodKey(owner, selector);
    NSMutableDictionary<NSString *, NSValue *> *store = EDBGetterOriginals();
    @synchronized (store) {
        if (store[key]) return YES;
    }

    IMP original = NULL;
    MSHookMessageEx(owner, selector, (IMP)EDBForcedBoolGetter, &original);
    if (!original) return NO;
    @synchronized (store) { store[key] = [NSValue valueWithPointer:original]; }
    EDBLOG("getter %{public}s.%{public}s ABI=%{public}s",
        class_getName(owner), sel_getName(selector), method_getTypeEncoding(method));
    return YES;
}

static BOOL EDBInstallSetterOnClass(Class cls, NSString *selectorName) {
    SEL selector = NSSelectorFromString(selectorName);
    Class owner = EDBDeclaringClass(cls, selector);
    if (!owner) return NO;

    Method method = class_getInstanceMethod(owner, selector);
    if (!EDBIsBoolSetter(method)) return NO;

    NSString *key = EDBMethodKey(owner, selector);
    NSMutableDictionary<NSString *, NSValue *> *store = EDBSetterOriginals();
    @synchronized (store) {
        if (store[key]) return YES;
    }

    IMP original = NULL;
    MSHookMessageEx(owner, selector, (IMP)EDBForcedBoolSetter, &original);
    if (!original) return NO;
    @synchronized (store) { store[key] = [NSValue valueWithPointer:original]; }
    EDBLOG("setter %{public}s.%{public}s ABI=%{public}s",
        class_getName(owner), sel_getName(selector), method_getTypeEncoding(method));
    return YES;
}

static BOOL EDBIdentityClassNameIsRelevant(Class cls) {
    NSString *name = NSStringFromClass(cls).lowercaseString ?: @"";
    return [name containsString:@"user"] ||
           [name containsString:@"session"] ||
           [name containsString:@"account"] ||
           [name containsString:@"employee"] ||
           [name containsString:@"dogfood"] ||
           [name containsString:@"internal"] ||
           [name containsString:@"identity"] ||
           [name containsString:@"bugreport"] ||
           [name containsString:@"facebookuserinfo"] ||
           [name containsString:@"adplatformlogger"];
}

static NSUInteger EDBInstallIdentityHooksForClass(Class cls) {
    if (!cls || !EDBIdentityClassNameIsRelevant(cls)) return 0;
    static NSArray<NSString *> *getters;
    static NSArray<NSString *> *setters;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        getters = @[
            @"isEmployee",
            @"isTestUser",
            @"isEmployeeOrTestUser",
            @"isDogfooder",
            @"isDogfood",
            @"isDogfooding",
            @"isInternalUser",
            @"isInternal",
            @"isMetaEmployee",
            @"isFacebookEmployee"
        ];
        setters = @[
            @"setIsEmployee:",
            @"setIsTestUser:",
            @"setIsEmployeeOrTestUser:",
            @"setIsDogfooder:",
            @"setIsDogfood:",
            @"setIsDogfooding:",
            @"setIsInternalUser:",
            @"setIsInternal:"
        ];
    });

    NSUInteger installed = 0;
    for (NSString *name in getters) installed += EDBInstallGetterOnClass(cls, name);
    for (NSString *name in setters) installed += EDBInstallSetterOnClass(cls, name);
    return installed;
}

static void EDBSyncParamDescriptors(void) {
    static NSString *const ownerKey = @"sci_employee_identity_descriptor_owner";
    NSUserDefaults *defaults = NSUserDefaults.standardUserDefaults;
    BOOL owned = [defaults boolForKey:ownerKey];
    BOOL enabled = EDBMasterOn();

    if (enabled) {
        for (NSString *symbol in @[@"ig_is_employee", @"ig_is_employee_or_test_user"]) {
            if (![[SCICSymbolStub forceForParamDescriptorSymbol:symbol] isEqual:@YES]) {
                [SCICSymbolStub setParamDescriptorForce:@YES forSymbol:symbol];
            }
        }
        if (!owned) [defaults setBool:YES forKey:ownerKey];
    } else if (owned) {
        [SCICSymbolStub setParamDescriptorForce:nil forSymbol:@"ig_is_employee"];
        [SCICSymbolStub setParamDescriptorForce:nil forSymbol:@"ig_is_employee_or_test_user"];
        [defaults removeObjectForKey:ownerKey];
    }
}

static void EDBInstallIdentityHooksNow(void) {
    static BOOL installing = NO;
    static BOOL lastMaster = NO;
    static int lastClassCount = -1;
    if (installing) return;
    installing = YES;

    BOOL enabled = EDBMasterOn();
    if (!enabled) {
        EDBSyncParamDescriptors();
        lastMaster = NO;
        lastClassCount = -1;
        installing = NO;
        return;
    }

    int count = objc_getClassList(NULL, 0);
    if (count <= 0) {
        EDBSyncParamDescriptors();
        installing = NO;
        return;
    }
    if (lastMaster && lastClassCount == count) {
        EDBSyncParamDescriptors();
        installing = NO;
        return;
    }

    __unsafe_unretained Class *classes =
        (__unsafe_unretained Class *)calloc((size_t)count, sizeof(Class));
    count = objc_getClassList(classes, count);
    NSUInteger installed = 0;
    for (int i = 0; i < count; i++) {
        installed += EDBInstallIdentityHooksForClass(classes[i]);
    }
    free(classes);
    EDBSyncParamDescriptors();
    lastMaster = YES;
    lastClassCount = count;
    installing = NO;
    EDBLOG("identity rescan installed/active=%lu classes=%d",
        (unsigned long)installed, count);
}

#pragma mark - Type-aware live bug-menu state

static Ivar EDBFindIvar(Class cls, NSString *name) {
    if (!cls || !name.length) return NULL;
    NSArray<NSString *> *candidates = [name hasPrefix:@"_"]
        ? @[name]
        : @[name, [@"_" stringByAppendingString:name]];
    for (Class current = cls; current; current = class_getSuperclass(current)) {
        for (NSString *candidate in candidates) {
            Ivar ivar = class_getInstanceVariable(current, candidate.UTF8String);
            if (ivar) return ivar;
        }
    }
    return NULL;
}

static BOOL EDBWriteBoolIvar(id object, NSString *name, BOOL value) {
    Ivar ivar = object ? EDBFindIvar(object_getClass(object), name) : NULL;
    if (!ivar) return NO;
    const char *type = ivar_getTypeEncoding(ivar);
    if (!type || (type[0] != 'B' && type[0] != 'c' && type[0] != 'C')) return NO;
    uint8_t normalized = value ? 1 : 0;
    uint8_t *bytes = (__bridge void *)object;
    memcpy(bytes + ivar_getOffset(ivar), &normalized, sizeof(normalized));
    return YES;
}

static BOOL EDBWriteIntegerIvar(id object, NSString *name, NSInteger value) {
    Ivar ivar = object ? EDBFindIvar(object_getClass(object), name) : NULL;
    if (!ivar) return NO;
    const char *type = ivar_getTypeEncoding(ivar);
    if (!type) return NO;
    uint8_t *bytes = (__bridge void *)object;
    ptrdiff_t offset = ivar_getOffset(ivar);
    switch (type[0]) {
        case 'q': { int64_t v = (int64_t)value; memcpy(bytes + offset, &v, sizeof(v)); return YES; }
        case 'Q': { uint64_t v = (uint64_t)value; memcpy(bytes + offset, &v, sizeof(v)); return YES; }
        case 'i': { int32_t v = (int32_t)value; memcpy(bytes + offset, &v, sizeof(v)); return YES; }
        case 'I': { uint32_t v = (uint32_t)value; memcpy(bytes + offset, &v, sizeof(v)); return YES; }
        case 's': { int16_t v = (int16_t)value; memcpy(bytes + offset, &v, sizeof(v)); return YES; }
        case 'S': { uint16_t v = (uint16_t)value; memcpy(bytes + offset, &v, sizeof(v)); return YES; }
        case 'c': { int8_t v = (int8_t)value; memcpy(bytes + offset, &v, sizeof(v)); return YES; }
        case 'C': { uint8_t v = (uint8_t)value; memcpy(bytes + offset, &v, sizeof(v)); return YES; }
        default: return NO;
    }
}

static id EDBObjectIvar(id object, NSString *name) {
    Ivar ivar = object ? EDBFindIvar(object_getClass(object), name) : NULL;
    if (!ivar) return nil;
    const char *type = ivar_getTypeEncoding(ivar);
    if (!type || type[0] != '@') return nil;
    @try { return object_getIvar(object, ivar); }
    @catch (__unused id exception) { return nil; }
}

static void EDBApplyLiveState(id controller, BOOL reload) {
    if (!controller || !EDBAnyOn()) return;
    BOOL changed = NO;
    if (EDBAvailabilityOn()) {
        changed |= EDBWriteIntegerIvar(controller,
            @"internalSettingsAvailabilityStatus", EDBAvailabilityRawValue());
    }
    if (EDBMenuOn()) {
        changed |= EDBWriteBoolIvar(controller, @"showInternalSettings", YES);
        changed |= EDBWriteBoolIvar(controller,
            @"showShakeToReportPreferenceToggle", YES);
    }
    if (EDBLoggedOutOn()) {
        changed |= EDBWriteBoolIvar(controller, @"showLoggedOutInternalSettings", YES);
    }
    if (EDBMasterOn()) {
        changed |= EDBWriteBoolIvar(controller, @"showDogfoodingAssistant", YES);
    }

    id deviceSession = EDBObjectIvar(controller, @"deviceSession");
    id userSession = EDBObjectIvar(controller, @"userSession");
    EDBCaptureSessions(deviceSession, userSession, @"IGBugReportMenuViewController live state");

    if (reload && changed) {
        UITableView *tableView = EDBObjectIvar(controller, @"tableView");
        if ([tableView isKindOfClass:UITableView.class]) {
            [tableView reloadData];
            [tableView setNeedsLayout];
        }
    }
}

static NSString *EDBTextInView(UIView *view) {
    if (!view) return nil;
    if ([view isKindOfClass:UILabel.class] && ((UILabel *)view).text.length) {
        return ((UILabel *)view).text;
    }
    for (UIView *child in view.subviews) {
        NSString *value = EDBTextInView(child);
        if (value.length) return value;
    }
    return nil;
}

static NSString *EDBCellTitle(UITableViewCell *cell) {
    if (!cell) return nil;
    NSString *title = cell.textLabel.text;
    if (!title.length) {
        id configuration = cell.contentConfiguration;
        SEL selector = NSSelectorFromString(@"text");
        if ([configuration respondsToSelector:selector]) {
            @try {
                id value = ((id (*)(id, SEL))objc_msgSend)(configuration, selector);
                if ([value isKindOfClass:NSString.class]) title = value;
            } @catch (__unused id exception) {}
        }
    }
    if (!title.length) title = EDBTextInView(cell.contentView);
    if (!title.length) title = cell.accessibilityLabel;
    return [title stringByTrimmingCharactersInSet:
        NSCharacterSet.whitespaceAndNewlineCharacterSet];
}

static BOOL EDBTitleEquals(NSString *title, NSString *expected) {
    return title.length && expected.length &&
        [title caseInsensitiveCompare:expected] == NSOrderedSame;
}

#pragma mark - Bug reporter hooks

typedef id (*EDBLegacyInitIMP)(id, SEL, id, id, id, id, id, id,
                               NSInteger, NSInteger, BOOL, BOOL, BOOL);
typedef id (*EDBCurrentInitIMP)(id, SEL, id, id, id, id, id, id,
                                NSInteger, NSInteger, BOOL, BOOL, BOOL, BOOL,
                                NSInteger);

static EDBLegacyInitIMP origEDBLegacyInit = NULL;
static EDBCurrentInitIMP origEDBCurrentInit = NULL;
static void (*origEDBViewDidLoad)(id, SEL) = NULL;
static void (*origEDBViewDidAppear)(id, SEL, BOOL) = NULL;
static BOOL (*origEDBShouldHighlight)(id, SEL, UITableView *, NSIndexPath *) = NULL;
static void (*origEDBDidSelect)(id, SEL, UITableView *, NSIndexPath *) = NULL;

static id EDBLegacyInit(id self, SEL _cmd,
                        id deviceSession, id userSession, id reliabilityLogging,
                        id navChain, id endpoint, id entryPoint,
                        NSInteger style, NSInteger availability,
                        BOOL showInternal, BOOL showLoggedOut, BOOL showShake) {
    EDBCaptureSessions(deviceSession, userSession, @"legacy bug-menu initializer");
    if (EDBAvailabilityOn()) availability = EDBAvailabilityRawValue();
    if (EDBMenuOn()) { showInternal = YES; showShake = YES; }
    if (EDBLoggedOutOn()) showLoggedOut = YES;
    id result = origEDBLegacyInit
        ? origEDBLegacyInit(self, _cmd, deviceSession, userSession,
            reliabilityLogging, navChain, endpoint, entryPoint, style,
            availability, showInternal, showLoggedOut, showShake)
        : nil;
    EDBApplyLiveState(result, NO);
    EDBInstallIdentityHooksNow();
    return result;
}

static id EDBCurrentInit(id self, SEL _cmd,
                         id deviceSession, id userSession, id reliabilityLogging,
                         id navChain, id endpoint, id entryPoint,
                         NSInteger style, NSInteger availability,
                         BOOL showInternal, BOOL showLoggedOut, BOOL showShake,
                         BOOL showAssistant, NSInteger maisaVariant) {
    EDBCaptureSessions(deviceSession, userSession, @"current bug-menu initializer");
    if (EDBAvailabilityOn()) availability = EDBAvailabilityRawValue();
    if (EDBMenuOn()) { showInternal = YES; showShake = YES; }
    if (EDBLoggedOutOn()) showLoggedOut = YES;
    if (EDBMasterOn()) showAssistant = YES;
    id result = origEDBCurrentInit
        ? origEDBCurrentInit(self, _cmd, deviceSession, userSession,
            reliabilityLogging, navChain, endpoint, entryPoint, style,
            availability, showInternal, showLoggedOut, showShake,
            showAssistant, maisaVariant)
        : nil;
    EDBApplyLiveState(result, NO);
    EDBInstallIdentityHooksNow();
    return result;
}

static void EDBViewDidLoad(id self, SEL _cmd) {
    EDBApplyLiveState(self, NO);
    if (origEDBViewDidLoad) origEDBViewDidLoad(self, _cmd);
    EDBApplyLiveState(self, YES);
}

static void EDBViewDidAppear(id self, SEL _cmd, BOOL animated) {
    EDBApplyLiveState(self, NO);
    if (origEDBViewDidAppear) origEDBViewDidAppear(self, _cmd, animated);
    EDBApplyLiveState(self, YES);
    EDBInstallIdentityHooksNow();
}

static BOOL EDBShouldHighlight(id self, SEL _cmd,
                               UITableView *tableView, NSIndexPath *indexPath) {
    UITableViewCell *cell = [tableView cellForRowAtIndexPath:indexPath];
    NSString *title = EDBCellTitle(cell);

    if (EDBTitleEquals(title, @"Internal Settings") &&
        EDBMenuOn() && EDBAvailabilityRawValue() == 0) {
        return YES;
    }
    if (EDBTitleEquals(title, @"Dogfooding Assistant") && EDBMasterOn()) {
        return YES;
    }
    if (EDBTitleEquals(title, @"Logged Out Internal Settings") && EDBLoggedOutOn()) {
        return YES;
    }
    return origEDBShouldHighlight
        ? origEDBShouldHighlight(self, _cmd, tableView, indexPath)
        : YES;
}

static void EDBDidSelect(id self, SEL _cmd,
                         UITableView *tableView, NSIndexPath *indexPath) {
    EDBApplyLiveState(self, NO);
    EDBInstallIdentityHooksNow();

    UITableViewCell *cell = [tableView cellForRowAtIndexPath:indexPath];
    NSString *title = EDBCellTitle(cell);
    if (EDBTitleEquals(title, @"Internal Settings") && EDBMenuOn()) {
        NSString *result = [SCIInternalMenusLauncher
            openInternalURLString:@"instagram://internal_settings"];
        if ([result hasPrefix:@"opened:"]) {
            [tableView deselectRowAtIndexPath:indexPath animated:YES];
            [SCIDogfoodObjectRuntime noteAction:@"Internal Settings"
                                          status:@"opened through native IGURLHandler"
                                          detail:result];
            return;
        }
        [SCIDogfoodObjectRuntime noteAction:@"Internal Settings native URL"
                                      status:@"falling back to native row handler"
                                      detail:result];
    }

    if (origEDBDidSelect) origEDBDidSelect(self, _cmd, tableView, indexPath);
}

static BOOL EDBHookInstanceMethod(Class cls, NSString *name, const char *expected,
                                  IMP replacement, IMP *original) {
    if (!cls || !name.length || !expected || !replacement || !original) return NO;
    if (*original != NULL) return YES;
    SEL selector = NSSelectorFromString(name);
    Method method = class_getInstanceMethod(cls, selector);
    if (!EDBMethodMatches(method, expected)) {
        if (method) EDBLOG("skip %{public}s.%{public}s ABI=%{public}s",
            class_getName(cls), sel_getName(selector), method_getTypeEncoding(method));
        return NO;
    }
    MSHookMessageEx(cls, selector, replacement, original);
    return *original != NULL;
}

static void EDBInstallBugMenuHooks(void) {
    Class cls = NSClassFromString(@"_TtC17IGBugReporterMenu29IGBugReportMenuViewController");
    if (!cls) cls = NSClassFromString(@"IGBugReportMenuViewController");
    if (!cls) return;

    BOOL legacy = EDBHookInstanceMethod(cls,
        @"initWithDeviceSession:userSession:reliabilityLogging:navChain:endpoint:entryPoint:style:internalSettingsAvailabilityStatus:showInternalSettings:showLoggedOutInternalSettings:showShakeToReportPreferenceToggle:",
        "@92@0:8@16@24@32@40@48@56q64q72B80B84B88",
        (IMP)EDBLegacyInit, (IMP *)&origEDBLegacyInit);
    BOOL current = EDBHookInstanceMethod(cls,
        @"initWithDeviceSession:userSession:reliabilityLogging:navChain:endpoint:entryPoint:style:internalSettingsAvailabilityStatus:showInternalSettings:showLoggedOutInternalSettings:showShakeToReportPreferenceToggle:showDogfoodingAssistant:maisaUXVariantRawValue:",
        "@104@0:8@16@24@32@40@48@56q64q72B80B84B88B92q96",
        (IMP)EDBCurrentInit, (IMP *)&origEDBCurrentInit);
    BOOL load = EDBHookInstanceMethod(cls, @"viewDidLoad", "v16@0:8",
        (IMP)EDBViewDidLoad, (IMP *)&origEDBViewDidLoad);
    BOOL appear = EDBHookInstanceMethod(cls, @"viewDidAppear:", "v20@0:8B16",
        (IMP)EDBViewDidAppear, (IMP *)&origEDBViewDidAppear);
    BOOL highlight = EDBHookInstanceMethod(cls,
        @"tableView:shouldHighlightRowAtIndexPath:", "B32@0:8@16@24",
        (IMP)EDBShouldHighlight, (IMP *)&origEDBShouldHighlight);
    if (!highlight) {
        highlight = EDBHookInstanceMethod(cls,
            @"tableView:shouldHighlightRowAtIndexPath:", "c32@0:8@16@24",
            (IMP)EDBShouldHighlight, (IMP *)&origEDBShouldHighlight);
    }
    BOOL select = EDBHookInstanceMethod(cls,
        @"tableView:didSelectRowAtIndexPath:", "v32@0:8@16@24",
        (IMP)EDBDidSelect, (IMP *)&origEDBDidSelect);

    EDBLOG("bug menu legacy=%d current=%d load=%d appear=%d highlight=%d select=%d",
        legacy, current, load, appear, highlight, select);
}

static void EDBDefaultsChanged(__unused NSNotification *notification) {
    EDBInstallBugMenuHooks();
    EDBInstallIdentityHooksNow();
}

__attribute__((constructor))
static void SCIEmployeeDogfoodNativeBridgeCtor(void) {
    @autoreleasepool {
        EDBInstallBugMenuHooks();
        EDBInstallIdentityHooksNow();
        [NSNotificationCenter.defaultCenter
            addObserverForName:NSUserDefaultsDidChangeNotification
                        object:nil
                         queue:NSOperationQueue.mainQueue
                    usingBlock:^(__unused NSNotification *notification) {
                        EDBDefaultsChanged(notification);
                    }];
        [NSNotificationCenter.defaultCenter
            addObserverForName:UIApplicationDidBecomeActiveNotification
                        object:nil
                         queue:NSOperationQueue.mainQueue
                    usingBlock:^(__unused NSNotification *notification) {
                        EDBInstallBugMenuHooks();
                        EDBInstallIdentityHooksNow();
                    }];
    }
}
