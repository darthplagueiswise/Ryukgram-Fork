#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

typedef NS_ENUM(NSInteger, RYGRuntimeArgumentKind) {
    RYGRuntimeArgumentNone = 0,
    RYGRuntimeArgumentObject,
    RYGRuntimeArgumentInteger,
};

// Kept only for source compatibility. Runtime enumeration is not preclassified.
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
+ (NSArray<NSString *> *)runtimeImagePaths;
+ (NSString *)shortNameForImagePath:(NSString *)imagePath;

/// Returns live ObjC BOOL methods for the selected loaded image. `scope` is
/// ignored deliberately; no name/employee/gate classification is performed.
/// Historical ObjC BOOL encodings B/c/C are accepted after ABI validation.
+ (NSArray<RYGRuntimeBoolMethod *> *)boolMethodsForImagePath:(NSString *)imagePath
                                                      scope:(RYGRuntimeBrowserScope)scope;

/// Reads the selected image's live Mach-O symbol table.
+ (NSArray<RYGMachOSymbol *> *)machOSymbolsForImagePath:(NSString *)imagePath;

/// Installs one pass-through trampoline for this exact ABI-validated method.
/// Without an override it only observes the original result.
+ (BOOL)observeMethod:(RYGRuntimeBoolMethod *)method;
+ (nullable NSNumber *)observedNativeValueForKey:(NSString *)overrideKey;

/// Runtime Browser overrides are intentionally process-local. They are never
/// installed automatically during app startup or dyld image loading.
+ (nullable NSNumber *)overrideForKey:(NSString *)overrideKey;
+ (void)setOverride:(nullable NSNumber *)value forMethod:(RYGRuntimeBoolMethod *)method;
+ (void)reinstallPersistedOverrides; // compatibility no-op

+ (BOOL)isStructuralNoiseSelectorName:(NSString *)selectorName;
@end

NS_ASSUME_NONNULL_END
