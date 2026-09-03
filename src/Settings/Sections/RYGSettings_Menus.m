#import "RYGSettingsSections.h"

@implementation RYGTweakSettings (Section_Menus)

// MARK: - Menus

#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wundeclared-selector"

// Order: actions first, downloads last.
+ (UIMenu *)defaultTapMenuForKey:(NSString *)key context:(NSString *)ctx {
	// { value, title, contexts (csv of feed,reels,stories,dm_visual,all) }
	NSArray *entries = @[
		@[@"menu",		   RYGLocalized(@"Open menu"),		  @"all"],
		@[@"expand",		 RYGLocalized(@"Expand"),			 @"all"],
		@[@"repost",		 RYGLocalized(@"Repost"),			 @"feed,reels,stories"],
		@[@"view_mentions",  RYGLocalized(@"View mentions"),	  @"stories"],
		@[@"copy_link",	  RYGLocalized(@"Copy download URL"),  @"feed,reels,stories"],
		@[@"download_share", RYGLocalized(@"Download and share"), @"all"],
		@[@"download_photos",RYGLocalized(@"Download to Photos"), @"all"],
	];
	NSMutableArray *children = [NSMutableArray array];
	for (NSArray *e in entries) {
		NSString *contexts = e[2];
		if (![contexts isEqualToString:@"all"] && ![contexts containsString:ctx]) continue;
		[children addObject:[UICommand commandWithTitle:e[1] image:nil
												 action:@selector(menuChanged:)
										   propertyList:@{@"defaultsKey": key, @"value": e[0]}]];
	}
	return [UIMenu menuWithChildren:children];
}

+ (UIMenu *)activityModeMenu:(NSString *)key {
	NSArray<NSArray<NSString *> *> *opts = @[
		@[@"off",        RYGLocalized(@"Off")],
		@[@"log",        RYGLocalized(@"Log only")],
		@[@"notify",     RYGLocalized(@"Notify only")],
		@[@"notify_log", RYGLocalized(@"Notify + log")],
	];
	NSMutableArray *children = [NSMutableArray array];
	for (NSArray *o in opts)
		[children addObject:[UICommand commandWithTitle:o[1] image:nil action:@selector(menuChanged:)
										   propertyList:@{ @"defaultsKey": key, @"value": o[0] }]];
	return [UIMenu menuWithChildren:children];
}

