#import <Foundation/Foundation.h>
@class RYGRuntimeBoolMethod;

NS_ASSUME_NONNULL_BEGIN

@interface RYGDeveloperRuntimeScanner : NSObject

/// Scans only the supplied loaded images and only returns BOOL methods whose
/// class/selector/image text matches at least one keyword. No hooks are
/// installed and no private method is invoked.
+ (NSArray<RYGRuntimeBoolMethod *> *)boolMethodsForImagePaths:(NSArray<NSString *> *)imagePaths
                                                    keywords:(NSArray<NSString *> *)keywords;

/// Developer feature surfaces intentionally stay focused on the app executable
/// plus FBSharedFramework. The full runtime browser still exposes every loaded
/// app-owned image.
+ (NSArray<NSString *> *)primaryDeveloperImagePaths;

@end

NS_ASSUME_NONNULL_END
