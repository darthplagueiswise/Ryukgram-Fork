#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

@class SCIResolverSpecifierEntry;

@interface SCIResolverScanner : NSObject

+ (void *)findPattern:(NSString *)patternMask inSegment:(NSString *)segmentName;
+ (void *)findMobileConfigFunctionAddress;

+ (NSArray<SCIResolverSpecifierEntry *> *)allKnownSpecifierEntries;

+ (NSString *)runDogfoodDeveloperReport;
+ (NSString *)runMobileConfigSymbolReport;
+ (NSString *)runFullResolverReport;

+ (void)applyOverrideForSpecifier:(unsigned long long)specifier value:(BOOL)value;
+ (void)removeOverrideForSpecifier:(unsigned long long)specifier;
+ (NSDictionary<NSNumber *, NSNumber *> *)allResolverOverrides;
+ (void)clearAllResolverOverrides;

@end

NS_ASSUME_NONNULL_END
