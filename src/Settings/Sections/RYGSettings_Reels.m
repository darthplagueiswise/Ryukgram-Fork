#import "RYGSettingsSections.h"

static NSString *rygReelFilterValueText(NSString *key) {
	long long v = (long long)[RYGUtils getDoublePref:key];
	if (v <= 0) return RYGLocalized(@"Off");
	return [NSNumberFormatter localizedStringFromNumber:@(v) numberStyle:NSNumberFormatterDecimalStyle];
}

static void rygReloadSettingsTable(void) {
	UIViewController *vc = rygTopVC();
	if ([vc isKindOfClass:UINavigationController.class]) vc = ((UINavigationController *)vc).topViewController;
	if ([vc respondsToSelector:@selector(tableView)]) {
		id tv = [vc performSelector:@selector(tableView)];
		if ([tv respondsToSelector:@selector(reloadData)]) [tv performSelector:@selector(reloadData)];
	}
}

static void rygPromptReelFilter(NSString *key, NSString *title) {
	UIViewController *presenter = rygTopVC();
	UIAlertController *alert = [UIAlertController alertControllerWithTitle:title
																   message:RYGLocalized(@"Reels below this count are hidden. 0 turns this limit off.")
															preferredStyle:UIAlertControllerStyleAlert];
	[alert addTextFieldWithConfigurationHandler:^(UITextField *tf) {
		tf.placeholder = RYGLocalized(@"e.g. 1000000");
		long long v = (long long)[RYGUtils getDoublePref:key];
		tf.text = v > 0 ? [NSString stringWithFormat:@"%lld", v] : @"";
		tf.keyboardType = UIKeyboardTypeNumberPad;
	}];
	[alert addAction:[UIAlertAction actionWithTitle:RYGLocalized(@"Cancel") style:UIAlertActionStyleCancel handler:nil]];
	[alert addAction:[UIAlertAction actionWithTitle:RYGLocalized(@"Save") style:UIAlertActionStyleDefault handler:^(__unused UIAlertAction *a) {
		NSString *v = [alert.textFields.firstObject.text stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceCharacterSet]];
		[RYGUtils setPref:@(v.longLongValue > 0 ? v.longLongValue : 0) forKey:key];
		rygReloadSettingsTable();
	}]];
	[presenter presentViewController:alert animated:YES completion:nil];
}

static RYGSetting *rygReelFilterRow(NSString *title, NSString *key) {
	RYGSetting *s = [RYGSetting buttonCellWithTitle:title subtitle:@"" icon:nil action:^{ rygPromptReelFilter(key, title); }];
	s.dynamicValueText = ^{ return rygReelFilterValueText(key); };
	return s;
}

static RYGSetting *rygReelFilterResetCell(void) {
	return [RYGSetting actionCellWithTitle:RYGLocalized(@"Reset to defaults")
									 color:UIColor.systemRedColor
									action:^{
		UIAlertController *a = [UIAlertController
			alertControllerWithTitle:RYGLocalized(@"Reset to defaults")
							 message:RYGLocalized(@"Turns the filter off and clears every minimum.")
					  preferredStyle:UIAlertControllerStyleAlert];
		[a addAction:[UIAlertAction actionWithTitle:RYGLocalized(@"Cancel") style:UIAlertActionStyleCancel handler:nil]];
		[a addAction:[UIAlertAction actionWithTitle:RYGLocalized(@"Reset") style:UIAlertActionStyleDestructive
											handler:^(__unused UIAlertAction *ac) {
			[RYGUtils setPref:@(NO) forKey:@"reels_engagement_filter"];
			[RYGUtils setPref:@(NO) forKey:@"reels_filter_hide_hidden_stats"];
			[RYGUtils setPref:@(YES) forKey:@"reels_filter_tab_only"];
			for (NSString *key in @[@"reels_filter_min_likes", @"reels_filter_min_comments", @"reels_filter_min_views", @"reels_filter_min_reshares"])
				[RYGUtils setPref:@(0) forKey:key];
			rygReloadSettingsTable();
		}]];
		[rygTopVC() presentViewController:a animated:YES completion:nil];
	}];
}

@implementation RYGTweakSettings (Section_Reels)

