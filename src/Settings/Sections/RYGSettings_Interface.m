#import "RYGSettingsSections.h"
#import "../RYGAppIconPickerViewController.h"
#import "../RYGTabBarOrderViewController.h"
#import "../RYGTimePickerViewController.h"
#import "../../Features/General/RYGMessagesOnlySchedule.h"
#import "../../InstagramHeaders.h"

@implementation RYGTweakSettings (Section_Interface)

static NSArray<NSArray<NSString *> *> *rygIGLanguages(void) {
	return @[
		@[@"system",     RYGLocalized(@"settings.language.system")],
		@[@"ar",         @"العربية"],
		@[@"hr",         @"Hrvatski"],
		@[@"cs",         @"Čeština"],
		@[@"da",         @"Dansk"],
		@[@"nl",         @"Nederlands"],
		@[@"en",         @"English"],
		@[@"en-GB",      @"English (UK)"],
		@[@"tl",         @"Filipino"],
		@[@"fi",         @"Suomi"],
		@[@"fr",         @"Français"],
		@[@"de",         @"Deutsch"],
		@[@"el",         @"Ελληνικά"],
		@[@"hi",         @"हिन्दी"],
		@[@"hu",         @"Magyar"],
		@[@"id",         @"Bahasa Indonesia"],
		@[@"it",         @"Italiano"],
		@[@"ja",         @"日本語"],
		@[@"ko",         @"한국어"],
		@[@"ms",         @"Bahasa Melayu"],
		@[@"nb",         @"Norsk"],
		@[@"pl",         @"Polski"],
		@[@"pt",         @"Português (Brasil)"],
		@[@"pt-PT",      @"Português (Portugal)"],
		@[@"ro",         @"Română"],
		@[@"ru",         @"Русский"],
		@[@"sk",         @"Slovenčina"],
		@[@"es",         @"Español"],
		@[@"es-ES",      @"Español (España)"],
		@[@"sv",         @"Svenska"],
		@[@"th",         @"ไทย"],
		@[@"tr",         @"Türkçe"],
		@[@"uk",         @"Українська"],
		@[@"vi",         @"Tiếng Việt"],
		@[@"zh-Hans",    @"简体中文"],
		@[@"zh-Hant",    @"繁體中文"],
		@[@"zh-Hant-HK", @"繁體中文（香港）"],
	];
}

static NSString *rygCurrentIGLanguageCode(void) {
	NSString *cur = [RYGUtils getStringPref:@"ig_force_language"];
	return cur.length ? cur : @"system";
}

static NSString *rygIGLanguageDisplayName(NSString *code) {
	for (NSArray *l in rygIGLanguages()) if ([l[0] isEqualToString:code]) return l[1];
	return RYGLocalized(@"settings.language.system");
}

+ (RYGSetting *)igLanguageNavCell {
	NSMutableArray *rows = [NSMutableArray array];
	for (NSArray *l in rygIGLanguages()) {
		NSString *code = l[0];
		RYGSetting *row = [RYGSetting buttonCellWithTitle:l[1] subtitle:@"" icon:nil action:^{
			[RYGUtils setPref:code forKey:@"ig_force_language"];
			[NSNotificationCenter.defaultCenter postNotificationName:@"RYGSettingsShouldReload" object:nil];
			[RYGUtils showRestartConfirmation];
		}];
		row.hidesDisclosureIndicator = YES;
		row.dynamicValueText = ^NSString *{ return [rygCurrentIGLanguageCode() isEqualToString:code] ? @"✓" : nil; };
		[rows addObject:row];
	}

	RYGSetting *nav = [RYGSetting navigationCellWithTitle:RYGLocalized(@"Instagram language")
												 subtitle:@""
													 icon:nil
											  navSections:@[ @{ @"rows": rows } ]];
	nav.dynamicValueText = ^NSString *{ return rygIGLanguageDisplayName(rygCurrentIGLanguageCode()); };
	nav.whatsNewID = @"ui_iglanguage";
	return nav;
}

+ (NSString *)scheduleTimeText:(NSString *)key {
	NSString *raw = [RYGUtils getStringPref:key] ?: @"";
	NSArray<NSString *> *p = [raw componentsSeparatedByString:@":"];
	if (p.count != 2) return raw;
	NSDate *date = [NSCalendar.currentCalendar dateBySettingHour:p[0].integerValue minute:p[1].integerValue second:0 ofDate:[NSDate date] options:0];
	if (!date) return raw;
	static NSDateFormatter *fmt;
	static dispatch_once_t once;
	dispatch_once(&once, ^{ fmt = [NSDateFormatter new]; fmt.timeStyle = NSDateFormatterShortStyle; fmt.dateStyle = NSDateFormatterNoStyle; });
	return [fmt stringFromDate:date];
}

static RYGSetting *rygMsgOnlySwitch(NSString *title, NSString *subtitle, NSString *key) {
	return [RYGSetting switchCellWithTitle:title subtitle:subtitle
									 value:^BOOL{ return [RYGUtils getBoolPref:key]; }
									action:^(BOOL on) {
		[[NSUserDefaults standardUserDefaults] setBool:on forKey:key];
		if (!RYGMessagesOnlyApplyLive()) [RYGUtils showRestartConfirmation];
	}];
}

