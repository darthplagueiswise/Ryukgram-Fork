#import "SCILockChatMenu.h"
#import "SCILockManager.h"
#import "SCILockGroups.h"
#import "SCILockGate.h"
#import "../Utils.h"
#import "../UI/SCIIcon.h"
#import "../Localization/SCILocalization.h"
#import "../UI/Notification/SCINotificationCenter.h"
#import "../UI/Notification/SCINotificationActions.h"

@implementation SCILockChatMenu

+ (NSArray<UIAction *> *)actionsForEntry:(NSDictionary *)entry {
    NSString *tid = entry[@"threadId"];
    if (![tid isKindOfClass:[NSString class]] || !tid.length) return @[];
    if (![SCIUtils getBoolPref:@"lock_master_enabled"]) return @[];

    SCILockManager *mgr = [SCILockManager shared];
    BOOL locked = [[mgr lockedChatIDs] containsObject:tid];

    NSString *title = locked ? SCILocalized(@"Unlock chat") : SCILocalized(@"Lock chat");
    UIImage *img = [SCIIcon imageNamed:(locked ? @"ig_icon_unlock_prism_outline_24" : @"ig_icon_lock_outline_24") pointSize:20];

    UIAction *toggle = [UIAction actionWithTitle:title image:img identifier:nil
                                          handler:^(__kindof UIAction *_) {
        NSString *authTitle = locked ? SCILocalized(@"Unlock this chat") : SCILocalized(@"Lock this chat");
        [SCILockGate forceAuthWithTitle:authTitle subtitle:nil from:nil then:^{
            if (locked) {
                [mgr setChat:tid locked:NO];
            } else {
                [mgr lockChatEntry:entry];
                // Auto-enable the Chats target the first time a chat is locked.
                if (![SCIUtils getBoolPref:SCILockPrefEnabled(SCILockGroupChats)]) {
                    [[NSUserDefaults standardUserDefaults] setBool:YES forKey:SCILockPrefEnabled(SCILockGroupChats)];
                }
            }
            SCINotifySuccess(SCI_NOTIF_LOCK_CHAT_TOGGLE,
                             locked ? SCILocalized(@"Chat unlocked") : SCILocalized(@"Chat locked"),
                             entry[@"threadName"]);
        }];
    }];
    return @[toggle];
}

@end
