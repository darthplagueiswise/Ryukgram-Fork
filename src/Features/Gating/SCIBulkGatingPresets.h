// SCIBulkGatingPresets.h
// Ações em massa para os presets de Feature Gating.
// Usa SCIGatingCatalog.setRuntimeBoolOverride: — o mesmo mecanismo que
// o Feature Gatings UI (mostra "forced ON via getter hook").
// Hooks são instalados por ação explícita, sem restart.
// Overrides são persistidos em NSUserDefaults, mas não são reinstalados automaticamente no launch.

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

@interface SCIBulkGatingPresets : NSObject

// ── Liquid Glass ─────────────────────────────────────────────────────────────
// IGDSLauncherConfig  (ObjC, inst, 11 flags — confirmados via disasm FBSharedFramework)
// IGDSAlertDialogLiquidGlass (_TtC26…, Swift class method +isEnabled)
// IGLiquidGlass (_TtC13…, Swift class method +isEnabled)
// IGLiquidGlassNavigationExperimentHelper (_TtC29…, Swift inst, 5 flags)
// IGLiquidGlassInteractiveTabBar (ObjC, inst, 6 flags)
// Total: ~25 overrides
+ (void)applyLiquidGlass:(BOOL)on;
+ (BOOL)isLiquidGlassActive;

// ── Status Bar Old School ─────────────────────────────────────────────────────
// IGThrowbackChromeExperimentHelper — módulo IGLiquidGlassExperimentHelper
// (carregado dinamicamente em runtime; setRuntimeBoolOverride faz no-op se ausente)
+ (void)applyStatusBarOldSchool:(BOOL)on;
+ (BOOL)isStatusBarOldSchoolActive;

// ── Story Tray ────────────────────────────────────────────────────────────────
// _TtC18IGNavConfiguration25IGHomecomingConfiguration — 6 flags confirmados via FLEX:
//   isStoriesTrayOnAllTabsEnabled · showCinemaStoriesTrayOnSwipeUp ·
//   isDynamicTabStoryGridEnabled · isVerticalStoriesTray ·
//   isFeedCullingOnStoriesAccessEnabled · isHomecomingStoriesAccessFaceClusterEnabled
// _TtC18IGNavConfiguration18IGNavConfiguration — 1 flag:
//   enableStoriesTabHeaderButton
+ (void)applyStoryTray:(BOOL)on;
+ (BOOL)isStoryTrayActive;

// ── Instagram Wordmark ────────────────────────────────────────────────────────
// IGDSLauncherConfig: isIGWordmark1aAltEnabled / isIGWordmark1aEnabled /
//                     isIGWordmark1bAltEnabled / isIGWordmark1bEnabled
// variant: 0=off, 1=1a-alt, 2=1a, 3=1b-alt, 4=1b
// Todos mutually-exclusive; applyWordmark: garante que só um está ON.
+ (void)applyWordmark:(NSInteger)variant;
+ (NSInteger)activeWordmarkVariant;

// ── Startup ───────────────────────────────────────────────────────────────────
// Instala SCIPrefObserver para o seletor de wordmark.
// Não deve ser usado para reinstalar hooks no %ctor; use apenas para ações explícitas de UI.
+ (void)installWordmarkPrefObserver;


+ (NSArray<NSString *> *)igWordmarkModes;
+ (void)applyIGWordmarkMode:(NSString *)mode;
+ (NSString *)currentIGWordmarkMode;

@end

NS_ASSUME_NONNULL_END
