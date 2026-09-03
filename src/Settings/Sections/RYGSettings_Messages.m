#import "RYGSettingsSections.h"
#import "../RYGOverlayLayoutEditorViewController.h"
#import "../../Features/StoriesAndMessages/RYGDMButtonLayout.h"
#import "../../Features/DeletedMessages/RYGDeletedMessagesCapture.h"
#import "../../Features/DeletedMessages/RYGNSEImport.h"
#import "../../Features/ReadReceipts/RYGReadReceiptLogViewController.h"
#import "../../Features/Activity/RYGActivityMatrixViewController.h"
#import "../../UI/RYGPopupChrome.h"
#import "../../Features/CallRecordings/RYGCallRecordingsViewController.h"
#import "../../Features/CallRecordings/RYGCallPipLayoutViewController.h"
#import "../../Features/CallRecordings/RYGCallRecordingStorage.h"
#import "../../Features/CallRecordings/RYGCallRecordingGallery.h"
#import "../../Features/CallRecordings/RYGCallIgnoreListViewController.h"
#import "../../UI/RYGFeatureIcons.h"

// Mutually exclusive auto-clean mode switch: on -> this mode, off -> "off".
static RYGSetting *rygNSEModeSwitch(NSString *title, NSString *subtitle, NSString *mode) {
	return [RYGSetting switchCellWithTitle:title subtitle:subtitle
		value:^BOOL{ return [[RYGUtils getStringPref:@"nse_cleanup_mode"] isEqualToString:mode]; }
		action:^(BOOL on) {
			[NSUserDefaults.standardUserDefaults setValue:(on ? mode : @"off") forKey:@"nse_cleanup_mode"];
			[NSNotificationCenter.defaultCenter postNotificationName:@"RYGSettingsShouldReload" object:nil];
		}];
}

// Tap-to-type numeric cell: shows "<value> <unit>" and prompts for a free number.
static RYGSetting *rygNSENumberCell(NSString *title, NSString *subtitle, NSString *key, NSString *unit, NSString *placeholder, BOOL (^disabled)(void)) {
	RYGSetting *cell = [RYGSetting buttonCellWithTitle:title subtitle:subtitle icon:nil action:^{
		double cur = [RYGUtils getDoublePref:key];
		UIAlertController *a = [UIAlertController alertControllerWithTitle:title message:nil preferredStyle:UIAlertControllerStyleAlert];
		[a addTextFieldWithConfigurationHandler:^(UITextField *tf) {
			tf.keyboardType = UIKeyboardTypeNumberPad;
			tf.placeholder = placeholder;
			tf.text = cur > 0 ? [NSString stringWithFormat:@"%g", cur] : @"";
		}];
		[a addAction:[UIAlertAction actionWithTitle:RYGLocalized(@"Cancel") style:UIAlertActionStyleCancel handler:nil]];
		[a addAction:[UIAlertAction actionWithTitle:RYGLocalized(@"Save") style:UIAlertActionStyleDefault handler:^(__unused UIAlertAction *act) {
			double v = [a.textFields.firstObject.text doubleValue];
			if (v > 0) [NSUserDefaults.standardUserDefaults setDouble:v forKey:key];
			[NSNotificationCenter.defaultCenter postNotificationName:@"RYGSettingsShouldReload" object:nil];
		}]];
		[rygTopVC() presentViewController:a animated:YES completion:nil];
	}];
	cell.defaultsKey = key;
	cell.disabledProvider = disabled;
	cell.dynamicValueText = ^NSString *{ return [NSString stringWithFormat:@"%g %@", [RYGUtils getDoublePref:key], unit]; };
	return cell;
}

// Shows the current staging-cache size and clears it (staged, not-yet-unsent only).
static RYGSetting *rygNSEClearCacheCell(void) {
	RYGSetting *cell = [RYGSetting buttonCellWithTitle:RYGLocalized(@"Clear cache now") subtitle:RYGLocalized(@"Delete staged captures that haven't been unsent yet") icon:nil action:^{
		UIAlertController *a = [UIAlertController alertControllerWithTitle:RYGLocalized(@"Clear view-once cache")
			message:RYGLocalized(@"Delete all staged captures that haven't been unsent? Anything already saved to the log is kept.")
			preferredStyle:UIAlertControllerStyleAlert];
		[a addAction:[UIAlertAction actionWithTitle:RYGLocalized(@"Cancel") style:UIAlertActionStyleCancel handler:nil]];
		[a addAction:[UIAlertAction actionWithTitle:RYGLocalized(@"Clear") style:UIAlertActionStyleDestructive handler:^(__unused UIAlertAction *x) {
			[RYGNSEImport clearAllStaging];
			[NSNotificationCenter.defaultCenter postNotificationName:@"RYGSettingsShouldReload" object:nil];
		}]];
		[rygTopVC() presentViewController:a animated:YES completion:nil];
	}];
	cell.dynamicValueText = ^NSString *{ return [NSByteCountFormatter stringFromByteCount:(long long)[RYGNSEImport stagingCacheSize] countStyle:NSByteCountFormatterCountStyleFile]; };
	return cell;
}

@implementation RYGTweakSettings (Section_Messages)

