#import "SCISettingsSections.h"

@implementation SCITweakSettings (Section_Reels)

+ (SCISetting *)reelsNavCell {
	return [SCISetting navigationCellWithTitle:SCILocalized(@"Reels")
										   subtitle:@""
											   icon:[SCISymbol symbolWithIGName:@"reels" fallback:@"film.stack"]
										navSections:@[@{
											@"header": SCILocalized(@"Action button"),
											@"footer": SCILocalized(@"Adds a RyukGram action button above the reel sidebar with view-cover/download/share/copy/expand/repost entries. Tap opens the menu by default; change the tap behavior below."),
											@"rows": @[
												[SCISetting switchCellWithTitle:SCILocalized(@"Show action button") subtitle:SCILocalized(@"Places a button above the like/comment/share column on each reel") defaultsKey:@"reels_action_button"],
												({ SCISetting *s = [SCISetting navigationCellWithTitle:SCILocalized(@"Configure menu")
																			subtitle:SCILocalized(@"Reorder, enable/disable, set default tap, show date")
																				icon:nil
																	  viewController:[[SCIActionMenuConfigViewController alloc] initForSource:SCIActionSourceReels]];
												   s.whatsNewID = @"ui_cfg_actionmenu"; s; }),
											]
										},
										@{
											@"header": @"",
											@"rows": @[
												[SCISetting menuCellWithTitle:SCILocalized(@"Tap Controls") subtitle:SCILocalized(@"Change what happens when you tap on a reel") menu:[self menus][@"reels_tap_control"]],
												[SCISetting menuCellWithTitle:SCILocalized(@"Auto-scroll reels") subtitle:SCILocalized(@"IG default: native behavior. RyukGram: re-advances after swiping back.") menu:[self menus][@"auto_scroll_reels_mode"]],
												[SCISetting switchCellWithTitle:SCILocalized(@"Always show progress scrubber") subtitle:SCILocalized(@"Forces the progress bar to appear on every reel") defaultsKey:@"reels_show_scrubber"],
												[SCISetting switchCellWithTitle:SCILocalized(@"Disable auto-unmuting reels") subtitle:SCILocalized(@"Prevents reels from unmuting when the volume/silent button is pressed") defaultsKey:@"disable_auto_unmuting_reels" requiresRestart:YES],
												[SCISetting switchCellWithTitle:SCILocalized(@"Confirm reel refresh") subtitle:SCILocalized(@"Shows an alert when you trigger a reels refresh") defaultsKey:@"refresh_reel_confirm"],
												[SCISetting switchCellWithTitle:SCILocalized(@"Disable tab button refresh") subtitle:SCILocalized(@"Tapping the Reels tab while on reels does nothing") defaultsKey:@"disable_reels_tab_refresh"],
												[SCISetting switchCellWithTitle:SCILocalized(@"Swipe left to profile") subtitle:SCILocalized(@"Swipe a reel left to open the author's profile") defaultsKey:@"reels_swipe_to_profile"],
												[SCISetting switchCellWithTitle:SCILocalized(@"Unlock password-locked reels") subtitle:SCILocalized(@"Shows buttons to reveal and auto-fill the password on locked reels") defaultsKey:@"unlock_password_reels"],
												[SCISetting switchCellWithTitle:SCILocalized(@"Playback speed") subtitle:SCILocalized(@"Hold the 3-dot on any reel to open speed picker") defaultsKey:@"reels_playback_speed"],
											]
										},
										@{
											@"header": SCILocalized(@"Hiding"),
											@"rows": @[
												[SCISetting switchCellWithTitle:SCILocalized(@"Hide reels header") subtitle:SCILocalized(@"Hides the top navigation bar when watching reels") defaultsKey:@"hide_reels_header"],
												[SCISetting switchCellWithTitle:SCILocalized(@"Hide repost button") subtitle:SCILocalized(@"Hides the repost button on the reels sidebar") defaultsKey:@"hide_reels_repost" requiresRestart:YES],
												[SCISetting switchCellWithTitle:SCILocalized(@"Hide friends avatars") subtitle:SCILocalized(@"Hides the avatar bubbles next to the Friends tab in reels") defaultsKey:@"hide_reels_friends_bubbles"],
												[SCISetting switchCellWithTitle:SCILocalized(@"Hide social context overlay") subtitle:SCILocalized(@"Hides the floating overlay showing who reposted or commented on reels") defaultsKey:@"hide_reels_floating_social_context"],
												[SCISetting switchCellWithTitle:SCILocalized(@"Hide \"Made with Edits\" badge") subtitle:SCILocalized(@"Hides the Edits app promo pill on reels") defaultsKey:@"hide_made_with_edits"]
											]
										},
										@{
											@"header": SCILocalized(@"Limits"),
											@"rows": @[
												[SCISetting switchCellWithTitle:SCILocalized(@"Disable scrolling reels") subtitle:SCILocalized(@"Prevents reels from being scrolled to the next video") defaultsKey:@"disable_scrolling_reels" requiresRestart:YES],
												[SCISetting switchCellWithTitle:SCILocalized(@"Prevent doom scrolling") subtitle:SCILocalized(@"Limits the amount of reels available to scroll at any given time, and prevents refreshing") defaultsKey:@"prevent_doom_scrolling"],
												[SCISetting stepperCellWithTitle:SCILocalized(@"Doom scrolling limit") subtitle:SCILocalized(@"Only loads %@ %@") defaultsKey:@"doom_scrolling_reel_count" min:1 max:100 step:1 label:@"reels" singularLabel:@"reel"]
											]
										},
										@{
											@"header": SCILocalized(@"Stickers"),
											@"footer": SCILocalized(@"Peek at poll/quiz/slider results on reels before interacting — you can still tap to vote normally."),
											@"rows": @[
												[SCISetting switchCellWithTitle:SCILocalized(@"Show quiz answer") subtitle:SCILocalized(@"Circle the correct option on quiz stickers, or the leading option on polls") defaultsKey:@"reels_show_quiz_answer"],
												[SCISetting switchCellWithTitle:SCILocalized(@"Show poll vote counts") subtitle:SCILocalized(@"Show vote tallies on poll options and slider count/average before you vote") defaultsKey:@"reels_show_poll_votes_count"],
											]
										},
										@{
											@"header": SCILocalized(@"Advanced"),
											@"rows": @[
												[SCISetting switchCellWithTitle:SCILocalized(@"Tap to mute on photo reels") subtitle:SCILocalized(@"When pause mode is on, tap on photo reels toggles audio instead of the native pause gesture") defaultsKey:@"reels_photo_tap_mute"],
											]
										}]
				];
}

@end
