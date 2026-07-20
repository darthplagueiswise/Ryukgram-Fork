#import "SCISettingsSections.h"
#import "../SCISettingsViewController.h"

@implementation SCITweakSettings (Section_InstaPlus)

// Every Instagram Plus pref, grouped by surface. One source for the rows, the
// enable/disable-all buttons, and reset.
+ (NSArray<NSDictionary *> *)instaPlusGroups {
	return @[
		@{@"header": SCILocalized(@"Stories"),
		  @"rows": @[
			@[@"igt_ip_storypeek", SCILocalized(@"Story peek"), SCILocalized(@"Hold a story in the tray to preview it without opening it.")],
			@[@"igt_ip_storyfonts", SCILocalized(@"Story fonts"), SCILocalized(@"Adds the subscriber fonts when you add text to a story.")],
			@[@"igt_ip_searchviewers", SCILocalized(@"Search story viewers"), SCILocalized(@"Search the list of people who viewed your story.")],
			@[@"igt_ip_timestampviewers", SCILocalized(@"Viewer timestamps"), SCILocalized(@"Shows when each person viewed your story.")],
			@[@"igt_ip_silentprofile", SCILocalized(@"Silent post to profile"), SCILocalized(@"Share to your profile without notifying your followers.")],
			@[@"igt_ip_silenthighlights", SCILocalized(@"Silent post to highlights"), SCILocalized(@"Add to a highlight without notifying your followers.")],
			@[@"igt_ip_storyrewatch", SCILocalized(@"Story rewatch"), SCILocalized(@"Rewatch a story right after it finishes.")],
			@[@"igt_ip_storyextend", SCILocalized(@"Story extend"), SCILocalized(@"Keep your story up longer than 24 hours.")],
			@[@"igt_ip_storyspotlight", SCILocalized(@"Story spotlight"), SCILocalized(@"Boost your story to more viewers. Loads from Instagram, so it may not work.")],
			@[@"igt_ip_superlikes", SCILocalized(@"Story super likes"), SCILocalized(@"Send super likes on stories. Loads from Instagram, so it may not work.")],
		]},
		@{@"header": SCILocalized(@"Messages"),
		  @"rows": @[
			@[@"igt_ip_dmpeek", SCILocalized(@"Message peek"), SCILocalized(@"Hold a chat in the inbox to preview it.")],
			@[@"igt_ip_chatfonts", SCILocalized(@"Chat fonts"), SCILocalized(@"Adds the subscriber fonts in direct messages.")],
			@[@"igt_ip_brandedthreads", SCILocalized(@"Chat themes"), SCILocalized(@"Unlocks the premium chat themes. Loads from Instagram, so it may not work.")],
		]},
		@{@"header": SCILocalized(@"Profile"),
		  @"rows": @[
			@[@"igt_ip_appicon", SCILocalized(@"App icons"), SCILocalized(@"Opens the alternate app icon picker.")],
			@[@"igt_ip_biofont", SCILocalized(@"Bio font"), SCILocalized(@"Use a subscriber font for your bio.")],
			@[@"igt_ip_customlists", SCILocalized(@"Custom story lists"), SCILocalized(@"Make lists to pick exactly who sees a story.")],
			@[@"igt_ip_pinnedposts", SCILocalized(@"More pinned posts"), SCILocalized(@"Pin more posts to the top of your profile.")],
		]},
		@{@"header": SCILocalized(@"More benefits"),
		  @"rows": @[
			@[@"igt_ip_storyviewnotify", SCILocalized(@"Story view notify"), SCILocalized(@"Turn on the subscriber option to notify people when they view your story.")],
			@[@"igt_ip_linksmedia", SCILocalized(@"Links in media"), SCILocalized(@"Unlock the subscriber option to add links to posts.")],
		]},
		@{@"header": SCILocalized(@"Ads-incentive text"),
		  @"rows": @[
			@[@"igt_ip_ads_incentive_feed", SCILocalized(@"Feed"), SCILocalized(@"Force the \"subscribe for an ad-free experience\" text on feed ads.")],
			@[@"igt_ip_ads_incentive_story", SCILocalized(@"Stories"), SCILocalized(@"Force the ad-free incentive text on story ads.")],
			@[@"igt_ip_ads_incentive_storycaptain", SCILocalized(@"Stories (captain)"), SCILocalized(@"Force the ad-free incentive text on the story captain surface.")],
			@[@"igt_ip_ads_incentive_reels", SCILocalized(@"Reels"), SCILocalized(@"Force the ad-free incentive text on reels ads.")],
			@[@"igt_ip_ads_incentive_promo", SCILocalized(@"Promo sheet"), SCILocalized(@"Force the ad-free promo sheet.")],
		]},
		@{@"header": SCILocalized(@"Subscription state"),
		  @"rows": @[
			@[@"igt_ip_freetrial", SCILocalized(@"Free trial offer"), SCILocalized(@"Treat the offered subscription as a free trial.")],
			@[@"igt_ip_bypass_expired", SCILocalized(@"Bypass \"subscription expired\""), SCILocalized(@"Force the client to ignore expired-subscription errors.")],
		]},
		@{@"header": SCILocalized(@"Upsell noise"),
		  @"rows": @[
			@[@"igt_ip_up_prefetch", SCILocalized(@"Silence upsell prefetch"), SCILocalized(@"Skip the Bloks upsell prefetch for peek, custom lists, app icon, story/chat fonts, DM peek, story view notify, pin limit, links in media, quota comms.")],
			@[@"igt_ip_up_block_dest", SCILocalized(@"Block upsell purchase screens"), SCILocalized(@"Prevent taps that would open the Instagram Plus purchase destination screens.")],
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
	UIViewController *top = sciTopVC();
	UINavigationController *nav = [top isKindOfClass:[UINavigationController class]]
		? (UINavigationController *)top : top.navigationController;
	UIViewController *vc = nav.topViewController;
	if ([vc isKindOfClass:[SCISettingsViewController class]])
		[[(SCISettingsViewController *)vc tableView] reloadData];
}

+ (SCISetting *)instaPlusNavCell {
	return [SCISetting navigationCellWithTitle:SCILocalized(@"Instagram Plus")
									  subtitle:SCILocalized(@"Unlock Instagram's paid features")
										  icon:[SCISymbol symbolWithIGName:@"ig_icon_aura_outline_24" fallback:@"star.circle.fill"]
								   navSections:[self instaPlusNavSections]];
}

+ (NSArray *)instaPlusNavSections {
	NSMutableArray *sections = [NSMutableArray array];

	[sections addObject:@{
		@"header": @"",
		@"footer": SCILocalized(@"Instagram Plus is Instagram's paid subscription. These switches turn its features on inside the app. Some work completely. Others only reveal the option, because the content is loaded from Instagram's servers and still needs a real subscription, so they may show up empty or do nothing. Turn on what you want and tap Apply. If Instagram fails to launch three times in a row, these switches reset themselves."),
		@"rows": @[
			[SCISetting buttonCellWithTitle:SCILocalized(@"Turn everything on")
								   subtitle:@""
									   icon:[SCISymbol symbolWithName:@"checkmark.circle.fill"]
									 action:^{ [self instaPlusSetAll:YES]; [self instaPlusRefreshVisible]; }],
			[SCISetting buttonCellWithTitle:SCILocalized(@"Turn everything off")
								   subtitle:@""
									   icon:[SCISymbol symbolWithName:@"minus.circle.fill"]
									 action:^{ [self instaPlusSetAll:NO]; [self instaPlusRefreshVisible]; }],
		]
	}];

	for (NSDictionary *g in [self instaPlusGroups]) {
		NSMutableArray *rows = [NSMutableArray array];
		for (NSArray *row in g[@"rows"])
			[rows addObject:[SCISetting switchCellWithTitle:row[1] subtitle:row[2] defaultsKey:row[0]]];
		[sections addObject:@{ @"header": g[@"header"], @"rows": rows }];
	}

	SCISetting *apply = [SCISetting buttonCellWithTitle:SCILocalized(@"Apply & restart")
											   subtitle:SCILocalized(@"Restart Instagram to apply changes")
												   icon:[SCISymbol symbolWithIGName:@"bcn_circle-check_outline_24" fallback:@"checkmark.circle.fill"]
												 action:^{ [SCIUtils showRestartConfirmation]; }];
	apply.titleColor = [UIColor systemBlueColor];

	SCISetting *reset = [SCISetting buttonCellWithTitle:SCILocalized(@"Reset Instagram Plus")
											   subtitle:SCILocalized(@"Turn every Instagram Plus feature off")
												   icon:[SCISymbol symbolWithIGName:@"bcn_arrow-ccw_outline_24" fallback:@"arrow.counterclockwise.circle"]
												 action:^{
		UIAlertController *a = [UIAlertController
			alertControllerWithTitle:SCILocalized(@"Reset Instagram Plus?")
							 message:SCILocalized(@"Every Instagram Plus feature turns off and Instagram restarts.")
					  preferredStyle:UIAlertControllerStyleAlert];
		[a addAction:[UIAlertAction actionWithTitle:SCILocalized(@"Cancel") style:UIAlertActionStyleCancel handler:nil]];
		[a addAction:[UIAlertAction actionWithTitle:SCILocalized(@"Reset") style:UIAlertActionStyleDestructive
											handler:^(UIAlertAction *_) {
			[self instaPlusSetAll:NO];
			[SCIUtils showRestartConfirmation];
		}]];
		[sciTopVC() presentViewController:a animated:YES completion:nil];
	}];
	reset.titleColor = [UIColor systemRedColor];

	[sections addObject:@{ @"header": SCILocalized(@"Actions"), @"rows": @[apply, reset] }];
	return sections;
}

@end
