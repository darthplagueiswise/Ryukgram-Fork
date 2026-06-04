#import "SCILockedChatsViewController.h"
#import "../SCILockManager.h"
#import "../../Networking/SCIInstagramAPI.h"
#import "../../Utils.h"
#import "../../SCIURLOpener.h"
#import "../../Localization/SCILocalization.h"

@implementation SCILockedChatsViewController

- (instancetype)init {
    SCIIDListConfig *cfg = [SCIIDListConfig new];
    cfg.title = SCILocalized(@"Locked chats");
    cfg.searchPlaceholder = SCILocalized(@"Search by name or username");
    cfg.addAlertTitle = SCILocalized(@"Add locked chat");
    cfg.addAlertMessage = SCILocalized(@"Username (looks up the DM thread) or raw thread ID");
    cfg.addAlertPlaceholder = SCILocalized(@"Username or thread ID");
    cfg.sortTitles = @[SCILocalized(@"Recently locked"), SCILocalized(@"Name (A–Z)")];

    cfg.itemsProvider = ^NSArray *{ return [[SCILockManager shared] lockedChatEntries]; };

    cfg.titleProvider = ^NSString *(NSDictionary *e) {
        NSString *name = e[@"threadName"];
        if ([name isKindOfClass:[NSString class]] && name.length) {
            BOOL isGroup = [e[@"isGroup"] boolValue];
            return [NSString stringWithFormat:@"%@%@", isGroup ? @"👥 " : @"", name];
        }
        return [NSString stringWithFormat:SCILocalized(@"Thread %@"), e[@"threadId"] ?: @"?"];
    };

    cfg.subtitleProvider = ^NSString *(NSDictionary *e) {
        NSArray *users = e[@"users"];
        if (![users isKindOfClass:[NSArray class]] || !users.count) return e[@"threadId"] ?: @"";
        NSMutableArray *unames = [NSMutableArray new];
        for (NSDictionary *u in users) {
            if (u[@"username"]) [unames addObject:[@"@" stringByAppendingString:u[@"username"]]];
        }
        return [unames componentsJoinedByString:@", "];
    };

    cfg.matchesQuery = ^BOOL(NSDictionary *e, NSString *q) {
        if ([[e[@"threadName"] lowercaseString] containsString:q]) return YES;
        if ([[e[@"threadId"] lowercaseString] containsString:q]) return YES;
        for (NSDictionary *u in (NSArray *)e[@"users"]) {
            if ([[u[@"username"] lowercaseString] containsString:q]) return YES;
            if ([[u[@"fullName"] lowercaseString] containsString:q]) return YES;
        }
        return NO;
    };

    cfg.sortedItems = ^NSArray *(NSArray *items, NSInteger mode) {
        return [items sortedArrayUsingComparator:^NSComparisonResult(NSDictionary *a, NSDictionary *b) {
            if (mode == 0) return [b[@"lockedAt"] ?: @0 compare:a[@"lockedAt"] ?: @0];
            return [a[@"threadName"] ?: @"" caseInsensitiveCompare:b[@"threadName"] ?: @""];
        }];
    };

    cfg.onTapItem = ^(NSDictionary *e, UIViewController *vc) {
        NSArray *users = e[@"users"];
        if ([e[@"isGroup"] boolValue] || users.count != 1) return;
        NSString *username = users.firstObject[@"username"];
        if (!username.length) return;
        [vc.navigationController dismissViewControllerAnimated:YES completion:^{
            [SCIURLOpener openInstagramProfileForUsername:username];
        }];
    };

    cfg.onRemoveItem = ^(NSDictionary *e) {
        [[SCILockManager shared] setChat:e[@"threadId"] locked:NO];
    };

    cfg.onAddRequest = ^(NSString *input, UIViewController *vc, void(^reload)(void)) {
        NSString *q = [input stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceCharacterSet]];
        if ([q hasPrefix:@"@"]) q = [q substringFromIndex:1];
        NSCharacterSet *nonDigits = [[NSCharacterSet decimalDigitCharacterSet] invertedSet];
        BOOL numeric = q.length > 0 && [q rangeOfCharacterFromSet:nonDigits].location == NSNotFound;
        if (numeric) {
            [[SCILockManager shared] lockChatEntry:@{ @"threadId": q }];
            reload();
            return;
        }
        NSString *username = q;
        [SCIInstagramAPI sendRequestWithMethod:@"GET"
            path:[NSString stringWithFormat:@"users/web_profile_info/?username=%@", username]
            body:nil completion:^(NSDictionary *resp, NSError *err) {
            NSDictionary *user = resp[@"data"][@"user"];
            if (!user || err) {
                [SCIUtils showErrorHUDWithDescription:[NSString stringWithFormat:SCILocalized(@"User '%@' not found"), username]];
                return;
            }
            NSString *pk = [user[@"id"] description] ?: @"";
            NSString *uname = user[@"username"] ?: username;
            NSString *fullName = user[@"full_name"] ?: @"";
            if (!pk.length) { [SCIUtils showErrorHUDWithDescription:SCILocalized(@"Could not resolve user ID")]; return; }
            [SCIInstagramAPI sendRequestWithMethod:@"GET"
                path:[NSString stringWithFormat:@"direct_v2/threads/get_by_participants/?recipient_users=[%@]", pk]
                body:nil completion:^(NSDictionary *threadResp, NSError *tErr) {
                NSString *threadId = threadResp[@"thread"][@"thread_id"];
                NSString *threadName = threadResp[@"thread"][@"thread_title"] ?: uname;
                if (!threadId.length || tErr) {
                    [SCIUtils showErrorHUDWithDescription:[NSString stringWithFormat:SCILocalized(@"No DM thread found with @%@"), uname]];
                    return;
                }
                NSString *msg = [NSString stringWithFormat:@"@%@%@", uname, fullName.length ? [NSString stringWithFormat:@" (%@)", fullName] : @""];
                UIAlertController *confirm = [UIAlertController alertControllerWithTitle:SCILocalized(@"Lock this chat?")
                                                                                 message:msg
                                                                          preferredStyle:UIAlertControllerStyleAlert];
                [confirm addAction:[UIAlertAction actionWithTitle:SCILocalized(@"Cancel") style:UIAlertActionStyleCancel handler:nil]];
                [confirm addAction:[UIAlertAction actionWithTitle:SCILocalized(@"Lock") style:UIAlertActionStyleDestructive handler:^(__unused UIAlertAction *_) {
                    [[SCILockManager shared] lockChatEntry:@{
                        @"threadId": threadId,
                        @"threadName": threadName,
                        @"isGroup": @NO,
                        @"users": @[@{ @"pk": pk, @"username": uname, @"fullName": fullName }],
                    }];
                    reload();
                }]];
                [vc presentViewController:confirm animated:YES completion:nil];
            }];
        }];
    };

    return [super initWithConfig:cfg];
}

@end
