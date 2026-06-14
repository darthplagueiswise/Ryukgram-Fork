#import "SCISettingsSections.h"

@implementation SCITweakSettings (Section_Theme)

+ (SCISetting *)themeNavCell {
	return [SCISetting navigationCellWithTitle:SCILocalized(@"Theme")
										   subtitle:@""
											   icon:[SCISymbol symbolWithIGName:@"moon" fallback:@"moon"]
										navSections:@[@{
											@"header": SCILocalized(@"Theme"),
											@"footer": SCILocalized(@"The theme RyukGram applies to Instagram."),
											@"rows": @[
												[SCISetting menuCellWithTitle:SCILocalized(@"Theme") subtitle:SCILocalized(@"Off, Light, Dark, or OLED") menu:[self menus][@"theme_mode"]],
											]
										},
										@{
											@"header": SCILocalized(@"Surfaces"),
											@"footer": SCILocalized(@"Optional per-surface overrides. Each one is independent of the theme above."),
											@"rows": @[
												[SCISetting switchCellWithTitle:SCILocalized(@"OLED chat theme") subtitle:SCILocalized(@"Pure black DM thread + incoming bubbles") defaultsKey:@"theme_oled_chat"],
												[SCISetting menuCellWithTitle:SCILocalized(@"Keyboard theme") subtitle:SCILocalized(@"Override the keyboard appearance when typing") menu:[self menus][@"theme_keyboard"]],
											]
										},
										@{
											@"header": SCILocalized(@"Behavior"),
											@"footer": SCILocalized(@"Affects everything above. When off, RyukGram's theme and surface overrides only apply while iOS is in dark mode — leaving light mode untouched."),
											@"rows": @[
												[SCISetting switchCellWithTitle:SCILocalized(@"Force theme") subtitle:SCILocalized(@"Override iOS appearance regardless of system mode") defaultsKey:@"theme_force"],
											]
										},
										@{
											@"header": @"",
											@"rows": @[
												[SCISetting buttonCellWithTitle:SCILocalized(@"Apply & restart")
																	   subtitle:SCILocalized(@"Restart Instagram to apply your theme changes")
																		   icon:[SCISymbol symbolWithIGName:@"bcn_circle-check_outline_24" fallback:@"checkmark.circle.fill"]
																		 action:^(void) { [SCIUtils showRestartConfirmation]; }
												],
												[SCISetting buttonCellWithTitle:SCILocalized(@"Reset theme")
																	   subtitle:SCILocalized(@"Turn every theme option off and restart")
																		   icon:[SCISymbol symbolWithIGName:@"bcn_arrow-ccw_outline_24" fallback:@"arrow.uturn.backward.circle.fill"]
																		 action:^(void) {
													[SCIUtils showConfirmation:^{
														[SCITheme resetToDefaults];
														[SCIUtils showRestartConfirmation];
													} title:SCILocalized(@"Reset theme")];
												}
												]
											]
										}]
				];
}

@end
