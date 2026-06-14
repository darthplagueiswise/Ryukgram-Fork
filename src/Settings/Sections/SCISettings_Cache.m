#import "SCISettingsSections.h"

@implementation SCITweakSettings (Section_Cache)

// MARK: - Cache clear

+ (SCISetting *)autoClearCacheMenuCell {
	SCISetting *cell = [SCISetting menuCellWithTitle:SCILocalized(@"Auto-clear cache")
											 subtitle:SCILocalized(@"Run a silent cache clear on launch when the interval has elapsed.")
												 menu:[self menus][@"cache_auto_clear_mode"]];
	cell.icon = [SCISymbol symbolWithName:@"clock.arrow.circlepath"];
	return cell;
}

+ (SCISetting *)preserveMessagesDBCell {
	SCISetting *cell = [SCISetting switchCellWithTitle:SCILocalized(@"Preserve messages database")
											  subtitle:SCILocalized(@"Skip the messages database when clearing — keeps DMs, drafts, and saved messages.")
										   defaultsKey:@"cache_preserve_messages_db"];
	cell.icon = [SCISymbol symbolWithIGName:@"document" fallback:@"archivebox"];
	return cell;
}

+ (SCISetting *)autoCheckCacheSizeCell {
	SCISetting *cell = [SCISetting switchCellWithTitle:SCILocalized(@"Show cache size")
											  subtitle:SCILocalized(@"Off skips the size scan when Advanced opens.")
										   defaultsKey:@"cache_auto_check_size"];
	cell.icon = [SCISymbol symbolWithName:@"magnifyingglass"];
	return cell;
}

+ (SCISetting *)clearCacheButtonCell {
	[SCICacheManager refreshSizeInBackgroundIfEnabled];
	SCISetting *cell = [SCISetting buttonCellWithTitle:SCILocalized(@"Clear cache")
											   subtitle:SCILocalized(@"Remove Instagram's cached images, videos, and temporary files.")
												   icon:[SCISymbol symbolWithName:@"trash"]
												 action:^{ [self presentClearCacheConfirmation]; }];
	cell.dynamicTitle = ^{
		if (![SCIUtils getBoolPref:@"cache_auto_check_size"]) return SCILocalized(@"Clear cache");
		uint64_t cached = [SCICacheManager cachedSize];
		if (cached == 0) return SCILocalized(@"Clear cache");
		return [NSString stringWithFormat:SCILocalized(@"Clear cache (%@)"), [SCICacheManager formattedSize:cached]];
	};
	return cell;
}

+ (void)presentClearCacheConfirmation {
	void (^showResult)(uint64_t) = ^(uint64_t bytes) {
		if (bytes == 0) {
			SCINotifyInfo(SCI_NOTIF_CACHE_CLEAR, SCILocalized(@"Nothing to clear"), nil);
			return;
		}
		NSString *msg = [NSString stringWithFormat:SCILocalized(@"Free %@ of Instagram cache."), [SCICacheManager formattedSize:bytes]];
		UIAlertController *a = [UIAlertController alertControllerWithTitle:SCILocalized(@"Clear cache") message:msg preferredStyle:UIAlertControllerStyleAlert];
		[a addAction:[UIAlertAction actionWithTitle:SCILocalized(@"Clear") style:UIAlertActionStyleDestructive handler:^(__unused UIAlertAction *x) {
			SCINotificationHandle *h = SCINotifyLoading(SCI_NOTIF_CACHE_CLEAR, SCILocalized(@"Clearing cache…"), nil);
			[SCICacheManager clearCacheWithCompletion:^(uint64_t cleared) {
				NSString *done = [NSString stringWithFormat:SCILocalized(@"Freed %@"), [SCICacheManager formattedSize:cleared]];
				if (h) [h success:SCILocalized(@"Cache cleared") subtitle:done];
				else   SCINotifySuccess(SCI_NOTIF_CACHE_CLEAR, SCILocalized(@"Cache cleared"), done);
			}];
		}]];
		[a addAction:[UIAlertAction actionWithTitle:SCILocalized(@"Cancel") style:UIAlertActionStyleCancel handler:nil]];
		[sciTopVC() presentViewController:a animated:YES completion:nil];
	};

	BOOL autoCheck = [SCIUtils getBoolPref:@"cache_auto_check_size"];
	uint64_t cached = [SCICacheManager cachedSize];
	if (autoCheck && cached > 0) { showResult(cached); return; }

	SCINotificationHandle *calc = SCINotifyLoading(SCI_NOTIF_CACHE_CLEAR, SCILocalized(@"Calculating cache size…"), nil);
	void (^onScan)(uint64_t) = ^(uint64_t bytes) {
		if (calc) [calc dismiss];
		showResult(bytes);
	};
	if (autoCheck) [SCICacheManager getCacheSizeWithCompletion:onScan];
	else		   [SCICacheManager getCacheSizeTransientWithCompletion:onScan];
}

@end
