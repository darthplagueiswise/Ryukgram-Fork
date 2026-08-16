#import "RYGActivityLogStore.h"
#import "../../Utils.h"

NSNotificationName const RYGActivityLogDidChangeNotification = @"RYGActivityLogDidChangeNotification";

static NSString *const kDir = @"RyukGram/ActivityLog";
static NSUInteger const kMaxPerPK = 200;
static NSTimeInterval const kMaxAge = 30 * 86400;

@implementation RYGActivityLogEvent
@end

@implementation RYGActivityLogStore

static NSString *lsStr(id v) { return [v isKindOfClass:NSString.class] ? v : nil; }

static dispatch_queue_t lsQ(void) {
    static dispatch_queue_t q; static dispatch_once_t once;
    dispatch_once(&once, ^{ q = dispatch_queue_create("com.ryukgram.activity.log", DISPATCH_QUEUE_SERIAL); });
    return q;
}

static NSString *storeFile(NSString *owner) {
    NSString *root = NSSearchPathForDirectoriesInDomains(NSApplicationSupportDirectory, NSUserDomainMask, YES).firstObject;
    NSString *dir = [root stringByAppendingPathComponent:kDir];
    [NSFileManager.defaultManager createDirectoryAtPath:dir withIntermediateDirectories:YES attributes:nil error:nil];
    return [dir stringByAppendingPathComponent:[NSString stringWithFormat:@"events_%@.json", owner.length ? owner : @"anon"]];
}

static NSMutableDictionary *sCache;
static NSString *sCacheOwner;

static NSMutableDictionary *load(NSString *owner) {
    if (sCache && [sCacheOwner isEqualToString:owner]) return sCache;
    NSData *d = [NSData dataWithContentsOfFile:storeFile(owner)];
    id j = d ? [NSJSONSerialization JSONObjectWithData:d options:0 error:nil] : nil;
    sCache = [j isKindOfClass:NSDictionary.class] ? [j mutableCopy] : [NSMutableDictionary dictionary];
    sCacheOwner = owner;
    return sCache;
}

static void save(NSString *owner) {
    NSDictionary *snap = [load(owner) copy];
    [[NSJSONSerialization dataWithJSONObject:snap options:0 error:nil] writeToFile:storeFile(owner) atomically:YES];
}

static void post(void) {
    dispatch_async(dispatch_get_main_queue(), ^{
        [NSNotificationCenter.defaultCenter postNotificationName:RYGActivityLogDidChangeNotification object:nil];
    });
}

static RYGActivityLogEvent *eventFromDict(NSDictionary *e, NSString *pk, NSString *un, NSString *pic) {
    RYGActivityLogEvent *ev = [RYGActivityLogEvent new];
    ev.type = (RYGActivityType)[e[@"t"] unsignedIntegerValue];
    ev.pk = pk;
    ev.username = un;
    ev.profilePicURL = pic;
    ev.at = [NSDate dateWithTimeIntervalSince1970:[e[@"ts"] doubleValue]];
    return ev;
}

+ (void)appendType:(RYGActivityType)type pk:(NSString *)pk username:(NSString *)username picURL:(NSString *)picURL ownerPK:(NSString *)ownerPK {
    if (!pk.length) return;
    NSString *owner = ownerPK.length ? ownerPK : @"anon";
    dispatch_async(lsQ(), ^{
        NSMutableDictionary *root = load(owner);
        NSMutableDictionary *rec = [(root[pk] ?: @{}) mutableCopy];
        if (username.length) rec[@"username"] = username;
        if (picURL.length) rec[@"pic"] = picURL;
        NSMutableArray *events = [(rec[@"events"] ?: @[]) mutableCopy];
        [events addObject:@{ @"t": @(type), @"ts": @(NSDate.date.timeIntervalSince1970) }];

        double cutoff = NSDate.date.timeIntervalSince1970 - kMaxAge;
        NSMutableArray *kept = [NSMutableArray array];
        for (NSDictionary *e in events) if ([e[@"ts"] doubleValue] >= cutoff) [kept addObject:e];
        if (kept.count > kMaxPerPK) [kept removeObjectsInRange:NSMakeRange(0, kept.count - kMaxPerPK)];

        rec[@"events"] = kept;
        root[pk] = rec;
        save(owner);
        post();
    });
}

+ (NSArray<NSString *> *)peopleForOwnerPK:(NSString *)ownerPK {
    NSString *owner = ownerPK.length ? ownerPK : @"anon";
    __block NSArray *a = @[];
    dispatch_sync(lsQ(), ^{ a = load(owner).allKeys; });
    return a;
}

