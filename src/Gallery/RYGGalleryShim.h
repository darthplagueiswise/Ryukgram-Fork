// RYGGalleryShim — stub-out the legacy feedback pill / action
// identifier API so the ported gallery code compiles without pulling in the
// full pill subsystem. Falls back to our existing showToastForDuration: API.

#import <UIKit/UIKit.h>
#import "../Utils.h"

NS_ASSUME_NONNULL_BEGIN

typedef NS_ENUM(NSInteger, RYGFeedbackPillTone) {
	RYGFeedbackPillToneSuccess = 0,
	RYGFeedbackPillToneInfo,
	RYGFeedbackPillToneWarning,
	RYGFeedbackPillToneError
};

extern NSString *const kRYGFeedbackActionGalleryDeleteFile;
extern NSString *const kRYGFeedbackActionGalleryDeleteSelected;
extern NSString *const kRYGFeedbackActionGalleryBulkDelete;
extern NSString *const kRYGFeedbackActionGalleryOpenOriginal;
extern NSString *const kRYGFeedbackActionGalleryOpenProfile;

@interface RYGUtils (RYGGalleryShim)
+ (void)showToastForActionIdentifier:(nullable NSString *)actionIdentifier
							duration:(NSTimeInterval)duration
							   title:(nullable NSString *)title
							subtitle:(nullable NSString *)subtitle
						iconResource:(nullable NSString *)iconResource;
+ (void)showToastForActionIdentifier:(nullable NSString *)actionIdentifier
							duration:(NSTimeInterval)duration
							   title:(nullable NSString *)title
							subtitle:(nullable NSString *)subtitle
						iconResource:(nullable NSString *)iconResource
								tone:(RYGFeedbackPillTone)tone;
@end

NS_ASSUME_NONNULL_END
