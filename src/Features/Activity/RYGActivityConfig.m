#import "RYGActivityConfig.h"
#import "../../Utils.h"
#import "../../UI/RYGIcon.h"

NSNotificationName const RYGActivityConfigDidChangeNotification = @"RYGActivityConfigDidChangeNotification";

static NSString *const kDir = @"RyukGram/Activity";

@implementation RYGActivityConfig

+ (NSArray<NSNumber *> *)allTypes {
    return @[ @(RYGActivityTypeRead), @(RYGActivityTypeOnline), @(RYGActivityTypeOffline), @(RYGActivityTypeTyping) ];
}

+ (NSArray<NSNumber *> *)allModes {
    return @[ @(RYGActivityModeOff), @(RYGActivityModeLog), @(RYGActivityModeNotify), @(RYGActivityModeNotifyLog) ];
}

+ (NSString *)titleForType:(RYGActivityType)type {
    switch (type) {
        case RYGActivityTypeRead:    return RYGLocalized(@"Read your message");
        case RYGActivityTypeOnline:  return RYGLocalized(@"Came online");
        case RYGActivityTypeOffline: return RYGLocalized(@"Went offline");
        case RYGActivityTypeTyping:  return RYGLocalized(@"Started typing");
    }
    return @"";
}

+ (NSString *)iconForType:(RYGActivityType)type {
    switch (type) {
        case RYGActivityTypeRead:    return @"eye.fill";
        case RYGActivityTypeOnline:  return @"circle.fill";
        case RYGActivityTypeOffline: return @"moon.zzz.fill";
        case RYGActivityTypeTyping:  return @"ellipsis.bubble.fill";
    }
    return @"bell";
}

// One canonical image per type, shared by every activity-log surface.
+ (UIImage *)imageForType:(RYGActivityType)type {
    UIImage *img = nil;
    switch (type) {
        case RYGActivityTypeRead:    img = [RYGIcon fbImageNamed:@"ig_icon_eye_filled_24"]; break;
        case RYGActivityTypeTyping:  img = [RYGIcon fbImageNamed:@"ig_icon_app_whatsapp_chat_prism_outline_24"]; break;
        default: break;
    }
    return img ?: [RYGIcon sfImageNamed:[self iconForType:type]];
}

+ (UIColor *)tintForType:(RYGActivityType)type {
    switch (type) {
        case RYGActivityTypeRead:    return UIColor.systemIndigoColor;
        case RYGActivityTypeOnline:  return UIColor.systemGreenColor;
        case RYGActivityTypeOffline: return UIColor.systemGray2Color;
        case RYGActivityTypeTyping:  return UIColor.systemBlueColor;
    }
    return UIColor.labelColor;
}

+ (NSString *)titleForMode:(RYGActivityMode)mode {
    switch (mode) {
        case RYGActivityModeOff:       return RYGLocalized(@"Off");
        case RYGActivityModeLog:       return RYGLocalized(@"Log only");
        case RYGActivityModeNotify:    return RYGLocalized(@"Notify only");
        case RYGActivityModeNotifyLog: return RYGLocalized(@"Notify + log");
    }
    return @"";
}

+ (NSString *)modeKeyForType:(RYGActivityType)type {
    switch (type) {
        case RYGActivityTypeRead:    return @"activity_read_mode";
        case RYGActivityTypeOnline:  return @"activity_online_mode";
        case RYGActivityTypeOffline: return @"activity_offline_mode";
        case RYGActivityTypeTyping:  return @"activity_typing_mode";
    }
    return nil;
}

+ (RYGActivityMode)globalModeForType:(RYGActivityType)type {
    NSString *v = [RYGUtils getStringPref:[self modeKeyForType:type]];
    if ([v isEqualToString:@"notify_log"]) return RYGActivityModeNotifyLog;
    if ([v isEqualToString:@"notify"])     return RYGActivityModeNotify;
    if ([v isEqualToString:@"log"])        return RYGActivityModeLog;
    return RYGActivityModeOff;
}

+ (void)setGlobalMode:(RYGActivityMode)mode forType:(RYGActivityType)type {
    NSString *v = @"off";
    if (mode == RYGActivityModeNotifyLog) v = @"notify_log";
    else if (mode == RYGActivityModeNotify) v = @"notify";
    else if (mode == RYGActivityModeLog) v = @"log";
    [RYGUtils setPref:v forKey:[self modeKeyForType:type]];
    [self post];
}