+ (NSArray<RYGActivityLogEvent *> *)eventsForPK:(NSString *)pk ownerPK:(NSString *)ownerPK {
    if (!pk.length) return @[];
    NSString *owner = ownerPK.length ? ownerPK : @"anon";
    __block NSMutableArray *out = [NSMutableArray array];
    dispatch_sync(lsQ(), ^{
        NSDictionary *rec = load(owner)[pk];
        NSString *un = lsStr(rec[@"username"]), *pic = lsStr(rec[@"pic"]);
        for (NSDictionary *e in rec[@"events"]) if ([e isKindOfClass:NSDictionary.class]) [out addObject:eventFromDict(e, pk, un, pic)];
    });
    [out sortUsingComparator:^NSComparisonResult(RYGActivityLogEvent *a, RYGActivityLogEvent *b) { return [b.at compare:a.at]; }];
    return out;
}

+ (RYGActivityLogEvent *)latestEventForPK:(NSString *)pk ownerPK:(NSString *)ownerPK {
    return [self eventsForPK:pk ownerPK:ownerPK].firstObject;
}

+ (NSString *)usernameForPK:(NSString *)pk ownerPK:(NSString *)ownerPK {
    if (!pk.length) return nil;
    NSString *owner = ownerPK.length ? ownerPK : @"anon";
    __block NSString *r = nil;
    dispatch_sync(lsQ(), ^{ r = lsStr(load(owner)[pk][@"username"]); });
    return r;
}

+ (NSString *)picURLForPK:(NSString *)pk ownerPK:(NSString *)ownerPK {
    if (!pk.length) return nil;
    NSString *owner = ownerPK.length ? ownerPK : @"anon";
    __block NSString *r = nil;
    dispatch_sync(lsQ(), ^{ r = lsStr(load(owner)[pk][@"pic"]); });
    return r;
}

+ (void)applyUsername:(NSString *)username picURL:(NSString *)picURL forPK:(NSString *)pk ownerPK:(NSString *)ownerPK {
    if (!pk.length || (!username.length && !picURL.length)) return;
    NSString *owner = ownerPK.length ? ownerPK : @"anon";
    dispatch_async(lsQ(), ^{
        NSMutableDictionary *root = load(owner);
        if (!root[pk]) return;
        NSMutableDictionary *rec = [root[pk] mutableCopy];
        if (username.length) rec[@"username"] = username;
        if (picURL.length) rec[@"pic"] = picURL;
        root[pk] = rec;
        save(owner);
        post();
    });
}

+ (void)deleteEventsForPK:(NSString *)pk ownerPK:(NSString *)ownerPK {
    if (!pk.length) return;
    NSString *owner = ownerPK.length ? ownerPK : @"anon";
    dispatch_async(lsQ(), ^{ [load(owner) removeObjectForKey:pk]; save(owner); post(); });
}

+ (void)deleteEventsMatchingMask:(RYGActivityType)mask forPK:(NSString *)pk ownerPK:(NSString *)ownerPK {
    if (!pk.length || !mask) return;
    NSString *owner = ownerPK.length ? ownerPK : @"anon";
    dispatch_async(lsQ(), ^{
        NSMutableDictionary *root = load(owner);
        NSDictionary *cur = root[pk];
        if (!cur) return;
        NSMutableDictionary *rec = [cur mutableCopy];
        NSMutableArray *kept = [NSMutableArray array];
        for (NSDictionary *e in rec[@"events"])
            if ([e isKindOfClass:NSDictionary.class] && !([e[@"t"] unsignedIntegerValue] & mask)) [kept addObject:e];
        rec[@"events"] = kept;
        root[pk] = rec;
        save(owner);
        post();
    });
}

+ (void)deleteEventOfType:(RYGActivityType)type atTimestamp:(double)ts forPK:(NSString *)pk ownerPK:(NSString *)ownerPK {
    if (!pk.length) return;
    NSString *owner = ownerPK.length ? ownerPK : @"anon";
    dispatch_async(lsQ(), ^{
        NSMutableDictionary *root = load(owner);
        NSDictionary *cur = root[pk];
        if (!cur) return;
        NSMutableDictionary *rec = [cur mutableCopy];
        NSMutableArray *kept = [NSMutableArray array];
        BOOL removed = NO;
        for (NSDictionary *e in rec[@"events"]) {
            if (!removed && [e isKindOfClass:NSDictionary.class]
                && [e[@"t"] unsignedIntegerValue] == type && [e[@"ts"] doubleValue] == ts) { removed = YES; continue; }
            [kept addObject:e];
        }
        if (!removed) return;
        rec[@"events"] = kept;
        root[pk] = rec;
        save(owner);
        post();
    });
}

+ (void)resetForOwnerPK:(NSString *)ownerPK {
    NSString *owner = ownerPK.length ? ownerPK : @"anon";
    dispatch_async(lsQ(), ^{
        [load(owner) removeAllObjects];
        [NSFileManager.defaultManager removeItemAtPath:storeFile(owner) error:nil];
        post();
    });
}

@end
