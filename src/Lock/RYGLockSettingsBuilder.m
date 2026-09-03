#import "RYGLockSettingsBuilder.h"
#import "UI/RYGLockSecurityViewController.h"
#import "UI/RYGLockGroupDetailViewController.h"
#import "RYGLockGroups.h"
#import "../Settings/RYGSymbol.h"
#import "../Localization/RYGLocalization.h"

@implementation RYGLockSettingsBuilder

+ (RYGSetting *)topLevelNavCell {
    return [RYGSetting navigationCellWithTitle:RYGLocalized(@"Security & Privacy")
                                       subtitle:@""
                                           icon:[RYGSymbol symbolWithIGName:@"ig_icon_lock_pano_outline_24" fallback:@"lock.shield"]
                                 viewController:[RYGLockSecurityViewController new]];
}

+ (RYGSetting *)groupNavCellForGroupID:(NSString *)groupID {
    RYGLockGroupInfo *info = RYGLockGroupInfoFor(groupID);
    if (!info) return nil;
    return [RYGSetting navigationCellWithTitle:info.displayName
                                       subtitle:@""
                                           icon:[RYGSymbol symbolWithIGName:info.iconSymbol fallback:@"lock.fill"]
                                 viewController:[[RYGLockGroupDetailViewController alloc] initWithGroupID:groupID]];
}

@end
