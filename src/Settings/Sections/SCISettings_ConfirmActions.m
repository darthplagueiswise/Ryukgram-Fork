#import "SCISettingsSections.h"

@implementation SCITweakSettings (Section_ConfirmActions)

+ (SCISetting *)confirmActionsNavCell {
	return [SCISetting navigationCellWithTitle:SCILocalized(@"Confirm actions")
										   subtitle:@""
											   icon:[SCISymbol symbolWithIGName:@"circle_check" fallback:@"checkmark"]
										navSections:@[@{
											@"header": SCILocalized(@"Likes"),
											@"rows": @[
												[SCISetting switchCellWithTitle:SCILocalized(@"Confirm like: Posts") subtitle:SCILocalized(@"Shows an alert when you click the like button on posts to confirm the like") defaultsKey:@"like_confirm"],
												[SCISetting switchCellWithTitle:SCILocalized(@"Confirm like: Reels") subtitle:SCILocalized(@"Shows an alert when you click the like button on reels to confirm the like") defaultsKey:@"like_confirm_reels"],
												[SCISetting switchCellWithTitle:SCILocalized(@"Confirm story like") subtitle:SCILocalized(@"Shows an alert when you click the like button on stories to confirm the like") defaultsKey:@"story_like_confirm"],
												[SCISetting switchCellWithTitle:SCILocalized(@"Confirm note like") subtitle:SCILocalized(@"Shows an alert when you click the like button on notes to confirm the like") defaultsKey:@"note_like_confirm"],
											]
										},
										@{
											@"header": SCILocalized(@"Reactions"),
											@"rows": @[
												[SCISetting switchCellWithTitle:SCILocalized(@"Confirm story emoji reaction") subtitle:SCILocalized(@"Shows an alert before sending an emoji reaction on a story") defaultsKey:@"emoji_reaction_confirm"],
												[SCISetting switchCellWithTitle:SCILocalized(@"Confirm note emoji reaction") subtitle:SCILocalized(@"Shows an alert before sending an emoji reaction on a note") defaultsKey:@"note_react_confirm"],
												[SCISetting switchCellWithTitle:SCILocalized(@"Confirm Instants emoji reaction") subtitle:SCILocalized(@"Shows an alert before sending an emoji reaction on an Instant") defaultsKey:@"instants_emoji_reaction_confirm"],
											]
										},
										@{
											@"header": SCILocalized(@"Stories & highlights"),
											@"rows": @[
												[SCISetting menuCellWithTitle:SCILocalized(@"Confirm sticker interaction (stories)") subtitle:SCILocalized(@"Shows an alert when you tap a sticker on someone's story") menu:[self menus][@"sticker_interact_stories_mode"]],
												[SCISetting menuCellWithTitle:SCILocalized(@"Confirm sticker interaction (highlights)") subtitle:SCILocalized(@"Shows an alert when you tap a sticker inside a highlight") menu:[self menus][@"sticker_interact_highlights_mode"]],
											]
										},
										@{
											@"header": SCILocalized(@"Instants"),
											@"rows": @[
												[SCISetting switchCellWithTitle:SCILocalized(@"Confirm Instants capture") subtitle:SCILocalized(@"Shows an alert before taking a photo with the Instants camera") defaultsKey:@"instants_capture_confirm"],
												[SCISetting switchCellWithTitle:SCILocalized(@"Confirm switching Instant") subtitle:SCILocalized(@"Shows an alert before tapping to switch to the next/previous Instant") defaultsKey:@"instants_advance_confirm"],
											]
										},
										@{
											@"header": SCILocalized(@"Follows"),
											@"rows": @[
												[SCISetting switchCellWithTitle:SCILocalized(@"Confirm follow") subtitle:SCILocalized(@"Shows an alert when you click the follow button to confirm the follow") defaultsKey:@"follow_confirm"],
												[SCISetting switchCellWithTitle:SCILocalized(@"Confirm unfollow") subtitle:SCILocalized(@"Shows an alert when you click the unfollow button to confirm") defaultsKey:@"unfollow_confirm"],
												[SCISetting switchCellWithTitle:SCILocalized(@"Confirm follow requests") subtitle:SCILocalized(@"Shows an alert when you accept/decline a follow request") defaultsKey:@"follow_request_confirm"],
											]
										},
										@{
											@"header": SCILocalized(@"Calls"),
											@"rows": @[
												[SCISetting switchCellWithTitle:SCILocalized(@"Confirm voice call") subtitle:SCILocalized(@"Shows an alert when you click the voice call button to confirm before calling") defaultsKey:@"voice_call_confirm"],
												[SCISetting switchCellWithTitle:SCILocalized(@"Confirm video call") subtitle:SCILocalized(@"Shows an alert when you click the video call button to confirm before calling") defaultsKey:@"video_call_confirm"],
											]
										},
										@{
											@"header": SCILocalized(@"Messaging"),
											@"rows": @[
												[SCISetting switchCellWithTitle:SCILocalized(@"Confirm voice messages") subtitle:SCILocalized(@"Shows an alert to confirm before sending a voice message") defaultsKey:@"voice_message_confirm"],
												[SCISetting switchCellWithTitle:SCILocalized(@"Confirm send to group chat") subtitle:SCILocalized(@"Shows an alert before creating/sending to a group chat from the share sheet") defaultsKey:@"confirm_send_to_group"],
												[SCISetting switchCellWithTitle:SCILocalized(@"Confirm changing theme") subtitle:SCILocalized(@"Shows an alert when you change a chat theme to confirm") defaultsKey:@"change_direct_theme_confirm"],
												[SCISetting switchCellWithTitle:SCILocalized(@"Confirm vanish mode") subtitle:SCILocalized(@"Shows an alert to confirm before toggling vanish mode") defaultsKey:@"shh_mode_confirm"],
											]
										},
										@{
											@"header": SCILocalized(@"Comments & posts"),
											@"rows": @[
												[SCISetting switchCellWithTitle:SCILocalized(@"Confirm posting comment") subtitle:SCILocalized(@"Shows an alert when you click the post comment button to confirm") defaultsKey:@"post_comment_confirm"],
												[SCISetting switchCellWithTitle:SCILocalized(@"Confirm repost") subtitle:SCILocalized(@"Shows an alert when you click the repost button to confirm before reposting") defaultsKey:@"repost_confirm"],
											]
										}]
				];
}

@end
