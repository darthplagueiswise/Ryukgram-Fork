// Exp flag override store + observation logs.
// MetaLocalExperiment override works by name-substring match on _experimentName.
// IGMobileConfig override works by raw param ID and type.

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

@interface SCIExpFlags : NSObject

// MetaLocalExperiment overrides (persisted)
+ (SCIExpFlagOverride)overrideForName:(NSString *)name;
+ (void)setOverride:(SCIExpFlagOverride)o forName:(NSString *)name;
+ (NSArray<NSString *> *)allOverriddenNames;
+ (void)resetAllOverrides;

// IGMobileConfig overrides by raw param ID (persisted)
+ (nullable id)mcOverrideObjectForParamID:(unsigned long long)pid type:(SCIExpMCType)type;
+ (void)setMCOverrideObject:(nullable id)obj forParamID:(unsigned long long)pid type:(SCIExpMCType)type;
+ (NSArray<NSNumber *> *)allOverriddenMCParamIDs;
+ (void)resetAllMCOverrides;

// Meta observations (live)
+ (void)recordExperimentName:(NSString *)name group:(NSString *)group;
+ (NSArray<SCIExpObservation *> *)allObservations;

// MC id observations (live)
+ (void)recordMCParamID:(unsigned long long)pid type:(SCIExpMCType)t defaultValue:(NSString *)def;
+ (NSArray<SCIExpMCObservation *> *)allMCObservations;

// Binary-scanned names (bg, cb on main)
+ (void)scanExecutableNamesWithCompletion:(void (^)(NSArray<NSString *> *names))completion;

// Crash-loop guard — 3 bad launches wipe overrides
+ (BOOL)checkAndHandleCrashLoop;
+ (void)markLaunchStable;

@end