+ (RYGSetting *)messagesNavCell {
	return [RYGSetting navigationCellWithTitle:RYGLocalized(@"Messages")
										   subtitle:@""
											   icon:[RYGSymbol symbolWithIGName:@"messages" fallback:@"bubble.left.and.bubble.right"]
										navSections:@[@{
											@"header": RYGLocalized(@"Threads"),
											@"rows": @[
												[RYGSetting navigationCellWithTitle:RYGLocalized(@"Read receipts")
																		   subtitle:RYGLocalized(@"Control when messages are marked as seen")
																			   icon:nil
																		navSections:@[@{
																			@"header": @"",
																			@"rows": @[
																				[RYGSetting switchCellWithTitle:RYGLocalized(@"Manually mark messages as seen") subtitle:RYGLocalized(@"Blocks the auto read receipt — mark seen happens only when you choose") defaultsKey:@"remove_lastseen"],
																				[RYGSetting switchCellWithTitle:RYGLocalized(@"Mark seen locally") subtitle:RYGLocalized(@"Opened chats look read on this device only. The eye button turns orange while the sender still has no read receipt") defaultsKey:@"dm_local_seen"],
																				[RYGSetting switchCellWithTitle:RYGLocalized(@"Show seen button") subtitle:RYGLocalized(@"Adds the eye button to DM threads. Off keeps receipt blocking on without the button") defaultsKey:@"show_dm_seen_button" requiresRestart:YES],
																				[RYGSetting menuCellWithTitle:RYGLocalized(@"Read receipt mode") subtitle:RYGLocalized(@"How the seen button behaves") menu:[self menus][@"seen_mode"]],
																				[RYGSetting switchCellWithTitle:RYGLocalized(@"Auto mark seen on interact") subtitle:RYGLocalized(@"Marks messages as seen when you reply, react or send media") defaultsKey:@"seen_auto_on_interact"],
																				[RYGSetting switchCellWithTitle:RYGLocalized(@"Auto mark seen on typing") subtitle:RYGLocalized(@"Marks messages as seen when you start typing") defaultsKey:@"seen_auto_on_typing"],
																			]
																		}]
												],
												[RYGSetting navigationCellWithTitle:RYGLocalized(@"Keep deleted messages")
																		   subtitle:RYGLocalized(@"Preserves messages that others unsend")
																			   icon:nil
																		navSections:@[@{
																			@"header": @"",
																			@"footer": RYGLocalized(@"⚠️ Pull-to-refresh in the DMs tab clears all preserved messages. Enable the warning below to get a confirmation dialog."),
																			@"rows": @[
																				[RYGSetting switchCellWithTitle:RYGLocalized(@"Keep deleted messages") subtitle:RYGLocalized(@"Preserves messages that others unsend") defaultsKey:@"keep_deleted_message"],
																					[RYGSetting switchCellWithTitle:RYGLocalized(@"Keep my deleted messages") subtitle:RYGLocalized(@"Also preserves messages you unsend yourself") defaultsKey:@"keep_my_deleted_messages"],
																					[self unsentIndicatorNavCell],
																				[RYGSetting switchCellWithTitle:RYGLocalized(@"Unsent message notification") subtitle:RYGLocalized(@"Shows a notification pill when a message is unsent") defaultsKey:@"unsent_message_toast"],
																				[RYGSetting switchCellWithTitle:RYGLocalized(@"Warn before clearing on refresh") subtitle:RYGLocalized(@"Confirmation dialog before clearing preserved messages") defaultsKey:@"warn_refresh_clears_preserved"],
																				[RYGSetting switchCellWithTitle:RYGLocalized(@"Keep running in background")
																										subtitle:RYGLocalized(@"Catch view-once media unsent while you're away. ⚠️ May drain battery")
																										value:^BOOL{ return [RYGUtils getBoolPref:@"deleted_messages_keepalive"]; }
																										action:^(BOOL on) {
																										if (!on) {
																											[NSUserDefaults.standardUserDefaults setBool:NO forKey:@"deleted_messages_keepalive"];
																											rygDMUpdateKeepAlive();
																											return;
																										}
																										UIAlertController *a = [UIAlertController alertControllerWithTitle:RYGLocalized(@"Keep Instagram active in background")
																											message:RYGLocalized(@"Forces Instagram to keep running in the background so it can capture disappearing media that someone unsends while you're not in the app.\n\nMainly useful for view-once media — normal photos/videos are usually still recoverable without it. ⚠️ May significantly drain your battery, and can't capture anything if you force-quit Instagram from the app switcher.\n\nEnable it?")
																											preferredStyle:UIAlertControllerStyleAlert];
																										[a addAction:[UIAlertAction actionWithTitle:RYGLocalized(@"Cancel") style:UIAlertActionStyleCancel handler:^(UIAlertAction *_) {
																											[NSUserDefaults.standardUserDefaults setBool:NO forKey:@"deleted_messages_keepalive"];
																											[NSNotificationCenter.defaultCenter postNotificationName:@"RYGSettingsShouldReload" object:nil];
																										}]];
																										[a addAction:[UIAlertAction actionWithTitle:RYGLocalized(@"Enable") style:UIAlertActionStyleDestructive handler:^(UIAlertAction *_) {
																											[NSUserDefaults.standardUserDefaults setBool:YES forKey:@"deleted_messages_keepalive"];
																											rygDMUpdateKeepAlive();
																										}]];
																										[rygTopVC() presentViewController:a animated:YES completion:nil];
																				}],
																			]
																		}]
												],
												[RYGSetting navigationCellWithTitle:RYGLocalized(@"Deleted messages log")
																		   subtitle:RYGLocalized(@"Records every message someone unsends, grouped by chat")
																			   icon:nil
																		navSections:@[@{
																			@"header": @"",
																			@"footer": RYGLocalized(@"When enabled, deleted messages and their media are saved on this device. Toggle off and clear the log to wipe history."),
																			@"rows": @[
																				[RYGSetting switchCellWithTitle:RYGLocalized(@"Enable deleted messages log") subtitle:RYGLocalized(@"Captures unsent messages with their text or media") defaultsKey:@"deleted_messages_log_enabled"],
																				[RYGSetting switchCellWithTitle:RYGLocalized(@"Log removed reactions") subtitle:RYGLocalized(@"Also records when someone removes a reaction, and which message it was on") defaultsKey:@"deleted_messages_log_reactions"],
																				[RYGSetting navigationCellWithTitle:RYGLocalized(@"Capture while closed")
																								subtitle:RYGLocalized(@"Save media that arrives while Instagram is closed")
																								icon:nil
																								navSections:@[@{
																									@"header": @"",
																									@"footer": RYGLocalized(@"⚠️ Only works on a plugins IPA signed with a paid, ad-hoc certificate under the default Instagram bundle id, not the no-plugins build. Requires the deleted messages log to stay on.\n\nCatches view-once media (and normal media if enabled) that arrives while Instagram is fully closed, using the notification extension. Affects only this log and its media, nothing else in the app. It rides push notifications, so muted chats, Do Not Disturb or disabled notifications miss messages; \"Keep running in background\" is the fallback."),
																									@"rows": @[
																										[RYGSetting switchCellWithTitle:RYGLocalized(@"Capture while closed") subtitle:RYGLocalized(@"Uses the notification extension to save media that arrives with the app closed") defaultsKey:@"nse_viewonce_enabled"],
																										[RYGSetting switchCellWithTitle:RYGLocalized(@"Also capture normal media") subtitle:RYGLocalized(@"Not just view-once. Uses a lot more storage") defaultsKey:@"nse_capture_normal_media"],
																										[RYGSetting navigationCellWithTitle:RYGLocalized(@"Auto-clean")
																														subtitle:RYGLocalized(@"Limit how much captured media is kept")
																														icon:nil
																														navSections:@[
																															@{
																																@"header": @"",
																																@"footer": RYGLocalized(@"With both off, captures are kept until they're unsent. Turning one on turns the other off. Anything actually unsent is saved to the log first and is never cleaned here."),
																																@"rows": @[
																																	rygNSEModeSwitch(RYGLocalized(@"Clear when I open Instagram"), RYGLocalized(@"Drop every capture each time you open the app"), @"on_open"),
																																	rygNSEModeSwitch(RYGLocalized(@"Keep within size / age limits"), RYGLocalized(@"Trim each account by size and age"), @"limits"),
																																]
																															},
																															@{
																																@"header": @"",
																																@"footer": RYGLocalized(@"Kept per account. A capture is dropped once it passes either limit."),
																																@"rows": @[
																																	rygNSENumberCell(RYGLocalized(@"Size limit"), RYGLocalized(@"Keep at most this per account"), @"nse_cleanup_size_mb", RYGLocalized(@"MB"), @"e.g. 200", ^BOOL{ return ![[RYGUtils getStringPref:@"nse_cleanup_mode"] isEqualToString:@"limits"]; }),
																																	rygNSENumberCell(RYGLocalized(@"Age limit"), RYGLocalized(@"Keep no longer than this"), @"nse_cleanup_age_days", RYGLocalized(@"days"), @"e.g. 30", ^BOOL{ return ![[RYGUtils getStringPref:@"nse_cleanup_mode"] isEqualToString:@"limits"]; }),
																																]
																															},
																															@{
																																@"header": @"",
																																@"rows": @[ rygNSEClearCacheCell() ]
																															}
										]
																										],
																									]
																								}]
																				],
																				[RYGSetting buttonCellWithTitle:RYGLocalized(@"Open log")
																								subtitle:RYGLocalized(@"Browse, filter and search recorded messages")
																									icon:[RYGFeatureIcons deletedMessages]
																									action:^(void) {
																				[RYGDeletedMessagesViewController presentFromViewController:nil];
																			}],
																			]
																		}]
											],
													[RYGSetting switchCellWithTitle:RYGLocalized(@"Disable typing status") subtitle:RYGLocalized(@"Hides typing indicator from others") defaultsKey:@"disable_typing_status"],
												[RYGSetting switchCellWithTitle:RYGLocalized(@"Disable vanish mode swipe") subtitle:RYGLocalized(@"Prevents accidental swipe-up activation of vanish mode") defaultsKey:@"disable_disappearing_mode_swipe"],
												[RYGSetting switchCellWithTitle:RYGLocalized(@"Hide voice call button") subtitle:RYGLocalized(@"Removes the audio call button from DM thread header") defaultsKey:@"hide_voice_call_button" requiresRestart:YES],
												[RYGSetting switchCellWithTitle:RYGLocalized(@"Hide video call button") subtitle:RYGLocalized(@"Removes the video call button from DM thread header") defaultsKey:@"hide_video_call_button" requiresRestart:YES],
												[RYGSetting switchCellWithTitle:RYGLocalized(@"Silence incoming calls") subtitle:RYGLocalized(@"Incoming calls stay silent — no ring, no screen, no notification") defaultsKey:@"ryg_silence_calls" requiresRestart:YES],
												[RYGSetting switchCellWithTitle:RYGLocalized(@"Hide reels blend button") subtitle:RYGLocalized(@"Hides the blend button in DMs") defaultsKey:@"hide_reels_blend"],
												[RYGSetting switchCellWithTitle:RYGLocalized(@"Hide send to group chat") subtitle:RYGLocalized(@"Removes the create/send to group chat row when sharing to multiple recipients") defaultsKey:@"hide_send_to_group"],
												[RYGSetting switchCellWithTitle:RYGLocalized(@"Bypass DM character limit") subtitle:RYGLocalized(@"Allows typing and sending DMs longer than Instagram's limit") defaultsKey:@"bypass_dm_char_limit"],
											]
										},
										@{
											@"header": RYGLocalized(@"Calls"),
											@"footer": RYGLocalized(@"Recorded calls are saved on this device only. A red status-bar indicator shows while recording."),
											@"rows": @[
												({
	RYGSetting *(^openRecordings)(void) = ^RYGSetting *{
		RYGSetting *s = [RYGSetting buttonCellWithTitle:RYGLocalized(@"Open recordings")
											   subtitle:RYGLocalized(@"Browse saved calls, grouped by person")
												   icon:[RYGFeatureIcons callRecordings]
												 action:^(void) { [RYGCallRecordingsViewController presentFromViewController:nil]; }];
		s.badgeCount = ^NSInteger{ return (NSInteger)[RYGCallRecordingStorage unreadCountForOwnerPK:[RYGUtils currentUserPK]]; };
		return s;
	};
	RYGSetting *callRecording = [RYGSetting navigationCellWithTitle:RYGLocalized(@"Call recording")
															   subtitle:RYGLocalized(@"Record voice and video calls, browse them later")
																   icon:nil
																navSections:@[@{
																	@"header": @"",
																	@"footer": RYGLocalized(@"Records the other party (call audio) and your microphone. A red status-bar indicator shows while recording. Recordings are saved on this device only."),
																	@"rows": @[
																		[RYGSetting switchCellWithTitle:RYGLocalized(@"Enable call recording") subtitle:RYGLocalized(@"Adds a record button to the call screen") defaultsKey:@"call_recordings_enabled" requiresRestart:YES],
																		[RYGSetting switchCellWithTitle:RYGLocalized(@"Auto-record calls") subtitle:RYGLocalized(@"Starts recording automatically when a call opens") defaultsKey:@"call_recordings_auto"],
																		({ RYGSetting *s = [RYGSetting navigationCellWithTitle:RYGLocalized(@"Auto-record ignore list") subtitle:RYGLocalized(@"Chats excluded from auto-record — long-press the record button in a call to add") icon:nil viewController:[RYGCallIgnoreListViewController new]];
																		   s.whatsNewID = @"ui_callignore"; s; }),
																		[RYGSetting menuCellWithTitle:RYGLocalized(@"Record audio from") subtitle:RYGLocalized(@"Which side's voice to capture") menu:[self menus][@"call_audio_source"]],
																		[RYGSetting switchCellWithTitle:RYGLocalized(@"Record video on video calls") subtitle:RYGLocalized(@"Off records audio only, even on video calls") defaultsKey:@"call_recordings_video"],
																		[RYGSetting navigationCellWithTitle:RYGLocalized(@"Include my camera")
																				   subtitle:RYGLocalized(@"Overlay your camera as a small window on video-call recordings")
																					   icon:nil
																				navSections:@[@{
																					@"header": @"",
																					@"footer": RYGLocalized(@"Your camera is captured and overlaid onto the recording. Choose which side fills the screen, the overlay size, and drag it to any corner."),
																					@"rows": @[
																						[RYGSetting switchCellWithTitle:RYGLocalized(@"Include my camera") subtitle:RYGLocalized(@"Overlay your camera on the recording") defaultsKey:@"call_recordings_self_cam"],
																						[RYGSetting menuCellWithTitle:RYGLocalized(@"Full screen") subtitle:RYGLocalized(@"Which camera fills the frame") menu:[self menus][@"call_pip_full"]],
																						[RYGSetting menuCellWithTitle:RYGLocalized(@"My camera size") subtitle:RYGLocalized(@"Size of the overlay window") menu:[self menus][@"call_pip_size"]],
																						({ RYGSetting *s = [RYGSetting navigationCellWithTitle:RYGLocalized(@"Camera position") subtitle:RYGLocalized(@"Drag the overlay where you want it") icon:[RYGSymbol symbolWithIGName:@"reposition" fallback:@"hand.draw"] viewController:[RYGCallPipLayoutViewController new]];
																						   s.whatsNewID = @"ui_callpip"; s; }),
																					]
																				}]],
																		({ RYGSetting *s = [RYGSetting switchCellWithTitle:RYGLocalized(@"Sync to gallery") subtitle:RYGLocalized(@"Also show recordings in the RyukGram gallery under Calls") value:^BOOL{ return [RYGUtils getBoolPref:@"call_recordings_sync_gallery"]; }
																					 action:^(BOOL on) {
																				[RYGUtils setPref:@(on) forKey:@"call_recordings_sync_gallery"];
																				[RYGCallRecordingGallery syncAllForOwnerPK:[RYGUtils currentUserPK]];   // reconcile: on adds refs, off removes
																			}];
																		   s.whatsNewID = @"call_recordings_sync_gallery"; s; }),
																		[RYGSetting menuCellWithTitle:RYGLocalized(@"Auto-delete old recordings") subtitle:RYGLocalized(@"Remove recordings older than the chosen age") menu:[self menus][@"call_retention"]],
																		openRecordings(),
																	]
																}]];
	callRecording;
}),
												[RYGSetting switchCellWithTitle:RYGLocalized(@"Block mute signal") subtitle:RYGLocalized(@"Mute without the other side seeing you muted — your mic is still silenced") defaultsKey:@"call_recordings_ghost_mute"],
											]
										},
										@{
											@"header": RYGLocalized(@"Share sheet"),
											@"footer": RYGLocalized(@"Long-press a recipient to pin or unpin. Pinned recipients render at the top."),
											@"rows": @[
												[RYGSetting switchCellWithTitle:RYGLocalized(@"Pin recipients on long-press") subtitle:RYGLocalized(@"Long-press in the share sheet to pin a chat/user to the top") defaultsKey:@"share_sheet_pin_threads"],
											]
										},
										@{
											@"header": RYGLocalized(@"Chat list"),
											@"footer": RYGLocalized(@"Block all: all chats blocked — listed chats are exceptions.\nBlock selected: only listed chats are blocked — everything else is normal.\nBoth lists are saved independently. Long-press a chat in the inbox to add or remove."),
											@"rows": @[
												[RYGSetting switchCellWithTitle:RYGLocalized(@"Enable chat list") subtitle:RYGLocalized(@"Master toggle. When off, the list is ignored") defaultsKey:@"enable_chat_exclusions"],
												[RYGSetting menuCellWithTitle:RYGLocalized(@"Blocking mode") subtitle:RYGLocalized(@"Which chats get read-receipt blocking") menu:[self menus][@"chat_blocking_mode"]],
												({
	RYGSetting *s = [RYGSetting switchCellWithTitle:@"" subtitle:@"" defaultsKey:@"exclusions_default_keep_deleted"];
	s.dynamicTitle = ^{
		BOOL bs = [[RYGUtils getStringPref:@"chat_blocking_mode"] isEqualToString:@"block_selected"];
		return bs ? RYGLocalized(@"Block keep-deleted for unlisted chats")
				  : RYGLocalized(@"Block keep-deleted for excluded chats");
	};
	s.subtitle = RYGLocalized(@"Each chat can override this in the list");
	s;
}),
												[RYGSetting switchCellWithTitle:RYGLocalized(@"Quick list button in chats") subtitle:RYGLocalized(@"Shows a button in DM threads to add/remove chats from the list. Long-press for more options") defaultsKey:@"chat_quick_list_button"],
												({
													RYGSetting *s = [RYGSetting buttonCellWithTitle:RYGLocalized(@"Manage list")
																	   subtitle:RYGLocalized(@"Search, sort, swipe to remove or toggle keep-deleted")
																		   icon:[RYGSymbol symbolWithIGName:@"ig_icon_edit_list_outline_24" fallback:@"list.bullet.rectangle"]
																		 action:^(void) {
														UIWindow *win = nil;
														for (UIWindow *w in [UIApplication sharedApplication].windows) {
															if (w.isKeyWindow) { win = w; break; }
														}
														UIViewController *top = win.rootViewController;
														while (top.presentedViewController) top = top.presentedViewController;
														if ([top isKindOfClass:[UINavigationController class]]) {
															[(UINavigationController *)top pushViewController:[RYGExcludedChatsViewController new] animated:YES];
														} else if (top.navigationController) {
															[top.navigationController pushViewController:[RYGExcludedChatsViewController new] animated:YES];
														}
													}];
													s.dynamicTitle = ^{ return [NSString stringWithFormat:RYGLocalized(@"Manage list (%lu)"), (unsigned long)[RYGExcludedThreads count]]; };
													s;
												}),
											]
										},
										@{
											@"header": RYGLocalized(@"Activity"),
											@"rows": @[
												[RYGSetting switchCellWithTitle:RYGLocalized(@"Activity status toggle") subtitle:RYGLocalized(@"Adds a dot to the inbox header. Tap it to turn your activity status on or off") defaultsKey:@"activity_toggle_enabled" requiresRestart:YES],
												[RYGSetting navigationCellWithTitle:RYGLocalized(@"Activity notifications")
																		   subtitle:RYGLocalized(@"Online, offline, typing and read receipts, per person")
																			   icon:nil
																		navSections:@[
																			@{
																				@"header": @"",
																				@"rows": @[
																					[RYGSetting switchCellWithTitle:RYGLocalized(@"Enable activity") subtitle:RYGLocalized(@"Track who reads your messages, comes online, goes offline or types") defaultsKey:@"activity_notif_enabled" requiresRestart:YES],
																				]
																			},
																			@{
																				@"header": RYGLocalized(@"For everyone"),
																				@"footer": RYGLocalized(@"Log only records silently. Notify only pings you without keeping it. Notify + log does both."),
																				@"rows": @[
																					[RYGSetting menuCellWithTitle:RYGLocalized(@"Read your message") subtitle:RYGLocalized(@"When someone opens a message you sent") menu:[self menus][@"activity_read_mode"]],
																					[RYGSetting menuCellWithTitle:RYGLocalized(@"Came online") subtitle:RYGLocalized(@"When someone becomes active") menu:[self menus][@"activity_online_mode"]],
																					[RYGSetting menuCellWithTitle:RYGLocalized(@"Went offline") subtitle:RYGLocalized(@"When someone goes inactive") menu:[self menus][@"activity_offline_mode"]],
																					[RYGSetting menuCellWithTitle:RYGLocalized(@"Started typing") subtitle:RYGLocalized(@"When someone starts typing to you") menu:[self menus][@"activity_typing_mode"]],
																				]
																			},
																			@{
																				@"header": RYGLocalized(@"Activity log"),
																				@"rows": @[
																																	[RYGSetting switchCellWithTitle:RYGLocalized(@"Log group chats") subtitle:RYGLocalized(@"Also track reads in group chats. Groups can be noisy") defaultsKey:@"read_receipts_log_groups"],
																					[RYGSetting buttonCellWithTitle:RYGLocalized(@"Open log")
																									   subtitle:RYGLocalized(@"Browse activity, grouped by person")
																										   icon:[RYGFeatureIcons readReceipts]
																										 action:^(void) { [RYGReadReceiptLogViewController presentFromViewController:nil]; }],
																					({ RYGSetting *s = [RYGSetting buttonCellWithTitle:RYGLocalized(@"Per-person notifications")
																									   subtitle:RYGLocalized(@"Pick what each person notifies you about")
																										   icon:[RYGSymbol symbolWithIGName:@"ig_icon_user_following_outline_24" fallback:@"person.crop.circle.badge.checkmark"]
																										 action:^(void) { [RYGPopupChrome presentVC:[RYGActivityMatrixViewController new] from:nil]; }];
																					   s.whatsNewID = @"ui_activitymatrix"; s; }),
																				]
																			}
																		]
												],
												[RYGSetting switchCellWithTitle:RYGLocalized(@"Accurate active status") subtitle:RYGLocalized(@"Refresh presence every 20s and drop Instagram's grace period, so the native green dot turns off the moment someone goes offline.") defaultsKey:@"activity_fast_presence" requiresRestart:YES],
											
												[RYGSetting switchCellWithTitle:RYGLocalized(@"Full last active date") subtitle:RYGLocalized(@"Show full date instead of \"Active 2h ago\"") defaultsKey:@"dm_full_last_active"],
											]
										},
										@{
											@"header": RYGLocalized(@"Files"),
											@"rows": @[
												[RYGSetting switchCellWithTitle:RYGLocalized(@"Send files (experimental)") subtitle:RYGLocalized(@"Adds a 'Send File' option to the plus menu in DMs. Supported file types may be limited by Instagram") defaultsKey:@"send_file"],
												({ RYGSetting *s = [RYGSetting switchCellWithTitle:RYGLocalized(@"Send image as drawing")
																		subtitle:RYGLocalized(@"In the Draw tool, send an image as your doodle, from the gallery, Photos, stickers or paste, with a built-in crop and background removal editor")
																		   value:^BOOL{ return [RYGUtils getBoolPref:@"ryg_doodle_image_enabled"]; }
																		  action:^(BOOL on) {
																			[NSUserDefaults.standardUserDefaults setBool:on forKey:@"ryg_doodle_image_enabled"];
																			if (!on) return;
																			UIAlertController *a = [UIAlertController alertControllerWithTitle:RYGLocalized(@"Send image as drawing")
																				message:RYGLocalized(@"Draw a line or shape, then tap Send and pick where to get the image from: gallery, Photos, stickers or paste.\n\nThe image takes the place of what you drew and matches its position and size, so draw bigger for a bigger image.\n\nRestart Instagram for it to take effect.")
																				preferredStyle:UIAlertControllerStyleAlert];
																			[a addAction:[UIAlertAction actionWithTitle:RYGLocalized(@"Restart") style:UIAlertActionStyleDefault handler:^(__unused UIAlertAction *_) { exit(0); }]];
																			[a addAction:[UIAlertAction actionWithTitle:RYGLocalized(@"Later") style:UIAlertActionStyleCancel handler:nil]];
																			[rygTopVC() presentViewController:a animated:YES completion:nil];
																		}];
											   s.whatsNewID = @"ryg_doodle_image_enabled"; s; }),
											]
										},
										@{
											@"header": RYGLocalized(@"Voice messages"),
											@"rows": @[
												[RYGSetting switchCellWithTitle:RYGLocalized(@"Send audio as file") subtitle:RYGLocalized(@"Adds an 'Audio File' option to the plus menu in DMs to send audio files as voice messages") defaultsKey:@"send_audio_as_file" requiresRestart:YES],
												[RYGSetting switchCellWithTitle:RYGLocalized(@"Download voice messages") subtitle:RYGLocalized(@"Adds a 'Download' option to the long-press menu on voice messages to save them as M4A audio") defaultsKey:@"download_audio_message"],
											]
										},
										@{
											@"header": RYGLocalized(@"Media"),
											@"rows": @[
												[RYGSetting switchCellWithTitle:RYGLocalized(@"Reroute native Save") subtitle:RYGLocalized(@"Make Instagram's built-in Save button on DM photos & videos download to Photos, the Gallery, or Share") defaultsKey:@"dm_native_save_enabled" requiresRestart:YES],
												({ RYGSetting *s = [RYGSetting navigationCellWithTitle:RYGLocalized(@"Configure menu")
																			subtitle:RYGLocalized(@"Reorder, enable/disable, set default tap")
																				icon:nil
																	  viewController:[[RYGActionMenuConfigViewController alloc] initForSource:RYGActionSourceDMNativeSave]];
												   s.whatsNewID = @"ui_cfg_actionmenu"; s; }),
											]
										},
										@{
											@"rows": @[
												({ RYGSetting *s = [RYGSetting navigationCellWithTitle:RYGLocalized(@"Custom chat background")
																		   subtitle:RYGLocalized(@"Use your own images as chat backgrounds")
																			   icon:[RYGFeatureIcons chatBackgrounds]
																	 viewController:[RYGChatBgSettingsVC new]];
												   s.whatsNewID = @"chat_bg_enabled"; s; }),
											]
										},
										@{
											@"header": RYGLocalized(@"Notes"),
											@"rows": @[
												[RYGSetting switchCellWithTitle:RYGLocalized(@"Hide notes tray") subtitle:RYGLocalized(@"Hides the notes tray in the DM inbox") defaultsKey:@"hide_notes_tray"],
												[RYGSetting switchCellWithTitle:RYGLocalized(@"Hide friends map") subtitle:RYGLocalized(@"Removes the friends map icon from the notes tray") defaultsKey:@"hide_friends_map" requiresRestart:YES],
												[RYGSetting switchCellWithTitle:RYGLocalized(@"Note actions") subtitle:RYGLocalized(@"Adds copy text, download GIF/audio to the note long-press menu") defaultsKey:@"note_actions"],
												[RYGSetting switchCellWithTitle:RYGLocalized(@"Copy text on hold") subtitle:RYGLocalized(@"Copies note text directly on long press without opening the menu") defaultsKey:@"note_copy_on_hold"],
												[RYGSetting switchCellWithTitle:RYGLocalized(@"Enable note theming") subtitle:RYGLocalized(@"Enables the notes theme picker") defaultsKey:@"enable_notes_customization"],
												[RYGSetting switchCellWithTitle:RYGLocalized(@"Custom note themes") subtitle:RYGLocalized(@"Adds Background, Text and Emoji buttons to the note editor") defaultsKey:@"custom_note_themes"],
											]
										},
										@{
											@"header": RYGLocalized(@"Disappearing media"),
											@"rows": @[
												({ RYGSetting *s = [RYGSetting navigationCellWithTitle:RYGLocalized(@"Arrange overlay buttons")
																			subtitle:RYGLocalized(@"Drag to position the buttons")
																				icon:[RYGSymbol symbolWithIGName:@"reposition" fallback:@"hand.draw"]
																	  viewController:[[RYGOverlayLayoutEditorViewController alloc] initWithLayoutClass:RYGDMButtonLayout.class]];
												   s.whatsNewID = @"ui_overlaylayout"; s; }),
												[RYGSetting switchCellWithTitle:RYGLocalized(@"Close gaps automatically") subtitle:RYGLocalized(@"Buttons next to each other close the gap when one is hidden") defaultsKey:@"dm_button_positions_auto_compact"],
												[RYGSetting switchCellWithTitle:RYGLocalized(@"Show action button") subtitle:RYGLocalized(@"Inserts a button on disappearing media overlays") defaultsKey:@"dm_visual_action_button" requiresRestart:YES],
												({ RYGSetting *s = [RYGSetting navigationCellWithTitle:RYGLocalized(@"Configure menu")
																			subtitle:RYGLocalized(@"Reorder, enable/disable, set default tap")
																				icon:nil
																	  viewController:[[RYGActionMenuConfigViewController alloc] initForSource:RYGActionSourceDM]];
												   s.whatsNewID = @"ui_cfg_actionmenu"; s; }),
												[RYGSetting switchCellWithTitle:RYGLocalized(@"Show mark-as-viewed button") subtitle:RYGLocalized(@"Inserts an eye button to mark the current disappearing media as viewed") defaultsKey:@"dm_visual_seen_button" requiresRestart:YES],
												[RYGSetting switchCellWithTitle:RYGLocalized(@"Advance when marking as seen") subtitle:RYGLocalized(@"Marking as viewed advances to the next stacked media instead of closing") defaultsKey:@"dm_visual_advance_on_mark_seen"],
												[RYGSetting switchCellWithTitle:RYGLocalized(@"Show audio toggle") subtitle:RYGLocalized(@"Inserts a speaker button to mute/unmute disappearing media") defaultsKey:@"dm_visual_audio_toggle" requiresRestart:YES],
												[RYGSetting switchCellWithTitle:RYGLocalized(@"Unlimited replay of visual messages") subtitle:RYGLocalized(@"Replay visual messages without expiring. Toggle in the eye button menu, or as a standalone button when the eye button is disabled") defaultsKey:@"unlimited_replay"],
												[RYGSetting switchCellWithTitle:RYGLocalized(@"Disable view-once limitations") subtitle:RYGLocalized(@"Turns view once messages into normal media you can loop and pause") defaultsKey:@"disable_view_once_limitations"],
											]
										},
										@{
											@"header": RYGLocalized(@"Advanced"),
											@"rows": @[
												[RYGSetting switchCellWithTitle:RYGLocalized(@"Bypass \"You can't send messages\"") subtitle:RYGLocalized(@"Removes the blocked composer banner and restores the text input in restricted threads") defaultsKey:@"unlock_send_composer" requiresRestart:YES],
											]
										}]
				];
}

