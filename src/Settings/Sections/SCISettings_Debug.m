#import "SCISettingsSections.h"
#import "../../SCIFileLog.h"

@implementation SCITweakSettings (Section_Debug)

+ (SCISetting *)debugNavCell {
	return [SCISetting navigationCellWithTitle:SCILocalized(@"Debug")
										   subtitle:@""
											   icon:[SCISymbol symbolWithName:@"ladybug"]
										navSections:@[@{
											@"header": SCILocalized(@"Localization"),
											@"footer": SCILocalized(@"Import a .strings file to update a translation. Pick a language, select the file, restart."),
											@"rows": @[
												[SCISetting buttonCellWithTitle:SCILocalized(@"Update localization file")
																	   subtitle:SCILocalized(@"Import a .strings file for a language")
																		   icon:[SCISymbol symbolWithName:@"square.and.arrow.down"]
																		 action:^(void) { [self presentLocalizationImport]; }
												],
												[SCISetting buttonCellWithTitle:SCILocalized(@"Export strings")
																	   subtitle:SCILocalized(@"Pick a language and share its .strings file")
																		   icon:[SCISymbol symbolWithName:@"square.and.arrow.up"]
																		 action:^(void) { [self presentLocalizationExport]; }
												],
												[SCISetting buttonCellWithTitle:SCILocalized(@"Reset localization")
																	   subtitle:SCILocalized(@"Delete an imported override and fall back to the shipped strings")
																		   icon:[SCISymbol symbolWithName:@"trash"]
																		 action:^(void) { [self presentLocalizationReset]; }
												],
											]
										},
#if SCI_FILELOG
									@{
											@"header": SCILocalized(@"Logging"),
											@"footer": SCILocalized(@"Logs RyukGram's own activity to one shareable file across the app and its extensions. Off by default — turn it on, reproduce the issue, then share."),
											@"rows": @[
												({ SCISetting *s = [SCISetting switchCellWithTitle:SCILocalized(@"Enable file logging")
																	   subtitle:@""
																		  value:^BOOL{ return SCIFileLogIsEnabled(); }
																		 action:^(BOOL on){ SCIFileLogSetEnabled(on); }];
																   s.whatsNewID = @"ui_filelogging"; s; }),
												[SCISetting buttonCellWithTitle:SCILocalized(@"Share log file")
																	   subtitle:@""
																		   icon:[SCISymbol symbolWithName:@"square.and.arrow.up"]
																		 action:^(void) {
													NSURL *url = SCIFileLogURL();
													if (!url || ![NSFileManager.defaultManager fileExistsAtPath:url.path]) {
														[SCIUtils showErrorHUDWithDescription:SCILocalized(@"Log file is empty")];
														return;
													}
													UIActivityViewController *ac = [[UIActivityViewController alloc] initWithActivityItems:@[url] applicationActivities:nil];
													UIViewController *top = sciTopVC();
													if (!top) return;
													if ([UIDevice currentDevice].userInterfaceIdiom == UIUserInterfaceIdiomPad) {
														ac.popoverPresentationController.sourceView = top.view;
														ac.popoverPresentationController.sourceRect = CGRectMake(CGRectGetMidX(top.view.bounds), CGRectGetMidY(top.view.bounds), 1, 1);
													}
													[top presentViewController:ac animated:YES completion:nil];
												}],
												[SCISetting buttonCellWithTitle:SCILocalized(@"Clear log")
																	   subtitle:@""
																		   icon:[SCISymbol symbolWithName:@"trash"]
																		 action:^(void) {
													SCIFileLogClear();
													[SCIUtils showToastForDuration:1.5 title:SCILocalized(@"Clear completed") subtitle:@""];
												}],
											]
										},
#endif
										@{
											@"header": @"FLEX",
											@"rows": @[
												[SCISetting switchCellWithTitle:SCILocalized(@"Enable FLEX gesture") subtitle:SCILocalized(@"Hold 5 fingers on the screen to open FLEX") defaultsKey:@"flex_instagram" requiresRestart:YES],
												[SCISetting switchCellWithTitle:SCILocalized(@"Open FLEX on app launch") subtitle:SCILocalized(@"Opens FLEX when the app launches") defaultsKey:@"flex_app_launch" requiresRestart:YES],
												[SCISetting switchCellWithTitle:SCILocalized(@"Open FLEX on app focus") subtitle:SCILocalized(@"Opens FLEX when the app is focused") defaultsKey:@"flex_app_start" requiresRestart:YES]
											]
										},
										@{
											@"header": @"_ Example",
											@"rows": @[
												[SCISetting staticCellWithTitle:SCILocalized(@"Static Cell") subtitle:@"" icon:[SCISymbol symbolWithName:@"tablecells"]],
												[SCISetting switchCellWithTitle:SCILocalized(@"Switch Cell") subtitle:SCILocalized(@"Tap the switch") defaultsKey:@"test_switch_cell"],
												[SCISetting switchCellWithTitle:SCILocalized(@"Switch Cell (Restart)") subtitle:SCILocalized(@"Tap the switch") defaultsKey:@"test_switch_cell_restart" requiresRestart:YES],
												[SCISetting stepperCellWithTitle:SCILocalized(@"Stepper cell") subtitle:SCILocalized(@"I have %@%@") defaultsKey:@"test_stepper_cell" min:-10 max:1000 step:5.5 label:@"$" singularLabel:@"$"],
												[SCISetting linkCellWithTitle:SCILocalized(@"Link Cell") subtitle:SCILocalized(@"Using icon") icon:[SCISymbol symbolWithName:@"link" color:[UIColor systemTealColor] size:20.0] url:@"https://google.com"],
												[SCISetting linkCellWithTitle:SCILocalized(@"Link Cell") subtitle:SCILocalized(@"Using image") imageUrl:@"https://i.imgur.com/c9CbytZ.png" url:@"https://google.com"],
												[SCISetting buttonCellWithTitle:SCILocalized(@"Button Cell")
																		   subtitle:@""
																			   icon:[SCISymbol symbolWithName:@"oval.inset.filled"]
																			 action:^(void) { [SCIUtils showConfirmation:^(void){}]; }
												],
												[SCISetting menuCellWithTitle:SCILocalized(@"Menu Cell") subtitle:SCILocalized(@"Change the value on the right") menu:[self menus][@"test"]],
												[SCISetting navigationCellWithTitle:SCILocalized(@"Navigation Cell")
																		   subtitle:@""
																			   icon:[SCISymbol symbolWithName:@"rectangle.stack"]
																		navSections:@[@{
																			@"header": @"",
																			@"rows": @[]
																		}]
												]
											],
											@"footer": @"_ Example"
										}
										]
				];
}

@end
