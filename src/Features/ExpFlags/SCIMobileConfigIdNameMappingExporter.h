#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

extern NSString * const SCIMobileConfigIdNameMappingExporterDidUpdateNotification;

@interface SCIMobileConfigIdNameMappingExporter : NSObject

// Legacy compatibility: callers may still use this selector, but DexKit v3 no longer
// treats the result as id_name_mapping. It delegates to IGMobile deprecated JSON export.
+ (NSDictionary *)exportIDNameMappingNow;
+ (NSDictionary *)exportDeprecatedStartupConfigsNow;
+ (NSDictionary *)exportIGMobileDeprecatedJSONNow;
+ (NSDictionary *)installNativePathObserver;
+ (NSArray<NSString *> *)candidateIDNameMappingPaths;
+ (nullable NSString *)lastStatusLine;

@end

NS_ASSUME_NONNULL_END