+ (RYGSetting *)scheduleTimeCellTitle:(NSString *)title key:(NSString *)key {
	RYGSetting *cell = [RYGSetting buttonCellWithTitle:title subtitle:@"" icon:nil action:^{
		[RYGTimePickerViewController presentForKey:key title:title from:rygTopVC() onSave:^{
			[[RYGMessagesOnlySchedule shared] refreshFromPrefs];
			[[NSNotificationCenter defaultCenter] postNotificationName:@"RYGSettingsShouldReload" object:nil];
		}];
	}];
	cell.dynamicValueText = ^NSString *{ return [self scheduleTimeText:key]; };
	return cell;
}

+ (RYGSetting *)messagesOnlyNavCell {
	RYGSetting *enable = [RYGSetting switchCellWithTitle:RYGLocalized(@"Automatic schedule")
												subtitle:RYGLocalized(@"Switch into Messages-only on its own during a time window")
												   value:^BOOL{ return [RYGUtils getBoolPref:@"messages_only_schedule_enabled"]; }
												  action:^(BOOL on) {
		[[NSUserDefaults standardUserDefaults] setBool:on forKey:@"messages_only_schedule_enabled"];
		[[RYGMessagesOnlySchedule shared] refreshFromPrefs];
	}];
	enable.dynamicSubtitle = ^NSString *{
		if (![RYGUtils getBoolPref:@"messages_only_schedule_enabled"]) return RYGLocalized(@"Switch into Messages-only on its own during a time window");
		NSString *startTxt = [self scheduleTimeText:@"messages_only_schedule_start"];
		NSString *endTxt = [self scheduleTimeText:@"messages_only_schedule_end"];
		if ([[RYGMessagesOnlySchedule shared] isWithinWindowNow])
			return [NSString stringWithFormat:RYGLocalized(@"Active now · ends %@"), endTxt];
		return [NSString stringWithFormat:RYGLocalized(@"Next window starts %@"), startTxt];
	};
	enable.whatsNewID = @"messages_only_schedule_enabled";

	return [RYGSetting navigationCellWithTitle:RYGLocalized(@"Messages-only mode")
									  subtitle:RYGLocalized(@"DM-only client, hide tabs, auto schedule")
										  icon:[RYGSymbol symbolWithIGName:@"messages" fallback:@"bubble.left.and.bubble.right"]
								   navSections:@[
		@{
			@"header": RYGLocalized(@"Messages-only mode"),
			@"footer": RYGLocalized(@"Hides every tab except DM inbox + profile and forces launch into the inbox. Settings shortcut moves to long-press on the inbox tab."),
			@"rows": @[
				rygMsgOnlySwitch(RYGLocalized(@"Messages only"), RYGLocalized(@"Turn IG into a DM-only client"), @"messages_only"),
				rygMsgOnlySwitch(RYGLocalized(@"Hide search tab"), RYGLocalized(@"Remove the search/explore button from the tab bar"), @"messages_only_hide_search"),
				rygMsgOnlySwitch(RYGLocalized(@"Hide tab bar"), RYGLocalized(@"Also hide the bottom tab bar — only the inbox is visible"), @"messages_only_hide_tabbar"),
				({
					BOOL homeOn = [RYGUtils getBoolPref:@"home_shortcut_enabled"];
					RYGSetting *s = rygMsgOnlySwitch(RYGLocalized(@"Home shortcut button"),
													 homeOn ? RYGLocalized(@"Show the home shortcut button in the inbox header, on the right")
															: RYGLocalized(@"Greyed out until the home shortcut button is enabled in Interface"),
													 @"messages_only_home_shortcut");
					s.disabled = !homeOn;
					s;
				}),
			]
		},
		@{
			@"header": RYGLocalized(@"Automatic schedule"),
			@"footer": RYGLocalized(@"Turn Messages-only on by itself during a daily window (e.g. 10:00 PM – 6:00 AM) using the toggles above."),
			@"rows": @[
				enable,
				[self scheduleTimeCellTitle:RYGLocalized(@"Start time") key:@"messages_only_schedule_start"],
				[self scheduleTimeCellTitle:RYGLocalized(@"End time") key:@"messages_only_schedule_end"],
				[RYGSetting menuCellWithTitle:RYGLocalized(@"When the window changes")
									 subtitle:@""
										 menu:[self menus][@"messages_only_schedule_apply"]],
			]
		},
	]];
}

