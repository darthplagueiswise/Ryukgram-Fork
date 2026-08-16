// Online/offline presence via an IGPresenceManagerListener (snapshot = baseline,
// update = real change) plus realtime pushes; the engine dedups either channel.

#import "RYGActivityEngine.h"
#import "../../Utils.h"
#import <UIKit/UIKit.h>
#import <objc/runtime.h>
#import <objc/message.h>

// Fast presence: re-fetch on our own timer rather than hooking IG's scheduler.
static __weak id sPresenceManager;

static void rygFastPresenceTick(void) {
    if (![RYGUtils getBoolPref:@"activity_fast_presence"]) return;
    if (UIApplication.sharedApplication.applicationState != UIApplicationStateActive) return;
    id mgr = sPresenceManager;
    SEL sel = @selector(updatePresencesWithSuccessCallback:failureCallback:configuration:);
    if (![mgr respondsToSelector:sel]) return;
    void (^ok)(id) = ^(id r) {};
    void (^fail)(id) = ^(id e) {};
    @try { ((void (*)(id, SEL, id, id, id))objc_msgSend)(mgr, sel, ok, fail, nil); } @catch (__unused id e) {}
}

static void rygStartFastPresenceTimer(void) {
    static dispatch_source_t t;
    if (t) return;
    double secs = [RYGUtils getDoublePref:@"activity_fast_presence_secs"];
    if (secs < 5) secs = 20;
    t = dispatch_source_create(DISPATCH_SOURCE_TYPE_TIMER, 0, 0, dispatch_get_main_queue());
    dispatch_source_set_timer(t, dispatch_time(DISPATCH_TIME_NOW, (int64_t)(secs * NSEC_PER_SEC)), (uint64_t)(secs * NSEC_PER_SEC), (uint64_t)(2 * NSEC_PER_SEC));
    dispatch_source_set_event_handler(t, ^{ rygFastPresenceTick(); });
    dispatch_resume(t);
}

static NSString *apPkStr(id pk) {
    if ([pk isKindOfClass:NSString.class]) return pk;
    if ([pk respondsToSelector:@selector(stringValue)]) return [pk stringValue];
    return pk ? [pk description] : nil;
}
static id apCall(id o, SEL s) { return (o && [o respondsToSelector:s]) ? ((id (*)(id, SEL))objc_msgSend)(o, s) : nil; }

static BOOL apStateActive(id state) {
    if (!state) return NO;
    if ([state respondsToSelector:@selector(isActive)]) return ((BOOL (*)(id, SEL))objc_msgSend)(state, @selector(isActive));
    Ivar iv = class_getInstanceVariable([state class], "_isActive");
    if (iv) return *(signed char *)((char *)(__bridge void *)state + ivar_getOffset(iv)) != 0;
    return NO;
}

// IGPresenceState exposes last-activity in one of several forms; normalize to ms.
static double apStateLastMs(id state) {
    if (!state) return 0;
    for (NSString *sn in @[@"lastActivityAtMs", @"lastActivityTimestampMs"]) {
        SEL s = NSSelectorFromString(sn);
        if ([state respondsToSelector:s]) { double v = ((double (*)(id, SEL))objc_msgSend)(state, s); if (v > 1e11) return v; }
    }
    for (NSString *sn in @[@"lastActivityTs", @"lastActivityTimestamp", @"lastActivityAt"]) {
        SEL s = NSSelectorFromString(sn);
        if ([state respondsToSelector:s]) { double v = ((double (*)(id, SEL))objc_msgSend)(state, s); if (v > 1e9 && v < 1e11) return v * 1000.0; }
    }
    SEL ds = NSSelectorFromString(@"lastActivityDate");
    if ([state respondsToSelector:ds]) { id d = ((id (*)(id, SEL))objc_msgSend)(state, ds); if ([d isKindOfClass:NSDate.class]) return [d timeIntervalSince1970] * 1000.0; }
    return 0;
}

