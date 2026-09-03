// Exp flag override store + observation logs.
// Override works only for MetaLocalExperiment (name-substring match on _experimentName).
// MC reads + scanned names are view-only — no reliable name→ID mapping.

#import <Foundation/Foundation.h>

typedef NS_ENUM(NSInteger, RYGExpFlagOverride) {
    RYGExpFlagOverrideOff   = 0,
    RYGExpFlagOverrideTrue  = 1,
    RYGExpFlagOverrideFalse = 2,
};

typedef NS_ENUM(NSInteger, RYGExpMCType) {
    RYGExpMCTypeBool,
    RYGExpMCTypeInt,
    RYGExpMCTypeDouble,
    RYGExpMCTypeString,
};

@interface RYGExpObservation : NSObject
@property (nonatomic, copy) NSString *experimentName;
@property (nonatomic, copy) NSString *lastGroup;
@property (nonatomic, assign) NSUInteger hitCount;
@end

@interface RYGExpMCObservation : NSObject
@property (nonatomic, assign) unsigned long long paramID;
@property (nonatomic, assign) RYGExpMCType type;
@property (nonatomic, copy) NSString *lastDefault;
@property (nonatomic, assign) NSUInteger hitCount;
@end

@interface RYGExpFlags : NSObject

// overrides (persisted)
+ (RYGExpFlagOverride)overrideForName:(NSString *)name;
+ (void)setOverride:(RYGExpFlagOverride)o forName:(NSString *)name;
+ (NSArray<NSString *> *)allOverriddenNames;
+ (void)resetAllOverrides;

// meta observations (live)
+ (void)recordExperimentName:(NSString *)name group:(NSString *)group;
+ (NSArray<RYGExpObservation *> *)allObservations;

// MC id observations (live, view-only)
+ (void)recordMCParamID:(unsigned long long)pid type:(RYGExpMCType)t defaultValue:(NSString *)def;
+ (NSArray<RYGExpMCObservation *> *)allMCObservations;

// binary-scanned names (bg, cb on main)
+ (void)scanExecutableNamesWithCompletion:(void (^)(NSArray<NSString *> *names))completion;

// crash-loop guard — 3 bad launches wipe overrides
+ (BOOL)checkAndHandleCrashLoop;
+ (void)markLaunchStable;

@end
