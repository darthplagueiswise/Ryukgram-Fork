#import "RYGAssetUtils.h"
#import "../UI/RYGIcon.h"

// Friendly gallery name → real IG glyph. Tried first; SF map below is the fallback.
static NSString *RYGIGForName(NSString *name) {
	if (!name.length) return nil;
	static NSDictionary<NSString *, NSString *> *map;
	static dispatch_once_t once;
	dispatch_once(&once, ^{
		map = @{
			// Generic / chrome
			@"more":		  @"ig_icon_more_horizontal_outline_24",
			@"settings":	  @"ig_icon_settings_outline_24",
			@"xmark":		  @"ig_icon_x_outline_24",
			@"close":		  @"ig_icon_x_outline_24",
			@"circle_check":  @"ig_icon_circle_check_outline_24",
			@"circle_check_filled": @"ig_icon_circle_check_filled_24",
			@"circle_xmark":  @"ig_icon_circle_x_outline_24",
			@"circle":		  @"ig_icon_circle_outline_24",
			@"clock":		  @"ig_icon_clock_outline_24",
			@"backspace":	  @"ig_icon_backspace_outline_24",
			@"external_link": @"ig_icon_external_link_outline_24",
			@"copy":		  @"ig_icon_copy_outline_24",
			@"copy_filled":   @"ig_icon_copy_filled_24",
			@"link":		  @"ig_icon_link_outline_24",
			@"text":		  @"ig_icon_text_outline_24",
			@"caption":		  @"ig_icon_text_outline_24",
			@"key":			  @"ig_icon_hashtag_outline_24",
			@"users":		  @"ig_icon_users_outline_24",
			@"lock":		  @"ig_icon_lock_outline_24",
			@"unlock":		  @"ig_icon_unlock_prism_outline_24",
			@"profile":		  @"ig_icon_user_circle_outline_24",
			@"chevron_right": @"ig_icon_chevron_right_outline_24",
			@"arrow_up":	  @"ig_icon_arrow_up_outline_24",
			@"arrow_down":	  @"ig_icon_arrow_down_outline_24",
			@"info":		  @"ig_icon_info_outline_24",

			// Media
			@"photo":		  @"ig_icon_photo_outline_24",
			@"photo_filled":  @"ig_icon_photo_filled_24",
			@"video":		  @"ig_icon_play_filled_24",
			@"video_filled":  @"ig_icon_play_filled_24",
			@"video_outline": @"ig_icon_play_prism_outline_24",
			@"audio":		  @"ig_icon_audio_wave_outline_24",
			@"waveform":	  @"ig_icon_audio_wave_outline_24",
			@"gif":			  @"ig_icon_gif_filled_24",
			@"gif_outline":   @"ig_icon_gif_outline_24",
			@"media":		  @"ig_icon_media_outline_24",
			@"media_empty":   @"ig_icon_no_photo_outline_24",
			@"photo_gallery": @"ig_icon_photo_gallery_outline_24",

			// Sources
			@"feed":		  @"ig_icon_feeds_outline_24",
			@"story":		  @"ig_icon_story_outline_24",
			@"stories":		  @"ig_icon_story_outline_24",
			@"reels":		  @"ig_icon_reels_outline_24",
			@"reel":		  @"ig_icon_reels_outline_24",
			@"messages":	  @"ig_icon_direct_outline_24",
			@"notes":		  @"ig_icon_text_post_outline_24",
			@"comments":	  @"ig_icon_comment_outline_24",
			@"call":		  @"ig_icon_call_outline_24",
			@"instants":	  @"ig_icon_app_instants_outline_24",
			@"green_screen":  @"ig_icon_green_screen_outline_24",

			// Actions
			@"share":		  @"ig_icon_share_pano_outline_24",
			@"download":	  @"ig_icon_download_outline_24",
			@"download_filled": @"ig_icon_download_filled_24",
			@"save":		  @"ig_icon_download_outline_24",
			@"trash":		  @"ig_icon_delete_outline_24",
			@"delete":		  @"ig_icon_delete_outline_24",
			@"folder":		  @"ig_icon_folder_outline_24",
			@"folder_move":   @"ig_icon_folder_arrow_right_prism_outline_24",
			@"heart":		  @"ig_icon_heart_outline_24",
			@"heart_filled":  @"ig_icon_heart_filled_24",
			@"favorite":	  @"ig_icon_star_outline_24",
			@"favorite_filled": @"ig_icon_star_pano_filled_24",
			@"search":		  @"ig_icon_search_outline_24",
			@"filter":		  @"ig_icon_sliders_outline_24",
			@"sort":		  @"ig_icon_sort_pano_outline_24",
			@"calendar":	  @"ig_icon_calendar_outline_24",
			@"calendar_star": @"ig_icon_calendar_star_outline_24",
			@"list":		  @"ig_icon_photo_list_outline_24",
			@"grid":		  @"ig_icon_photo_grid_outline_24",
			@"edit":		  @"ig_icon_edit_outline_24",
			@"add":			  @"ig_icon_add_outline_24",
			@"plus":		  @"ig_icon_add_outline_24",

			// Status
			@"error_filled":  @"ig_icon_error_filled_24",
		};
	});
	return map[name];
}

