#import "SCISettingsSections.h"
#import "../SCISymbolsBrowserViewController.h"
#import "../SCIIGDSLauncherConfigViewController.h"
#import "../../Features/Dogfooding/SCIInternalSettingsApplier.h"
#import "../../Features/Dogfooding/SCIInternalMenusLauncher.h"
#import "../../Features/Dogfooding/SCIInternalGatePrefs.h"
#import "../../Features/Dogfooding/SCISymbolBrowserEngine.h"

void SCIInstallUnifiedExperimentManagerHooksIfNeeded(void);
void SCIInstallInternalDevMenuHooksIfNeeded(void);
void SCIInstallEmployeeInternalHooksIfNeeded(void);

static UIViewController *SCIDevTop(void) {
	UIWindow *w = nil;
	for (UIScene *scene in UIApplication.sharedApplication.connectedScenes) {
		if (![scene isKindOfClass:UIWindowScene.class]) continue;
		for (UIWindow *candidate in ((UIWindowScene *)scene).windows) if (candidate.isKeyWindow) { w = candidate; break; }
		if (w) break;
	}
	UIViewController *top = w.rootViewController;
	while (top.presentedViewController) top = top.presentedViewController;
	return top;
}
static void SCIDevShow(NSString *title, NSString *message) {
	UIViewController *top = SCIDevTop(); if (!top) return;
	UIAlertController *a = [UIAlertController alertControllerWithTitle:title message:message preferredStyle:UIAlertControllerStyleAlert];
	[a addAction:[UIAlertAction actionWithTitle:@"OK" style:UIAlertActionStyleDefault handler:nil]];
	[top presentViewController:a animated:YES completion:nil];
}
static SCISetting *SCIExperimentSwitch(NSString *title, NSString *subtitle, NSString *key, NSUInteger (^apply)(NSNumber *)) {
	return [SCISetting switchCellWithTitle:title subtitle:subtitle value:^BOOL { return [SCIUtils getBoolPref:key]; } action:^(BOOL on) {
		[SCIUtils setPref:@(on) forKey:key];
		dispatch_async(dispatch_get_global_queue(QOS_CLASS_USER_INITIATED, 0), ^{
			NSUInteger count = apply(on ? @YES : nil);
			dispatch_async(dispatch_get_main_queue(), ^{ [SCIUtils showToastForDuration:2.5 title:[NSString stringWithFormat:@"%@ — %lu methods", on ? @"Applied" : @"Cleared", (unsigned long)count] subtitle:nil]; });
		});
	}];
}

static SCISetting *SCIEmployeeInternalSwitch(NSString *title, NSString *subtitle, NSString *key) {
	return [SCISetting switchCellWithTitle:title subtitle:subtitle value:^BOOL {
		return [SCIUtils getBoolPref:key];
	} action:^(BOOL on) {
		[SCIUtils setPref:@(on) forKey:key];
		// Idempotente: instala alvos ainda ausentes quando liga e atualiza os
		// caches C quando desliga. Os replacements consultam as prefs ao vivo.
		SCIInstallEmployeeInternalHooksIfNeeded();
	}];
}

