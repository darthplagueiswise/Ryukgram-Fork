#import "RYGSettingsSections.h"
#import "../../Features/Experimental/RYGExperimentalGuard.h"
#import "../../Features/ExpFlags/RYGMobileConfigToolsViewController.h"
#import "../../UI/RYGPopupChrome.h"

@implementation RYGTweakSettings (Section_Experimental)

// MARK: - Advanced experimental features

+ (void)pushExperimentalMenu {
	RYGSettingsViewController *vc = [[RYGSettingsViewController alloc]
		initWithTitle:RYGLocalized(@"Advanced experimental features")
			 sections:[self experimentalNavSections]
		 reduceMargin:NO];
	UIViewController *top = rygTopVC();
	if ([top isKindOfClass:[UINavigationController class]]) {
		[(UINavigationController *)top pushViewController:vc animated:YES];
	} else if (top.navigationController) {
		[top.navigationController pushViewController:vc animated:YES];
	} else {
		UINavigationController *nav = [[UINavigationController alloc] initWithRootViewController:vc];
		[top presentViewController:nav animated:YES completion:nil];
	}
}

+ (RYGSetting *)experimentalEntryCell {
	return [RYGSetting buttonCellWithTitle:RYGLocalized(@"Advanced experimental features")
								  subtitle:RYGLocalized(@"Hidden Instagram experiments")
									  icon:[RYGSymbol symbolWithName:@"flask"]
									action:^{
		if ([[NSUserDefaults standardUserDefaults] boolForKey:@"ryg_exp_warning_seen"]) {
			[self pushExperimentalMenu];
			return;
		}
		UIAlertController *a = [UIAlertController
			alertControllerWithTitle:RYGLocalized(@"Heads up")
							 message:RYGLocalized(@"These toggles flip hidden Instagram experiments on. Some features may not work on every account or IG version. If IG keeps crashing on launch, the flags auto-reset after 3 failed starts.")
					  preferredStyle:UIAlertControllerStyleAlert];
		[a addAction:[UIAlertAction actionWithTitle:RYGLocalized(@"Got it") style:UIAlertActionStyleDefault
											handler:^(UIAlertAction *_) {
			[[NSUserDefaults standardUserDefaults] setBool:YES forKey:@"ryg_exp_warning_seen"];
			[self pushExperimentalMenu];
		}]];
		[rygTopVC() presentViewController:a animated:YES completion:nil];
	}];
}

+ (RYGSetting *)advancedExperimentalShortcutCell {
	return [RYGSetting buttonCellWithTitle:RYGLocalized(@"Advanced experimental features")
								  subtitle:RYGLocalized(@"Hidden Instagram experiments (in Advanced)")
									  icon:[RYGSymbol symbolWithName:@"flask"]
									action:^{ [self pushExperimentalMenu]; }];
}

+ (void)openMobileConfigBrowser {
	if (![RYGUtils getBoolPref:@"ryg_metaconfig_enabled"]) {
		[RYGUtils showToastForDuration:2.5 title:RYGLocalized(@"Turn on the browser first, then restart Instagram")];
		return;
	}
	if ([[NSUserDefaults standardUserDefaults] boolForKey:@"ryg_metaconfig_warning_seen"]) {
		[RYGPopupChrome presentVC:[RYGMobileConfigToolsViewController new] from:nil];
		return;
	}
	UIAlertController *a = [UIAlertController
		alertControllerWithTitle:RYGLocalized(@"Use at your own risk")
						 message:RYGLocalized(@"This changes Instagram's own internal settings. Some can break features or cause crashes until you switch them back.\n\nChanges stay on this device. Most take effect right away, and some only after you restart Instagram. If it crashes on launch three times in a row, they're cleared for you.\n\nInstagram can tell when a setting doesn't match what its server sent. It's very unlikely to affect your account, but not impossible. Use at your own risk.")
				  preferredStyle:UIAlertControllerStyleAlert];
	[a addAction:[UIAlertAction actionWithTitle:RYGLocalized(@"Cancel") style:UIAlertActionStyleCancel handler:nil]];
	[a addAction:[UIAlertAction actionWithTitle:RYGLocalized(@"I understand") style:UIAlertActionStyleDefault
										handler:^(UIAlertAction *_) {
		[[NSUserDefaults standardUserDefaults] setBool:YES forKey:@"ryg_metaconfig_warning_seen"];
		[RYGPopupChrome presentVC:[RYGMobileConfigToolsViewController new] from:nil];
	}]];
	[rygTopVC() presentViewController:a animated:YES completion:nil];
}

+ (RYGSetting *)applyRestartCell {
	return [RYGSetting actionCellWithTitle:RYGLocalized(@"Apply & restart")
									 color:[RYGUtils RYGColor_Primary]
									action:^{ [RYGUtils showRestartConfirmation]; }];
}

