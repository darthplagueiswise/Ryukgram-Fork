#import "RYGMobileConfig.h"

NS_ASSUME_NONNULL_BEGIN

@interface RYGMobileConfig (RYGJSONIO)
- (nullable NSString *)ryg_nativeDataDirectory;
- (nullable NSString *)ryg_nativeNameMappingPath;
- (nullable NSString *)ryg_nativeOverridesJSONPath;
- (BOOL)ryg_importNameMappingData:(NSData *)data error:(NSError **)error;
- (nullable NSData *)ryg_exportNameMappingData:(NSError **)error;
- (BOOL)ryg_importAndApplyOverridesData:(NSData *)data appliedCount:(NSUInteger *)appliedCount error:(NSError **)error;
- (nullable NSData *)ryg_exportOverridesData:(NSError **)error;
@end

NS_ASSUME_NONNULL_END
