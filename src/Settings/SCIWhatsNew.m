#import "SCIWhatsNew.h"
#import "SCISetting.h"
#import "../Utils.h"

static NSString *const kSeenKey = @"sci_whatsnew_seen";

@implementation SCIWhatsNew

+ (NSSet<NSString *> *)newIDs {
	static NSSet *ids;
	static dispatch_once_t once;
	dispatch_once(&once, ^{
		ids = [NSSet setWithArray:@[
			@"action_button_profile_enabled", @"adv_audio_bitrate", @"adv_audio_channels",
			@"adv_audio_codec", @"adv_audio_samplerate", @"adv_crf",
			@"adv_encoding_enabled", @"adv_faststart", @"adv_fps",
			@"adv_h264_level", @"adv_h264_profile", @"adv_max_resolution",
			@"adv_pixel_format", @"adv_preset", @"adv_strip_metadata",
			@"adv_tune", @"adv_video_bitrate", @"adv_video_codec",
			@"audio_page_download", @"bg_keepalive", @"bypass_dm_char_limit",
			@"bypass_reveal_sticker", @"cache_preserve_messages_db", @"chat_bg_enabled",
			@"confirm_send_to_group", @"follow_indicator",
			@"custom_gif_comment", @"custom_music_sticker_color", @"deleted_messages_log_enabled",
			@"dl_auto_retry", @"dl_auto_retry_count", @"dl_max_concurrent",
			@"dm_tab_long_press_gallery", @"enhanced_media_resolution",
			@"full_followers_count", @"full_posts_count", @"gallery_album_name",
			@"gallery_save_mode", @"hide_ads_explore", @"hide_ads_feed",
			@"hide_ads_reels", @"hide_ads_shopping", @"hide_ads_stories",
			@"hide_made_with_edits", @"hide_reels_floating_social_context", @"hide_reels_friends_bubbles",
			@"hide_send_to_group", @"hide_stories_midcards", @"hide_testflight_nag",
			@"home_shortcut_enabled", @"instants_advance_confirm", @"instants_capture_confirm",
			@"instants_download_btn", @"instants_emoji_reaction_confirm", @"instants_send_from_gallery",
			@"liquid_glass_tabbar_mode", @"main_feed_mode", @"media_zoom_start_muted",
			@"note_like_confirm", @"note_react_confirm", @"photo_sticker_allow_video",
			@"reel_card_fetch_missing", @"reel_card_full_views", @"reel_card_shortened_numbers",
			@"reel_card_show_date", @"reel_card_show_likes", @"reels_playback_speed",
			@"reels_swipe_to_profile", @"sci_fix_duplicate_notifications", @"sci_followlist_sort_enabled",
			@"sci_gallery_enabled", @"sci_silence_calls", @"share_sheet_pin_threads",
			@"skip_sensitive_content", @"sticker_interact_highlights_mode", @"sticker_interact_stories_mode",
			@"story_mentions_button", @"story_mentions_counter", @"theme_force",
			@"theme_mode", @"whatsnew_always_show",
			// keyless destinations — tagged via SCISetting.whatsNewID
			@"ui_gallery", @"ui_lock", @"ui_backup", @"ui_interface", @"ui_dateformat",
			@"ui_notifications", @"ui_appicon", @"ui_downloadmanager", @"ui_actionicon",
			@"ui_homeshortcut_config", @"ui_profileanalyzer", @"ui_cfg_actionmenu",
		]];
	});
	return ids;
}

+ (NSMutableSet<NSString *> *)seenSet {
	static NSMutableSet *seen;
	static dispatch_once_t once;
	dispatch_once(&once, ^{
		NSArray *stored = [NSUserDefaults.standardUserDefaults arrayForKey:kSeenKey];
		seen = stored.count ? [NSMutableSet setWithArray:stored] : [NSMutableSet set];
	});
	return seen;
}

+ (BOOL)alwaysShow { return [SCIUtils getBoolPref:@"whatsnew_always_show"]; }

+ (BOOL)isUnseen:(NSString *)identifier {
	if (!identifier.length || ![[self newIDs] containsObject:identifier]) return NO;
	if ([self alwaysShow]) return YES;
	return ![[self seenSet] containsObject:identifier];
}

+ (void)markSeen:(NSString *)identifier {
	if ([self alwaysShow]) return;
	if (!identifier.length || ![[self newIDs] containsObject:identifier]) return;
	NSMutableSet *seen = [self seenSet];
	if ([seen containsObject:identifier]) return;
	[seen addObject:identifier];
	[NSUserDefaults.standardUserDefaults setObject:seen.allObjects forKey:kSeenKey];
}

+ (NSString *)defaultsKeyInMenu:(UIMenu *)menu {
	for (UIMenuElement *el in menu.children) {
		if ([el isKindOfClass:UIMenu.class]) {
			NSString *k = [self defaultsKeyInMenu:(UIMenu *)el];
			if (k) return k;
		} else if ([el isKindOfClass:UICommand.class]) {
			id pl = [(UICommand *)el propertyList];
			if ([pl isKindOfClass:NSDictionary.class] && [pl[@"defaultsKey"] isKindOfClass:NSString.class])
				return pl[@"defaultsKey"];
		}
	}
	return nil;
}

+ (NSString *)identifierForRow:(SCISetting *)row {
	if (row.whatsNewID.length) return row.whatsNewID;
	if (row.defaultsKey.length) return row.defaultsKey;
	if (row.type == SCITableCellMenu && row.baseMenu) return [self defaultsKeyInMenu:row.baseMenu];
	return nil;
}

+ (BOOL)sectionsHaveUnseen:(NSArray *)sections {
	for (NSDictionary *section in sections) {
		if (![section isKindOfClass:NSDictionary.class]) continue;
		for (SCISetting *row in section[@"rows"]) {
			if (![row isKindOfClass:SCISetting.class]) continue;
			if ([self isUnseen:[self identifierForRow:row]]) return YES;
			if (row.navSections.count && [self sectionsHaveUnseen:row.navSections]) return YES;
		}
	}
	return NO;
}

@end
