#import "SCISettingsSections.h"

@implementation SCITweakSettings (Section_GalleryAlbum)

// MARK: - Gallery album name

+ (SCISetting *)galleryAlbumNameCell {
	SCISetting *cell = [SCISetting buttonCellWithTitle:SCILocalized(@"Album name")
											  subtitle:@""
												  icon:nil
												action:^{ [self promptGalleryAlbumName]; }];
	cell.dynamicValueText = ^NSString *{ return [SCITweakSettings galleryAlbumNameValueText]; };
	cell.defaultsKey = @"gallery_album_name"; // button cells ignore defaultsKey; set for the what's-new dot
	return cell;
}

+ (NSString *)galleryAlbumNameValueText {
	NSString *cur = [[SCIUtils getStringPref:@"gallery_album_name"]
		stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
	return cur.length ? cur : @"RyukGram";
}

+ (void)promptGalleryAlbumName {
	NSString *current = [SCIUtils getStringPref:@"gallery_album_name"];
	UIViewController *presenter = sciTopVC();
	UIAlertController *alert = [UIAlertController alertControllerWithTitle:SCILocalized(@"Album name")
																   message:SCILocalized(@"Name of the Photos album RyukGram saves into. Leave empty to restore the default.")
															preferredStyle:UIAlertControllerStyleAlert];
	[alert addTextFieldWithConfigurationHandler:^(UITextField *tf) {
		tf.placeholder = @"RyukGram";
		tf.text = current ?: @"";
		tf.autocorrectionType = UITextAutocorrectionTypeNo;
		tf.clearButtonMode = UITextFieldViewModeWhileEditing;
	}];
	[alert addAction:[UIAlertAction actionWithTitle:SCILocalized(@"Cancel") style:UIAlertActionStyleCancel handler:nil]];
	[alert addAction:[UIAlertAction actionWithTitle:SCILocalized(@"Save") style:UIAlertActionStyleDefault handler:^(__unused UIAlertAction *a) {
		NSString *v = [alert.textFields.firstObject.text
			stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
		[[NSUserDefaults standardUserDefaults] setObject:(v.length ? v : @"RyukGram") forKey:@"gallery_album_name"];
		[[NSNotificationCenter defaultCenter] postNotificationName:@"SCISettingsShouldReload" object:nil];
	}]];
	[presenter presentViewController:alert animated:YES completion:nil];
}

@end