// SF fallback for friendly names without a clean IG glyph (e.g. @username).
static NSString *RYGSFForIGName(NSString *name) {
	if (!name.length) return nil;
	static NSDictionary<NSString *, NSString *> *map;
	static dispatch_once_t once;
	dispatch_once(&once, ^{
		map = @{
			// Generic / chrome
			@"more":		  @"ellipsis",
			@"settings":	  @"gearshape",
			@"xmark":		 @"xmark",
			@"circle_check":  @"checkmark.circle",
			@"backspace":	 @"delete.left",
			@"external_link": @"arrow.up.right.square",
			@"copy":		  @"doc.on.doc",
			@"copy_filled":   @"doc.on.doc.fill",
			@"link":		  @"link",
			@"text":		  @"textformat",
			@"caption":	   @"text.quote",
			@"key":		   @"number",
			@"username":	  @"at",
			@"users":		 @"person.2",
			@"lock":		  @"lock",
			@"unlock":		@"lock.open",
			@"profile":	   @"person.crop.circle",

			// Media
			@"photo":		 @"photo",
			@"photo_filled":  @"photo.fill",
			@"video":		 @"video",
			@"video_filled":  @"video.fill",
			@"media":		 @"photo.on.rectangle",
			@"media_empty":   @"photo.on.rectangle.angled",
			@"photo_gallery": @"photo.on.rectangle.angled",

			// Sources
			@"feed":		  @"rectangle.stack",
			@"story":		 @"circle.dashed",
			@"stories":	   @"circle.dashed",
			@"reels":		 @"film.stack",
			@"reel":		  @"film",
			@"messages":	  @"bubble.left.and.bubble.right",
			@"green_screen":  @"person.fill.viewfinder",

			// Actions
			@"share":		 @"square.and.arrow.up",
			@"download":	  @"square.and.arrow.down",
			@"download_filled": @"square.and.arrow.down.fill",
			@"trash":		 @"trash",
			@"delete":		@"trash",
			@"folder":		@"folder",
			@"folder_move":   @"folder.badge.gearshape",
			@"heart":		 @"heart",
			@"heart_filled":  @"heart.fill",
			@"favorite":	  @"star",
			@"favorite_filled": @"star.fill",
			@"search":		@"magnifyingglass",
			@"filter":		@"line.3.horizontal.decrease.circle",
			@"sort":		  @"arrow.up.arrow.down",
			@"size_large":	@"arrow.up.arrow.down",
			@"size_small":	@"arrow.down.arrow.up",
			@"calendar":	  @"calendar",
			@"list":		  @"list.bullet",
			@"grid":		  @"square.grid.2x2",

			// Status
			@"error_filled":  @"exclamationmark.triangle.fill",
			@"info":		  @"info.circle",

			// Misc
			@"edit":			  @"pencil",
			@"circle_check_filled": @"checkmark.circle.fill",
			@"save":			  @"square.and.arrow.down",
			@"add":			   @"plus",
			@"plus":			  @"plus",
			@"close":			 @"xmark",
		};
	});
	return map[name];
}

