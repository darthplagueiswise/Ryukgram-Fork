#import "RYGSettingsSections.h"

@implementation RYGTweakSettings (Section_ConfirmActions)

+ (RYGSetting *)confirmActionsNavCell {
	return [RYGSetting navigationCellWithTitle:RYGLocalized(@"Confirm actions")
										   subtitle:@""
											   icon:[RYGSymbol symbolWithIGName:@"circle_check" fallback:@"checkmark"]
										navSections:@[@{
											@"header": RYGLocalized(@"Likes"),
											@"rows": @[
												[RYGSetting switchCellWithTitle:RYGLocalized(@"Confirm like: Posts") subtitle:RYGLocalized(@"Shows an alert when you click the like button on posts to confirm the like") defaultsKey:@"like_confirm"],
												[RYGSetting switchCellWithTitle:RYGLocalized(@"Confirm like: Reels") subtitle:RYGLocalized(@"Confirms before a like lands on a reel") defaultsKey:@"like_confirm_reels"],
												[RYGSetting switchCellWithTitle:RYGLocalized(@"Confirm story like") subtitle:RYGLocalized(@"Shows an alert when you click the like button on stories to confirm the like") defaultsKey:@"story_like_confirm"],
												[RYGSetting switchCellWithTitle:RYGLocalized(@"Confirm note like") subtitle:RYGLocalized(@"Shows an alert when you click the like button on notes to confirm the like") defaultsKey:@"note_like_confirm"],
											]
										},
										@{
											@"header": RYGLocalized(@"Reactions"),
											@"rows": @[
												[RYGSetting switchCellWithTitle:RYGLocalized(@"Confirm story emoji reaction") subtitle:RYGLocalized(@"Shows an alert before sending an emoji reaction on a story") defaultsKey:@"emoji_reaction_confirm"],
												[RYGSetting switchCellWithTitle:RYGLocalized(@"Confirm note emoji reaction") subtitle:RYGLocalized(@"Shows an alert before sending an emoji reaction on a note") defaultsKey:@"note_react_confirm"],
												[RYGSetting menuCellWithTitle:RYGLocalized(@"Confirm DM reaction") subtitle:RYGLocalized(@"Shows an alert before sending a reaction in a chat") menu:[self menus][@"dm_reaction_confirm_mode"]],
											]
										},
										@{
											@"header": RYGLocalized(@"Stories & highlights"),
											@"rows": @[
												[RYGSetting menuCellWithTitle:RYGLocalized(@"Confirm sticker interaction (stories)") subtitle:RYGLocalized(@"Shows an alert when you tap a sticker on someone's story") menu:[self menus][@"sticker_interact_stories_mode"]],
												[RYGSetting menuCellWithTitle:RYGLocalized(@"Confirm sticker interaction (highlights)") subtitle:RYGLocalized(@"Shows an alert when you tap a sticker inside a highlight") menu:[self menus][@"sticker_interact_highlights_mode"]],
											]
										},
										@{
											@"header": RYGLocalized(@"Follows"),
											@"rows": @[
												[RYGSetting switchCellWithTitle:RYGLocalized(@"Confirm follow") subtitle:RYGLocalized(@"Confirms before the follow button follows someone") defaultsKey:@"follow_confirm"],
												[RYGSetting switchCellWithTitle:RYGLocalized(@"Confirm unfollow") subtitle:RYGLocalized(@"Shows an alert when you click the unfollow button to confirm") defaultsKey:@"unfollow_confirm"],
												[RYGSetting switchCellWithTitle:RYGLocalized(@"Confirm follow requests") subtitle:RYGLocalized(@"Confirms before you accept or decline a follow request") defaultsKey:@"follow_request_confirm"],
											]
										},
										@{
											@"header": RYGLocalized(@"Calls"),
											@"rows": @[
												[RYGSetting switchCellWithTitle:RYGLocalized(@"Confirm voice call") subtitle:RYGLocalized(@"Shows an alert when you click the voice call button to confirm before calling") defaultsKey:@"voice_call_confirm"],
												[RYGSetting switchCellWithTitle:RYGLocalized(@"Confirm video call") subtitle:RYGLocalized(@"Shows an alert when you click the video call button to confirm before calling") defaultsKey:@"video_call_confirm"],
											]
										},
										@{
											@"header": RYGLocalized(@"Read receipts"),
											@"rows": @[
												[RYGSetting switchCellWithTitle:RYGLocalized(@"Confirm DM mark as seen") subtitle:RYGLocalized(@"Shows an alert before sending a read receipt from the DM seen button or menu") defaultsKey:@"confirm_mark_seen_dm"],
												[RYGSetting switchCellWithTitle:RYGLocalized(@"Confirm story mark as seen") subtitle:RYGLocalized(@"Shows an alert before sending a story view receipt from the eye button or menu") defaultsKey:@"confirm_mark_seen_story"],
												[RYGSetting switchCellWithTitle:RYGLocalized(@"Confirm disappearing media mark as viewed") subtitle:RYGLocalized(@"Shows an alert before marking a disappearing message as viewed") defaultsKey:@"confirm_mark_seen_dm_visual"],
											]
										},
										@{
											@"header": RYGLocalized(@"Messaging"),
											@"rows": @[
												[RYGSetting switchCellWithTitle:RYGLocalized(@"Confirm voice messages") subtitle:RYGLocalized(@"Asks you to confirm before a voice message sends") defaultsKey:@"voice_message_confirm"],
												[RYGSetting switchCellWithTitle:RYGLocalized(@"Confirm send to group chat") subtitle:RYGLocalized(@"Shows an alert before creating/sending to a group chat from the share sheet") defaultsKey:@"confirm_send_to_group"],
												[RYGSetting switchCellWithTitle:RYGLocalized(@"Confirm changing theme") subtitle:RYGLocalized(@"Confirms before a chat theme change applies") defaultsKey:@"change_direct_theme_confirm"],
												[RYGSetting switchCellWithTitle:RYGLocalized(@"Confirm vanish mode") subtitle:RYGLocalized(@"Shows an alert to confirm before toggling vanish mode") defaultsKey:@"shh_mode_confirm"],
											]
										},
										@{
											@"header": RYGLocalized(@"Comments & posts"),
											@"rows": @[
												[RYGSetting switchCellWithTitle:RYGLocalized(@"Confirm posting comment") subtitle:RYGLocalized(@"Confirms before a comment posts") defaultsKey:@"post_comment_confirm"],
												[RYGSetting switchCellWithTitle:RYGLocalized(@"Confirm repost") subtitle:RYGLocalized(@"Shows an alert when you click the repost button to confirm before reposting") defaultsKey:@"repost_confirm"],
											]
										}]
				];
}

@end
