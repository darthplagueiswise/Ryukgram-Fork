// SCIEmployeeInternal.x
// =====================================================================
// Employee / Internal — equivalente cliente-side do primeiro toggle FBTweak
// =====================================================================
// Confirmado em Instagram(29) + FBSharedFramework(105):
//   • IGFacebookUserInfo -isEmployee (FBSharedFramework)
//   • IGAdPlatformLogger_objc -isEmployee/-setIsEmployee:
//   • Swift IGAdPlatformLogger_swift -isEmployee/-setIsEmployee:
//   • FBWKWebView / FBWKWebViewDelegateAdaptor -setIsEmployee:
//   • duas ABIs reais de IGBugReportMenuViewController initWith...
//   • ivars escalares do menu: availability + showInternalSettings/loggedOut/
//     shake/dogfoodingAssistant
//   • IGInternalSettingsAvailabilityStatus: 0 abre, 2 mostra Access Denied
//
// _ig_is_employee e _ig_is_employee_or_test_user NÃO são funções BOOL: são
// descritores DATA de 16 bytes. Nunca usar fishhook/MSHookFunction neles.
// MobileConfig/DATA continua no runtime browser/override nativo separado.
//
// Hooks instalados uma vez; todos os corpos leem prefs ao vivo. Desligar o
// toggle faz o caminho voltar ao original sem tentar desinstalar IMPs.

#import "../../Utils.h"
#import <UIKit/UIKit.h>
#import <objc/runtime.h>
#import <substrate.h>
#import <os/log.h>
#import <stdint.h>
#import <string.h>

#define EILOG(fmt, ...) os_log(OS_LOG_DEFAULT, "[SCIGate] EmployeeInternal " fmt, ##__VA_ARGS__)

static inline BOOL EIMasterOn(void) {
	return [SCIUtils getBoolPref:@"sci_employee_internal"];
}

static inline BOOL EIMenuOn(void) {
	return EIMasterOn() || [SCIUtils getBoolPref:@"sci_force_internal_settings_menu"];
}

static inline BOOL EIAvailabilityOn(void) {
	return EIMenuOn() || [SCIUtils getBoolPref:@"sci_force_internal_settings_availability"];
}

static inline BOOL EILoggedOutOn(void) {
	return EIMasterOn() || [SCIUtils getBoolPref:@"sci_force_internal_settings_loggedout"];
}

static inline BOOL EIAnyOn(void) {
	return EIMasterOn() || EIMenuOn() || EIAvailabilityOn() || EILoggedOutOn();
}

// ---------------------------------------------------------------------
// ObjC conhecido — identidade e propagação local.
// ---------------------------------------------------------------------
%group SCIEmployeeKnownObjCGroup

%hook IGFacebookUserInfo
- (BOOL)isEmployee {
	if (EIMasterOn()) return YES;
	return %orig;
}
%end

%hook IGAdPlatformLogger_objc
- (BOOL)isEmployee {
	if (EIMasterOn()) return YES;
	return %orig;
}
- (void)setIsEmployee:(BOOL)value {
	if (EIMasterOn()) {
		%orig(YES);
		return;
	}
	%orig(value);
}
%end

%hook FBWKWebView
- (void)setIsEmployee:(BOOL)value {
	if (EIMasterOn()) {
		%orig(YES);
		return;
	}
	%orig(value);
}
%end

%hook FBWKWebViewDelegateAdaptor
- (void)setIsEmployee:(BOOL)value {
	if (EIMasterOn()) {
		%orig(YES);
		return;
	}
	%orig(value);
}
%end

%end

// ---------------------------------------------------------------------
// Swift @objc conhecido — classe mangled exata, um orig por selector.
// ---------------------------------------------------------------------
static BOOL (*orig_EIAdLoggerSwiftIsEmployee)(id, SEL) = NULL;
static void (*orig_EIAdLoggerSwiftSetIsEmployee)(id, SEL, BOOL) = NULL;

static BOOL EIAdLoggerSwiftIsEmployee(id self, SEL _cmd) {
	if (EIMasterOn()) return YES;
	return orig_EIAdLoggerSwiftIsEmployee
		? orig_EIAdLoggerSwiftIsEmployee(self, _cmd)
		: NO;
}

static void EIAdLoggerSwiftSetIsEmployee(id self, SEL _cmd, BOOL value) {
	if (orig_EIAdLoggerSwiftSetIsEmployee) {
		orig_EIAdLoggerSwiftSetIsEmployee(self, _cmd, EIMasterOn() ? YES : value);
	}
}

static BOOL EITypeEncodingMatches(Method method, const char *expected) {
	if (!method || !expected) return NO;
	const char *encoding = method_getTypeEncoding(method);
	return encoding && strcmp(encoding, expected) == 0;
}

