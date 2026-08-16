#import "RYGExcludedStoryUsers.h"
#import "../../Utils.h"
#import "../../RYGAccountScopedDefaults.h"

#define RYG_STORY_EXCL_KEY @"excluded_story_users"
#define RYG_STORY_INCL_KEY @"included_story_users"

@implementation RYGExcludedStoryUsers

+ (BOOL)isFeatureEnabled {
    return [RYGUtils getBoolPref:@"enable_story_user_exclusions"];
}

+ (BOOL)isBlockSelectedMode {
    return [[RYGUtils getStringPref:@"story_blocking_mode"] isEqualToString:@"block_selected"];
}

+ (NSString *)activeKey {
    return [self isBlockSelectedMode] ? RYG_STORY_INCL_KEY : RYG_STORY_EXCL_KEY;
}

+ (NSArray<NSDictionary *> *)allEntries {
    return [RYGAccountScopedDefaults arrayForKey:[self activeKey]] ?: @[];
}

+ (NSUInteger)count { return [self allEntries].count; }

+ (void)saveAll:(NSArray *)entries {
    [RYGAccountScopedDefaults setObject:entries forKey:[self activeKey]];
}

+ (NSDictionary *)entryForPK:(NSString *)pk {
    if (pk.length == 0) return nil;
    for (NSDictionary *e in [self allEntries]) {
        if ([e[@"pk"] isEqualToString:pk]) return e;
    }
    return nil;
}

+ (BOOL)isInList:(NSString *)pk {
    return [self entryForPK:pk] != nil;
}

+ (BOOL)isUserPKExcluded:(NSString *)pk {
    if (![self isFeatureEnabled]) return NO;
    BOOL inList = [self isInList:pk];
    return [self isBlockSelectedMode] ? !inList : inList;
}

+ (void)addOrUpdateEntry:(NSDictionary *)entry {
    NSString *pk = entry[@"pk"];
    if (pk.length == 0) return;
    NSMutableArray *all = [[self allEntries] mutableCopy];
    NSInteger existingIdx = -1;
    for (NSInteger i = 0; i < (NSInteger)all.count; i++) {
        if ([all[i][@"pk"] isEqualToString:pk]) { existingIdx = i; break; }
    }
    NSMutableDictionary *merged = [entry mutableCopy];
    if (existingIdx >= 0) {
        NSDictionary *old = all[existingIdx];
        if (old[@"addedAt"]) merged[@"addedAt"] = old[@"addedAt"];
        all[existingIdx] = merged;
    } else {
        if (!merged[@"addedAt"]) merged[@"addedAt"] = @([[NSDate date] timeIntervalSince1970]);
        [all addObject:merged];
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

@end
