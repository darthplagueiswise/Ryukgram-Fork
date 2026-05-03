#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

@interface SCIAutofillInternalDevMode : NSObject

+ (void)registerDefaults;
+ (void)applyEnabledToggles;
+ (NSDictionary<NSString *, id> *)statusSnapshot;
+ (NSString *)statusText;

@end

NS_ASSUME_NONNULL_END
