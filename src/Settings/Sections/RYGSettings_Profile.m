#import "RYGSettingsSections.h"

@implementation RYGTweakSettings (Section_Profile)

+ (RYGSetting *)profileNavCell {
	return [RYGSetting navigationCellWithTitle:RYGLocalized(@"Profile")
										   subtitle:@""
											   icon:[RYGSymbol symbolWithIGName:@"profile" fallback:@"person.crop.circle"]
										navSections:@[@{
											@"header": RYGLocalized(@"Action button"),
											@"footer": RYGLocalized(@"Adds a RyukGram action button to the profile header with copy, view picture, share, save, and profile-info entries. Tap opens the menu by default; change the tap behavior in Configure menu."),
											@"rows": @[
												[RYGSetting switchCellWithTitle:RYGLocalized(@"Show action button") subtitle:RYGLocalized(@"Inserts a button in the profile navigation header") defaultsKey:@"action_button_profile_enabled" requiresRestart:YES],
												({ RYGSetting *s = [RYGSetting navigationCellWithTitle:RYGLocalized(@"Configure menu")
																			subtitle:RYGLocalized(@"Reorder, enable/disable, set default tap")
																				icon:nil
																	  viewController:[[RYGActionMenuConfigViewController alloc] initForSource:RYGActionSourceProfile]];
												   s.whatsNewID = @"ui_cfg_actionmenu"; s; }),
											]
										},
										@{
											@"header": RYGLocalized(@"Profile stats"),
											@"rows": @[
												[RYGSetting switchCellWithTitle:RYGLocalized(@"Show full follower count") subtitle:RYGLocalized(@"Show the exact number instead of a shortened one") defaultsKey:@"full_followers_count"],
												[RYGSetting switchCellWithTitle:RYGLocalized(@"Show full post count") subtitle:RYGLocalized(@"Show the exact number instead of a shortened one") defaultsKey:@"full_posts_count"],
											]
										},
										@{
											@"header": RYGLocalized(@"Hide"),
											@"rows": @[
												[RYGSetting switchCellWithTitle:RYGLocalized(@"No suggested users") subtitle:RYGLocalized(@"Hides suggested accounts") defaultsKey:@"no_profile_suggested_users"],
											]
										},
										@{
											@"header": RYGLocalized(@"Follower & following lists"),
											@"footer": RYGLocalized(@"Adds a button to filter & sort any followers/following list. Resets when you leave."),
											@"rows": @[
												[RYGSetting switchCellWithTitle:RYGLocalized(@"Filter & sort lists") subtitle:@"" defaultsKey:@"ryg_followlist_sort_enabled" requiresRestart:YES],
											]
										},
										@{
											@"header": RYGLocalized(@"Profile card details"),
											@"footer": RYGLocalized(@"Extra stats shown on each post and reel card in profile grids — pick which, reorder them, then apply."),
											@"rows": @[
												({ RYGSetting *s = [RYGSetting navigationCellWithTitle:RYGLocalized(@"Card details")
																		   subtitle:RYGLocalized(@"Views, likes, comments, shares, reposts, date")
																			   icon:nil
																	 viewController:[RYGProfileCardDetailsViewController new]];
												   s.whatsNewID = @"ui_profilecard"; s; }),
											]
										},
										@{
											@"header": RYGLocalized(@"Long-press gestures"),
											@"footer": RYGLocalized(@"Long-press gestures on profile elements — kept separate from the per-feature action buttons."),
											@"rows": @[
												[RYGSetting switchCellWithTitle:RYGLocalized(@"Zoom profile photo") subtitle:RYGLocalized(@"Long press a profile picture to open it in full-screen with zoom, share, and save") defaultsKey:@"zoom_profile_photo"],
												[RYGSetting switchCellWithTitle:RYGLocalized(@"Save profile picture") subtitle:RYGLocalized(@"Long press to download directly (ignored when zoom is on)") defaultsKey:@"save_profile"],
												[RYGSetting switchCellWithTitle:RYGLocalized(@"View highlight cover") subtitle:RYGLocalized(@"Adds a view option to the highlight long-press menu to open the cover in full-screen") defaultsKey:@"download_highlight_cover"],
												[RYGSetting menuCellWithTitle:RYGLocalized(@"Follow indicator") subtitle:RYGLocalized(@"Shows whether the profile user follows you") menu:[self menus][@"follow_indicator"]],
												[RYGSetting switchCellWithTitle:RYGLocalized(@"Copy note on long press") subtitle:RYGLocalized(@"Long press the note bubble on a profile to copy the text") defaultsKey:@"profile_note_copy"],
											]
										},
										@{
											@"header": RYGLocalized(@"Fake profile stats"),
											@"footer": RYGLocalized(@"Only affects your own profile header. Other users see the real numbers."),
											@"rows": @[
												[RYGSetting switchCellWithTitle:RYGLocalized(@"Fake verified badge") subtitle:RYGLocalized(@"Show a checkmark next to your name on your own profile") defaultsKey:@"fake_verified" requiresRestart:YES],
												[RYGSetting switchCellWithTitle:RYGLocalized(@"Fake follower count") subtitle:RYGLocalized(@"Show the custom number set below") defaultsKey:@"fake_follower_count" requiresRestart:YES],
												[RYGSetting buttonCellWithTitle:RYGLocalized(@"Follower count")
																		subtitle:[[NSUserDefaults standardUserDefaults] stringForKey:@"fake_follower_count_value"] ?: RYGLocalized(@"Tap to set")
																			icon:nil
																		  action:^{ [self promptFakeCountForKey:@"fake_follower_count_value" title:RYGLocalized(@"Follower count")]; }],
												[RYGSetting switchCellWithTitle:RYGLocalized(@"Fake following count") subtitle:RYGLocalized(@"Show the custom number set below") defaultsKey:@"fake_following_count" requiresRestart:YES],
												[RYGSetting buttonCellWithTitle:RYGLocalized(@"Following count")
																		subtitle:[[NSUserDefaults standardUserDefaults] stringForKey:@"fake_following_count_value"] ?: RYGLocalized(@"Tap to set")
																			icon:nil
																		  action:^{ [self promptFakeCountForKey:@"fake_following_count_value" title:RYGLocalized(@"Following count")]; }],
												[RYGSetting switchCellWithTitle:RYGLocalized(@"Fake post count") subtitle:RYGLocalized(@"Show the custom number set below") defaultsKey:@"fake_post_count" requiresRestart:YES],
												[RYGSetting buttonCellWithTitle:RYGLocalized(@"Post count")
																		subtitle:[[NSUserDefaults standardUserDefaults] stringForKey:@"fake_post_count_value"] ?: RYGLocalized(@"Tap to set")
																			icon:nil
																		  action:^{ [self promptFakeCountForKey:@"fake_post_count_value" title:RYGLocalized(@"Post count")]; }],
											]
										}]
				];
}

@end
