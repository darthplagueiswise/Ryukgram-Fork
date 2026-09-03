#import "RYGExcludedThreads.h"
#import "../../Utils.h"
#import "../../RYGAccountScopedDefaults.h"

#define RYG_EXCL_KEY @"excluded_threads"
#define RYG_INCL_KEY @"included_threads"

@implementation RYGExcludedThreads

static NSString *rygActiveTid = nil;
static NSString *rygActiveViewerPK = nil;

+ (BOOL)isFeatureEnabled {
    return [RYGUtils getBoolPref:@"enable_chat_exclusions"];
}

+ (BOOL)isBlockSelectedMode {
    return [[RYGUtils getStringPref:@"chat_blocking_mode"] isEqualToString:@"block_selected"];
}

+ (NSString *)activeKey {
    return [self isBlockSelectedMode] ? RYG_INCL_KEY : RYG_EXCL_KEY;
}

+ (NSArray<NSDictionary *> *)allEntries {
    return [RYGAccountScopedDefaults arrayForKey:[self activeKey]] ?: @[];
}

+ (NSUInteger)count { return [self allEntries].count; }

+ (void)saveAll:(NSArray *)entries {
    [RYGAccountScopedDefaults setObject:entries forKey:[self activeKey]];
}

+ (NSDictionary *)entryForThreadId:(NSString *)threadId {
    if (threadId.length == 0) return nil;
    for (NSDictionary *e in [self allEntries]) {
        if ([e[@"threadId"] isEqualToString:threadId]) return e;
    }
    return nil;
}

+ (BOOL)isInList:(NSString *)threadId {
    return [self entryForThreadId:threadId] != nil;
}

+ (BOOL)isThreadIdExcluded:(NSString *)threadId {
    if (![self isFeatureEnabled]) return NO;
    BOOL inList = [self isInList:threadId];
    return [self isBlockSelectedMode] ? !inList : inList;
}

+ (BOOL)shouldKeepDeletedBeBlockedForThreadId:(NSString *)threadId {
    if (![self isFeatureEnabled]) return NO;
    NSDictionary *e = [self entryForThreadId:threadId];

    if ([self isBlockSelectedMode]) {
        // block_selected: listed chats are blocked
        // NOT in list → normal chat → block keep-deleted if default pref is on
        // IN list → blocked chat → keep-deleted should work (not blocked) unless overridden
        if (!e) return [RYGUtils getBoolPref:@"exclusions_default_keep_deleted"];
        RYGKeepDeletedOverride mode = [e[@"keepDeletedOverride"] integerValue];
        if (mode == RYGKeepDeletedOverrideExcluded) return YES;
        if (mode == RYGKeepDeletedOverrideIncluded) return NO;
        return NO; // default: keep-deleted works in blocked chats
    }

    // block_all: listed chats are excluded (behave normally)
    if (!e) return NO;
    RYGKeepDeletedOverride mode = [e[@"keepDeletedOverride"] integerValue];
    if (mode == RYGKeepDeletedOverrideExcluded) return YES;
    if (mode == RYGKeepDeletedOverrideIncluded) return NO;
    return [RYGUtils getBoolPref:@"exclusions_default_keep_deleted"];
}

+ (void)addOrUpdateEntry:(NSDictionary *)entry {
    NSString *tid = entry[@"threadId"];
    if (tid.length == 0) return;
    NSMutableArray *all = [[self allEntries] mutableCopy];
    NSInteger existingIdx = -1;
    for (NSInteger i = 0; i < (NSInteger)all.count; i++) {
        if ([all[i][@"threadId"] isEqualToString:tid]) { existingIdx = i; break; }
    }
    NSMutableDictionary *merged = [entry mutableCopy];
    if (existingIdx >= 0) {
        NSDictionary *old = all[existingIdx];
        if (old[@"addedAt"]) merged[@"addedAt"] = old[@"addedAt"];
        if (old[@"keepDeletedOverride"]) merged[@"keepDeletedOverride"] = old[@"keepDeletedOverride"];
        all[existingIdx] = merged;
    } else {
        if (!merged[@"addedAt"]) merged[@"addedAt"] = @([[NSDate date] timeIntervalSince1970]);
        if (!merged[@"keepDeletedOverride"]) merged[@"keepDeletedOverride"] = @(RYGKeepDeletedOverrideDefault);
        [all addObject:merged];
    }
    [self saveAll:all];
}

+ (void)removeThreadId:(NSString *)threadId {
    if (threadId.length == 0) return;
    NSMutableArray *all = [[self allEntries] mutableCopy];
    [all filterUsingPredicate:[NSPredicate predicateWithBlock:^BOOL(NSDictionary *e, id _) {
        return ![e[@"threadId"] isEqualToString:threadId];
    }]];
    [self saveAll:all];
}

+ (void)setKeepDeletedOverride:(RYGKeepDeletedOverride)mode forThreadId:(NSString *)threadId {
    if (threadId.length == 0) return;
    NSMutableArray *all = [[self allEntries] mutableCopy];
    for (NSInteger i = 0; i < (NSInteger)all.count; i++) {
        if ([all[i][@"threadId"] isEqualToString:threadId]) {
            NSMutableDictionary *m = [all[i] mutableCopy];
            m[@"keepDeletedOverride"] = @(mode);
            all[i] = m;
            break;
        }
    }
    [self saveAll:all];
}

+ (void)setActiveThreadId:(NSString *)threadId { [self setActiveThreadId:threadId viewerPK:nil]; }

+ (void)setActiveThreadId:(NSString *)threadId viewerPK:(NSString *)pk {
    rygActiveTid = [threadId copy];
    rygActiveViewerPK = [pk copy];
}

+ (NSString *)activeThreadId { return rygActiveTid; }
+ (NSString *)activeViewerPK { return rygActiveViewerPK; }
+ (BOOL)isActiveThreadExcluded { return [self isThreadIdExcluded:rygActiveTid]; }

@end
