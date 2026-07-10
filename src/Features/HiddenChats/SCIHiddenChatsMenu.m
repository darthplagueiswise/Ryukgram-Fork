#import "SCIHiddenChatsMenu.h"
#import "SCIHiddenChats.h"
#import "../../UI/SCIIcon.h"
#import "../../UI/Notification/SCINotificationCenter.h"
#import "../../UI/Notification/SCINotificationActions.h"
#import "../../Localization/SCILocalization.h"

@implementation SCIHiddenChatsMenu

+ (NSArray<UIAction *> *)actionsForEntry:(NSDictionary *)entry {
    NSString *tid = entry[@"threadId"];
    if (![tid isKindOfClass:[NSString class]] || !tid.length) return @[];

    // A hidden row is only reachable while the list is revealed — offer Unhide there.
    if ([SCIHiddenChats isHidden:tid]) {
        UIAction *unhide = [UIAction actionWithTitle:SCILocalized(@"Unhide chat")
                                               image:[SCIIcon imageNamed:@"ig_icon_direct_prism_outline_24" pointSize:20]
                                          identifier:nil
                                             handler:^(__kindof UIAction *_) {
            [SCIHiddenChats removeThreadId:tid];
            [SCIHiddenChats refreshInboxInPlace];
            SCINotifySuccess(SCI_NOTIF_LOCK_CHAT_TOGGLE,
                             SCILocalized(@"Chat unhidden"),
                             entry[@"threadName"]);
        }];
        return @[unhide];
    }

    UIAction *hide = [UIAction actionWithTitle:SCILocalized(@"Hide chat")
                                          image:[SCIIcon imageNamed:@"ig_icon_direct_off_prism_outline_24" pointSize:20]
                                     identifier:nil
                                        handler:^(__kindof UIAction *_) {
        [SCIHiddenChats addEntry:entry];
        [SCIHiddenChats refreshInboxInPlace];
        SCINotifySuccess(SCI_NOTIF_LOCK_CHAT_TOGGLE,
                         SCILocalized(@"Chat hidden"),
                         entry[@"threadName"]);
    }];
    return @[hide];
}

@end