+ (RYGSetting *)reelsNavCell {
	return [RYGSetting navigationCellWithTitle:RYGLocalized(@"Reels")
										   subtitle:@""
											   icon:[RYGSymbol symbolWithIGName:@"reels" fallback:@"film.stack"]
										navSections:@[@{
											@"header": RYGLocalized(@"Action button"),
											@"footer": RYGLocalized(@"Adds a RyukGram action button above the reel sidebar with view-cover/download/share/copy/expand/repost entries. Tap opens the menu by default; change the tap behavior below."),
											@"rows": @[
												[RYGSetting switchCellWithTitle:RYGLocalized(@"Show action button") subtitle:RYGLocalized(@"Places a button above the like/comment/share column on each reel") defaultsKey:@"reels_action_button"],
												({ RYGSetting *s = [RYGSetting navigationCellWithTitle:RYGLocalized(@"Configure menu")
																			subtitle:RYGLocalized(@"Reorder, enable/disable, set default tap, show date")
																				icon:nil
																	  viewController:[[RYGActionMenuConfigViewController alloc] initForSource:RYGActionSourceReels]];
												   s.whatsNewID = @"ui_cfg_actionmenu"; s; }),
											]
										},
										@{
											@"header": @"",
											@"rows": @[
												[RYGSetting menuCellWithTitle:RYGLocalized(@"Tap Controls") subtitle:RYGLocalized(@"Set what a tap on a reel does") menu:[self menus][@"reels_tap_control"]],
												[RYGSetting navigationCellWithTitle:RYGLocalized(@"Playback") subtitle:RYGLocalized(@"Speed, seek and auto-scroll controls") icon:nil navSections:@[@{
													@"footer": RYGLocalized(@"Enabled controls appear when you hold the ⋯ or audio button on a reel."),
													@"rows": @[
														[RYGSetting switchCellWithTitle:RYGLocalized(@"Playback speed") subtitle:@"" defaultsKey:@"reels_playback_speed" requiresRestart:YES],
														[RYGSetting switchCellWithTitle:RYGLocalized(@"Seek controls") subtitle:@"" defaultsKey:@"reels_playback_seek"],
														[RYGSetting switchCellWithTitle:RYGLocalized(@"Auto-scroll control") subtitle:@"" defaultsKey:@"reels_playback_autoscroll"],
													]
												}]],
												[RYGSetting switchCellWithTitle:RYGLocalized(@"Always show progress scrubber") subtitle:RYGLocalized(@"Keeps the progress bar visible on every reel") defaultsKey:@"reels_show_scrubber"],
												[RYGSetting switchCellWithTitle:RYGLocalized(@"Disable auto-unmuting reels") subtitle:RYGLocalized(@"Keeps reels from unmuting when you hit a volume or ringer key") defaultsKey:@"disable_auto_unmuting_reels" requiresRestart:YES],
												[RYGSetting switchCellWithTitle:RYGLocalized(@"Confirm reel refresh") subtitle:RYGLocalized(@"Confirms before the reels feed refreshes") defaultsKey:@"refresh_reel_confirm"],
												[RYGSetting switchCellWithTitle:RYGLocalized(@"Disable tab button refresh") subtitle:RYGLocalized(@"Tapping the Reels tab while on reels does nothing") defaultsKey:@"disable_reels_tab_refresh"],
												[RYGSetting switchCellWithTitle:RYGLocalized(@"Swipe left to profile") subtitle:RYGLocalized(@"Swipe a reel left to open the author's profile") defaultsKey:@"reels_swipe_to_profile" requiresRestart:YES],
												[RYGSetting switchCellWithTitle:RYGLocalized(@"Unlock password-locked reels") subtitle:RYGLocalized(@"Shows buttons to reveal and auto-fill the password on locked reels") defaultsKey:@"unlock_password_reels"],
											]
										},
										@{
											@"header": RYGLocalized(@"Hiding"),
											@"rows": @[
												[RYGSetting switchCellWithTitle:RYGLocalized(@"Hide reels header") subtitle:RYGLocalized(@"Drops the top bar while you watch reels") defaultsKey:@"hide_reels_header"],
												[RYGSetting switchCellWithTitle:RYGLocalized(@"Hide friends avatars") subtitle:RYGLocalized(@"Hides the avatar bubbles next to the Friends tab in reels") defaultsKey:@"hide_reels_friends_bubbles"],
												[RYGSetting switchCellWithTitle:RYGLocalized(@"Hide social context overlay") subtitle:RYGLocalized(@"Hides the floating overlay showing who reposted or commented on reels") defaultsKey:@"hide_reels_floating_social_context"],
												[RYGSetting switchCellWithTitle:RYGLocalized(@"Hide \"Made with Edits\" badge") subtitle:RYGLocalized(@"Hides the Edits app promo pill on reels") defaultsKey:@"hide_made_with_edits"]
											]
										},
										@{
											@"header": RYGLocalized(@"Limits"),
											@"rows": @[
												[RYGSetting switchCellWithTitle:RYGLocalized(@"Disable scrolling reels") subtitle:RYGLocalized(@"Locks a reel in place so it never scrolls to the next one") defaultsKey:@"disable_scrolling_reels" requiresRestart:YES],
												[RYGSetting switchCellWithTitle:RYGLocalized(@"Prevent doom scrolling") subtitle:RYGLocalized(@"Caps how many reels you can scroll in a row and blocks the refresh") defaultsKey:@"prevent_doom_scrolling"],
												[RYGSetting stepperCellWithTitle:RYGLocalized(@"Doom scrolling limit") subtitle:RYGLocalized(@"Only loads %@ %@") defaultsKey:@"doom_scrolling_reel_count" min:1 max:100 step:1 label:@"reels" singularLabel:@"reel"],
												[RYGSetting switchCellWithTitle:RYGLocalized(@"Limit audio and effect pages") subtitle:RYGLocalized(@"Grids on audio, effect, template and remix pages stop at the same count") defaultsKey:@"doom_limit_pivot_grids"],
												[RYGSetting navigationCellWithTitle:RYGLocalized(@"Engagement filter") subtitle:RYGLocalized(@"Hide reels below a like, comment, view or repost count") icon:nil navSections:@[@{
													@"footer": RYGLocalized(@"Hides reels that don't reach every minimum you set. Reels whose counts are hidden by the author pass through unless you hide them too."),
													@"rows": @[
														[RYGSetting switchCellWithTitle:RYGLocalized(@"Filter reels by engagement") subtitle:@"" defaultsKey:@"reels_engagement_filter"],
														[RYGSetting switchCellWithTitle:RYGLocalized(@"Hide reels with hidden stats") subtitle:@"" defaultsKey:@"reels_filter_hide_hidden_stats"],
														[RYGSetting switchCellWithTitle:RYGLocalized(@"Only filter the Reels tab") subtitle:RYGLocalized(@"Reels you open from a post, profile or share are never filtered") defaultsKey:@"reels_filter_tab_only"],
													]
												},
												@{
													@"header": RYGLocalized(@"Minimums"),
													@"rows": @[
														rygReelFilterRow(RYGLocalized(@"Minimum likes"), @"reels_filter_min_likes"),
														rygReelFilterRow(RYGLocalized(@"Minimum comments"), @"reels_filter_min_comments"),
														rygReelFilterRow(RYGLocalized(@"Minimum views"), @"reels_filter_min_views"),
														rygReelFilterRow(RYGLocalized(@"Minimum reposts"), @"reels_filter_min_reshares"),
													]
												},
												@{
													@"header": @"",
													@"rows": @[rygReelFilterResetCell()]
												}]]
											]
										},
										@{
											@"header": RYGLocalized(@"Stickers"),
											@"footer": RYGLocalized(@"Peek at poll/quiz/slider results on reels before interacting — you can still tap to vote normally."),
											@"rows": @[
												[RYGSetting switchCellWithTitle:RYGLocalized(@"Show quiz answer") subtitle:RYGLocalized(@"Circle the correct option on quiz stickers, or the leading option on polls") defaultsKey:@"reels_show_quiz_answer"],
												[RYGSetting switchCellWithTitle:RYGLocalized(@"Show poll vote counts") subtitle:RYGLocalized(@"Show vote tallies on poll options and slider count/average before you vote") defaultsKey:@"reels_show_poll_votes_count"],
											]
										},
										@{
											@"header": RYGLocalized(@"Reposts"),
											@"footer": RYGLocalized(@"Shows the repost date on the \"reposted this reel\" header."),
											@"rows": @[
												[RYGSetting switchCellWithTitle:RYGLocalized(@"Hide repost button") subtitle:RYGLocalized(@"Hides the repost button on the reels sidebar") defaultsKey:@"hide_reels_repost" requiresRestart:YES],
												[RYGSetting switchCellWithTitle:RYGLocalized(@"Show date") subtitle:@"" defaultsKey:@"repost_show_date" requiresRestart:YES],
												[RYGSetting menuCellWithTitle:RYGLocalized(@"Date format") subtitle:@"" menu:[self menus][@"repost_date_format"]],
											]
										},
										@{
											@"header": RYGLocalized(@"Advanced"),
											@"rows": @[
												[RYGSetting switchCellWithTitle:RYGLocalized(@"Tap to mute on photo reels") subtitle:RYGLocalized(@"When pause mode is on, tap on photo reels toggles audio instead of the native pause gesture") defaultsKey:@"reels_photo_tap_mute"],
											]
										}]
				];
}

@end
