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

    // Once hidden the row vanishes so the user can't reach the context menu;
    // surface only the "Hide chat" action here. Unhide is done from the
    // Security & Privacy → Hidden chats list.
    UIAction *hide = [UIAction actionWithTitle:SCILocalized(@"Hide chat")
                                          image:[SCIIcon imageNamed:@"ig_icon_direct_off_prism_outline_24" pointSize:20]
                                     identifier:nil
                                        handler:^(__kindof UIAction *_) {
        [SCIHiddenChats addEntry:entry];
        SCINotifySuccess(SCI_NOTIF_LOCK_CHAT_TOGGLE,
                         SCILocalized(@"Chat hidden"),
                         entry[@"threadName"]);
    }];
    return @[hide];
}

@end
