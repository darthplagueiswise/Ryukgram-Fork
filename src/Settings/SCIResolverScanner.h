#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

@interface SCIResolverScanner : NSObject

+ (void *)findPattern:(NSString *)patternMask inSegment:(NSString *)segmentName;
+ (void *)findMobileConfigFunctionAddress;

+ (NSString *)runDogfoodDeveloperReport;
+ (NSString *)runMobileConfigSymbolReport;
+ (NSString *)runFullResolverReport;

@end

NS_ASSUME_NONNULL_END
