#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

@interface SCIResolverScanner : NSObject

+ (NSString *)runDogfoodDeveloperReport;
+ (NSString *)runMobileConfigSymbolReport;
+ (NSString *)runFullResolverReport;

@end

NS_ASSUME_NONNULL_END
