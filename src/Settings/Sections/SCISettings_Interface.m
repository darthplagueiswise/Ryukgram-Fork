#import "SCISettingsSections.h"
#import "../SCIAppIconPickerViewController.h"
#import "../../InstagramHeaders.h"

@implementation SCITweakSettings (Section_Interface)

+ (SCISetting *)interfaceNavCell {
	return [SCISetting navigationCellWithTitle:SCILocalized(@"Interface")

										   subtitle:@""
											   icon:[SCISymbol symbolWithIGName:@"layout" fallback:@"hand.draw.fill"]
										navSections:@[
										@{
											@"header": SCILocalized(@"Home shortcut button"),
											@"footer": SCILocalized(@"Adds an extra shortcut button beside the create-post + button on the home top bar."),
											@"rows": @[
												[SCISetting switchCellWithTitle:SCILocalized(@"Show home shortcut button")
																	   subtitle:SCILocalized(@"Show the extra button on the home top bar")
																	defaultsKey:@"home_shortcut_enabled" requiresRestart:YES],
												({ SCISetting *s = [SCISetting navigationCellWithTitle:SCILocalized(@"Configure button")
																		   subtitle:SCILocalized(@"Choose icon, reorder actions, and enable menu items")
																			   icon:[SCISymbol symbolWithIGName:@"home" fallback:@"house"]
																	 viewController:[SCIHomeShortcutConfigViewController new]];
												   s.whatsNewID = @"ui_homeshortcut_config"; s; }),
											]
										},
										@{
											@"header": SCILocalized(@"Global Action Icons"),
											@"footer": SCILocalized(@"Used across feed, stories, reels, and DMs."),
											@"rows": @[
												[self actionIconNavCell],
											]
										},
										@{
											@"header": SCILocalized(@"Notifications"),
											@"footer": SCILocalized(@"Universal in-app notifications. Pick style, position, per-action routing (custom pill / IG-native / off)."),
											@"rows": @[
												({ SCISetting *s = [SCINotificationSettings notificationsNavCell]; s.whatsNewID = @"ui_notifications"; s; }),
											]
										},
										@{
											@"header": SCILocalized(@"Tab bar"),
											@"rows": @[
												[SCISetting menuCellWithTitle:SCILocalized(@"Icon order") subtitle:SCILocalized(@"The order of the icons on the bottom navigation bar") menu:[self menus][@"nav_icon_ordering"]],
												[SCISetting menuCellWithTitle:SCILocalized(@"Swipe between tabs") subtitle:SCILocalized(@"Lets you swipe to switch between navigation bar tabs") menu:[self menus][@"swipe_nav_tabs"]],
												[SCISetting menuCellWithTitle:SCILocalized(@"Launch tab") subtitle:SCILocalized(@"Tab the app opens to. Ignored when Messages-only is on") menu:[self menus][@"launch_tab"]],
											]
										},
										@{
											@"header": SCILocalized(@"Hiding tabs"),
											@"rows": @[
												[SCISetting switchCellWithTitle:SCILocalized(@"Hide feed tab") subtitle:SCILocalized(@"Hides the feed/home tab on the bottom navigation bar") defaultsKey:@"hide_feed_tab" requiresRestart:YES],
												[SCISetting switchCellWithTitle:SCILocalized(@"Hide explore tab") subtitle:SCILocalized(@"Hides the explore/search tab on the bottom navigation bar") defaultsKey:@"hide_explore_tab" requiresRestart:YES],
												[SCISetting switchCellWithTitle:SCILocalized(@"Hide reels tab") subtitle:SCILocalized(@"Hides the reels tab on the bottom navigation bar") defaultsKey:@"hide_reels_tab" requiresRestart:YES],
												[SCISetting switchCellWithTitle:SCILocalized(@"Hide create tab") subtitle:SCILocalized(@"Hides the create tab on the bottom navigation bar") defaultsKey:@"hide_create_tab" requiresRestart:YES],
												[SCISetting switchCellWithTitle:SCILocalized(@"Hide messages tab") subtitle:SCILocalized(@"Hides the direct messages tab on the bottom navigation bar") defaultsKey:@"hide_messages_tab" requiresRestart:YES]
											]
										},
										@{
											@"header": SCILocalized(@"Messages-only mode"),
											@"footer": SCILocalized(@"Hides every tab except DM inbox + profile and forces launch into the inbox. Settings shortcut moves to long-press on the inbox tab."),
											@"rows": @[
												[SCISetting switchCellWithTitle:SCILocalized(@"Messages only") subtitle:SCILocalized(@"Turn IG into a DM-only client") defaultsKey:@"messages_only" requiresRestart:YES],
												[SCISetting switchCellWithTitle:SCILocalized(@"Hide tab bar") subtitle:SCILocalized(@"Also hide the bottom tab bar — only the inbox is visible") defaultsKey:@"messages_only_hide_tabbar" requiresRestart:YES],
											]
										},
										@{
											@"header": SCILocalized(@"Liquid Glass — Buttons & Notifications"),
											@"footer": SCILocalized(@"iOS 26+ visual API. Each switch hooks one IGDSLauncherConfig / SwizzleToggle getter; off falls through to the app's original value."),
											@"rows": @[
												[SCISetting switchCellWithTitle:SCILocalized(@"Native Liquid Glass") subtitle:SCILocalized(@"Enables the coherent iOS 26 glass path: buttons, navigation, rendering, blur and tab bar style") defaultsKey:@"lg_native_enabled" requiresRestart:YES],
												[SCISetting switchCellWithTitle:SCILocalized(@"LG button swizzle") subtitle:SCILocalized(@"IGLiquidGlassSwizzleToggle.isEnabled — the actual button shape rendering") defaultsKey:@"lg_swizzle_buttons" requiresRestart:YES],
												[SCISetting switchCellWithTitle:SCILocalized(@"LG in-app notifications") subtitle:SCILocalized(@"IGDSLauncherConfig.isLiquidGlassInAppNotificationEnabled") defaultsKey:@"lg_inapp_notif" requiresRestart:YES],
												[SCISetting switchCellWithTitle:SCILocalized(@"LG toasts") subtitle:SCILocalized(@"IGDSLauncherConfig.isLiquidGlassToastEnabled") defaultsKey:@"lg_toast" requiresRestart:YES],
												[SCISetting switchCellWithTitle:SCILocalized(@"LG ease-in/out blur") subtitle:SCILocalized(@"IGDSLauncherConfig.isLiquidGlassEaseInOutBlurEnabled") defaultsKey:@"lg_ease_in_out_blur" requiresRestart:YES],
											]
										},
										@{
											@"header": SCILocalized(@"Liquid Glass — Navigation"),
											@"footer": SCILocalized(@"IGLiquidGlassNavigationExperimentHelper. The init hook applies override APIs (overrideIsEnabled:, overrideIsGlassRenderingOptimizationEnabled:, ...) on the shared singleton."),
											@"rows": @[
												[SCISetting switchCellWithTitle:SCILocalized(@"LG navigation (master)") subtitle:SCILocalized(@"isEnabled + overrideIsEnabled:") defaultsKey:@"lg_nav_enabled" requiresRestart:YES],
												[SCISetting switchCellWithTitle:SCILocalized(@"LG home feed header") subtitle:SCILocalized(@"isHomeFeedHeaderEnabled") defaultsKey:@"lg_home_feed_header" requiresRestart:YES],
												[SCISetting switchCellWithTitle:SCILocalized(@"LG glass rendering optimization") subtitle:SCILocalized(@"overrideIsGlassRenderingOptimizationEnabled:") defaultsKey:@"lg_glass_rendering" requiresRestart:YES],
												[SCISetting switchCellWithTitle:SCILocalized(@"LG glass background steps") subtitle:SCILocalized(@"overrideGlassBackgroundAlphaDiscreteSteps:") defaultsKey:@"lg_glass_background_steps" requiresRestart:YES],
												[SCISetting switchCellWithTitle:SCILocalized(@"LG legibility blur") subtitle:SCILocalized(@"overrideIsLegibilityBlurEnabled:") defaultsKey:@"lg_legibility_blur" requiresRestart:YES],
												[SCISetting switchCellWithTitle:SCILocalized(@"LG profile nav bar height match") subtitle:SCILocalized(@"overrideIsProfileOtherNavBarHeightMatchSelf:") defaultsKey:@"lg_profile_navbar_match" requiresRestart:YES],
												[SCISetting switchCellWithTitle:SCILocalized(@"LG profile segmented tabs glass") subtitle:SCILocalized(@"Glass ON for profile segmented tabs (isProfileSegmentedTabsGlassDisabled = NO)") defaultsKey:@"lg_profile_segmented_tabs_glass" requiresRestart:YES],
											]
										},
										@{
											@"header": SCILocalized(@"Liquid Glass — Surfaces (Tab Bar)"),
											@"footer": SCILocalized(@"Fishhook on IG-internal C functions gating floating / dynamic / homecoming tab bar variants. Works pre-iOS 26."),
											@"rows": @[
												[SCISetting switchCellWithTitle:SCILocalized(@"Floating tab bar") subtitle:SCILocalized(@"IGFloatingTabBarEnabled") defaultsKey:@"lg_floating_tab_bar" requiresRestart:YES],
												[SCISetting switchCellWithTitle:SCILocalized(@"Tab bar dynamic sizing") subtitle:SCILocalized(@"IGTabBarDynamicSizingEnabled") defaultsKey:@"lg_tab_bar_dynamic_sizing" requiresRestart:YES],
												[SCISetting switchCellWithTitle:SCILocalized(@"Tab bar enhanced dynamic sizing") subtitle:SCILocalized(@"IGTabBarEnhancedDynamicSizingEnabled") defaultsKey:@"lg_tab_bar_enhanced_sizing" requiresRestart:YES],
												[SCISetting switchCellWithTitle:SCILocalized(@"Tab bar homecoming + floating") subtitle:SCILocalized(@"IGTabBarHomecomingWithFloatingTabEnabled") defaultsKey:@"lg_tab_bar_homecoming_floating" requiresRestart:YES],
												[SCISetting switchCellWithTitle:SCILocalized(@"Tab bar glass style") subtitle:SCILocalized(@"IGTabBarStyleForLauncherSet → 1 (glass)") defaultsKey:@"lg_tab_bar_style_glass" requiresRestart:YES],
											]
										},
										@{
											@"header": SCILocalized(@"Experimental features"),
											@"footer": SCILocalized(@"These features rely on hidden Instagram flags and may not work on all accounts or versions."),
											@"rows": @[
												[SCISetting menuCellWithTitle:SCILocalized(@"Liquid glass tab bar") subtitle:SCILocalized(@"Fixed prevents shrinking. Hide makes it disappear when scrolling down") menu:[self menus][@"liquid_glass_tabbar_mode"]],
												[SCISetting switchCellWithTitle:SCILocalized(@"Enable teen app icons") subtitle:SCILocalized(@"Hold down on the Instagram logo to change the app icon") defaultsKey:@"teen_app_icons" requiresRestart:YES],
												[SCISetting switchCellWithTitle:SCILocalized(@"Disable app haptics") subtitle:SCILocalized(@"Disables haptics/vibrations within the app") defaultsKey:@"disable_haptics"],
												({ SCISetting *s = [SCISetting buttonCellWithTitle:SCILocalized(@"Open app icon picker") subtitle:SCILocalized(@"Change the app icon from the bundled icons")
																			icon:[SCISymbol symbolWithIGName:@"app.badge" fallback:@"app"]
																		  action:^{ [SCIPopupChrome presentVC:[SCIAppIconPickerViewController new] from:topMostController()]; }];
												   s.whatsNewID = @"ui_appicon"; s; }),
											]
										}]
				];
}

@end
