#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

@interface RYGCFunctionOverrideEngine : NSObject
+ (BOOL)isKnownBoolFunctionSymbol:(NSString *)symbol;
+ (nullable NSNumber *)forceForSymbol:(NSString *)symbol;
+ (nullable NSNumber *)observedValueForSymbol:(NSString *)symbol;
+ (NSUInteger)callCountForSymbol:(NSString *)symbol;
+ (BOOL)setForce:(nullable NSNumber *)value forSymbol:(NSString *)symbol;
@end

NS_ASSUME_NONNULL_END
