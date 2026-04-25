#import <Foundation/Foundation.h>

@interface SCIExpMobileConfigMapping : NSObject

+ (NSString *)resolvedNameForSpecifier:(unsigned long long)specifier;
+ (NSString *)mappingSourceDescription;
+ (void)reloadMapping;

@end
