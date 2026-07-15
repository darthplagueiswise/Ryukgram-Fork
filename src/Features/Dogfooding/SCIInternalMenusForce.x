// Standalone "Internal & Dogfood Menus" enabler.
//
// Startup-safe persistent-toggle version.
//
// The previous version executed these hooks from %ctor when the persisted
// sci_internal_menus pref was ON. That made a persisted UI toggle execute during
// Instagram scene-create, before the app finished booting. On the tested build,
// that drove IG into XPlugins/FBAnalytics while FBAnalyticsCurrentSerializedAppIdentity
// was still inside pthread_once, producing a 0x8BADF00D watchdog deadlock.
//
// This file now keeps persistence but removes launch-time execution. The toggle
// remains ON across restarts, but the hooks are applied only when the user
// changes the toggle to ON inside Settings during the current session. There is
// no separate manual Apply button and nothing runs automatically at launch.

#import <Foundation/Foundation.h>
#import <objc/runtime.h>
#import "../../Utils.h"
#import "../Gating/SCIGatingCatalog.h"
#import "SCIInternalMenusForce.h"

// SCI-FIX 2026-07-11: migrado de SCIRuntimeBoolForce (Mecanismo D — class_replaceMethod
// com bloco constante, descarta o IMP original, não desliga sem relançar) para
// SCIGatingCatalog (Mecanismo C — MSHookMessageEx + override-dict + fallback seguro pro
// IMP original). Ver CLAUDE.md §3. Os 4 alvos abaixo foram revalidados contra o
// Instagram 433.0.283 (classe + seletor confirmados como instance method BOOL real).
static NSUInteger SCIInternalMenusInstallLocalRuntimeBoolHooks(void) {
    NSUInteger installed = 0;

    // Master local employee gate (FBSharedFramework). Este é o predicado que os
    // checkers [ig-only]/[internal-only] consultam e de que as linhas de dogfood
    // dependem.
    if (objc_getClass("IGFacebookUserInfo")) {
        [SCIGatingCatalog setRuntimeBoolOverride:YES class:@"IGFacebookUserInfo"
                                         selector:@"isEmployee" classMethod:NO];
        installed++;
    }

    // Getter secundário de employee na imagem principal do IG.
    if (objc_getClass("IGAdPlatformLogger_objc")) {
        [SCIGatingCatalog setRuntimeBoolOverride:YES class:@"IGAdPlatformLogger_objc"
                                         selector:@"isEmployee" classMethod:NO];
        installed++;
    }

    // SCI 2026-07-15: variante Swift nova na build 438 do mesmo logger — também
    // expõe -isEmployee (instance, B16@0:8). Cobre o caminho Swift de checagem de
    // employee que não existia na 433.
    if (objc_getClass("_TtC28IGAdInsertionLoggingKitSwift24IGAdPlatformLogger_swift")) {
        [SCIGatingCatalog setRuntimeBoolOverride:YES
                                            class:@"_TtC28IGAdInsertionLoggingKitSwift24IGAdPlatformLogger_swift"
                                         selector:@"isEmployee" classMethod:NO];
        installed++;
    }

    // Autofill internal settings debug footer — linha de entrada pra superfície
    // nativa de settings internos/debug.
    if (objc_getClass("_TtC33AutofillInternalSettingsInstagram26IGAutofillInternalSettings")) {
        [SCIGatingCatalog setRuntimeBoolOverride:YES
                                            class:@"_TtC33AutofillInternalSettingsInstagram26IGAutofillInternalSettings"
                                         selector:@"getDebugFooterEnabled" classMethod:NO];
        installed++;
    }

    // Identity-switcher dogfood mode.
    if (objc_getClass("_TtC24IGIdentitySwitcherGating30IGIdentitySwitcherGatingHelper")) {
        [SCIGatingCatalog setRuntimeBoolOverride:YES
                                            class:@"_TtC24IGIdentitySwitcherGating30IGIdentitySwitcherGatingHelper"
                                         selector:@"isFbAcquisitionEpDogfoodModeEnabled" classMethod:NO];
        installed++;
    }

    return installed;
}

NSString *SCIInternalMenusForceApplyNow(void) {
    if (![SCIUtils getBoolPref:@"sci_internal_menus"]) {
        return @"Internal & Dogfood Menus is OFF. Toggle state is persisted and no hook is active for this session.";
    }

    NSUInteger installed = SCIInternalMenusInstallLocalRuntimeBoolHooks();
    if (installed == 0) {
        return @"No internal menu hooks were installed. The target classes may not be loaded yet in this Instagram surface. Toggle remains persisted; flip it ON again after opening the relevant surface.";
    }

    return [NSString stringWithFormat:@"Applied %lu internal menu runtime hook%@ for this session from the toggle change. Nothing was executed during launch.",
            (unsigned long)installed,
            installed == 1 ? @"" : @"s"];
}

%ctor {
    @autoreleasepool {
        // Deliberately no-op. Persistence stays in NSUserDefaults, but a persisted
        // ON state must not execute during Instagram scene-create. Execution occurs
        // only when the settings toggle is changed to ON in the current session.
    }
}
