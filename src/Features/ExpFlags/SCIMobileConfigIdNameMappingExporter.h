#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

extern NSString * const SCIMobileConfigIdNameMappingExporterDidUpdateNotification;

@interface SCIMobileConfigIdNameMappingExporter : NSObject

+ (NSDictionary *)exportIDNameMappingNow;
+ (NSDictionary *)installNativePathObserver;
+ (NSArray<NSString *> *)candidateIDNameMappingPaths;
+ (NSDictionary *)mobileConfigAssetExperimentReport;
+ (NSDictionary *)copyMobileConfigAssetExperimentFiles;
+ (nullable NSString *)lastStatusLine;

@end

NS_ASSUME_NONNULL_END
