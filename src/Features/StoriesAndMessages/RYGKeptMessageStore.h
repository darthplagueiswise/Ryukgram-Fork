// Archived copies of kept unsent messages, so a bubble survives Instagram dropping it.

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

@interface RYGKeptMessageStore : NSObject

+ (void)saveMessage:(id)message serverId:(NSString *)serverId ownerPK:(nullable NSString *)ownerPK;
+ (nullable id)messageForServerId:(NSString *)serverId ownerPK:(nullable NSString *)ownerPK;

// Mirror of what a thread has shown, so an older unsend still has a copy to restore.
+ (void)mirrorMessages:(NSDictionary<NSString *, id> *)messagesByServerId
			  threadId:(nullable NSString *)threadId
			   ownerPK:(nullable NSString *)ownerPK;
+ (nullable id)mirroredMessageForServerId:(NSString *)serverId ownerPK:(nullable NSString *)ownerPK;
+ (void)resetMirror;

+ (void)resetAll;
+ (void)resetForOwnerPK:(nullable NSString *)ownerPK;

@end

NS_ASSUME_NONNULL_END
