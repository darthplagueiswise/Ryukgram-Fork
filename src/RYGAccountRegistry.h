#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

FOUNDATION_EXPORT NSNotificationName const RYGAccountRegistryDidChangeNotification;

// Names every account seen on this device, so its data reads as @name once logged out.
@interface RYGAccountRegistry : NSObject

+ (void)noteCurrentAccount;

// pk -> { username, full_name, profile_pic_url, last_seen }
+ (NSDictionary<NSString *, NSDictionary *> *)allAccounts;
+ (nullable NSDictionary *)infoForPK:(NSString *)pk;

+ (NSString *)displayNameForPK:(NSString *)pk;
+ (NSString *)displayNameForPK:(NSString *)pk info:(nullable NSDictionary *)info;

// A backup's names, so an import can label accounts never logged in here.
+ (void)mergeAccounts:(NSDictionary<NSString *, NSDictionary *> *)accounts;

// Names any unknown pk over the current session. Cheap to call from anywhere:
// skips known/in-flight pks and backs off after a failure.
+ (void)resolveMissingNamesForPKs:(NSArray<NSString *> *)pks;

@end

NS_ASSUME_NONNULL_END