+ (RYGActivityType)globalNotifyMask {
    RYGActivityType m = 0;
    for (NSNumber *n in [self allTypes]) {
        RYGActivityType t = (RYGActivityType)n.unsignedIntegerValue;
        if ([self globalModeForType:t] & RYGActivityModeNotify) m |= t;
    }
    return m;
}

+ (RYGActivityType)globalLogMask {
    RYGActivityType m = 0;
    for (NSNumber *n in [self allTypes]) {
        RYGActivityType t = (RYGActivityType)n.unsignedIntegerValue;
        if ([self globalModeForType:t] & RYGActivityModeLog) m |= t;
    }
    return m;
}

+ (BOOL)readReceiptsActive {
    return [RYGUtils getBoolPref:@"activity_notif_enabled"]
        && [self globalModeForType:RYGActivityTypeRead] != RYGActivityModeOff;
}

#pragma mark - Per-person store (account-scoped)

static void *kQKey = &kQKey;
static dispatch_queue_t ioQ(void) {
    static dispatch_queue_t q; static dispatch_once_t once;
    dispatch_once(&once, ^{ q = dispatch_queue_create("com.ryukgram.activity.config", DISPATCH_QUEUE_SERIAL); });
    return q;
}
static NSString *storeFile(void) {
    NSString *root = NSSearchPathForDirectoriesInDomains(NSApplicationSupportDirectory, NSUserDomainMask, YES).firstObject;
    NSString *dir = [root stringByAppendingPathComponent:kDir];
    [NSFileManager.defaultManager createDirectoryAtPath:dir withIntermediateDirectories:YES attributes:nil error:nil];
    NSString *owner = [RYGUtils currentUserPK] ?: @"anon";
    return [dir stringByAppendingPathComponent:[NSString stringWithFormat:@"overrides_%@.json", owner]];
}
static NSMutableDictionary *sCache;
static NSString *sCacheOwner;
static NSMutableDictionary *overrides(void) {
    NSString *owner = [RYGUtils currentUserPK] ?: @"anon";
    if (sCache && [sCacheOwner isEqualToString:owner]) return sCache;
    NSData *d = [NSData dataWithContentsOfFile:storeFile()];
    id j = d ? [NSJSONSerialization JSONObjectWithData:d options:0 error:nil] : nil;
    sCache = [j isKindOfClass:NSDictionary.class] ? [j mutableCopy] : [NSMutableDictionary dictionary];
    sCacheOwner = owner;
    return sCache;
}
static void save(void) {
    NSDictionary *snap = [overrides() copy];
    NSString *path = storeFile();
    [[NSJSONSerialization dataWithJSONObject:snap options:0 error:nil] writeToFile:path atomically:YES];
}

+ (void)post {
    dispatch_async(dispatch_get_main_queue(), ^{
        [NSNotificationCenter.defaultCenter postNotificationName:RYGActivityConfigDidChangeNotification object:nil];
    });
}

// Override value is a dict { notify, log?, username, pic }. Legacy shapes:
// a bare NSNumber, or { mask, username, pic } — both mean notify-only, log unset.
static RYGActivityType notifyMaskOf(id v) {
    if ([v isKindOfClass:NSDictionary.class]) return (RYGActivityType)[(v[@"notify"] ?: v[@"mask"]) unsignedIntegerValue];
    return (RYGActivityType)[v unsignedIntegerValue];
}
static BOOL hasLogKey(id v) { return [v isKindOfClass:NSDictionary.class] && v[@"log"] != nil; }
static RYGActivityType logMaskOf(id v) { return (RYGActivityType)[([v isKindOfClass:NSDictionary.class] ? v[@"log"] : nil) unsignedIntegerValue]; }
static NSString *metaOf(id v, NSString *key) {
    id s = [v isKindOfClass:NSDictionary.class] ? v[key] : nil;
    return [s isKindOfClass:NSString.class] ? s : nil;
}
static NSMutableDictionary *recFrom(id cur) {
    NSMutableDictionary *rec = [NSMutableDictionary dictionary];
    rec[@"username"] = metaOf(cur, @"username");
    rec[@"pic"] = metaOf(cur, @"pic");
    rec[@"notify"] = @(notifyMaskOf(cur));
    if (hasLogKey(cur)) rec[@"log"] = @(logMaskOf(cur));
    return rec;
}

+ (BOOL)hasOverrideForPK:(NSString *)pk {
    if (!pk.length) return NO;
    __block BOOL r = NO;
    dispatch_sync(ioQ(), ^{ r = overrides()[pk] != nil; });
    return r;
}

