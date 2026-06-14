#import "SCIExcludeChatMenu.h"
#import "SCIExcludedThreads.h"
#import "../../UI/SCIIcon.h"
#import "../../Localization/SCILocalization.h"

@implementation SCIExcludeChatMenu

+ (UIAction *)actionForEntry:(NSDictionary *)entry {
    if (![SCIExcludedThreads isFeatureEnabled]) return nil;
    NSString *tid = entry[@"threadId"];
    if (!tid.length) return nil;

    BOOL inList = [SCIExcludedThreads isInList:tid];
    BOOL blockSelected = [SCIExcludedThreads isBlockSelectedMode];
    NSString *addLabel = blockSelected ? SCILocalized(@"Add to block list") : SCILocalized(@"Exclude chat");
    NSString *removeLabel = blockSelected ? SCILocalized(@"Remove from block list") : SCILocalized(@"Un-exclude chat");
    NSString *title = inList ? removeLabel : addLabel;
    UIImage *img = [SCIIcon imageNamed:(inList ? @"eye.fill" : @"eye.slash")];

    return [UIAction actionWithTitle:title image:img identifier:nil
                              handler:^(__kindof UIAction *_) {
        if (inList) [SCIExcludedThreads removeThreadId:tid];
        else        [SCIExcludedThreads addOrUpdateEntry:entry];
    }];
}

@end