+ (RYGSetting *)interfaceNavCell {
	return [RYGSetting navigationCellWithTitle:RYGLocalized(@"Interface")

										   subtitle:@""
											   icon:[RYGSymbol symbolWithIGName:@"layout" fallback:@"hand.draw.fill"]
										navSections:@[
										@{
											@"header": RYGLocalized(@"settings.language.title"),
											@"rows": @[
												[self igLanguageNavCell],
											]
										},
										@{
											@"header": RYGLocalized(@"Home shortcut button"),
											@"footer": RYGLocalized(@"Adds an extra shortcut button beside the create-post + button on the home top bar."),
											@"rows": @[
												[RYGSetting switchCellWithTitle:RYGLocalized(@"Show home shortcut button")
																	   subtitle:RYGLocalized(@"Show the extra button on the home top bar")
																	defaultsKey:@"home_shortcut_enabled" requiresRestart:YES],
												({ RYGSetting *s = [RYGSetting navigationCellWithTitle:RYGLocalized(@"Configure button")
																		   subtitle:RYGLocalized(@"Choose icon, reorder actions, and enable menu items")
																			   icon:[RYGSymbol symbolWithIGName:@"ig_icon_home_prism_outline_24" fallback:@"house"]
																	 viewController:[RYGHomeShortcutConfigViewController new]];
												   s.whatsNewID = @"ui_homeshortcut_config"; s; }),
											]
										},
										@{
											@"header": RYGLocalized(@"Global Action Icons"),
											@"footer": RYGLocalized(@"Used across feed, stories, reels, and DMs."),
											@"rows": @[
												[self actionIconNavCell],
											]
										},
										@{
											@"header": RYGLocalized(@"Notifications"),
											@"footer": RYGLocalized(@"Universal in-app notifications. Pick style, position, per-action routing (custom pill / IG-native / off)."),
											@"rows": @[
												({ RYGSetting *s = [RYGNotificationSettings notificationsNavCell]; s.whatsNewID = @"ui_notifications"; s; }),
											]
										},
										@{
											@"header": RYGLocalized(@"Tab bar"),
											@"rows": @[
												({ RYGSetting *s = [RYGSetting navigationCellWithTitle:RYGLocalized(@"Icon order") subtitle:RYGLocalized(@"How the icons on the bottom tab bar are ordered")
																			   icon:nil
																	 viewController:[RYGTabBarOrderViewController new]];
																   s.whatsNewID = @"ui_taborder"; s; }),
												[RYGSetting menuCellWithTitle:RYGLocalized(@"Swipe between tabs") subtitle:RYGLocalized(@"Swipe sideways to move between the tab bar tabs") menu:[self menus][@"swipe_nav_tabs"]],
												[RYGSetting menuCellWithTitle:RYGLocalized(@"Launch tab") subtitle:RYGLocalized(@"Tab the app opens to. Ignored when Messages-only is on") menu:[self menus][@"launch_tab"]],
											]
										},
										@{
											@"header": RYGLocalized(@"Messages-only mode"),
											@"rows": @[
												[self messagesOnlyNavCell],
											]
										},
										@{
											@"header": RYGLocalized(@"Experimental features"),
											@"footer": RYGLocalized(@"These features rely on hidden Instagram flags and may not work on all accounts or versions."),
											@"rows": @[
												[RYGSetting switchCellWithTitle:RYGLocalized(@"Enable liquid glass buttons") subtitle:RYGLocalized(@"Enables experimental liquid glass buttons") defaultsKey:@"liquid_glass_buttons" requiresRestart:YES],
												[RYGSetting switchCellWithTitle:RYGLocalized(@"Enable liquid glass surfaces") subtitle:RYGLocalized(@"Enables liquid glass tab bar, floating navigation, and other UI elements") defaultsKey:@"liquid_glass_surfaces" requiresRestart:YES],
												[RYGSetting switchCellWithTitle:RYGLocalized(@"Force liquid glass off") subtitle:RYGLocalized(@"Disables liquid glass for accounts that have it enabled by default. Overrides the options above") defaultsKey:@"liquid_glass_force_off" requiresRestart:YES],
												[RYGSetting menuCellWithTitle:RYGLocalized(@"Liquid glass tab bar") subtitle:RYGLocalized(@"Fixed prevents shrinking. Hide makes it disappear when scrolling down") menu:[self menus][@"liquid_glass_tabbar_mode"]],
												[RYGSetting switchCellWithTitle:RYGLocalized(@"Force progressive blur") subtitle:RYGLocalized(@"Keeps the iOS 26 scroll-edge blur visible instead of letting it fade out") defaultsKey:@"liquid_glass_progressive_blur" requiresRestart:YES],
												[RYGSetting switchCellWithTitle:RYGLocalized(@"Enable teen app icons") subtitle:RYGLocalized(@"Hold down on the Instagram logo to change the app icon") defaultsKey:@"teen_app_icons" requiresRestart:YES],
												[RYGSetting switchCellWithTitle:RYGLocalized(@"Disable app haptics") subtitle:RYGLocalized(@"Disables haptics/vibrations within the app") defaultsKey:@"disable_haptics"],
												({ RYGSetting *s = [RYGSetting buttonCellWithTitle:RYGLocalized(@"Open app icon picker") subtitle:RYGLocalized(@"Change the app icon from the bundled icons")
																			icon:[RYGSymbol symbolWithIGName:@"app.badge" fallback:@"app"]
																		  action:^{ [RYGPopupChrome presentVC:[RYGAppIconPickerViewController new] from:topMostController()]; }];
												   s.whatsNewID = @"ui_appicon"; s; }),
											]
										}]
				];
}

@end
