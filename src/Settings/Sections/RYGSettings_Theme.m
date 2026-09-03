#import "RYGSettingsSections.h"

@implementation RYGTweakSettings (Section_Theme)

+ (RYGSetting *)themeNavCell {
	return [RYGSetting navigationCellWithTitle:RYGLocalized(@"Theme")
										   subtitle:@""
											   icon:[RYGSymbol symbolWithIGName:@"moon" fallback:@"moon"]
										navSections:@[@{
											@"header": RYGLocalized(@"Theme"),
											@"footer": RYGLocalized(@"The theme RyukGram applies to Instagram."),
											@"rows": @[
												[RYGSetting menuCellWithTitle:RYGLocalized(@"Theme") subtitle:RYGLocalized(@"Off, Light, Dark, or OLED") menu:[self menus][@"theme_mode"]],
											]
										},
										@{
											@"header": RYGLocalized(@"Surfaces"),
											@"footer": RYGLocalized(@"Optional per-surface overrides. Each one is independent of the theme above."),
											@"rows": @[
												[RYGSetting switchCellWithTitle:RYGLocalized(@"OLED chat theme") subtitle:RYGLocalized(@"Pure black DM thread + incoming bubbles") defaultsKey:@"theme_oled_chat"],
												[RYGSetting menuCellWithTitle:RYGLocalized(@"Keyboard theme") subtitle:RYGLocalized(@"Override the keyboard appearance when typing") menu:[self menus][@"theme_keyboard"]],
											]
										},
										@{
											@"header": RYGLocalized(@"Behavior"),
											@"footer": RYGLocalized(@"Affects everything above. When off, RyukGram's theme and surface overrides only apply while iOS is in dark mode — leaving light mode untouched."),
											@"rows": @[
												[RYGSetting switchCellWithTitle:RYGLocalized(@"Force theme") subtitle:RYGLocalized(@"Override iOS appearance regardless of system mode") defaultsKey:@"theme_force"],
											]
										},
										@{
											@"header": @"",
											@"footer": RYGLocalized(@"Applying restarts Instagram to load your changes."),
											@"rows": @[
												[RYGSetting actionCellWithTitle:RYGLocalized(@"Apply & restart")
																		  color:[RYGUtils RYGColor_Primary]
																		 action:^(void) { [RYGUtils showRestartConfirmation]; }
												],
												[RYGSetting actionCellWithTitle:RYGLocalized(@"Reset to defaults")
																		  color:UIColor.systemRedColor
																		 action:^(void) {
													[RYGUtils showConfirmation:^{
														[RYGTheme resetToDefaults];
														[RYGUtils showRestartConfirmation];
													} title:RYGLocalized(@"Reset to defaults")];
												}
												]
											]
										}]
				];
}

@end
