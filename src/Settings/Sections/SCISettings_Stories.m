#import "SCISettingsSections.h"

@implementation SCITweakSettings (Section_Stories)

+ (SCISetting *)storiesNavCell {
	return [SCISetting navigationCellWithTitle:SCILocalized(@"Stories")
										   subtitle:@""
											   icon:[SCISymbol symbolWithIGName:@"story" fallback:@"circle.dashed"]
										navSections:@[@{
											@"header": SCILocalized(@"Action button"),
											@"footer": SCILocalized(@"Adds a RyukGram action button next to the eye button on stories with download/share/copy/expand/repost/view-mentions entries. Tap opens the menu by default; change the tap behavior below."),
											@"rows": @[
												[SCISetting switchCellWithTitle:SCILocalized(@"Show action button") subtitle:SCILocalized(@"Inserts a button next to the seen/eye button on story overlays") defaultsKey:@"stories_action_button" requiresRestart:YES],
												({ SCISetting *s = [SCISetting navigationCellWithTitle:SCILocalized(@"Configure menu")
																			subtitle:SCILocalized(@"Reorder, enable/disable, set default tap, show date")
																				icon:nil
																	  viewController:[[SCIActionMenuConfigViewController alloc] initForSource:SCIActionSourceStories]];
												   s.whatsNewID = @"ui_cfg_actionmenu"; s; }),
											]
										},
										@{
											@"header": SCILocalized(@"Seen receipts"),
											@"rows": @[
												[SCISetting switchCellWithTitle:SCILocalized(@"Disable story seen receipt") subtitle:SCILocalized(@"Hides the notification for others when you view their story") defaultsKey:@"no_seen_receipt" requiresRestart:YES],
												[SCISetting switchCellWithTitle:SCILocalized(@"Show seen button") subtitle:SCILocalized(@"Adds the eye button to story overlays. Off keeps seen blocking on without the button") defaultsKey:@"show_story_seen_button" requiresRestart:YES],
												[SCISetting switchCellWithTitle:SCILocalized(@"Keep stories visually seen locally") subtitle:SCILocalized(@"Marks stories as seen locally (grey ring) while still blocking the seen receipt on the server") defaultsKey:@"keep_seen_visual_local"],
												[SCISetting switchCellWithTitle:SCILocalized(@"Mark seen on story like") subtitle:SCILocalized(@"Marks a story as seen the moment you tap the heart, even with seen blocking on") defaultsKey:@"seen_on_story_like"],
												[SCISetting switchCellWithTitle:SCILocalized(@"Mark seen on story reply") subtitle:SCILocalized(@"Marks a story as seen when you send a reply or emoji reaction, even with seen blocking on") defaultsKey:@"seen_on_story_reply"],
												[SCISetting menuCellWithTitle:SCILocalized(@"Manual seen button mode") subtitle:SCILocalized(@"Button = single-tap mark seen. Toggle = tap toggles story read receipts on/off (eye fills blue when on)") menu:[self menus][@"story_seen_mode"]],
											]
										},
										@{
											@"header": SCILocalized(@"Playback"),
											@"rows": @[
												[SCISetting switchCellWithTitle:SCILocalized(@"Stop story auto-advance") subtitle:SCILocalized(@"Stories won't auto-skip to the next one when the timer ends. Tap to advance manually") defaultsKey:@"stop_story_auto_advance"],
												[SCISetting switchCellWithTitle:SCILocalized(@"Advance when marking as seen") subtitle:SCILocalized(@"Tapping the eye button to mark a story as seen advances to the next story automatically") defaultsKey:@"advance_on_mark_seen"],
												[SCISetting switchCellWithTitle:SCILocalized(@"Advance on story like") subtitle:SCILocalized(@"Liking a story automatically advances to the next one after a short delay") defaultsKey:@"advance_on_story_like"],
												[SCISetting switchCellWithTitle:SCILocalized(@"Advance on story reply") subtitle:SCILocalized(@"Sending a reply or emoji reaction automatically advances to the next story") defaultsKey:@"advance_on_story_reply"],
											]
										},
										@{
											@"header": SCILocalized(@"Story user list"),
											@"footer": SCILocalized(@"Block all: all stories blocked — listed users are exceptions.\nBlock selected: only listed users are blocked — everything else is normal.\nBoth lists are saved independently."),
											@"rows": @[
												[SCISetting switchCellWithTitle:SCILocalized(@"Enable story user list") subtitle:SCILocalized(@"Master toggle. When off, the list is ignored") defaultsKey:@"enable_story_user_exclusions"],
												[SCISetting menuCellWithTitle:SCILocalized(@"Blocking mode") subtitle:SCILocalized(@"Which stories get seen-receipt blocking") menu:[self menus][@"story_blocking_mode"]],
												({
													SCISetting *s = [SCISetting buttonCellWithTitle:SCILocalized(@"Manage list")
																	   subtitle:SCILocalized(@"Search, sort, swipe to remove")
																		   icon:[SCISymbol symbolWithIGName:@"ig_icon_edit_list_outline_24" fallback:@"list.bullet.rectangle"]
																		 action:^(void) {
														UIWindow *win = nil;
														for (UIWindow *w in [UIApplication sharedApplication].windows) {
															if (w.isKeyWindow) { win = w; break; }
														}
														UIViewController *top = win.rootViewController;
														while (top.presentedViewController) top = top.presentedViewController;
														if ([top isKindOfClass:[UINavigationController class]]) {
															[(UINavigationController *)top pushViewController:[SCIExcludedStoryUsersViewController new] animated:YES];
														} else if (top.navigationController) {
															[top.navigationController pushViewController:[SCIExcludedStoryUsersViewController new] animated:YES];
														}
													}];
													s.dynamicTitle = ^{ return [NSString stringWithFormat:SCILocalized(@"Manage list (%lu)"), (unsigned long)[SCIExcludedStoryUsers count]]; };
													s;
												}),
											]
										},
										@{
											@"header": SCILocalized(@"Audio"),
											@"rows": @[
												[SCISetting switchCellWithTitle:SCILocalized(@"Story audio toggle") subtitle:SCILocalized(@"Adds a speaker button to the story overlay to unmute/mute audio. Also available in the 3-dot menu") defaultsKey:@"story_audio_toggle" requiresRestart:YES],
											]
										},
										@{
											@"header": SCILocalized(@"Stickers"),
											@"footer": SCILocalized(@"Peek at poll/quiz/slider results before interacting — you can still tap to vote normally. Force legacy adds the Quiz and Reveal stickers back to the story composer."),
											@"rows": @[
												[SCISetting switchCellWithTitle:SCILocalized(@"Force legacy stickers in tray") subtitle:SCILocalized(@"Adds Quiz and Reveal stickers back to the picker") defaultsKey:@"force_enable_quiz_sticker" requiresRestart:YES],
												[SCISetting switchCellWithTitle:SCILocalized(@"Bypass Reveal sticker") subtitle:SCILocalized(@"Skip the DM-to-reveal step on stories with a Reveal sticker") defaultsKey:@"bypass_reveal_sticker"],
												[SCISetting switchCellWithTitle:SCILocalized(@"Show quiz answer") subtitle:SCILocalized(@"Circle the correct option on quiz stickers, or the leading option on polls") defaultsKey:@"stories_show_quiz_answer"],
												[SCISetting switchCellWithTitle:SCILocalized(@"Show poll vote counts") subtitle:SCILocalized(@"Show vote tallies on poll options and slider count/average before you vote") defaultsKey:@"stories_show_poll_votes_count"],
												[SCISetting switchCellWithTitle:SCILocalized(@"Custom sticker colors") subtitle:SCILocalized(@"Long-press the color wheel in sticker editors to pick any solid or gradient color") defaultsKey:@"custom_music_sticker_color"],
												[SCISetting switchCellWithTitle:SCILocalized(@"Allow video in photo sticker") subtitle:SCILocalized(@"Lets the photo sticker picker show videos too, not just photos") defaultsKey:@"photo_sticker_allow_video"],
												[SCISetting switchCellWithTitle:SCILocalized(@"Use detailed color picker") subtitle:SCILocalized(@"Long press on the eyedropper tool in stories to customize the text color more precisely") defaultsKey:@"detailed_color_picker"],
											]
										},
										@{
											@"header": SCILocalized(@"Mentions"),
											@"rows": @[
												[SCISetting switchCellWithTitle:SCILocalized(@"View story mentions") subtitle:SCILocalized(@"Adds a 'View mentions' entry to the action button menu and story 3-dot menu") defaultsKey:@"view_story_mentions"],
												[SCISetting switchCellWithTitle:SCILocalized(@"Mentions overlay button") subtitle:SCILocalized(@"Adds a button next to the action/eye button on the story overlay. Only appears when the current story has mentions or shared posts/reels") defaultsKey:@"story_mentions_button" requiresRestart:YES],
												[SCISetting switchCellWithTitle:SCILocalized(@"Mentions count badge") subtitle:SCILocalized(@"Shows the number of unique mentioned accounts as a red badge on the overlay button") defaultsKey:@"story_mentions_counter"]
											]
										}]
				];
}

@end
