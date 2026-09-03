#import "RYGSettingsSections.h"
#import "../../Features/Feed/GridFeed/RYGGridFeedSettingsViewController.h"

@implementation RYGTweakSettings (Section_Feed)

+ (RYGSetting *)feedNavCell {
	return [RYGSetting navigationCellWithTitle:RYGLocalized(@"Feed")
										   subtitle:@""
											   icon:[RYGSymbol symbolWithIGName:@"feed" fallback:@"rectangle.stack"]
										navSections:@[@{
											@"header": RYGLocalized(@"Main feed"),
											@"rows": @[
												[RYGSetting menuCellWithTitle:RYGLocalized(@"Main feed") subtitle:RYGLocalized(@"Choose Instagram's default feed or force the Following feed") menu:[self menus][@"main_feed_mode"]],
											]
										},
										@{
											@"header": RYGLocalized(@"Grid feed"),
											@"rows": @[
												({ RYGSetting *s = [RYGSetting navigationCellWithTitle:RYGLocalized(@"Grid feed") subtitle:RYGLocalized(@"Browse your home feed as a grid of posts") icon:[RYGSymbol symbolWithIGName:@"ig_icon_photo_grid_tall_filled_24" fallback:@"square.grid.3x3.fill"] viewController:[RYGGridFeedSettingsViewController new]];
												   s.whatsNewID = @"ui_gridfeed"; s; }),
											]
										},
										@{
											@"header": RYGLocalized(@"Action button"),
											@"footer": RYGLocalized(@"Adds a RyukGram action button under each feed post with download/share/copy/expand/repost entries. Tap opens the menu by default; change the tap behavior below."),
											@"rows": @[
												[RYGSetting switchCellWithTitle:RYGLocalized(@"Show action button") subtitle:RYGLocalized(@"Inserts a button row below like/comment/share on each post") defaultsKey:@"feed_action_button"],
												({ RYGSetting *s = [RYGSetting navigationCellWithTitle:RYGLocalized(@"Configure menu")
																			subtitle:RYGLocalized(@"Reorder, enable/disable, set default tap, show date")
																				icon:nil
																	  viewController:[[RYGActionMenuConfigViewController alloc] initForSource:RYGActionSourceFeed]];
												   s.whatsNewID = @"ui_cfg_actionmenu"; s; }),
											]
										},
										@{
											@"header": RYGLocalized(@"Media"),
											@"rows": @[
												[RYGSetting switchCellWithTitle:RYGLocalized(@"Media zoom") subtitle:RYGLocalized(@"Long press on media to expand in full-screen viewer") defaultsKey:@"feed_media_zoom"],
												[RYGSetting switchCellWithTitle:RYGLocalized(@"Start media muted") subtitle:RYGLocalized(@"Expanded videos open with sound off") defaultsKey:@"media_zoom_start_muted"],
												[RYGSetting switchCellWithTitle:RYGLocalized(@"Disable video autoplay") subtitle:RYGLocalized(@"Prevents videos from playing automatically") defaultsKey:@"disable_feed_autoplay" requiresRestart:YES],
											]
										},
										@{
											@"header": RYGLocalized(@"Reels"),
											@"rows": @[
												[RYGSetting menuCellWithTitle:RYGLocalized(@"Tap Controls") subtitle:RYGLocalized(@"Set what a tap on a reel does") menu:[self menus][@"feed_reel_tap"]],
											]
										},
										@{
											@"header": RYGLocalized(@"Stories tray"),
											@"rows": @[
												[RYGSetting switchCellWithTitle:RYGLocalized(@"Tray long-press actions") subtitle:RYGLocalized(@"Adds 'Profile picture' to story tray long-press menus") defaultsKey:@"story_tray_actions"],
											]
										},
										@{
											@"header": RYGLocalized(@"Hide"),
											@"rows": @[
												[RYGSetting switchCellWithTitle:RYGLocalized(@"Hide suggested stories") subtitle:RYGLocalized(@"Removes suggested accounts from the stories tray") defaultsKey:@"hide_suggested_stories"],
												[RYGSetting switchCellWithTitle:RYGLocalized(@"Hide story highlights") subtitle:RYGLocalized(@"Removes resurfaced highlights from the stories tray in feed") defaultsKey:@"hide_story_highlights"],
												[RYGSetting switchCellWithTitle:RYGLocalized(@"Hide stories midcards") subtitle:RYGLocalized(@"Removes the Trending and Music promo cards from the stories tray") defaultsKey:@"hide_stories_midcards" requiresRestart:YES],
												[RYGSetting switchCellWithTitle:RYGLocalized(@"Hide stories tray") subtitle:RYGLocalized(@"Hides the story tray at the top") defaultsKey:@"hide_stories_tray"],
												[RYGSetting switchCellWithTitle:RYGLocalized(@"Hide entire feed") subtitle:RYGLocalized(@"Removes all content from your home feed") defaultsKey:@"hide_entire_feed"],
												[RYGSetting switchCellWithTitle:RYGLocalized(@"Hide repost button") subtitle:RYGLocalized(@"Hides the repost button on feed posts") defaultsKey:@"hide_feed_repost" requiresRestart:YES],
												[RYGSetting switchCellWithTitle:RYGLocalized(@"No suggested posts") subtitle:RYGLocalized(@"Removes suggested posts") defaultsKey:@"no_suggested_post"],
												[RYGSetting switchCellWithTitle:RYGLocalized(@"No suggested for you") subtitle:RYGLocalized(@"Hides suggested accounts") defaultsKey:@"no_suggested_account"],
												[RYGSetting switchCellWithTitle:RYGLocalized(@"No suggested reels") subtitle:RYGLocalized(@"Hides suggested reels") defaultsKey:@"no_suggested_reels"],
												[RYGSetting switchCellWithTitle:RYGLocalized(@"No suggested threads") subtitle:RYGLocalized(@"Hides suggested threads posts") defaultsKey:@"no_suggested_threads"],
											]
										},
										@{
											@"header": RYGLocalized(@"Refresh"),
											@"footer": RYGLocalized(@"Controls when and how the feed refreshes. Background refresh occurs when returning to the app after ~10 minutes. Home button refresh occurs when tapping the Home tab while already on it."),
											@"rows": @[
												[RYGSetting switchCellWithTitle:RYGLocalized(@"Confirm feed refresh") subtitle:RYGLocalized(@"Shows an alert before a pull-to-refresh reloads the feed") defaultsKey:@"refresh_feed_confirm"],
												[RYGSetting switchCellWithTitle:RYGLocalized(@"Refresh stories only") subtitle:RYGLocalized(@"Pull-to-refresh reloads the stories tray without refreshing the feed") defaultsKey:@"refresh_feed_stories_only"],
												[RYGSetting switchCellWithTitle:RYGLocalized(@"Disable background refresh") subtitle:RYGLocalized(@"Prevents feed from reloading when returning from background") defaultsKey:@"disable_bg_refresh" requiresRestart:YES],
												[RYGSetting switchCellWithTitle:RYGLocalized(@"Disable home button refresh") subtitle:RYGLocalized(@"Scroll to top without refreshing when tapping Home") defaultsKey:@"disable_home_refresh"],
												[RYGSetting switchCellWithTitle:RYGLocalized(@"Disable home button scroll") subtitle:RYGLocalized(@"Tapping Home does nothing when already on feed") defaultsKey:@"disable_home_scroll"],
												[RYGSetting menuCellWithTitle:RYGLocalized(@"Status bar tap") subtitle:RYGLocalized(@"Tapping the top of the screen scrolls up and refreshes") menu:[self menus][@"feed_statusbar_tap"]],
											]
										}]
				];
}

@end
