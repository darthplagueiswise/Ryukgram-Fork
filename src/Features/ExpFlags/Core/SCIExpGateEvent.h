#import <Foundation/Foundation.h>

typedef NS_ENUM(NSUInteger, SCIExpGateKind) {
    SCIExpGateKindCBoolBroker = 0,
    SCIExpGateKindObjCBoolGetter,
    SCIExpGateKindInternalUseCFunction,
    SCIExpGateKindStartupConfigGetter,
    SCIExpGateKindUpdatePath,
    SCIExpGateKindOverridePath,
    SCIExpGateKindDogfoodUI,
};

typedef NS_ENUM(NSUInteger, SCIExpGateRisk) {
    SCIExpGateRiskSafeObserve = 0,
    SCIExpGateRiskSafeForce,
    SCIExpGateRiskNeedsAllowlist,
    SCIExpGateRiskObserveOnly,
    SCIExpGateRiskCrashLikely,
};

@interface SCIExpGateObservation : NSObject
@property (nonatomic, copy) NSString *gateSymbol;
@property (nonatomic, assign) SCIExpGateKind kind;
@property (nonatomic, assign) SCIExpGateRisk risk;
@property (nonatomic, assign) unsigned long long specifier;
@property (nonatomic, copy) NSString *resolvedName;
@property (nonatomic, copy) NSString *category;
@property (nonatomic, copy) NSString *contextClass;
@property (nonatomic, copy) NSString *selectorName;
@property (nonatomic, copy) NSString *callerDescription;
@property (nonatomic, assign) BOOL defaultValue;
@property (nonatomic, assign) BOOL originalValue;
@property (nonatomic, assign) BOOL finalValue;
@property (nonatomic, assign) BOOL shadowTrueValue;
@property (nonatomic, assign) BOOL wouldChangeIfTrue;
@property (nonatomic, assign) BOOL forcedValue;
@property (nonatomic, assign) NSUInteger hitCount;
@property (nonatomic, assign) NSUInteger lastSeenOrder;
@end

NSString *SCIExpGateKindName(SCIExpGateKind kind);
NSString *SCIExpGateRiskName(SCIExpGateRisk risk);
NSString *SCIExpGateCategoryForName(NSString *name, NSString *gateSymbol, NSString *callerDescription);
SCIExpGateRisk SCIExpGateRiskForSymbol(NSString *gateSymbol, SCIExpGateKind kind);
