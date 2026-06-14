#import "SCISettingsSections.h"
#import "../../Downloader/SCIDownloadManagerViewController.h"

@implementation SCITweakSettings (Section_MediaSaving)

+ (SCISetting *)mediaSavingNavCell {
	return [SCISetting navigationCellWithTitle:SCILocalized(@"Media saving")
										   subtitle:@""
											   icon:[SCISymbol symbolWithIGName:@"download_filled" fallback:@"tray.and.arrow.down"]
										navSections:@[@{
											@"header": SCILocalized(@"Downloads"),
											@"footer": SCILocalized(@"When \"Save to dedicated album\" is on, downloads and share-sheet \"Save to Photos\" picks are routed into a named album in your Photos library. Tap \"Album name\" to change it."),
											@"rows": @[
												[SCISetting switchCellWithTitle:SCILocalized(@"Confirm before download") subtitle:SCILocalized(@"Show a confirmation dialog before starting a download") defaultsKey:@"dw_confirm"],
												[SCISetting switchCellWithTitle:SCILocalized(@"Save to dedicated album") subtitle:SCILocalized(@"Route saves into a custom album in Photos instead of the camera roll root") defaultsKey:@"save_to_ryukgram_album"],
												[self galleryAlbumNameCell],
												[SCISetting switchCellWithTitle:SCILocalized(@"Enhanced media resolution") subtitle:SCILocalized(@"Spoof device profile so IG serves higher-quality images") defaultsKey:@"enhanced_media_resolution" requiresRestart:YES],
											]
										},
										@{
											@"header": SCILocalized(@"Download queue"),
											@"footer": SCILocalized(@"How many downloads run at once — extras wait in line and start as slots free up. Failed downloads retry automatically on network errors. Open the manager to watch, cancel, or retry downloads."),
											@"rows": @[
												[SCISetting switchCellWithTitle:SCILocalized(@"Auto-retry failed downloads") subtitle:SCILocalized(@"Retry automatically when a download drops on a network error") defaultsKey:@"dl_auto_retry"],
												[SCISetting stepperCellWithTitle:SCILocalized(@"Auto-retry attempts") subtitle:SCILocalized(@"Try %@ more %@ before giving up") defaultsKey:@"dl_auto_retry_count" min:1 max:5 step:1 label:@"times" singularLabel:@"time"],
												[SCISetting stepperCellWithTitle:SCILocalized(@"Max simultaneous downloads") subtitle:SCILocalized(@"Run up to %@ %@ at once") defaultsKey:@"dl_max_concurrent" min:1 max:6 step:1 label:@"downloads" singularLabel:@"download"],
												[SCISetting switchCellWithTitle:SCILocalized(@"Keep running in background") subtitle:SCILocalized(@"Don't pause downloads, encoding, or profile scans when you leave the app") defaultsKey:@"bg_keepalive"],
												({ SCISetting *s = [SCISetting buttonCellWithTitle:SCILocalized(@"Open download manager") subtitle:SCILocalized(@"Active, queued, and finished downloads") icon:[SCISymbol symbolWithIGName:@"download_filled" fallback:@"arrow.down.circle"] action:^{ [SCIDownloadManagerViewController present]; }]; s.whatsNewID = @"ui_downloadmanager"; s; }),
											]
										},
										@{
											@"header": SCILocalized(@"Gallery"),
											@"footer": SCILocalized(@"On-device library of media downloaded through RyukGram. Save mode picks where 'Download to Photos' actually writes."),
											@"rows": @[
												[SCISetting switchCellWithTitle:SCILocalized(@"Enable gallery") subtitle:SCILocalized(@"Show gallery entries in download menus and unlock the gallery button") defaultsKey:@"sci_gallery_enabled"],
												[SCISetting menuCellWithTitle:SCILocalized(@"Gallery save mode") subtitle:SCILocalized(@"Where 'Download to Photos' actually writes when gallery is on") menu:[self menus][@"gallery_save_mode"]],
												[SCISetting switchCellWithTitle:SCILocalized(@"Hold DM tab to open gallery") subtitle:SCILocalized(@"Long-press the inbox button in the bottom tab bar to open RyukGram gallery") defaultsKey:@"dm_tab_long_press_gallery"],
											]
										},
										[self enhancedDownloadsSection],
										@{
											@"header": SCILocalized(@"Legacy long-press gesture"),
											@"footer": SCILocalized(@"Deprecated. The RyukGram action button (configured per feature in Feed/Reels/Stories) is the new way to download media. Enable this master toggle only if you prefer the old multi-finger long-press directly on the media."),
											@"rows": @[
												[SCISetting switchCellWithTitle:SCILocalized(@"Enable long-press gesture") subtitle:SCILocalized(@"Master toggle for the deprecated gesture workflow (off by default)") defaultsKey:@"dw_legacy_gesture"],
												[SCISetting menuCellWithTitle:SCILocalized(@"Save action") subtitle:SCILocalized(@"What happens after the gesture downloads") menu:[self menus][@"dw_save_action"]],
												[SCISetting stepperCellWithTitle:SCILocalized(@"Finger count for long-press") subtitle:SCILocalized(@"Downloads with %@ %@") defaultsKey:@"dw_finger_count" min:1 max:5 step:1 label:@"fingers" singularLabel:@"finger"],
												[SCISetting stepperCellWithTitle:SCILocalized(@"Long-press hold time") subtitle:SCILocalized(@"Press finger(s) for %@ %@") defaultsKey:@"dw_finger_duration" min:0 max:10 step:0.25 label:@"sec" singularLabel:@"sec"]
											]
										}]
				];
}

@end