+ (NSDictionary *)menus {
	return @{
		@"gallery_save_mode": [UIMenu menuWithChildren:@[
			[UICommand commandWithTitle:RYGLocalized(@"Photos only")
									image:nil
									action:@selector(menuChanged:)
							propertyList:@{ @"defaultsKey": @"gallery_save_mode", @"value": @"off" }
			],
			[UICommand commandWithTitle:RYGLocalized(@"Photos + Gallery")
									image:nil
									action:@selector(menuChanged:)
							propertyList:@{ @"defaultsKey": @"gallery_save_mode", @"value": @"mirror" }
			],
			[UICommand commandWithTitle:RYGLocalized(@"Gallery only")
									image:nil
									action:@selector(menuChanged:)
							propertyList:@{ @"defaultsKey": @"gallery_save_mode", @"value": @"gallery_only" }
			]
		]],

		@"instants_auto_save": [UIMenu menuWithChildren:@[
			[UICommand commandWithTitle:RYGLocalized(@"Off")
									image:nil
									action:@selector(menuChanged:)
							propertyList:@{ @"defaultsKey": @"instants_auto_save", @"value": @"off" }
			],
			[UICommand commandWithTitle:RYGLocalized(@"Save to Photos")
									image:nil
									action:@selector(menuChanged:)
							propertyList:@{ @"defaultsKey": @"instants_auto_save", @"value": @"photos" }
			],
			[UICommand commandWithTitle:RYGLocalized(@"Save to Gallery")
									image:nil
									action:@selector(menuChanged:)
							propertyList:@{ @"defaultsKey": @"instants_auto_save", @"value": @"gallery" }
			]
		]],

		@"theme_mode": [UIMenu menuWithChildren:@[
			[UICommand commandWithTitle:RYGLocalized(@"Off")
									image:nil
									action:@selector(menuChanged:)
							propertyList:@{ @"defaultsKey": @"theme_mode", @"value": @"off" }
			],
			[UICommand commandWithTitle:RYGLocalized(@"Light")
									image:nil
									action:@selector(menuChanged:)
							propertyList:@{ @"defaultsKey": @"theme_mode", @"value": @"light" }
			],
			[UICommand commandWithTitle:RYGLocalized(@"Dark")
									image:nil
									action:@selector(menuChanged:)
							propertyList:@{ @"defaultsKey": @"theme_mode", @"value": @"dark" }
			],
			[UICommand commandWithTitle:RYGLocalized(@"OLED")
									image:nil
									action:@selector(menuChanged:)
							propertyList:@{ @"defaultsKey": @"theme_mode", @"value": @"oled" }
			]
		]],

		@"theme_keyboard": [UIMenu menuWithChildren:@[
			[UICommand commandWithTitle:RYGLocalized(@"Off")
									image:nil
									action:@selector(menuChanged:)
							propertyList:@{ @"defaultsKey": @"theme_keyboard", @"value": @"off" }
			],
			[UICommand commandWithTitle:RYGLocalized(@"Dark")
									image:nil
									action:@selector(menuChanged:)
							propertyList:@{ @"defaultsKey": @"theme_keyboard", @"value": @"dark" }
			],
			[UICommand commandWithTitle:RYGLocalized(@"OLED")
									image:nil
									action:@selector(menuChanged:)
							propertyList:@{ @"defaultsKey": @"theme_keyboard", @"value": @"oled" }
			]
		]],

		@"chat_blocking_mode": [UIMenu menuWithChildren:@[
			[UICommand commandWithTitle:RYGLocalized(@"Block all")
									image:nil
									action:@selector(menuChanged:)
							propertyList:@{ @"defaultsKey": @"chat_blocking_mode", @"value": @"block_all" }
			],
			[UICommand commandWithTitle:RYGLocalized(@"Block selected")
									image:nil
									action:@selector(menuChanged:)
							propertyList:@{ @"defaultsKey": @"chat_blocking_mode", @"value": @"block_selected" }
			]
		]],

		@"follow_indicator": [UIMenu menuWithChildren:@[
			[UICommand commandWithTitle:RYGLocalized(@"Off")
								  image:nil
								 action:@selector(menuChanged:)
						   propertyList:@{ @"defaultsKey": @"follow_indicator", @"value": @"off" }],
			[UICommand commandWithTitle:RYGLocalized(@"On")
								  image:nil
								 action:@selector(menuChanged:)
						   propertyList:@{ @"defaultsKey": @"follow_indicator", @"value": @"on" }],
			[UICommand commandWithTitle:RYGLocalized(@"Colored")
								  image:nil
								 action:@selector(menuChanged:)
						   propertyList:@{ @"defaultsKey": @"follow_indicator", @"value": @"colored" }]
		]],

		@"follow_indicator_lists": [UIMenu menuWithChildren:@[
			[UICommand commandWithTitle:RYGLocalized(@"Off")
								  image:nil
								 action:@selector(menuChanged:)
						   propertyList:@{ @"defaultsKey": @"follow_indicator_lists", @"value": @"off" }],
			[UICommand commandWithTitle:RYGLocalized(@"On")
								  image:nil
								 action:@selector(menuChanged:)
						   propertyList:@{ @"defaultsKey": @"follow_indicator_lists", @"value": @"on" }],
			[UICommand commandWithTitle:RYGLocalized(@"Colored")
								  image:nil
								 action:@selector(menuChanged:)
						   propertyList:@{ @"defaultsKey": @"follow_indicator_lists", @"value": @"colored" }]
		]],

		@"follow_requests_check_interval": [UIMenu menuWithChildren:@[
			[UICommand commandWithTitle:RYGLocalized(@"Off (manual only)") image:nil action:@selector(menuChanged:)
						   propertyList:@{ @"defaultsKey": @"follow_requests_check_interval", @"value": @"0" }],
			[UICommand commandWithTitle:RYGLocalized(@"Every 15 minutes") image:nil action:@selector(menuChanged:)
						   propertyList:@{ @"defaultsKey": @"follow_requests_check_interval", @"value": @"900" }],
			[UICommand commandWithTitle:RYGLocalized(@"Every 30 minutes") image:nil action:@selector(menuChanged:)
						   propertyList:@{ @"defaultsKey": @"follow_requests_check_interval", @"value": @"1800" }],
			[UICommand commandWithTitle:RYGLocalized(@"Every hour") image:nil action:@selector(menuChanged:)
						   propertyList:@{ @"defaultsKey": @"follow_requests_check_interval", @"value": @"3600" }],
			[UICommand commandWithTitle:RYGLocalized(@"Every 6 hours") image:nil action:@selector(menuChanged:)
						   propertyList:@{ @"defaultsKey": @"follow_requests_check_interval", @"value": @"21600" }],
		]],

		@"story_blocking_mode": [UIMenu menuWithChildren:@[
			[UICommand commandWithTitle:RYGLocalized(@"Block all")
									image:nil
									action:@selector(menuChanged:)
							propertyList:@{ @"defaultsKey": @"story_blocking_mode", @"value": @"block_all" }
			],
			[UICommand commandWithTitle:RYGLocalized(@"Block selected")
									image:nil
									action:@selector(menuChanged:)
							propertyList:@{ @"defaultsKey": @"story_blocking_mode", @"value": @"block_selected" }
			]
		]],

		@"sticker_interact_stories_mode": [UIMenu menuWithChildren:@[
			[UICommand commandWithTitle:RYGLocalized(@"Disabled")
								  image:nil
								 action:@selector(menuChanged:)
						   propertyList:@{ @"defaultsKey": @"sticker_interact_stories_mode", @"value": @"off" }],
			[UICommand commandWithTitle:RYGLocalized(@"All")
								  image:nil
								 action:@selector(menuChanged:)
						   propertyList:@{ @"defaultsKey": @"sticker_interact_stories_mode", @"value": @"all" }],
			[UICommand commandWithTitle:RYGLocalized(@"Reaction stickers only")
								  image:nil
								 action:@selector(menuChanged:)
						   propertyList:@{ @"defaultsKey": @"sticker_interact_stories_mode", @"value": @"reactions" }]
		]],

		@"sticker_interact_highlights_mode": [UIMenu menuWithChildren:@[
			[UICommand commandWithTitle:RYGLocalized(@"Disabled")
								  image:nil
								 action:@selector(menuChanged:)
						   propertyList:@{ @"defaultsKey": @"sticker_interact_highlights_mode", @"value": @"off" }],
			[UICommand commandWithTitle:RYGLocalized(@"All")
								  image:nil
								 action:@selector(menuChanged:)
						   propertyList:@{ @"defaultsKey": @"sticker_interact_highlights_mode", @"value": @"all" }],
			[UICommand commandWithTitle:RYGLocalized(@"Reaction stickers only")
								  image:nil
								 action:@selector(menuChanged:)
						   propertyList:@{ @"defaultsKey": @"sticker_interact_highlights_mode", @"value": @"reactions" }]
		]],

		@"dm_reaction_confirm_mode": [UIMenu menuWithChildren:@[
			[UICommand commandWithTitle:RYGLocalized(@"Disabled")
								  image:nil
								 action:@selector(menuChanged:)
						   propertyList:@{ @"defaultsKey": @"dm_reaction_confirm_mode", @"value": @"off" }],
			[UICommand commandWithTitle:RYGLocalized(@"Double tap only")
								  image:nil
								 action:@selector(menuChanged:)
						   propertyList:@{ @"defaultsKey": @"dm_reaction_confirm_mode", @"value": @"double_tap" }],
			[UICommand commandWithTitle:RYGLocalized(@"All")
								  image:nil
								 action:@selector(menuChanged:)
						   propertyList:@{ @"defaultsKey": @"dm_reaction_confirm_mode", @"value": @"all" }]
		]],

		@"messages_only_schedule_apply": [UIMenu menuWithChildren:@[
			[UICommand commandWithTitle:RYGLocalized(@"Apply instantly")
								  image:nil
								 action:@selector(menuChanged:)
						   propertyList:@{ @"defaultsKey": @"messages_only_schedule_apply", @"value": @"live" }],
			[UICommand commandWithTitle:RYGLocalized(@"Always ask")
								  image:nil
								 action:@selector(menuChanged:)
						   propertyList:@{ @"defaultsKey": @"messages_only_schedule_apply", @"value": @"ask" }]
		]],

		@"story_seen_mode": [UIMenu menuWithChildren:@[
			[UICommand commandWithTitle:RYGLocalized(@"Button")
									image:nil
									action:@selector(menuChanged:)
							propertyList:@{
								@"defaultsKey": @"story_seen_mode",
								@"value": @"button"
							}
			],
			[UICommand commandWithTitle:RYGLocalized(@"Toggle")
									image:nil
									action:@selector(menuChanged:)
							propertyList:@{
								@"defaultsKey": @"story_seen_mode",
								@"value": @"toggle"
							}
			]
		]],

		@"unsent_indicator_position": [UIMenu menuWithChildren:@[
			[UICommand commandWithTitle:RYGLocalized(@"Beside the bubble") image:nil action:@selector(menuChanged:)
						   propertyList:@{ @"defaultsKey": @"unsent_indicator_position", @"value": @"side" }],
			[UICommand commandWithTitle:RYGLocalized(@"Above the bubble") image:nil action:@selector(menuChanged:)
						   propertyList:@{ @"defaultsKey": @"unsent_indicator_position", @"value": @"above" }],
			[UICommand commandWithTitle:RYGLocalized(@"Below the bubble") image:nil action:@selector(menuChanged:)
						   propertyList:@{ @"defaultsKey": @"unsent_indicator_position", @"value": @"below" }]
		]],

		@"story_seen_marked_indicator": [UIMenu menuWithChildren:@[
			[UICommand commandWithTitle:RYGLocalized(@"Off") image:nil action:@selector(menuChanged:)
						   propertyList:@{ @"defaultsKey": @"story_seen_marked_indicator", @"value": @"off" }],
			[UICommand commandWithTitle:RYGLocalized(@"Hide eye button") image:nil action:@selector(menuChanged:)
						   propertyList:@{ @"defaultsKey": @"story_seen_marked_indicator", @"value": @"hide" }],
			[UICommand commandWithTitle:RYGLocalized(@"Fill eye button green") image:nil action:@selector(menuChanged:)
						   propertyList:@{ @"defaultsKey": @"story_seen_marked_indicator", @"value": @"tint" }]
		]],

		@"stories_archive_viewer_refresh": [UIMenu menuWithChildren:@[
			[UICommand commandWithTitle:RYGLocalized(@"On each launch") image:nil action:@selector(menuChanged:)
						   propertyList:@{ @"defaultsKey": @"ryg_stories_archive_viewer_refresh", @"value": @"launch" }],
			[UICommand commandWithTitle:RYGLocalized(@"Every 15 minutes") image:nil action:@selector(menuChanged:)
						   propertyList:@{ @"defaultsKey": @"ryg_stories_archive_viewer_refresh", @"value": @"15m" }],
			[UICommand commandWithTitle:RYGLocalized(@"Every hour") image:nil action:@selector(menuChanged:)
						   propertyList:@{ @"defaultsKey": @"ryg_stories_archive_viewer_refresh", @"value": @"1h" }],
			[UICommand commandWithTitle:RYGLocalized(@"Every 6 hours") image:nil action:@selector(menuChanged:)
						   propertyList:@{ @"defaultsKey": @"ryg_stories_archive_viewer_refresh", @"value": @"6h" }],
		]],

		@"call_audio_source": [UIMenu menuWithChildren:@[
			[UICommand commandWithTitle:RYGLocalized(@"Both sides") image:nil action:@selector(menuChanged:)
						   propertyList:@{ @"defaultsKey": @"call_recordings_audio", @"value": @"both" }],
			[UICommand commandWithTitle:RYGLocalized(@"Only me") image:nil action:@selector(menuChanged:)
						   propertyList:@{ @"defaultsKey": @"call_recordings_audio", @"value": @"mine" }],
			[UICommand commandWithTitle:RYGLocalized(@"Only them") image:nil action:@selector(menuChanged:)
						   propertyList:@{ @"defaultsKey": @"call_recordings_audio", @"value": @"theirs" }],
		]],

		@"call_pip_full": [UIMenu menuWithChildren:@[
			[UICommand commandWithTitle:RYGLocalized(@"Them") image:nil action:@selector(menuChanged:)
						   propertyList:@{ @"defaultsKey": @"call_recordings_pip_full", @"value": @"remote" }],
			[UICommand commandWithTitle:RYGLocalized(@"You") image:nil action:@selector(menuChanged:)
						   propertyList:@{ @"defaultsKey": @"call_recordings_pip_full", @"value": @"self" }],
		]],

		@"call_pip_size": [UIMenu menuWithChildren:@[
			[UICommand commandWithTitle:RYGLocalized(@"Small") image:nil action:@selector(menuChanged:)
						   propertyList:@{ @"defaultsKey": @"call_recordings_pip_size", @"value": @"small" }],
			[UICommand commandWithTitle:RYGLocalized(@"Medium") image:nil action:@selector(menuChanged:)
						   propertyList:@{ @"defaultsKey": @"call_recordings_pip_size", @"value": @"medium" }],
			[UICommand commandWithTitle:RYGLocalized(@"Large") image:nil action:@selector(menuChanged:)
						   propertyList:@{ @"defaultsKey": @"call_recordings_pip_size", @"value": @"large" }],
		]],

		@"call_retention": [UIMenu menuWithChildren:@[
			[UICommand commandWithTitle:RYGLocalized(@"Keep forever") image:nil action:@selector(menuChanged:)
						   propertyList:@{ @"defaultsKey": @"call_recordings_retention", @"value": @"0" }],
			[UICommand commandWithTitle:RYGLocalized(@"7 days") image:nil action:@selector(menuChanged:)
						   propertyList:@{ @"defaultsKey": @"call_recordings_retention", @"value": @"7" }],
			[UICommand commandWithTitle:RYGLocalized(@"30 days") image:nil action:@selector(menuChanged:)
						   propertyList:@{ @"defaultsKey": @"call_recordings_retention", @"value": @"30" }],
			[UICommand commandWithTitle:RYGLocalized(@"90 days") image:nil action:@selector(menuChanged:)
						   propertyList:@{ @"defaultsKey": @"call_recordings_retention", @"value": @"90" }],
		]],

		@"dl_history_retention": [UIMenu menuWithChildren:@[
			[UICommand commandWithTitle:RYGLocalized(@"Don't keep") image:nil action:@selector(menuChanged:)
						   propertyList:@{ @"defaultsKey": @"dl_history_retention", @"value": @"off" }],
			[UICommand commandWithTitle:RYGLocalized(@"12 hours") image:nil action:@selector(menuChanged:)
						   propertyList:@{ @"defaultsKey": @"dl_history_retention", @"value": @"12" }],
			[UICommand commandWithTitle:RYGLocalized(@"24 hours") image:nil action:@selector(menuChanged:)
						   propertyList:@{ @"defaultsKey": @"dl_history_retention", @"value": @"24" }],
			[UICommand commandWithTitle:RYGLocalized(@"48 hours") image:nil action:@selector(menuChanged:)
						   propertyList:@{ @"defaultsKey": @"dl_history_retention", @"value": @"48" }],
			[UICommand commandWithTitle:RYGLocalized(@"7 days") image:nil action:@selector(menuChanged:)
						   propertyList:@{ @"defaultsKey": @"dl_history_retention", @"value": @"168" }],
			[UICommand commandWithTitle:RYGLocalized(@"30 days") image:nil action:@selector(menuChanged:)
						   propertyList:@{ @"defaultsKey": @"dl_history_retention", @"value": @"720" }],
			[UICommand commandWithTitle:RYGLocalized(@"Keep forever") image:nil action:@selector(menuChanged:)
						   propertyList:@{ @"defaultsKey": @"dl_history_retention", @"value": @"forever" }],
		]],

		@"seen_mode": [UIMenu menuWithChildren:@[
			[UICommand commandWithTitle:RYGLocalized(@"Button")
									image:nil
									action:@selector(menuChanged:)
							propertyList:@{
								@"defaultsKey": @"seen_mode",
								@"value": @"button"
							}
			],
			[UICommand commandWithTitle:RYGLocalized(@"Toggle")
									image:nil
									action:@selector(menuChanged:)
							propertyList:@{
								@"defaultsKey": @"seen_mode",
								@"value": @"toggle"
							}
			]
		]],

		@"dw_save_action": ({
			NSMutableArray *_dwItems = [NSMutableArray array];
			[_dwItems addObject:[UICommand commandWithTitle:RYGLocalized(@"Share sheet")
									image:nil
									action:@selector(menuChanged:)
							propertyList:@{
								@"defaultsKey": @"dw_save_action",
								@"value": @"share"
							}
			]];
			[_dwItems addObject:[UICommand commandWithTitle:RYGLocalized(@"Save to Photos")
									image:nil
									action:@selector(menuChanged:)
							propertyList:@{
								@"defaultsKey": @"dw_save_action",
								@"value": @"photos"
							}
			]];
			if ([RYGUtils getBoolPref:@"ryg_gallery_enabled"]) {
				[_dwItems addObject:[UICommand commandWithTitle:RYGLocalized(@"Save to Gallery")
										image:nil
										action:@selector(menuChanged:)
								propertyList:@{
									@"defaultsKey": @"dw_save_action",
									@"value": @"gallery"
								}
				]];
			}
			[UIMenu menuWithChildren:_dwItems];
		}),

		@"feed_action_default":	[self defaultTapMenuForKey:@"feed_action_default"	context:@"feed"],
		@"reels_action_default":   [self defaultTapMenuForKey:@"reels_action_default"   context:@"reels"],
		@"stories_action_default": [self defaultTapMenuForKey:@"stories_action_default" context:@"stories"],
		@"dm_visual_action_default": [self defaultTapMenuForKey:@"dm_visual_action_default" context:@"dm_visual"],
		@"dm_log_date_format": [UIMenu menuWithChildren:@[
			[UICommand commandWithTitle:RYGLocalized(@"Relative (1m / 3h / 3d ago)") image:nil action:@selector(menuChanged:)
						   propertyList:@{@"defaultsKey": @"dm_log_date_format", @"value": @"relative"}],
			[UICommand commandWithTitle:RYGLocalized(@"Absolute date + time") image:nil action:@selector(menuChanged:)
						   propertyList:@{@"defaultsKey": @"dm_log_date_format", @"value": @"absolute"}],
		]],
		@"main_feed_mode": [UIMenu menuWithChildren:@[
			[UICommand commandWithTitle:RYGLocalized(@"Default") image:nil action:@selector(menuChanged:)
						   propertyList:@{@"defaultsKey": @"main_feed_mode", @"value": @"default", @"requiresRestart": @YES}],
			[UICommand commandWithTitle:RYGLocalized(@"Following") image:nil action:@selector(menuChanged:)
						   propertyList:@{@"defaultsKey": @"main_feed_mode", @"value": @"following", @"requiresRestart": @YES}],
		]],
		@"feed_reel_tap": [UIMenu menuWithChildren:@[
			[UICommand commandWithTitle:RYGLocalized(@"Default") image:nil action:@selector(menuChanged:)
						   propertyList:@{@"defaultsKey": @"feed_reel_tap", @"value": @"default", @"requiresRestart": @YES}],
			[UICommand commandWithTitle:RYGLocalized(@"Play in place") image:nil action:@selector(menuChanged:)
						   propertyList:@{@"defaultsKey": @"feed_reel_tap", @"value": @"inline", @"requiresRestart": @YES}],
			[UICommand commandWithTitle:RYGLocalized(@"Play, then open") image:nil action:@selector(menuChanged:)
						   propertyList:@{@"defaultsKey": @"feed_reel_tap", @"value": @"double", @"requiresRestart": @YES}],
		]],
		@"feed_statusbar_tap": [UIMenu menuWithChildren:@[
			[UICommand commandWithTitle:RYGLocalized(@"Default") image:nil action:@selector(menuChanged:)
						   propertyList:@{@"defaultsKey": @"feed_statusbar_tap", @"value": @"default"}],
			[UICommand commandWithTitle:RYGLocalized(@"Scroll only") image:nil action:@selector(menuChanged:)
						   propertyList:@{@"defaultsKey": @"feed_statusbar_tap", @"value": @"scroll", @"requiresRestart": @YES}],
			[UICommand commandWithTitle:RYGLocalized(@"Disabled") image:nil action:@selector(menuChanged:)
						   propertyList:@{@"defaultsKey": @"feed_statusbar_tap", @"value": @"off", @"requiresRestart": @YES}],
		]],
		@"liquid_glass_tabbar_mode": [UIMenu menuWithChildren:@[
			[UICommand commandWithTitle:RYGLocalized(@"Default") image:nil action:@selector(menuChanged:)
						   propertyList:@{@"defaultsKey": @"liquid_glass_tabbar_mode", @"value": @"default", @"requiresRestart": @YES}],
			[UICommand commandWithTitle:RYGLocalized(@"Fixed") image:nil action:@selector(menuChanged:)
						   propertyList:@{@"defaultsKey": @"liquid_glass_tabbar_mode", @"value": @"fixed", @"requiresRestart": @YES}],
			[UICommand commandWithTitle:RYGLocalized(@"Hide on scroll") image:nil action:@selector(menuChanged:)
						   propertyList:@{@"defaultsKey": @"liquid_glass_tabbar_mode", @"value": @"hide", @"requiresRestart": @YES}],
		]],

		@"default_video_quality": [UIMenu menuWithChildren:@[
			[UICommand commandWithTitle:RYGLocalized(@"Always ask") image:nil action:@selector(menuChanged:)
						   propertyList:@{@"defaultsKey": @"default_video_quality", @"value": @"always_ask"}],
			[UICommand commandWithTitle:RYGLocalized(@"High") image:nil action:@selector(menuChanged:)
						   propertyList:@{@"defaultsKey": @"default_video_quality", @"value": @"high"}],
			[UICommand commandWithTitle:RYGLocalized(@"Medium") image:nil action:@selector(menuChanged:)
						   propertyList:@{@"defaultsKey": @"default_video_quality", @"value": @"medium"}],
			[UICommand commandWithTitle:RYGLocalized(@"Low") image:nil action:@selector(menuChanged:)
						   propertyList:@{@"defaultsKey": @"default_video_quality", @"value": @"low"}],
		]],
		@"default_photo_quality": [UIMenu menuWithChildren:@[
			[UICommand commandWithTitle:RYGLocalized(@"High") image:nil action:@selector(menuChanged:)
						   propertyList:@{@"defaultsKey": @"default_photo_quality", @"value": @"high"}],
			[UICommand commandWithTitle:RYGLocalized(@"Standard") image:nil action:@selector(menuChanged:)
						   propertyList:@{@"defaultsKey": @"default_photo_quality", @"value": @"standard"}],
		]],
		@"ffmpeg_encoding_speed": [UIMenu menuWithChildren:@[
			[UICommand commandWithTitle:RYGLocalized(@"Fast") image:nil action:@selector(menuChanged:)
						   propertyList:@{@"defaultsKey": @"ffmpeg_encoding_speed", @"value": @"ultrafast"}],
			[UICommand commandWithTitle:RYGLocalized(@"Balanced") image:nil action:@selector(menuChanged:)
						   propertyList:@{@"defaultsKey": @"ffmpeg_encoding_speed", @"value": @"veryfast"}],
			[UICommand commandWithTitle:RYGLocalized(@"Quality") image:nil action:@selector(menuChanged:)
						   propertyList:@{@"defaultsKey": @"ffmpeg_encoding_speed", @"value": @"fast"}],
			[UICommand commandWithTitle:RYGLocalized(@"Max") image:nil action:@selector(menuChanged:)
						   propertyList:@{@"defaultsKey": @"ffmpeg_encoding_speed", @"value": @"max"}],
		]],

		@"adv_video_codec": [UIMenu menuWithChildren:@[
			[UICommand commandWithTitle:RYGLocalized(@"Hardware (VideoToolbox)") image:nil action:@selector(menuChanged:)
						   propertyList:@{@"defaultsKey": @"adv_video_codec", @"value": @"h264_videotoolbox"}],
			[UICommand commandWithTitle:RYGLocalized(@"Software (libx264)") image:nil action:@selector(menuChanged:)
						   propertyList:@{@"defaultsKey": @"adv_video_codec", @"value": @"libx264"}],
		]],
		@"adv_preset": [UIMenu menuWithChildren:@[
			[UICommand commandWithTitle:@"ultrafast" image:nil action:@selector(menuChanged:) propertyList:@{@"defaultsKey": @"adv_preset", @"value": @"ultrafast"}],
			[UICommand commandWithTitle:@"superfast" image:nil action:@selector(menuChanged:) propertyList:@{@"defaultsKey": @"adv_preset", @"value": @"superfast"}],
			[UICommand commandWithTitle:@"veryfast"  image:nil action:@selector(menuChanged:) propertyList:@{@"defaultsKey": @"adv_preset", @"value": @"veryfast"}],
			[UICommand commandWithTitle:@"faster"    image:nil action:@selector(menuChanged:) propertyList:@{@"defaultsKey": @"adv_preset", @"value": @"faster"}],
			[UICommand commandWithTitle:@"fast"      image:nil action:@selector(menuChanged:) propertyList:@{@"defaultsKey": @"adv_preset", @"value": @"fast"}],
			[UICommand commandWithTitle:@"medium"    image:nil action:@selector(menuChanged:) propertyList:@{@"defaultsKey": @"adv_preset", @"value": @"medium"}],
			[UICommand commandWithTitle:@"slow"      image:nil action:@selector(menuChanged:) propertyList:@{@"defaultsKey": @"adv_preset", @"value": @"slow"}],
			[UICommand commandWithTitle:@"slower"    image:nil action:@selector(menuChanged:) propertyList:@{@"defaultsKey": @"adv_preset", @"value": @"slower"}],
			[UICommand commandWithTitle:@"veryslow"  image:nil action:@selector(menuChanged:) propertyList:@{@"defaultsKey": @"adv_preset", @"value": @"veryslow"}],
			[UICommand commandWithTitle:@"placebo"   image:nil action:@selector(menuChanged:) propertyList:@{@"defaultsKey": @"adv_preset", @"value": @"placebo"}],
		]],
		@"adv_h264_profile": [UIMenu menuWithChildren:@[
			[UICommand commandWithTitle:@"baseline" image:nil action:@selector(menuChanged:) propertyList:@{@"defaultsKey": @"adv_h264_profile", @"value": @"baseline"}],
			[UICommand commandWithTitle:@"main"     image:nil action:@selector(menuChanged:) propertyList:@{@"defaultsKey": @"adv_h264_profile", @"value": @"main"}],
			[UICommand commandWithTitle:@"high"     image:nil action:@selector(menuChanged:) propertyList:@{@"defaultsKey": @"adv_h264_profile", @"value": @"high"}],
			[UICommand commandWithTitle:@"high10"   image:nil action:@selector(menuChanged:) propertyList:@{@"defaultsKey": @"adv_h264_profile", @"value": @"high10"}],
			[UICommand commandWithTitle:@"high422"  image:nil action:@selector(menuChanged:) propertyList:@{@"defaultsKey": @"adv_h264_profile", @"value": @"high422"}],
			[UICommand commandWithTitle:@"high444"  image:nil action:@selector(menuChanged:) propertyList:@{@"defaultsKey": @"adv_h264_profile", @"value": @"high444"}],
		]],
		@"adv_h264_level": [UIMenu menuWithChildren:@[
			[UICommand commandWithTitle:RYGLocalized(@"Auto") image:nil action:@selector(menuChanged:) propertyList:@{@"defaultsKey": @"adv_h264_level", @"value": @"auto"}],
			[UICommand commandWithTitle:@"3.0" image:nil action:@selector(menuChanged:) propertyList:@{@"defaultsKey": @"adv_h264_level", @"value": @"3.0"}],
			[UICommand commandWithTitle:@"3.1" image:nil action:@selector(menuChanged:) propertyList:@{@"defaultsKey": @"adv_h264_level", @"value": @"3.1"}],
			[UICommand commandWithTitle:@"3.2" image:nil action:@selector(menuChanged:) propertyList:@{@"defaultsKey": @"adv_h264_level", @"value": @"3.2"}],
			[UICommand commandWithTitle:@"4.0" image:nil action:@selector(menuChanged:) propertyList:@{@"defaultsKey": @"adv_h264_level", @"value": @"4.0"}],
			[UICommand commandWithTitle:@"4.1" image:nil action:@selector(menuChanged:) propertyList:@{@"defaultsKey": @"adv_h264_level", @"value": @"4.1"}],
			[UICommand commandWithTitle:@"4.2" image:nil action:@selector(menuChanged:) propertyList:@{@"defaultsKey": @"adv_h264_level", @"value": @"4.2"}],
			[UICommand commandWithTitle:@"5.0" image:nil action:@selector(menuChanged:) propertyList:@{@"defaultsKey": @"adv_h264_level", @"value": @"5.0"}],
			[UICommand commandWithTitle:@"5.1" image:nil action:@selector(menuChanged:) propertyList:@{@"defaultsKey": @"adv_h264_level", @"value": @"5.1"}],
			[UICommand commandWithTitle:@"5.2" image:nil action:@selector(menuChanged:) propertyList:@{@"defaultsKey": @"adv_h264_level", @"value": @"5.2"}],
		]],
		@"adv_max_resolution": [UIMenu menuWithChildren:@[
			[UICommand commandWithTitle:RYGLocalized(@"Original") image:nil action:@selector(menuChanged:) propertyList:@{@"defaultsKey": @"adv_max_resolution", @"value": @"original"}],
			[UICommand commandWithTitle:@"2160p (4K)" image:nil action:@selector(menuChanged:) propertyList:@{@"defaultsKey": @"adv_max_resolution", @"value": @"2160"}],
			[UICommand commandWithTitle:@"1440p"      image:nil action:@selector(menuChanged:) propertyList:@{@"defaultsKey": @"adv_max_resolution", @"value": @"1440"}],
			[UICommand commandWithTitle:@"1080p"      image:nil action:@selector(menuChanged:) propertyList:@{@"defaultsKey": @"adv_max_resolution", @"value": @"1080"}],
			[UICommand commandWithTitle:@"720p"       image:nil action:@selector(menuChanged:) propertyList:@{@"defaultsKey": @"adv_max_resolution", @"value": @"720"}],
			[UICommand commandWithTitle:@"480p"       image:nil action:@selector(menuChanged:) propertyList:@{@"defaultsKey": @"adv_max_resolution", @"value": @"480"}],
		]],
		@"adv_audio_codec": [UIMenu menuWithChildren:@[
			[UICommand commandWithTitle:RYGLocalized(@"Copy (passthrough)") image:nil action:@selector(menuChanged:) propertyList:@{@"defaultsKey": @"adv_audio_codec", @"value": @"copy"}],
			[UICommand commandWithTitle:@"AAC" image:nil action:@selector(menuChanged:) propertyList:@{@"defaultsKey": @"adv_audio_codec", @"value": @"aac"}],
		]],
		@"adv_audio_bitrate": [UIMenu menuWithChildren:@[
			[UICommand commandWithTitle:@"64k"  image:nil action:@selector(menuChanged:) propertyList:@{@"defaultsKey": @"adv_audio_bitrate", @"value": @"64k"}],
			[UICommand commandWithTitle:@"96k"  image:nil action:@selector(menuChanged:) propertyList:@{@"defaultsKey": @"adv_audio_bitrate", @"value": @"96k"}],
			[UICommand commandWithTitle:@"128k" image:nil action:@selector(menuChanged:) propertyList:@{@"defaultsKey": @"adv_audio_bitrate", @"value": @"128k"}],
			[UICommand commandWithTitle:@"192k" image:nil action:@selector(menuChanged:) propertyList:@{@"defaultsKey": @"adv_audio_bitrate", @"value": @"192k"}],
			[UICommand commandWithTitle:@"256k" image:nil action:@selector(menuChanged:) propertyList:@{@"defaultsKey": @"adv_audio_bitrate", @"value": @"256k"}],
			[UICommand commandWithTitle:@"320k" image:nil action:@selector(menuChanged:) propertyList:@{@"defaultsKey": @"adv_audio_bitrate", @"value": @"320k"}],
		]],
		@"adv_audio_channels": [UIMenu menuWithChildren:@[
			[UICommand commandWithTitle:RYGLocalized(@"Original") image:nil action:@selector(menuChanged:) propertyList:@{@"defaultsKey": @"adv_audio_channels", @"value": @"original"}],
			[UICommand commandWithTitle:RYGLocalized(@"Stereo")   image:nil action:@selector(menuChanged:) propertyList:@{@"defaultsKey": @"adv_audio_channels", @"value": @"stereo"}],
			[UICommand commandWithTitle:RYGLocalized(@"Mono")     image:nil action:@selector(menuChanged:) propertyList:@{@"defaultsKey": @"adv_audio_channels", @"value": @"mono"}],
		]],

		@"reels_long_press": [UIMenu menuWithChildren:@[
			[UICommand commandWithTitle:RYGLocalized(@"Default")
									image:nil
									action:@selector(menuChanged:)
							propertyList:@{
								@"defaultsKey": @"reels_long_press",
								@"value": @"default",
								@"requiresRestart": @YES
							}
			],
			[UIMenu menuWithTitle:@""
							image:nil
						identifier:nil
							options:UIMenuOptionsDisplayInline
							children:@[
								[UICommand commandWithTitle:RYGLocalized(@"Pause")
														image:nil
														action:@selector(menuChanged:)
												propertyList:@{
													@"defaultsKey": @"reels_long_press",
													@"value": @"pause",
													@"requiresRestart": @YES
												}
								],
								[UICommand commandWithTitle:RYGLocalized(@"Menu")
														image:nil
														action:@selector(menuChanged:)
												propertyList:@{
													@"defaultsKey": @"reels_long_press",
													@"value": @"menu",
													@"requiresRestart": @YES
												}
								],
								[UICommand commandWithTitle:RYGLocalized(@"Menu + PiP")
														image:nil
														action:@selector(menuChanged:)
												propertyList:@{
													@"defaultsKey": @"reels_long_press",
													@"value": @"menu_pip",
													@"requiresRestart": @YES
												}
								]
							]
			]
		]],

		@"reels_tap_control": [UIMenu menuWithChildren:@[
			[UICommand commandWithTitle:RYGLocalized(@"Default")
									image:nil
									action:@selector(menuChanged:)
							propertyList:@{
								@"defaultsKey": @"reels_tap_control",
								@"value": @"default",
								@"requiresRestart": @YES
							}
			],
			[UIMenu menuWithTitle:@""
							image:nil
						identifier:nil
							options:UIMenuOptionsDisplayInline
							children:@[
								[UICommand commandWithTitle:RYGLocalized(@"Pause/Play")
														image:nil
														action:@selector(menuChanged:)
												propertyList:@{
													@"defaultsKey": @"reels_tap_control",
													@"value": @"pause",
													@"requiresRestart": @YES
												}
								],
								[UICommand commandWithTitle:RYGLocalized(@"Mute/Unmute")
														image:nil
														action:@selector(menuChanged:)
												propertyList:@{
													@"defaultsKey": @"reels_tap_control",
													@"value": @"mute",
													@"requiresRestart": @YES
												}
								]
							]
			]
		]],

		@"auto_scroll_reels_mode": [UIMenu menuWithChildren:@[
			[UICommand commandWithTitle:RYGLocalized(@"Off") image:nil action:@selector(menuChanged:)
						   propertyList:@{@"defaultsKey": @"auto_scroll_reels_mode", @"value": @"off"}],
			[UICommand commandWithTitle:RYGLocalized(@"IG default") image:nil action:@selector(menuChanged:)
						   propertyList:@{@"defaultsKey": @"auto_scroll_reels_mode", @"value": @"ig"}],
			[UICommand commandWithTitle:RYGLocalized(@"RyukGram") image:nil action:@selector(menuChanged:)
						   propertyList:@{@"defaultsKey": @"auto_scroll_reels_mode", @"value": @"custom"}],
		]],

		@"story_viewer_default_list": [UIMenu menuWithChildren:@[
			[UICommand commandWithTitle:RYGLocalized(@"RyukGram") image:nil action:@selector(menuChanged:)
						   propertyList:@{@"defaultsKey": @"story_viewer_default_list", @"value": @"ryukgram"}],
			[UICommand commandWithTitle:RYGLocalized(@"Instagram") image:nil action:@selector(menuChanged:)
						   propertyList:@{@"defaultsKey": @"story_viewer_default_list", @"value": @"instagram"}],
		]],

		@"launch_tab": [UIMenu menuWithChildren:@[
			[UICommand commandWithTitle:RYGLocalized(@"Default") image:nil action:@selector(menuChanged:)
						   propertyList:@{@"defaultsKey": @"launch_tab", @"value": @"default"}],
			[UICommand commandWithTitle:RYGLocalized(@"Feed") image:nil action:@selector(menuChanged:)
						   propertyList:@{@"defaultsKey": @"launch_tab", @"value": @"feed"}],
			[UICommand commandWithTitle:RYGLocalized(@"Explore") image:nil action:@selector(menuChanged:)
						   propertyList:@{@"defaultsKey": @"launch_tab", @"value": @"explore"}],
			[UICommand commandWithTitle:RYGLocalized(@"Reels") image:nil action:@selector(menuChanged:)
						   propertyList:@{@"defaultsKey": @"launch_tab", @"value": @"reels"}],
			[UICommand commandWithTitle:RYGLocalized(@"Inbox") image:nil action:@selector(menuChanged:)
						   propertyList:@{@"defaultsKey": @"launch_tab", @"value": @"inbox"}],
			[UICommand commandWithTitle:RYGLocalized(@"Profile") image:nil action:@selector(menuChanged:)
						   propertyList:@{@"defaultsKey": @"launch_tab", @"value": @"profile"}],
		]],
		@"swipe_nav_tabs": [UIMenu menuWithChildren:@[
			[UICommand commandWithTitle:RYGLocalized(@"Default")
									image:nil
									action:@selector(menuChanged:)
							propertyList:@{
								@"defaultsKey": @"swipe_nav_tabs",
								@"value": @"default",
								@"requiresRestart": @YES
							}
			],
			[UIMenu menuWithTitle:@""
							image:nil
						identifier:nil
							options:UIMenuOptionsDisplayInline
							children:@[
								[UICommand commandWithTitle:RYGLocalized(@"Enabled")
														image:nil
														action:@selector(menuChanged:)
												propertyList:@{
													@"defaultsKey": @"swipe_nav_tabs",
													@"value": @"enabled",
													@"requiresRestart": @YES
												}
								],
								[UICommand commandWithTitle:RYGLocalized(@"Disabled")
														image:nil
														action:@selector(menuChanged:)
												propertyList:@{
													@"defaultsKey": @"swipe_nav_tabs",
													@"value": @"disabled",
													@"requiresRestart": @YES
												}
								]
							]
			]
		]],

		@"test": [UIMenu menuWithChildren:@[
			[UIMenu menuWithTitle:@""
							image:nil
						identifier:nil
							options:UIMenuOptionsDisplayInline
							children:@[
								[UICommand commandWithTitle:@"ABC"
														image:nil
														action:@selector(menuChanged:)
												propertyList:@{
													@"defaultsKey": @"test_menu_cell",
													@"value": @"abc"
												}
								],
								[UICommand commandWithTitle:@"123"
														image:nil
														action:@selector(menuChanged:)
												propertyList:@{
													@"defaultsKey": @"test_menu_cell",
													@"value": @"123"
												}
								]
							]
			],
			[UICommand commandWithTitle:RYGLocalized(@"Requires restart")
								  image:nil
								 action:@selector(menuChanged:)
						   propertyList:@{
							   @"defaultsKey": @"test_menu_cell",
							   @"value": @"requires_restart",
							   @"requiresRestart": @YES
						   }
			],
		]],

		@"cache_auto_clear_mode": [UIMenu menuWithChildren:@[
			[UICommand commandWithTitle:RYGLocalized(@"Off")
								  image:nil
								 action:@selector(menuChanged:)
						   propertyList:@{ @"defaultsKey": @"cache_auto_clear_mode", @"value": @"off" }
			],
			[UICommand commandWithTitle:RYGLocalized(@"Daily")
								  image:nil
								 action:@selector(menuChanged:)
						   propertyList:@{ @"defaultsKey": @"cache_auto_clear_mode", @"value": @"daily" }
			],
			[UICommand commandWithTitle:RYGLocalized(@"Weekly")
								  image:nil
								 action:@selector(menuChanged:)
						   propertyList:@{ @"defaultsKey": @"cache_auto_clear_mode", @"value": @"weekly" }
			],
			[UICommand commandWithTitle:RYGLocalized(@"Monthly")
								  image:nil
								 action:@selector(menuChanged:)
						   propertyList:@{ @"defaultsKey": @"cache_auto_clear_mode", @"value": @"monthly" }
			],
			[UICommand commandWithTitle:RYGLocalized(@"Every launch")
								  image:nil
								 action:@selector(menuChanged:)
						   propertyList:@{ @"defaultsKey": @"cache_auto_clear_mode", @"value": @"launch" }
			],
		]],

		@"activity_read_mode":    [self activityModeMenu:@"activity_read_mode"],
		@"activity_online_mode":  [self activityModeMenu:@"activity_online_mode"],
		@"activity_offline_mode": [self activityModeMenu:@"activity_offline_mode"],
		@"activity_typing_mode":  [self activityModeMenu:@"activity_typing_mode"],

		@"repost_date_format": ({
			NSArray<NSArray<NSString *> *> *opts = @[
				@[@"general",	RYGLocalized(@"Same as general format")],
				@[@"relative",	RYGLocalized(@"Relative (1m / 3h / 3d ago)")],
				@[@"rel_date",	@"3d – Jul 9, 2026"],
				@[@"date_rel",	@"Jul 9, 2026 (3d)"],
				@[@"short",		@"Jul 9"],
				@[@"medium",	@"Jul 9, 2026"],
				@[@"full",		@"Jul 9, 2026 at 8:42 AM"],
			];
			NSMutableArray *children = [NSMutableArray array];
			for (NSArray *o in opts)
				[children addObject:[UICommand commandWithTitle:o[1] image:nil action:@selector(menuChanged:)
												   propertyList:@{ @"defaultsKey": @"repost_date_format", @"value": o[0] }]];
			[UIMenu menuWithChildren:children];
		})
	};
}

#pragma clang diagnostic pop

@end
