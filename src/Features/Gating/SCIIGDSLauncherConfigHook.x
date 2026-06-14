// SCIIGDSLauncherConfigHook.x — LiquidGlass / Prism / Nav / Wordmark forcing.
//
// FIX: the getters used to be hooked as `%hook IGDSLauncherConfig`, but that
// class does not exist in Instagram 433. Authoritative binary analysis shows the
// real owner is the Swift class BSLDSConfig (runtime name
// _TtC11BSLDSConfig11BSLDSConfig) — every flag is an @objc `B16@0:8` getter on it.
// Because it is a Swift class resolved by runtime name, the correct mechanism is
// baseline §4: MSHookMessageEx on objc_getClass(...), one orig per selector,
// ABI-compatible replacement, install gated by a cheap pref read in %ctor. Each
// replacement reads its pref live via SCIUtils, so once installed the toggles
// apply without restart (first enable from an all-off launch needs one relaunch).

#import <Foundation/Foundation.h>
#import <objc/runtime.h>
#import <substrate.h>
#import "../../Utils.h"

static BOOL SCIIGDSBool(NSString *key) { return [SCIUtils getBoolPref:key]; }
static NSString *SCIIGDSString(NSString *key) { return [SCIUtils getStringPref:key] ?: @""; }

static BOOL SCIIGDSAll(void) { return SCIIGDSBool(@"sci_igds_launcher_all"); }
static BOOL SCIIGDSLiquidGlass(void) { return SCIIGDSAll() || SCIIGDSBool(@"sci_igds_liquidglass") || SCIIGDSBool(@"sci_apply_liquidglass"); }
static BOOL SCIIGDSPrism(void) { return SCIIGDSAll() || SCIIGDSBool(@"sci_igds_prism"); }
static BOOL SCIIGDSLGk(NSString *key) { return SCIIGDSLiquidGlass() || SCIIGDSBool(key); }
static BOOL SCIIGDSNavk(NSString *key) { return SCIIGDSAll() || SCIIGDSBool(key); }
static NSString *SCIIGDSWordmarkVariant(void) {
	NSString *variant = SCIIGDSString(@"sci_ig_wordmark_variant");
	if (!variant.length) variant = SCIIGDSString(@"sci_ig_wordmark_mode");
	return variant ?: @"off";
}

