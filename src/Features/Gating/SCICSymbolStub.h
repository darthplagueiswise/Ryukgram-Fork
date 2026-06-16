// SCICSymbolStub.h
// FBShared C symbol runtime hook engine.
//
// This is intentionally NOT a blind "force any symbol" layer. It has two
// persisted modes:
//   - observe: fishhook a validated BOOL reader, call orig, record hits/value,
//              return orig. This is safe for multi-key readers.
//   - force:   only for curated single-purpose BOOL functions. Returns YES/NO
//              after optional orig call, using a plain C atomic cache.
//
// Hot path never calls NSUserDefaults/ObjC. All prefs are read at install time
// and refreshed only by explicit UI setter calls.

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

@interface SCICSymbolStub : NSObject

+ (BOOL)isBoolLikeSymbol:(NSString *)name;
+ (BOOL)isHookableSymbol:(NSString *)name;     // validated ABI/profile, observe safe
+ (BOOL)isForceableSymbol:(NSString *)name;    // safe single-purpose only
+ (nullable NSString *)blacklistReasonForSymbol:(NSString *)name;
+ (nullable NSString *)notHookableReasonForSymbol:(NSString *)name;
+ (nullable NSString *)notForceableReasonForSymbol:(NSString *)name;

+ (BOOL)observeForSymbol:(NSString *)name;
+ (BOOL)setObserve:(BOOL)value forSymbol:(NSString *)name;
+ (NSArray<NSString *> *)observedSymbols;

+ (nullable NSNumber *)forceForSymbol:(NSString *)name;
+ (BOOL)setForce:(nullable NSNumber *)value forSymbol:(NSString *)name;
+ (NSArray<NSString *> *)forcedSymbols;

+ (BOOL)hookInstalledForSymbol:(NSString *)name;
+ (NSUInteger)callCountForSymbol:(NSString *)name;
+ (nullable NSNumber *)observedValueForSymbol:(NSString *)name;

+ (BOOL)installStubForSymbol:(NSString *)name;
+ (void)reinstallPersistedStubs;
+ (void)refreshCacheFromDefaults;

@end

NS_ASSUME_NONNULL_END
