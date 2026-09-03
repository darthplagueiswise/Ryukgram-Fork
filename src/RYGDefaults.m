#import "RYGDefaults.h"
#import "Utils.h"
#import "UI/Notification/RYGNotificationCenter.h"
#import "UI/Notification/RYGNotificationMirror.h"

NSDictionary *RYGDefaultsDictionary(void) {
	return @{
		@"hide_ads": @(YES),
		@"suppress_surveys": @(NO),
		@"hide_ads_feed": @(YES),
		@"hide_ads_stories": @(YES),
		@"hide_ads_reels": @(YES),
		@"hide_ads_explore": @(YES),
		@"hide_ads_shopping": @(YES),
		@"copy_description": @(YES),
		@"profile_copy_button": @(YES),
		@"detailed_color_picker": @(YES),
		@"remove_screenshot_alert": @(YES),
		@"voice_call_confirm": @(NO),
		@"video_call_confirm": @(NO),
		@"call_recordings_enabled": @(NO),
		@"call_recordings_auto": @(NO),
		@"call_recordings_audio": @"both",
		@"call_recordings_video": @(YES),
		@"call_recordings_self_cam": @(NO),
		@"call_recordings_pip_full": @"remote",
		@"call_recordings_pip_x": @(0.82),
		@"call_recordings_pip_y": @(0.82),
		@"call_recordings_pip_size": @"medium",
		@"call_recordings_ghost_mute": @(NO),
		@"call_recordings_sync_gallery": @(NO),
		@"call_recordings_retention": @"0",
		@"keep_deleted_message": @(NO),
		@"keep_my_deleted_messages": @(NO),
		@"unlock_send_composer": @(NO),
		@"deleted_messages_log_enabled": @(NO),
		@"deleted_messages_log_reactions": @(NO),
		@"deleted_messages_keepalive": @(NO),
		@"nse_viewonce_enabled": @(NO),
		@"nse_capture_normal_media": @(NO),
		@"nse_cleanup_mode": @"off",
		@"nse_cleanup_size_mb": @(200),
		@"nse_cleanup_age_days": @(30),
		@"dm_log_date_format": @"relative",
		@"hide_suggested_stories": @(NO),
		@"hide_story_highlights": @(NO),
		@"hide_stories_midcards": @(NO),
		@"hide_testflight_nag": @(YES),
		@"profile_analyzer_track_visits": @(NO),
		@"profile_analyzer_record_snapshots": @(NO),
		@"profile_analyzer_snapshot_cap": @(20),
		@"profile_analyzer_check_mutual": @(YES),
		@"profile_analyzer_check_not_following_back": @(YES),
		@"profile_analyzer_check_dont_follow_back": @(YES),
		@"profile_analyzer_check_new_followers": @(YES),
		@"profile_analyzer_check_lost_followers": @(YES),
		@"profile_analyzer_check_started_following": @(YES),
		@"profile_analyzer_check_unfollowed": @(YES),
		@"profile_analyzer_check_profile_updates": @(YES),
		@"story_tray_actions": @(NO),
		@"zoom_profile_photo": @(NO),
		@"ryg_followlist_sort_enabled": @(NO),
		@"follow_indicator_lists": @"off",
		@"follow_indicator": @"off",
		@"profile_note_copy": @(NO),
		@"disable_disappearing_mode_swipe": @(NO),
		@"hide_voice_call_button": @(NO),
		@"hide_video_call_button": @(NO),
		@"ryg_silence_calls": @(NO),
		@"fake_location_enabled": @(NO),
		@"show_fake_location_map_button": @(NO),
		@"fake_location_lat": @(48.8584),
		@"fake_location_lon": @(2.2945),
		@"fake_location_name": @"Eiffel Tower",
		@"fake_location_presets": @[],
		@"messages_only": @(NO),
		@"messages_only_hide_tabbar": @(NO),
		@"messages_only_hide_search": @(NO),
		@"messages_only_home_shortcut": @(NO),
		@"messages_only_schedule_enabled": @(NO),
		@"messages_only_schedule_start": @"22:00",
		@"messages_only_schedule_end": @"06:00",
		@"messages_only_schedule_forced": @(NO),
		@"messages_only_schedule_apply": @"live",
		@"hide_send_to_group": @(NO),
		@"confirm_send_to_group": @(NO),
		@"share_sheet_pin_threads": @(NO),
		@"share_sheet_pinned_thread_ids": @[],
		@"hide_reels_friends_bubbles": @(NO),
		@"hide_reels_floating_social_context": @(NO),
		@"hide_made_with_edits": @(NO),
		@"hide_reels_repost": @(NO),
		@"repost_show_date": @(NO),
		@"repost_date_format": @"general",
		@"hide_notes_tray": @(NO),
		@"repost_confirm": @(NO),
		@"emoji_reaction_confirm": @(NO),
		@"story_like_confirm": @(NO),
		@"disable_safe_mode": @(NO),
		@"tweak_settings_app_launch": @(NO),
		@"gallery_folders": @[],
		@"full_followers_count": @(NO),
		@"full_posts_count": @(NO),
		@"reel_card_master_enabled": @(NO),
		@"reel_card_order": @"date,reposts,shares,comments,likes,views",
		@"reel_card_full_views": @(NO),
		@"reel_card_show_likes": @(NO),
		@"reel_card_show_date": @(NO),
		@"reel_card_show_comments": @(NO),
		@"reel_card_show_shares": @(NO),
		@"reel_card_show_reposts": @(NO),
		@"reel_card_fetch_missing": @(NO),
		@"reel_card_shortened_numbers": @(NO),
		@"search_card_enabled": @(NO),
		@"search_card_order": @"date,reposts,shares,comments,likes,views",
		@"search_card_full_views": @(NO),
		@"search_card_show_likes": @(NO),
		@"search_card_show_date": @(NO),
		@"search_card_show_comments": @(NO),
		@"search_card_show_shares": @(NO),
		@"search_card_show_reposts": @(NO),
		@"search_card_fetch_missing": @(NO),
		@"search_card_shortened_numbers": @(NO),
		@"fake_follower_count": @(NO),
		@"fake_follower_count_value": @"",
		@"fake_following_count": @(NO),
		@"fake_following_count_value": @"",
		@"fake_post_count": @(NO),
		@"fake_post_count_value": @"",
		@"fake_verified": @(NO),
		@"fake_username": @(NO),
		@"fake_username_value": @"",
		@"fake_full_name": @(NO),
		@"fake_full_name_value": @"",
		@"fake_identity_real": @{},
		@"launch_tab": @"default",
		@"save_profile": @(YES),

		@"liquid_glass_buttons": @(NO),
		@"liquid_glass_surfaces": @(NO),
		@"liquid_glass_force_off": @(NO),
		@"liquid_glass_progressive_blur": @(NO),
		@"liquid_glass_tabbar_mode": @"default",

		@"flex_app_launch": @(NO),
		@"flex_app_start": @(NO),
		@"flex_instagram": @(NO),

		@"hide_stories_tray": @(NO),
		@"hide_meta_ai": @(NO),
		@"hide_entire_feed": @(NO),
		@"hide_explore_grid": @(NO),
		@"hide_explore_tab": @(NO),
		@"hide_feed_tab": @(NO),
		@"hide_reels_tab": @(NO),
		@"hide_messages_tab": @(NO),
		@"hide_create_tab": @(NO),
		@"hide_friends_map": @(NO),
		@"hide_metrics": @(NO),
		@"hide_reels_blend": @(NO),
		@"hide_reels_header": @(NO),
		@"hide_trending_searches": @(NO),
		@"no_suggested_users": @(NO),
		@"no_suggested_chats": @(NO),
		@"no_dm_search_suggestions": @(NO),
		@"no_suggested_threads": @(NO),
		@"no_suggested_reels": @(NO),
		@"no_suggested_post": @(NO),
		@"no_suggested_account": @(NO),
		@"no_profile_suggested_users": @(NO),
		@"no_recent_searches": @(NO),
		@"no_seen_receipt": @(NO),
		@"remove_lastseen": @(NO),
		@"dm_local_seen": @(NO),

		@"like_confirm": @(NO),
		@"like_confirm_reels": @(NO),
		@"note_like_confirm": @(NO),
		@"note_react_confirm": @(NO),
		@"dm_reaction_confirm_mode": @"off",
		@"follow_confirm": @(NO),
		@"follow_request_confirm": @(NO),
		@"post_comment_confirm": @(NO),
		@"refresh_reel_confirm": @(NO),
		@"refresh_feed_confirm": @(NO),
		@"refresh_feed_stories_only": @(NO),
		@"shh_mode_confirm": @(NO),
		@"voice_message_confirm": @(NO),
		@"change_direct_theme_confirm": @(NO),

		@"disable_feed_autoplay": @(NO),
		@"disable_haptics": @(NO),
		@"disable_scrolling_reels": @(NO),
		@"disable_typing_status": @(NO),
		@"activity_toggle_enabled": @(NO),
		@"disable_view_once_limitations": @(NO),
		@"enable_hidden_texteffectsstyles": @(NO),
		@"reels_show_scrubber": @(NO),
		@"reels_playback_speed": @(NO),
		@"reels_playback_speed_rate": @(1.0),
		@"reels_playback_seek": @(NO),
		@"reels_playback_seek_step": @(10.0),
		@"reels_playback_pause": @(NO),
		@"reels_playback_autoscroll": @(NO),
		@"story_playback_speed": @(NO),
		@"story_playback_speed_rate": @(1.0),
		@"story_playback_seek": @(NO),
		@"story_playback_seek_step": @(10.0),
		@"story_playback_pause": @(NO),
		@"reels_swipe_to_profile": @(NO),
		@"stop_story_auto_advance": @(NO),
		@"unlimited_replay": @(NO),
		@"teen_app_icons": @(NO),
		@"RYGSelectedAppIconName": @"",
		@"ryg_exp_flags_enabled": @(NO),
		@"ryg_metaconfig_enabled": @(NO),

		@"feed_media_zoom": @(NO),
		@"media_zoom_start_muted": @(NO),
		@"enhanced_media_resolution": @(NO),
		@"disable_bg_refresh": @(NO),
		@"disable_home_refresh": @(NO),
		@"disable_home_scroll": @(NO),
		@"feed_reel_tap": @"default",
		@"feed_statusbar_tap": @"default",
		@"main_feed_mode": @"default",
		@"grid_feed_enabled": @(NO),
		@"grid_feed_visible": @(YES),
		@"grid_feed_toggle_placement": @(0),
		@"grid_feed_toggle_last_mode": @(0),
		@"grid_feed_button_layout": @{},
		@"grid_feed_chrome": @{},
		@"grid_feed_hide_stories": @(NO),
		@"grid_feed_columns": @(3),
		@"grid_feed_tall_cells": @(NO),
		@"grid_feed_date_format": @(0),
		@"grid_feed_like_state": @"",
		@"grid_feed_follow_state": @"",
		@"grid_feed_info_order": @"username,following,likes,comments,views,shares,date",
		@"grid_feed_el_username": @(YES),
		@"grid_feed_el_following": @(NO),
		@"grid_feed_el_likes": @(YES),
		@"grid_feed_el_comments": @(YES),
		@"grid_feed_el_views": @(YES),
		@"grid_feed_el_shares": @(NO),
		@"grid_feed_el_date": @(NO),
		@"grid_feed_show_avatar": @(YES),
		@"grid_feed_show_type_badge": @(YES),
		@"grid_feed_shortened_numbers": @(YES),
		@"disable_reels_tab_refresh": @(NO),
		@"dm_full_last_active": @(NO),
		@"bypass_dm_char_limit": @(NO),
		@"send_file": @(NO),
		@"ryg_doodle_image_enabled": @(NO),
		@"note_actions": @(NO),
		@"note_copy_on_hold": @(NO),
		@"feed_date_format": @"default",
		@"feed_date_custom_templates": @"",
		@"feed_date_show_seconds": @(NO),
		@"feed_date_relative_days_threshold": @(0),
		@"feed_date_compact_relative": @(NO),
		@"feed_date_combine_with_date": @"off",

		@"date_fmt_mixed": @(YES),
		@"date_fmt_notes_comments_stories": @(NO),
		@"date_fmt_dms": @(NO),

		@"feed_action_button": @(YES),
		@"feed_action_default": @"menu",
		@"menu_date_feed": @(NO),
		@"reels_action_button": @(YES),
		@"reels_action_default": @"menu",
		@"menu_date_reels": @(NO),
		@"stories_action_button": @(YES),
		@"stories_action_default": @"menu",
		@"menu_date_stories": @(NO),
		@"dm_visual_action_button": @(YES),
		@"dm_visual_action_default": @"menu",
		@"action_button_icon": @"ellipsis.circle",
		@"action_button_icon_feed": @"",
		@"action_button_icon_reels": @"",
		@"action_button_icon_stories": @"",
		@"action_button_icon_dm": @"",
		@"action_button_icon_profile": @"",

		@"action_menu_cfg_feed": @{},
		@"action_menu_cfg_reels": @{},
		@"action_menu_cfg_stories": @{},
		@"action_menu_cfg_dm": @{},
		@"action_menu_cfg_profile": @{},
		@"action_menu_cfg_instants": @{},
		@"action_menu_cfg_dm_native_save": @{},

		@"action_button_profile_enabled": @(NO),
		@"action_button_profile_default_action": @"menu",
		@"action_button_profile_default_copy_info_action": @"copy_username",

		@"chat_bg_enabled": @(NO),
		@"chat_bg_default_asset": @"",
		@"chat_bg_thread_map": @{},
		@"chat_bg_thread_meta": @{},
		@"chat_bg_library": @[],
		@"chat_bg_per_image": @{},

		@"ryg_devicespoof_enabled": @(NO),
		@"ryg_devicespoof_device_id": @"",
		@"ryg_devicespoof_fdid": @"",
		@"ryg_devicespoof_orig_deviceid": @"",
		@"ryg_devicespoof_orig_fbdeviceid": @"",
		@"ryg_devicespoof_mid": @"",
		@"ryg_devicespoof_mid_header": @"",
		@"ryg_devicespoof_orig_mid": @"",
		@"ryg_devicespoof_orig_mid_header": @"",
		@"ryg_devicespoof_login_button": @(YES),
		@"ryg_devicespoof_block_devicecheck": @(NO),

		@"ryg_known_accounts": @{},

		@"ryg_stories_archive": @(NO),
		@"ryg_stories_archive_auto_viewers": @(NO),
		@"ryg_stories_archive_viewer_refresh": @"launch",
		@"ryg_stories_archive_notify_pinned": @(NO),

		@"ryg_gallery_enabled": @(NO),
		@"gallery_save_mode": @"off",
		@"gallery_sort_order": @(0),
		@"gallery_sort_ascending": @(NO),
		@"gallery_sort_type_first": @(0),
		@"gallery_grid_columns": @"3",
		@"gallery_view_mode": @(0),
		@"show_favorites_at_top": @(NO),
		@"gallery_group_mode": @"off",
		@"dm_tab_long_press_gallery": @(NO),

		@"old_feed_logo": @(NO),
		@"home_shortcut_enabled": @(NO),
		@"home_shortcut_icon": @"auto",
		@"home_shortcut_actions": @[],
		@"dm_visual_seen_button": @(YES),
		@"dm_visual_audio_toggle": @(NO),
		@"dm_button_positions": @{},
		@"dm_button_positions_auto_compact": @(YES),
		@"dm_button_positions_spacing": @(6),

		@"dw_legacy_gesture": @(NO),
		@"dw_confirm": @(NO),
		@"dl_max_concurrent": @(3),
		@"dl_auto_retry": @(YES),
		@"dl_auto_retry_count": @(2),
		@"dl_history_retention": @"48",
		@"dl_duplicate_check": @(NO),
		@"dl_name_prefix": @(NO),
		@"bg_keepalive": @(YES),
		@"enhance_download_quality": @(YES),
		@"enhance_download_advanced": @(NO),
		@"default_video_quality": @"always_ask",
		@"default_photo_quality": @"high",
		@"ffmpeg_encoding_speed": @"ultrafast",
		@"adv_encoding_enabled": @(NO),
		@"adv_video_codec": @"h264_videotoolbox",
		@"adv_preset": @"medium",
		@"adv_tune": @"none",
		@"adv_h264_profile": @"high",
		@"adv_h264_level": @"auto",
		@"adv_crf": @"18",
		@"adv_video_bitrate": @"",
		@"adv_max_resolution": @"original",
		@"adv_fps": @"original",
		@"adv_audio_codec": @"copy",
		@"adv_audio_bitrate": @"128k",
		@"adv_audio_channels": @"original",
		@"adv_audio_samplerate": @"original",
		@"adv_pixel_format": @"yuv420p",
		@"adv_faststart": @(YES),
		@"adv_strip_metadata": @(NO),
		@"unfollow_confirm": @(NO),
		@"sticker_interact_stories_mode": @"off",
		@"sticker_interact_highlights_mode": @"off",
		@"dw_save_action": @"share",
		@"dw_finger_count": @(3),
		@"dw_finger_duration": @(0.5),

		@"reels_tap_control": @"default",
		@"reels_long_press": @"default",
		@"reels_photo_tap_mute": @(NO),
		@"nav_tab_order": @"",
		@"hide_profile_tab": @(NO),
		@"swipe_nav_tabs": @"default",
		@"enable_notes_customization": @(YES),
		@"custom_note_themes": @(YES),
		@"disable_auto_unmuting_reels": @(NO),
		@"auto_scroll_reels_mode": @"off",
		@"settings_shortcut": @(YES),
		@"prevent_doom_scrolling": @(NO),
		@"doom_scrolling_reel_count": @(1),
		@"doom_limit_pivot_grids": @(NO),
		@"reels_engagement_filter": @(NO),
		@"reels_filter_hide_hidden_stats": @(NO),
		@"reels_filter_tab_only": @(YES),
		@"reels_filter_min_likes": @(0),
		@"reels_filter_min_comments": @(0),
		@"reels_filter_min_views": @(0),
		@"reels_filter_min_reshares": @(0),

		@"keep_seen_visual_local": @(NO),
		@"send_audio_as_file": @(YES),
		@"download_audio_message": @(NO),
		@"dm_native_save_enabled": @(NO),
		@"audio_page_download": @(NO),
		@"save_to_ryukgram_album": @(NO),
		@"gallery_album_name": @"RyukGram",
		@"unlock_password_reels": @(YES),

		@"seen_mode": @"button",
		@"seen_auto_on_interact": @(NO),
		@"seen_auto_on_typing": @(NO),
		@"show_dm_seen_button": @(YES),
		@"show_story_seen_button": @(YES),
		@"confirm_mark_seen_dm": @(NO),
		@"confirm_mark_seen_story": @(NO),
		@"confirm_mark_seen_dm_visual": @(NO),
		@"seen_on_story_like": @(NO),
		@"seen_on_story_reply": @(NO),
		@"advance_on_story_reply": @(NO),
		@"advance_on_mark_seen": @(NO),
		@"advance_on_story_like": @(NO),
		@"dm_visual_advance_on_mark_seen": @(NO),

		@"indicate_unsent_messages": @(NO),
		@"unsent_indicator_label": @(YES),
		@"unsent_indicator_text": @"",
		@"unsent_indicator_position": @"side",
		@"unsent_indicator_label_size": @(10),
		@"unsent_indicator_label_color": @"#FF4D4D",
		@"unsent_indicator_dim": @(YES),
		@"unsent_indicator_opacity": @(45),
		@"unsent_indicator_bubble": @(NO),
		@"unsent_indicator_bubble_color": @"#6B2E2E",
		@"unsent_indicator_hide_accessories": @(YES),
		@"unsent_message_toast": @(NO),
		@"warn_refresh_clears_preserved": @(NO),

		@"read_receipts_log_groups": @(NO),

		@"activity_notif_enabled": @(NO),
		@"activity_read_mode": @"off",
		@"activity_online_mode": @"notify_log",
		@"activity_offline_mode": @"notify_log",
		@"activity_typing_mode": @"notify_log",
		@"activity_fast_presence": @(NO),
		@"activity_fast_presence_secs": @(20),

		@"follow_requests_enabled": @(NO),
		@"follow_requests_track_outgoing": @(YES),
		@"follow_requests_track_incoming": @(YES),
		@"follow_requests_check_interval": @"3600",
		@"follow_requests_notify_accepted": @(YES),
		@"follow_requests_notify_rejected": @(YES),
		@"follow_requests_notify_received": @(YES),
		@"follow_requests_notify_withdrawn": @(YES),

		@"enable_chat_exclusions": @(YES),
		@"chat_blocking_mode": @"block_all",
		@"exclusions_default_keep_deleted": @(NO),
		@"chat_quick_list_button": @(YES),

		@"enable_story_user_exclusions": @(YES),
		@"ryg_story_viewer_sort_enabled": @(NO),
		@"story_viewer_default_list": @"ryukgram",
		@"story_blocking_mode": @"block_all",
		@"story_seen_mode": @"button",
		@"story_seen_marked_indicator": @"hide",
		@"story_audio_toggle": @(NO),
		@"view_story_mentions": @(YES),
		@"story_mentions_button": @(NO),
		@"story_mentions_counter": @(NO),
		@"story_button_positions": @{},
		@"story_button_positions_auto_compact": @(YES),
		@"story_button_positions_spacing": @(6),

		@"stories_show_quiz_answer": @(NO),
		@"stories_show_poll_votes_count": @(NO),
		@"reels_show_quiz_answer": @(NO),
		@"reels_show_poll_votes_count": @(NO),
		@"force_enable_quiz_sticker": @(NO),
		@"bypass_reveal_sticker": @(NO),
		@"photo_sticker_allow_video": @(NO),

		@"ryg_disable_all": @(NO),

		@"ryg_fix_duplicate_notifications": @(YES),

		@"settings_pause_playback": @(YES),
		@"whatsnew_always_show": @(NO),
		@"embed_links": @(NO),
		@"embed_link_domain": @"kkinstagram.com",
		@"strip_tracking_params": @(NO),
		@"download_highlight_cover": @(YES),
		@"open_links_external": @(NO),
		@"strip_browser_tracking": @(NO),

		@"hide_feed_repost": @(NO),
		@"copy_comment": @(YES),
		@"download_gif_comment": @(YES),
		@"custom_gif_comment": @(NO),
		@"gif_favorites_enabled": @(NO),
		@"gif_favorites_list": @[],
		@"skip_sensitive_content": @(NO),

		@"cache_auto_clear_mode": @"off",
		@"cache_auto_check_size": @(YES),
		@"cache_preserve_messages_db": @(YES),
		@"cache_last_auto_clear_ts": @(0),
		@"cache_last_known_size": @(0),
		@"cache_auto_clear_in_progress": @(NO),
		@"cache_auto_clear_last_result": @"never",
		@"cache_auto_clear_fail_count": @(0),
		@"ryg_changelog_force_show": @(NO),

		@"live_anonymous_view": @(NO),
		@"live_hide_comments": @(NO),
		@"hide_ui_on_capture": @(NO),
		@"paste_link_from_search": @(NO),
		@"ryg_language": @"system",
		@"ig_force_language": @"system",

		@"theme_mode": @"off",
		@"theme_force": @(NO),
		@"theme_oled_chat": @(NO),
		@"theme_keyboard": @"off",

		@"igt_homecoming": @(NO),
		@"igt_quicksnap": @(NO),
		@"igt_prism": @(NO),
		@"igt_directnotes_friendmap": @(NO),
		@"igt_directnotes_audio_reply": @(NO),
		@"igt_directnotes_avatar_reply": @(NO),
		@"igt_directnotes_gifs_reply": @(NO),
		@"igt_directnotes_photo_reply": @(NO),
		@"igt_ip_appicon": @(NO),
		@"igt_ip_storyfonts": @(NO),
		@"igt_ip_chatfonts": @(NO),
		@"igt_ip_biofont": @(NO),
		@"igt_ip_customlists": @(NO),
		@"igt_ip_storypeek": @(NO),
		@"igt_ip_dmpeek": @(NO),
		@"igt_ip_brandedthreads": @(NO),
		@"igt_ip_timestampviewers": @(NO),
		@"igt_ip_searchviewers": @(NO),
		@"igt_ip_storyspotlight": @(NO),
		@"igt_ip_superlikes": @(NO),
		@"igt_ip_storyrewatch": @(NO),
		@"igt_ip_storyextend": @(NO),
		@"igt_ip_pinnedposts": @(NO),
		@"igt_ip_silentprofile": @(NO),
		@"igt_ip_silenthighlights": @(NO),
		@"ryg_exp_warning_seen": @(NO),
		@"custom_music_sticker_color": @(NO),
		@"instants_send_from_gallery": @(NO),
		@"instants_allow_screenshot": @(NO),
		@"instants_download_btn": @(NO),
		@"instants_confirm_toggle_btn": @(NO),
		@"instants_auto_save": @"off",
		@"instants_emoji_reaction_confirm": @(NO),
		@"instants_capture_confirm": @(NO),
		@"instants_advance_confirm": @(NO),
		@"instant_auto_advance_reaction": @(NO),
		@"instants_auto_close": @(NO),

		@"lock_master_enabled": @(NO),
		@"lock_biometric_enabled": @(YES),
		@"lock_passcode_length": @(4),
		@"lock_chats_locked_entries": @[],
		@"lock_chats_appearance_default": @"icon",
		@"lock_chats_appearance_overrides": @{},
		@"lock_chats_hide_from_inbox": @(NO),
		@"lock_chats_hide_preview": @(NO),
		@"hidden_chats": @[],
		@"hidden_chats_reveal_on_hold": @(YES),

		@"lock_app_enabled": @(NO),
		@"lock_app_relock_background": @(YES),
		@"lock_app_idle_timeout": @(0),
		@"lock_app_independent_session": @(YES),
		@"lock_app_relock_on_dismiss": @(NO),

		@"lock_settings_enabled": @(NO),
		@"lock_settings_relock_background": @(NO),
		@"lock_settings_idle_timeout": @(300),
		@"lock_settings_independent_session": @(NO),
		@"lock_settings_relock_on_dismiss": @(NO),

		@"lock_gallery_enabled": @(NO),
		@"lock_gallery_relock_background": @(NO),
		@"lock_gallery_idle_timeout": @(300),
		@"lock_gallery_independent_session": @(NO),
		@"lock_gallery_relock_on_dismiss": @(NO),

		@"lock_keep_deleted_enabled": @(NO),
		@"lock_keep_deleted_relock_background": @(NO),
		@"lock_keep_deleted_idle_timeout": @(300),
		@"lock_keep_deleted_independent_session": @(NO),
		@"lock_keep_deleted_relock_on_dismiss": @(NO),

		@"lock_profile_analyzer_enabled": @(NO),
		@"lock_profile_analyzer_relock_background": @(NO),
		@"lock_profile_analyzer_idle_timeout": @(300),
		@"lock_profile_analyzer_independent_session": @(NO),
		@"lock_profile_analyzer_relock_on_dismiss": @(NO),

		@"lock_call_recordings_enabled": @(NO),
		@"lock_call_recordings_relock_background": @(NO),
		@"lock_call_recordings_idle_timeout": @(300),
		@"lock_call_recordings_independent_session": @(NO),
		@"lock_call_recordings_relock_on_dismiss": @(NO),

		@"lock_activity_log_enabled": @(NO),
		@"lock_activity_log_relock_background": @(NO),
		@"lock_activity_log_idle_timeout": @(300),
		@"lock_activity_log_independent_session": @(NO),
		@"lock_activity_log_relock_on_dismiss": @(NO),

		@"lock_messages_tab_enabled": @(NO),
		@"lock_messages_tab_relock_background": @(YES),
		@"lock_messages_tab_idle_timeout": @(0),
		@"lock_messages_tab_independent_session": @(YES),
		@"lock_messages_tab_relock_on_dismiss": @(YES),

		@"lock_chats_enabled": @(NO),
		@"lock_chats_relock_background": @(YES),
		@"lock_chats_idle_timeout": @(0),
		@"lock_chats_independent_session": @(YES),
		@"lock_chats_relock_on_dismiss": @(YES),

		@"lock_hidden_reveal_enabled": @(NO),
		@"lock_hidden_reveal_relock_background": @(YES),
		@"lock_hidden_reveal_idle_timeout": @(0),
		@"lock_hidden_reveal_independent_session": @(YES),
		@"lock_hidden_reveal_relock_on_dismiss": @(YES),

		@"notif_master_enabled": @(YES),
		@"notif_style": @"colorful",
		@"notif_position": @"top",
		@"notif_default_surface": @"pill",
		@"notif_max_visible": @(2),
		@"notif_haptics": @(YES),
		@"notif_duration": @(1.0),
		@"notif_mirror_enabled": @(YES),
		@"notif_mirror_while_open": @(NO),
		@"notif_mirror_clear_on_open": @(YES),
	};
}