// MARK: - Unsent indicator

+ (RYGSetting *)unsentIndicatorNavCell {
	RYGSetting *cell = [RYGSetting navigationCellWithTitle:RYGLocalized(@"Indicate unsent messages")
												  subtitle:RYGLocalized(@"How kept messages are marked")
													  icon:nil
											   navSections:[self unsentIndicatorNavSections]];
	cell.defaultsKey = @"indicate_unsent_messages";
	cell.dynamicValueText = ^NSString *{ return [RYGTweakSettings unsentIndicatorSummary]; };
	return cell;
}

+ (NSString *)unsentIndicatorSummary {
	if (![RYGUtils getBoolPref:@"indicate_unsent_messages"]) return RYGLocalized(@"Off");

	NSMutableArray<NSString *> *on = NSMutableArray.array;
	if ([RYGUtils getBoolPref:@"unsent_indicator_label"]) [on addObject:RYGLocalized(@"Tag")];
	if ([RYGUtils getBoolPref:@"unsent_indicator_dim"]) [on addObject:RYGLocalized(@"Fade")];
	if ([RYGUtils getBoolPref:@"unsent_indicator_bubble"]) [on addObject:RYGLocalized(@"Tint")];

	return on.count ? [on componentsJoinedByString:@" + "] : RYGLocalized(@"No mark");
}

