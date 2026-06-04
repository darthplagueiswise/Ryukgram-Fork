#import "SCISettingsSections.h"
#import <objc/runtime.h>
#import "../../Localization/SCILocalization.h"

// Copies imported .strings into the writable override dir.
@interface SCILocImportHelper : NSObject <UIDocumentPickerDelegate>
@end

@implementation SCILocImportHelper
- (void)documentPicker:(UIDocumentPickerViewController *)controller didPickDocumentsAtURLs:(NSArray<NSURL *> *)urls {
	if (!urls.count) return;
	NSURL *src = urls.firstObject;
	NSString *code = objc_getAssociatedObject(controller, "sci_lang");
	if (!code.length) return;

	NSDictionary *test = [NSDictionary dictionaryWithContentsOfURL:src];
	if (!test.count) {
		UIAlertController *a = [UIAlertController alertControllerWithTitle:SCILocalized(@"Error")
			message:SCILocalized(@"File is empty or not a valid .strings file.") preferredStyle:UIAlertControllerStyleAlert];
		[a addAction:[UIAlertAction actionWithTitle:SCILocalized(@"OK") style:UIAlertActionStyleCancel handler:nil]];
		UIViewController *top = controller.presentingViewController ?: UIApplication.sharedApplication.keyWindow.rootViewController;
		[top presentViewController:a animated:YES completion:nil];
		return;
	}

	NSString *lproj = [NSString stringWithFormat:@"%@.lproj", code];
	NSString *dir = [SCILocalizationOverridePath() stringByAppendingPathComponent:lproj];
	NSFileManager *fm = [NSFileManager defaultManager];
	[fm createDirectoryAtPath:dir withIntermediateDirectories:YES attributes:nil error:nil];
	NSString *dest = [dir stringByAppendingPathComponent:@"Localizable.strings"];
	[fm removeItemAtPath:dest error:nil];
	BOOL ok = [fm copyItemAtPath:src.path toPath:dest error:nil];

	NSString *msg = ok
		? [NSString stringWithFormat:SCILocalized(@"Updated %@ (%ld keys). Restart to apply."), code, (long)test.count]
		: SCILocalized(@"Could not write file.");
	UIAlertController *a = [UIAlertController alertControllerWithTitle:ok ? SCILocalized(@"Done") : SCILocalized(@"Error")
															   message:msg preferredStyle:UIAlertControllerStyleAlert];
	if (ok) {
		[a addAction:[UIAlertAction actionWithTitle:SCILocalized(@"Restart now") style:UIAlertActionStyleDefault
											handler:^(__unused UIAlertAction *x) { [SCIUtils showRestartConfirmation]; }]];
	}
	[a addAction:[UIAlertAction actionWithTitle:SCILocalized(@"OK") style:UIAlertActionStyleCancel handler:nil]];
	UIViewController *top = UIApplication.sharedApplication.keyWindow.rootViewController;
	while (top.presentedViewController) top = top.presentedViewController;
	[top presentViewController:a animated:YES completion:nil];
}
@end

@implementation SCITweakSettings (Section_Localization)

+ (void)presentLocalizationExport {
	UIAlertController *picker = [UIAlertController alertControllerWithTitle:SCILocalized(@"Export strings")
																	message:SCILocalized(@"Pick a language to export")
															 preferredStyle:UIAlertControllerStyleActionSheet];
	for (NSDictionary *lang in SCIAvailableLanguages()) {
		NSString *code = lang[@"code"];
		if ([code isEqualToString:@"system"]) continue;
		NSString *title = [NSString stringWithFormat:@"%@ (%@)", lang[@"native"], code];
		[picker addAction:[UIAlertAction actionWithTitle:title
												   style:UIAlertActionStyleDefault
												 handler:^(__unused UIAlertAction *a) { [self exportStringsForLanguage:code]; }]];
	}
	[picker addAction:[UIAlertAction actionWithTitle:SCILocalized(@"Cancel") style:UIAlertActionStyleCancel handler:nil]];
	[sciTopVC() presentViewController:picker animated:YES completion:nil];
}

// Override dir wins over the shipped bundle so users can re-export their own edits.
+ (void)exportStringsForLanguage:(NSString *)code {
	NSFileManager *fm = [NSFileManager defaultManager];
	NSString *lproj = [NSString stringWithFormat:@"%@.lproj", code];
	NSString *path = [[SCILocalizationOverridePath() stringByAppendingPathComponent:lproj]
					  stringByAppendingPathComponent:@"Localizable.strings"];
	if (![fm fileExistsAtPath:path]) {
		path = [SCILocalizationBundle() pathForResource:code ofType:@"lproj"];
		if (path) path = [path stringByAppendingPathComponent:@"Localizable.strings"];
	}
	if (!path || ![fm fileExistsAtPath:path]) {
		[SCIUtils showErrorHUDWithDescription:SCILocalized(@"Localization file not found")];
		return;
	}
	NSURL *url = [NSURL fileURLWithPath:path];
	UIActivityViewController *ac = [[UIActivityViewController alloc] initWithActivityItems:@[url] applicationActivities:nil];
	UIViewController *top = sciTopVC();
	if (!top) return;
	if ([UIDevice currentDevice].userInterfaceIdiom == UIUserInterfaceIdiomPad) {
		ac.popoverPresentationController.sourceView = top.view;
		ac.popoverPresentationController.sourceRect = CGRectMake(CGRectGetMidX(top.view.bounds), CGRectGetMidY(top.view.bounds), 1, 1);
	}
	[top presentViewController:ac animated:YES completion:nil];
}

