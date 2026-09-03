#import "RYGSettingsSections.h"
#import "../RYGSettingsViewController.h"

@implementation RYGTweakSettings (Section_InstaPlus)

// One source for the rows, the enable/disable-all buttons, and reset.
+ (NSArray<NSDictionary *> *)instaPlusGroups {
	return @[
		@{@"header": RYGLocalized(@"Stories"),
		  @"rows": @[
			@[@"igt_ip_storypeek", RYGLocalized(@"Story peek"), RYGLocalized(@"Hold a story in the tray or an inbox avatar to preview it without opening it.")],
			@[@"igt_ip_storyfonts", RYGLocalized(@"Story fonts"), RYGLocalized(@"Adds the subscriber fonts when you add text to a story.")],
			@[@"igt_ip_searchviewers", RYGLocalized(@"Search story viewers"), RYGLocalized(@"Search the list of people who viewed your story.")],
			@[@"igt_ip_timestampviewers", RYGLocalized(@"Viewer timestamps"), RYGLocalized(@"Shows when each person viewed your story.")],
			@[@"igt_ip_silentprofile", RYGLocalized(@"Silent post to profile"), RYGLocalized(@"Share to your profile without notifying your followers.")],
			@[@"igt_ip_silenthighlights", RYGLocalized(@"Silent post to highlights"), RYGLocalized(@"Add to a highlight without notifying your followers.")],
			@[@"igt_ip_storyrewatch", RYGLocalized(@"Story rewatch"), RYGLocalized(@"Rewatch a story right after it finishes.")],
			@[@"igt_ip_storyextend", RYGLocalized(@"Story extend"), RYGLocalized(@"Keep your story up longer than 24 hours.")],
			@[@"igt_ip_storyspotlight", RYGLocalized(@"Story spotlight"), RYGLocalized(@"Boost your story to more viewers. Loads from Instagram, so it may not work.")],
			@[@"igt_ip_superlikes", RYGLocalized(@"Story super likes"), RYGLocalized(@"Send super likes on stories. Loads from Instagram, so it may not work.")],
		]},
		@{@"header": RYGLocalized(@"Messages"),
		  @"rows": @[
			@[@"igt_ip_dmpeek", RYGLocalized(@"Message peek"), RYGLocalized(@"Hold a chat in the inbox to preview it.")],
			@[@"igt_ip_chatfonts", RYGLocalized(@"Chat fonts"), RYGLocalized(@"Adds the subscriber fonts in direct messages.")],
			@[@"igt_ip_brandedthreads", RYGLocalized(@"Chat themes"), RYGLocalized(@"Unlocks the premium chat themes. Loads from Instagram, so it may not work.")],
		]},
		@{@"header": RYGLocalized(@"Profile"),
		  @"rows": @[
			@[@"igt_ip_appicon", RYGLocalized(@"App icons"), RYGLocalized(@"Opens the alternate app icon picker.")],
			@[@"igt_ip_biofont", RYGLocalized(@"Bio font"), RYGLocalized(@"Use a subscriber font for your bio.")],
			@[@"igt_ip_customlists", RYGLocalized(@"Custom story lists"), RYGLocalized(@"Make lists to pick exactly who sees a story.")],
			@[@"igt_ip_pinnedposts", RYGLocalized(@"More pinned posts"), RYGLocalized(@"Pin more posts to the top of your profile.")],
		]},
	];
}

+ (NSArray<NSString *> *)instaPlusKeys {
	NSMutableArray *keys = [NSMutableArray array];
	for (NSDictionary *g in [self instaPlusGroups])
		for (NSArray *row in g[@"rows"]) [keys addObject:row[0]];
	return keys;
}

+ (void)instaPlusSetAll:(BOOL)on {
	NSUserDefaults *ud = [NSUserDefaults standardUserDefaults];
	for (NSString *k in [self instaPlusKeys]) [ud setBool:on forKey:k];
}

+ (void)instaPlusRefreshVisible {
	UIViewController *top = rygTopVC();
	UINavigationController *nav = [top isKindOfClass:[UINavigationController class]]
		? (UINavigationController *)top : top.navigationController;
	UIViewController *vc = nav.topViewController;
	if ([vc isKindOfClass:[RYGSettingsViewController class]])
		[[(RYGSettingsViewController *)vc tableView] reloadData];
}

+ (RYGSetting *)instaPlusNavCell {
	return [RYGSetting navigationCellWithTitle:RYGLocalized(@"Instagram Plus")
									  subtitle:RYGLocalized(@"Unlock Instagram's paid features")
										  icon:[RYGSymbol symbolWithIGName:@"ig_icon_aura_outline_24" fallback:@"star.circle.fill"]
								   navSections:[self instaPlusNavSections]];
}

+ (NSArray *)instaPlusNavSections {
	NSMutableArray *sections = [NSMutableArray array];

	[sections addObject:@{
		@"header": @"",
		@"footer": RYGLocalized(@"Instagram Plus is Instagram's paid subscription. These switches turn its features on inside the app. Some work completely. Others only reveal the option, because the content is loaded from Instagram's servers and still needs a real subscription, so they may show up empty or do nothing. Turn on what you want and tap Apply. If Instagram fails to launch three times in a row, these switches reset themselves."),
		@"rows": @[
			[RYGSetting buttonCellWithTitle:RYGLocalized(@"Turn everything on")
								   subtitle:@""
									   icon:[RYGSymbol symbolWithName:@"checkmark.circle.fill"]
									 action:^{ [self instaPlusSetAll:YES]; [self instaPlusRefreshVisible]; }],
			[RYGSetting buttonCellWithTitle:RYGLocalized(@"Turn everything off")
								   subtitle:@""
									   icon:[RYGSymbol symbolWithName:@"minus.circle.fill"]
									 action:^{ [self instaPlusSetAll:NO]; [self instaPlusRefreshVisible]; }],
		]
	}];

	for (NSDictionary *g in [self instaPlusGroups]) {
		NSMutableArray *rows = [NSMutableArray array];
		for (NSArray *row in g[@"rows"])
			[rows addObject:[RYGSetting switchCellWithTitle:row[1] subtitle:row[2] defaultsKey:row[0]]];
		[sections addObject:@{ @"header": g[@"header"], @"rows": rows }];
	}

	RYGSetting *apply = [RYGSetting actionCellWithTitle:RYGLocalized(@"Apply & restart")
												  color:[RYGUtils RYGColor_Primary]
												 action:^{ [RYGUtils showRestartConfirmation]; }];

	RYGSetting *reset = [RYGSetting actionCellWithTitle:RYGLocalized(@"Reset to defaults")
												  color:UIColor.systemRedColor
												 action:^{
		UIAlertController *a = [UIAlertController
			alertControllerWithTitle:RYGLocalized(@"Reset to defaults")
							 message:RYGLocalized(@"Every Instagram Plus feature turns off and Instagram restarts.")
					  preferredStyle:UIAlertControllerStyleAlert];
		[a addAction:[UIAlertAction actionWithTitle:RYGLocalized(@"Cancel") style:UIAlertActionStyleCancel handler:nil]];
		[a addAction:[UIAlertAction actionWithTitle:RYGLocalized(@"Reset") style:UIAlertActionStyleDestructive
											handler:^(UIAlertAction *_) {
			[self instaPlusSetAll:NO];
			[RYGUtils showRestartConfirmation];
		}]];
		[rygTopVC() presentViewController:a animated:YES completion:nil];
	}];

	[sections addObject:@{ @"header": @"", @"footer": RYGLocalized(@"Applying restarts Instagram to load your changes."), @"rows": @[apply, reset] }];
	return sections;
}

@end
