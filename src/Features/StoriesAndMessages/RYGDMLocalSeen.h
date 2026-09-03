#import <Foundation/Foundation.h>

extern NSString * const RYGDMSeenStateDidChangeNotification;

// pk is the thread's own viewer — the inbox renders every signed-in account's threads.
@interface RYGDMLocalSeen : NSObject
+ (void)recordThreadId:(NSString *)threadId coveredTs:(double)ts pk:(NSString *)pk;
+ (double)localSeenTsForThreadId:(NSString *)threadId pk:(NSString *)pk;

+ (void)recordServerSeenThreadId:(NSString *)threadId ts:(double)ts;
+ (void)recordServerSeenThreadId:(NSString *)threadId ts:(double)ts pk:(NSString *)pk;
+ (void)seedServerSeenThreadId:(NSString *)threadId ts:(double)ts pk:(NSString *)pk;
+ (double)serverSeenTsForThreadId:(NSString *)threadId pk:(NSString *)pk;

+ (void)noteNewestIncomingTs:(double)ts forThreadId:(NSString *)threadId pk:(NSString *)pk;
+ (double)newestIncomingTsForThreadId:(NSString *)threadId pk:(NSString *)pk;

+ (BOOL)isServerPendingForThreadId:(NSString *)threadId;
@end
