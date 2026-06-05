#import "SCISettingsSections.h"
#import "../../Features/Experimental/SCIExperimentalGuard.h"
#import "../../Features/Dogfooding/SCILauncherOverride.h"
#import "../../Features/Dogfooding/SCIDogfooding.h"
#import "../SCIDogfoodBrowserViewController.h"

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

+ (SCISetting *)forceExperimentByNameCell {
	return [SCISetting buttonCellWithTitle:SCILocalized(@"Force experiment by name…")
								  subtitle:SCILocalized(@"Substring match, case-insensitive. Applied via MetaLocalExperiment hook.")
									  icon:[SCISymbol symbolWithName:@"plus.circle"]
									action:^{
		UIAlertController *a = [UIAlertController
			alertControllerWithTitle:SCILocalized(@"Force experiment")
							 message:SCILocalized(@"Type part of the experiment name (e.g. liquidglass, prism).")
					  preferredStyle:UIAlertControllerStyleAlert];
		[a addTextFieldWithConfigurationHandler:^(UITextField *tf) {
			tf.placeholder = @"experiment name";
			tf.autocapitalizationType = UITextAutocapitalizationTypeNone;
			tf.autocorrectionType = UITextAutocorrectionTypeNo;
		}];
		[a addAction:[UIAlertAction actionWithTitle:SCILocalized(@"Cancel") style:UIAlertActionStyleCancel handler:nil]];
		[a addAction:[UIAlertAction actionWithTitle:SCILocalized(@"Force ON") style:UIAlertActionStyleDefault
											handler:^(UIAlertAction *_) {
			NSString *n = [a.textFields.firstObject.text stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceCharacterSet]];
			if (!n.length) return;
			NSUserDefaults *ud = [NSUserDefaults standardUserDefaults];
			NSMutableArray *list = [[ud arrayForKey:@"sci_forced_experiments"] mutableCopy] ?: [NSMutableArray array];
			if (![list containsObject:n]) [list addObject:n];
			[ud setObject:list forKey:@"sci_forced_experiments"];
			[SCIUtils showRestartConfirmation];
		}]];
		[sciTopVC() presentViewController:a animated:YES completion:nil];
	}];
}

+ (SCISetting *)clearForcedExperimentsCell {
	SCISetting *cell = [SCISetting buttonCellWithTitle:SCILocalized(@"Clear forced experiments")
											  subtitle:@""
												  icon:[SCISymbol symbolWithIGName:@"bcn_arrow-ccw_outline_24" fallback:@"arrow.counterclockwise.circle"]
												action:^{
		[[NSUserDefaults standardUserDefaults] removeObjectForKey:@"sci_forced_experiments"];
		[SCIUtils showRestartConfirmation];
	}];
	cell.dynamicSubtitle = ^NSString *{
		NSArray *l = [[NSUserDefaults standardUserDefaults] arrayForKey:@"sci_forced_experiments"];
		return [NSString stringWithFormat:SCILocalized(@"Currently forcing %lu"), (unsigned long)([l isKindOfClass:[NSArray class]] ? l.count : 0)];
	};
	cell.titleColor = [UIColor systemRedColor];
	return cell;
}

// ------- Level-2 launcher overrides UI -------

+ (id)coerceLauncherValue:(NSString *)raw {
	NSString *t = [raw stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceCharacterSet]];
	if (t.length == 0) return nil;
	NSString *low = t.lowercaseString;
	if ([low isEqualToString:@"true"] || [low isEqualToString:@"yes"] || [low isEqualToString:@"1"]) return @YES;
	if ([low isEqualToString:@"false"] || [low isEqualToString:@"no"] || [low isEqualToString:@"0"]) return @NO;
	NSScanner *sc = [NSScanner scannerWithString:t];
	long long iv; if ([sc scanLongLong:&iv] && sc.isAtEnd) return @(iv);
	sc = [NSScanner scannerWithString:t];
	double dv; if ([sc scanDouble:&dv] && sc.isAtEnd) return @(dv);
	return t;
}

+ (SCISetting *)addLauncherOverrideCell {
	return [SCISetting buttonCellWithTitle:SCILocalized(@"Add launcher override…")
								  subtitle:SCILocalized(@"Writes to FBMobileConfigOverridesTable on disk via IGDogfoodingAssistantLauncherClient. Persists.")
									  icon:[SCISymbol symbolWithName:@"slider.horizontal.below.square.filled.and.square"]
									action:^{
		if (![SCILauncherOverride isAvailable]) {
			[SCIUtils showErrorHUDWithDescription:@"Launcher override client unavailable"];
			return;
		}
		UIAlertController *a = [UIAlertController
			alertControllerWithTitle:SCILocalized(@"Launcher override")
							 message:SCILocalized(@"Launcher name, parameter name, value. Value parsed as bool/int/double or string.")
					  preferredStyle:UIAlertControllerStyleAlert];
		[a addTextFieldWithConfigurationHandler:^(UITextField *tf) {
			tf.placeholder = @"launcher name (e.g. ig_ios_friend_map_liquid_glass)";
			tf.autocapitalizationType = UITextAutocapitalizationTypeNone;
			tf.autocorrectionType = UITextAutocorrectionTypeNo;
		}];
		[a addTextFieldWithConfigurationHandler:^(UITextField *tf) {
			tf.placeholder = @"parameter name (e.g. liquid_glass_enabled)";
			tf.autocapitalizationType = UITextAutocapitalizationTypeNone;
			tf.autocorrectionType = UITextAutocorrectionTypeNo;
		}];
		[a addTextFieldWithConfigurationHandler:^(UITextField *tf) {
			tf.placeholder = @"value (true / false / 1 / 0.5 / string)";
			tf.autocapitalizationType = UITextAutocapitalizationTypeNone;
			tf.autocorrectionType = UITextAutocorrectionTypeNo;
		}];
		[a addAction:[UIAlertAction actionWithTitle:SCILocalized(@"Cancel") style:UIAlertActionStyleCancel handler:nil]];
		[a addAction:[UIAlertAction actionWithTitle:SCILocalized(@"Apply") style:UIAlertActionStyleDefault
											handler:^(UIAlertAction *_) {
			NSString *launcher = [a.textFields[0].text stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceCharacterSet]];
			NSString *param    = [a.textFields[1].text stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceCharacterSet]];
			id value = [self coerceLauncherValue:a.textFields[2].text];
			if (!launcher.length || !param.length || !value) {
				[SCIUtils showErrorHUDWithDescription:@"All three fields required"];
				return;
			}
			BOOL ok = [SCILauncherOverride applyLauncher:launcher parameter:param value:value];
			if (!ok) {
				[SCIUtils showErrorHUDWithDescription:@"Native call returned NO (saved anyway; replays on next launch)"];
			}
			[SCIUtils showRestartConfirmation];
		}]];
		[sciTopVC() presentViewController:a animated:YES completion:nil];
	}];
}