@implementation SCITweakSettings (Section_Dev)
+ (SCISetting *)devNavCell {
	return [SCISetting navigationCellWithTitle:SCILocalized(@"Dev") subtitle:@"" icon:[SCISymbol symbolWithIGName:@"wrench" fallback:@"hammer"] navSections:@[
		@{
			@"header": SCILocalized(@"Unified experiment engines"),
			@"footer": SCILocalized(@"Validated in Instagram(29): FBCCIGExperimentManager/FBCustomExperimentManager use BOOL isFeatureEnabled:(uint64_t). ExperimentConfig and helper sweeps enumerate only supported BOOL methods with zero or one ObjC/integer argument."),
			@"rows": @[
				[SCISetting switchCellWithTitle:SCILocalized(@"Force unified experiment managers") subtitle:SCILocalized(@"Forces isFeatureEnabled: and isFeatureEnabledWithoutLogging: on both managers") value:^BOOL { return [SCIUtils getBoolPref:@"sci_force_unified_experiment_managers"]; } action:^(BOOL on) { [SCIUtils setPref:@(on) forKey:@"sci_force_unified_experiment_managers"]; if (on) SCIInstallUnifiedExperimentManagerHooksIfNeeded(); }],
				SCIExperimentSwitch(SCILocalized(@"Force ExperimentConfig / QE gates"), SCILocalized(@"isEnabled:, isBacktestEnabled:, shouldLogImmediately and equivalent config gates"), @"sci_force_experiment_configs", ^NSUInteger(NSNumber *v){ return [SCISymbolBrowserEngine setExperimentConfigsForced:v]; }),
				SCIExperimentSwitch(SCILocalized(@"Force experiment helpers"), SCILocalized(@"IGMagicMod, IGStoriesTab, IGDirectNotes, IGLiquidGlass and experiment/gating helpers"), @"sci_force_experiment_helpers", ^NSUInteger(NSNumber *v){ return [SCISymbolBrowserEngine setExperimentHelpersForced:v]; }),
				[SCISetting buttonCellWithTitle:SCILocalized(@"Rescan current experiment surfaces") subtitle:SCILocalized(@"Discovers newly loaded ExperimentConfig/helper classes and reapplies enabled masters") icon:[SCISymbol symbolWithName:@"arrow.clockwise"] action:^{
					dispatch_async(dispatch_get_global_queue(QOS_CLASS_USER_INITIATED, 0), ^{ NSUInteger n=0; if([SCIUtils getBoolPref:@"sci_force_experiment_configs"]) n += [SCISymbolBrowserEngine setExperimentConfigsForced:@YES]; if([SCIUtils getBoolPref:@"sci_force_experiment_helpers"]) n += [SCISymbolBrowserEngine setExperimentHelpersForced:@YES]; dispatch_async(dispatch_get_main_queue(), ^{ [SCIUtils showToastForDuration:2.5 title:[NSString stringWithFormat:@"Experiment rescan: %lu methods",(unsigned long)n] subtitle:nil]; }); });
				}],
			]
		},
		@{
			@"header": SCILocalized(@"Employee, Internal Settings & Dev Menu"),
			@"footer": SCILocalized(@"The master now mirrors the Facebook strategy with Instagram-native equivalents: known employee getters/setters, identity defaults, IGBugReportMenu availability=0, Internal Settings visibility, logged-out entry and Dogfooding Assistant. _ig_is_employee symbols are DATA descriptors and are never fishhooked as functions."),
			@"rows": @[
				SCIEmployeeInternalSwitch(SCILocalized(@"Employee / Internal"), SCILocalized(@"Forces known employee identity paths plus the native Internal Settings gates"), @"sci_employee_internal"),
				SCIEmployeeInternalSwitch(SCILocalized(@"Internal settings access allowed"), SCILocalized(@"Forces IGInternalSettingsAvailabilityStatus to the confirmed available value 0"), @"sci_force_internal_settings_availability"),
				SCIEmployeeInternalSwitch(SCILocalized(@"Internal settings menu"), SCILocalized(@"Forces showInternalSettings and shake-to-report in both validated initializer ABIs"), @"sci_force_internal_settings_menu"),
				SCIEmployeeInternalSwitch(SCILocalized(@"Internal settings while logged out"), SCILocalized(@"Forces showLoggedOutInternalSettings"), @"sci_force_internal_settings_loggedout"),
				[SCISetting switchCellWithTitle:SCILocalized(@"React Native Dev Menu") subtitle:SCILocalized(@"Forces RCTDevMenu devMenuEnabled, shakeToShow, hot loading and keyboard shortcuts") value:^BOOL { return [SCIUtils getBoolPref:@"sci_force_rct_dev_menu"]; } action:^(BOOL on) { [SCIUtils setPref:@(on) forKey:@"sci_force_rct_dev_menu"]; if(on) SCIInstallInternalDevMenuHooksIfNeeded(); }],
				[SCISetting buttonCellWithTitle:SCILocalized(@"Apply internal/debug now") subtitle:SCILocalized(@"Uses the live IGAutofillInternalSettings session object") icon:[SCISymbol symbolWithIGName:@"bcn_wrench_outline_24" fallback:@"wrench.and.screwdriver"] action:^{ SCIDevShow(SCILocalized(@"Internal/debug"), [SCIInternalSettingsApplier applyNow]); }],
				[SCISetting switchCellWithTitle:SCILocalized(@"Force Bloks experience") subtitle:@"" defaultsKey:@"sci_apply_force_bloks" requiresRestart:YES],
				[SCISetting switchCellWithTitle:SCILocalized(@"Bloks prefetch") subtitle:@"" defaultsKey:@"sci_apply_bloks_prefetch" requiresRestart:YES],
			]
		},
		@{
			@"header": SCILocalized(@"Current C experiment gates"),
			@"footer": SCILocalized(@"The removed IGMobileConfigBooleanValueForInternalUse reader is not exposed. Remaining rows map to imports/exports confirmed in Instagram(29) and FBSharedFramework(105); complex readers call the original first, then force YES."),
			@"rows": @[
				[SCISetting switchCellWithTitle:SCILocalized(@"Instagram internal apps installed") subtitle:@"IGAppIsInstagramInternalAppsInstalledAndNotHiddenAfteriOS18" defaultsKey:@"sci_force_ig_internal_apps_installed_after_ios18" requiresRestart:YES],
				[SCISetting switchCellWithTitle:SCILocalized(@"Minos dogfood MEK") subtitle:@"MEBIsMinosDogfoodMekEncryptionVersionEnabled" defaultsKey:@"sci_force_minos_dogfood_mek_encryption" requiresRestart:YES],
				[SCISetting switchCellWithTitle:SCILocalized(@"Force all EasyGating BOOL readers") subtitle:@"" defaultsKey:@"sci_force_easy_gating_all" requiresRestart:YES],
				[SCISetting switchCellWithTitle:@"EasyGating Internal" subtitle:@"EasyGatingGetBoolean_Internal_DoNotUseOrMock" defaultsKey:@"sci_force_easy_gating_internal" requiresRestart:YES],
				[SCISetting switchCellWithTitle:@"EasyGating Platform" subtitle:@"EasyGatingPlatformGetBoolean" defaultsKey:@"sci_force_easy_gating_platform" requiresRestart:YES],
				[SCISetting switchCellWithTitle:@"EasyGating AuthDataContext" subtitle:@"" defaultsKey:@"sci_force_easy_gating_auth" requiresRestart:YES],
				[SCISetting switchCellWithTitle:@"MCQ EasyGating" subtitle:@"" defaultsKey:@"sci_force_easy_gating_mcq" requiresRestart:YES],
				[SCISetting switchCellWithTitle:SCILocalized(@"Force Sessioned/MCI BOOL readers") subtitle:SCILocalized(@"MSGC + MCIExperiment + MCIExtension") defaultsKey:@"sci_force_sessioned_mc_all" requiresRestart:YES],
				[SCISetting switchCellWithTitle:@"MSGC Sessioned BOOL" subtitle:@"MSGCSessionedMobileConfigGetBoolean" defaultsKey:@"sci_force_msgc_sessioned_boolean" requiresRestart:YES],
				[SCISetting switchCellWithTitle:@"MCI Experiment BOOL" subtitle:@"MCIExperimentCacheGetMobileConfigBoolean" defaultsKey:@"sci_force_mci_experiment_boolean" requiresRestart:YES],
				[SCISetting switchCellWithTitle:@"MCI Extension BOOL" subtitle:@"MCIExtensionExperimentCacheGetMobileConfigBoolean" defaultsKey:@"sci_force_mci_extension_boolean" requiresRestart:YES],
				[SCISetting switchCellWithTitle:@"META Extensions experiments" subtitle:@"GetBoolean + WithoutExposure" defaultsKey:@"sci_force_meta_ext_experiment" requiresRestart:YES],
			]
		},
		@{
			@"header": SCILocalized(@"Open native internal menus"),
			@"rows": @[
				[SCISetting buttonCellWithTitle:SCILocalized(@"Open Instagram Debug Menu") subtitle:SCILocalized(@"Calls the validated -[IGWindow showDebugMenu] entry point") icon:[SCISymbol symbolWithIGName:@"bcn_bug_outline_24" fallback:@"ladybug"] action:^{ NSString *r=[SCIInternalMenusLauncher openInstagramDebugMenu]; if(![r hasPrefix:@"opened"]&&![r hasPrefix:@"presented"]) SCIDevShow(@"Instagram Debug Menu",r); }],
				[SCISetting buttonCellWithTitle:SCILocalized(@"Open Dogfooding/Notes settings") subtitle:@"" icon:[SCISymbol symbolWithIGName:@"bcn_settings_outline_24" fallback:@"gearshape"] action:^{ NSString *r=[SCIInternalMenusLauncher openDogfoodingNotesSettings]; if(![r hasPrefix:@"opened"]&&![r hasPrefix:@"presented"]) SCIDevShow(@"Internal menu",r); }],
				[SCISetting buttonCellWithTitle:SCILocalized(@"Open Dogfooding Settings VC") subtitle:@"" icon:[SCISymbol symbolWithIGName:@"toolbox" fallback:@"wrench.and.screwdriver"] action:^{ NSString *r=[SCIInternalMenusLauncher openDogfoodingSettingsVC]; if(![r hasPrefix:@"opened"]&&![r hasPrefix:@"presented"]) SCIDevShow(@"Internal menu",r); }],
				[SCISetting buttonCellWithTitle:SCILocalized(@"Open internal URL") subtitle:@"instagram://internal_settings" icon:[SCISymbol symbolWithIGName:@"bcn_link_outline_24" fallback:@"link"] action:^{ NSString *r=[SCIInternalMenusLauncher openInternalURLString:@"instagram://internal_settings"]; if(![r hasPrefix:@"opened"]&&![r hasPrefix:@"presented"]) SCIDevShow(@"Internal URL",r); }],
			]
		},
		@{
			@"header": SCILocalized(@"Runtime"),
			@"footer": SCILocalized(@"The ObjC index now includes supported BOOL methods with zero or one object/integer argument, so experiment managers and +isEnabled: QuickExperiment configs are visible and forceable."),
			@"rows": @[
				[SCISetting navigationCellWithTitle:SCILocalized(@"Unified Runtime Browser") subtitle:SCILocalized(@"Exec + FBShared: ObjC, C, DATA and Swift/xrefs") icon:[SCISymbol symbolWithIGName:@"bcn_code_outline_24" fallback:@"square.grid.2x2"] viewController:[[SCISymbolsBrowserViewController alloc] initWithMode:SCICSymbolsBrowserModeObjCMethods]],
				[SCISetting navigationCellWithTitle:@"IGDSLauncherConfig" subtitle:@"" icon:[SCISymbol symbolWithName:@"wand.and.stars"] viewController:[SCIIGDSLauncherConfigViewController new]],
			]
		},
		@{
			@"header": SCILocalized(@"Advanced experimental features"),
			@"rows": @[
				[self experimentalEntryCell],
				({ SCISetting *s=[SCISetting switchCellWithTitle:SCILocalized(@"Status Bar Old School") subtitle:@"" defaultsKey:@"sci_statusbar_oldschool" requiresRestart:NO]; s.icon=[SCISymbol symbolWithName:@"statusbar_oldschool" color:UIColor.labelColor]; s; }),
				({ SCISetting *s=[SCISetting switchCellWithTitle:SCILocalized(@"Stories Tray") subtitle:@"" defaultsKey:@"sci_story_tray" requiresRestart:NO]; s.icon=[SCISymbol symbolWithName:@"story_tray" color:UIColor.labelColor]; s; }),
				({ SCISetting *s=[SCISetting menuCellWithTitle:SCILocalized(@"Custom Feed Header") subtitle:@"" menu:[self menus][@"ig_wordmark_variant"]]; s.icon=[SCISymbol symbolWithName:@"custom_feed_header" color:UIColor.labelColor]; s; }),
			]
		}
	]];
}
@end
