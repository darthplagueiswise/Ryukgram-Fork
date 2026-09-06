#pragma once
#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

@interface RYGRuntimeEntry : NSObject
@property(nonatomic, copy) NSString *surfaceID;
@property(nonatomic, copy) NSString *className;
@property(nonatomic, assign) BOOL classMethod;
@property(nonatomic, assign) BOOL property;
@property(nonatomic, copy) NSString *selectorName;
@property(nonatomic, copy) NSString *displayName;
@property(nonatomic, copy) NSString *category;
@property(nonatomic, copy) NSString *returnType;
@property(nonatomic, copy) NSString *typeCode;
@property(nonatomic, copy) NSString *typeName;
@property(nonatomic, copy) NSString *overrideKey;
@property(nonatomic, copy) NSString *imagePath;
@property(nonatomic, copy) NSString *imageName;
@property(nonatomic, copy) NSString *runtimeFamily;
@property(nonatomic, copy) NSString *runtimeSubcategory;
@end

@interface RYGRuntimeSurfaceSpec : NSObject
@property(nonatomic, copy) NSString *surfaceID;
@property(nonatomic, copy) NSString *title;
@property(nonatomic, copy) NSString *subtitle;
@property(nonatomic, copy) NSString *icon;
@property(nonatomic, strong) NSArray<NSString *> *classNames;
@property(nonatomic, strong) NSArray<NSString *> *classNameFragments;
/// Presentation-only compatibility metadata. The scanner never uses these
/// tokens to define the runtime universe; search/filtering happens after the
/// full selected-image/whole-host catalog has been built.
@property(nonatomic, strong) NSArray<NSString *> *selectorTokens;
@property(nonatomic, strong) NSArray<NSString *> *categoryAllowList;
@property(nonatomic, assign) BOOL scanInstanceMethods;
@property(nonatomic, assign) BOOL scanClassMethods;
@property(nonatomic, assign) BOOL scanProperties;
@property(nonatomic, assign) BOOL advancedOnly;
@property(nonatomic, copy, nullable) NSString *runtimeImagePath;
@property(nonatomic, copy, nullable) NSString *runtimeFamilyKey;
@property(nonatomic, assign) BOOL runtimeGenerated;
@property(nonatomic, assign) NSUInteger runtimeClassCount;
@property(nonatomic, assign) NSUInteger runtimeEntryCount;
+ (NSArray<RYGRuntimeSurfaceSpec *> *)allSurfaces;
@end

FOUNDATION_EXPORT NSString *RYGRuntimeImageNameForPath(NSString * _Nullable imagePath);
FOUNDATION_EXPORT NSString *RYGRuntimeFamilyForSelector(NSString * _Nullable selectorName,
                                                        NSString * _Nullable className);
FOUNDATION_EXPORT NSString *RYGRuntimeSubcategoryForEntry(NSString * _Nullable selectorName,
                                                           NSString * _Nullable className,
                                                           NSString * _Nullable imagePath);
FOUNDATION_EXPORT NSArray<NSString *> *RYGRuntimeQueryTerms(NSString * _Nullable query);

@interface RYGRuntimeScanner : NSObject
/// Full runtime catalog for the requested scope. No feature/domain keyword is
/// applied here. Supported methods are defined only by their Objective-C ABI.
+ (NSArray<RYGRuntimeEntry *> *)scanSurface:(RYGRuntimeSurfaceSpec *)spec;
/// Image-first root. Enumerates loaded Instagram-owned Mach-O images without
/// eagerly enumerating every method in the process.
+ (NSArray<RYGRuntimeSurfaceSpec *> *)runtimeImageSurfaces;
+ (NSArray<RYGRuntimeSurfaceSpec *> *)runtimeFamilySurfaces;
/// Whole-host scope used by Developer domain shortcuts. `query` is intentionally
/// not copied into scanner filters; it is applied by the browser after discovery.
+ (RYGRuntimeSurfaceSpec *)allAppSurfaceWithTitle:(NSString *)title query:(NSString *)query;
@end

NS_ASSUME_NONNULL_END
