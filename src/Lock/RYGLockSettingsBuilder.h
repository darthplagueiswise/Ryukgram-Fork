// Builds the "Security & Privacy" entry in the main settings tree.

#import <Foundation/Foundation.h>
#import "../Settings/RYGSetting.h"

NS_ASSUME_NONNULL_BEGIN

@interface RYGLockSettingsBuilder : NSObject
+ (RYGSetting *)topLevelNavCell;
+ (RYGSetting *)groupNavCellForGroupID:(NSString *)groupID;
@end

NS_ASSUME_NONNULL_END