static BOOL EIInstallSwiftIdentityHooks(void) {
	Class cls = objc_getClass("_TtC28IGAdInsertionLoggingKitSwift24IGAdPlatformLogger_swift");
	if (!cls) return NO;
	BOOL installed = NO;

	SEL getter = sel_registerName("isEmployee");
	Method getterMethod = class_getInstanceMethod(cls, getter);
	if (!orig_EIAdLoggerSwiftIsEmployee &&
		EITypeEncodingMatches(getterMethod, "B16@0:8")) {
		MSHookMessageEx(cls, getter, (IMP)EIAdLoggerSwiftIsEmployee,
		                (IMP *)&orig_EIAdLoggerSwiftIsEmployee);
	}
	installed = installed || (orig_EIAdLoggerSwiftIsEmployee != NULL);
	if (getterMethod && !EITypeEncodingMatches(getterMethod, "B16@0:8")) {
		EILOG("skip Swift isEmployee: ABI changed: %{public}s", method_getTypeEncoding(getterMethod));
	}

	SEL setter = sel_registerName("setIsEmployee:");
	Method setterMethod = class_getInstanceMethod(cls, setter);
	if (!orig_EIAdLoggerSwiftSetIsEmployee &&
		EITypeEncodingMatches(setterMethod, "v20@0:8B16")) {
		MSHookMessageEx(cls, setter, (IMP)EIAdLoggerSwiftSetIsEmployee,
		                (IMP *)&orig_EIAdLoggerSwiftSetIsEmployee);
	}
	installed = installed || (orig_EIAdLoggerSwiftSetIsEmployee != NULL);
	if (setterMethod && !EITypeEncodingMatches(setterMethod, "v20@0:8B16")) {
		EILOG("skip Swift setIsEmployee: ABI changed: %{public}s", method_getTypeEncoding(setterMethod));
	}
	return installed;
}

// ---------------------------------------------------------------------
// Bug Reporter Menu — equivalente ao FBBugReportConfiguration.
// ---------------------------------------------------------------------
// ABI legada:
// @92@0:8@16@24@32@40@48@56q64q72B80B84B88
//
// ABI atual:
// @104@0:8@16@24@32@40@48@56q64q72B80B84B88B92q96
//
// status=0 segue para Internal Settings; status=2 mostra Access Denied.
//
// O Instagram pode conservar/reusar uma instância do report menu criada antes
// do tap no menu Dev. Só alterar os argumentos do initializer não cobre esse
// caso. Por isso os mesmos estados são reaplicados nos ivars escalares reais em
// viewDidLoad/viewDidAppear, e a UITableView é recarregada quando necessário.

typedef id (*EIBugMenuLegacyIMP)(
	id, SEL, id, id, id, id, id, id,
	NSInteger, NSInteger, BOOL, BOOL, BOOL
);

typedef id (*EIBugMenuCurrentIMP)(
	id, SEL, id, id, id, id, id, id,
	NSInteger, NSInteger, BOOL, BOOL, BOOL, BOOL, NSInteger
);

static EIBugMenuLegacyIMP orig_EIBugMenuLegacy = NULL;
static EIBugMenuCurrentIMP orig_EIBugMenuCurrent = NULL;
static void (*orig_EIBugMenuViewDidLoad)(id, SEL) = NULL;
static void (*orig_EIBugMenuViewDidAppear)(id, SEL, BOOL) = NULL;

static BOOL EIWriteIntegerIvar(id object, const char *name, NSInteger value) {
	if (!object || !name) return NO;
	Ivar ivar = class_getInstanceVariable([object class], name);
	if (!ivar) return NO;
	uint8_t *bytes = (uint8_t *)(__bridge void *)object;
	memcpy(bytes + ivar_getOffset(ivar), &value, sizeof(value));
	return YES;
}

static BOOL EIWriteBoolIvar(id object, const char *name, BOOL value) {
	if (!object || !name) return NO;
	Ivar ivar = class_getInstanceVariable([object class], name);
	if (!ivar) return NO;
	BOOL normalized = value ? YES : NO;
	uint8_t *bytes = (uint8_t *)(__bridge void *)object;
	memcpy(bytes + ivar_getOffset(ivar), &normalized, sizeof(normalized));
	return YES;
}

static UITableView *EIBugMenuTableView(id controller) {
	if (!controller) return nil;
	Ivar ivar = class_getInstanceVariable([controller class], "tableView");
	if (!ivar) return nil;
	id value = object_getIvar(controller, ivar);
	return [value isKindOfClass:UITableView.class] ? value : nil;
}

