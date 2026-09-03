#import "RYGGalleryShim.h"
#import "../Utils.h"

NSString *const kRYGFeedbackActionGalleryDeleteFile	 = @"gallery_delete_file";
NSString *const kRYGFeedbackActionGalleryDeleteSelected = @"gallery_delete_selected";
NSString *const kRYGFeedbackActionGalleryBulkDelete	 = @"gallery_bulk_delete";
NSString *const kRYGFeedbackActionGalleryOpenOriginal   = @"gallery_open_original";
NSString *const kRYGFeedbackActionGalleryOpenProfile	= @"gallery_open_profile";

@implementation RYGUtils (RYGGalleryShim)

+ (void)showToastForActionIdentifier:(NSString *)actionIdentifier
							duration:(NSTimeInterval)duration
							   title:(NSString *)title
							subtitle:(NSString *)subtitle
						iconResource:(NSString *)iconResource {
	[RYGUtils showToastForDuration:duration title:title ?: @"" subtitle:subtitle ?: @""];
}

+ (void)showToastForActionIdentifier:(NSString *)actionIdentifier
							duration:(NSTimeInterval)duration
							   title:(NSString *)title
							subtitle:(NSString *)subtitle
						iconResource:(NSString *)iconResource
								tone:(RYGFeedbackPillTone)tone {
	[RYGUtils showToastForDuration:duration title:title ?: @"" subtitle:subtitle ?: @""];
}

@end