+ (RYGSetting *)resetAllExperimentalCell {
	RYGSetting *cell = [RYGSetting actionCellWithTitle:RYGLocalized(@"Reset to defaults")
												 color:UIColor.systemRedColor
												action:^{
		UIAlertController *a = [UIAlertController
			alertControllerWithTitle:RYGLocalized(@"Reset to defaults")
							 message:RYGLocalized(@"All experimental toggles will be turned off. Instagram will restart.")
					  preferredStyle:UIAlertControllerStyleAlert];
		[a addAction:[UIAlertAction actionWithTitle:RYGLocalized(@"Cancel") style:UIAlertActionStyleCancel handler:nil]];
		[a addAction:[UIAlertAction actionWithTitle:RYGLocalized(@"Reset") style:UIAlertActionStyleDestructive
											handler:^(UIAlertAction *_) {
			[RYGExperimentalGuard resetAll];
			[RYGUtils showRestartConfirmation];
		}]];
		[rygTopVC() presentViewController:a animated:YES completion:nil];
	}];
	return cell;
}

+ (NSArray *)experimentalNavSections {
	return @[
		@{
			@"header": @"",
			@"footer": RYGLocalized(@"Flip what you want on, then tap Apply to restart. Some flags may not work on every account or IG version. Flags auto-reset if IG crashes on launch 3 times."),
			@"rows": @[]
		},
		@{
			@"header": RYGLocalized(@"MobileConfig"),
			@"footer": RYGLocalized(@"Read and change Instagram's own internal settings. The Developer browser now uses id_name_mapping plus the current typed runtime table; mapping-only rows stay read-only until this iOS build exposes them."),
			@"rows": @[
				[RYGSetting switchCellWithTitle:RYGLocalized(@"Enable MobileConfig browser")
									   subtitle:RYGLocalized(@"Lets the browser read values and apply typed changes")
									defaultsKey:@"ryg_metaconfig_enabled"
								requiresRestart:YES],
				[RYGSetting buttonCellWithTitle:RYGLocalized(@"Open MobileConfig browser")
									   subtitle:RYGLocalized(@"Search, import/export names and edit runtime-linked values")
										   icon:[RYGSymbol symbolWithIGName:@"bcn_settings_outline_24" fallback:@"slider.horizontal.3"]
										 action:^{ [self openMobileConfigBrowser]; }],
			]
		},
		@{
			@"header": RYGLocalized(@"Notes & QuickSnap"),
			@"rows": @[
				({
					RYGSetting *qs = [RYGSetting switchCellWithTitle:RYGLocalized(@"QuickSnap (Instants)")
														   subtitle:RYGLocalized(@"Forces the QuickSnap / Instants surface on in feed, inbox, stories, and notes tray")
														defaultsKey:@"igt_quicksnap"];
					qs.disabled = YES;
					qs;
				}),
				[RYGSetting switchCellWithTitle:RYGLocalized(@"Direct Notes — Friend Map")
									   subtitle:RYGLocalized(@"Shows the friend map entry in Direct Notes")
									defaultsKey:@"igt_directnotes_friendmap"],
				[RYGSetting switchCellWithTitle:RYGLocalized(@"Direct Notes — Audio reply")
									   subtitle:RYGLocalized(@"Enables the audio-note reply type")
									defaultsKey:@"igt_directnotes_audio_reply"],
				[RYGSetting switchCellWithTitle:RYGLocalized(@"Direct Notes — Avatar reply")
									   subtitle:RYGLocalized(@"Enables the avatar reply type")
									defaultsKey:@"igt_directnotes_avatar_reply"],
				[RYGSetting switchCellWithTitle:RYGLocalized(@"Direct Notes — GIFs & stickers reply")
									   subtitle:RYGLocalized(@"Enables GIF/sticker replies")
									defaultsKey:@"igt_directnotes_gifs_reply"],
				[RYGSetting switchCellWithTitle:RYGLocalized(@"Direct Notes — Photo reply")
									   subtitle:RYGLocalized(@"Enables photo replies")
									defaultsKey:@"igt_directnotes_photo_reply"],
			]
		},
		@{
			@"header": RYGLocalized(@"Surfaces"),
			@"rows": @[
				[RYGSetting switchCellWithTitle:RYGLocalized(@"Homecoming")
									   subtitle:RYGLocalized(@"Forces the Homecoming home surface / nav on")
									defaultsKey:@"igt_homecoming"],
				[RYGSetting switchCellWithTitle:RYGLocalized(@"Prism design system")
									   subtitle:RYGLocalized(@"Forces Prism-gated experiments on")
									defaultsKey:@"igt_prism"],
			]
		},
		@{
			@"header": @"",
			@"footer": RYGLocalized(@"Applying restarts Instagram to load your changes."),
			@"rows": @[
				[self applyRestartCell],
				[self resetAllExperimentalCell],
			]
		},
	];
}

@end
