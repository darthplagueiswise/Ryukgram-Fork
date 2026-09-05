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
@property(nonatomic, copy) NSArray<NSString *> *selectorTokens;
@property(nonatomic, assign) BOOL scanInstanceMethods;
@property(nonatomic, assign) BOOL scanClassMethods;
@property(nonatomic, assign) BOOL scanProperties;
@property(nonatomic, assign) BOOL runtimeGenerated;
@property(nonatomic, copy, nullable) NSString *runtimeImagePath;
@property(nonatomic, copy, nullable) NSString *runtimeFamilyKey;
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
+ (NSArray<RYGRuntimeEntry *> *)scanSurface:(RYGRuntimeSurfaceSpec *)spec;
+ (NSArray<RYGRuntimeSurfaceSpec *> *)runtimeImageSurfaces;
+ (NSArray<RYGRuntimeSurfaceSpec *> *)runtimeFamilySurfaces;
+ (RYGRuntimeSurfaceSpec *)allAppSurfaceWithTitle:(NSString *)title query:(NSString *)query;
@end

NS_ASSUME_NONNULL_END
