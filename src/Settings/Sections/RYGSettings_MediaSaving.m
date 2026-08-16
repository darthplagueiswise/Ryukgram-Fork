#import "RYGSettingsSections.h"
#import "../../Downloader/RYGDownloadManagerViewController.h"
#import "../../UI/RYGFeatureIcons.h"

@implementation RYGTweakSettings (Section_MediaSaving)

+ (RYGSetting *)mediaSavingNavCell {
	return [RYGSetting navigationCellWithTitle:RYGLocalized(@"Media saving")
										   subtitle:@""
											   icon:[RYGSymbol symbolWithIGName:@"download_filled" fallback:@"tray.and.arrow.down"]
										navSections:@[@{
											@"header": RYGLocalized(@"Downloads"),
											@"footer": RYGLocalized(@"When \"Save to dedicated album\" is on, downloads and share-sheet \"Save to Photos\" picks are routed into a named album in your Photos library. Tap \"Album name\" to change it."),
											@"rows": @[
												[RYGSetting switchCellWithTitle:RYGLocalized(@"Confirm before download") subtitle:RYGLocalized(@"Show a confirmation dialog before starting a download") defaultsKey:@"dw_confirm"],
												[RYGSetting switchCellWithTitle:RYGLocalized(@"Save to dedicated album") subtitle:RYGLocalized(@"Route saves into a custom album in Photos instead of the camera roll root") defaultsKey:@"save_to_ryukgram_album"],
												[self galleryAlbumNameCell],
												[RYGSetting switchCellWithTitle:RYGLocalized(@"Enhanced media resolution") subtitle:RYGLocalized(@"Spoof device profile so IG serves higher-quality images") defaultsKey:@"enhanced_media_resolution" requiresRestart:YES],
											]
										},
										@{
											@"header": RYGLocalized(@"Download queue"),
											@"footer": RYGLocalized(@"How many downloads run at once — extras wait in line and start as slots free up. Failed downloads retry automatically on network errors. Open the manager to watch, cancel, or retry downloads."),
											@"rows": @[
												[RYGSetting switchCellWithTitle:RYGLocalized(@"Auto-retry failed downloads") subtitle:RYGLocalized(@"Retry automatically when a download drops on a network error") defaultsKey:@"dl_auto_retry"],
												[RYGSetting stepperCellWithTitle:RYGLocalized(@"Auto-retry attempts") subtitle:RYGLocalized(@"Try %@ more %@ before giving up") defaultsKey:@"dl_auto_retry_count" min:1 max:5 step:1 label:@"times" singularLabel:@"time"],
												[RYGSetting stepperCellWithTitle:RYGLocalized(@"Max simultaneous downloads") subtitle:RYGLocalized(@"Run up to %@ %@ at once") defaultsKey:@"dl_max_concurrent" min:1 max:6 step:1 label:@"downloads" singularLabel:@"download"],
												[RYGSetting switchCellWithTitle:RYGLocalized(@"Keep running in background") subtitle:RYGLocalized(@"Don't pause downloads, encoding, or profile scans when you leave the app") defaultsKey:@"bg_keepalive"],
												({ RYGSetting *s = [RYGSetting buttonCellWithTitle:RYGLocalized(@"Open download manager") subtitle:RYGLocalized(@"Active, queued, and finished downloads") icon:[RYGFeatureIcons downloads] action:^{ [RYGDownloadManagerViewController present]; }]; s.whatsNewID = @"ui_downloadmanager"; s; }),
											]
										},
										@{
											@"header": RYGLocalized(@"Download history"),
											@"footer": RYGLocalized(@"How long finished, failed and cancelled downloads stay in the manager after you close the app. The files themselves are never touched — only the list."),
											@"rows": @[
												[RYGSetting menuCellWithTitle:RYGLocalized(@"Keep history for") subtitle:RYGLocalized(@"How long past downloads stay listed in the manager") menu:[self menus][@"dl_history_retention"]],
												[RYGSetting buttonCellWithTitle:RYGLocalized(@"Clear download history") subtitle:RYGLocalized(@"Empty the manager's list of past downloads") icon:[RYGSymbol symbolWithName:@"trash"] action:^{ [RYGDownloadManagerViewController presentClearHistoryConfirmation]; }],
											]
										},
										@{
											@"header": RYGLocalized(@"Gallery"),
											@"footer": RYGLocalized(@"On-device library of media downloaded through RyukGram. Save mode picks where 'Download to Photos' actually writes."),
											@"rows": @[
												[RYGSetting switchCellWithTitle:RYGLocalized(@"Enable gallery") subtitle:RYGLocalized(@"Show gallery entries in download menus and unlock the gallery button") defaultsKey:@"ryg_gallery_enabled"],
												[RYGSetting menuCellWithTitle:RYGLocalized(@"Gallery save mode") subtitle:RYGLocalized(@"Where 'Download to Photos' actually writes when gallery is on") menu:[self menus][@"gallery_save_mode"]],
												[RYGSetting switchCellWithTitle:RYGLocalized(@"Hold DM tab to open gallery") subtitle:RYGLocalized(@"Long-press the inbox button in the bottom tab bar to open RyukGram gallery") defaultsKey:@"dm_tab_long_press_gallery"],
											]
										},
										[self enhancedDownloadsSection],
										@{
											@"header": RYGLocalized(@"Legacy long-press gesture"),
											@"footer": RYGLocalized(@"Deprecated. The RyukGram action button (configured per feature in Feed/Reels/Stories) is the new way to download media. Enable this master toggle only if you prefer the old multi-finger long-press directly on the media."),
											@"rows": @[
												[RYGSetting switchCellWithTitle:RYGLocalized(@"Enable long-press gesture") subtitle:RYGLocalized(@"Master toggle for the deprecated gesture workflow (off by default)") defaultsKey:@"dw_legacy_gesture"],
												[RYGSetting menuCellWithTitle:RYGLocalized(@"Save action") subtitle:RYGLocalized(@"What happens after the gesture downloads") menu:[self menus][@"dw_save_action"]],
												[RYGSetting stepperCellWithTitle:RYGLocalized(@"Finger count for long-press") subtitle:RYGLocalized(@"Downloads with %@ %@") defaultsKey:@"dw_finger_count" min:1 max:5 step:1 label:@"fingers" singularLabel:@"finger"],
												[RYGSetting stepperCellWithTitle:RYGLocalized(@"Long-press hold time") subtitle:RYGLocalized(@"Press finger(s) for %@ %@") defaultsKey:@"dw_finger_duration" min:0 max:10 step:0.25 label:@"sec" singularLabel:@"sec"]
											]
										}]
				];
}

@end
