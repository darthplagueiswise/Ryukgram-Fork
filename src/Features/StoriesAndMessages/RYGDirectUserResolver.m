#import "RYGDirectUserResolver.h"
#import <UIKit/UIKit.h>
#import <objc/runtime.h>

// Weak so account-switch / logout drops it; the hook re-stamps on every
// cache delta.
static __weak id rygCachedApplicator = nil;

// Persistent pk -> {username, pic} directory. The live applicator map only knows
// users in currently-loaded threads, so presence/typing PKs for people you
// haven't opened this session miss. This sticks every user we ever see to disk
// so any DM contact resolves app-wide and across launches.
static NSMutableDictionary<NSString *, NSDictionary *> *rygDir;
static dispatch_queue_t rygDirQ;
static BOOL rygDirDirty;

static NSString *rygDirPath(void) {
    NSString *root = NSSearchPathForDirectoriesInDomains(NSApplicationSupportDirectory, NSUserDomainMask, YES).firstObject;
    NSString *d = [root stringByAppendingPathComponent:@"RyukGram"];
    [NSFileManager.defaultManager createDirectoryAtPath:d withIntermediateDirectories:YES attributes:nil error:nil];
    return [d stringByAppendingPathComponent:@"UserDirectory.json"];
}
static void rygDirInit(void) {
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        rygDirQ = dispatch_queue_create("com.ryukgram.userdir", DISPATCH_QUEUE_SERIAL);
        id j = [NSJSONSerialization JSONObjectWithData:([NSData dataWithContentsOfFile:rygDirPath()] ?: [NSData data]) options:0 error:nil];
        rygDir = [j isKindOfClass:NSDictionary.class] ? [j mutableCopy] : [NSMutableDictionary dictionary];
    });
}
static void rygDirFlushSoon(void) {
    rygDirDirty = YES;
    static dispatch_once_t t; dispatch_once(&t, ^{
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(3 * NSEC_PER_SEC)), rygDirQ, ^{});
    });
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(3 * NSEC_PER_SEC)), rygDirQ, ^{
        if (!rygDirDirty) return;
        rygDirDirty = NO;
        NSData *d = [NSJSONSerialization dataWithJSONObject:rygDir options:0 error:nil];
        [d writeToFile:rygDirPath() atomically:YES];
    });
}
static void rygDirRecord(NSString *pk, NSString *username, NSString *pic) {
    if (!pk.length || (!username.length && !pic.length)) return;
    rygDirInit();
    dispatch_async(rygDirQ, ^{
        NSDictionary *cur = rygDir[pk];
        NSString *u = username.length ? username : cur[@"u"];
        NSString *p = pic.length ? pic : cur[@"p"];
        NSDictionary *next = p.length ? @{ @"u": u ?: @"", @"p": p } : (u.length ? @{ @"u": u } : nil);
        if (next && ![next isEqualToDictionary:cur]) { rygDir[pk] = next; rygDirFlushSoon(); }
    });
}
static NSString *rygDirName(NSString *pk) {
    if (!pk.length) return nil;
    rygDirInit();
    __block NSString *v = nil;
    dispatch_sync(rygDirQ, ^{ v = rygDir[pk][@"u"]; });
    return v.length ? v : nil;
}
static NSString *rygDirPic(NSString *pk) {
    if (!pk.length) return nil;
    rygDirInit();
    __block NSString *v = nil;
    dispatch_sync(rygDirQ, ^{ v = rygDir[pk][@"p"]; });
    return v.length ? v : nil;
}

NSArray<NSDictionary *> *rygDirectUserResolverAllKnown(void) {
    rygDirInit();
    __block NSMutableArray *out = [NSMutableArray array];
    dispatch_sync(rygDirQ, ^{
        [rygDir enumerateKeysAndObjectsUsingBlock:^(NSString *pk, NSDictionary *v, BOOL *stop) {
            NSString *u = v[@"u"];
            if (!u.length) return;
            NSMutableDictionary *e = [@{ @"pk": pk, @"username": u } mutableCopy];
            if ([v[@"p"] length]) e[@"pic"] = v[@"p"];
            [out addObject:e];
        }];
    });
    [out sortUsingComparator:^NSComparisonResult(NSDictionary *a, NSDictionary *b) {
        return [a[@"username"] caseInsensitiveCompare:b[@"username"]];
    }];
    return out;
}

NSString *rygDirectUserResolverPicForPK(NSString *pk) {
    if (!pk.length) return nil;
    return rygDirPic(pk) ?: rygDirectUserResolverProfilePicURLStringForPK(pk);
}

void rygDirectUserResolverRecordUser(id user) {
    if (!user) return;
    NSString *pk = rygDirectUserResolverPKFromUser(user);
    if (!pk.length) return;
    rygDirRecord(pk, rygDirectUserResolverUsernameFromUser(user), rygDirectUserResolverProfilePicURLStringFromUser(user));
}

// Walk the applicator's whole user map and cache everyone — one cheap sweep so
// names persist even for threads not reopened this session.
static void rygHarvestApplicator(id applicator) {
    if (!applicator) return;
    @try {
        Ivar umIv = class_getInstanceVariable([applicator class], "_userMap");
        id userMap = umIv ? object_getIvar(applicator, umIv) : nil;
        Ivar omIv = userMap ? class_getInstanceVariable([userMap class], "_objectMap") : NULL;
        id objMap = omIv ? object_getIvar(userMap, omIv) : nil;
        Ivar oIv = objMap ? class_getInstanceVariable([objMap class], "_objects") : NULL;
        id store = oIv ? object_getIvar(objMap, oIv) : nil;
        if (![store respondsToSelector:@selector(objectEnumerator)]) return;
        for (id user in [store objectEnumerator]) rygDirectUserResolverRecordUser(user);
    } @catch (__unused id e) {}
}

