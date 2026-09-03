#import "RYGHiddenChats.h"
#import "../../RYGAccountScopedDefaults.h"
#import "../../Utils.h"
#import "../../Lock/RYGLockGate.h"
#import "../../Lock/RYGLockGroups.h"
#import "../../Lock/RYGLockManager.h"
#import "../../UI/Notification/RYGNotificationCenter.h"
#import "../../UI/Notification/RYGNotificationActions.h"
#import "../../Localization/RYGLocalization.h"
#import <UIKit/UIKit.h>
#import <objc/message.h>

NSString *const RYGHiddenChatsRevealDidChangeNotification = @"RYGHiddenChatsRevealDidChange";

static NSString *const kHiddenChatsKey = @"hidden_chats";
static BOOL rygHiddenChatsRevealed = NO;

@implementation RYGHiddenChats

+ (NSArray<NSDictionary *> *)allEntries {
    NSArray *raw = [RYGAccountScopedDefaults arrayForKey:kHiddenChatsKey];
    if (![raw isKindOfClass:[NSArray class]]) return @[];
    NSMutableArray *out = [NSMutableArray arrayWithCapacity:raw.count];
    for (id e in raw) {
        if (![e isKindOfClass:[NSDictionary class]]) continue;
        NSString *tid = e[@"threadId"];
        if ([tid isKindOfClass:[NSString class]] && tid.length) [out addObject:e];
    }
    return out;
}

+ (NSArray<NSString *> *)allThreadIDs {
    NSMutableArray *ids = [NSMutableArray new];
    for (NSDictionary *e in [self allEntries]) [ids addObject:e[@"threadId"]];
    return ids;
}

+ (BOOL)isHidden:(NSString *)threadId {
    if (!threadId.length) return NO;
    for (NSDictionary *e in [self allEntries]) {
        if ([e[@"threadId"] isEqualToString:threadId]) return YES;
    }
    return NO;
}

+ (NSInteger)indexOfThreadID:(NSString *)tid in:(NSArray *)arr {
    for (NSInteger i = 0; i < (NSInteger)arr.count; i++) {
        if ([arr[i][@"threadId"] isEqualToString:tid]) return i;
    }
    return NSNotFound;
}

+ (void)addEntry:(NSDictionary *)entry {
    NSString *tid = entry[@"threadId"];
    if (![tid isKindOfClass:[NSString class]] || !tid.length) return;
    NSMutableDictionary *merged = [entry mutableCopy];
    if (!merged[@"hiddenAt"]) merged[@"hiddenAt"] = @([NSDate date].timeIntervalSince1970);
    NSMutableArray *list = [[self allEntries] mutableCopy];
    NSInteger idx = [self indexOfThreadID:tid in:list];
    if (idx == NSNotFound) [list addObject:merged];
    else                   list[idx] = merged;
    [RYGAccountScopedDefaults setObject:list forKey:kHiddenChatsKey];
}

+ (void)removeThreadId:(NSString *)tid {
    if (!tid.length) return;
    NSMutableArray *list = [[self allEntries] mutableCopy];
    NSInteger idx = [self indexOfThreadID:tid in:list];
    if (idx == NSNotFound) return;
    [list removeObjectAtIndex:idx];
    [RYGAccountScopedDefaults setObject:list forKey:kHiddenChatsKey];
    if (list.count == 0 && rygHiddenChatsRevealed) {
        rygHiddenChatsRevealed = NO;
        [[NSNotificationCenter defaultCenter] postNotificationName:RYGHiddenChatsRevealDidChangeNotification object:nil];
    }
}

+ (void)setAllEntries:(NSArray<NSDictionary *> *)entries {
    NSMutableArray *out = [NSMutableArray arrayWithCapacity:entries.count];
    for (id e in entries) if ([e isKindOfClass:[NSDictionary class]] && [e[@"threadId"] length]) [out addObject:e];
    [RYGAccountScopedDefaults setObject:out forKey:kHiddenChatsKey];
}

+ (BOOL)revealed { return rygHiddenChatsRevealed; }
+ (void)setRevealed:(BOOL)revealed { rygHiddenChatsRevealed = revealed; }

+ (void)toggleRevealFrom:(UIViewController *)presenter {
    if ([self allThreadIDs].count == 0) return;
    NSString *grp = RYGLockGroupHiddenReveal;
    BOOL turningOn = !rygHiddenChatsRevealed;

    [RYGLockGate runGated:grp from:presenter then:^{
        rygHiddenChatsRevealed = turningOn;
        [self refreshInboxInPlace];
        if ([RYGUtils getBoolPref:RYGLockPrefRelockOnDismiss(grp)])
            [[RYGLockManager shared] markGroupLocked:grp];
        [[NSNotificationCenter defaultCenter] postNotificationName:RYGHiddenChatsRevealDidChangeNotification object:nil];
        RYGNotifyInfo(RYG_NOTIF_LOCK_CHAT_TOGGLE,
                      turningOn ? RYGLocalized(@"Hidden chats revealed") : RYGLocalized(@"Hidden chats hidden"),
                      nil);
    }];
}

+ (void)handleAppBackground {
    if (!rygHiddenChatsRevealed) return;
    rygHiddenChatsRevealed = NO;
    [self refreshInboxInPlace];
    [[NSNotificationCenter defaultCenter] postNotificationName:RYGHiddenChatsRevealDidChangeNotification object:nil];
}

+ (UIViewController *)findInboxVC:(UIViewController *)vc {
    Class inbox = NSClassFromString(@"IGDirectInboxViewController");
    if (!inbox || !vc) return nil;
    if ([vc isKindOfClass:inbox]) return vc;
    for (UIViewController *child in vc.childViewControllers) {
        UIViewController *found = [self findInboxVC:child];
        if (found) return found;
    }
    return [self findInboxVC:vc.presentedViewController];
}

+ (void)refreshInboxInPlace {
    dispatch_async(dispatch_get_main_queue(), ^{
        UIViewController *inbox = nil;
        for (UIScene *scene in [UIApplication sharedApplication].connectedScenes) {
            if (![scene isKindOfClass:[UIWindowScene class]]) continue;
            for (UIWindow *w in ((UIWindowScene *)scene).windows) {
                inbox = [self findInboxVC:w.rootViewController];
                if (inbox) break;
            }
            if (inbox) break;
        }
        if (!inbox) return;

        id adapter = nil;
        @try { adapter = [inbox valueForKey:@"listAdapter"]; } @catch (__unused id e) {}
        if ([adapter respondsToSelector:@selector(performUpdatesAnimated:completion:)])
            ((void (*)(id, SEL, BOOL, id))objc_msgSend)(adapter, @selector(performUpdatesAnimated:completion:), YES, nil);
    });
}

@end
