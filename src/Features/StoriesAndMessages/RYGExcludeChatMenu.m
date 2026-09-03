#import "RYGExcludeChatMenu.h"
#import "RYGExcludedThreads.h"
#import "../../UI/RYGIcon.h"
#import "../../Localization/RYGLocalization.h"

@implementation RYGExcludeChatMenu

+ (UIAction *)actionForEntry:(NSDictionary *)entry {
    if (![RYGExcludedThreads isFeatureEnabled]) return nil;
    NSString *tid = entry[@"threadId"];
    if (!tid.length) return nil;

    BOOL inList = [RYGExcludedThreads isInList:tid];
    BOOL blockSelected = [RYGExcludedThreads isBlockSelectedMode];
    NSString *addLabel = blockSelected ? RYGLocalized(@"Add to block list") : RYGLocalized(@"Exclude chat");
    NSString *removeLabel = blockSelected ? RYGLocalized(@"Remove from block list") : RYGLocalized(@"Un-exclude chat");
    NSString *title = inList ? removeLabel : addLabel;
    UIImage *img = [RYGIcon imageNamed:(inList ? @"eye.fill" : @"eye.slash")];

    return [UIAction actionWithTitle:title image:img identifier:nil
                              handler:^(__kindof UIAction *_) {
        if (inList) [RYGExcludedThreads removeThreadId:tid];
        else        [RYGExcludedThreads addOrUpdateEntry:entry];
    }];
}

@end
