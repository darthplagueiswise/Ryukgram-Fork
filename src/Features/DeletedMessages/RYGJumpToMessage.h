#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

@interface RYGJumpToMessage : NSObject

+ (BOOL)available;

// `sentAt` is used to stop paging once the chat is older than the message.
+ (void)openThreadId:(NSString *)threadId
		   messageId:(nullable NSString *)messageId
			  sentAt:(nullable NSDate *)sentAt;

@end

NS_ASSUME_NONNULL_END
