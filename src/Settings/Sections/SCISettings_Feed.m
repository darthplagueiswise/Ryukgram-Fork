#import "SCISettingsSections.h"

@implementation SCITweakSettings (Section_Feed)

+ (SCISetting *)feedNavCell {
	return [SCISetting navigationCellWithTitle:SCILocalized(@"Feed")
										   subtitle:@""
											   icon:[SCISymbol symbolWithIGName:@"feed" fallback:@"rectangle.stack"]
										navSections:@[@{
											@"header": SCILocalized(@"Main feed"),
											@"rows": @[
												[SCISetting menuCellWithTitle:SCILocalized(@"Main feed") subtitle:SCILocalized(@"Choose Instagram's default feed or force the Following feed") menu:[self menus][@"main_feed_mode"]],
											]
										},
										@{
											@"header": SCILocalized(@"Action button"),
											@"footer": SCILocalized(@"Adds a RyukGram action button under each feed post with download/share/copy/expand/repost entries. Tap opens the menu by default; change the tap behavior below."),
											@"rows": @[
												[SCISetting switchCellWithTitle:SCILocalized(@"Show action button") subtitle:SCILocalized(@"Inserts a button row below like/comment/share on each post") defaultsKey:@"feed_action_button"],
												({ SCISetting *s = [SCISetting navigationCellWithTitle:SCILocalized(@"Configure menu")
																			subtitle:SCILocalized(@"Reorder, enable/disable, set default tap, show date")
																				icon:nil
																	  viewController:[[SCIActionMenuConfigViewController alloc] initForSource:SCIActionSourceFeed]];
												   s.whatsNewID = @"ui_cfg_actionmenu"; s; }),
											]
										},
										@{
											@"header": SCILocalized(@"Media"),
											@"rows": @[
												[SCISetting switchCellWithTitle:SCILocalized(@"Media zoom") subtitle:SCILocalized(@"Long press on media to expand in full-screen viewer") defaultsKey:@"feed_media_zoom"],
												[SCISetting switchCellWithTitle:SCILocalized(@"Start media muted") subtitle:SCILocalized(@"Expanded videos open with sound off") defaultsKey:@"media_zoom_start_muted"],
												[SCISetting switchCellWithTitle:SCILocalized(@"Disable video autoplay") subtitle:SCILocalized(@"Prevents videos from playing automatically") defaultsKey:@"disable_feed_autoplay" requiresRestart:YES],
											]
										},
										@{
											@"header": SCILocalized(@"Stories tray"),
											@"rows": @[
												[SCISetting switchCellWithTitle:SCILocalized(@"Tray long-press actions") subtitle:SCILocalized(@"Adds 'View profile picture' and 'View cover' to story tray long-press menus") defaultsKey:@"story_tray_actions"],
											]
										},
										@{
											@"header": SCILocalized(@"Hide"),
											@"rows": @[
												[SCISetting switchCellWithTitle:SCILocalized(@"Hide suggested stories") subtitle:SCILocalized(@"Removes suggested accounts from the stories tray") defaultsKey:@"hide_suggested_stories"],
												[SCISetting switchCellWithTitle:SCILocalized(@"Hide stories midcards") subtitle:SCILocalized(@"Removes the Trending and Music promo cards from the stories tray") defaultsKey:@"hide_stories_midcards" requiresRestart:YES],
												[SCISetting switchCellWithTitle:SCILocalized(@"Hide stories tray") subtitle:SCILocalized(@"Hides the story tray at the top") defaultsKey:@"hide_stories_tray"],
												[SCISetting switchCellWithTitle:SCILocalized(@"Hide entire feed") subtitle:SCILocalized(@"Removes all content from your home feed") defaultsKey:@"hide_entire_feed"],
												[SCISetting switchCellWithTitle:SCILocalized(@"Hide repost button") subtitle:SCILocalized(@"Hides the repost button on feed posts") defaultsKey:@"hide_feed_repost" requiresRestart:YES],
												[SCISetting switchCellWithTitle:SCILocalized(@"No suggested posts") subtitle:SCILocalized(@"Removes suggested posts") defaultsKey:@"no_suggested_post"],
												[SCISetting switchCellWithTitle:SCILocalized(@"No suggested for you") subtitle:SCILocalized(@"Hides suggested accounts") defaultsKey:@"no_suggested_account"],
												[SCISetting switchCellWithTitle:SCILocalized(@"No suggested reels") subtitle:SCILocalized(@"Hides suggested reels") defaultsKey:@"no_suggested_reels"],
												[SCISetting switchCellWithTitle:SCILocalized(@"No suggested threads") subtitle:SCILocalized(@"Hides suggested threads posts") defaultsKey:@"no_suggested_threads"],
											]
										},
										@{
											@"header": SCILocalized(@"Refresh"),
											@"footer": SCILocalized(@"Controls when and how the feed refreshes. Background refresh occurs when returning to the app after ~10 minutes. Home button refresh occurs when tapping the Home tab while already on it."),
											@"rows": @[
												[SCISetting switchCellWithTitle:SCILocalized(@"Disable background refresh") subtitle:SCILocalized(@"Prevents feed from reloading when returning from background") defaultsKey:@"disable_bg_refresh" requiresRestart:YES],
												[SCISetting switchCellWithTitle:SCILocalized(@"Disable home button refresh") subtitle:SCILocalized(@"Scroll to top without refreshing when tapping Home") defaultsKey:@"disable_home_refresh"],
												[SCISetting switchCellWithTitle:SCILocalized(@"Disable home button scroll") subtitle:SCILocalized(@"Tapping Home does nothing when already on feed") defaultsKey:@"disable_home_scroll"],
											]
										}]
				];
}

@end