+ (void)presentLocalizationImport {
	NSArray *langs = SCIAvailableLanguages();

	UIAlertController *picker = [UIAlertController alertControllerWithTitle:SCILocalized(@"Update localization")
																	message:SCILocalized(@"Pick a language to update, or add a new one")
															 preferredStyle:UIAlertControllerStyleActionSheet];
	for (NSDictionary *lang in langs) {
		NSString *code = lang[@"code"];
		if ([code isEqualToString:@"system"]) continue;
		NSString *title = [NSString stringWithFormat:@"%@ (%@)", lang[@"native"], code];
		[picker addAction:[UIAlertAction actionWithTitle:title
												   style:UIAlertActionStyleDefault
												 handler:^(__unused UIAlertAction *a) {
			[self importStringsForLanguage:code];
		}]];
	}

	[picker addAction:[UIAlertAction actionWithTitle:SCILocalized(@"+ Add new language")
											   style:UIAlertActionStyleDefault
											 handler:^(__unused UIAlertAction *a) {
		[self promptNewLanguageCode];
	}]];
	[picker addAction:[UIAlertAction actionWithTitle:SCILocalized(@"Cancel") style:UIAlertActionStyleCancel handler:nil]];
	[sciTopVC() presentViewController:picker animated:YES completion:nil];
}

+ (void)presentLocalizationReset {
	NSString *overrides = SCILocalizationOverridePath();
	NSFileManager *fm = [NSFileManager defaultManager];
	NSArray *contents = [fm contentsOfDirectoryAtPath:overrides error:nil];
	NSMutableArray<NSString *> *codes = [NSMutableArray array];
	for (NSString *name in [contents sortedArrayUsingSelector:@selector(compare:)]) {
		if (![name hasSuffix:@".lproj"]) continue;
		NSString *stringsPath = [[overrides stringByAppendingPathComponent:name]
								 stringByAppendingPathComponent:@"Localizable.strings"];
		if (![fm fileExistsAtPath:stringsPath]) continue;
		[codes addObject:[name stringByDeletingPathExtension]];
	}

	if (!codes.count) {
		UIAlertController *a = [UIAlertController alertControllerWithTitle:SCILocalized(@"No overrides")
																   message:SCILocalized(@"No imported localization files to reset.")
															preferredStyle:UIAlertControllerStyleAlert];
		[a addAction:[UIAlertAction actionWithTitle:SCILocalized(@"OK") style:UIAlertActionStyleCancel handler:nil]];
		[sciTopVC() presentViewController:a animated:YES completion:nil];
		return;
	}

	UIAlertController *picker = [UIAlertController alertControllerWithTitle:SCILocalized(@"Reset localization")
																	message:SCILocalized(@"Pick a language to delete the imported file")
															 preferredStyle:UIAlertControllerStyleActionSheet];
	for (NSString *code in codes) {
		NSLocale *loc = [NSLocale localeWithLocaleIdentifier:code];
		NSString *native = [loc localizedStringForLanguageCode:code] ?: code;
		if (native.length) native = [[[native substringToIndex:1] uppercaseString]
									  stringByAppendingString:[native substringFromIndex:1]];
		NSString *title = [NSString stringWithFormat:@"%@ (%@)", native, code];
		[picker addAction:[UIAlertAction actionWithTitle:title
												   style:UIAlertActionStyleDestructive
												 handler:^(__unused UIAlertAction *a) {
			[self resetLocalizationForCode:code];
		}]];
	}
	[picker addAction:[UIAlertAction actionWithTitle:SCILocalized(@"Cancel") style:UIAlertActionStyleCancel handler:nil]];
	[sciTopVC() presentViewController:picker animated:YES completion:nil];
}

+ (void)resetLocalizationForCode:(NSString *)code {
	NSString *overrides = SCILocalizationOverridePath();
	NSString *lproj = [overrides stringByAppendingPathComponent:
						[NSString stringWithFormat:@"%@.lproj", code]];
	NSError *err = nil;
	[[NSFileManager defaultManager] removeItemAtPath:lproj error:&err];

	NSString *msg = err
		? [NSString stringWithFormat:SCILocalized(@"Could not delete: %@"), err.localizedDescription]
		: [NSString stringWithFormat:SCILocalized(@"Deleted %@ override. Restart to apply."), code];
	UIAlertController *a = [UIAlertController alertControllerWithTitle:err ? SCILocalized(@"Error") : SCILocalized(@"Done")
															   message:msg
														preferredStyle:UIAlertControllerStyleAlert];
	if (!err) {
		SCILocalizationReset();
		[a addAction:[UIAlertAction actionWithTitle:SCILocalized(@"Restart now") style:UIAlertActionStyleDefault
											handler:^(__unused UIAlertAction *x) { [SCIUtils showRestartConfirmation]; }]];
	}
	[a addAction:[UIAlertAction actionWithTitle:SCILocalized(@"OK") style:UIAlertActionStyleCancel handler:nil]];
	[sciTopVC() presentViewController:a animated:YES completion:nil];
}

