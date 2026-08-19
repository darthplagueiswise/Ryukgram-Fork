#import <Foundation/Foundation.h>
@class RYGRuntimeBoolMethod;

NS_ASSUME_NONNULL_BEGIN

typedef NS_ENUM(NSInteger, RYGDeveloperRuntimeSurface) {
    RYGDeveloperRuntimeSurfacePrism = 0,
    RYGDeveloperRuntimeSurfaceLiquidGlass,
    RYGDeveloperRuntimeSurfaceStories,
    RYGDeveloperRuntimeSurfaceInternalOnly,
    RYGDeveloperRuntimeSurfaceBugReport,
    RYGDeveloperRuntimeSurfaceSettingsRows,
    RYGDeveloperRuntimeSurfaceDirectDogfood,
};

@interface RYGDeveloperRuntimeScanner : NSObject

/// Scans only the supplied loaded images and only returns BOOL methods whose
/// class/selector/image text matches at least one keyword. No hook is installed
/// and no private method is invoked by enumeration.
+ (NSArray<RYGRuntimeBoolMethod *> *)boolMethodsForImagePaths:(NSArray<NSString *> *)imagePaths
                                                    keywords:(NSArray<NSString *> *)keywords;

/// Topic-scoped live discovery used by the rebuilt Developer menu. The result is
/// produced from the currently loaded executable / FBSharedFramework and then
/// filtered by surface semantics; there is no shipped selector manifest and no
/// MobileConfig fallback.
+ (NSArray<RYGRuntimeBoolMethod *> *)boolMethodsForSurface:(RYGDeveloperRuntimeSurface)surface;

+ (NSString *)titleForSurface:(RYGDeveloperRuntimeSurface)surface;

/// Developer feature surfaces intentionally stay focused on the app executable
/// plus FBSharedFramework. The full Runtime Browser exposes every loaded app-owned
/// image independently.
+ (NSArray<NSString *> *)primaryDeveloperImagePaths;

@end

NS_ASSUME_NONNULL_END
