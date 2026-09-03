#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

@interface RYGSecureBlob : NSObject

+ (nullable NSData *)decryptContainer:(NSData *)container;
+ (nullable NSData *)decryptBundleResource:(NSString *)name ofType:(NSString *)type;

@end

NS_ASSUME_NONNULL_END
