#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

extern NSString * const SCIMobileConfigIdNameMappingExporterDidUpdateNotification;

@interface SCIMobileConfigIdNameMappingExporter : NSObject

+ (NSDictionary *)exportIDNameMappingNow;
+ (NSDictionary *)exportDeprecatedStartupConfigsNow;
+ (NSDictionary *)installNativePathObserver;
+ (NSArray<NSString *> *)candidateIDNameMappingPaths;
+ (nullable NSString *)lastStatusLine;

@end

// DexKit v3 IGMobile JSON path. This method is implemented by
// SCIIgMobileDeprecatedJSONExporter.xm as a category, so it must not be declared
// in the primary interface above; otherwise Clang emits -Wincomplete-implementation
// for SCIMobileConfigIdNameMappingExporter.m.
@interface SCIMobileConfigIdNameMappingExporter (SCIIgMobileDeprecatedJSON)
+ (NSDictionary *)exportIGMobileDeprecatedJSONNow;
@end

NS_ASSUME_NONNULL_END