+ (SCISetting *)clearLauncherOverridesCell {
	SCISetting *cell = [SCISetting buttonCellWithTitle:SCILocalized(@"Clear launcher overrides")
											  subtitle:SCILocalized(@"Removes our persisted set. Restart required to fully drop in-process values.")
												  icon:[SCISymbol symbolWithIGName:@"bcn_arrow-ccw_outline_24" fallback:@"arrow.counterclockwise.circle"]
												action:^{
		[SCILauncherOverride clearAll];
		[SCIUtils showRestartConfirmation];
	}];
	cell.dynamicSubtitle = ^NSString *{
		return [NSString stringWithFormat:SCILocalized(@"Currently overriding %lu params"), (unsigned long)[SCILauncherOverride totalOverrideCount]];
	};
	cell.titleColor = [UIColor systemRedColor];
	return cell;
}

// ------- Native menus -------

+ (SCISetting *)openNotesDogfoodingCell {
	return [SCISetting buttonCellWithTitle:SCILocalized(@"Open Notes dogfooding settings")
								  subtitle:SCILocalized(@"Native IG menu — Tray, Reply Sheet, View Model, UI, Multiple Notes, Self Sheet. Toggles persist via Launcher Overrides; if a switch doesn't stick, use Add launcher override above with the same param.")
									  icon:[SCISymbol symbolWithName:@"text.bubble"]
									action:^{ [SCIDogfooding presentNotesDogfoodingSettings]; }];
}

+ (SCISetting *)openMetaLocalExperimentBrowserCell {
	return [SCISetting buttonCellWithTitle:SCILocalized(@"Open MetaLocalExperiment browser")
								  subtitle:SCILocalized(@"Native experiment list (MetaLocalExperimentListViewController). Lists all configs conforming to MetaLocalExperimentConfigProtocol.")
									  icon:[SCISymbol symbolWithName:@"flask"]
									action:^{ [SCIDogfooding presentMetaLocalExperimentBrowser]; }];
}


+ (SCISetting *)openDogfoodInternalBrowserCell {
	return [SCISetting navigationCellWithTitle:SCILocalized(@"Dogfood & Internal Browser")
									subtitle:SCILocalized(@"Native dogfood menus plus filtered dogfood/internal MobileConfig candidates")
										icon:[SCISymbol symbolWithName:@"pawprint"]
							 viewController:[SCIDogfoodBrowserViewController new]];
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
			@"header": SCILocalized(@"Experiment overrides"),
			@"footer": SCILocalized(@"Force any MetaLocalExperiment ON by substring. Hook applies to isInExperiment/groupName/peekGroupName; requires a restart."),
			@"rows": @[
				[self forceExperimentByNameCell],
				[self clearForcedExperimentsCell],
			]
		},
		@{
			@"header": SCILocalized(@"Launcher overrides (Level 2)"),
			@"footer": SCILocalized(@"Direct override of any MobileConfig launcher via IGDogfoodingAssistantLauncherClient (FLEX-confirmed live in FBSharedFramework). We mirror writes into NSUserDefaults and replay ~2s after every cold start. The native client is hooked: any call from IG's own code path is captured too, so toggles made inside the Notes dogfood menu below also accumulate here automatically."),
			@"rows": @[
				[self addLauncherOverrideCell],
				[self clearLauncherOverridesCell],
			]
		},
		@{
			@"header": SCILocalized(@"Native menus"),
			@"footer": SCILocalized(@"Notes dogfooding works visually. If toggles don't persist via the Notes UI, use Launcher overrides above with one of: _ig_notes_reply_sheet_redesign · _ig_notes_self_sheet_redesign · ig_ios_multiple_notes · ig_ios_notes_new_reply_sheet_old_design — params: replySheetDesignRevsEnabled · newReplySheetOldDesignEnabled · newReplySheetShouldHideDraggingIndicator. The dogfood launcher client is now hooked, so any internal call from IG to it is mirrored into our persistent store automatically."),
			@"rows": @[
				[self openDogfoodInternalBrowserCell],
				[self openNotesDogfoodingCell],
				[self openMetaLocalExperimentBrowserCell],
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
