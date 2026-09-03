// Persistent per-chat exclusion list for read-receipt features. Lookup is by
// canonical thread id (the MSYS string used by both inbox view models and
// IGDirectThreadViewController). Each entry carries a per-thread keep-deleted
// override that can force-include or force-exclude regardless of the global
// default.
#import <Foundation/Foundation.h>

typedef NS_ENUM(NSInteger, RYGKeepDeletedOverride) {
    RYGKeepDeletedOverrideDefault  = 0, // follow exclusions_default_keep_deleted
    RYGKeepDeletedOverrideExcluded = 1, // force keep-deleted OFF for this thread
    RYGKeepDeletedOverrideIncluded = 2, // force keep-deleted ON  for this thread
};

@interface RYGExcludedThreads : NSObject

+ (BOOL)isFeatureEnabled;
+ (BOOL)isBlockSelectedMode; // YES = only listed chats get blocked

+ (BOOL)isThreadIdExcluded:(NSString *)threadId;
+ (BOOL)isInList:(NSString *)threadId; // raw list check, ignores mode
+ (BOOL)shouldKeepDeletedBeBlockedForThreadId:(NSString *)threadId;
+ (NSDictionary *)entryForThreadId:(NSString *)threadId;
+ (NSArray<NSDictionary *> *)allEntries;
+ (NSUInteger)count;

+ (void)addOrUpdateEntry:(NSDictionary *)entry;
+ (void)removeThreadId:(NSString *)threadId;
+ (void)setKeepDeletedOverride:(RYGKeepDeletedOverride)mode forThreadId:(NSString *)threadId;

// Currently-visible thread, set by IGDirectThreadViewController hooks.
+ (void)setActiveThreadId:(NSString *)threadId;
// Both participants share a thread id, so the viewer is what tells the copies apart.
+ (void)setActiveThreadId:(NSString *)threadId viewerPK:(NSString *)pk;
+ (NSString *)activeThreadId;
+ (NSString *)activeViewerPK;
+ (BOOL)isActiveThreadExcluded;

@end
