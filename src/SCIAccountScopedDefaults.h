// Account-scoped NSUserDefaults wrapper. Keys become "<base>_acct_<pk>" when
// a current user PK is resolvable, else the bare key (pre-login). One-time
// migration moves bare-key data into the active account on first read.

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

@interface SCIAccountScopedDefaults : NSObject

+ (NSString *)scopedKey:(NSString *)baseKey;

+ (nullable id)objectForKey:(NSString *)baseKey;
+ (nullable NSArray *)arrayForKey:(NSString *)baseKey;
+ (nullable NSDictionary *)dictForKey:(NSString *)baseKey;
+ (void)setObject:(nullable id)value forKey:(NSString *)baseKey;
+ (void)removeObjectForKey:(NSString *)baseKey;

// Explicit-PK variants — hit "<base>_acct_<pk>" for any account without being
// signed into it (nil pk = bare key). Lets backup round-trip every account.
+ (NSString *)scopedKey:(NSString *)baseKey forPK:(nullable NSString *)pk;
+ (nullable id)objectForKey:(NSString *)baseKey pk:(nullable NSString *)pk;
+ (void)setObject:(nullable id)value forKey:(NSString *)baseKey pk:(nullable NSString *)pk;
+ (void)removeObjectForKey:(NSString *)baseKey pk:(nullable NSString *)pk;

// Every PK that currently has data stored under any of `baseKeys`
// (scanning "<base>_acct_<pk>" keys in NSUserDefaults).
+ (NSArray<NSString *> *)allKnownPKsForBaseKeys:(NSArray<NSString *> *)baseKeys;

@end

NS_ASSUME_NONNULL_END
