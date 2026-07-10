// Account-scoped pin list for story viewers. Pinned users float to the top of
// the "who viewed my story" list and can be pinned even when they aren't in the
// current list (resolved by username in the manager). Lookup is by user pk.
#import <Foundation/Foundation.h>

@interface SCIStoryViewerPins : NSObject

+ (NSArray<NSDictionary *> *)allEntries;     // pin order: index 0 = top priority
+ (NSUInteger)count;

+ (BOOL)isPinned:(NSString *)pk;
+ (NSUInteger)rankOfPK:(NSString *)pk;       // NSNotFound if not pinned
+ (NSDictionary *)entryForPK:(NSString *)pk;

+ (void)addOrUpdateEntry:(NSDictionary *)entry; // {pk, username, fullName, avatarURL}
+ (void)removePK:(NSString *)pk;
+ (BOOL)togglePK:(NSString *)pk entry:(NSDictionary *)entry; // returns new pinned state
+ (void)setOrder:(NSArray<NSDictionary *> *)entries;

@end
