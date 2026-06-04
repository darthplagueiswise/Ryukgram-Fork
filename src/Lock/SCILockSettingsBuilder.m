#import "SCILockSettingsBuilder.h"
#import "UI/SCILockSecurityViewController.h"
#import "UI/SCILockGroupDetailViewController.h"
#import "SCILockGroups.h"
#import "../Settings/SCISymbol.h"
#import "../Localization/SCILocalization.h"

@implementation SCILockSettingsBuilder

+ (SCISetting *)topLevelNavCell {
    return [SCISetting navigationCellWithTitle:SCILocalized(@"Security & Privacy")
                                       subtitle:@""
                                           icon:[SCISymbol symbolWithIGName:@"ig_icon_lock_pano_outline_24" fallback:@"lock.shield"]
                                 viewController:[SCILockSecurityViewController new]];
}

+ (SCISetting *)groupNavCellForGroupID:(NSString *)groupID {
    SCILockGroupInfo *info = SCILockGroupInfoFor(groupID);
    if (!info) return nil;
    return [SCISetting navigationCellWithTitle:info.displayName
                                       subtitle:@""
                                           icon:[SCISymbol symbolWithIGName:info.iconSymbol fallback:@"lock.fill"]
                                 viewController:[[SCILockGroupDetailViewController alloc] initWithGroupID:groupID]];
}

@end