static void EIApplyBugMenuLiveState(id controller, BOOL reloadTable) {
	if (!controller || !EIAnyOn()) return;

	BOOL changed = NO;
	if (EIAvailabilityOn()) {
		changed |= EIWriteIntegerIvar(controller,
			"internalSettingsAvailabilityStatus", 0);
	}
	if (EIMenuOn()) {
		changed |= EIWriteBoolIvar(controller, "showInternalSettings", YES);
		changed |= EIWriteBoolIvar(controller,
			"showShakeToReportPreferenceToggle", YES);
	}
	if (EILoggedOutOn()) {
		changed |= EIWriteBoolIvar(controller,
			"showLoggedOutInternalSettings", YES);
	}
	if (EIMasterOn()) {
		changed |= EIWriteBoolIvar(controller,
			"showDogfoodingAssistant", YES);
	}

	if (reloadTable && changed) {
		UITableView *tableView = EIBugMenuTableView(controller);
		[tableView reloadData];
		[tableView setNeedsLayout];
	}
}

static id EIBugMenuLegacy(
	id self, SEL _cmd,
	id deviceSession, id userSession, id reliabilityLogging,
	id navChain, id endpoint, id entryPoint,
	NSInteger style, NSInteger availabilityStatus,
	BOOL showInternalSettings,
	BOOL showLoggedOutInternalSettings,
	BOOL showShakeToReportPreferenceToggle
) {
	if (EIAvailabilityOn()) availabilityStatus = 0;
	if (EIMenuOn()) {
		showInternalSettings = YES;
		showShakeToReportPreferenceToggle = YES;
	}
	if (EILoggedOutOn()) showLoggedOutInternalSettings = YES;

	id result = orig_EIBugMenuLegacy
		? orig_EIBugMenuLegacy(
			self, _cmd, deviceSession, userSession, reliabilityLogging,
			navChain, endpoint, entryPoint, style, availabilityStatus,
			showInternalSettings, showLoggedOutInternalSettings,
			showShakeToReportPreferenceToggle)
		: nil;
	EIApplyBugMenuLiveState(result, NO);
	return result;
}

static id EIBugMenuCurrent(
	id self, SEL _cmd,
	id deviceSession, id userSession, id reliabilityLogging,
	id navChain, id endpoint, id entryPoint,
	NSInteger style, NSInteger availabilityStatus,
	BOOL showInternalSettings,
	BOOL showLoggedOutInternalSettings,
	BOOL showShakeToReportPreferenceToggle,
	BOOL showDogfoodingAssistant,
	NSInteger maisaUXVariantRawValue
) {
	if (EIAvailabilityOn()) availabilityStatus = 0;
	if (EIMenuOn()) {
		showInternalSettings = YES;
		showShakeToReportPreferenceToggle = YES;
	}
	if (EILoggedOutOn()) showLoggedOutInternalSettings = YES;
	if (EIMasterOn()) showDogfoodingAssistant = YES;

	id result = orig_EIBugMenuCurrent
		? orig_EIBugMenuCurrent(
			self, _cmd, deviceSession, userSession, reliabilityLogging,
			navChain, endpoint, entryPoint, style, availabilityStatus,
			showInternalSettings, showLoggedOutInternalSettings,
			showShakeToReportPreferenceToggle, showDogfoodingAssistant,
			maisaUXVariantRawValue)
		: nil;
	EIApplyBugMenuLiveState(result, NO);
	return result;
}

static void EIBugMenuViewDidLoad(id self, SEL _cmd) {
	EIApplyBugMenuLiveState(self, NO);
	if (orig_EIBugMenuViewDidLoad) orig_EIBugMenuViewDidLoad(self, _cmd);
	EIApplyBugMenuLiveState(self, YES);
}

static void EIBugMenuViewDidAppear(id self, SEL _cmd, BOOL animated) {
	EIApplyBugMenuLiveState(self, NO);
	if (orig_EIBugMenuViewDidAppear) {
		orig_EIBugMenuViewDidAppear(self, _cmd, animated);
	}
	EIApplyBugMenuLiveState(self, YES);
}

