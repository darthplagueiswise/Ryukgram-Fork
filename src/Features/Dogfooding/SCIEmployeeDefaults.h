#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

@interface SCIEmployeeDefaults : NSObject
+ (BOOL)enabled;
+ (void)installHooksIfNeeded;
+ (void)applyToStandardDefaults;
+ (void)applyToUserSession:(nullable id)session source:(NSString *)source;
+ (void)applyToObject:(nullable id)obj source:(NSString *)source;
+ (NSArray<NSString *> *)employeeDefaultKeys;
@end

NS_ASSUME_NONNULL_END
