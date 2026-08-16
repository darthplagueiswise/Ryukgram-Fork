// SCISymbolBrowserEngine.h
// Runtime ObjC experiment/gating browser for the app executable and every
// currently loaded framework/dylib inside the Instagram bundle.
#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

typedef NS_ENUM(NSInteger, SCISymbolImage) {
	SCISymbolImageInstagram = 0,
	SCISymbolImageFBShared  = 1,
};

typedef NS_ENUM(NSInteger, SCISymbolArgumentKind) {
	SCISymbolArgumentNone = 0,
	SCISymbolArgumentObject,
	SCISymbolArgumentInteger,
};

@interface SCISymbolGetter : NSObject
@property (nonatomic, copy) NSString *selectorName;
@property (nonatomic, copy) NSString *ownerClassName;
@property (nonatomic, copy) NSString *typeEncoding;
@property (nonatomic, readonly) NSString *overrideKey;
@property (nonatomic, assign) BOOL isClassMethod;
@property (nonatomic, assign) SCISymbolArgumentKind argumentKind;
@property (nonatomic, readonly) BOOL isParameterized;
@property (nonatomic, readonly, nullable) NSNumber *liveValue;
@property (nonatomic, readonly, nullable) NSNumber *override;
@end

@interface SCISymbolClass : NSObject
@property (nonatomic, copy) NSString *className;
@property (nonatomic, strong) NSArray<SCISymbolGetter *> *getters;
@end

@interface SCISymbolBrowserEngine : NSObject
/// Snapshot of loaded app-owned Mach-O images. Main executable is first;
/// Frameworks/*.framework and Frameworks/*.dylib follow alphabetically.
+ (NSArray<NSString *> *)runtimeImagePaths;
+ (NSString *)shortNameForImagePath:(NSString *)imagePath;
+ (NSArray<SCISymbolClass *> *)classesForImagePath:(NSString *)imagePath;
+ (BOOL)isStructuralNoiseSelectorName:(NSString *)selectorName;

/// Legacy two-image API retained for existing callers. FBShared maps to
/// FBSharedFramework when loaded, otherwise InstagramSharedFramework.
+ (NSArray<SCISymbolClass *> *)classesForImage:(SCISymbolImage)image;
+ (nullable NSNumber *)liveValueForClass:(NSString *)className selector:(NSString *)selectorName isClassMethod:(BOOL)isClassMethod;
+ (nullable NSNumber *)overrideForKey:(NSString *)overrideKey;
+ (BOOL)hookInstalledForKey:(NSString *)overrideKey;
+ (BOOL)installOverrideForKey:(NSString *)overrideKey;
+ (void)setOverride:(nullable NSNumber *)value forClass:(NSString *)className selector:(NSString *)selectorName isClassMethod:(BOOL)isClassMethod;
+ (void)reinstallPersistedHooks;

// Explicit, on-demand experiment surfaces. No broad runtime scan occurs in %ctor.
+ (NSUInteger)setExperimentManagersForced:(nullable NSNumber *)value;
+ (NSUInteger)setExperimentConfigsForced:(nullable NSNumber *)value;
+ (NSUInteger)setExperimentHelpersForced:(nullable NSNumber *)value;
+ (NSUInteger)sweepForceForClassNeedles:(NSArray<NSString *> *)classNeedles selectorNeedles:(NSArray<NSString *> *)selectorNeedles forcedValue:(BOOL)forcedValue;
@end

NS_ASSUME_NONNULL_END
