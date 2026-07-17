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
#import "SCIDogfoodObjectRuntime.h"
#import <UIKit/UIKit.h>
#import <objc/runtime.h>
#import <objc/message.h>
#import <substrate.h>
#import <os/log.h>
#import <stdint.h>
#import <string.h>

#define EILOG(fmt, ...) os_log(OS_LOG_DEFAULT, "[SCIGate] EmployeeInternal " fmt, ##__VA_ARGS__)

static inline BOOL EIMasterOn(void) {
	// One identity master, including the two legacy switches. Previously these
	// paths disagreed: sci_force_ig_is_employee only changed an ads logger while
	// sci_employee_internal changed the real user-info model.
	return [SCIUtils getBoolPref:@"sci_employee_internal"] ||
	       [SCIUtils getBoolPref:@"sci_force_ig_internal_employee"] ||
	       [SCIUtils getBoolPref:@"sci_force_ig_is_employee"];
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

// ---------------------------------------------------------------------
// Identity gates — exact runtime methods only, with ABI validation.
//
// _ig_is_employee / _ig_is_employee_or_test_user are DATA descriptors,
// not callable BOOL functions. The actual local identity surfaces are ObjC
// getters and generated fragment models. We hook only selectors that really
// exist and return BOOL; missing names are recorded as absent, never added.
// ---------------------------------------------------------------------
static NSMutableDictionary<NSString *, NSValue *> *EIIdentityOriginals(void) {
	static NSMutableDictionary<NSString *, NSValue *> *store = nil;
	static dispatch_once_t onceToken;
	dispatch_once(&onceToken, ^{ store = [NSMutableDictionary dictionary]; });
	return store;
}

static NSString *EIIdentityKey(Class cls, SEL selector) {
	return [NSString stringWithFormat:@"%@#%@",
		NSStringFromClass(cls) ?: @"<nil>",
		NSStringFromSelector(selector) ?: @"<nil>"];
}

static BOOL EIIsZeroArgumentBoolGetter(Method method) {
	if (!method) return NO;
	const char *encoding = method_getTypeEncoding(method);
	return encoding &&
		(strcmp(encoding, "B16@0:8") == 0 ||
		 strcmp(encoding, "c16@0:8") == 0);
}

static BOOL EIIdentityBoolGetter(id self, SEL _cmd) {
	if (EIMasterOn()) return YES;

	IMP original = NULL;
	NSMutableDictionary<NSString *, NSValue *> *store = EIIdentityOriginals();
	@synchronized (store) {
		for (Class cls = object_getClass(self); cls; cls = class_getSuperclass(cls)) {
			NSValue *value = store[EIIdentityKey(cls, _cmd)];
			if (value) {
				original = value.pointerValue;
				break;
			}
		}
	}
	return original ? ((BOOL (*)(id, SEL))original)(self, _cmd) : NO;
}

static BOOL EIInstallIdentitySelectorOnClass(Class cls, SEL selector) {
	if (!cls || !selector) return NO;
	Method method = class_getInstanceMethod(cls, selector);
	if (!method) return NO;

	const char *encoding = method_getTypeEncoding(method);
	if (!EIIsZeroArgumentBoolGetter(method)) {
		EILOG("skip identity %{public}s.%{public}s ABI=%{public}s",
		      class_getName(cls), sel_getName(selector),
		      encoding ?: "<nil>");
		return NO;
	}

	NSString *key = EIIdentityKey(cls, selector);
	NSMutableDictionary<NSString *, NSValue *> *store = EIIdentityOriginals();
	@synchronized (store) {
		if (store[key]) return YES;
	}

	IMP original = NULL;
	MSHookMessageEx(cls, selector, (IMP)EIIdentityBoolGetter, &original);
	if (!original) return NO;

	@synchronized (store) {
		store[key] = [NSValue valueWithPointer:original];
	}
	EILOG("identity hook %{public}s.%{public}s",
	      class_getName(cls), sel_getName(selector));
	return YES;
}

static NSUInteger EIInstallIdentityHooksOnClass(Class cls, BOOL includeIsEmployee) {
	if (!cls) return 0;
	NSArray<NSString *> *names = @[
		@"isEmployee",
		@"isEmployeeOrTestUser",
		@"isTestUser",
		@"isDogfooder"
	];
	NSUInteger installed = 0;
	for (NSString *name in names) {
		if (!includeIsEmployee && [name isEqualToString:@"isEmployee"]) continue;
		if (EIInstallIdentitySelectorOnClass(cls, NSSelectorFromString(name))) {
			installed++;
		}
	}
	return installed;
}

void SCIInstallEmployeeIdentityHooksForObject(id object) {
	if (!EIMasterOn() || !object) return;
	Class cls = object_getClass(object);
	BOOL includeIsEmployee = (cls != objc_getClass("IGFacebookUserInfo"));
	EIInstallIdentityHooksOnClass(cls, includeIsEmployee);
}

static NSUInteger EIInstallKnownIdentityHooks(void) {
	NSArray<NSString *> *classNames = @[
		@"IGFacebookUserInfo",
		@"IGBaseUser",
		@"IGUserSession",
		@"IGSessionContext",
		@"IGUserSessionContext",
		@"IGDeviceSession",
		@"IGDogfooderProd"
	];
	NSUInteger installed = 0;
	for (NSString *className in classNames) {
		Class cls = NSClassFromString(className);
		BOOL includeIsEmployee = ![className isEqualToString:@"IGFacebookUserInfo"];
		installed += EIInstallIdentityHooksOnClass(cls, includeIsEmployee);
	}
	return installed;
}

static id (*orig_EIEmployeeOrTestFragment)(id, SEL) = NULL;
static id (*orig_EIDogfooderInformationFragment)(id, SEL) = NULL;

static id EIEmployeeOrTestFragment(id self, SEL _cmd) {
	if (EIMasterOn()) SCIInstallEmployeeIdentityHooksForObject(self);
	id model = orig_EIEmployeeOrTestFragment
		? orig_EIEmployeeOrTestFragment(self, _cmd)
		: nil;
	if (EIMasterOn()) SCIInstallEmployeeIdentityHooksForObject(model);
	return model;
}

static id EIDogfooderInformationFragment(id self, SEL _cmd) {
	if (EIMasterOn()) SCIInstallEmployeeIdentityHooksForObject(self);
	id model = orig_EIDogfooderInformationFragment
		? orig_EIDogfooderInformationFragment(self, _cmd)
		: nil;
	if (EIMasterOn()) SCIInstallEmployeeIdentityHooksForObject(model);
	return model;
}

static BOOL EIInstallIdentityFragmentHooks(void) {
	Class cls = objc_getClass("IGBaseUser");
	if (!cls) return NO;

	SEL employeeSel = NSSelectorFromString(
		@"asIGUserIsEmployeeOrTestUserFragmentImmutableModel");
	Method employeeMethod = class_getInstanceMethod(cls, employeeSel);
	if (!orig_EIEmployeeOrTestFragment &&
		EITypeEncodingMatches(employeeMethod, "@16@0:8")) {
		MSHookMessageEx(cls, employeeSel, (IMP)EIEmployeeOrTestFragment,
		                (IMP *)&orig_EIEmployeeOrTestFragment);
	}

	SEL dogfooderSel = NSSelectorFromString(
		@"asIGDogfooderInformationFragmentImmutableModel");
	Method dogfooderMethod = class_getInstanceMethod(cls, dogfooderSel);
	if (!orig_EIDogfooderInformationFragment &&
		EITypeEncodingMatches(dogfooderMethod, "@16@0:8")) {
		MSHookMessageEx(cls, dogfooderSel,
		                (IMP)EIDogfooderInformationFragment,
		                (IMP *)&orig_EIDogfooderInformationFragment);
	}

	return orig_EIEmployeeOrTestFragment != NULL ||
	       orig_EIDogfooderInformationFragment != NULL;
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
static void (*orig_EIBugMenuDidSelectRow)(id, SEL, UITableView *, NSIndexPath *) = NULL;

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

static NSString *EIBugMenuRowTitle(UIView *view) {
	if (!view) return nil;
	if ([view isKindOfClass:UILabel.class]) {
		NSString *text = ((UILabel *)view).text;
		if (text.length) return text;
	}
	for (UIView *child in view.subviews) {
		NSString *text = EIBugMenuRowTitle(child);
		if (text.length) return text;
	}
	return nil;
}

static NSString *EIBugMenuCellTitle(UITableViewCell *cell) {
	if (!cell) return nil;
	NSString *title = cell.textLabel.text;

	if (!title.length) {
		id configuration = cell.contentConfiguration;
		SEL textSelector = sel_registerName("text");
		if ([configuration respondsToSelector:textSelector]) {
			@try {
				id value = ((id (*)(id, SEL))objc_msgSend)(
					configuration, textSelector);
				if ([value isKindOfClass:NSString.class]) title = value;
			} @catch (__unused id exception) {}
		}
	}
	if (!title.length) title = EIBugMenuRowTitle(cell.contentView);
	if (!title.length) title = cell.accessibilityLabel;
	return [title stringByTrimmingCharactersInSet:
		NSCharacterSet.whitespaceAndNewlineCharacterSet];
}

static BOOL EIStringContainsDogfoodDependency(NSString *value) {
	NSString *lower = value.lowercaseString ?: @"";
	return [lower containsString:@"dogfood"] ||
	       [lower containsString:@"assistant"] ||
	       [lower containsString:@"provider"] ||
	       [lower containsString:@"socket"] ||
	       [lower containsString:@"config"] ||
	       [lower containsString:@"usersession"];
}

static void EICollectDogfoodDependencies(
	id object,
	NSUInteger depth,
	NSMutableSet<NSValue *> *visited,
	NSMutableDictionary<NSString *, id> *found
) {
	if (!object || depth > 3) return;
	NSValue *address = [NSValue valueWithPointer:(__bridge const void *)object];
	if ([visited containsObject:address]) return;
	[visited addObject:address];

	Class cls = object_getClass(object);
	NSString *className = NSStringFromClass(cls) ?: @"";
	NSString *lowerClass = className.lowercaseString;

	Protocol *providerProtocol = objc_getProtocol(
		"IGBugReportingDogfoodingAssistantMenuRowProviding");
	BOOL isProvider = providerProtocol &&
		[object conformsToProtocol:providerProtocol];

	if ([lowerClass containsString:@"dogfoodingsettingsconfig"]) {
		found[@"config"] = object;
		[SCIDogfoodObjectRuntime noteObject:object
			role:@"IGDogfoodingSettingsConfig"
			source:@"Bug Reporter live dependency"];
	}
	if ([className isEqualToString:@"IGUserSession"] ||
		[lowerClass hasSuffix:@"usersession"]) {
		found[@"session"] = object;
	}
	if (isProvider || [lowerClass containsString:@"dogfoodingassistant"]) {
		found[@"provider"] = object;
		[SCIDogfoodObjectRuntime noteObject:object
			role:@"IGBugReportingDogfoodingAssistantMenuRowProviding"
			source:@"Bug Reporter live dependency"];
	}

	if (depth == 3) return;
	for (Class current = cls; current; current = class_getSuperclass(current)) {
		unsigned int count = 0;
		Ivar *ivars = class_copyIvarList(current, &count);
		for (unsigned int i = 0; ivars && i < count; i++) {
			Ivar ivar = ivars[i];
			const char *encoding = ivar_getTypeEncoding(ivar);
			if (!encoding || encoding[0] != '@') continue;

			id child = nil;
			@try { child = object_getIvar(object, ivar); }
			@catch (__unused id exception) {}
			if (!child) continue;

			NSString *ivarName = ivar_getName(ivar)
				? [NSString stringWithUTF8String:ivar_getName(ivar)]
				: @"";
			NSString *childClass = NSStringFromClass(object_getClass(child)) ?: @"";
			BOOL relevant = depth == 0 ||
				EIStringContainsDogfoodDependency(ivarName) ||
				EIStringContainsDogfoodDependency(childClass);
			if (relevant) {
				EICollectDogfoodDependencies(
					child, depth + 1, visited, found);
			}
		}
		if (ivars) free(ivars);
	}
}

static void EICaptureDogfoodDependencies(id controller) {
	if (!controller || !EIMasterOn()) return;
	NSMutableDictionary<NSString *, id> *found =
		[NSMutableDictionary dictionary];
	EICollectDogfoodDependencies(
		controller, 0, [NSMutableSet set], found);

	id session = found[@"session"] ?:
		[SCIDogfoodObjectRuntime activeUserSession];
	id config = found[@"config"];
	if (config) {
		[SCIDogfoodObjectRuntime noteDogfoodConfig:config
			userSession:session
			source:@"IGBugReportMenuViewController live dependency graph"];
	} else if (session) {
		[SCIDogfoodObjectRuntime noteLiveUserSession:session
			source:@"IGBugReportMenuViewController live dependency graph"];
	}
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
	if (EIMasterOn()) {
		SCIInstallEmployeeIdentityHooksForObject(deviceSession);
		SCIInstallEmployeeIdentityHooksForObject(userSession);
	}

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
	if (EIMasterOn()) {
		showDogfoodingAssistant = YES;
		SCIInstallEmployeeIdentityHooksForObject(deviceSession);
		SCIInstallEmployeeIdentityHooksForObject(userSession);
	}

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
	EICaptureDogfoodDependencies(self);
}

static void EIBugMenuViewDidAppear(id self, SEL _cmd, BOOL animated) {
	EIApplyBugMenuLiveState(self, NO);
	if (orig_EIBugMenuViewDidAppear) {
		orig_EIBugMenuViewDidAppear(self, _cmd, animated);
	}
	EIApplyBugMenuLiveState(self, YES);
	EICaptureDogfoodDependencies(self);
}

static void EIBugMenuDidSelectRow(id self, SEL _cmd,
	UITableView *tableView, NSIndexPath *indexPath) {
	// Keep the native handler authoritative. This hook only reapplies the live
	// scalar state and, for a positively identified Assistant row, captures its
	// real provider/config before giving the original implementation first try.
	EIApplyBugMenuLiveState(self, NO);

	UITableViewCell *cell = [tableView cellForRowAtIndexPath:indexPath];
	NSString *title = EIBugMenuCellTitle(cell);
	BOOL dogfoodingAssistant = title.length > 0 &&
		[title caseInsensitiveCompare:@"Dogfooding Assistant"] == NSOrderedSame;
	UIViewController *topBefore = nil;

	if (dogfoodingAssistant) {
		EICaptureDogfoodDependencies(self);
		topBefore = [SCIDogfoodObjectRuntime topViewController];
	}

	if (orig_EIBugMenuDidSelectRow) {
		orig_EIBugMenuDidSelectRow(self, _cmd, tableView, indexPath);
	}

	if (!dogfoodingAssistant || !EIMasterOn()) return;

	// The previous implementation treated a nil title as NSOrderedSame (both
	// are numeric zero) and could run this path for Internal Settings. It also
	// substituted DirectNotes when native config was absent. Both behaviours
	// are forbidden here: fallback is native Dogfooding Settings only, and only
	// when the real config was captured from the live provider graph.
	dispatch_async(dispatch_get_main_queue(), ^{
		UIViewController *topAfter =
			[SCIDogfoodObjectRuntime topViewController];
		if (topAfter != topBefore) return;
		if ([self isKindOfClass:UIViewController.class] &&
			((UIViewController *)self).presentedViewController) return;

		if (![SCIDogfoodObjectRuntime bestDogfoodSettingsConfig]) {
			[SCIDogfoodObjectRuntime noteAction:@"Dogfooding Assistant"
				status:@"native provider/config unavailable; no unrelated fallback"
				detail:title];
			return;
		}
		if (![SCIDogfoodObjectRuntime tryOpenNativeDogfoodSettings]) {
			[SCIDogfoodObjectRuntime noteAction:@"Dogfooding Assistant"
				status:@"native Dogfooding Settings opener unavailable"
				detail:title];
		}
	});
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

	SEL didSelectSel = @selector(tableView:didSelectRowAtIndexPath:);
	Method didSelectMethod = class_getInstanceMethod(cls, didSelectSel);
	if (!orig_EIBugMenuDidSelectRow &&
		EITypeEncodingMatches(didSelectMethod, "v32@0:8@16@24")) {
		MSHookMessageEx(cls, didSelectSel, (IMP)EIBugMenuDidSelectRow,
		                (IMP *)&orig_EIBugMenuDidSelectRow);
	}
	installed = installed || (orig_EIBugMenuDidSelectRow != NULL);

	EILOG("Bug Reporter hooks legacy=%d current=%d load=%d appear=%d select=%d",
	      orig_EIBugMenuLegacy != NULL, orig_EIBugMenuCurrent != NULL,
	      orig_EIBugMenuViewDidLoad != NULL,
	      orig_EIBugMenuViewDidAppear != NULL,
	      orig_EIBugMenuDidSelectRow != NULL);
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

	NSUInteger identityHooks = 0;
	BOOL identityFragments = NO;
	if (EIMasterOn()) {
		identityHooks = EIInstallKnownIdentityHooks();
		identityFragments = EIInstallIdentityFragmentHooks();
	}

	if (EIMasterOn() && !swiftIdentityInstalled) {
		swiftIdentityInstalled = EIInstallSwiftIdentityHooks();
	}

	if (!bugReporterInstalled &&
		(EIMenuOn() || EIAvailabilityOn() || EILoggedOutOn())) {
		bugReporterInstalled = EIInstallBugReporterHooks();
	}

	EILOG("installed master=%d menu=%d availability=%d loggedOut=%d identity=%lu fragments=%d swift=%d bugMenu=%d",
	      EIMasterOn(), EIMenuOn(), EIAvailabilityOn(), EILoggedOutOn(),
	      (unsigned long)identityHooks, identityFragments,
	      swiftIdentityInstalled, bugReporterInstalled);
}

%ctor {
	@autoreleasepool {
		if (!EIAnyOn()) return;
		SCIInstallEmployeeInternalHooksIfNeeded();
	}
}
