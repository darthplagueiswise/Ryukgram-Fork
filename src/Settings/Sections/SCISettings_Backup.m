#import "SCISettingsSections.h"
#import "../SCISettingsBackup.h"

@implementation SCITweakSettings (Section_Backup)

+ (SCISetting *)backupNavCell {
	return [SCISetting navigationCellWithTitle:SCILocalized(@"Backup & Restore")
										   subtitle:@""
											   icon:[SCISymbol symbolWithIGName:@"cloud" fallback:@"arrow.up.arrow.down.square"]
										navSections:@[@{
											@"header": @"",
											@"footer": SCILocalized(@"Export or import RyukGram data — settings, per-account filters, hidden & locked chats, Profile Analyzer, gallery, chat backgrounds and deleted messages. Pick any combination on each page. Settings stay a plain JSON file; bundles with media export as a compressed .ryukbak."),
											@"rows": @[
												[SCISetting buttonCellWithTitle:SCILocalized(@"Export")
																	   subtitle:SCILocalized(@"Save settings or a full backup")
																		   icon:[SCISymbol symbolWithName:@"square.and.arrow.up"]
																		 action:^(void) { [SCISettingsBackup presentExport]; }
												],
												[SCISetting buttonCellWithTitle:SCILocalized(@"Import")
																	   subtitle:SCILocalized(@"Load a .json or .ryukbak backup")
																		   icon:[SCISymbol symbolWithName:@"square.and.arrow.down"]
																		 action:^(void) { [SCISettingsBackup presentImport]; }
												],
												[SCISetting buttonCellWithTitle:SCILocalized(@"Reset")
																	   subtitle:SCILocalized(@"Clear selected data")
																		   icon:[SCISymbol symbolWithIGName:@"bcn_arrow-ccw_outline_24" fallback:@"arrow.counterclockwise.circle"]
																		 action:^(void) { [SCISettingsBackup presentReset]; }
												]
											]
										}]
				];
}

@end
