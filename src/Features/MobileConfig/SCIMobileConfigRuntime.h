#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

FOUNDATION_EXPORT void SCIInstallMobileConfigRuntimeHooksIfNeeded(void);

@interface SCIMobileConfigRuntime : NSObject

+ (void)recordParamID:(unsigned long long)paramID
                 type:(NSString *)type
             returned:(nullable id)returned
         defaultValue:(nullable id)defaultValue
         sourceObject:(nullable id)sourceObject
             selector:(nullable NSString *)selector;

+ (void)recordParamID:(unsigned long long)paramID
                 type:(NSString *)type
             returned:(nullable id)returned
         defaultValue:(nullable id)defaultValue
          sourceClass:(nullable NSString *)sourceClass
             selector:(nullable NSString *)selector;

+ (NSArray<NSDictionary *> *)hotParams;
+ (NSArray<NSDictionary *> *)dogfoodCandidateParams;
+ (BOOL)deepCallerSymbolsEnabled;
+ (BOOL)onCriticalFacebookQueue;
+ (void)noteLiveObject:(nullable id)object role:(NSString *)role source:(nullable NSString *)source;
+ (NSArray<NSDictionary *> *)liveContexts;
+ (NSDictionary<NSString *, NSArray<NSDictionary *> *> *)paramsMapIndex;
+ (NSString *)mapSummaryForParamID:(unsigned long long)paramID;
+ (NSArray<NSDictionary *> *)mapCandidatesForParamID:(unsigned long long)paramID stableID:(nullable NSString *)stableID;
+ (void)reloadParamsMapIndex;
+ (void)clearObservations;

+ (BOOL)runtimeHooksEnabled;
+ (void)setRuntimeCaptureActive:(BOOL)active;
+ (BOOL)manualOverridesEnabled;
+ (nullable id)overrideForParamID:(unsigned long long)paramID type:(NSString *)type original:(nullable id)original;
+ (NSDictionary<NSString *, id> *)manualOverrides;
+ (void)setManualOverride:(id)value paramID:(unsigned long long)paramID type:(NSString *)type;
+ (void)removeManualOverrideForParamID:(unsigned long long)paramID type:(NSString *)type;
+ (void)clearManualOverrides;

// Name<->paramID binding + named overrides (gating patcher).
+ (void)beginBindingForName:(NSString *)name;
+ (NSArray<NSString *> *)endBinding;
+ (NSArray<NSString *> *)boundKeysForName:(NSString *)name;
+ (nullable NSString *)nameForKey:(NSString *)key;
+ (void)setBoolOverride:(BOOL)v forName:(NSString *)name;
+ (void)clearOverrideForName:(NSString *)name;
+ (nullable NSNumber *)overrideStateForName:(NSString *)name;

+ (BOOL)checkAndArmCrashGuard;
+ (void)markLaunchStable;

@end

NS_ASSUME_NONNULL_END