+ (NSArray *)unsentIndicatorNavSections {
	return @[
		@{
			@"header": @"",
			@"footer": RYGLocalized(@"Use any mix of the three, or none of them to keep messages silently."),
			@"rows": @[
				[RYGSetting switchCellWithTitle:RYGLocalized(@"Indicate unsent messages") subtitle:RYGLocalized(@"Marks messages someone unsent but you kept") defaultsKey:@"indicate_unsent_messages"],
			]
		},
		@{
			@"header": RYGLocalized(@"Tag"),
			@"rows": @[
				[RYGSetting switchCellWithTitle:RYGLocalized(@"Show tag") subtitle:RYGLocalized(@"A small label on the message") defaultsKey:@"unsent_indicator_label"],
				[self unsentIndicatorTextCell],
				[RYGSetting menuCellWithTitle:RYGLocalized(@"Position") subtitle:RYGLocalized(@"Where the tag sits") menu:[self menus][@"unsent_indicator_position"]],
				[RYGSetting stepperCellWithTitle:RYGLocalized(@"Text size") subtitle:RYGLocalized(@"Drawn at %@ %@") defaultsKey:@"unsent_indicator_label_size" min:6 max:20 step:1 label:@"pt" singularLabel:@"pt"],
				[RYGSetting colorCellWithTitle:RYGLocalized(@"Text color") subtitle:@"" defaultsKey:@"unsent_indicator_label_color" defaultColor:[UIColor colorWithRed:1.0 green:0.3 blue:0.3 alpha:1.0]],
			]
		},
		@{
			@"header": RYGLocalized(@"Bubble"),
			@"footer": RYGLocalized(@"The tint stays put even when a chat background or theme repaints the other bubbles."),
			@"rows": @[
				[RYGSetting switchCellWithTitle:RYGLocalized(@"Fade") subtitle:RYGLocalized(@"Makes the message see-through") defaultsKey:@"unsent_indicator_dim"],
				[RYGSetting stepperCellWithTitle:RYGLocalized(@"Opacity") subtitle:RYGLocalized(@"Left at %@%@ opacity") defaultsKey:@"unsent_indicator_opacity" min:10 max:100 step:5 label:@"%" singularLabel:@"%"],
				[RYGSetting switchCellWithTitle:RYGLocalized(@"Tint") subtitle:RYGLocalized(@"Paints the bubble one color") defaultsKey:@"unsent_indicator_bubble" requiresRestart:YES],
				[RYGSetting colorCellWithTitle:RYGLocalized(@"Bubble color") subtitle:@"" defaultsKey:@"unsent_indicator_bubble_color" defaultColor:[UIColor colorWithRed:0.42 green:0.18 blue:0.18 alpha:1.0]],
				[RYGSetting switchCellWithTitle:RYGLocalized(@"Hide quick actions") subtitle:RYGLocalized(@"Hides the shortcut buttons next to the message") defaultsKey:@"unsent_indicator_hide_accessories"],
			]
		},
		@{
			@"header": @"",
			@"rows": @[ [self unsentIndicatorResetCell] ]
		},
	];
}

