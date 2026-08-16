// Presence + typing event log, account-scoped. Reads live in RYGReadReceiptStorage;
// this holds online / offline / typing events per person so the activity log can
// show a full per-person timeline. Append-only, capped and age-pruned.

#import <Foundation/Foundation.h>
#import "RYGActivityConfig.h"

NS_ASSUME_NONNULL_BEGIN

FOUNDATION_EXPORT NSNotificationName const RYGActivityLogDidChangeNotification;

@interface RYGActivityLogEvent : NSObject
@property (nonatomic, assign) RYGActivityType type;
@property (nonatomic, copy)   NSString *pk;
@property (nonatomic, copy, nullable) NSString *username;
@property (nonatomic, copy, nullable) NSString *profilePicURL;
@property (nonatomic, strong) NSDate *at;
@end

@interface RYGActivityLogStore : NSObject

+ (void)appendType:(RYGActivityType)type
                pk:(NSString *)pk
          username:(nullable NSString *)username
            picURL:(nullable NSString *)picURL
           ownerPK:(NSString *)ownerPK;

+ (NSArray<NSString *> *)peopleForOwnerPK:(NSString *)ownerPK;
+ (NSArray<RYGActivityLogEvent *> *)eventsForPK:(NSString *)pk ownerPK:(NSString *)ownerPK;
+ (nullable RYGActivityLogEvent *)latestEventForPK:(NSString *)pk ownerPK:(NSString *)ownerPK;
+ (NSString *)usernameForPK:(NSString *)pk ownerPK:(NSString *)ownerPK;
+ (NSString *)picURLForPK:(NSString *)pk ownerPK:(NSString *)ownerPK;

+ (void)applyUsername:(nullable NSString *)username picURL:(nullable NSString *)picURL forPK:(NSString *)pk ownerPK:(NSString *)ownerPK;

+ (void)deleteEventsForPK:(NSString *)pk ownerPK:(NSString *)ownerPK;
+ (void)deleteEventsMatchingMask:(RYGActivityType)mask forPK:(NSString *)pk ownerPK:(NSString *)ownerPK;
+ (void)deleteEventOfType:(RYGActivityType)type atTimestamp:(double)ts forPK:(NSString *)pk ownerPK:(NSString *)ownerPK;
+ (void)resetForOwnerPK:(NSString *)ownerPK;

@end

NS_ASSUME_NONNULL_END
