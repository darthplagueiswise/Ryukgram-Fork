#import "SCISettingsSections.h"

@implementation SCITweakSettings (Section_Profile)

+ (SCISetting *)profileNavCell {
	return [SCISetting navigationCellWithTitle:SCILocalized(@"Profile")
										   subtitle:@""
											   icon:[SCISymbol symbolWithIGName:@"profile" fallback:@"person.crop.circle"]
										navSections:@[@{
											@"header": SCILocalized(@"Action button"),
											@"footer": SCILocalized(@"Adds a RyukGram action button to the profile header with copy, view picture, share, save, and profile-info entries. Tap opens the menu by default; change the tap behavior in Configure menu."),
											@"rows": @[
												[SCISetting switchCellWithTitle:SCILocalized(@"Show action button") subtitle:SCILocalized(@"Inserts a button in the profile navigation header") defaultsKey:@"action_button_profile_enabled" requiresRestart:YES],
												({ SCISetting *s = [SCISetting navigationCellWithTitle:SCILocalized(@"Configure menu")
																			subtitle:SCILocalized(@"Reorder, enable/disable, set default tap")
																				icon:nil
																	  viewController:[[SCIActionMenuConfigViewController alloc] initForSource:SCIActionSourceProfile]];
												   s.whatsNewID = @"ui_cfg_actionmenu"; s; }),
											]
										},
										@{
											@"header": SCILocalized(@"Profile stats"),
											@"rows": @[
												[SCISetting switchCellWithTitle:SCILocalized(@"Show full follower count") subtitle:@"" defaultsKey:@"full_followers_count"],
												[SCISetting switchCellWithTitle:SCILocalized(@"Show full post count") subtitle:@"" defaultsKey:@"full_posts_count"],
											]
										},
										@{
											@"header": SCILocalized(@"Hide"),
											@"rows": @[
												[SCISetting switchCellWithTitle:SCILocalized(@"No suggested users") subtitle:SCILocalized(@"Hides suggested accounts") defaultsKey:@"no_profile_suggested_users"],
											]
										},
										@{
											@"header": SCILocalized(@"Follower & following lists"),
											@"footer": SCILocalized(@"Adds a button to filter & sort any followers/following list. Resets when you leave."),
											@"rows": @[
												[SCISetting switchCellWithTitle:SCILocalized(@"Filter & sort lists") subtitle:@"" defaultsKey:@"sci_followlist_sort_enabled" requiresRestart:YES],
											]
										},
										@{
											@"header": SCILocalized(@"Profile card details"),
											@"footer": SCILocalized(@"Extra stats shown on each post and reel card in profile grids."),
											@"rows": @[
												[SCISetting switchCellWithTitle:SCILocalized(@"Override view count") subtitle:@"" defaultsKey:@"reel_card_full_views" requiresRestart:YES],
												[SCISetting switchCellWithTitle:SCILocalized(@"Show like count") subtitle:@"" defaultsKey:@"reel_card_show_likes" requiresRestart:YES],
												[SCISetting switchCellWithTitle:SCILocalized(@"Show upload date") subtitle:@"" defaultsKey:@"reel_card_show_date" requiresRestart:YES],
												[SCISetting switchCellWithTitle:SCILocalized(@"Short numbers") subtitle:SCILocalized(@"Render counts in shortened format.") defaultsKey:@"reel_card_shortened_numbers"],
												[SCISetting switchCellWithTitle:SCILocalized(@"Fetch missing counts") subtitle:SCILocalized(@"Uses Instagram's API. May hit rate limits.") defaultsKey:@"reel_card_fetch_missing"],
											]
										},
										@{
											@"header": SCILocalized(@"Long-press gestures"),
											@"footer": SCILocalized(@"Long-press gestures on profile elements — kept separate from the per-feature action buttons."),
											@"rows": @[
												[SCISetting switchCellWithTitle:SCILocalized(@"Zoom profile photo") subtitle:SCILocalized(@"Long press a profile picture to open it in full-screen with zoom, share, and save") defaultsKey:@"zoom_profile_photo"],
												[SCISetting switchCellWithTitle:SCILocalized(@"Save profile picture") subtitle:SCILocalized(@"Long press to download directly (ignored when zoom is on)") defaultsKey:@"save_profile"],
												[SCISetting switchCellWithTitle:SCILocalized(@"View highlight cover") subtitle:SCILocalized(@"Adds a view option to the highlight long-press menu to open the cover in full-screen") defaultsKey:@"download_highlight_cover"],
												[SCISetting menuCellWithTitle:SCILocalized(@"Follow indicator") subtitle:SCILocalized(@"Shows whether the profile user follows you") menu:[self menus][@"follow_indicator"]],
												[SCISetting switchCellWithTitle:SCILocalized(@"Copy note on long press") subtitle:SCILocalized(@"Long press the note bubble on a profile to copy the text") defaultsKey:@"profile_note_copy"],
											]
										},
										@{
											@"header": SCILocalized(@"Fake profile stats"),
											@"footer": SCILocalized(@"Only affects your own profile header. Other users see the real numbers."),
											@"rows": @[
												[SCISetting switchCellWithTitle:SCILocalized(@"Fake verified badge") subtitle:SCILocalized(@"Show a checkmark next to your name on your own profile") defaultsKey:@"fake_verified" requiresRestart:YES],
												[SCISetting switchCellWithTitle:SCILocalized(@"Fake follower count") subtitle:@"" defaultsKey:@"fake_follower_count" requiresRestart:YES],
												[SCISetting buttonCellWithTitle:SCILocalized(@"Follower count")
																		subtitle:[[NSUserDefaults standardUserDefaults] stringForKey:@"fake_follower_count_value"] ?: SCILocalized(@"Tap to set")
																			icon:nil
																		  action:^{ [self promptFakeCountForKey:@"fake_follower_count_value" title:SCILocalized(@"Follower count")]; }],
												[SCISetting switchCellWithTitle:SCILocalized(@"Fake following count") subtitle:@"" defaultsKey:@"fake_following_count" requiresRestart:YES],
												[SCISetting buttonCellWithTitle:SCILocalized(@"Following count")
																		subtitle:[[NSUserDefaults standardUserDefaults] stringForKey:@"fake_following_count_value"] ?: SCILocalized(@"Tap to set")
																			icon:nil
																		  action:^{ [self promptFakeCountForKey:@"fake_following_count_value" title:SCILocalized(@"Following count")]; }],
												[SCISetting switchCellWithTitle:SCILocalized(@"Fake post count") subtitle:@"" defaultsKey:@"fake_post_count" requiresRestart:YES],
												[SCISetting buttonCellWithTitle:SCILocalized(@"Post count")
																		subtitle:[[NSUserDefaults standardUserDefaults] stringForKey:@"fake_post_count_value"] ?: SCILocalized(@"Tap to set")
																			icon:nil
																		  action:^{ [self promptFakeCountForKey:@"fake_post_count_value" title:SCILocalized(@"Post count")]; }],
											]
										}]
				];
}

@end
