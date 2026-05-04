#import <Foundation/Foundation.h>
#import "SCIExpFlags.h"

@interface SCIDexKitStore : NSObject

+ (NSString *)boolGetterKeyWithClassName:(NSString *)className methodName:(NSString *)methodName classMethod:(BOOL)classMethod;
+ (BOOL)parseBoolGetterKey:(NSString *)key className:(NSString **)className methodName:(NSString **)methodName classMethod:(BOOL *)classMethod;

+ (SCIExpFlagOverride)overrideForKey:(NSString *)key;
+ (void)setOverride:(SCIExpFlagOverride)override forKey:(NSString *)key;
+ (NSArray<NSString *> *)allOverrideKeys;
+ (NSArray<NSString *> *)allBoolGetterOverrideKeys;

+ (NSDictionary<NSString *, NSNumber *> *)observedBoolGetterValues;
+ (NSNumber *)observedBoolGetterValueForKey:(NSString *)key;
+ (void)setObservedBoolGetterValue:(BOOL)value forKey:(NSString *)key;

+ (BOOL)effectiveBoolValueForKey:(NSString *)key defaultKnown:(BOOL)defaultKnown defaultValue:(BOOL)defaultValue;
+ (NSString *)systemLabelForKnown:(BOOL)known value:(BOOL)value;
+ (NSString *)overrideLabelForKey:(NSString *)key;

@end
