// SCIIGDSLauncherConfigHook.x
//
// IGDSLauncherConfig BOOL getter hooks, priv-main style.
// ObjC BOOL getters use Logos %hook + %group/%init and read prefs live through
// SCIUtils, so toggles apply live after the hook group was installed at launch.
// No MSHookMessageEx, no class_replaceMethod, no %hookf, no arbitrary runtime
// selector patching.

#import <Foundation/Foundation.h>
#import "../../Utils.h"

static BOOL SCIIGDSBool(NSString *key) { return [SCIUtils getBoolPref:key]; }
static NSString *SCIIGDSString(NSString *key) { return [SCIUtils getStringPref:key] ?: @""; }

static BOOL SCIIGDSAll(void) { return SCIIGDSBool(@"sci_igds_launcher_all"); }
static BOOL SCIIGDSLiquidGlass(void) { return SCIIGDSAll() || SCIIGDSBool(@"sci_igds_liquidglass") || SCIIGDSBool(@"sci_apply_liquidglass"); }
static BOOL SCIIGDSPrism(void) { return SCIIGDSAll() || SCIIGDSBool(@"sci_igds_prism"); }
static BOOL SCIIGDSLG(NSString *key) { return SCIIGDSLiquidGlass() || SCIIGDSBool(key); }
static BOOL SCIIGDSNav(NSString *key) { return SCIIGDSAll() || SCIIGDSBool(key); }
static NSString *SCIIGDSWordmarkVariant(void) {
	NSString *variant = SCIIGDSString(@"sci_ig_wordmark_variant");
	if (!variant.length) variant = SCIIGDSString(@"sci_ig_wordmark_mode");
	return variant ?: @"off";
}

static BOOL SCIIGDSAnyPrefEnabled(void) {
	NSString *variant = SCIIGDSWordmarkVariant();
	return SCIIGDSAll() || SCIIGDSLiquidGlass() || SCIIGDSPrism() ||
		   SCIIGDSBool(@"sci_igds_lg_inappnotif") || SCIIGDSBool(@"sci_igds_lg_toast") ||
		   SCIIGDSBool(@"sci_igds_lg_toastpeek") || SCIIGDSBool(@"sci_igds_lg_iconbarbtn") ||
		   SCIIGDSBool(@"sci_igds_lg_navstylepin") || SCIIGDSBool(@"sci_igds_lg_easeinout") ||
		   SCIIGDSBool(@"sci_igds_lg_cgblur") || SCIIGDSBool(@"sci_igds_lg_glyphopt") ||
		   SCIIGDSBool(@"sci_igds_lg_debugger") || SCIIGDSBool(@"sci_igds_nav_ctxmenu") ||
		   SCIIGDSBool(@"sci_igds_nav_rounded") || SCIIGDSBool(@"sci_igds_nav_tzoom") ||
		   SCIIGDSBool(@"sci_igds_nav_bottomsheet") || SCIIGDSBool(@"sci_igds_async_font") ||
		   SCIIGDSBool(@"sci_igds_wordmark_isIGWordmark1aEnabled") ||
		   SCIIGDSBool(@"sci_igds_wordmark_isIGWordmark1aAltEnabled") ||
		   SCIIGDSBool(@"sci_igds_wordmark_isIGWordmark1bEnabled") ||
		   SCIIGDSBool(@"sci_igds_wordmark_isIGWordmark1bAltEnabled") ||
		   [variant isEqualToString:@"1a"] || [variant isEqualToString:@"1a_alt"] ||
		   [variant isEqualToString:@"1b"] || [variant isEqualToString:@"1b_alt"];
}

%group SCIIGDSLauncherConfigGroup
%hook IGDSLauncherConfig

- (BOOL)canSupportLauncher { return SCIIGDSAll() ? YES : %orig; }

- (BOOL)isLiquidGlassInAppNotificationEnabled { return SCIIGDSLG(@"sci_igds_lg_inappnotif") ? YES : %orig; }
- (BOOL)isLiquidGlassToastEnabled { return SCIIGDSLG(@"sci_igds_lg_toast") ? YES : %orig; }
- (BOOL)isLiquidGlassToastPeekEnabled { return SCIIGDSLG(@"sci_igds_lg_toastpeek") ? YES : %orig; }
- (BOOL)isLiquidGlassIconBarButtonEnabled { return SCIIGDSLG(@"sci_igds_lg_iconbarbtn") ? YES : %orig; }
- (BOOL)isLiquidGlassNavigationContentStylePinningEnabled { return SCIIGDSLG(@"sci_igds_lg_navstylepin") ? YES : %orig; }
- (BOOL)isLiquidGlassEaseInOutBlurEnabled { return SCIIGDSLG(@"sci_igds_lg_easeinout") ? YES : %orig; }
- (BOOL)isLiquidGlassCGContextBlurEnabled { return SCIIGDSLG(@"sci_igds_lg_cgblur") ? YES : %orig; }
- (BOOL)canUseInternalLiquidGlassDebugger { return SCIIGDSLG(@"sci_igds_lg_debugger") ? YES : %orig; }
- (BOOL)isContextMenuMigrationEnabled { return SCIIGDSLG(@"sci_igds_nav_ctxmenu") ? YES : %orig; }

