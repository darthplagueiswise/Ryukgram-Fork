#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

typedef void (^SCIGraphQLInternalToolsCompletion)(NSString *message);

FOUNDATION_EXPORT void SCIRegisterGraphQLInternalDefaults(void);

@interface SCIGraphQLInternalTools : NSObject

+ (NSString *)currentFOASandboxOverride;
+ (NSString *)setFOASandboxHostname:(NSString *)hostname reason:(NSString *)reason;
+ (NSString *)resetFOASandboxOverride;

+ (void)warmupGraphQLDebugWithCompletion:(SCIGraphQLInternalToolsCompletion)completion;
+ (void)retrieveGraphQLACSTokenWithCompletion:(SCIGraphQLInternalToolsCompletion)completion;
+ (void)retrieveGraphQLACSTokenAndOHAIWithCompletion:(SCIGraphQLInternalToolsCompletion)completion;

@end

NS_ASSUME_NONNULL_END
