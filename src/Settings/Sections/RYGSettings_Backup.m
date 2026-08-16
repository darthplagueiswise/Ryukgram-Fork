#import "RYGSettingsSections.h"
#import "../RYGSettingsBackup.h"
#import "../RYGStorageUsage.h"
#import "../RYGStorageUsageViewController.h"
#import "../../UI/RYGFeatureIcons.h"

@implementation RYGTweakSettings (Section_Backup)

+ (RYGSetting *)storageNavCell {
	// The scan also warms the account registry, turning bare pks into @names.
	[RYGStorageUsage refreshTotalInBackground];
	RYGSetting *cell = [RYGSetting navigationCellWithTitle:RYGLocalized(@"Storage")
												  subtitle:RYGLocalized(@"RyukGram's own data on this device")
													  icon:[RYGFeatureIcons storage]
											viewController:[RYGStorageUsageViewController new]];
	cell.dynamicValueText = ^{
		unsigned long long total = [RYGStorageUsage cachedTotal];
		return total ? [RYGStorageUsage formattedSize:total] : @"—";
	};
	cell.whatsNewID = @"ui_storage";
	return cell;
}

+ (RYGSetting *)backupNavCell {
	return [RYGSetting navigationCellWithTitle:RYGLocalized(@"Backup & Restore")
										   subtitle:@""
											   icon:[RYGSymbol symbolWithIGName:@"cloud" fallback:@"arrow.up.arrow.down.square"]
										navSections:@[@{
											@"header": @"",
											@"footer": RYGLocalized(@"Export or import RyukGram data — settings, per-account filters, hidden & locked chats, Profile Analyzer, gallery, chat backgrounds, deleted messages and the read receipts log. Pick any combination on each page. Settings stay a plain JSON file; bundles with media export as a compressed .ryukbak."),
											@"rows": @[
												[self storageNavCell],
												[RYGSetting buttonCellWithTitle:RYGLocalized(@"Export")
																	   subtitle:RYGLocalized(@"Save settings or a full backup")
																		   icon:[RYGSymbol symbolWithName:@"square.and.arrow.up"]
																		 action:^(void) { [RYGSettingsBackup presentExport]; }
												],
												[RYGSetting buttonCellWithTitle:RYGLocalized(@"Import")
																	   subtitle:RYGLocalized(@"Load a .json or .ryukbak backup")
																		   icon:[RYGSymbol symbolWithName:@"square.and.arrow.down"]
																		 action:^(void) { [RYGSettingsBackup presentImport]; }
												],
												[RYGSetting buttonCellWithTitle:RYGLocalized(@"Reset")
																	   subtitle:RYGLocalized(@"Put settings back to defaults and clear data")
																		   icon:[RYGSymbol symbolWithIGName:@"bcn_arrow-ccw_outline_24" fallback:@"arrow.counterclockwise.circle"]
																		 action:^(void) { [RYGSettingsBackup presentReset]; }
												]
											]
										}]
				];
}

@end
