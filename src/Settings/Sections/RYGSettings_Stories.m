#import "RYGSettingsSections.h"
#import "../RYGStoryViewerPinsViewController.h"
#import "../RYGOverlayLayoutEditorViewController.h"
#import "../../Features/StoriesAndMessages/RYGStoryButtonLayout.h"
#import "../../Features/StoriesAndMessages/RYGStoryViewerPins.h"

@implementation RYGTweakSettings (Section_Stories)

+ (RYGSetting *)storiesNavCell {
	return [RYGSetting navigationCellWithTitle:RYGLocalized(@"Stories")
										   subtitle:@""
											   icon:[RYGSymbol symbolWithIGName:@"story" fallback:@"circle.dashed"]
										navSections:@[@{
											@"header": RYGLocalized(@"Action button"),
											@"footer": RYGLocalized(@"Adds a RyukGram action button next to the eye button on stories with download/share/copy/expand/repost/view-mentions entries. Tap opens the menu by default; change the tap behavior below."),
											@"rows": @[
												[RYGSetting switchCellWithTitle:RYGLocalized(@"Show action button") subtitle:RYGLocalized(@"Inserts a button next to the seen/eye button on story overlays") defaultsKey:@"stories_action_button" requiresRestart:YES],
												({ RYGSetting *s = [RYGSetting navigationCellWithTitle:RYGLocalized(@"Configure menu")
																			subtitle:RYGLocalized(@"Reorder, enable/disable, set default tap, show date")
																				icon:nil
																	  viewController:[[RYGActionMenuConfigViewController alloc] initForSource:RYGActionSourceStories]];
												   s.whatsNewID = @"ui_cfg_actionmenu"; s; }),
											]
										},
										@{
											@"header": RYGLocalized(@"Overlay layout"),
											@"rows": @[
												({ RYGSetting *s = [RYGSetting navigationCellWithTitle:RYGLocalized(@"Arrange overlay buttons")
																		   subtitle:RYGLocalized(@"Drag to position the buttons")
																			   icon:[RYGSymbol symbolWithIGName:@"reposition" fallback:@"hand.draw"]
																	 viewController:[[RYGOverlayLayoutEditorViewController alloc] initWithLayoutClass:RYGStoryButtonLayout.class]];
												   s.whatsNewID = @"ui_overlaylayout"; s; }),
												[RYGSetting switchCellWithTitle:RYGLocalized(@"Close gaps automatically") subtitle:RYGLocalized(@"Buttons next to each other close the gap when one is hidden") defaultsKey:@"story_button_positions_auto_compact"],
											]
										},
										@{
											@"header": RYGLocalized(@"Seen receipts"),
											@"rows": @[
												[RYGSetting switchCellWithTitle:RYGLocalized(@"Disable story seen receipt") subtitle:RYGLocalized(@"Stops others from seeing that you viewed their story") defaultsKey:@"no_seen_receipt" requiresRestart:YES],
												[RYGSetting switchCellWithTitle:RYGLocalized(@"Show seen button") subtitle:RYGLocalized(@"Adds the eye button to story overlays. Off keeps seen blocking on without the button") defaultsKey:@"show_story_seen_button" requiresRestart:YES],
												[RYGSetting switchCellWithTitle:RYGLocalized(@"Keep stories visually seen locally") subtitle:RYGLocalized(@"Marks stories as seen locally (grey ring) while still blocking the seen receipt on the server") defaultsKey:@"keep_seen_visual_local"],
												[RYGSetting switchCellWithTitle:RYGLocalized(@"Mark seen on story like") subtitle:RYGLocalized(@"Marks a story as seen the moment you tap the heart, even with seen blocking on") defaultsKey:@"seen_on_story_like"],
												[RYGSetting switchCellWithTitle:RYGLocalized(@"Mark seen on story reply") subtitle:RYGLocalized(@"Marks a story as seen when you send a reply or emoji reaction, even with seen blocking on") defaultsKey:@"seen_on_story_reply"],
												[RYGSetting menuCellWithTitle:RYGLocalized(@"Manual seen button mode") subtitle:RYGLocalized(@"Button = single-tap mark seen. Toggle = tap toggles story read receipts on/off (eye fills blue when on)") menu:[self menus][@"story_seen_mode"]],
												[RYGSetting menuCellWithTitle:RYGLocalized(@"Marked-seen indicator") subtitle:RYGLocalized(@"Remembers stories you marked as seen for 48 hours and hides or fills the eye button on them") menu:[self menus][@"story_seen_marked_indicator"]],
											]
										},
										@{
											@"header": RYGLocalized(@"Playback"),
											@"rows": @[
												[RYGSetting navigationCellWithTitle:RYGLocalized(@"Playback controls") subtitle:RYGLocalized(@"Speed, seek and pause controls") icon:nil navSections:@[@{
													@"footer": RYGLocalized(@"Enabled controls appear when you hold the ⋯ or speaker button on a story, or from Playback in the story menu."),
													@"rows": @[
														[RYGSetting switchCellWithTitle:RYGLocalized(@"Playback speed") subtitle:@"" defaultsKey:@"story_playback_speed" requiresRestart:YES],
														[RYGSetting switchCellWithTitle:RYGLocalized(@"Seek controls") subtitle:@"" defaultsKey:@"story_playback_seek"],
														[RYGSetting switchCellWithTitle:RYGLocalized(@"Pause control") subtitle:@"" defaultsKey:@"story_playback_pause"],
													]
												}]],
												[RYGSetting switchCellWithTitle:RYGLocalized(@"Stop story auto-advance") subtitle:RYGLocalized(@"Stories won't auto-skip to the next one when the timer ends. Tap to advance manually") defaultsKey:@"stop_story_auto_advance"],
												[RYGSetting switchCellWithTitle:RYGLocalized(@"Advance when marking as seen") subtitle:RYGLocalized(@"Tapping the eye button to mark a story as seen advances to the next story automatically") defaultsKey:@"advance_on_mark_seen"],
												[RYGSetting switchCellWithTitle:RYGLocalized(@"Advance on story like") subtitle:RYGLocalized(@"Liking a story automatically advances to the next one after a short delay") defaultsKey:@"advance_on_story_like"],
												[RYGSetting switchCellWithTitle:RYGLocalized(@"Advance on story reply") subtitle:RYGLocalized(@"Sending a reply or emoji reaction automatically advances to the next story") defaultsKey:@"advance_on_story_reply"],
											]
										},
										@{
											@"header": RYGLocalized(@"Story user list"),
											@"footer": RYGLocalized(@"Block all: all stories blocked — listed users are exceptions.\nBlock selected: only listed users are blocked — everything else is normal.\nBoth lists are saved independently."),
											@"rows": @[
												[RYGSetting switchCellWithTitle:RYGLocalized(@"Enable story user list") subtitle:RYGLocalized(@"Master toggle. When off, the list is ignored") defaultsKey:@"enable_story_user_exclusions"],
												[RYGSetting menuCellWithTitle:RYGLocalized(@"Blocking mode") subtitle:RYGLocalized(@"Which stories get seen-receipt blocking") menu:[self menus][@"story_blocking_mode"]],
												({
													RYGSetting *s = [RYGSetting buttonCellWithTitle:RYGLocalized(@"Manage list")
																	   subtitle:RYGLocalized(@"Search, sort, swipe to remove")
																		   icon:[RYGSymbol symbolWithIGName:@"ig_icon_edit_list_outline_24" fallback:@"list.bullet.rectangle"]
																		 action:^(void) {
														UIWindow *win = nil;
														for (UIWindow *w in [UIApplication sharedApplication].windows) {
															if (w.isKeyWindow) { win = w; break; }
														}
														UIViewController *top = win.rootViewController;
														while (top.presentedViewController) top = top.presentedViewController;
														if ([top isKindOfClass:[UINavigationController class]]) {
															[(UINavigationController *)top pushViewController:[RYGExcludedStoryUsersViewController new] animated:YES];
														} else if (top.navigationController) {
															[top.navigationController pushViewController:[RYGExcludedStoryUsersViewController new] animated:YES];
														}
													}];
													s.dynamicTitle = ^{ return [NSString stringWithFormat:RYGLocalized(@"Manage list (%lu)"), (unsigned long)[RYGExcludedStoryUsers count]]; };
													s;
												}),
											]
										},
										@{
											@"header": RYGLocalized(@"Viewers list"),
											@"footer": RYGLocalized(@"Replaces the 'who viewed my story' list with a searchable, filterable, sortable list. Long-press a viewer to pin them to the top. Switch back to the native list any time."),
											@"rows": @[
												[RYGSetting switchCellWithTitle:RYGLocalized(@"Filter, sort & pin viewers") subtitle:RYGLocalized(@"Turn on a custom viewer list to pin, search and sort viewers") defaultsKey:@"ryg_story_viewer_sort_enabled" requiresRestart:YES],
												[RYGSetting menuCellWithTitle:RYGLocalized(@"Default list") subtitle:RYGLocalized(@"Which list opens first. The header button still switches between them") menu:[self menus][@"story_viewer_default_list"]],
												({
													RYGSetting *s = [RYGSetting buttonCellWithTitle:RYGLocalized(@"Pinned viewers")
																		subtitle:RYGLocalized(@"Add by username, remove, reorder")
																			icon:[RYGSymbol symbolWithIGName:@"ig_icon_edit_list_outline_24" fallback:@"pin.fill"]
																		  action:^(void) {
														UIWindow *win = nil;
														for (UIWindow *w in [UIApplication sharedApplication].windows) {
															if (w.isKeyWindow) { win = w; break; }
														}
														UIViewController *top = win.rootViewController;
														while (top.presentedViewController) top = top.presentedViewController;
														if ([top isKindOfClass:[UINavigationController class]]) {
															[(UINavigationController *)top pushViewController:[RYGStoryViewerPinsViewController new] animated:YES];
														} else if (top.navigationController) {
															[top.navigationController pushViewController:[RYGStoryViewerPinsViewController new] animated:YES];
														}
													}];
													s.dynamicTitle = ^{ return [NSString stringWithFormat:RYGLocalized(@"Pinned viewers (%lu)"), (unsigned long)[RYGStoryViewerPins count]]; };
													s;
												}),
											]
										},
										@{
											@"header": RYGLocalized(@"Audio"),
											@"rows": @[
												[RYGSetting switchCellWithTitle:RYGLocalized(@"Story audio toggle") subtitle:RYGLocalized(@"Adds a speaker button to the story overlay to unmute/mute audio. Also available in the 3-dot menu") defaultsKey:@"story_audio_toggle" requiresRestart:YES],
											]
										},
										@{
											@"header": RYGLocalized(@"Stickers"),
											@"footer": RYGLocalized(@"Peek at poll/quiz/slider results before interacting — you can still tap to vote normally. Force legacy adds the Quiz and Reveal stickers back to the story composer."),
											@"rows": @[
												[RYGSetting switchCellWithTitle:RYGLocalized(@"Force legacy stickers in tray") subtitle:RYGLocalized(@"Adds Quiz and Reveal stickers back to the picker") defaultsKey:@"force_enable_quiz_sticker" requiresRestart:YES],
												[RYGSetting switchCellWithTitle:RYGLocalized(@"Bypass Reveal sticker") subtitle:RYGLocalized(@"Skip the DM-to-reveal step on stories with a Reveal sticker") defaultsKey:@"bypass_reveal_sticker"],
												[RYGSetting switchCellWithTitle:RYGLocalized(@"Show quiz answer") subtitle:RYGLocalized(@"Circle the correct option on quiz stickers, or the leading option on polls") defaultsKey:@"stories_show_quiz_answer"],
												[RYGSetting switchCellWithTitle:RYGLocalized(@"Show poll vote counts") subtitle:RYGLocalized(@"Show vote tallies on poll options and slider count/average before you vote") defaultsKey:@"stories_show_poll_votes_count"],
												[RYGSetting switchCellWithTitle:RYGLocalized(@"Custom sticker colors") subtitle:RYGLocalized(@"Long-press the color wheel in sticker editors to pick any solid or gradient color") defaultsKey:@"custom_music_sticker_color"],
												[RYGSetting switchCellWithTitle:RYGLocalized(@"Allow video in photo sticker") subtitle:RYGLocalized(@"Lets the photo sticker picker show videos too, not just photos") defaultsKey:@"photo_sticker_allow_video"],
												[RYGSetting switchCellWithTitle:RYGLocalized(@"Use detailed color picker") subtitle:RYGLocalized(@"Hold the eyedropper in stories to pick an exact text color") defaultsKey:@"detailed_color_picker"],
											]
										},
										@{
											@"header": RYGLocalized(@"Mentions"),
											@"rows": @[
												[RYGSetting switchCellWithTitle:RYGLocalized(@"View story mentions") subtitle:RYGLocalized(@"Adds a 'View mentions' entry to the action button menu and story 3-dot menu") defaultsKey:@"view_story_mentions"],
												[RYGSetting switchCellWithTitle:RYGLocalized(@"Mentions overlay button") subtitle:RYGLocalized(@"Adds a button next to the action/eye button on the story overlay. Only appears when the current story has mentions or shared posts/reels") defaultsKey:@"story_mentions_button" requiresRestart:YES],
												[RYGSetting switchCellWithTitle:RYGLocalized(@"Mentions count badge") subtitle:RYGLocalized(@"Shows the number of unique mentioned accounts as a red badge on the overlay button") defaultsKey:@"story_mentions_counter"]
											]
										}]
				];
}

@end
