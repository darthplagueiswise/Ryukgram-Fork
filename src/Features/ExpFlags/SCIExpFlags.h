// Exp flag override store + observation logs.
// Override works only for MetaLocalExperiment (name-substring match on _experimentName).
// MC reads + scanned names are view-only — no reliable name→ID mapping.

#import <Foundation/Foundation.h>

typedef NS_ENUM(NSInteger, SCIExpFlagOverride) {
    SCIExpFlagOverrideOff   = 0,
    SCIExpFlagOverrideTrue  = 1,
    SCIExpFlagOverrideFalse = 2,
};

typedef NS_ENUM(NSInteger, SCIExpMCType) {
    SCIExpMCTypeBool,
    SCIExpMCTypeInt,
    SCIExpMCTypeDouble,
    SCIExpMCTypeString,
};

@interface SCIExpObservation : NSObject
@property (nonatomic, copy) NSString *experimentName;
@property (nonatomic, copy) NSString *lastGroup;
@property (nonatomic, assign) NSUInteger hitCount;
@end

@interface SCIExpMCObservation : NSObject
@property (nonatomic, assign) unsigned long long paramID;
@property (nonatomic, assign) SCIExpMCType type;
@property (nonatomic, copy) NSString *lastDefault;
@property (nonatomic, assign) NSUInteger hitCount;
@end

@interface SCIExpInternalUseObservation : NSObject
@property (nonatomic, copy) NSString *functionName;
@property (nonatomic, copy) NSString *specifierName;
@property (nonatomic, copy) NSString *callerDescription;
@property (nonatomic, assign) unsigned long long specifier;
@property (nonatomic, assign) BOOL defaultValue;
@property (nonatomic, assign) BOOL resultValue;
@property (nonatomic, assign) BOOL forcedValue;
@property (nonatomic, assign) NSUInteger hitCount;
@property (nonatomic, assign) NSUInteger lastSeenOrder;
@end

@interface SCIExpFlags : NSObject

+ (SCIExpFlagOverride)overrideForName:(NSString *)name;
+ (void)setOverride:(SCIExpFlagOverride)o forName:(NSString *)name;
+ (NSArray<NSString *> *)allOverriddenNames;
+ (void)resetAllOverrides;

+ (void)recordExperimentName:(NSString *)name group:(NSString *)group;
+ (NSArray<SCIExpObservation *> *)allObservations;

+ (void)recordMCParamID:(unsigned long long)pid type:(SCIExpMCType)t defaultValue:(NSString *)def;
+ (NSArray<SCIExpMCObservation *> *)allMCObservations;

+ (void)recordInternalUseSpecifier:(unsigned long long)specifier
                      functionName:(NSString *)functionName
                     specifierName:(NSString *)specifierName
                      defaultValue:(BOOL)defaultValue
                       resultValue:(BOOL)resultValue
                       forcedValue:(BOOL)forcedValue
                     callerAddress:(void *)callerAddress;
+ (NSArray<SCIExpInternalUseObservation *> *)allInternalUseObservations;
+ (NSArray<NSString *> *)allInternalUseObservationLines;

+ (void)scanExecutableNamesWithCompletion:(void (^)(NSArray<NSString *> *names))completion;

+ (BOOL)checkAndHandleCrashLoop;
+ (void)markLaunchStable;

@end

@interface SCIExpFlags (InternalUseOverrides)
+ (SCIExpFlagOverride)internalUseOverrideForSpecifier:(unsigned long long)specifier;
+ (void)setInternalUseOverride:(SCIExpFlagOverride)o forSpecifier:(unsigned long long)specifier;
+ (NSArray<NSNumber *> *)allOverriddenInternalUseSpecifiers;
+ (void)resetAllInternalUseOverrides;
@end
