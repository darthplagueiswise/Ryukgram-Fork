#import "RYGStoryViewerPins.h"
#import "../../Utils.h"
#import "../../RYGAccountScopedDefaults.h"

#define RYG_STORY_PINS_KEY @"story_pinned_viewers"

// Cached per-account snapshot — isPinned/rankOfPK run per row during reorder
// and scroll. Keyed by the scoped key so an account switch invalidates it.
static NSString *gCacheKey = nil;
static NSArray *gCacheArr = nil;
static NSDictionary<NSString *, NSNumber *> *gCacheRank = nil;

@implementation RYGStoryViewerPins

+ (void)primeCache {
    NSString *scoped = [RYGAccountScopedDefaults scopedKey:RYG_STORY_PINS_KEY];
    if (gCacheArr && [gCacheKey isEqualToString:scoped]) return;
    NSArray *a = [RYGAccountScopedDefaults arrayForKey:RYG_STORY_PINS_KEY];
    gCacheArr = [a isKindOfClass:NSArray.class] ? a : @[];
    NSMutableDictionary *rank = [NSMutableDictionary dictionaryWithCapacity:gCacheArr.count];
    [gCacheArr enumerateObjectsUsingBlock:^(NSDictionary *e, NSUInteger i, BOOL *stop) {
        NSString *pk = e[@"pk"];
        if ([pk isKindOfClass:NSString.class] && pk.length && !rank[pk]) rank[pk] = @(i);
    }];
    gCacheRank = rank;
    gCacheKey = scoped;
}

+ (NSArray<NSDictionary *> *)allEntries { [self primeCache]; return gCacheArr; }

+ (NSUInteger)count { return [self allEntries].count; }

+ (void)saveAll:(NSArray *)entries {
    [RYGAccountScopedDefaults setObject:(entries ?: @[]) forKey:RYG_STORY_PINS_KEY];
    gCacheArr = nil; gCacheKey = nil; gCacheRank = nil;
}

+ (NSUInteger)rankOfPK:(NSString *)pk {
    if (pk.length == 0) return NSNotFound;
    [self primeCache];
    NSNumber *r = gCacheRank[pk];
    return r ? r.unsignedIntegerValue : NSNotFound;
}

+ (BOOL)isPinned:(NSString *)pk {
    if (pk.length == 0) return NO;
    [self primeCache];
    return gCacheRank[pk] != nil;
}

+ (NSDictionary *)entryForPK:(NSString *)pk {
    NSUInteger r = [self rankOfPK:pk];
    return r == NSNotFound ? nil : [self allEntries][r];
}

+ (void)addOrUpdateEntry:(NSDictionary *)entry {
    NSString *pk = entry[@"pk"];
    if (pk.length == 0) return;
    NSMutableArray *all = [[self allEntries] mutableCopy];
    NSInteger idx = -1;
    for (NSInteger i = 0; i < (NSInteger)all.count; i++) {
        if ([all[i][@"pk"] isEqualToString:pk]) { idx = i; break; }
    }
    NSMutableDictionary *merged = [entry mutableCopy];
    if (idx >= 0) {
        NSDictionary *old = all[idx];
        if (old[@"addedAt"]) merged[@"addedAt"] = old[@"addedAt"];
        for (NSString *k in @[@"username", @"fullName", @"avatarURL"]) {
            if (![merged[k] length] && [old[k] length]) merged[k] = old[k];
        }
        all[idx] = merged;
    } else {
        if (!merged[@"addedAt"]) merged[@"addedAt"] = @([[NSDate date] timeIntervalSince1970]);
        [all insertObject:merged atIndex:0];   // newest pin = top priority
    }
    [self saveAll:all];
}

+ (void)removePK:(NSString *)pk {
    if (pk.length == 0) return;
    NSMutableArray *all = [[self allEntries] mutableCopy];
    [all filterUsingPredicate:[NSPredicate predicateWithBlock:^BOOL(NSDictionary *e, id _) {
        return ![e[@"pk"] isEqualToString:pk];
    }]];
    [self saveAll:all];
}

+ (BOOL)togglePK:(NSString *)pk entry:(NSDictionary *)entry {
    if (pk.length == 0) return NO;
    if ([self isPinned:pk]) { [self removePK:pk]; return NO; }
    NSMutableDictionary *e = [(entry ?: @{}) mutableCopy];
    e[@"pk"] = pk;
    [self addOrUpdateEntry:e];
    return YES;
}

+ (void)setOrder:(NSArray<NSDictionary *> *)entries { [self saveAll:entries]; }

@end
