#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

@interface SCIMobileConfigNativeOverrides : NSObject

+ (NSDictionary<NSString *, id> *)symbolStatus;
+ (BOOL)canAttemptNativeOverride;
+ (BOOL)applyBoolOverrideForParamID:(unsigned long long)paramID value:(BOOL)value error:(NSError **)error;
+ (BOOL)applyInt64OverrideForParamID:(unsigned long long)paramID value:(long long)value error:(NSError **)error;
+ (BOOL)applyDoubleOverrideForParamID:(unsigned long long)paramID value:(double)value error:(NSError **)error;
+ (BOOL)applyStringOverrideForParamID:(unsigned long long)paramID value:(NSString *)value error:(NSError **)error;
+ (BOOL)removeOverrideForParamID:(unsigned long long)paramID error:(NSError **)error;
+ (BOOL)applyRuntimeFallbackOverrideForParamID:(unsigned long long)paramID type:(NSString *)type value:(id)value error:(NSError **)error;
+ (BOOL)removeRuntimeFallbackOverrideForParamID:(unsigned long long)paramID type:(NSString *)type;

@end

NS_ASSUME_NONNULL_END
