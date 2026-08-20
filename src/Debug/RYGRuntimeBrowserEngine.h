#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

typedef NS_ENUM(NSInteger, RYGRuntimeArgumentKind) {
    RYGRuntimeArgumentNone = 0,
    RYGRuntimeArgumentObject,
    RYGRuntimeArgumentInteger,
};

// Source-compatibility only. The runtime browser never uses these values to
// pre-classify methods by names such as employee/gate/feature.
typedef NS_ENUM(NSInteger, RYGRuntimeBrowserScope) {
    RYGRuntimeBrowserScopeRelevant = 0,
    RYGRuntimeBrowserScopeEmployee,
    RYGRuntimeBrowserScopeAll,
};

typedef NS_ENUM(NSInteger, RYGRuntimeMemberKind) {
    RYGRuntimeMemberInstanceMethod = 0,
    RYGRuntimeMemberClassMethod,
    RYGRuntimeMemberInstanceProperty,
    RYGRuntimeMemberClassProperty,
};

@interface RYGRuntimeClassRow : NSObject
@property (nonatomic, copy) NSString *imagePath;
@property (nonatomic, copy) NSString *className;
@end

@interface RYGRuntimeMemberRow : NSObject
@property (nonatomic, copy) NSString *imagePath;
@property (nonatomic, copy) NSString *className;
@property (nonatomic, copy) NSString *name;
@property (nonatomic, copy) NSString *typeEncoding;
@property (nonatomic, assign) RYGRuntimeMemberKind kind;
@property (nonatomic, assign) BOOL hookableBool;
@property (nonatomic, assign) RYGRuntimeArgumentKind argumentKind;
@property (nonatomic, readonly) BOOL method;
@property (nonatomic, readonly) BOOL classMember;
@end

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

/// dyld images loaded in the current process. The returned paths are the paths
/// the Objective-C runtime itself can use with objc_copyClassNamesForImage().
+ (NSArray<NSString *> *)runtimeImagePaths;
+ (NSString *)shortNameForImagePath:(NSString *)imagePath;

/// Live image -> class enumeration. No method-name/category table is cached or
/// shipped with the tweak; class names are requested from the Objective-C
/// runtime for the selected loaded image each time this method runs.
+ (NSArray<RYGRuntimeClassRow *> *)classesForImagePath:(NSString *)imagePath;

/// Reads the class at the moment the user opens/searches it. Only methods and
/// properties declared by the class/metaclass are returned; inherited NSObject
/// plumbing is not synthesized into the result.
+ (NSArray<RYGRuntimeMemberRow *> *)membersForClassName:(NSString *)className
                                              imagePath:(NSString *)imagePath;

/// Converts an ABI-supported BOOL method row into the one hook model used by
/// Observe / Force True / Force False. Returns nil for properties or unsupported
/// ABI shapes; unsupported members remain browsable but cannot be hooked.
+ (nullable RYGRuntimeBoolMethod *)boolMethodForMember:(RYGRuntimeMemberRow *)member;

/// Compatibility API for exact owner-based Developer pages. `scope` is ignored
/// deliberately. It returns ABI-supported BOOL methods from the selected image,
/// never a keyword-preclassified feature table.
+ (NSArray<RYGRuntimeBoolMethod *> *)boolMethodsForImagePath:(NSString *)imagePath
                                                      scope:(RYGRuntimeBrowserScope)scope;

/// Reads the selected loaded image's in-memory Mach-O symbol table. Symbols are
/// metadata only until a concrete C ABI is known; the generic browser never
/// guesses a function prototype from its name.
+ (NSArray<RYGMachOSymbol *> *)machOSymbolsForImagePath:(NSString *)imagePath;

/// Installs one process-local pass-through trampoline for this exact validated
/// Objective-C ABI. The original IMP is called first and its BOOL is recorded.
+ (BOOL)observeMethod:(RYGRuntimeBoolMethod *)method;
+ (nullable NSNumber *)observedNativeValueForKey:(NSString *)overrideKey;

/// Runtime Browser overrides are process-local and explicit. Nothing is
/// reinstalled at launch or when another dyld image is loaded.
+ (nullable NSNumber *)overrideForKey:(NSString *)overrideKey;
+ (void)setOverride:(nullable NSNumber *)value forMethod:(RYGRuntimeBoolMethod *)method;
+ (void)reinstallPersistedOverrides; // compatibility no-op

/// Filters only universal Objective-C infrastructure (isEqual:, respondsTo…,
/// etc.). It never classifies app features by words such as employee/internal.
+ (BOOL)isStructuralNoiseSelectorName:(NSString *)selectorName;

@end

NS_ASSUME_NONNULL_END
