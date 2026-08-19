#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

typedef NS_ENUM(NSInteger, RYGRuntimeArgumentKind) {
    RYGRuntimeArgumentNone = 0,
    RYGRuntimeArgumentObject,
    RYGRuntimeArgumentInteger,
};

// Retained for source compatibility with older callers. The live runtime no
// longer semantically preclassifies methods by these scopes; image enumeration
// returns every strict-BOOL method whose ABI is supported.
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

/// Fresh dyld snapshot. No shipped/persisted symbol table is used.
+ (NSArray<NSString *> *)runtimeImagePaths;
+ (NSString *)shortNameForImagePath:(NSString *)imagePath;

/// Compatibility API for callers that need a flat BOOL list. `scope` is
/// deliberately ignored: the current browser does not classify methods by name.
/// Enumeration is image-scoped and ABI-only.
+ (NSArray<RYGRuntimeBoolMethod *> *)boolMethodsForImagePath:(NSString *)imagePath
                                                      scope:(RYGRuntimeBrowserScope)scope;

/// Reads LC_SYMTAB from the selected loaded image. Addresses are current-process
/// runtime addresses and are never persisted.
+ (NSArray<RYGMachOSymbol *> *)machOSymbolsForImagePath:(NSString *)imagePath;

/// Installs the one unified pass-through/override trampoline for this exact
/// method. With no override it only records the original BOOL result; with an
/// override the same trampoline returns the forced value after recording native.
+ (BOOL)observeMethod:(RYGRuntimeBoolMethod *)method;
+ (nullable NSNumber *)observedNativeValueForKey:(NSString *)overrideKey;

+ (nullable NSNumber *)overrideForKey:(NSString *)overrideKey;
+ (void)setOverride:(nullable NSNumber *)value forMethod:(RYGRuntimeBoolMethod *)method;
+ (void)reinstallPersistedOverrides;

/// Kept for source compatibility only; runtime browsing/hooking no longer uses
/// name-based structural filtering.
+ (BOOL)isStructuralNoiseSelectorName:(NSString *)selectorName;

@end

NS_ASSUME_NONNULL_END
