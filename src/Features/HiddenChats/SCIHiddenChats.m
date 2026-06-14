#import "SCIHiddenChats.h"
#import "../../SCIAccountScopedDefaults.h"

static NSString *const kHiddenChatsKey = @"hidden_chats";

@implementation SCIHiddenChats

+ (NSArray<NSDictionary *> *)allEntries {
    NSArray *raw = [SCIAccountScopedDefaults arrayForKey:kHiddenChatsKey];
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
    [SCIAccountScopedDefaults setObject:list forKey:kHiddenChatsKey];
}

+ (void)removeThreadId:(NSString *)tid {
    if (!tid.length) return;
    NSMutableArray *list = [[self allEntries] mutableCopy];
    NSInteger idx = [self indexOfThreadID:tid in:list];
    if (idx == NSNotFound) return;
    [list removeObjectAtIndex:idx];
    [SCIAccountScopedDefaults setObject:list forKey:kHiddenChatsKey];
}

+ (void)setAllEntries:(NSArray<NSDictionary *> *)entries {
    NSMutableArray *out = [NSMutableArray arrayWithCapacity:entries.count];
    for (id e in entries) if ([e isKindOfClass:[NSDictionary class]] && [e[@"threadId"] length]) [out addObject:e];
    [SCIAccountScopedDefaults setObject:out forKey:kHiddenChatsKey];
}

@end
