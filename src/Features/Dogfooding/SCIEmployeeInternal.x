// SCIEmployeeInternal.x
// =====================================================================
// UM HOOK, UM TOGGLE — Employee / Internal (KEYSTONE)
// =====================================================================
// Mesmo objetivo do FBTEmployeeMode.x do FBTweak (forçar employee/internal
// globalmente), mas NÃO é espelho 1:1 — validado seletor a seletor contra o
// binário 438 e vários alvos do FBTweak simplesmente não existem no Instagram
// (são específicos do app Facebook): FBBugReportConfiguration (config por
// setters), isInternalTestUser: (FBIdentitySwitcherGatingHelper),
// FBProductTagCreationLogger, FB*ImageNetworkerConfiguration,
// FBRichPushNotificationTypeTraits — nenhum tem equivalente na 438, confirmado
// por busca exaustiva, não substituído por invenção.
//
// Alvos que EXISTEM e são hookados (revalidados contra 438):
//   C imports (GOT, fishhook-safe; stub adrp/ldr/br + caller real confirmados):
//       ig_is_employee
//       ig_is_employee_or_test_user
//   ObjC getters -isEmployee:
//       IGFacebookUserInfo        (FBSharedFramework) <- CHECK CENTRAL de funcionário
//       IGAdPlatformLogger_objc   (Instagram exec)
//   Swift @objc -isEmployee:
//       _TtC28IGAdInsertionLoggingKitSwift24IGAdPlatformLogger_swift
//   Bug reporter menu (rageshake) — Instagram não usa config-por-setters como o
//   FBTweak; usa INIT com BOOLs posicionais. Hookadas as 2 variantes de
//   -[IGBugReportMenuViewController initWith...] confirmadas na 438 (a segunda,
//   com showDogfoodingAssistant:/maisaUXVariantRawValue:, é nova nesta build):
//       style:q64 internalSettingsAvailabilityStatus:q72
//       showInternalSettings:B80 showLoggedOutInternalSettings:B84 (intocado)
//       showShakeToReportPreferenceToggle:B88
//       [variante 438] showDogfoodingAssistant:B92 maisaUXVariantRawValue:q96 (intocado)
//
// Sideload-safe: só MSHookMessageEx/%hook (ObjC/Swift @objc) + fishhook (GOT C import).
// Nunca __TEXT inline. %ctor barato: lê 1 pref e instala só se ON.

#import "../../Utils.h"
#import <objc/runtime.h>
#import <substrate.h>
#import "../../../modules/fishhook/fishhook.h"
#import <os/log.h>

#define EILOG(fmt, ...) os_log(OS_LOG_DEFAULT, "[SCIGate] EmployeeInternal " fmt, ##__VA_ARGS__)

static inline BOOL EIOn(void) { return [SCIUtils getBoolPref:@"sci_employee_internal"]; }

// ── (1) C imports: ig_is_employee* -> YES (latched; orig nunca chamado) ──
static BOOL (*orig_ig_is_employee)(void) = NULL;
static BOOL (*orig_ig_is_employee_or_test_user)(void) = NULL;
static BOOL ei_ig_is_employee(void) { return YES; }
static BOOL ei_ig_is_employee_or_test_user(void) { return YES; }

// ── (2) Getters ObjC conhecidos -> YES (resolvidos por nome; safe se ausentes) ──
%group SCIEmployeeObjCGroup
%hook IGFacebookUserInfo
- (BOOL)isEmployee {
	return EIOn() ? YES : %orig;
}
%end
%hook IGAdPlatformLogger_objc
- (BOOL)isEmployee {
	return EIOn() ? YES : %orig;
}
%end
%end

// ── (3) Getter Swift @objc -> YES (classe mangled, alias em runtime) ──
%group SCIEmployeeSwiftGroup
%hook IGAdPlatformLogger_swift
- (BOOL)isEmployee {
	return EIOn() ? YES : %orig;
}
%end
%end

