#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

@interface SCIGraphQLDogfoodDiagnostics : NSObject

// Installs read-only observers for the exact dogfood GraphQL models and
// backend-check entrypoints validated in the current Instagram executable.
+ (NSString *)installObservers;
+ (NSString *)snapshot;

// FOA environment override. This changes the client backend hostname only;
// it does not bypass authentication or server authorization.
+ (NSString *)currentFOASandboxOverride;
+ (NSString *)setFOASandboxHostname:(NSString *)hostname;
+ (NSString *)resetFOASandboxOverride;

// GraphQL Debug provider actions. Credential checks report only presence,
// runtime class and errors; token/config contents are never logged or shown.
+ (NSString *)graphQLDebugCapabilities;
+ (void)warmupGraphQLDebugWithCompletion:(void (^)(NSString *result))completion;
+ (void)retrieveGraphQLDebugACSTokenStatusWithCompletion:(void (^)(NSString *result))completion;
+ (void)retrieveGraphQLDebugACSAndOHAIStatusWithCompletion:(void (^)(NSString *result))completion;

@end

NS_ASSUME_NONNULL_END
