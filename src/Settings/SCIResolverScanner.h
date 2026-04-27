#import <Foundation/Foundation.h>

@class SCIResolverSpecifierEntry;

NS_ASSUME_NONNULL_BEGIN

@interface SCIResolverScanner : NSObject

+ (void *)findPattern:(NSString *)patternMask inSegment:(NSString *)segmentName;
+ (void *)findMobileConfigFunctionAddress;

+ (NSString *)runDogfoodDeveloperReport;
+ (NSString *)runMobileConfigSymbolReport;
+ (NSString *)runFullResolverReport;

+ (void)applyOverrideForSpecifier:(unsigned long long)specifier value:(BOOL)value;
+ (void)removeOverrideForSpecifier:(unsigned long long)specifier;
+ (NSDictionary<NSNumber *, NSNumber *> *)allResolverOverrides;
+ (void)clearAllResolverOverrides;

+ (NSArray<SCIResolverSpecifierEntry *> *)allKnownSpecifierEntries;

@end

NS_ASSUME_NONNULL_END