// ── (4) Bug reporter menu (rageshake) init -> força Internal Settings visível ──
// Instagram não tem um objeto de config por setters como o FBBugReportConfiguration
// do FBTweak (confirmado: não existe classe equivalente nem os seletores
// setEnableInternalSettingsOption:/setForceShowingInternalTools:/etc no binário).
// O equivalente funcional aqui é via INIT: IGBugReportMenuViewController recebe
// showInternalSettings/showShakeToReportPreferenceToggle (e, novo na 438,
// showDogfoodingAssistant — o análogo do setShowTriageToDogfoodingAssistantSession:
// do FBTweak) como BOOL posicionais. Hookamos as DUAS variantes de init confirmadas
// no binário 438 e forçamos esses três flags a YES antes de repassar pro %orig.
// internalSettingsAvailabilityStatus (enum) e showLoggedOutInternalSettings ficam
// intocados — não há evidência de quais valores fazem o quê, não forço sem saber.
%group SCIEmployeeBugReportGroup
%hook IGBugReportMenuViewController

- (id)initWithDeviceSession:(id)deviceSession
                 userSession:(id)userSession
         reliabilityLogging:(id)reliabilityLogging
                    navChain:(id)navChain
                    endpoint:(id)endpoint
                  entryPoint:(id)entryPoint
                       style:(NSInteger)style
internalSettingsAvailabilityStatus:(NSInteger)internalSettingsAvailabilityStatus
        showInternalSettings:(BOOL)showInternalSettings
showLoggedOutInternalSettings:(BOOL)showLoggedOutInternalSettings
showShakeToReportPreferenceToggle:(BOOL)showShakeToReportPreferenceToggle {
	if (EIOn()) {
		showInternalSettings = YES;
		showShakeToReportPreferenceToggle = YES;
	}
	return %orig(deviceSession, userSession, reliabilityLogging, navChain, endpoint, entryPoint,
	             style, internalSettingsAvailabilityStatus, showInternalSettings,
	             showLoggedOutInternalSettings, showShakeToReportPreferenceToggle);
}

- (id)initWithDeviceSession:(id)deviceSession
                 userSession:(id)userSession
         reliabilityLogging:(id)reliabilityLogging
                    navChain:(id)navChain
                    endpoint:(id)endpoint
                  entryPoint:(id)entryPoint
                       style:(NSInteger)style
internalSettingsAvailabilityStatus:(NSInteger)internalSettingsAvailabilityStatus
        showInternalSettings:(BOOL)showInternalSettings
showLoggedOutInternalSettings:(BOOL)showLoggedOutInternalSettings
showShakeToReportPreferenceToggle:(BOOL)showShakeToReportPreferenceToggle
    showDogfoodingAssistant:(BOOL)showDogfoodingAssistant
     maisaUXVariantRawValue:(NSInteger)maisaUXVariantRawValue {
	if (EIOn()) {
		showInternalSettings = YES;
		showShakeToReportPreferenceToggle = YES;
		showDogfoodingAssistant = YES;
	}
	return %orig(deviceSession, userSession, reliabilityLogging, navChain, endpoint, entryPoint,
	             style, internalSettingsAvailabilityStatus, showInternalSettings,
	             showLoggedOutInternalSettings, showShakeToReportPreferenceToggle,
	             showDogfoodingAssistant, maisaUXVariantRawValue);
}

%end
%end

// ── (4) Bug reporter menu init: força a entrada Internal Settings ──
%ctor {
    @autoreleasepool {
        if (!EIOn()) return;   // %ctor barato: 1 pref read

        // (1) C gates — equivalente do FBShouldEnableInternalSettings
        struct rebinding rbs[] = {
            { "ig_is_employee",              (void *)ei_ig_is_employee,              (void **)&orig_ig_is_employee },
            { "ig_is_employee_or_test_user", (void *)ei_ig_is_employee_or_test_user, (void **)&orig_ig_is_employee_or_test_user },
        };
        int rc = rebind_symbols(rbs, 2);

        // (2) Getters ObjC conhecidos (Logos pula os que não existirem)
        %init(SCIEmployeeObjCGroup);

        // (3) Getter Swift (classe mangled via alias runtime)
        Class swCls = objc_getClass("_TtC28IGAdInsertionLoggingKitSwift24IGAdPlatformLogger_swift");
        if (swCls) %init(SCIEmployeeSwiftGroup, IGAdPlatformLogger_swift = swCls);

        // (4) Bug reporter menu init — força Internal Settings/Shake-to-report/
        // Dogfooding assistant visíveis (Logos pula a variante de init ausente).
        %init(SCIEmployeeBugReportGroup);

        BOOL haveFB = objc_getClass("IGFacebookUserInfo") != nil;
        EILOG("installed rc=%d fbUserInfo=%d swift=%d", rc, haveFB, swCls!=nil);
    }
}
