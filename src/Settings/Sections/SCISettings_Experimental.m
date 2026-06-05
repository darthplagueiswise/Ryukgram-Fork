#import "SCISettingsSections.h"
#import "../../Features/Experimental/SCIExperimentalGuard.h"

@implementation SCITweakSettings (Section_Experimental)

// MARK: - Advanced experimental features

+ (void)pushExperimentalMenu {
	SCISettingsViewController *vc = [[SCISettingsViewController alloc]
		initWithTitle:SCILocalized(@"Advanced experimental features")
			 sections:[self experimentalNavSections]
		 reduceMargin:NO];
	UIViewController *top = sciTopVC();
	if ([top isKindOfClass:[UINavigationController class]]) {
		[(UINavigationController *)top pushViewController:vc animated:YES];
	} else if (top.navigationController) {
		[top.navigationController pushViewController:vc animated:YES];
	} else {
		UINavigationController *nav = [[UINavigationController alloc] initWithRootViewController:vc];
		[top presentViewController:nav animated:YES completion:nil];
	}
}

+ (SCISetting *)experimentalEntryCell {
	return [SCISetting buttonCellWithTitle:SCILocalized(@"Advanced experimental features")
								  subtitle:SCILocalized(@"Hidden Instagram experiments")
									  icon:[SCISymbol symbolWithName:@"flask"]
									action:^{
		if ([[NSUserDefaults standardUserDefaults] boolForKey:@"sci_exp_warning_seen"]) {
			[self pushExperimentalMenu];
			return;
		}
		UIAlertController *a = [UIAlertController
			alertControllerWithTitle:SCILocalized(@"Heads up")
							 message:SCILocalized(@"These toggles flip hidden Instagram experiments on. Some features may not work on every account or IG version. If IG keeps crashing on launch, the flags auto-reset after 3 failed starts.")
					  preferredStyle:UIAlertControllerStyleAlert];
		[a addAction:[UIAlertAction actionWithTitle:SCILocalized(@"Got it") style:UIAlertActionStyleDefault
											handler:^(UIAlertAction *_) {
			[[NSUserDefaults standardUserDefaults] setBool:YES forKey:@"sci_exp_warning_seen"];
			[self pushExperimentalMenu];
		}]];
		[sciTopVC() presentViewController:a animated:YES completion:nil];
	}];
}

+ (SCISetting *)advancedExperimentalShortcutCell {
	return [SCISetting buttonCellWithTitle:SCILocalized(@"Advanced experimental features")
								  subtitle:SCILocalized(@"Hidden Instagram experiments (in Advanced)")
									  icon:[SCISymbol symbolWithName:@"flask"]
									action:^{ [self pushExperimentalMenu]; }];
}

+ (SCISetting *)applyRestartCell {
	SCISetting *cell = [SCISetting buttonCellWithTitle:SCILocalized(@"Apply & restart")
											  subtitle:SCILocalized(@"Restart Instagram to apply changes")
												  icon:[SCISymbol symbolWithIGName:@"bcn_circle-check_outline_24" fallback:@"checkmark.circle.fill"]
												action:^{ [SCIUtils showRestartConfirmation]; }];
	cell.titleColor = [UIColor systemBlueColor];
	return cell;
}

+ (SCISetting *)resetAllExperimentalCell {
	SCISetting *cell = [SCISetting buttonCellWithTitle:SCILocalized(@"Reset all experimental flags")
											  subtitle:SCILocalized(@"Turn every experimental toggle off")
												  icon:[SCISymbol symbolWithIGName:@"bcn_arrow-ccw_outline_24" fallback:@"arrow.counterclockwise.circle"]
												action:^{
		UIAlertController *a = [UIAlertController
			alertControllerWithTitle:SCILocalized(@"Reset experimental flags?")
							 message:SCILocalized(@"All experimental toggles will be turned off. Instagram will restart.")
					  preferredStyle:UIAlertControllerStyleAlert];
		[a addAction:[UIAlertAction actionWithTitle:SCILocalized(@"Cancel") style:UIAlertActionStyleCancel handler:nil]];
		[a addAction:[UIAlertAction actionWithTitle:SCILocalized(@"Reset") style:UIAlertActionStyleDestructive
											handler:^(UIAlertAction *_) {
			[SCIExperimentalGuard resetAll];
			[SCIUtils showRestartConfirmation];
		}]];
		[sciTopVC() presentViewController:a animated:YES completion:nil];
	}];
	cell.titleColor = [UIColor systemRedColor];
	return cell;
}

+ (NSArray *)experimentalNavSections {
	return @[
		@{
			@"header": @"",
			@"footer": SCILocalized(@"Flip what you want on, then tap Apply to restart. Some flags may not work on every account or IG version. Flags auto-reset if IG crashes on launch 3 times."),
			@"rows": @[]
		},
		@{
			@"header": SCILocalized(@"Notes & QuickSnap"),
			@"rows": @[
				({
					SCISetting *qs = [SCISetting switchCellWithTitle:SCILocalized(@"QuickSnap (Instants)")
														   subtitle:SCILocalized(@"Forces the QuickSnap / Instants surface on in feed, inbox, stories, and notes tray")
														defaultsKey:@"igt_quicksnap"];
					qs.disabled = YES;
					qs;
				}),
				[SCISetting switchCellWithTitle:SCILocalized(@"Direct Notes — Friend Map")
									   subtitle:SCILocalized(@"Shows the friend map entry in Direct Notes")
									defaultsKey:@"igt_directnotes_friendmap"],
				[SCISetting switchCellWithTitle:SCILocalized(@"Direct Notes — Audio reply")
									   subtitle:SCILocalized(@"Enables the audio-note reply type")
									defaultsKey:@"igt_directnotes_audio_reply"],
				[SCISetting switchCellWithTitle:SCILocalized(@"Direct Notes — Avatar reply")
									   subtitle:SCILocalized(@"Enables the avatar reply type")
									defaultsKey:@"igt_directnotes_avatar_reply"],
				[SCISetting switchCellWithTitle:SCILocalized(@"Direct Notes — GIFs & stickers reply")
									   subtitle:SCILocalized(@"Enables GIF/sticker replies")
									defaultsKey:@"igt_directnotes_gifs_reply"],
				[SCISetting switchCellWithTitle:SCILocalized(@"Direct Notes — Photo reply")
									   subtitle:SCILocalized(@"Enables photo replies")
									defaultsKey:@"igt_directnotes_photo_reply"],
			]
		},
		@{
			@"header": SCILocalized(@"Surfaces"),
			@"rows": @[
				[SCISetting switchCellWithTitle:SCILocalized(@"Homecoming")
									   subtitle:SCILocalized(@"Forces the Homecoming home surface / nav on")
									defaultsKey:@"igt_homecoming"],
				[SCISetting switchCellWithTitle:SCILocalized(@"Prism design system")
									   subtitle:SCILocalized(@"Forces Prism-gated experiments on")
									defaultsKey:@"igt_prism"],
			]
		},
		@{
			@"header": SCILocalized(@"Actions"),
			@"rows": @[
				[self applyRestartCell],
				[self resetAllExperimentalCell],
			]
		},
	];
}

@end
