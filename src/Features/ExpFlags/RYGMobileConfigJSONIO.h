#import "RYGMobileConfig.h"

NS_ASSUME_NONNULL_BEGIN

typedef NS_ENUM(NSInteger, RYGMCNameMappingImportMode) {
    /// The imported JSON becomes RyukGram's complete persisted id_name_mapping
    /// overlay. Any prior imported overlay entries not present in the new file
    /// are removed.
    RYGMCNameMappingImportModeReplace = 0,

    /// Merge the imported JSON with the mapping already available to RyukGram.
    /// Existing configs/params are preserved when absent from the import; the
    /// imported file wins on config-name or param-name conflicts.
    RYGMCNameMappingImportModeMerge,
};

@interface RYGMobileConfig (RYGJSONIO)
- (nullable NSString *)ryg_nativeDataDirectory;
- (nullable NSString *)ryg_nativeNameMappingPath;
- (nullable NSString *)ryg_nativeOverridesJSONPath;
- (BOOL)ryg_importNameMappingData:(NSData *)data error:(NSError **)error;
- (BOOL)ryg_importNameMappingData:(NSData *)data
                             mode:(RYGMCNameMappingImportMode)mode
                            error:(NSError **)error;
- (nullable NSData *)ryg_exportNameMappingData:(NSError **)error;
- (BOOL)ryg_importAndApplyOverridesData:(NSData *)data
                           appliedCount:(NSUInteger *)appliedCount
                                  error:(NSError **)error;
- (nullable NSData *)ryg_exportOverridesData:(NSError **)error;
@end

NS_ASSUME_NONNULL_END