+ (RYGSetting *)unsentIndicatorResetCell {
	return [RYGSetting actionCellWithTitle:RYGLocalized(@"Reset to defaults")
									 color:UIColor.systemRedColor
									action:^{
		UIAlertController *a = [UIAlertController
			alertControllerWithTitle:RYGLocalized(@"Reset to defaults")
							 message:RYGLocalized(@"The tag, fade and tint all return to their defaults.")
					  preferredStyle:UIAlertControllerStyleAlert];
		[a addAction:[UIAlertAction actionWithTitle:RYGLocalized(@"Cancel") style:UIAlertActionStyleCancel handler:nil]];
		[a addAction:[UIAlertAction actionWithTitle:RYGLocalized(@"Reset") style:UIAlertActionStyleDestructive
											handler:^(__unused UIAlertAction *action) {
			BOOL tintWasOn = [RYGUtils getBoolPref:@"unsent_indicator_bubble"];

			[RYGUtils setPref:@(YES) forKey:@"unsent_indicator_label"];
			[RYGUtils setPref:@"" forKey:@"unsent_indicator_text"];
			[RYGUtils setPref:@"side" forKey:@"unsent_indicator_position"];
			[RYGUtils setPref:@(10) forKey:@"unsent_indicator_label_size"];
			[RYGUtils setPref:@"#FF4D4D" forKey:@"unsent_indicator_label_color"];
			[RYGUtils setPref:@(YES) forKey:@"unsent_indicator_dim"];
			[RYGUtils setPref:@(45) forKey:@"unsent_indicator_opacity"];
			[RYGUtils setPref:@(NO) forKey:@"unsent_indicator_bubble"];
			[RYGUtils setPref:@"#6B2E2E" forKey:@"unsent_indicator_bubble_color"];
			[RYGUtils setPref:@(YES) forKey:@"unsent_indicator_hide_accessories"];
			[NSNotificationCenter.defaultCenter postNotificationName:@"RYGSettingsShouldReload" object:nil];

			if (tintWasOn) [RYGUtils showRestartConfirmation];
		}]];
		[rygTopVC() presentViewController:a animated:YES completion:nil];
	}];
}

