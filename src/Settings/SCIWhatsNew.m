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
			// Device ID
			@"sci_devicespoof_login_button",
			// Story viewers list — filter / sort / pin
			@"sci_story_viewer_sort_enabled",
			// Follow Requests Tracker
			@"follow_requests_enabled", @"follow_requests_track_outgoing", @"follow_requests_track_incoming",
			@"follow_requests_notify_accepted", @"follow_requests_notify_rejected",
			@"follow_requests_notify_received", @"follow_requests_notify_withdrawn",
			@"follow_requests_check_interval",
			// Hide seen buttons + confirm mark-as-seen
			@"show_dm_seen_button", @"show_story_seen_button",
			@"confirm_mark_seen_dm", @"confirm_mark_seen_story", @"confirm_mark_seen_dm_visual",
			// Disappearing media advance on mark-as-viewed
			@"dm_visual_advance_on_mark_seen",
			// Deleted-messages log — groups, removed reactions, disappearing media, keep-alive
			@"deleted_messages_log_enabled", @"deleted_messages_log_reactions", @"deleted_messages_keepalive",
			// Read receipts
			@"read_receipts_enabled", @"read_receipts_save_log", @"read_receipts_log_groups",
			// Reroute native DM Save button
			@"dm_native_save_enabled",
			// Mirror toasts to iOS notifications
			@"notif_mirror_enabled", @"notif_mirror_clear_on_open",
			// Instants — auto-save, auto-advance after reaction
			@"instants_auto_save", @"instant_auto_advance_reaction",
			// Profile hides
			@"no_profile_suggested_users", @"hide_story_highlights",
			// Liquid glass
			@"liquid_glass_force_off", @"liquid_glass_progressive_blur",
			// Messages-only keeps the search tab
			@"messages_only_hide_search",
			// Disable all tweak options
			@"sci_disable_all",
			// Bypass "You can't send messages"
			@"unlock_send_composer",
			// Favorite GIFs
			@"gif_favorites_enabled",
			// Reworked features
			@"chat_bg_enabled", @"custom_music_sticker_color", @"action_button_profile_enabled",
			// keyless destinations — tagged via SCISetting.whatsNewID
			@"ui_deviceid", @"ui_followrequests", @"ui_taborder", @"ui_filelogging",
			@"ui_profileanalyzer", @"ui_backup", @"ui_notifications", @"ui_dateformat",
			@"ui_cfg_actionmenu",
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