void RYGRegisterDefaultsOnce(void) {
	static dispatch_once_t onceToken;
	dispatch_once(&onceToken, ^{
		NSMutableDictionary *defaults = [RYGDefaultsDictionary() mutableCopy];
		[defaults addEntriesFromDictionary:[RYGNotificationCenter defaultPerActionPrefs]];
		[defaults addEntriesFromDictionary:[RYGNotificationMirror defaultPerActionPrefs]];
		[[NSUserDefaults standardUserDefaults] registerDefaults:defaults];
		[RYGUtils setRygRegisteredDefaults:defaults];
	});
}

// Carry pre-rename keys onto the new prefixes once, before defaults register.
void RYGMigrateLegacyDefaults(void) {
	NSUserDefaults *d = [NSUserDefaults standardUserDefaults];
	if ([d boolForKey:@"ryg_defaults_migrated_v1"]) return;

	NSString *bundleId = [[NSBundle mainBundle] bundleIdentifier] ?: @"";
	NSDictionary *domain = [d persistentDomainForName:bundleId];
	NSMutableArray<NSString *> *stale = [NSMutableArray array];

	for (NSString *key in domain) {
		NSString *newKey = nil;
		if ([key hasPrefix:@"sci_"])         newKey = [@"ryg_" stringByAppendingString:[key substringFromIndex:4]];
		else if ([key hasPrefix:@"SCInsta"]) newKey = [@"RyukGram" stringByAppendingString:[key substringFromIndex:7]];
		else if ([key hasPrefix:@"SCI"])     newKey = [@"RYG" stringByAppendingString:[key substringFromIndex:3]];
		if (!newKey) continue;
		if ([d objectForKey:newKey] == nil) [d setObject:domain[key] forKey:newKey];
		[stale addObject:key];
	}
	for (NSString *key in stale) [d removeObjectForKey:key];

	[d setBool:YES forKey:@"ryg_defaults_migrated_v1"];
	[d synchronize];
}

