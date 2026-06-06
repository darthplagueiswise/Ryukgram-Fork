// SCIBulkGatingPresets.h
// Ações em massa para os presets de Feature Gating.
// Usa SCIGatingCatalog.setRuntimeBoolOverride: — o mesmo mecanismo que
// o Feature Gatings UI (mostra "forced ON via getter hook").
// Hooks são instalados imediatamente, sem restart.
// Overrides são persistidos em NSUserDefaults e reaplicados no launch.

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

@interface SCIBulkGatingPresets : NSObject

// ── Liquid Glass (23 overrides: 22 ON + isProfileSegmentedTabsGlassDisabled=OFF) ──
// Classes: IGDSLauncherConfig (9), IGDSAlertDialogLiquidGlass (+1 cls),
//          IGLiquidGlass (+1 cls), IGLiquidGlassNavigationExperimentHelper (6 inst),
//          IGLiquidGlassInteractiveTabBar (6 inst)
+ (void)applyLiquidGlass:(BOOL)on;
+ (BOOL)isLiquidGlassActive;

// ── Status Bar Old School ────────────────────────────────────────────────────────
// IGThrowbackChromeExperimentHelper.isEnabled → torna a status bar azul/clássica.
// Classe Swift em módulo IGLiquidGlassExperimentHelper; não está no binário estático
// analisado mas existe no device (confirmado via "Direct override: ON" no FLEX).
+ (void)applyStatusBarOldSchool:(BOOL)on;
+ (BOOL)isStatusBarOldSchoolActive;

// ── Story Tray (3 overrides) ─────────────────────────────────────────────────────
// IGNavConfiguration.IGHomecomingConfiguration:
//   isStoriesTrayOnAllTabsEnabled, showCinemaStoriesTrayOnSwipeUp,
//   isDynamicTabStoryGridEnabled
+ (void)applyStoryTray:(BOOL)on;
+ (BOOL)isStoryTrayActive;

@end

NS_ASSUME_NONNULL_END
