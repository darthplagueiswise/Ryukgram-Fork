#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

typedef NS_ENUM(NSInteger, RYGRuntimeArgumentKind) {
	RYGRuntimeArgumentNone = 0,
	RYGRuntimeArgumentObject,
	RYGRuntimeArgumentInteger,
};

typedef NS_ENUM(NSInteger, RYGRuntimeBrowserScope) {
	RYGRuntimeBrowserScopeRelevant = 0,
	RYGRuntimeBrowserScopeEmployee,
	RYGRuntimeBrowserScopeAll,
};

@interface RYGRuntimeBoolMethod : NSObject
@property (nonatomic, copy) NSString *imagePath;
@property (nonatomic, copy) NSString *className;
@property (nonatomic, copy) NSString *selectorName;
@property (nonatomic, copy) NSString *typeEncoding;
@property (nonatomic, assign) BOOL classMethod;
@property (nonatomic, assign) RYGRuntimeArgumentKind argumentKind;
@property (nonatomic, readonly) NSString *overrideKey;
@property (nonatomic, readonly, nullable) NSNumber *overrideValue;
@property (nonatomic, readonly, nullable) NSNumber *liveValue;
@end

@interface RYGMachOSymbol : NSObject
@property (nonatomic, copy) NSString *name;
@property (nonatomic, copy) NSString *kind;
@property (nonatomic, assign) uint64_t address;
@property (nonatomic, assign) BOOL external;
@end

@interface RYGRuntimeBrowserEngine : NSObject

/// A fresh dyld snapshot. Nothing is loaded from a shipped table or persisted
/// symbol cache. The app executable is first, then currently loaded app-owned
/// frameworks and dylibs.
+ (NSArray<NSString *> *)runtimeImagePaths;
+ (NSString *)shortNameForImagePath:(NSString *)imagePath;

/// Enumerates the selected image at call time. Only arm64 Objective-C BOOL
/// methods with a safe supported signature are returned.
+ (NSArray<RYGRuntimeBoolMethod *> *)boolMethodsForImagePath:(NSString *)imagePath
										 scope:(RYGRuntimeBrowserScope)scope;

/// Reads LC_SYMTAB from the selected loaded image. Addresses are live runtime
/// addresses and are deliberately never persisted.
+ (NSArray<RYGMachOSymbol *> *)machOSymbolsForImagePath:(NSString *)imagePath;

+ (BOOL)isStructuralNoiseSelectorName:(NSString *)selectorName;
+ (nullable NSNumber *)overrideForKey:(NSString *)overrideKey;
+ (void)setOverride:(nullable NSNumber *)value forMethod:(RYGRuntimeBoolMethod *)method;
+ (void)reinstallPersistedOverrides;

@end

NS_ASSUME_NONNULL_END
