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

typedef NS_ENUM(NSInteger, RYGRuntimeMemberKind) {
    RYGRuntimeMemberInstanceMethod = 0,
    RYGRuntimeMemberClassMethod,
    RYGRuntimeMemberInstanceProperty,
    RYGRuntimeMemberClassProperty,
};

@interface RYGRuntimeClassRow : NSObject
@property (nonatomic, copy) NSString *imagePath;
@property (nonatomic, copy) NSString *className;
@property (nonatomic, assign) NSUInteger instanceMethodCount;
@property (nonatomic, assign) NSUInteger classMethodCount;
@property (nonatomic, assign) NSUInteger propertyCount;
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
+ (NSArray<NSString *> *)runtimeImagePaths;
+ (NSString *)shortNameForImagePath:(NSString *)imagePath;
+ (NSArray<RYGRuntimeClassRow *> *)classesForImagePath:(NSString *)imagePath;
+ (NSArray<RYGRuntimeMemberRow *> *)membersForClassName:(NSString *)className imagePath:(NSString *)imagePath;
+ (nullable RYGRuntimeBoolMethod *)boolMethodForMember:(RYGRuntimeMemberRow *)member;
+ (NSArray<RYGRuntimeBoolMethod *> *)boolMethodsForImagePath:(NSString *)imagePath scope:(RYGRuntimeBrowserScope)scope;
+ (NSArray<RYGMachOSymbol *> *)machOSymbolsForImagePath:(NSString *)imagePath;
+ (BOOL)observeMethod:(RYGRuntimeBoolMethod *)method;
+ (nullable NSNumber *)observedNativeValueForKey:(NSString *)overrideKey;
+ (nullable NSNumber *)overrideForKey:(NSString *)overrideKey;
+ (void)setOverride:(nullable NSNumber *)value forMethod:(RYGRuntimeBoolMethod *)method;
+ (void)reinstallPersistedOverrides;
+ (BOOL)isStructuralNoiseSelectorName:(NSString *)selectorName;
@end

NS_ASSUME_NONNULL_END
