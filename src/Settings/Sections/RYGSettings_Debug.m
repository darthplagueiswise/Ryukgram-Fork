#import "RYGSettingsSections.h"
#import "../../RYGFileLog.h"
#import "../../Debug/RYGDynamicProbe.h"
#import "../../Debug/RYGRuntimeBrowserViewController.h"
#import "../../UI/RYGPopupChrome.h"

@implementation RYGTweakSettings (Section_Debug)

+ (RYGSetting *)debugNavCell {
	return [RYGSetting navigationCellWithTitle:RYGLocalized(@"Debug")
										   subtitle:@""
											   icon:[RYGSymbol symbolWithName:@"ladybug"]
										navSections:@[@{
											@"header": RYGLocalized(@"Localization"),
											@"footer": RYGLocalized(@"Import a .strings file to update a translation. Pick a language, select the file, restart."),
											@"rows": @[
												[RYGSetting buttonCellWithTitle:RYGLocalized(@"Update localization file")
																	   subtitle:RYGLocalized(@"Import a .strings file for a language")
																		   icon:[RYGSymbol symbolWithName:@"square.and.arrow.down"]
																		 action:^(void) { [self presentLocalizationImport]; }
												],
												[RYGSetting buttonCellWithTitle:RYGLocalized(@"Export strings")
																	   subtitle:RYGLocalized(@"Pick a language and share its .strings file")
																		   icon:[RYGSymbol symbolWithName:@"square.and.arrow.up"]
																		 action:^(void) { [self presentLocalizationExport]; }
												],
												[RYGSetting buttonCellWithTitle:RYGLocalized(@"Reset localization")
																	   subtitle:RYGLocalized(@"Delete an imported override and fall back to the shipped strings")
																		   icon:[RYGSymbol symbolWithName:@"trash"]
																		 action:^(void) { [self presentLocalizationReset]; }
												],
											]
										},
#if RYG_FILELOG
									@{
											@"header": RYGLocalized(@"Logging"),
											@"footer": RYGLocalized(@"Logs RyukGram's own activity to one shareable file across the app and its extensions. Off by default — turn it on, reproduce the issue, then share."),
											@"rows": @[
												({ RYGSetting *s = [RYGSetting switchCellWithTitle:RYGLocalized(@"Enable file logging")
																	   subtitle:@""
																		  value:^BOOL{ return RYGFileLogIsEnabled(); }
																		 action:^(BOOL on){ RYGFileLogSetEnabled(on); }];
																   s.whatsNewID = @"ui_filelogging"; s; }),
												[RYGSetting buttonCellWithTitle:RYGLocalized(@"Share log file")
																	   subtitle:@""
																		   icon:[RYGSymbol symbolWithName:@"square.and.arrow.up"]
																		 action:^(void) {
													NSURL *url = RYGFileLogURL();
													if (!url || ![NSFileManager.defaultManager fileExistsAtPath:url.path]) {
														[RYGUtils showErrorHUDWithDescription:RYGLocalized(@"Log file is empty")];
														return;
													}
													UIActivityViewController *ac = [[UIActivityViewController alloc] initWithActivityItems:@[url] applicationActivities:nil];
													UIViewController *top = rygTopVC();
													if (!top) return;
													if ([UIDevice currentDevice].userInterfaceIdiom == UIUserInterfaceIdiomPad) {
														ac.popoverPresentationController.sourceView = top.view;
														ac.popoverPresentationController.sourceRect = CGRectMake(CGRectGetMidX(top.view.bounds), CGRectGetMidY(top.view.bounds), 1, 1);
													}
													[top presentViewController:ac animated:YES completion:nil];
												}],
												[RYGSetting buttonCellWithTitle:RYGLocalized(@"Clear log")
																	   subtitle:@""
																		   icon:[RYGSymbol symbolWithName:@"trash"]
																		 action:^(void) {
													RYGFileLogClear();
													[RYGUtils showToastForDuration:1.5 title:RYGLocalized(@"Clear completed") subtitle:@""];
												}],
											]
										},
#endif
#if RYG_PROBE
										// Dev-only (compiled out by default) — plain strings, not localized.
										@{
											@"header": @"Dynamic probe",
											@"footer": @"Reproduce an issue, then dump — the report lists probes that never fired and classes that resolved to nil.",
											@"rows": @[
												[RYGSetting buttonCellWithTitle:@"Dump probe coverage"
																	   subtitle:@"Write the report to the device console"
																		   icon:[RYGSymbol symbolWithName:@"scope"]
																		 action:^(void) {
													RYGProbeDumpReport();
													[RYGUtils showToastForDuration:1.5 title:@"Dumped to console" subtitle:@"Filter [RyukGram][Probe]"];
												}],
												[RYGSetting buttonCellWithTitle:@"Run class sweep now"
																	   subtitle:@"Re-check which hooked classes resolve"
																		   icon:[RYGSymbol symbolWithName:@"arrow.triangle.2.circlepath"]
																		 action:^(void) { RYGProbeRunClassSweep(); }],
												[RYGSetting buttonCellWithTitle:@"Reset probe session"
																	   subtitle:@""
																		   icon:[RYGSymbol symbolWithName:@"trash"]
																		 action:^(void) { RYGProbeResetSession(); }],
											]
										},
#endif
										@{
											@"header": RYGLocalized(@"Runtime · real time"),
											@"footer": RYGLocalized(@"Select the currently loaded Instagram executable or any app framework, then scan it live. No symbol rows or addresses are shipped or persisted. Structural BOOL methods such as isEqual: and respondsToSelector: are excluded."),
											@"rows": @[
												[RYGSetting buttonCellWithTitle:RYGLocalized(@"Open multi-framework browser")
																	   subtitle:RYGLocalized(@"BOOL gates, Employee/Dogfood scope and Mach-O symbols")
																		   icon:[RYGSymbol symbolWithName:@"shippingbox.and.arrow.backward"]
																		 action:^{ [RYGPopupChrome presentVC:[RYGRuntimeBrowserViewController new] from:nil]; }],
											]
										},
										@{
											@"header": RYGLocalized(@"Developer browser shortcuts"),
											@"footer": RYGLocalized(@"These shortcuts open the same self-contained real-time browser above; no external debugger dylib is required."),
											@"rows": @[
												[RYGSetting switchCellWithTitle:RYGLocalized(@"Enable five-finger long press") subtitle:RYGLocalized(@"Hold five fingers for one second to open the runtime browser") defaultsKey:@"flex_instagram" requiresRestart:YES],
												[RYGSetting switchCellWithTitle:RYGLocalized(@"Open browser on app launch") subtitle:RYGLocalized(@"Opens the runtime browser once after launch") defaultsKey:@"flex_app_launch" requiresRestart:YES],
												[RYGSetting switchCellWithTitle:RYGLocalized(@"Open browser on app focus") subtitle:RYGLocalized(@"Opens the runtime browser whenever Instagram becomes active") defaultsKey:@"flex_app_start" requiresRestart:YES]
											]
										}
										]
				];
}

@end
