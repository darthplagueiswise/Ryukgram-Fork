#import "RYGWhatsNew.h"
#import "RYGSetting.h"
#import "../Utils.h"

static NSString *const kSeenKey = @"ryg_whatsnew_seen";
static NSString *const kGenKey = @"ryg_whatsnew_gen";

// Bump whenever newIDs changes, otherwise an ID reused from a past release stays
static NSInteger const kNewIDsGeneration = 3;

@implementation RYGWhatsNew

+ (NSSet<NSString *> *)newIDs {
	static NSSet *ids;
	static dispatch_once_t once;
	dispatch_once(&once, ^{
		ids = [NSSet setWithArray:@[
			// Call recording
			@"call_recordings_enabled", @"call_recordings_auto", @"call_recordings_audio",
			@"call_recordings_video", @"call_recordings_self_cam", @"call_recordings_pip_full",
			@"call_recordings_pip_size", @"call_recordings_sync_gallery", @"call_recordings_retention",
			@"call_recordings_ghost_mute", @"ui_callignore", @"ui_callpip",
			// Activity — status toggle, presence/typing/read modes, accurate active status
			@"activity_toggle_enabled", @"activity_notif_enabled", @"activity_fast_presence",
			@"activity_read_mode", @"activity_online_mode", @"activity_offline_mode", @"activity_typing_mode",
			@"ui_activitymatrix",
			// Keep my own unsends
			@"keep_my_deleted_messages",
			// Instagram Plus
			@"igt_ip_storypeek", @"igt_ip_storyfonts", @"igt_ip_searchviewers", @"igt_ip_timestampviewers",
			@"igt_ip_silentprofile", @"igt_ip_silenthighlights", @"igt_ip_storyrewatch", @"igt_ip_storyextend",
			@"igt_ip_storyspotlight", @"igt_ip_superlikes", @"igt_ip_dmpeek", @"igt_ip_chatfonts",
			@"igt_ip_brandedthreads", @"igt_ip_appicon", @"igt_ip_biofont", @"igt_ip_customlists",
			@"igt_ip_pinnedposts",
			// Grid feed
			@"ui_gridfeed",
			// Feed refresh
			@"refresh_feed_confirm", @"refresh_feed_stories_only",
			// Reels playback menu + repost date
			@"reels_playback_seek", @"reels_playback_autoscroll",
			@"repost_show_date", @"repost_date_format",
			// Card details — search/explore grids and profile grids
			@"ui_searchcard", @"ui_profilecard",
			// Block surveys
			@"suppress_surveys",
			// Hide DM search suggestions
			@"no_dm_search_suggestions",
			// Instants — auto-close, video from gallery, new menu entries
			@"instants_auto_close", @"instants_send_from_gallery",
			// Story/DM overlay buttons — drag-to-place editor
			@"ui_overlaylayout",
			// Action menus — story "Save image (no music)", instants video entries
			@"ui_cfg_actionmenu",
			// Send image as drawing
			@"ryg_doodle_image_enabled",
			// Instagram interface language
			@"ui_iglanguage",
			// Messages-only automatic schedule
			@"messages_only_schedule_enabled",
			// Device ID — vendor/machine ID masking + Apple attestation block
			@"ui_deviceid", @"ryg_devicespoof_block_devicecheck",
			// Download manager rebuild + history
			@"ui_downloadmanager", @"dl_history_retention",
			// Security & Privacy — new lock targets, hold-to-reveal hidden chats
			@"ui_lockpasscode", @"hidden_chats_reveal_on_hold",
			// Gallery grid columns
			@"gallery_grid_columns",
			// Reworked destinations
			@"ui_backup", @"ui_storage", @"ui_gallery", @"ui_lock", @"ui_taborder",
			@"ui_notifications", @"ui_profileanalyzer", @"ui_followrequests",
			@"ui_homeshortcut_config", @"chat_bg_enabled",
			@"ryg_story_viewer_sort_enabled", @"ryg_followlist_sort_enabled",
			// Story viewers — default list choice
			@"story_viewer_default_list",
			// Stories archive
			@"ui_storiesarchive",
			// Action button icon browser, date format, app icon picker
			@"ui_actionicon", @"ui_dateformat", @"ui_appicon",
			// Reels engagement filter
			@"reels_engagement_filter", @"reels_filter_min_likes", @"reels_filter_min_comments",
			@"reels_filter_min_views", @"reels_filter_min_reshares",
			@"reels_filter_hide_hidden_stats", @"reels_filter_tab_only",
			// Auto-scroll reels mode
			@"auto_scroll_reels_mode",
			// Marked-seen indicator + local seen
			@"story_seen_marked_indicator", @"keep_seen_visual_local", @"dm_local_seen",
			// Bypass send-composer block
			@"unlock_send_composer",
			// Instants confirm-switch button
			@"instants_confirm_toggle_btn",
			// Notifications — system banner while open
			@"notif_mirror_while_open",
			// Story playback menu + reels pause
			@"story_playback_speed", @"story_playback_seek", @"story_playback_pause",
			@"reels_playback_pause",
		]];
	});
	return ids;
}

+ (NSMutableSet<NSString *> *)seenSet {
	static NSMutableSet *seen;
	static dispatch_once_t once;
	dispatch_once(&once, ^{
		NSUserDefaults *ud = NSUserDefaults.standardUserDefaults;
		if ([ud integerForKey:kGenKey] != kNewIDsGeneration) {
			[ud removeObjectForKey:kSeenKey];
			[ud setInteger:kNewIDsGeneration forKey:kGenKey];
			seen = [NSMutableSet set];
			return;
		}
		NSArray *stored = [ud arrayForKey:kSeenKey];
		seen = stored.count ? [NSMutableSet setWithArray:stored] : [NSMutableSet set];
	});
	return seen;
}

+ (BOOL)alwaysShow { return [RYGUtils getBoolPref:@"whatsnew_always_show"]; }

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

+ (NSString *)identifierForRow:(RYGSetting *)row {
	if (row.whatsNewID.length) return row.whatsNewID;
	if (row.defaultsKey.length) return row.defaultsKey;
	if (row.type == RYGTableCellMenu && row.baseMenu) return [self defaultsKeyInMenu:row.baseMenu];
	return nil;
}

+ (BOOL)sectionsHaveUnseen:(NSArray *)sections {
	for (NSDictionary *section in sections) {
		if (![section isKindOfClass:NSDictionary.class]) continue;
		for (RYGSetting *row in section[@"rows"]) {
			if (![row isKindOfClass:RYGSetting.class]) continue;
			if ([self isUnseen:[self identifierForRow:row]]) return YES;
			if (row.navSections.count && [self sectionsHaveUnseen:row.navSections]) return YES;
		}
	}
	return NO;
}

@end