+ (RYGActivityType)overrideMaskForPK:(NSString *)pk {
    if (!pk.length) return 0;
    __block RYGActivityType m = 0;
    dispatch_sync(ioQ(), ^{ m = notifyMaskOf(overrides()[pk]); });
    return m;
}

+ (RYGActivityType)overrideLogMaskForPK:(NSString *)pk {
    if (!pk.length) return 0;
    __block RYGActivityType m = 0;
    dispatch_sync(ioQ(), ^{ id v = overrides()[pk]; m = hasLogKey(v) ? logMaskOf(v) : notifyMaskOf(v); });
    return m;
}

+ (BOOL)hasLogOverrideForPK:(NSString *)pk {
    if (!pk.length) return NO;
    __block BOOL r = NO;
    dispatch_sync(ioQ(), ^{ r = hasLogKey(overrides()[pk]); });
    return r;
}

+ (void)setNotifyMask:(RYGActivityType)mask forPK:(NSString *)pk {
    if (!pk.length) return;
    dispatch_sync(ioQ(), ^{
        NSMutableDictionary *rec = recFrom(overrides()[pk]);
        rec[@"notify"] = @(mask);
        overrides()[pk] = rec;
        save();
    });
    [self post];
}

+ (void)setLogMask:(RYGActivityType)mask forPK:(NSString *)pk {
    if (!pk.length) return;
    dispatch_sync(ioQ(), ^{
        NSMutableDictionary *rec = recFrom(overrides()[pk]);
        rec[@"log"] = @(mask);
        overrides()[pk] = rec;
        save();
    });
    [self post];
}

+ (void)setOverrideNotifyMask:(RYGActivityType)notifyMask logMask:(RYGActivityType)logMask forPK:(NSString *)pk username:(NSString *)username picURL:(NSString *)picURL {
    if (!pk.length) return;
    dispatch_sync(ioQ(), ^{
        NSMutableDictionary *rec = recFrom(overrides()[pk]);
        rec[@"notify"] = @(notifyMask);
        rec[@"log"] = @(logMask);
        if (username.length) rec[@"username"] = username;
        if (picURL.length) rec[@"pic"] = picURL;
        overrides()[pk] = rec;
        save();
    });
    [self post];
}

+ (NSString *)overrideUsernameForPK:(NSString *)pk {
    if (!pk.length) return nil;
    __block NSString *r = nil;
    dispatch_sync(ioQ(), ^{ r = metaOf(overrides()[pk], @"username"); });
    return r;
}

+ (NSString *)overridePicURLForPK:(NSString *)pk {
    if (!pk.length) return nil;
    __block NSString *r = nil;
    dispatch_sync(ioQ(), ^{ r = metaOf(overrides()[pk], @"pic"); });
    return r;
}

+ (void)clearOverrideForPK:(NSString *)pk {
    if (!pk.length) return;
    dispatch_sync(ioQ(), ^{ [overrides() removeObjectForKey:pk]; save(); });
    [self post];
}

+ (NSArray<NSString *> *)peopleWithOverrides {
    __block NSArray *a = @[];
    dispatch_sync(ioQ(), ^{ a = overrides().allKeys; });
    return a;
}

#pragma mark - Gate

+ (BOOL)shouldNotifyType:(RYGActivityType)type forPK:(NSString *)pk {
    if (![RYGUtils getBoolPref:@"activity_notif_enabled"]) return NO;
    if (pk.length) {
        __block BOOL has = NO; __block RYGActivityType m = 0;
        dispatch_sync(ioQ(), ^{ id v = overrides()[pk]; if (v) { has = YES; m = notifyMaskOf(v); } });
        if (has) return (m & type) != 0;
    }
    return ([self globalModeForType:type] & RYGActivityModeNotify) != 0;
}

+ (BOOL)shouldLogType:(RYGActivityType)type forPK:(NSString *)pk {
    if (![RYGUtils getBoolPref:@"activity_notif_enabled"]) return NO;
    if (pk.length) {
        __block BOOL hasLog = NO; __block RYGActivityType m = 0;
        dispatch_sync(ioQ(), ^{ id v = overrides()[pk]; if (hasLogKey(v)) { hasLog = YES; m = logMaskOf(v); } });
        if (hasLog) return (m & type) != 0;
    }
    return ([self globalModeForType:type] & RYGActivityModeLog) != 0;
}

@end
