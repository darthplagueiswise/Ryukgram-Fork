#import "SCISettingsSections.h"
#import "../SCIAppIconPickerViewController.h"
#import "../SCITabBarOrderViewController.h"
#import "../SCITimePickerViewController.h"
#import "../../Features/General/SCIMessagesOnlySchedule.h"
#import "../../InstagramHeaders.h"

@implementation SCITweakSettings (Section_Interface)

static NSArray<NSArray<NSString *> *> *sciIGLanguages(void) {
	return @[
		@[@"system",     SCILocalized(@"settings.language.system")],
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

static NSString *sciCurrentIGLanguageCode(void) {
	NSString *cur = [SCIUtils getStringPref:@"ig_force_language"];
	return cur.length ? cur : @"system";
}

static NSString *sciIGLanguageDisplayName(NSString *code) {
	for (NSArray *l in sciIGLanguages()) if ([l[0] isEqualToString:code]) return l[1];
	return SCILocalized(@"settings.language.system");
}

+ (SCISetting *)igLanguageNavCell {
	NSMutableArray *rows = [NSMutableArray array];
	for (NSArray *l in sciIGLanguages()) {
		NSString *code = l[0];
		SCISetting *row = [SCISetting buttonCellWithTitle:l[1] subtitle:@"" icon:nil action:^{
			[SCIUtils setPref:code forKey:@"ig_force_language"];
			[NSNotificationCenter.defaultCenter postNotificationName:@"SCISettingsShouldReload" object:nil];
			[SCIUtils showRestartConfirmation];
		}];
		row.hidesDisclosureIndicator = YES;
		row.dynamicValueText = ^NSString *{ return [sciCurrentIGLanguageCode() isEqualToString:code] ? @"✓" : nil; };
		[rows addObject:row];
	}

	SCISetting *nav = [SCISetting navigationCellWithTitle:SCILocalized(@"Instagram language")
												 subtitle:@""
													 icon:nil
											  navSections:@[ @{ @"rows": rows } ]];
	nav.dynamicValueText = ^NSString *{ return sciIGLanguageDisplayName(sciCurrentIGLanguageCode()); };
	return nav;
}

+ (NSString *)scheduleTimeText:(NSString *)key {
	NSString *raw = [SCIUtils getStringPref:key] ?: @"";
	NSArray<NSString *> *p = [raw componentsSeparatedByString:@":"];
	if (p.count != 2) return raw;
	NSDate *date = [NSCalendar.currentCalendar dateBySettingHour:p[0].integerValue minute:p[1].integerValue second:0 ofDate:[NSDate date] options:0];
	if (!date) return raw;
	static NSDateFormatter *fmt;
	static dispatch_once_t once;
	dispatch_once(&once, ^{ fmt = [NSDateFormatter new]; fmt.timeStyle = NSDateFormatterShortStyle; fmt.dateStyle = NSDateFormatterNoStyle; });
	return [fmt stringFromDate:date];
}

+ (SCISetting *)scheduleTimeCellTitle:(NSString *)title key:(NSString *)key {
	SCISetting *cell = [SCISetting buttonCellWithTitle:title subtitle:@"" icon:nil action:^{
		[SCITimePickerViewController presentForKey:key title:title from:sciTopVC() onSave:^{
			[[SCIMessagesOnlySchedule shared] refreshFromPrefs];
			[[NSNotificationCenter defaultCenter] postNotificationName:@"SCISettingsShouldReload" object:nil];
		}];
	}];
	cell.dynamicValueText = ^NSString *{ return [self scheduleTimeText:key]; };
	return cell;
}

+ (SCISetting *)messagesOnlyNavCell {
	SCISetting *enable = [SCISetting switchCellWithTitle:SCILocalized(@"Automatic schedule")
												subtitle:SCILocalized(@"Switch into Messages-only on its own during a time window")
												   value:^BOOL{ return [SCIUtils getBoolPref:@"messages_only_schedule_enabled"]; }
												  action:^(BOOL on) {
		[[NSUserDefaults standardUserDefaults] setBool:on forKey:@"messages_only_schedule_enabled"];
		[[SCIMessagesOnlySchedule shared] refreshFromPrefs];
	}];
	enable.dynamicSubtitle = ^NSString *{
		if (![SCIUtils getBoolPref:@"messages_only_schedule_enabled"]) return SCILocalized(@"Switch into Messages-only on its own during a time window");
		NSString *startTxt = [self scheduleTimeText:@"messages_only_schedule_start"];
		NSString *endTxt = [self scheduleTimeText:@"messages_only_schedule_end"];
		if ([[SCIMessagesOnlySchedule shared] isWithinWindowNow])
			return [NSString stringWithFormat:SCILocalized(@"Active now · ends %@"), endTxt];
		return [NSString stringWithFormat:SCILocalized(@"Next window starts %@"), startTxt];
	};

	return [SCISetting navigationCellWithTitle:SCILocalized(@"Messages-only mode")
									  subtitle:SCILocalized(@"DM-only client, hide tabs, auto schedule")
										  icon:[SCISymbol symbolWithIGName:@"messages" fallback:@"bubble.left.and.bubble.right"]
								   navSections:@[
		@{
			@"header": SCILocalized(@"Messages-only mode"),
			@"footer": SCILocalized(@"Hides every tab except DM inbox + profile and forces launch into the inbox. Settings shortcut moves to long-press on the inbox tab."),
			@"rows": @[
				[SCISetting switchCellWithTitle:SCILocalized(@"Messages only") subtitle:SCILocalized(@"Turn IG into a DM-only client") defaultsKey:@"messages_only" requiresRestart:YES],
				[SCISetting switchCellWithTitle:SCILocalized(@"Hide search tab") subtitle:SCILocalized(@"Remove the search/explore button from the tab bar") defaultsKey:@"messages_only_hide_search" requiresRestart:YES],
				[SCISetting switchCellWithTitle:SCILocalized(@"Hide tab bar") subtitle:SCILocalized(@"Also hide the bottom tab bar — only the inbox is visible") defaultsKey:@"messages_only_hide_tabbar" requiresRestart:YES],
			]
		},
		@{
			@"header": SCILocalized(@"Automatic schedule"),
			@"footer": SCILocalized(@"Turn Messages-only on by itself during a daily window (e.g. 10:00 PM – 6:00 AM) using the toggles above. You'll be asked to restart when the window starts and when it ends."),
			@"rows": @[
				enable,
				[self scheduleTimeCellTitle:SCILocalized(@"Start time") key:@"messages_only_schedule_start"],
				[self scheduleTimeCellTitle:SCILocalized(@"End time") key:@"messages_only_schedule_end"],
			]
		},
	]];
}

+ (SCISetting *)interfaceNavCell {
	return [SCISetting navigationCellWithTitle:SCILocalized(@"Interface")

										   subtitle:@""
											   icon:[SCISymbol symbolWithIGName:@"layout" fallback:@"hand.draw.fill"]
										navSections:@[
										@{
											@"header": SCILocalized(@"settings.language.title"),
											@"rows": @[
												[self igLanguageNavCell],
											]
										},
										@{
											@"header": SCILocalized(@"Home shortcut button"),
											@"footer": SCILocalized(@"Adds an extra shortcut button beside the create-post + button on the home top bar."),
											@"rows": @[
												[SCISetting switchCellWithTitle:SCILocalized(@"Show home shortcut button")
																	   subtitle:SCILocalized(@"Show the extra button on the home top bar")
																	defaultsKey:@"home_shortcut_enabled" requiresRestart:YES],
												({ SCISetting *s = [SCISetting navigationCellWithTitle:SCILocalized(@"Configure button")
																		   subtitle:SCILocalized(@"Choose icon, reorder actions, and enable menu items")
																			   icon:[SCISymbol symbolWithIGName:@"home" fallback:@"house"]
																	 viewController:[SCIHomeShortcutConfigViewController new]];
												   s.whatsNewID = @"ui_homeshortcut_config"; s; }),
											]
										},
										@{
											@"header": SCILocalized(@"Global Action Icons"),
											@"footer": SCILocalized(@"Used across feed, stories, reels, and DMs."),
											@"rows": @[
												[self actionIconNavCell],
											]
										},
										@{
											@"header": SCILocalized(@"Notifications"),
											@"footer": SCILocalized(@"Universal in-app notifications. Pick style, position, per-action routing (custom pill / IG-native / off)."),
											@"rows": @[
												({ SCISetting *s = [SCINotificationSettings notificationsNavCell]; s.whatsNewID = @"ui_notifications"; s; }),
											]
										},
										@{
											@"header": SCILocalized(@"Tab bar"),
											@"rows": @[
												({ SCISetting *s = [SCISetting navigationCellWithTitle:SCILocalized(@"Icon order") subtitle:SCILocalized(@"The order of the icons on the bottom navigation bar")
																			   icon:nil
																	 viewController:[SCITabBarOrderViewController new]];
																   s.whatsNewID = @"ui_taborder"; s; }),
												[SCISetting menuCellWithTitle:SCILocalized(@"Swipe between tabs") subtitle:SCILocalized(@"Lets you swipe to switch between navigation bar tabs") menu:[self menus][@"swipe_nav_tabs"]],
												[SCISetting menuCellWithTitle:SCILocalized(@"Launch tab") subtitle:SCILocalized(@"Tab the app opens to. Ignored when Messages-only is on") menu:[self menus][@"launch_tab"]],
											]
										},
										@{
											@"header": SCILocalized(@"Messages-only mode"),
											@"rows": @[
												[self messagesOnlyNavCell],
											]
										},
										@{
											@"header": SCILocalized(@"Experimental features"),
											@"footer": SCILocalized(@"These features rely on hidden Instagram flags and may not work on all accounts or versions."),
											@"rows": @[
												[SCISetting switchCellWithTitle:SCILocalized(@"Enable liquid glass buttons") subtitle:SCILocalized(@"Enables experimental liquid glass buttons") defaultsKey:@"liquid_glass_buttons" requiresRestart:YES],
												[SCISetting switchCellWithTitle:SCILocalized(@"Enable liquid glass surfaces") subtitle:SCILocalized(@"Enables liquid glass tab bar, floating navigation, and other UI elements") defaultsKey:@"liquid_glass_surfaces" requiresRestart:YES],
												[SCISetting switchCellWithTitle:SCILocalized(@"Force liquid glass off") subtitle:SCILocalized(@"Disables liquid glass for accounts that have it enabled by default. Overrides the options above") defaultsKey:@"liquid_glass_force_off" requiresRestart:YES],
												[SCISetting menuCellWithTitle:SCILocalized(@"Liquid glass tab bar") subtitle:SCILocalized(@"Fixed prevents shrinking. Hide makes it disappear when scrolling down") menu:[self menus][@"liquid_glass_tabbar_mode"]],
												[SCISetting switchCellWithTitle:SCILocalized(@"Force progressive blur") subtitle:SCILocalized(@"Keeps the iOS 26 scroll-edge blur visible instead of letting it fade out") defaultsKey:@"liquid_glass_progressive_blur" requiresRestart:YES],
												[SCISetting switchCellWithTitle:SCILocalized(@"Enable teen app icons") subtitle:SCILocalized(@"Hold down on the Instagram logo to change the app icon") defaultsKey:@"teen_app_icons" requiresRestart:YES],
												[SCISetting switchCellWithTitle:SCILocalized(@"Disable app haptics") subtitle:SCILocalized(@"Disables haptics/vibrations within the app") defaultsKey:@"disable_haptics"],
												({ SCISetting *s = [SCISetting buttonCellWithTitle:SCILocalized(@"Open app icon picker") subtitle:SCILocalized(@"Change the app icon from the bundled icons")
																			icon:[SCISymbol symbolWithIGName:@"app.badge" fallback:@"app"]
																		  action:^{ [SCIPopupChrome presentVC:[SCIAppIconPickerViewController new] from:topMostController()]; }];
												   s.whatsNewID = @"ui_appicon"; s; }),
											]
										}]
				];
}

@end
