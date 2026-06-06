// SCIBulkGatingPresets.m
//
// Aplica/remove overrides do Feature Gating em massa.
// Todos os nomes de classe/seletor foram verificados via:
//   • disassembly do FBSharedFramework + Instagram (arm64)
//   • screenshots FLEX do Feature Gatings mostrando "forced ON via getter hook"
//   • comparação de nomes mangled Swift (_TtC<n>Module<m>Class)
//
// Qualquer classe não encontrada em runtime é ignorada silenciosamente por
// setRuntimeBoolOverride: (que checa objc_getClass + Method existence antes de hookear).

#import "SCIBulkGatingPresets.h"
#import "SCIGatingCatalog.h"

// Alias curto
#define SRBO(cls, sel, cm, val) [SCIGatingCatalog setRuntimeBoolOverride:(val) class:(cls) selector:(sel) classMethod:(cm)]
#define CRBO(cls, sel, cm)      [SCIGatingCatalog clearRuntimeBoolOverrideForClass:(cls) selector:(sel) classMethod:(cm)]

@implementation SCIBulkGatingPresets

// ── Liquid Glass ─────────────────────────────────────────────────────────────────

+ (void)applyLiquidGlass:(BOOL)on {

    // ① IGDSLauncherConfig — ObjC, instance methods, 9 flags
    //    Confirmado via disasm FBSharedFramework + screenshots (todos "forced ON")
    NSString *ds = @"IGDSLauncherConfig";
    for (NSString *s in @[
        @"canUseInternalLiquidGlassDebugger",
        @"isLiquidGlassCGContextBlurEnabled",
        @"isLiquidGlassEaseInOutBlurEnabled",
        @"isLiquidGlassIconBarButtonEnabled",
        @"isLiquidGlassInAppNotificationEnabled",
        @"isLiquidGlassNavigationContentStylePinningEnabled",
        @"isLiquidGlassToastEnabled",
        @"isLiquidGlassToastPeekEnabled",
        @"isOptimizeLiquidGlassGlyphRenderingEnabled",
    ]) { on ? SRBO(ds, s, NO, YES) : CRBO(ds, s, NO); }

    // ② IGDSAlertDialogLiquidGlass — Swift, CLASS method +isEnabled
    //    Mangled: _TtC(26)IGDSAlertDialogLiquidGlass(26)IGDSAlertDialogLiquidGlass
    NSString *alert = @"_TtC26IGDSAlertDialogLiquidGlass26IGDSAlertDialogLiquidGlass";
    on ? SRBO(alert, @"isEnabled", YES, YES) : CRBO(alert, @"isEnabled", YES);

    // ③ IGLiquidGlass — Swift, CLASS method +isEnabled
    //    Mangled: _TtC(13)IGLiquidGlass(13)IGLiquidGlass
    NSString *lgCls = @"_TtC13IGLiquidGlass13IGLiquidGlass";
    on ? SRBO(lgCls, @"isEnabled", YES, YES) : CRBO(lgCls, @"isEnabled", YES);

    // ④ IGLiquidGlassNavigationExperimentHelper — Swift, instance methods
    //    Mangled: _TtC(29)IGLiquidGlassExperimentHelper(39)IGLiquidGlassNavigationExperimentHelper
    NSString *nh = @"_TtC29IGLiquidGlassExperimentHelper39IGLiquidGlassNavigationExperimentHelper";
    for (NSString *s in @[
        @"isEnabled",
        @"isGlassRenderingOptimizationEnabled",
        @"isHomeFeedHeaderEnabled",
        @"isProfileOtherNavBarHeightMatchSelf",
    ]) { on ? SRBO(nh, s, NO, YES) : CRBO(nh, s, NO); }
    // isProfileSegmentedTabsGlassDisabled → forçar OFF quando LiquidGlass ON
    // (glass desativado para tabs segmentadas = glass ATIVO nos tabs)
    on ? SRBO(nh, @"isProfileSegmentedTabsGlassDisabled", NO, NO) : CRBO(nh, @"isProfileSegmentedTabsGlassDisabled", NO);

    // ⑤ IGLiquidGlassInteractiveTabBar — ObjC, instance methods
    //    Seletores confirmados via disasm FBSharedFramework
    NSString *itb = @"IGLiquidGlassInteractiveTabBar";
    for (NSString *s in @[
        @"accessoryButtonEnabled",
        @"isAccessoryButtonVisible",
        @"isDebuggerEnabled",
        @"isHapticsEnabled",
        @"isPanGestureEnabled",
        @"syncConfigWithBarAppearance",
    ]) { on ? SRBO(itb, s, NO, YES) : CRBO(itb, s, NO); }
}

+ (BOOL)isLiquidGlassActive {
    // Checa um flag representativo do grupo
    NSNumber *v = [SCIGatingCatalog runtimeBoolOverrideStateForClass:@"IGDSLauncherConfig"
                                                            selector:@"isLiquidGlassToastEnabled"
                                                         classMethod:NO];
    return v != nil && v.boolValue;
}

// ── Status Bar Old School ─────────────────────────────────────────────────────────

+ (void)applyStatusBarOldSchool:(BOOL)on {
    // IGThrowbackChromeExperimentHelper — módulo IGLiquidGlassExperimentHelper
    // Mangled: _TtC(29)IGLiquidGlassExperimentHelper(33)IGThrowbackChromeExperimentHelper
    // Não encontrado no binário estático analisado, mas confirmado presente no device
    // via FLEX ("Direct override: ON"). setRuntimeBoolOverride: faz no-op se classe ausente.
    NSString *cls = @"_TtC29IGLiquidGlassExperimentHelper33IGThrowbackChromeExperimentHelper";
    on ? SRBO(cls, @"isEnabled", NO, YES) : CRBO(cls, @"isEnabled", NO);
}

+ (BOOL)isStatusBarOldSchoolActive {
    NSString *cls = @"_TtC29IGLiquidGlassExperimentHelper33IGThrowbackChromeExperimentHelper";
    NSNumber *v = [SCIGatingCatalog runtimeBoolOverrideStateForClass:cls
                                                            selector:@"isEnabled"
                                                         classMethod:NO];
    return v != nil && v.boolValue;
}

// ── Story Tray ────────────────────────────────────────────────────────────────────

+ (void)applyStoryTray:(BOOL)on {
    // IGNavConfiguration.IGHomecomingConfiguration — Swift, instance methods
    // Mangled: _TtC(18)IGNavConfiguration(25)IGHomecomingConfiguration
    // Seletores confirmados via disasm FBSharedFramework + screenshots FLEX
    NSString *hc = @"_TtC18IGNavConfiguration25IGHomecomingConfiguration";
    for (NSString *s in @[
        @"isStoriesTrayOnAllTabsEnabled",
        @"showCinemaStoriesTrayOnSwipeUp",
        @"isDynamicTabStoryGridEnabled",
    ]) { on ? SRBO(hc, s, NO, YES) : CRBO(hc, s, NO); }
}

+ (BOOL)isStoryTrayActive {
    NSString *hc = @"_TtC18IGNavConfiguration25IGHomecomingConfiguration";
    NSNumber *v = [SCIGatingCatalog runtimeBoolOverrideStateForClass:hc
                                                            selector:@"isStoriesTrayOnAllTabsEnabled"
                                                         classMethod:NO];
    return v != nil && v.boolValue;
}

@end
