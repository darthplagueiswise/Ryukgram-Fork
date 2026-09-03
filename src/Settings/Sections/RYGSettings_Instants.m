#import "RYGSettingsSections.h"
#import "../../UI/RYGFeatureIcons.h"

@implementation RYGTweakSettings (Section_Instants)

+ (RYGSetting *)instantsNavCell {
	return [RYGSetting navigationCellWithTitle:RYGLocalized(@"Instants")
									   subtitle:@""
										   icon:[RYGFeatureIcons instants]
									navSections:@[@{
										@"header": RYGLocalized(@"Camera"),
										@"footer": RYGLocalized(@"Tweaks for the QuickSnap / Instants camera surface."),
										@"rows": @[
											[RYGSetting switchCellWithTitle:RYGLocalized(@"Send from gallery") subtitle:RYGLocalized(@"Adds a gallery button to the instants camera so you can send a photo from your album") defaultsKey:@"instants_send_from_gallery" requiresRestart:YES],
										]
									},
									@{
										@"header": RYGLocalized(@"Viewer"),
										@"rows": @[
											[RYGSetting switchCellWithTitle:RYGLocalized(@"Auto advance after reaction") subtitle:RYGLocalized(@"Automatically moves to the next instant after you like or react") defaultsKey:@"instant_auto_advance_reaction"],
											[RYGSetting switchCellWithTitle:RYGLocalized(@"Auto close when finished") subtitle:RYGLocalized(@"Closes the instants viewer once you have seen them all instead of landing on the camera") defaultsKey:@"instants_auto_close" requiresRestart:YES],
											[RYGSetting switchCellWithTitle:RYGLocalized(@"Instants action button") subtitle:RYGLocalized(@"Adds a RyukGram action button to the instants viewer header with expand, save, share, and bulk-save entries") defaultsKey:@"instants_download_btn"],
											({ RYGSetting *s = [RYGSetting navigationCellWithTitle:RYGLocalized(@"Configure menu")
																		subtitle:RYGLocalized(@"Reorder, enable/disable, set default tap, show date")
																			icon:nil
																  viewController:[[RYGActionMenuConfigViewController alloc] initForSource:RYGActionSourceInstants]];
											   s.whatsNewID = @"ui_cfg_actionmenu"; s; }),
										]
									},
									@{
										@"header": RYGLocalized(@"Saving"),
										@"rows": @[
											[RYGSetting menuCellWithTitle:RYGLocalized(@"Auto-save instants") subtitle:RYGLocalized(@"Automatically saves every instant you view, including as you swipe — each one only once") menu:[self menus][@"instants_auto_save"]],
										]
									},
									@{
										@"header": RYGLocalized(@"Confirmations"),
										@"rows": @[
											[RYGSetting switchCellWithTitle:RYGLocalized(@"Confirm Instants capture") subtitle:RYGLocalized(@"Shows an alert before sending a photo or video from the Instants camera") defaultsKey:@"instants_capture_confirm" requiresRestart:YES],
											({ RYGSetting *s = [RYGSetting switchCellWithTitle:RYGLocalized(@"Confirm switching Instant") subtitle:RYGLocalized(@"Shows an alert before tapping to switch to the next/previous Instant") defaultsKey:@"instants_advance_confirm" requiresRestart:YES];
											   s.lockedOnProvider = ^{ return [RYGUtils getBoolPref:@"instants_confirm_toggle_btn"]; }; s; }),
											[RYGSetting switchCellWithTitle:RYGLocalized(@"Confirm switching button") subtitle:RYGLocalized(@"Adds a button next to the action button that turns the switching confirmation on or off on the spot") defaultsKey:@"instants_confirm_toggle_btn" requiresRestart:YES],
											[RYGSetting switchCellWithTitle:RYGLocalized(@"Confirm Instants emoji reaction") subtitle:RYGLocalized(@"Shows an alert before sending an emoji reaction on an Instant") defaultsKey:@"instants_emoji_reaction_confirm"],
										]
									}]
				];
}

@end
