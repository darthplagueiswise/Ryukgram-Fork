// Persistent per-account list of DM thread ids filtered out of the inbox.
// Added via the inbox long-press menu, managed under S&P → Hidden chats.

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

@interface SCIHiddenChats : NSObject

+ (NSArray<NSDictionary *> *)allEntries;
+ (NSArray<NSString *> *)allThreadIDs;
+ (BOOL)isHidden:(NSString *)threadId;

+ (void)addEntry:(NSDictionary *)entry;
+ (void)removeThreadId:(NSString *)threadId;
+ (void)setAllEntries:(NSArray<NSDictionary *> *)entries;

@end

NS_ASSUME_NONNULL_END