static UIImage *RYGResolvedSFImage(NSString *name, CGFloat pointSize, UIImageSymbolWeight weight) {
	NSString *ig = RYGIGForName(name);
	if (ig.length) {
		UIImage *img = [RYGIcon menuImageNamed:ig pointSize:pointSize];
		if (img) return img;
	}
	if ([RYGIcon isIGAssetName:name]) {
		UIImage *img = [RYGIcon menuImageNamed:name pointSize:pointSize];
		if (img) return img;
	}
	NSString *sf = RYGSFForIGName(name);
	if (sf.length) {
		UIImage *img = [RYGIcon sfImageNamed:sf pointSize:pointSize weight:weight];
		if (img) return img;
	}
	// Treat the input as already-an-SF-symbol (e.g. "lock.fill").
	UIImage *direct = [RYGIcon sfImageNamed:name pointSize:pointSize weight:weight];
	if (direct) return direct;
	// Last resort: hybrid resolver (FB asset / bundle / SF).
	return [RYGIcon imageNamed:name pointSize:pointSize weight:weight];
}

@implementation RYGAssetUtils

+ (UIImage *)selectionCheckmarkSelected:(BOOL)selected pointSize:(CGFloat)pointSize {
	if (selected) return [RYGIcon sfImageNamed:@"checkmark" pointSize:pointSize weight:UIImageSymbolWeightBold];
	return [self instagramIconNamed:@"circle" pointSize:pointSize];
}

+ (UIImage *)instagramIconNamed:(NSString *)name {
	return [self instagramIconNamed:name pointSize:17.0];
}

+ (UIImage *)instagramIconNamed:(NSString *)name pointSize:(CGFloat)pointSize {
	return RYGResolvedSFImage(name, pointSize, UIImageSymbolWeightRegular);
}

+ (UIImage *)instagramIconNamed:(NSString *)name pointSize:(CGFloat)pointSize renderingMode:(UIImageRenderingMode)renderingMode {
	UIImage *img = RYGResolvedSFImage(name, pointSize, UIImageSymbolWeightRegular);
	return [img imageWithRenderingMode:renderingMode];
}

+ (UIImage *)instagramIconNamed:(NSString *)name pointSize:(CGFloat)pointSize source:(RYGAssetCatalogSource)source {
	return RYGResolvedSFImage(name, pointSize, UIImageSymbolWeightRegular);
}

+ (UIImage *)instagramIconNamed:(NSString *)name pointSize:(CGFloat)pointSize source:(RYGAssetCatalogSource)source renderingMode:(UIImageRenderingMode)renderingMode {
	UIImage *img = RYGResolvedSFImage(name, pointSize, UIImageSymbolWeightRegular);
	return [img imageWithRenderingMode:renderingMode];
}

+ (UIImage *)resolvedImageNamed:(NSString *)name pointSize:(CGFloat)pointSize weight:(UIImageSymbolWeight)weight source:(RYGResolvedImageSource)source renderingMode:(UIImageRenderingMode)renderingMode {
	if (!name.length) return nil;
	UIImage *img = (source == RYGResolvedImageSourceSystemSymbol)
		? [RYGIcon sfImageNamed:name pointSize:pointSize weight:weight]
		: RYGResolvedSFImage(name, pointSize, weight);
	return [img imageWithRenderingMode:renderingMode];
}

+ (UIImage *)resolvedImageNamed:(NSString *)name fallbackSystemName:(NSString *)fallbackSystemName pointSize:(CGFloat)pointSize weight:(UIImageSymbolWeight)weight source:(RYGResolvedImageSource)source renderingMode:(UIImageRenderingMode)renderingMode {
	UIImage *img = name.length ? RYGResolvedSFImage(name, pointSize, weight) : nil;
	if (!img && fallbackSystemName.length) {
		img = [RYGIcon sfImageNamed:fallbackSystemName pointSize:pointSize weight:weight];
	}
	return [img imageWithRenderingMode:renderingMode];
}

@end
