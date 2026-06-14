#import <Foundation/Foundation.h>
#import "SCISetting.h"
#import "SCISymbol.h"
#import "../Utils.h"
#import "../Tweak.h"

NS_ASSUME_NONNULL_BEGIN

@interface SCITweakSettings : NSObject

+ (NSArray *)sections;
+ (NSString *)title;

@end

// Implemented in section files under Sections/. Declared as a category so the
// implementations don't conflict with the primary @interface.
@interface SCITweakSettings (Public)
+ (NSDictionary *)menus;
+ (void)presentClearCacheConfirmation;
+ (NSArray *)rebuildAdvancedEncodingSlotInSections:(NSArray *)sections;
@end

NS_ASSUME_NONNULL_END
