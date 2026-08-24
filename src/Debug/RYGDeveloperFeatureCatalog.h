#import <Foundation/Foundation.h>
#import "RYGDeveloperTopicViewController.h"

@class RYGRuntimeBoolMethod;

NS_ASSUME_NONNULL_BEGIN

FOUNDATION_EXPORT NSNotificationName const RYGDeveloperFeatureCatalogDidUpdateNotification;
FOUNDATION_EXPORT NSString *const RYGDeveloperFeatureCatalogSurfaceUserInfoKey;

/// Lightweight Developer-only feature catalogue.
///
/// The catalogue is independent from Runtime Browser UI/state.  Starting it is
/// effectively free: only a dyld image-generation marker is registered.  Known
/// owners are prewarmed after Developer is opened; a loaded-class walk is only
/// allowed for the single domain the user explicitly opens.
@interface RYGDeveloperFeatureCatalog : NSObject

+ (instancetype)sharedCatalog;

/// Idempotent; does not enumerate Objective-C classes or methods.
- (void)startIfNeeded;

/// Called when the Developer root is visible. Resolves only the tiny per-domain
/// known-owner lists on the private queue; never performs objc_getClassList.
- (void)prewarmKnownOwners;

/// Immutable in-memory snapshot. Never performs discovery synchronously.
- (NSArray<RYGRuntimeBoolMethod *> *)snapshotForSurface:(RYGDeveloperRuntimeSurface)surface;

/// Refreshes on the private queue. When discoverAdditionalClasses is NO, only
/// known owners are checked with objc_lookUpClass. When YES, a scoped walk over
/// already-loaded app classes is allowed for this one domain.
- (void)requestRefreshForSurface:(RYGDeveloperRuntimeSurface)surface
        discoverAdditionalClasses:(BOOL)discoverAdditionalClasses;

- (BOOL)isRefreshingSurface:(RYGDeveloperRuntimeSurface)surface;

@end

NS_ASSUME_NONNULL_END