+ (void)refreshFakeCountSubtitlesInVC:(UIViewController *)vc {
	if ([vc isKindOfClass:[UINavigationController class]])
		vc = [(UINavigationController *)vc topViewController];
	if (![vc respondsToSelector:@selector(sections)]) return;
	NSArray *sections = [vc valueForKey:@"sections"];
	NSDictionary *map = @{
		SCILocalized(@"Follower count"):  @"fake_follower_count_value",
		SCILocalized(@"Following count"): @"fake_following_count_value",
		SCILocalized(@"Post count"):	  @"fake_post_count_value",
	};
	for (NSDictionary *section in sections) {
		for (SCISetting *row in section[@"rows"]) {
			NSString *k = map[row.title];
			if (!k) continue;
			NSString *v = [[NSUserDefaults standardUserDefaults] stringForKey:k];
			row.subtitle = v.length ? v : SCILocalized(@"Tap to set");
		}
	}
	if ([vc respondsToSelector:@selector(tableView)]) {
		id tv = [vc performSelector:@selector(tableView)];
		if ([tv respondsToSelector:@selector(reloadData)])
			[tv performSelector:@selector(reloadData)];
	}
}

+ (void)promptFakeCountForKey:(NSString *)key title:(NSString *)title {
	NSString *current = [[NSUserDefaults standardUserDefaults] stringForKey:key];
	UIViewController *presenter = sciTopVC();
	UIAlertController *alert = [UIAlertController alertControllerWithTitle:title
																   message:nil
															preferredStyle:UIAlertControllerStyleAlert];
	[alert addTextFieldWithConfigurationHandler:^(UITextField *tf) {
		tf.placeholder = SCILocalized(@"e.g. 1000000");
		tf.text = current ?: @"";
		tf.keyboardType = UIKeyboardTypeNumberPad;
	}];
	[alert addAction:[UIAlertAction actionWithTitle:SCILocalized(@"Cancel") style:UIAlertActionStyleCancel handler:nil]];
	[alert addAction:[UIAlertAction actionWithTitle:SCILocalized(@"Save") style:UIAlertActionStyleDefault handler:^(__unused UIAlertAction *a) {
		NSString *v = [alert.textFields.firstObject.text stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceCharacterSet]];
		if (v.length == 0) {
			[[NSUserDefaults standardUserDefaults] removeObjectForKey:key];
		} else {
			[[NSUserDefaults standardUserDefaults] setObject:v forKey:key];
		}
		[self refreshFakeCountSubtitlesInVC:presenter];
	}]];
	[presenter presentViewController:alert animated:YES completion:nil];
}

+ (void)promptNewLanguageCode {
	UIAlertController *alert = [UIAlertController alertControllerWithTitle:SCILocalized(@"Add language")
																   message:SCILocalized(@"Enter the language code (e.g. fr, de, ja)")
															preferredStyle:UIAlertControllerStyleAlert];
	[alert addTextFieldWithConfigurationHandler:^(UITextField *tf) { tf.placeholder = @"fr"; }];
	[alert addAction:[UIAlertAction actionWithTitle:SCILocalized(@"Cancel") style:UIAlertActionStyleCancel handler:nil]];
	[alert addAction:[UIAlertAction actionWithTitle:SCILocalized(@"Next") style:UIAlertActionStyleDefault handler:^(__unused UIAlertAction *a) {
		NSString *code = [alert.textFields.firstObject.text stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceCharacterSet]];
		if (code.length < 2 || code.length > 5) return;
		[self importStringsForLanguage:code];
	}]];
	[sciTopVC() presentViewController:alert animated:YES completion:nil];
}

+ (void)importStringsForLanguage:(NSString *)langCode {
	UIViewController *top = sciTopVC();
	if (!top) return;

	#pragma clang diagnostic push
	#pragma clang diagnostic ignored "-Wdeprecated-declarations"
	UIDocumentPickerViewController *dp = [[UIDocumentPickerViewController alloc]
		initWithDocumentTypes:@[@"public.plain-text", @"com.apple.xcode.strings-text", @"public.data"] inMode:UIDocumentPickerModeImport];
	#pragma clang diagnostic pop

	dp.allowsMultipleSelection = NO;
	dp.delegate = (id<UIDocumentPickerDelegate>)[self sharedImportHelper];
	objc_setAssociatedObject(dp, "sci_lang", [langCode copy], OBJC_ASSOCIATION_COPY_NONATOMIC);
	[top presentViewController:dp animated:YES completion:nil];
}

+ (id)sharedImportHelper {
	static id helper = nil;
	static dispatch_once_t onceToken;
	dispatch_once(&onceToken, ^{
		helper = [SCILocImportHelper new];
	});
	return helper;
}

@end
