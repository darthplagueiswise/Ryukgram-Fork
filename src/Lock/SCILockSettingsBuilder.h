// Builds the "Security & Privacy" entry in the main settings tree.

#import <Foundation/Foundation.h>
#import "../Settings/SCISetting.h"

NS_ASSUME_NONNULL_BEGIN

@interface SCILockSettingsBuilder : NSObject
+ (SCISetting *)topLevelNavCell;
+ (SCISetting *)groupNavCellForGroupID:(NSString *)groupID;
@end

NS_ASSUME_NONNULL_END