static BOOL rygSameStorageKind(id a, id b) {
	for (Class kind in @[ NSNumber.class, NSString.class, NSArray.class, NSDictionary.class, NSData.class ])
		if ([a isKindOfClass:kind]) return [b isKindOfClass:kind];
	return NO;
}

// An old install can leave a key holding a type this build no longer reads.
void RYGDropMistypedStoredDefaults(void) {
	NSUserDefaults *d = [NSUserDefaults standardUserDefaults];
	if ([d boolForKey:@"ryg_defaults_typecheck_v1"]) return;

	NSDictionary *expected = [RYGUtils rygRegisteredDefaults];
	NSDictionary *domain = [d persistentDomainForName:[[NSBundle mainBundle] bundleIdentifier] ?: @""];
	for (NSString *key in expected) {
		id stored = domain[key];
		if (stored && !rygSameStorageKind(stored, expected[key])) [d removeObjectForKey:key];
	}

	[d setBool:YES forKey:@"ryg_defaults_typecheck_v1"];
	[d synchronize];
}

// Splits the old per-type on/off into an independent mode per type.
void RYGMigrateActivityModes(void) {
	NSUserDefaults *d = [NSUserDefaults standardUserDefaults];
	if ([d boolForKey:@"activity_modes_migrated_v1"]) return;
	[d setBool:YES forKey:@"activity_modes_migrated_v1"];

	BOOL touched = [d objectForKey:@"activity_online_enabled"] != nil
	            || [d objectForKey:@"read_receipts_enabled"] != nil
	            || [d objectForKey:@"activity_notif_enabled"] != nil;
	if (!touched) return; // fresh install, registered defaults are already right

	BOOL master  = [d boolForKey:@"activity_notif_enabled"];
	BOOL saveLog = [d objectForKey:@"read_receipts_save_log"] ? [d boolForKey:@"read_receipts_save_log"] : YES;
	BOOL readOn  = [d objectForKey:@"read_receipts_enabled"] ? [d boolForKey:@"read_receipts_enabled"] : NO;

	// The old split (notify = master, log = save_log) maps exactly onto the two bits.
	NSString *(^combo)(BOOL, BOOL) = ^NSString *(BOOL notify, BOOL log) {
		if (notify && log) return @"notify_log";
		if (notify) return @"notify";
		if (log) return @"log";
		return @"off";
	};
	NSString *(^presenceMode)(NSString *) = ^NSString *(NSString *typeKey) {
		BOOL on = [d objectForKey:typeKey] ? [d boolForKey:typeKey] : YES;
		return combo(on && master, on && saveLog);
	};
	NSString *onlineM  = presenceMode(@"activity_online_enabled");
	NSString *offlineM = presenceMode(@"activity_offline_enabled");
	NSString *typingM  = presenceMode(@"activity_typing_enabled");
	NSString *readM    = combo(readOn, readOn && saveLog);
	[d setObject:onlineM  forKey:@"activity_online_mode"];
	[d setObject:offlineM forKey:@"activity_offline_mode"];
	[d setObject:typingM  forKey:@"activity_typing_mode"];
	[d setObject:readM    forKey:@"activity_read_mode"];

	// The master now gates log too, so switch it on if anything was doing something.
	BOOL anyOn = ![onlineM isEqual:@"off"] || ![offlineM isEqual:@"off"]
	          || ![typingM isEqual:@"off"] || ![readM isEqual:@"off"];
	[d setBool:anyOn forKey:@"activity_notif_enabled"];

	for (NSString *k in @[ @"activity_online_enabled", @"activity_offline_enabled",
	                       @"activity_typing_enabled", @"read_receipts_enabled", @"read_receipts_save_log" ])
		[d removeObjectForKey:k];
	[d synchronize];
}
