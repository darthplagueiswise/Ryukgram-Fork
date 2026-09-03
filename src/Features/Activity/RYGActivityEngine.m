#import "RYGActivityEngine.h"
#import "RYGActivityConfig.h"
#import "RYGActivityLogStore.h"
#import "../Feed/RYGHomeShortcutBadges.h"
#import "../../Utils.h"
#import "../StoriesAndMessages/RYGDirectUserResolver.h"
#import "../StoriesAndMessages/RYGExcludedThreads.h"
#import "../../UI/Notification/RYGNotificationActions.h"
#import "RYGActivityMatrixViewController.h"
#import "../../UI/RYGPopupChrome.h"
#import <UIKit/UIKit.h>

NSNotificationName const RYGActivityPresenceDidChangeNotification = @"RYGActivityPresenceDidChangeNotification";

static NSTimeInterval const kPresenceCooldown = 45.0;
static NSTimeInterval const kTypingCooldown   = 25.0;

@implementation RYGActivityEngine

// pk -> @{ @"active": bool, @"tsOn"/"tsOff": last-notify time per direction }
static NSMutableDictionary *sPresence;
// "tid|pk" -> last-notify time
static NSMutableDictionary *sTyping;
static dispatch_queue_t sQ;

+ (void)initialize {
    if (self != RYGActivityEngine.class) return;
    sPresence = [NSMutableDictionary dictionary];
    sTyping   = [NSMutableDictionary dictionary];
    sQ = dispatch_queue_create("com.ryukgram.activity.engine", DISPATCH_QUEUE_SERIAL);
}

static NSString *handleForPK(NSString *pk) {
    NSString *u = rygDirectUserResolverUsernameForPK(pk);
    return u.length ? [@"@" stringByAppendingString:u] : RYGLocalized(@"Someone");
}

static void rygOpenActivityLog(void) {
    [RYGPopupChrome presentVC:[RYGActivityMatrixViewController new] from:nil];
}

static void notifyOnMain(NSString *actionID, NSString *pk, NSString *title, NSString *sub, NSString *icon) {
    dispatch_async(dispatch_get_main_queue(), ^{
        RYGNotifyTap(actionID, title, sub, icon, RYGNotificationToneInfo, ^{ rygOpenActivityLog(); });
    });
}

static void logEvent(RYGActivityType type, NSString *pk) {
    if (![RYGActivityConfig shouldLogType:type forPK:pk]) return;
    [RYGActivityLogStore appendType:type pk:pk
                           username:rygDirectUserResolverUsernameForPK(pk)
                             picURL:rygDirectUserResolverPicForPK(pk)
                            ownerPK:[RYGUtils currentUserPK]];
    dispatch_async(dispatch_get_main_queue(), ^{ [RYGHomeShortcutBadges bumpActionID:@"read_receipts"]; });
}

+ (void)handlePresenceActive:(BOOL)active forPK:(NSString *)pk lastActivityAtMs:(double)ms snapshot:(BOOL)snapshot {
    if (!pk.length) return;
    NSString *me = [RYGUtils currentUserPK];
    if (me.length && [pk isEqualToString:me]) return;

    dispatch_async(sQ, ^{
        double now = CFAbsoluteTimeGetCurrent();
        NSDictionary *st = sPresence[pk];
        NSNumber *prev = st[@"active"];
        BOOL known = (prev != nil);
        BOOL wasActive = prev.boolValue;
        // Separate on/off cooldowns: an offline notify must never suppress the
        // online that follows (they're opposite events, both wanted).
        NSString *tsKey = active ? @"tsOn" : @"tsOff";
        double lastTs = [st[tsKey] doubleValue];
        NSMutableDictionary *nst = st ? [st mutableCopy] : [NSMutableDictionary dictionary];
        nst[@"active"] = @(active);
        if (ms > 0) nst[@"ms"] = @(ms);
        sPresence[pk] = nst;

        if (known && wasActive == active) return;              // no change, either channel
        if (known) {                                           // real flip — let the header refresh live
            NSDictionary *ui = @{ @"pk": pk, @"active": @(active) };
            dispatch_async(dispatch_get_main_queue(), ^{
                [NSNotificationCenter.defaultCenter postNotificationName:RYGActivityPresenceDidChangeNotification object:nil userInfo:ui];
            });
        }
        if (!known) {
            // First time we see this pk. A snapshot is just initial state (baseline).
            // A realtime push is a genuine change: announce it if it's a come-online.
            if (snapshot) return;
            if (!active) return;                               // first thing we hear is "offline" — nothing to announce
        }
        logEvent(active ? RYGActivityTypeOnline : RYGActivityTypeOffline, pk);
        if (![RYGActivityConfig shouldNotifyType:(active ? RYGActivityTypeOnline : RYGActivityTypeOffline) forPK:pk]) return;
        if (now - lastTs < kPresenceCooldown) return;
        nst[tsKey] = @(now);
        sPresence[pk] = nst;

        NSString *handle = handleForPK(pk);
        notifyOnMain(active ? RYG_NOTIF_ACTIVITY_ONLINE : RYG_NOTIF_ACTIVITY_OFFLINE, pk, handle,
                     active ? RYGLocalized(@"is now active") : RYGLocalized(@"went offline"),
                     active ? @"circle.fill" : @"moon.zzz.fill");
    });
}

+ (int)presenceForPK:(NSString *)pk {
    if (!pk.length) return -1;
    __block int r = -1;
    dispatch_sync(sQ, ^{ NSNumber *a = sPresence[pk][@"active"]; if (a) r = a.boolValue ? 1 : 0; });
    return r;
}

+ (int)presenceForLastActiveMs:(double)ms {
    if (ms <= 0) return -1;
    __block int r = -1; __block double best = 4000.0;
    dispatch_sync(sQ, ^{
        for (NSString *pk in sPresence) {
            double m = [sPresence[pk][@"ms"] doubleValue];
            if (m <= 0) continue;
            double d = fabs(m - ms);
            if (d <= best) { best = d; r = [sPresence[pk][@"active"] boolValue] ? 1 : 0; }
        }
    });
    return r;
}

+ (void)handleTypingActive:(BOOL)active forPK:(NSString *)pk threadId:(NSString *)threadId {
    if (!active || !pk.length) return;
    NSString *me = [RYGUtils currentUserPK];
    if (me.length && [pk isEqualToString:me]) return;

    dispatch_async(sQ, ^{
        double now = CFAbsoluteTimeGetCurrent();
        NSString *k = [NSString stringWithFormat:@"%@|%@", threadId ?: @"", pk];
        if (now - [sTyping[k] doubleValue] < kTypingCooldown) return;
        sTyping[k] = @(now);

        logEvent(RYGActivityTypeTyping, pk);
        if (![RYGActivityConfig shouldNotifyType:RYGActivityTypeTyping forPK:pk]) return;

        dispatch_async(dispatch_get_main_queue(), ^{
            // You're looking at that chat — the native dots already show it.
            if (UIApplication.sharedApplication.applicationState == UIApplicationStateActive
                && threadId.length && [[RYGExcludedThreads activeThreadId] isEqualToString:threadId])
                return;
            NSString *handle = handleForPK(pk);
            RYGNotifyTap(RYG_NOTIF_ACTIVITY_TYPING, handle, RYGLocalized(@"is typing…"),
                         @"ellipsis.bubble.fill", RYGNotificationToneInfo, ^{ rygOpenActivityLog(); });
        });
    });
}

@end
