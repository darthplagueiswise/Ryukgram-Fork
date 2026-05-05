#import <Foundation/Foundation.h>

@interface SCIExpMobileConfigMapping : NSObject

+ (NSString *)resolvedNameForSpecifier:(unsigned long long)specifier;
+ (NSString *)mappingSourceDescription;
+ (NSString *)mappingDebugDescription;
+ (NSArray<NSString *> *)candidateMappingPaths;
+ (NSArray<NSString *> *)checkedMappingPaths;
+ (NSArray<NSString *> *)foundMappingPaths;
+ (void)reloadMapping;

@end
