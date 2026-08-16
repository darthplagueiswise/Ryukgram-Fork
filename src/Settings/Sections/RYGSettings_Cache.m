#import "RYGSettingsSections.h"

@implementation RYGTweakSettings (Section_Cache)

// MARK: - Cache clear

+ (RYGSetting *)autoClearCacheMenuCell {
	RYGSetting *cell = [RYGSetting menuCellWithTitle:RYGLocalized(@"Auto-clear cache")
											 subtitle:RYGLocalized(@"Run a silent cache clear on launch when the interval has elapsed.")
												 menu:[self menus][@"cache_auto_clear_mode"]];
	cell.icon = [RYGSymbol symbolWithName:@"clock.arrow.circlepath"];
	return cell;
}

+ (RYGSetting *)preserveMessagesDBCell {
	RYGSetting *cell = [RYGSetting switchCellWithTitle:RYGLocalized(@"Preserve messages database")
											  subtitle:RYGLocalized(@"Skip the messages database when clearing — keeps DMs, drafts, and saved messages.")
										   defaultsKey:@"cache_preserve_messages_db"];
	cell.icon = [RYGSymbol symbolWithIGName:@"document" fallback:@"archivebox"];
	return cell;
}

+ (RYGSetting *)autoCheckCacheSizeCell {
	RYGSetting *cell = [RYGSetting switchCellWithTitle:RYGLocalized(@"Show cache size")
											  subtitle:RYGLocalized(@"Off skips the size scan when Advanced opens.")
										   defaultsKey:@"cache_auto_check_size"];
	cell.icon = [RYGSymbol symbolWithName:@"magnifyingglass"];
	return cell;
}

+ (RYGSetting *)clearCacheButtonCell {
	[RYGCacheManager refreshSizeInBackgroundIfEnabled];
	RYGSetting *cell = [RYGSetting buttonCellWithTitle:RYGLocalized(@"Clear cache")
											   subtitle:RYGLocalized(@"Remove Instagram's cached images, videos, and temporary files.")
												   icon:[RYGSymbol symbolWithName:@"trash"]
												 action:^{ [self presentClearCacheConfirmation]; }];
	cell.dynamicTitle = ^{
		if (![RYGUtils getBoolPref:@"cache_auto_check_size"]) return RYGLocalized(@"Clear cache");
		uint64_t cached = [RYGCacheManager cachedSize];
		if (cached == 0) return RYGLocalized(@"Clear cache");
		return [NSString stringWithFormat:RYGLocalized(@"Clear cache (%@)"), [RYGCacheManager formattedSize:cached]];
	};
	return cell;
}

+ (void)presentClearCacheConfirmation {
	void (^showResult)(uint64_t) = ^(uint64_t bytes) {
		if (bytes == 0) {
			RYGNotifyInfo(RYG_NOTIF_CACHE_CLEAR, RYGLocalized(@"Nothing to clear"), nil);
			return;
		}
		NSString *msg = [NSString stringWithFormat:RYGLocalized(@"Free %@ of Instagram cache."), [RYGCacheManager formattedSize:bytes]];
		UIAlertController *a = [UIAlertController alertControllerWithTitle:RYGLocalized(@"Clear cache") message:msg preferredStyle:UIAlertControllerStyleAlert];
		[a addAction:[UIAlertAction actionWithTitle:RYGLocalized(@"Clear") style:UIAlertActionStyleDestructive handler:^(__unused UIAlertAction *x) {
			RYGNotificationHandle *h = RYGNotifyLoading(RYG_NOTIF_CACHE_CLEAR, RYGLocalized(@"Clearing cache…"), nil);
			[RYGCacheManager clearCacheWithCompletion:^(uint64_t cleared) {
				NSString *done = [NSString stringWithFormat:RYGLocalized(@"Freed %@"), [RYGCacheManager formattedSize:cleared]];
				if (h) [h success:RYGLocalized(@"Cache cleared") subtitle:done];
				else   RYGNotifySuccess(RYG_NOTIF_CACHE_CLEAR, RYGLocalized(@"Cache cleared"), done);
			}];
		}]];
		[a addAction:[UIAlertAction actionWithTitle:RYGLocalized(@"Cancel") style:UIAlertActionStyleCancel handler:nil]];
		[rygTopVC() presentViewController:a animated:YES completion:nil];
	};

	BOOL autoCheck = [RYGUtils getBoolPref:@"cache_auto_check_size"];
	uint64_t cached = [RYGCacheManager cachedSize];
	if (autoCheck && cached > 0) { showResult(cached); return; }

	RYGNotificationHandle *calc = RYGNotifyLoading(RYG_NOTIF_CACHE_CLEAR, RYGLocalized(@"Calculating cache size…"), nil);
	void (^onScan)(uint64_t) = ^(uint64_t bytes) {
		if (calc) [calc dismiss];
		showResult(bytes);
	};
	if (autoCheck) [RYGCacheManager getCacheSizeWithCompletion:onScan];
	else		   [RYGCacheManager getCacheSizeTransientWithCompletion:onScan];
}

@end