@interface RYGPresenceListener : NSObject
@end
@implementation RYGPresenceListener

+ (instancetype)shared {
    static RYGPresenceListener *s; static dispatch_once_t o;
    dispatch_once(&o, ^{
        Protocol *p = objc_getProtocol("IGPresenceManagerListener");
        if (p) class_addProtocol([RYGPresenceListener class], p);
        s = [self new];
    });
    return s;
}

- (void)apApplyFromManager:(id)mgr snapshot:(BOOL)snapshot {
    id map = apCall(mgr, @selector(presenceStatesByUserPk));
    if (![map isKindOfClass:NSDictionary.class]) return;
    [(NSDictionary *)map enumerateKeysAndObjectsUsingBlock:^(id pk, id state, BOOL *stop) {
        [RYGActivityEngine handlePresenceActive:apStateActive(state) forPK:apPkStr(pk) lastActivityAtMs:apStateLastMs(state) snapshot:snapshot];
    }];
    // Snapshots record baseline silently; nudge the honest-header to re-evaluate.
    dispatch_async(dispatch_get_main_queue(), ^{
        [NSNotificationCenter.defaultCenter postNotificationName:RYGActivityPresenceDidChangeNotification object:nil userInfo:nil];
    });
}

- (void)presenceManager:(id)mgr didReceiveSnapshot:(id)snapshot { @try { [self apApplyFromManager:mgr snapshot:YES]; } @catch (__unused id e) {} }
- (void)presenceManager:(id)mgr didReceiveUpdate:(id)update   { @try { [self apApplyFromManager:mgr snapshot:NO]; } @catch (__unused id e) {} }
- (void)didUpdatePresence:(id)x {}

@end

// Collapse IG's "active now" grace so the native green dot reflects real presence.
%group ActivityPresence

%hook IGDirectGatingService
- (long long)activeNowGracePeriod {
    if ([RYGUtils getBoolPref:@"activity_fast_presence"]) return 0;
    return %orig;
}
- (NSNumber *)activeNowGracePeriodCacheValue {
    if ([RYGUtils getBoolPref:@"activity_fast_presence"]) return @0;
    return %orig;
}
%end

%hook IGPresenceManager

- (id)initWithScopedObjects:(id)a presenceStore:(id)b backgroundFetchDataProvider:(id)c realtimeDataProvider:(id)d analyticsLogger:(id)e {
    id r = %orig;
    @try {
        if (r && [r respondsToSelector:@selector(addListener:)])
            ((void (*)(id, SEL, id))objc_msgSend)(r, @selector(addListener:), [RYGPresenceListener shared]);
        sPresenceManager = r;
        if ([RYGUtils getBoolPref:@"activity_fast_presence"]) rygStartFastPresenceTimer();
    } @catch (__unused id e) {}
    return r;
}

// Realtime pushes — faster than the periodic snapshot refresh.
- (void)presenceRealtimeDataProvider:(id)provider didReceiveUpdateForUserPk:(id)pk isActive:(BOOL)active lastActivityAtMs:(double)ms capabilities:(unsigned long long)caps correlationId:(id)cid isCloseFriend:(BOOL)closeFriend {
    %orig;
    [RYGActivityEngine handlePresenceActive:active forPK:apPkStr(pk) lastActivityAtMs:ms snapshot:NO];
}

- (void)handleUPCRealtimePresenceUpdateForUserPk:(id)pk isActive:(BOOL)active lastActivityAtMs:(double)ms capabilities:(unsigned long long)caps correlationId:(id)cid {
    %orig;
    [RYGActivityEngine handlePresenceActive:active forPK:apPkStr(pk) lastActivityAtMs:ms snapshot:NO];
}

%end

%end

%ctor {
    if ([RYGUtils getBoolPref:@"activity_notif_enabled"] ||
        [RYGUtils getBoolPref:@"activity_fast_presence"])
        %init(ActivityPresence);
}
