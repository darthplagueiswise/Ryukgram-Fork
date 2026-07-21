#import "SCISettingsSections.h"
#import "../../SCIFileLog.h"
#import "../../Features/MobileConfig/SCIIdNameMappingInstaller.h"

extern void SCIGateSetCapture(BOOL on);
extern BOOL SCIGateIsCapturing(void);

@implementation SCITweakSettings (Section_Debug)

+ (SCISetting *)debugNavCell {
	NSMutableArray *sections = [NSMutableArray array];

	[sections addObject:@{
		@"header": SCILocalized(@"Localization"),
		@"footer": SCILocalized(@"Import a .strings file to update a translation. Pick a language, select the file, restart."),
		@"rows": @[
			[SCISetting buttonCellWithTitle:SCILocalized(@"Update localization file")
				subtitle:SCILocalized(@"Import a .strings file for a language")
				icon:[SCISymbol symbolWithName:@"square.and.arrow.down"]
				action:^{ [self presentLocalizationImport]; }],
			[SCISetting buttonCellWithTitle:SCILocalized(@"Export strings")
				subtitle:SCILocalized(@"Pick a language and share its .strings file")
				icon:[SCISymbol symbolWithName:@"square.and.arrow.up"]
				action:^{ [self presentLocalizationExport]; }],
			[SCISetting buttonCellWithTitle:SCILocalized(@"Reset localization")
				subtitle:SCILocalized(@"Delete an imported override and fall back to the shipped strings")
				icon:[SCISymbol symbolWithName:@"trash"]
				action:^{ [self presentLocalizationReset]; }],
		]
	}];

#if SCI_FILELOG
	SCISetting *fileLogSwitch = [SCISetting switchCellWithTitle:SCILocalized(@"Enable file logging")
		subtitle:@"" value:^BOOL { return SCIFileLogIsEnabled(); }
		action:^(BOOL on) { SCIFileLogSetEnabled(on); }];
	fileLogSwitch.whatsNewID = @"ui_filelogging";
	[sections addObject:@{
		@"header": SCILocalized(@"Logging"),
		@"footer": SCILocalized(@"Logs RyukGram's own activity to one shareable file across the app and its extensions."),
		@"rows": @[
			fileLogSwitch,
			[SCISetting switchCellWithTitle:SCILocalized(@"Capture EasyGating gates")
				subtitle:SCILocalized(@"Turn on, tap Internal Settings, turn off, then share the log.")
				value:^BOOL { return SCIGateIsCapturing(); }
				action:^(BOOL on) { SCIGateSetCapture(on); }],
			[SCISetting buttonCellWithTitle:SCILocalized(@"Share log file") subtitle:@""
				icon:[SCISymbol symbolWithName:@"square.and.arrow.up"] action:^{
					NSURL *url = SCIFileLogURL();
					if (!url || ![NSFileManager.defaultManager fileExistsAtPath:url.path]) {
						[SCIUtils showErrorHUDWithDescription:SCILocalized(@"Log file is empty")];
						return;
					}
					UIActivityViewController *activity = [[UIActivityViewController alloc]
						initWithActivityItems:@[url] applicationActivities:nil];
					UIViewController *top = sciTopVC();
					if (!top) return;
					if (UIDevice.currentDevice.userInterfaceIdiom == UIUserInterfaceIdiomPad) {
						activity.popoverPresentationController.sourceView = top.view;
						activity.popoverPresentationController.sourceRect = CGRectMake(
							CGRectGetMidX(top.view.bounds), CGRectGetMidY(top.view.bounds), 1, 1);
					}
					[top presentViewController:activity animated:YES completion:nil];
				}],
			[SCISetting buttonCellWithTitle:SCILocalized(@"Clear log") subtitle:@""
				icon:[SCISymbol symbolWithName:@"trash"] action:^{
					SCIFileLogClear();
					[SCIUtils showToastForDuration:1.5 title:SCILocalized(@"Clear completed") subtitle:@""];
				}],
		]
	}];
#endif

	[sections addObject:@{
		@"header": SCILocalized(@"MobileConfig names"),
		@"footer": SCILocalized(@"The action downloads and validates JSON, then writes id_name_mapping.json to disk. Instagram's native MobileConfig factory reads it on the next launch."),
		@"rows": @[
			[SCISetting buttonCellWithTitle:SCILocalized(@"Force download ID-name mapping")
				subtitle:SCILocalized(@"Download the version-pinned mapping, write atomically, then restart")
				icon:[SCISymbol symbolWithName:@"arrow.down.doc"] action:^{
					[SCIUtils showToastForDuration:2.0 title:SCILocalized(@"ID-name mapping")
						subtitle:SCILocalized(@"Downloading…")];
					SCIForceDownloadIDNameMapping(^(NSString *result) {
						[SCIUtils showToastForDuration:5.0 title:SCILocalized(@"ID-name mapping") subtitle:result];
					});
				}],
			[SCISetting buttonCellWithTitle:SCILocalized(@"Install bundled verified mapping")
				subtitle:SCILocalized(@"Offline fallback with 163 verified IG439 entries")
				icon:[SCISymbol symbolWithName:@"shippingbox"] action:^{
					NSString *result = SCIInstallBundledIDNameMapping(YES);
					[SCIUtils showToastForDuration:5.0 title:SCILocalized(@"ID-name mapping") subtitle:result];
				}],
			[SCISetting buttonCellWithTitle:SCILocalized(@"ID-name mapping status")
				subtitle:SCILocalized(@"Validate app, Documents and application-group paths")
				icon:[SCISymbol symbolWithName:@"checkmark.shield"] action:^{
					[SCIUtils showToastForDuration:5.0 title:SCILocalized(@"ID-name mapping")
						subtitle:SCIIdNameMappingStatus()];
				}],
		]
	}];

	[sections addObject:@{
		@"header": @"FLEX",
		@"rows": @[
			[SCISetting switchCellWithTitle:SCILocalized(@"Enable FLEX gesture")
				subtitle:SCILocalized(@"Hold 5 fingers on the screen to open FLEX")
				defaultsKey:@"flex_instagram" requiresRestart:YES],
			[SCISetting switchCellWithTitle:SCILocalized(@"Open FLEX on app launch")
				subtitle:SCILocalized(@"Opens FLEX when the app launches")
				defaultsKey:@"flex_app_launch" requiresRestart:YES],
			[SCISetting switchCellWithTitle:SCILocalized(@"Open FLEX on app focus")
				subtitle:SCILocalized(@"Opens FLEX when the app is focused")
				defaultsKey:@"flex_app_start" requiresRestart:YES],
		]
	}];

	[sections addObject:@{
		@"header": @"_ Example",
		@"footer": @"_ Example",
		@"rows": @[
			[SCISetting staticCellWithTitle:SCILocalized(@"Static Cell") subtitle:@""
				icon:[SCISymbol symbolWithName:@"tablecells"]],
			[SCISetting switchCellWithTitle:SCILocalized(@"Switch Cell")
				subtitle:SCILocalized(@"Tap the switch") defaultsKey:@"test_switch_cell"],
			[SCISetting switchCellWithTitle:SCILocalized(@"Switch Cell (Restart)")
				subtitle:SCILocalized(@"Tap the switch") defaultsKey:@"test_switch_cell_restart"
				requiresRestart:YES],
			[SCISetting stepperCellWithTitle:SCILocalized(@"Stepper cell")
				subtitle:SCILocalized(@"I have %@%@") defaultsKey:@"test_stepper_cell"
				min:-10 max:1000 step:5.5 label:@"$" singularLabel:@"$"],
			[SCISetting linkCellWithTitle:SCILocalized(@"Link Cell")
				subtitle:SCILocalized(@"Using icon")
				icon:[SCISymbol symbolWithName:@"link" color:UIColor.systemTealColor size:20.0]
				url:@"https://google.com"],
			[SCISetting linkCellWithTitle:SCILocalized(@"Link Cell")
				subtitle:SCILocalized(@"Using image") imageUrl:@"https://i.imgur.com/c9CbytZ.png"
				url:@"https://google.com"],
			[SCISetting buttonCellWithTitle:SCILocalized(@"Button Cell") subtitle:@""
				icon:[SCISymbol symbolWithName:@"oval.inset.filled"]
				action:^{ [SCIUtils showConfirmation:^{}]; }],
			[SCISetting menuCellWithTitle:SCILocalized(@"Menu Cell")
				subtitle:SCILocalized(@"Change the value on the right") menu:[self menus][@"test"]],
			[SCISetting navigationCellWithTitle:SCILocalized(@"Navigation Cell") subtitle:@""
				icon:[SCISymbol symbolWithName:@"rectangle.stack"]
				navSections:@[@{@"header": @"", @"rows": @[]}]],
		]
	}];

	return [SCISetting navigationCellWithTitle:SCILocalized(@"Debug") subtitle:@""
		icon:[SCISymbol symbolWithName:@"ladybug"] navSections:sections];
}

@end