- (BOOL)isPrismControlsEnabled { return SCIIGDSPrism() ? YES : %orig; }
- (BOOL)isPrismDefaultTooltipEnabled { return SCIIGDSPrism() ? YES : %orig; }
- (BOOL)isPrismToastsEnabled { return SCIIGDSPrism() ? YES : %orig; }
- (BOOL)isPrismAlertDialogEnabled { return SCIIGDSPrism() ? YES : %orig; }
- (BOOL)isPrismAvatarRingEnabled { return SCIIGDSPrism() ? YES : %orig; }
- (BOOL)isPrismContextMenuEnabled { return SCIIGDSPrism() ? YES : %orig; }
- (BOOL)isPrismContextMenuRefactorEnabled { return SCIIGDSPrism() ? YES : %orig; }
- (BOOL)isPrismIndigoButtonEnabled { return SCIIGDSPrism() ? YES : %orig; }
- (BOOL)isPrismIndigoButtonM1DirectEnabled { return SCIIGDSPrism() ? YES : %orig; }
- (BOOL)isPrismIndigoActionCellsEnabled { return SCIIGDSPrism() ? YES : %orig; }
- (BOOL)isIGBPrismEnabled { return SCIIGDSPrism() ? YES : %orig; }
- (BOOL)isPrismOverflowMenuEnabled { return SCIIGDSPrism() ? YES : %orig; }
- (BOOL)isPrismOverflowMenuStampWidthIncreased { return SCIIGDSPrism() ? YES : %orig; }
- (BOOL)isPrismBottomSheetEnabled { return SCIIGDSPrism() ? YES : %orig; }
- (BOOL)isPrismCreationIconsEnabled { return SCIIGDSPrism() ? YES : %orig; }
- (BOOL)isPrismMediaButtonsEnabled { return SCIIGDSPrism() ? YES : %orig; }
- (BOOL)isPrismCommentsEmptyStateEnabled { return SCIIGDSPrism() ? YES : %orig; }
- (BOOL)isPrismAllUserAssetsEnabled { return SCIIGDSPrism() ? YES : %orig; }
- (BOOL)isPrismFollowRelatedUserAssetsEnabled { return SCIIGDSPrism() ? YES : %orig; }
- (BOOL)_isPrismSecondaryNonUserIconsEnabled { return SCIIGDSPrism() ? YES : %orig; }
- (BOOL)isPrismDividersUpdateEnabled { return SCIIGDSPrism() ? YES : %orig; }
- (BOOL)isPrismDividersCommentsUpdateEnabled { return SCIIGDSPrism() ? YES : %orig; }
- (BOOL)isPrismDividersEditReelEnabled { return SCIIGDSPrism() ? YES : %orig; }
- (BOOL)isPrismDividersNotificationsUpdateEnabled { return SCIIGDSPrism() ? YES : %orig; }
- (BOOL)isPrismDividersProfileUpdateEnabled { return SCIIGDSPrism() ? YES : %orig; }
- (BOOL)isPrismDividersShareSheetUpdateEnabled { return SCIIGDSPrism() ? YES : %orig; }

- (BOOL)isNavPushRoundedCornersEnabled { return SCIIGDSNav(@"sci_igds_nav_rounded") ? YES : %orig; }
- (BOOL)isTransitionZoomCustomizationEnabled { return SCIIGDSNav(@"sci_igds_nav_tzoom") ? YES : %orig; }
- (BOOL)isNativeBottomsheetForiPhoneEnabled { return SCIIGDSNav(@"sci_igds_nav_bottomsheet") ? YES : %orig; }
- (BOOL)isNativeBottomsheetForiPhoneOnAllSurfacesEnabled { return SCIIGDSNav(@"sci_igds_nav_bottomsheet") ? YES : %orig; }
- (BOOL)isAsyncFontRegistrationEnabled { return SCIIGDSNav(@"sci_igds_async_font") ? YES : %orig; }

- (BOOL)isIGWordmark1aEnabled { return (SCIIGDSBool(@"sci_igds_wordmark_isIGWordmark1aEnabled") || [SCIIGDSWordmarkVariant() isEqualToString:@"1a"]) ? YES : %orig; }
- (BOOL)isIGWordmark1aAltEnabled { return (SCIIGDSBool(@"sci_igds_wordmark_isIGWordmark1aAltEnabled") || [SCIIGDSWordmarkVariant() isEqualToString:@"1a_alt"]) ? YES : %orig; }
- (BOOL)isIGWordmark1bEnabled { return (SCIIGDSBool(@"sci_igds_wordmark_isIGWordmark1bEnabled") || [SCIIGDSWordmarkVariant() isEqualToString:@"1b"]) ? YES : %orig; }
- (BOOL)isIGWordmark1bAltEnabled { return (SCIIGDSBool(@"sci_igds_wordmark_isIGWordmark1bAltEnabled") || [SCIIGDSWordmarkVariant() isEqualToString:@"1b_alt"]) ? YES : %orig; }

%end
%end

void SCIIGDSEnsureHooksInstalled(void) {
	// Intentionally no-op: the hook group is installed only from %ctor.
	// Existing installed getters read SCIUtils prefs live; first enable from an
	// all-off launch takes effect after relaunch.
}

%ctor {
	@autoreleasepool {
		if (!SCIIGDSAnyPrefEnabled()) return;
		%init(SCIIGDSLauncherConfigGroup);
	}
}