+ (RYGSetting *)unsentIndicatorTextCell {
	RYGSetting *cell = [RYGSetting buttonCellWithTitle:RYGLocalized(@"Tag text")
											  subtitle:@""
												  icon:nil
												action:^{ [RYGTweakSettings promptUnsentIndicatorText]; }];
	cell.dynamicValueText = ^NSString *{
		NSString *cur = [[RYGUtils getStringPref:@"unsent_indicator_text"]
			stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet];
		return cur.length ? cur : RYGLocalized(@"Unsent");
	};
	cell.defaultsKey = @"unsent_indicator_text";
	return cell;
}

+ (void)promptUnsentIndicatorText {
	UIAlertController *alert = [UIAlertController alertControllerWithTitle:RYGLocalized(@"Tag text")
																   message:RYGLocalized(@"Your own wording stays as typed, in any language. Leave it empty for the default.")
															preferredStyle:UIAlertControllerStyleAlert];
	[alert addTextFieldWithConfigurationHandler:^(UITextField *tf) {
		tf.placeholder = RYGLocalized(@"Unsent");
		tf.text = [RYGUtils getStringPref:@"unsent_indicator_text"] ?: @"";
		tf.autocorrectionType = UITextAutocorrectionTypeNo;
		tf.clearButtonMode = UITextFieldViewModeWhileEditing;
	}];
	[alert addAction:[UIAlertAction actionWithTitle:RYGLocalized(@"Cancel") style:UIAlertActionStyleCancel handler:nil]];
	[alert addAction:[UIAlertAction actionWithTitle:RYGLocalized(@"Save") style:UIAlertActionStyleDefault handler:^(__unused UIAlertAction *a) {
		NSString *v = [alert.textFields.firstObject.text
			stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet];
		[RYGUtils setPref:(v ?: @"") forKey:@"unsent_indicator_text"];
		[NSNotificationCenter.defaultCenter postNotificationName:@"RYGSettingsShouldReload" object:nil];
	}]];
	[rygTopVC() presentViewController:alert animated:YES completion:nil];
}

@end
