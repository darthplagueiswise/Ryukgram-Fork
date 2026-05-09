#import <Foundation/Foundation.h>
#import "../../Settings/SCISetting.h"

NS_ASSUME_NONNULL_BEGIN

// Builds the Settings → Interface → Notifications entry. Lives outside
// TweakSettings.m so the per-action picker generation stays self-contained.
@interface SCINotificationSettings : NSObject

+ (SCISetting *)notificationsNavCell;
+ (NSArray *)navSections;

@end

NS_ASSUME_NONNULL_END
