#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

@interface SCIMachODexKitResolvedName : NSObject

@property (nonatomic, copy) NSString *name;
@property (nonatomic, copy) NSString *source;
@property (nonatomic, copy) NSString *confidence;
@property (nonatomic, assign) unsigned long long specifier;

@end

@interface SCIMachODexKitResolver : NSObject

+ (instancetype)sharedResolver;

- (SCIMachODexKitResolvedName *)resolvedNameForSpecifier:(unsigned long long)specifier
                                            functionName:(NSString * _Nullable)functionName
                                            existingName:(NSString * _Nullable)existingName
                                           callerAddress:(void * _Nullable)callerAddress;

- (NSDictionary<NSNumber *, NSString *> *)allKnownSpecifierNames;
- (NSArray<NSString *> *)reportLines;
- (void)rebuildIndex;

@end

NS_ASSUME_NONNULL_END
