// SCICSymbolEngine.h
//
// Real runtime browser for FBSharedFramework exported C symbols. It enumerates
// the loaded FBSharedFramework Mach-O symbol table at runtime, then lets the
// user search the actual FBShared export universe. Hooking is opt-in and
// observe-only by default.

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

@interface SCICImport : NSObject
@property (nonatomic, copy) NSString *symbolName;
@property (nonatomic, copy) NSString *imageName;
@property (nonatomic, assign) BOOL resolvable;
@property (nonatomic, assign) BOOL boolLike;
@property (nonatomic, assign) BOOL forceBlacklisted;
@property (nonatomic, readonly) NSString *overrideKey;
@property (nonatomic, readonly, nullable) NSNumber *override;
@property (nonatomic, readonly) BOOL observing;
@property (nonatomic, readonly) BOOL hookInstalled;
@property (nonatomic, readonly) NSUInteger observedCallCount;
@property (nonatomic, readonly, nullable) NSNumber *observedValue;
@end

@interface SCICSymbolEngine : NSObject

// Runtime FBSharedFramework export universe. Search is evaluated when the UI asks
// for it; no full symbol scan runs in %ctor.
+ (NSArray<SCICImport *> *)searchImports:(nullable NSString *)query limit:(NSUInteger)limit;
+ (NSUInteger)totalImportCount;

// Force value for a symbol (nil = remove override). Returns NO if the symbol is
// not resolvable, not bool-like, or explicitly force-blacklisted.
+ (BOOL)setForce:(nullable NSNumber *)value forSymbolName:(NSString *)name;
+ (nullable NSNumber *)overrideForSymbolName:(NSString *)name;

// Observe-only hook. Replacement calls original, records hit count + real value,
// and returns original unless a force override exists.
+ (BOOL)setObserve:(BOOL)observe forSymbolName:(NSString *)name;
+ (BOOL)isObserving:(NSString *)name;

+ (NSUInteger)callCountForSymbolName:(NSString *)name;
+ (nullable NSNumber *)observedValueForSymbolName:(NSString *)name;
+ (BOOL)hookInstalledForSymbolName:(NSString *)name;
+ (BOOL)isForceBlacklistedSymbolName:(NSString *)name;
+ (BOOL)isBoolLikeSymbolName:(NSString *)name;

// Cheap launch gate used by SCICSymbolBootstrap.x.
+ (BOOL)hasPersistedHooks;
+ (BOOL)masterEnabled;
+ (void)reinstallPersistedHooks;

// Back-compat helpers used by the Dev UI quick toggle. These only target the
// curated internal/employee readers and still honor blacklist rules.
+ (NSArray<NSString *> *)internalGateSymbolNames;
+ (NSArray<NSString *> *)forceInternalReadersEnabled:(BOOL)enabled;

@end

NS_ASSUME_NONNULL_END
