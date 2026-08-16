#import "RYGHiddenChatsMenu.h"
#import "RYGHiddenChats.h"
#import "../../UI/RYGIcon.h"
#import "../../UI/Notification/RYGNotificationCenter.h"
#import "../../UI/Notification/RYGNotificationActions.h"
#import "../../Localization/RYGLocalization.h"

@implementation RYGHiddenChatsMenu

+ (NSArray<UIAction *> *)actionsForEntry:(NSDictionary *)entry {
    NSString *tid = entry[@"threadId"];
    if (![tid isKindOfClass:[NSString class]] || !tid.length) return @[];

    // A hidden row is only reachable while the list is revealed — offer Unhide there.
    if ([RYGHiddenChats isHidden:tid]) {
        UIAction *unhide = [UIAction actionWithTitle:RYGLocalized(@"Unhide chat")
                                               image:[RYGIcon imageNamed:@"ig_icon_direct_prism_outline_24" pointSize:20]
                                          identifier:nil
                                             handler:^(__kindof UIAction *_) {
            [RYGHiddenChats removeThreadId:tid];
            [RYGHiddenChats refreshInboxInPlace];
            RYGNotifySuccess(RYG_NOTIF_LOCK_CHAT_TOGGLE,
                             RYGLocalized(@"Chat unhidden"),
                             entry[@"threadName"]);
        }];
        return @[unhide];
    }

    UIAction *hide = [UIAction actionWithTitle:RYGLocalized(@"Hide chat")
                                          image:[RYGIcon imageNamed:@"ig_icon_direct_off_prism_outline_24" pointSize:20]
                                     identifier:nil
                                        handler:^(__kindof UIAction *_) {
        [RYGHiddenChats addEntry:entry];
        [RYGHiddenChats refreshInboxInPlace];
        RYGNotifySuccess(RYG_NOTIF_LOCK_CHAT_TOGGLE,
                         RYGLocalized(@"Chat hidden"),
                         entry[@"threadName"]);
    }];
    return @[hide];
}

@end