static BOOL EIInstallBugReporterHooks(void) {
	Class cls = objc_getClass("_TtC17IGBugReporterMenu29IGBugReportMenuViewController");
	if (!cls) cls = objc_getClass("IGBugReportMenuViewController");
	if (!cls) {
		EILOG("IGBugReportMenuViewController absent");
		return NO;
	}
	BOOL installed = NO;

	SEL legacySel = NSSelectorFromString(
		@"initWithDeviceSession:userSession:reliabilityLogging:navChain:endpoint:entryPoint:style:internalSettingsAvailabilityStatus:showInternalSettings:showLoggedOutInternalSettings:showShakeToReportPreferenceToggle:");
	Method legacyMethod = class_getInstanceMethod(cls, legacySel);
	if (!orig_EIBugMenuLegacy && EITypeEncodingMatches(legacyMethod,
		"@92@0:8@16@24@32@40@48@56q64q72B80B84B88")) {
		MSHookMessageEx(cls, legacySel, (IMP)EIBugMenuLegacy,
		                (IMP *)&orig_EIBugMenuLegacy);
	}
	installed = installed || (orig_EIBugMenuLegacy != NULL);
	if (legacyMethod && !EITypeEncodingMatches(legacyMethod,
		"@92@0:8@16@24@32@40@48@56q64q72B80B84B88")) {
		EILOG("skip legacy bug menu init: ABI changed: %{public}s",
		      method_getTypeEncoding(legacyMethod));
	}

	SEL currentSel = NSSelectorFromString(
		@"initWithDeviceSession:userSession:reliabilityLogging:navChain:endpoint:entryPoint:style:internalSettingsAvailabilityStatus:showInternalSettings:showLoggedOutInternalSettings:showShakeToReportPreferenceToggle:showDogfoodingAssistant:maisaUXVariantRawValue:");
	Method currentMethod = class_getInstanceMethod(cls, currentSel);
	if (!orig_EIBugMenuCurrent && EITypeEncodingMatches(currentMethod,
		"@104@0:8@16@24@32@40@48@56q64q72B80B84B88B92q96")) {
		MSHookMessageEx(cls, currentSel, (IMP)EIBugMenuCurrent,
		                (IMP *)&orig_EIBugMenuCurrent);
	}
	installed = installed || (orig_EIBugMenuCurrent != NULL);
	if (currentMethod && !EITypeEncodingMatches(currentMethod,
		"@104@0:8@16@24@32@40@48@56q64q72B80B84B88B92q96")) {
		EILOG("skip current bug menu init: ABI changed: %{public}s",
		      method_getTypeEncoding(currentMethod));
	}

	SEL viewDidLoadSel = @selector(viewDidLoad);
	Method viewDidLoadMethod = class_getInstanceMethod(cls, viewDidLoadSel);
	if (!orig_EIBugMenuViewDidLoad &&
		EITypeEncodingMatches(viewDidLoadMethod, "v16@0:8")) {
		MSHookMessageEx(cls, viewDidLoadSel, (IMP)EIBugMenuViewDidLoad,
		                (IMP *)&orig_EIBugMenuViewDidLoad);
	}
	installed = installed || (orig_EIBugMenuViewDidLoad != NULL);

	SEL viewDidAppearSel = @selector(viewDidAppear:);
	Method viewDidAppearMethod = class_getInstanceMethod(cls, viewDidAppearSel);
	if (!orig_EIBugMenuViewDidAppear &&
		EITypeEncodingMatches(viewDidAppearMethod, "v20@0:8B16")) {
		MSHookMessageEx(cls, viewDidAppearSel, (IMP)EIBugMenuViewDidAppear,
		                (IMP *)&orig_EIBugMenuViewDidAppear);
	}
	installed = installed || (orig_EIBugMenuViewDidAppear != NULL);

	EILOG("Bug Reporter hooks legacy=%d current=%d load=%d appear=%d",
	      orig_EIBugMenuLegacy != NULL, orig_EIBugMenuCurrent != NULL,
	      orig_EIBugMenuViewDidLoad != NULL,
	      orig_EIBugMenuViewDidAppear != NULL);
	return installed;
}

// ---------------------------------------------------------------------
// Instalador idempotente, usado pelo ctor e pelo menu Dev.
// ---------------------------------------------------------------------
void SCIInstallEmployeeInternalHooksIfNeeded(void) {
	static BOOL knownObjCInstalled = NO;
	static BOOL swiftIdentityInstalled = NO;
	static BOOL bugReporterInstalled = NO;

	if (!EIAnyOn()) return;

	if (EIMasterOn() && !knownObjCInstalled) {
		knownObjCInstalled = YES;
		%init(SCIEmployeeKnownObjCGroup);
	}

	if (EIMasterOn() && !swiftIdentityInstalled) {
		swiftIdentityInstalled = EIInstallSwiftIdentityHooks();
	}

	if (!bugReporterInstalled &&
		(EIMenuOn() || EIAvailabilityOn() || EILoggedOutOn())) {
		bugReporterInstalled = EIInstallBugReporterHooks();
	}

	EILOG("installed master=%d menu=%d availability=%d loggedOut=%d swift=%d bugMenu=%d",
	      EIMasterOn(), EIMenuOn(), EIAvailabilityOn(), EILoggedOutOn(),
	      swiftIdentityInstalled, bugReporterInstalled);
}

%ctor {
	@autoreleasepool {
		if (!EIAnyOn()) return;
		SCIInstallEmployeeInternalHooksIfNeeded();
	}
}