#define IGDS_ALL(fn) \
	static BOOL (*orig_##fn)(id,SEL)=NULL; \
	static BOOL hook_##fn(id s, SEL c){ return SCIIGDSAll() ? YES : (orig_##fn?orig_##fn(s,c):NO); }
#define IGDS_PRISM(fn) \
	static BOOL (*orig_##fn)(id,SEL)=NULL; \
	static BOOL hook_##fn(id s, SEL c){ return SCIIGDSPrism() ? YES : (orig_##fn?orig_##fn(s,c):NO); }
#define IGDS_LG(fn, key) \
	static BOOL (*orig_##fn)(id,SEL)=NULL; \
	static BOOL hook_##fn(id s, SEL c){ return SCIIGDSLGk(@key) ? YES : (orig_##fn?orig_##fn(s,c):NO); }
#define IGDS_NAV(fn, key) \
	static BOOL (*orig_##fn)(id,SEL)=NULL; \
	static BOOL hook_##fn(id s, SEL c){ return SCIIGDSNavk(@key) ? YES : (orig_##fn?orig_##fn(s,c):NO); }
#define IGDS_WM(fn, key, variant) \
	static BOOL (*orig_##fn)(id,SEL)=NULL; \
	static BOOL hook_##fn(id s, SEL c){ return (SCIIGDSBool(@key) || [SCIIGDSWordmarkVariant() isEqualToString:@variant]) ? YES : (orig_##fn?orig_##fn(s,c):NO); }

IGDS_ALL(canSupportLauncher)

IGDS_LG(isLiquidGlassInAppNotificationEnabled,            "sci_igds_lg_inappnotif")
IGDS_LG(isLiquidGlassToastEnabled,                        "sci_igds_lg_toast")
IGDS_LG(isLiquidGlassToastPeekEnabled,                    "sci_igds_lg_toastpeek")
IGDS_LG(isLiquidGlassIconBarButtonEnabled,                "sci_igds_lg_iconbarbtn")
IGDS_LG(isLiquidGlassNavigationContentStylePinningEnabled,"sci_igds_lg_navstylepin")
IGDS_LG(isLiquidGlassEaseInOutBlurEnabled,                "sci_igds_lg_easeinout")
IGDS_LG(isLiquidGlassCGContextBlurEnabled,                "sci_igds_lg_cgblur")
IGDS_LG(canUseInternalLiquidGlassDebugger,                "sci_igds_lg_debugger")
IGDS_LG(isContextMenuMigrationEnabled,                    "sci_igds_nav_ctxmenu")

IGDS_PRISM(isPrismControlsEnabled)
IGDS_PRISM(isPrismDefaultTooltipEnabled)
IGDS_PRISM(isPrismToastsEnabled)
IGDS_PRISM(isPrismAlertDialogEnabled)
IGDS_PRISM(isPrismAvatarRingEnabled)
IGDS_PRISM(isPrismContextMenuEnabled)
IGDS_PRISM(isPrismContextMenuRefactorEnabled)
IGDS_PRISM(isPrismIndigoButtonEnabled)
IGDS_PRISM(isPrismIndigoButtonM1DirectEnabled)
IGDS_PRISM(isPrismIndigoActionCellsEnabled)
IGDS_PRISM(isIGBPrismEnabled)
IGDS_PRISM(isPrismOverflowMenuEnabled)
IGDS_PRISM(isPrismOverflowMenuStampWidthIncreased)
IGDS_PRISM(isPrismBottomSheetEnabled)
IGDS_PRISM(isPrismCreationIconsEnabled)
IGDS_PRISM(isPrismMediaButtonsEnabled)
IGDS_PRISM(isPrismCommentsEmptyStateEnabled)
IGDS_PRISM(isPrismAllUserAssetsEnabled)
IGDS_PRISM(isPrismFollowRelatedUserAssetsEnabled)
IGDS_PRISM(_isPrismSecondaryNonUserIconsEnabled)
IGDS_PRISM(isPrismDividersUpdateEnabled)
IGDS_PRISM(isPrismDividersCommentsUpdateEnabled)
IGDS_PRISM(isPrismDividersEditReelEnabled)
IGDS_PRISM(isPrismDividersNotificationsUpdateEnabled)
IGDS_PRISM(isPrismDividersProfileUpdateEnabled)
IGDS_PRISM(isPrismDividersShareSheetUpdateEnabled)

IGDS_NAV(isNavPushRoundedCornersEnabled,                  "sci_igds_nav_rounded")
IGDS_NAV(isTransitionZoomCustomizationEnabled,            "sci_igds_nav_tzoom")
IGDS_NAV(isNativeBottomsheetForiPhoneEnabled,             "sci_igds_nav_bottomsheet")
IGDS_NAV(isNativeBottomsheetForiPhoneOnAllSurfacesEnabled,"sci_igds_nav_bottomsheet")
IGDS_NAV(isAsyncFontRegistrationEnabled,                  "sci_igds_async_font")

IGDS_WM(isIGWordmark1aEnabled,    "sci_igds_wordmark_isIGWordmark1aEnabled",    "1a")
IGDS_WM(isIGWordmark1aAltEnabled, "sci_igds_wordmark_isIGWordmark1aAltEnabled", "1a_alt")
IGDS_WM(isIGWordmark1bEnabled,    "sci_igds_wordmark_isIGWordmark1bEnabled",    "1b")
IGDS_WM(isIGWordmark1bAltEnabled, "sci_igds_wordmark_isIGWordmark1bAltEnabled", "1b_alt")

#define IGDS_INSTALL(fn) do { \
		SEL _s = NSSelectorFromString(@#fn); \
		if (class_getInstanceMethod(cls, _s)) MSHookMessageEx(cls, _s, (IMP)hook_##fn, (IMP *)&orig_##fn); \
	} while(0)

static void SCIInstallIGDSHooks(void) {
	Class cls = objc_getClass("_TtC11BSLDSConfig11BSLDSConfig");
	if (!cls) return;
	IGDS_INSTALL(canSupportLauncher);
	IGDS_INSTALL(isLiquidGlassInAppNotificationEnabled);
	IGDS_INSTALL(isLiquidGlassToastEnabled);
	IGDS_INSTALL(isLiquidGlassToastPeekEnabled);
	IGDS_INSTALL(isLiquidGlassIconBarButtonEnabled);
	IGDS_INSTALL(isLiquidGlassNavigationContentStylePinningEnabled);
	IGDS_INSTALL(isLiquidGlassEaseInOutBlurEnabled);
	IGDS_INSTALL(isLiquidGlassCGContextBlurEnabled);
	IGDS_INSTALL(canUseInternalLiquidGlassDebugger);
	IGDS_INSTALL(isContextMenuMigrationEnabled);
	IGDS_INSTALL(isPrismControlsEnabled);
	IGDS_INSTALL(isPrismDefaultTooltipEnabled);
	IGDS_INSTALL(isPrismToastsEnabled);
	IGDS_INSTALL(isPrismAlertDialogEnabled);
	IGDS_INSTALL(isPrismAvatarRingEnabled);
	IGDS_INSTALL(isPrismContextMenuEnabled);
	IGDS_INSTALL(isPrismContextMenuRefactorEnabled);
	IGDS_INSTALL(isPrismIndigoButtonEnabled);
	IGDS_INSTALL(isPrismIndigoButtonM1DirectEnabled);
	IGDS_INSTALL(isPrismIndigoActionCellsEnabled);
	IGDS_INSTALL(isIGBPrismEnabled);
	IGDS_INSTALL(isPrismOverflowMenuEnabled);
	IGDS_INSTALL(isPrismOverflowMenuStampWidthIncreased);
	IGDS_INSTALL(isPrismBottomSheetEnabled);
	IGDS_INSTALL(isPrismCreationIconsEnabled);
	IGDS_INSTALL(isPrismMediaButtonsEnabled);
	IGDS_INSTALL(isPrismCommentsEmptyStateEnabled);
	IGDS_INSTALL(isPrismAllUserAssetsEnabled);
	IGDS_INSTALL(isPrismFollowRelatedUserAssetsEnabled);
	IGDS_INSTALL(_isPrismSecondaryNonUserIconsEnabled);
	IGDS_INSTALL(isPrismDividersUpdateEnabled);
	IGDS_INSTALL(isPrismDividersCommentsUpdateEnabled);
	IGDS_INSTALL(isPrismDividersEditReelEnabled);
	IGDS_INSTALL(isPrismDividersNotificationsUpdateEnabled);
	IGDS_INSTALL(isPrismDividersProfileUpdateEnabled);
	IGDS_INSTALL(isPrismDividersShareSheetUpdateEnabled);
	IGDS_INSTALL(isNavPushRoundedCornersEnabled);
	IGDS_INSTALL(isTransitionZoomCustomizationEnabled);
	IGDS_INSTALL(isNativeBottomsheetForiPhoneEnabled);
	IGDS_INSTALL(isNativeBottomsheetForiPhoneOnAllSurfacesEnabled);
	IGDS_INSTALL(isAsyncFontRegistrationEnabled);
	IGDS_INSTALL(isIGWordmark1aEnabled);
	IGDS_INSTALL(isIGWordmark1aAltEnabled);
	IGDS_INSTALL(isIGWordmark1bEnabled);
	IGDS_INSTALL(isIGWordmark1bAltEnabled);
}

static BOOL SCIIGDSAnyPrefEnabled(void) {
	NSString *v = SCIIGDSWordmarkVariant();
	if (SCIIGDSAll() || SCIIGDSLiquidGlass() || SCIIGDSPrism()) return YES;
	for (NSString *k in @[@"sci_igds_lg_inappnotif", @"sci_igds_lg_toast", @"sci_igds_lg_toastpeek",
			@"sci_igds_lg_iconbarbtn", @"sci_igds_lg_navstylepin", @"sci_igds_lg_easeinout",
			@"sci_igds_lg_cgblur", @"sci_igds_lg_debugger", @"sci_igds_nav_ctxmenu",
			@"sci_igds_nav_rounded", @"sci_igds_nav_tzoom", @"sci_igds_nav_bottomsheet",
			@"sci_igds_async_font", @"sci_igds_wordmark_isIGWordmark1aEnabled",
			@"sci_igds_wordmark_isIGWordmark1aAltEnabled", @"sci_igds_wordmark_isIGWordmark1bEnabled",
			@"sci_igds_wordmark_isIGWordmark1bAltEnabled"]) {
		if (SCIIGDSBool(k)) return YES;
	}
	return [v isEqualToString:@"1a"] || [v isEqualToString:@"1a_alt"] ||
		   [v isEqualToString:@"1b"] || [v isEqualToString:@"1b_alt"];
}

// Kept as a safe post-launch no-op for any caller that pings after a settings
// change; install only ever happens once from %ctor.
void SCIIGDSEnsureHooksInstalled(void) { }

%ctor {
	@autoreleasepool {
		if (!SCIIGDSAnyPrefEnabled()) return;
		SCIInstallIGDSHooks();
	}
}
