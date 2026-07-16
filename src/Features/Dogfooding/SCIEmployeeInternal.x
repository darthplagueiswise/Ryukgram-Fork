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
//   • IGInternalSettingsAvailabilityStatus: 0 abre, 2 mostra Access Denied
//
// _ig_is_employee e _ig_is_employee_or_test_user NÃO são funções BOOL: são
// descritores DATA de 16 bytes. Nunca usar fishhook/MSHookFunction neles.
// MobileConfig/DATA continua no runtime browser/override nativo separado.
//
// Hooks instalados uma vez; todos os corpos leem prefs ao vivo. Desligar o
// toggle faz o caminho voltar ao original sem tentar desinstalar IMPs.

#import "../../Utils.h"
#import <objc/runtime.h>
#import <substrate.h>
#import <os/log.h>
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

static void EIInstallSwiftIdentityHooks(void) {
	Class cls = objc_getClass("_TtC28IGAdInsertionLoggingKitSwift24IGAdPlatformLogger_swift");
	if (!cls) return;

	SEL getter = sel_registerName("isEmployee");
	Method getterMethod = class_getInstanceMethod(cls, getter);
	if (EITypeEncodingMatches(getterMethod, "B16@0:8")) {
		MSHookMessageEx(cls, getter, (IMP)EIAdLoggerSwiftIsEmployee,
		                (IMP *)&orig_EIAdLoggerSwiftIsEmployee);
	} else if (getterMethod) {
		EILOG("skip Swift isEmployee: ABI changed: %{public}s", method_getTypeEncoding(getterMethod));
	}

	SEL setter = sel_registerName("setIsEmployee:");
	Method setterMethod = class_getInstanceMethod(cls, setter);
	if (EITypeEncodingMatches(setterMethod, "v20@0:8B16")) {
		MSHookMessageEx(cls, setter, (IMP)EIAdLoggerSwiftSetIsEmployee,
		                (IMP *)&orig_EIAdLoggerSwiftSetIsEmployee);
	} else if (setterMethod) {
		EILOG("skip Swift setIsEmployee: ABI changed: %{public}s", method_getTypeEncoding(setterMethod));
	}
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

	return orig_EIBugMenuLegacy
		? orig_EIBugMenuLegacy(
			self, _cmd, deviceSession, userSession, reliabilityLogging,
			navChain, endpoint, entryPoint, style, availabilityStatus,
			showInternalSettings, showLoggedOutInternalSettings,
			showShakeToReportPreferenceToggle)
		: nil;
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

	return orig_EIBugMenuCurrent
		? orig_EIBugMenuCurrent(
			self, _cmd, deviceSession, userSession, reliabilityLogging,
			navChain, endpoint, entryPoint, style, availabilityStatus,
			showInternalSettings, showLoggedOutInternalSettings,
			showShakeToReportPreferenceToggle, showDogfoodingAssistant,
			maisaUXVariantRawValue)
		: nil;
}

static void EIInstallBugReporterHooks(void) {
	Class cls = objc_getClass("_TtC17IGBugReporterMenu29IGBugReportMenuViewController");
	if (!cls) cls = objc_getClass("IGBugReportMenuViewController");
	if (!cls) {
		EILOG("IGBugReportMenuViewController absent");
		return;
	}

	SEL legacySel = NSSelectorFromString(
		@"initWithDeviceSession:userSession:reliabilityLogging:navChain:endpoint:entryPoint:style:internalSettingsAvailabilityStatus:showInternalSettings:showLoggedOutInternalSettings:showShakeToReportPreferenceToggle:");
	Method legacyMethod = class_getInstanceMethod(cls, legacySel);
	if (EITypeEncodingMatches(legacyMethod,
		"@92@0:8@16@24@32@40@48@56q64q72B80B84B88")) {
		MSHookMessageEx(cls, legacySel, (IMP)EIBugMenuLegacy,
		                (IMP *)&orig_EIBugMenuLegacy);
	} else if (legacyMethod) {
		EILOG("skip legacy bug menu init: ABI changed: %{public}s",
		      method_getTypeEncoding(legacyMethod));
	}

	SEL currentSel = NSSelectorFromString(
		@"initWithDeviceSession:userSession:reliabilityLogging:navChain:endpoint:entryPoint:style:internalSettingsAvailabilityStatus:showInternalSettings:showLoggedOutInternalSettings:showShakeToReportPreferenceToggle:showDogfoodingAssistant:maisaUXVariantRawValue:");
	Method currentMethod = class_getInstanceMethod(cls, currentSel);
	if (EITypeEncodingMatches(currentMethod,
		"@104@0:8@16@24@32@40@48@56q64q72B80B84B88B92q96")) {
		MSHookMessageEx(cls, currentSel, (IMP)EIBugMenuCurrent,
		                (IMP *)&orig_EIBugMenuCurrent);
	} else if (currentMethod) {
		EILOG("skip current bug menu init: ABI changed: %{public}s",
		      method_getTypeEncoding(currentMethod));
	}
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
		swiftIdentityInstalled = YES;
		EIInstallSwiftIdentityHooks();
	}

	if (!bugReporterInstalled && (EIMenuOn() || EIAvailabilityOn() || EILoggedOutOn())) {
		bugReporterInstalled = YES;
		EIInstallBugReporterHooks();
	}

	EILOG("installed master=%d menu=%d availability=%d loggedOut=%d",
	      EIMasterOn(), EIMenuOn(), EIAvailabilityOn(), EILoggedOutOn());
}

%ctor {
	@autoreleasepool {
		if (!EIAnyOn()) return;
		SCIInstallEmployeeInternalHooksIfNeeded();
	}
}
