#import "RYGSettingsSections.h"

@implementation RYGTweakSettings (Section_GalleryAlbum)

// MARK: - Gallery album name

+ (RYGSetting *)galleryAlbumNameCell {
	RYGSetting *cell = [RYGSetting buttonCellWithTitle:RYGLocalized(@"Album name")
											  subtitle:@""
												  icon:nil
												action:^{ [self promptGalleryAlbumName]; }];
	cell.dynamicValueText = ^NSString *{ return [RYGTweakSettings galleryAlbumNameValueText]; };
	cell.defaultsKey = @"gallery_album_name"; // button cells ignore defaultsKey; set for the what's-new dot
	return cell;
}

+ (NSString *)galleryAlbumNameValueText {
	NSString *cur = [[RYGUtils getStringPref:@"gallery_album_name"]
		stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
	return cur.length ? cur : @"RyukGram";
}

+ (void)promptGalleryAlbumName {
	NSString *current = [RYGUtils getStringPref:@"gallery_album_name"];
	UIViewController *presenter = rygTopVC();
	UIAlertController *alert = [UIAlertController alertControllerWithTitle:RYGLocalized(@"Album name")
																   message:RYGLocalized(@"Name of the Photos album RyukGram saves into. Leave empty to restore the default.")
															preferredStyle:UIAlertControllerStyleAlert];
	[alert addTextFieldWithConfigurationHandler:^(UITextField *tf) {
		tf.placeholder = @"RyukGram";
		tf.text = current ?: @"";
		tf.autocorrectionType = UITextAutocorrectionTypeNo;
		tf.clearButtonMode = UITextFieldViewModeWhileEditing;
	}];
	[alert addAction:[UIAlertAction actionWithTitle:RYGLocalized(@"Cancel") style:UIAlertActionStyleCancel handler:nil]];
	[alert addAction:[UIAlertAction actionWithTitle:RYGLocalized(@"Save") style:UIAlertActionStyleDefault handler:^(__unused UIAlertAction *a) {
		NSString *v = [alert.textFields.firstObject.text
			stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
		[[NSUserDefaults standardUserDefaults] setObject:(v.length ? v : @"RyukGram") forKey:@"gallery_album_name"];
		[[NSNotificationCenter defaultCenter] postNotificationName:@"RYGSettingsShouldReload" object:nil];
	}]];
	[presenter presentViewController:alert animated:YES completion:nil];
}

@end
