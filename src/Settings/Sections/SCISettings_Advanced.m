#import "SCISettingsSections.h"
#import "../SCIDogfoodBrowserViewController.h"
#import "../SCIGatingCatalogViewController.h"
#import "../SCIInternalActionsViewController.h"
#import "../../Features/Dogfooding/SCIInternalSettingsApplier.h"
#import "../../Features/Dogfooding/SCIInternalMenusLauncher.h"
#import "../SCISymbolsBrowserViewController.h"

@implementation SCITweakSettings (Section_Advanced)

+ (SCISetting *)advancedNavCell {
	return [SCISetting navigationCellWithTitle:SCILocalized(@"Advanced")
										   subtitle:@""
											   icon:[SCISymbol symbolWithIGName:@"toolbox" fallback:@"gearshape.2"]
										navSections:@[@{
											@"header": SCILocalized(@"Notifications"),
											@"footer": SCILocalized(@"Suppresses the second notification IG enqueues in-app while the notification extension is also delivering it."),
											@"rows": @[
												[SCISetting switchCellWithTitle:SCILocalized(@"Fix duplicate notifications") subtitle:SCILocalized(@"Prevents two banners for the same message when IG is in the foreground") defaultsKey:@"sci_fix_duplicate_notifications"],
											]
										},
										@{
											@"header": SCILocalized(@"Tweak settings"),
											@"rows": @[
												[SCISetting switchCellWithTitle:SCILocalized(@"Enable tweak settings quick-access") subtitle:SCILocalized(@"Hold on the home tab to open RyukGram settings") defaultsKey:@"settings_shortcut" requiresRestart:YES],
												[SCISetting switchCellWithTitle:SCILocalized(@"Show tweak settings on app launch") subtitle:SCILocalized(@"Automatically opens settings when the app launches") defaultsKey:@"tweak_settings_app_launch"],
												[SCISetting switchCellWithTitle:SCILocalized(@"Pause playback when opening settings") subtitle:SCILocalized(@"Pauses any playing video/audio when settings opens") defaultsKey:@"settings_pause_playback"],
												[SCISetting switchCellWithTitle:SCILocalized(@"Always show what's new") subtitle:SCILocalized(@"Keep the blue dot on every new feature instead of clearing it once viewed") defaultsKey:@"whatsnew_always_show"],
											]
										},
										@{
											@"header": SCILocalized(@"Cache"),
											@"footer": SCILocalized(@"Clearing still scans on demand."),
											@"rows": @[
												[self clearCacheButtonCell],
												[self autoClearCacheMenuCell],
												[self autoCheckCacheSizeCell],
												[self preserveMessagesDBCell],
											]
										},
										@{
											@"header": SCILocalized(@"Instagram"),
											@"rows": @[
												[SCISetting switchCellWithTitle:SCILocalized(@"Disable safe mode") subtitle:SCILocalized(@"Prevents Instagram from resetting settings after crashes (at your own risk)") defaultsKey:@"disable_safe_mode"],
												[SCISetting switchCellWithTitle:SCILocalized(@"Hide TestFlight popup") subtitle:SCILocalized(@"Suppresses the \"It's time to update Instagram Beta\" nag") defaultsKey:@"hide_testflight_nag" requiresRestart:YES],
												[SCISetting buttonCellWithTitle:SCILocalized(@"Reset onboarding state")
																		   subtitle:@""
																			   icon:[SCISymbol symbolWithIGName:@"bcn_arrow-ccw_outline_24" fallback:@"arrow.counterclockwise.circle"]
																			 action:^(void) { [[NSUserDefaults standardUserDefaults] removeObjectForKey:@"SCInstaFirstRun"]; [SCIUtils showRestartConfirmation];}
												],
											]
										},
										@{
											@"header": SCILocalized(@"IG-only/debug gates"),
											@"footer": SCILocalized(@"These hook real BOOL getters and safe imported C BOOL gates confirmed in Instagram metadata. Restart Instagram after changing them. Action/update functions are intentionally not fishhooked because they crash at launch."),
												@"rows": @[
													[SCISetting switchCellWithTitle:SCILocalized(@"Internal hook crash guard") subtitle:SCILocalized(@"Auto-disables active internal gates if the previous launch crashed before becoming stable") defaultsKey:@"sci_internal_gate_crash_guard_enabled" requiresRestart:YES],
													[SCISetting switchCellWithTitle:SCILocalized(@"Force all IG-only/debug ObjC gates") subtitle:SCILocalized(@"Master switch for isEmployee, internal badges, launch debug info and story debug underlay") defaultsKey:@"sci_force_ig_internal_employee" requiresRestart:YES],
												[SCISetting switchCellWithTitle:SCILocalized(@"Force all MobileConfig BOOL gates") subtitle:SCILocalized(@"Master switch for the bool-returning MobileConfig C gates below") defaultsKey:@"sci_force_mc_internal_use_all" requiresRestart:YES],
												[SCISetting switchCellWithTitle:SCILocalized(@"MobileConfig internal-use BOOL") subtitle:SCILocalized(@"IGMobileConfigBooleanValueForInternalUse") defaultsKey:@"sci_force_mc_internal_use_boolean" requiresRestart:YES],
												[SCISetting switchCellWithTitle:SCILocalized(@"MobileConfig sessionless internal-use BOOL") subtitle:SCILocalized(@"IGMobileConfigSessionlessBooleanValueForInternalUse") defaultsKey:@"sci_force_mc_sessionless_internal_use_boolean" requiresRestart:YES],
												[SCISetting switchCellWithTitle:SCILocalized(@"Instagram internal apps installed") subtitle:SCILocalized(@"IGAppIsInstagramInternalAppsInstalledAndNotHiddenAfteriOS18") defaultsKey:@"sci_force_ig_internal_apps_installed_after_ios18" requiresRestart:YES],
												[SCISetting switchCellWithTitle:SCILocalized(@"Minos dogfood MEK encryption") subtitle:SCILocalized(@"MEBIsMinosDogfoodMekEncryptionVersionEnabled") defaultsKey:@"sci_force_minos_dogfood_mek_encryption" requiresRestart:YES],
												[SCISetting switchCellWithTitle:SCILocalized(@"IGFacebookUserInfo.isEmployee") subtitle:SCILocalized(@"Primary local employee gate") defaultsKey:@"sci_force_ig_is_employee" requiresRestart:YES],
												[SCISetting switchCellWithTitle:SCILocalized(@"Featured internal badge") subtitle:SCILocalized(@"IGFeaturedUserInfo.shouldShowInternalBadge") defaultsKey:@"sci_force_ig_featured_internal_badge" requiresRestart:YES],
												[SCISetting switchCellWithTitle:SCILocalized(@"Inbox internal badge") subtitle:SCILocalized(@"IGDirectInboxThreadCellViewModel.shouldShowInternalBadge") defaultsKey:@"sci_force_ig_inbox_internal_badge" requiresRestart:YES],
												[SCISetting switchCellWithTitle:SCILocalized(@"Creation internal label") subtitle:SCILocalized(@"IGCreationActionBarButton.shouldShowInternalLabel") defaultsKey:@"sci_force_ig_creation_internal_label" requiresRestart:YES],
												[SCISetting switchCellWithTitle:SCILocalized(@"Launch debug info") subtitle:SCILocalized(@"IGLaunchHorizonViewController.shouldShowDebugInfo") defaultsKey:@"sci_force_ig_launch_debug_info" requiresRestart:YES],
												[SCISetting switchCellWithTitle:SCILocalized(@"Launch debug info V2") subtitle:SCILocalized(@"LaunchHorizonViewControllerV2.shouldShowDebugInfo") defaultsKey:@"sci_force_ig_launch_debug_info_v2" requiresRestart:YES],
												[SCISetting switchCellWithTitle:SCILocalized(@"Story debug underlay") subtitle:SCILocalized(@"IGStoryOpaqueDebugUnderlayViewFactory.shouldShowDebugUnderlay") defaultsKey:@"sci_force_ig_story_debug_underlay" requiresRestart:YES],
											]
										},
										@{
											@"header": SCILocalized(@"Internal / Debug (native, live session)"),
											@"footer": SCILocalized(@"Uses the native IGAutofillInternalSettings setters on the live user session to enable the debug footer and internal experience (persists via sessionUserDefaults). Tap Apply after you are logged in; toggles take effect after applying/restart."),
											@"rows": @[
												[SCISetting buttonCellWithTitle:SCILocalized(@"⚠️ Reset crash guard → restore gates")
													   subtitle:SCILocalized(@"Restores gates auto-disabled after a crash. Tap after enabling toggles that were reset.")
													       icon:[SCISymbol symbolWithName:@"arrow.counterclockwise.circle"]
													     action:^(void) {
														NSUserDefaults *ud = NSUserDefaults.standardUserDefaults;
														NSArray *d = [ud arrayForKey:@"sci_internal_gate_crash_disabled_keys"] ?: @[];
														for (NSString *key in d) [ud setBool:YES forKey:key];
														[ud removeObjectForKey:@"sci_internal_gate_crash_pending_keys"];
														[ud removeObjectForKey:@"sci_internal_gate_crash_disabled_keys"];
														[ud removeObjectForKey:@"sci_internal_gate_crash_last_source"];
														NSString *msg = d.count ? [NSString stringWithFormat:@"Restored %lu gate(s):\n%@",(unsigned long)d.count,[d componentsJoinedByString:@"\n"]] : @"No disabled gates. Guard cleared.";
														UIWindow *w=nil; for(UIScene *sc in UIApplication.sharedApplication.connectedScenes){if([sc isKindOfClass:UIWindowScene.class])for(UIWindow *win in((UIWindowScene*)sc).windows)if(win.isKeyWindow){w=win;break;}if(w)break;}
														UIViewController *top=w.rootViewController; while(top.presentedViewController)top=top.presentedViewController;
														UIAlertController *a=[UIAlertController alertControllerWithTitle:@"Crash guard reset" message:msg preferredStyle:UIAlertControllerStyleAlert];
														[a addAction:[UIAlertAction actionWithTitle:@"OK" style:UIAlertActionStyleDefault handler:nil]];
														if(top)[top presentViewController:a animated:YES completion:nil];
													}],
												[SCISetting buttonCellWithTitle:SCILocalized(@"Apply internal/debug now (native)")
													   subtitle:SCILocalized(@"Calls IGAutofillInternalSettings setters on the live session")
													       icon:[SCISymbol symbolWithIGName:@"bcn_wrench_outline_24" fallback:@"wrench.and.screwdriver"]
													     action:^(void) {
														NSString *r = [SCIInternalSettingsApplier applyNow];
														UIWindow *w=nil; for (UIScene *sc in UIApplication.sharedApplication.connectedScenes){ if([sc isKindOfClass:UIWindowScene.class]) for(UIWindow *win in ((UIWindowScene*)sc).windows) if(win.isKeyWindow){w=win;break;} if(w)break; }
														UIViewController *top=w.rootViewController; while(top.presentedViewController) top=top.presentedViewController;
														UIAlertController *a=[UIAlertController alertControllerWithTitle:SCILocalized(@"Applied") message:r preferredStyle:UIAlertControllerStyleAlert];
														[a addAction:[UIAlertAction actionWithTitle:@"OK" style:UIAlertActionStyleDefault handler:nil]];
														if(top)[top presentViewController:a animated:YES completion:nil];
													}
												],
												[SCISetting switchCellWithTitle:SCILocalized(@"Show Internal Settings menu") subtitle:SCILocalized(@"Forces showInternalSettings=YES in IGBugReportMenuViewController (shake-to-report menu). Shake device to open it.") defaultsKey:@"sci_force_internal_settings_menu" requiresRestart:YES],
												[SCISetting switchCellWithTitle:SCILocalized(@"\u2514 also when logged out") subtitle:SCILocalized(@"Also forces showLoggedOutInternalSettings=YES") defaultsKey:@"sci_force_internal_settings_loggedout" requiresRestart:YES],
												[SCISetting switchCellWithTitle:SCILocalized(@"Auto-apply on launch (native)") subtitle:SCILocalized(@"Re-applies a few seconds after login") defaultsKey:@"sci_apply_internal_native" requiresRestart:YES],
												[SCISetting switchCellWithTitle:SCILocalized(@"Enable debug footer") subtitle:SCILocalized(@"Gateway to internal/debug menus (applied by the button above)") defaultsKey:@"sci_apply_internal_native" requiresRestart:YES],
												[SCISetting switchCellWithTitle:SCILocalized(@"Force Bloks experience ON") subtitle:SCILocalized(@"setForceBloksExperienceOn") defaultsKey:@"sci_apply_force_bloks" requiresRestart:YES],
												[SCISetting switchCellWithTitle:SCILocalized(@"Bloks prefetch ON") subtitle:SCILocalized(@"setBloksPrefetchEnabledWithEnabled:") defaultsKey:@"sci_apply_bloks_prefetch" requiresRestart:YES],
												[SCISetting switchCellWithTitle:SCILocalized(@"LiquidGlass override ON") subtitle:SCILocalized(@"IGLiquidGlassNavigationExperimentHelper.shared") defaultsKey:@"sci_apply_liquidglass" requiresRestart:YES],
												[SCISetting switchCellWithTitle:SCILocalized(@"Force IGPlus eligibility layer") subtitle:SCILocalized(@"SUBSBenefitDataProvider + StoryPeek/DirectChat eligibility + CustomAppIcon availability") defaultsKey:@"sci_igplus_eligibility" requiresRestart:YES],
											]
										},
										@{
											@"header": SCILocalized(@"Instagram Plus (client benefits)"),
											@"footer": SCILocalized(@"Forces IGConsumerSubsService to report each benefit as enabled. These are the client getters the features read, so cosmetic/local IGPlus features light up. Server-validated actions still need a real subscription. Restart Instagram after toggling."),
											@"rows": @[
												[SCISetting switchCellWithTitle:SCILocalized(@"Force ALL Instagram Plus benefits") subtitle:SCILocalized(@"Master: every IGConsumerSubsService benefit getter \u2192 YES") defaultsKey:@"sci_force_igplus_all" requiresRestart:YES],
												[SCISetting switchCellWithTitle:SCILocalized(@"hasAccessToIGPlus \u2192 YES") subtitle:SCILocalized(@"") defaultsKey:@"sci_igplus_has_access" requiresRestart:YES],
												[SCISetting switchCellWithTitle:SCILocalized(@"hasAnyActiveBenefit / isBenefitActive: \u2192 YES") subtitle:SCILocalized(@"") defaultsKey:@"sci_igplus_any_active" requiresRestart:YES],
												[SCISetting switchCellWithTitle:SCILocalized(@"Custom Lists") subtitle:SCILocalized(@"isCustomListsBenefitEnabled") defaultsKey:@"sci_igplus_custom_lists" requiresRestart:YES],
												[SCISetting switchCellWithTitle:SCILocalized(@"Story Superlikes") subtitle:SCILocalized(@"isStorySuperlikesBenefitEnabled") defaultsKey:@"sci_igplus_story_superlikes" requiresRestart:YES],
												[SCISetting switchCellWithTitle:SCILocalized(@"Search Story Viewers") subtitle:SCILocalized(@"isSearchStoryViewersBenefitEnabled") defaultsKey:@"sci_igplus_search_story_viewers" requiresRestart:YES],
												[SCISetting switchCellWithTitle:SCILocalized(@"Story Extend") subtitle:SCILocalized(@"isStoryExtendBenefitEnabled") defaultsKey:@"sci_igplus_story_extend" requiresRestart:YES],
												[SCISetting switchCellWithTitle:SCILocalized(@"Story Rewatch") subtitle:SCILocalized(@"isStoryRewatchBenefitEnabled") defaultsKey:@"sci_igplus_story_rewatch" requiresRestart:YES],
												[SCISetting switchCellWithTitle:SCILocalized(@"Story Peeks") subtitle:SCILocalized(@"isStoryPeeksBenefitEnabled") defaultsKey:@"sci_igplus_story_peeks" requiresRestart:YES],
												[SCISetting switchCellWithTitle:SCILocalized(@"Story Spotlight") subtitle:SCILocalized(@"isStorySpotlightBenefitEnabled") defaultsKey:@"sci_igplus_story_spotlight" requiresRestart:YES],
												[SCISetting switchCellWithTitle:SCILocalized(@"Silent Post to Highlights") subtitle:SCILocalized(@"isSilentPostToHighlightsBenefitEnabled") defaultsKey:@"sci_igplus_silent_post_highlights" requiresRestart:YES],
												[SCISetting switchCellWithTitle:SCILocalized(@"Direct Message Peek") subtitle:SCILocalized(@"isDirectMessagePeekBenefitEnabled") defaultsKey:@"sci_igplus_dm_peek" requiresRestart:YES],
												[SCISetting switchCellWithTitle:SCILocalized(@"Custom App Icon") subtitle:SCILocalized(@"isCustomAppIconBenefitEnabled") defaultsKey:@"sci_igplus_custom_app_icon" requiresRestart:YES],
												[SCISetting switchCellWithTitle:SCILocalized(@"Branded Threads") subtitle:SCILocalized(@"isBrandedThreadsBenefitEnabled") defaultsKey:@"sci_igplus_branded_threads" requiresRestart:YES],
												[SCISetting switchCellWithTitle:SCILocalized(@"Timestamp Viewers List") subtitle:SCILocalized(@"isTimestampViewersListBenefitEnabled") defaultsKey:@"sci_igplus_timestamp_viewers" requiresRestart:YES],
												[SCISetting switchCellWithTitle:SCILocalized(@"Custom Bio Font") subtitle:SCILocalized(@"isCustomBioFontInProfileBenefitEnabled") defaultsKey:@"sci_igplus_custom_bio_font" requiresRestart:YES],
												[SCISetting switchCellWithTitle:SCILocalized(@"Silent Post to Profile") subtitle:SCILocalized(@"isSilentPostToProfileBenefitEnabled") defaultsKey:@"sci_igplus_silent_post_profile" requiresRestart:YES],
												[SCISetting switchCellWithTitle:SCILocalized(@"Pinned Posts Increased Limit") subtitle:SCILocalized(@"isPinnedPostsIncreasedLimitEnabled") defaultsKey:@"sci_igplus_pinned_posts_limit" requiresRestart:YES],
												[SCISetting switchCellWithTitle:SCILocalized(@"Story Peek active") subtitle:SCILocalized(@"IGConsumerSubsStoryPeekCoordinator.isPeekActive") defaultsKey:@"sci_igplus_story_peek_active" requiresRestart:YES],
											]
										},
										@{
											@"header": SCILocalized(@"Open internal menus (direct, live session)"),
											@"footer": SCILocalized(@"Presents Instagram\u2019s own internal/dogfooding screens via validated class-method entrypoints using the live user session. Open after you are logged in. The VC/URL routes are best-effort and depend on the IG build."),
											@"rows": @[
												[SCISetting buttonCellWithTitle:SCILocalized(@"Open Dogfooding/Notes settings")
													   subtitle:SCILocalized(@"Reliable entrypoint (no config needed)")
													       icon:[SCISymbol symbolWithIGName:@"bcn_settings_outline_24" fallback:@"gearshape"]
													     action:^(void) {
														NSString *r = [SCIInternalMenusLauncher openDogfoodingNotesSettings];
														UIWindow *w=nil; for (UIScene *sc in UIApplication.sharedApplication.connectedScenes){ if([sc isKindOfClass:UIWindowScene.class]) for(UIWindow *win in ((UIWindowScene*)sc).windows) if(win.isKeyWindow){w=win;break;} if(w)break; }
														UIViewController *top=w.rootViewController; while(top.presentedViewController) top=top.presentedViewController;
														if(![r hasPrefix:@"opened"] && ![r hasPrefix:@"presented"]){ UIAlertController *a=[UIAlertController alertControllerWithTitle:SCILocalized(@"Internal menu") message:r preferredStyle:UIAlertControllerStyleAlert]; [a addAction:[UIAlertAction actionWithTitle:@"OK" style:UIAlertActionStyleDefault handler:nil]]; if(top)[top presentViewController:a animated:YES completion:nil]; }
													}
												],
												[SCISetting buttonCellWithTitle:SCILocalized(@"Open Dogfooding Settings VC")
													   subtitle:SCILocalized(@"Best-effort: constructs the internal settings VC directly")
													       icon:[SCISymbol symbolWithIGName:@"toolbox" fallback:@"wrench.and.screwdriver"]
													     action:^(void) {
														NSString *r = [SCIInternalMenusLauncher openDogfoodingSettingsVC];
														UIWindow *w=nil; for (UIScene *sc in UIApplication.sharedApplication.connectedScenes){ if([sc isKindOfClass:UIWindowScene.class]) for(UIWindow *win in ((UIWindowScene*)sc).windows) if(win.isKeyWindow){w=win;break;} if(w)break; }
														UIViewController *top=w.rootViewController; while(top.presentedViewController) top=top.presentedViewController;
														if(![r hasPrefix:@"opened"] && ![r hasPrefix:@"presented"]){ UIAlertController *a=[UIAlertController alertControllerWithTitle:SCILocalized(@"Internal menu") message:r preferredStyle:UIAlertControllerStyleAlert]; [a addAction:[UIAlertAction actionWithTitle:@"OK" style:UIAlertActionStyleDefault handler:nil]]; if(top)[top presentViewController:a animated:YES completion:nil]; }
													}
												],
												[SCISetting buttonCellWithTitle:SCILocalized(@"Open internal URL\u2026")
													   subtitle:SCILocalized(@"Routes via IGURLHandler internal URL opener")
													       icon:[SCISymbol symbolWithIGName:@"bcn_link_outline_24" fallback:@"link"]
													     action:^(void) {
														NSString *r = [SCIInternalMenusLauncher openInternalURLString:@"instagram://internal_settings"];
														UIWindow *w=nil; for (UIScene *sc in UIApplication.sharedApplication.connectedScenes){ if([sc isKindOfClass:UIWindowScene.class]) for(UIWindow *win in ((UIWindowScene*)sc).windows) if(win.isKeyWindow){w=win;break;} if(w)break; }
														UIViewController *top=w.rootViewController; while(top.presentedViewController) top=top.presentedViewController;
														if(![r hasPrefix:@"opened"] && ![r hasPrefix:@"presented"]){ UIAlertController *a=[UIAlertController alertControllerWithTitle:SCILocalized(@"Internal menu") message:r preferredStyle:UIAlertControllerStyleAlert]; [a addAction:[UIAlertAction actionWithTitle:@"OK" style:UIAlertActionStyleDefault handler:nil]]; if(top)[top presentViewController:a animated:YES completion:nil]; }
													}
												],
											]
										},
										@{
											@"header": SCILocalized(@"Runtime"),
											@"footer": SCILocalized(@"Exports ALL Mach-O C symbols from the selected image — including IGMobileConfigBoolean*, EasyGating*, and other C functions FLEX cannot show. Blue = Bool gating candidate. Tap a row to copy name+address."),
											@"rows": @[
												[SCISetting navigationCellWithTitle:SCILocalized(@"Symbols Browser")
																							   subtitle:SCILocalized(@"All exported C symbols from Instagram / FBSharedFramework")
																							      icon:[SCISymbol symbolWithIGName:@"bcn_link_outline_24" fallback:@"function"]
																						viewController:[SCISymbolsBrowserViewController new]],
											]
										},
										@{
											@"header": SCILocalized(@"Advanced experimental features"),
											@"footer": SCILocalized(@"Toggle hidden Instagram experiments. Some may not work on every account or IG version."),
											@"rows": @[
												[self experimentalEntryCell],
								[SCISetting navigationCellWithTitle:SCILocalized(@"Dogfood & Internal Browser") subtitle:SCILocalized(@"Runtime stubs, live IGUserSession objects, dogfood actions and native internal setters") icon:[SCISymbol symbolWithName:@"pawprint"] viewController:[SCIDogfoodBrowserViewController new]],
								[SCISetting navigationCellWithTitle:SCILocalized(@"Internal Actions") subtitle:SCILocalized(@"Live IGUserSession actions, IGFacebookUserInfo.isEmployee, Notes dogfood and native Autofill setters") icon:[SCISymbol symbolWithName:@"switch.2"] viewController:[SCIInternalActionsViewController new]],
				[SCISetting navigationCellWithTitle:SCILocalized(@"Feature Gatings") subtitle:SCILocalized(@"Browse named gating/experiment/config BOOL accessors and force values by hooking the getter directly.") icon:[SCISymbol symbolWithName:@"switch.2"] viewController:[SCIGatingCatalogViewController new]],
											]
										}]
				];
}

@end
