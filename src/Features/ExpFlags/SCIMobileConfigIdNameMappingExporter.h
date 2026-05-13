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

NS_ASSUME_NONNULL_END