void rygDirectUserResolverSetActiveApplicator(id applicator) {
    if (!applicator) return;
    rygCachedApplicator = applicator;
    static double lastHarvest = 0;
    double now = CFAbsoluteTimeGetCurrent();
    if (now - lastHarvest > 8.0) { lastHarvest = now; dispatch_async(dispatch_get_global_queue(QOS_CLASS_UTILITY, 0), ^{ rygHarvestApplicator(applicator); }); }
}

#pragma mark - IGUser field extraction

NSString *rygDirectUserResolverPKFromUser(id user) {
    if (!user) return nil;
    @try {
        for (NSString *key in @[@"pk", @"instagramUserID", @"instagramUserId", @"userID", @"userId", @"identifier"]) {
            @try {
                id v = [user valueForKey:key];
                if ([v isKindOfClass:[NSString class]] && [(NSString *)v length] > 0) return v;
                if ([v isKindOfClass:[NSNumber class]]) return [(NSNumber *)v stringValue];
            } @catch (__unused id e) {}
        }
    } @catch (__unused id e) {}
    return nil;
}

NSString *rygDirectUserResolverUsernameFromUser(id user) {
    if (!user) return nil;
    @try {
        id un = [user valueForKey:@"username"];
        if ([un isKindOfClass:[NSString class]] && [(NSString *)un length] > 0) return un;
    } @catch (__unused id e) {}
    return nil;
}

NSString *rygDirectUserResolverProfilePicURLStringFromUser(id user) {
    if (!user) return nil;
    @try {
        for (NSString *key in @[@"profilePicURL", @"profilePictureURL", @"profileImageURL"]) {
            @try {
                id v = [user valueForKey:key];
                if ([v isKindOfClass:[NSURL class]]) return [(NSURL *)v absoluteString];
                if ([v isKindOfClass:[NSString class]] && [(NSString *)v length] > 0) return v;
            } @catch (__unused id e) {}
        }
    } @catch (__unused id e) {}
    return nil;
}

#pragma mark - PK lookup

// applicator._userMap._objectMap._objects (NSMapTable). IG mutates the map
// on its own queue so the lookup hops onto _queue when present.
id rygDirectUserResolverUserForPK(NSString *pk) {
    if (pk.length == 0) return nil;
    id applicator = rygCachedApplicator;
    if (!applicator) return nil;

    @try {
        Ivar umIv = class_getInstanceVariable([applicator class], "_userMap");
        id userMap = umIv ? object_getIvar(applicator, umIv) : nil;
        if (!userMap) return nil;
        Ivar omIv = class_getInstanceVariable([userMap class], "_objectMap");
        id objMap = omIv ? object_getIvar(userMap, omIv) : nil;
        if (!objMap) return nil;
        Ivar oIv = class_getInstanceVariable([objMap class], "_objects");
        id store = oIv ? object_getIvar(objMap, oIv) : nil;
        if (!store) return nil;

        Ivar qIv = class_getInstanceVariable([userMap class], "_queue");
        id qObj = qIv ? object_getIvar(userMap, qIv) : nil;
        Class dqCls = NSClassFromString(@"OS_dispatch_queue");
        dispatch_queue_t userQueue = (dqCls && [qObj isKindOfClass:dqCls]) ? (dispatch_queue_t)qObj : nil;

        __block id result = nil;
        dispatch_block_t lookup = ^{
            id user = nil;
            if ([store isKindOfClass:[NSMapTable class]]) {
                NSMapTable *mt = (NSMapTable *)store;
                user = [mt objectForKey:pk];
                if (!user) user = [mt objectForKey:@([pk longLongValue])];
                if (!user) {
                    for (id candidate in [mt objectEnumerator]) {
                        NSString *cpk = rygDirectUserResolverPKFromUser(candidate);
                        if (cpk && [cpk isEqualToString:pk]) { user = candidate; break; }
                    }
                }
            } else if ([store isKindOfClass:[NSDictionary class]]) {
                user = ((NSDictionary *)store)[pk];
                if (!user) user = ((NSDictionary *)store)[@([pk longLongValue])];
            }
            result = user;
        };

        if (userQueue) {
            @try { dispatch_sync(userQueue, lookup); }
            @catch (__unused id e) { lookup(); }
        } else {
            lookup();
        }
        return result;
    } @catch (__unused id e) {}
    return nil;
}

NSString *rygDirectUserResolverUsernameForPK(NSString *pk) {
    id user = rygDirectUserResolverUserForPK(pk);
    if (user) {
        NSString *u = rygDirectUserResolverUsernameFromUser(user);
        if (u.length) { rygDirectUserResolverRecordUser(user); return u; }
    }
    return rygDirName(pk);
}

NSString *rygDirectUserResolverProfilePicURLStringForPK(NSString *pk) {
    id user = rygDirectUserResolverUserForPK(pk);
    if (user) {
        NSString *p = rygDirectUserResolverProfilePicURLStringFromUser(user);
        if (p.length) { rygDirectUserResolverRecordUser(user); return p; }
    }
    return rygDirPic(pk);
}
