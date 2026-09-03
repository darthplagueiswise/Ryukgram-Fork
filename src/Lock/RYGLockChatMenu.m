#import "RYGLockChatMenu.h"
#import "RYGLockManager.h"
#import "RYGLockGroups.h"
#import "RYGLockGate.h"
#import "../Utils.h"
#import "../UI/RYGIcon.h"
#import "../Localization/RYGLocalization.h"
#import "../UI/Notification/RYGNotificationCenter.h"
#import "../UI/Notification/RYGNotificationActions.h"

@implementation RYGLockChatMenu

+ (NSArray<UIAction *> *)actionsForEntry:(NSDictionary *)entry {
    NSString *tid = entry[@"threadId"];
    if (![tid isKindOfClass:[NSString class]] || !tid.length) return @[];
    if (![RYGUtils getBoolPref:@"lock_master_enabled"]) return @[];

    RYGLockManager *mgr = [RYGLockManager shared];
    BOOL locked = [[mgr lockedChatIDs] containsObject:tid];

    NSString *title = locked ? RYGLocalized(@"Unlock chat") : RYGLocalized(@"Lock chat");
    UIImage *img = [RYGIcon imageNamed:(locked ? @"ig_icon_unlock_prism_outline_24" : @"ig_icon_lock_outline_24") pointSize:20];

    UIAction *toggle = [UIAction actionWithTitle:title image:img identifier:nil
                                          handler:^(__kindof UIAction *_) {
        NSString *authTitle = locked ? RYGLocalized(@"Unlock this chat") : RYGLocalized(@"Lock this chat");
        [RYGLockGate forceAuthWithTitle:authTitle subtitle:nil from:nil then:^{
            if (locked) {
                [mgr setChat:tid locked:NO];
            } else {
                [mgr lockChatEntry:entry];
                // Auto-enable the Chats target the first time a chat is locked.
                if (![RYGUtils getBoolPref:RYGLockPrefEnabled(RYGLockGroupChats)]) {
                    [[NSUserDefaults standardUserDefaults] setBool:YES forKey:RYGLockPrefEnabled(RYGLockGroupChats)];
                }
            }
            RYGNotifySuccess(RYG_NOTIF_LOCK_CHAT_TOGGLE,
                             locked ? RYGLocalized(@"Chat unlocked") : RYGLocalized(@"Chat locked"),
                             entry[@"threadName"]);
        }];
    }];
    return @[toggle];
}

@end
