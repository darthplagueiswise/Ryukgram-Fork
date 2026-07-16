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

// GraphQL Debug capability inspection. Warmup is exposed, but ACS/OHAI token
// retrieval is intentionally not invoked or displayed.
+ (NSString *)graphQLDebugCapabilities;
+ (void)warmupGraphQLDebugWithCompletion:(void (^)(NSString *result))completion;

@end

NS_ASSUME_NONNULL_END
