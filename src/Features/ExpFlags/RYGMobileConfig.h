#import <Foundation/Foundation.h>

typedef uint8_t RYGMCType;
enum {
    RYGMCTypeUnknown = 0,
    RYGMCTypeBool    = 1,
    RYGMCTypeInt     = 2,
    // FBSharedFramework(3), UUID 4C4C44B7-5555-3144-A167-D73E543FBB32:
    // mobileconfig::typeFromParameter = (parameter >> 48) & 0x3f.
    // The current runtime discriminator is 1=bool, 2=int64, 3=string, 4=double.
    RYGMCTypeString  = 3,
    RYGMCTypeDouble  = 4,
};

static inline BOOL RYGMCTypeIsRuntimeValue(RYGMCType type) {
    return type == RYGMCTypeBool || type == RYGMCTypeInt ||
           type == RYGMCTypeString || type == RYGMCTypeDouble;
}

typedef NS_ENUM(NSInteger, RYGMCOverrideState) {
    RYGMCOverrideNone = 0,
    RYGMCOverrideSet,
};

@interface RYGMCParam : NSObject
@property (nonatomic, assign) unsigned long long paramID;
@property (nonatomic, assign) unsigned int ordinal;
@property (nonatomic, assign) unsigned int configNumber;
@property (nonatomic, assign) unsigned int paramIndex;
@property (nonatomic, assign) RYGMCType type;
@property (nonatomic, assign, getter=isRuntimeBacked) BOOL runtimeBacked;
@property (nonatomic, copy) NSString *name;
@property (nonatomic, readonly) NSString *typeName;
@end

@interface RYGMCConfig : NSObject
@property (nonatomic, assign) unsigned int number;
@property (nonatomic, copy) NSString *name;
@property (nonatomic, strong) NSArray<RYGMCParam *> *params;
@property (nonatomic, readonly) NSString *displayName;
@property (nonatomic, readonly) BOOL hasRuntimeBacking;
@end

@interface RYGMobileConfig : NSObject

+ (instancetype)shared;

// Compatibility facade consumed by RYGSettingsBackup. These methods operate
// only on RyukGram-owned MobileConfig state; they never restore the removed
// legacy MobileConfig controller/backend and never delete Instagram-owned data.
+ (NSString *)storageDirectory;
+ (void)resetStore;
+ (void)mergeImportedStoreAtPath:(NSString *)path;
+ (void)reloadStoreFromDisk;

@property (nonatomic, readonly) BOOL ready;
@property (nonatomic, readonly) NSUInteger namedConfigCount;

- (void)prepare;
- (void)reloadFromRuntime;
/// Runtime-backed rows discovered in the current FBSharedFramework.
- (NSArray<RYGMCConfig *> *)allConfigs;
/// Union used by Developer/MobileConfig browsers: runtime rows plus
/// id_name_mapping-only rows. Mapping-only rows are always read-only and have
/// type=RYGMCTypeUnknown / paramID=0.
- (NSArray<RYGMCConfig *> *)allConfigsIncludingMappingOnly;
- (NSArray<RYGMCConfig *> *)configsMatching:(NSString *)query onlyOverridden:(BOOL)onlyOverridden;
- (NSArray<NSString *> *)paramsMatching:(NSString *)query inConfig:(RYGMCConfig *)config;

/// Native-disk fallback used only before an explicit imported mapping exists.
- (void)mergeDiskNamesInto:(NSMutableDictionary *)catalog;

- (id)liveValueFor:(RYGMCParam *)param;

- (RYGMCOverrideState)overrideStateFor:(RYGMCParam *)param;
- (id)overrideValueFor:(RYGMCParam *)param;
- (BOOL)setOverride:(id)value for:(RYGMCParam *)param;
- (void)clearOverrideFor:(RYGMCParam *)param;
- (NSUInteger)overrideCount;
- (void)resetAllOverrides;
- (void)resetOverridesForConfig:(RYGMCConfig *)config;

- (NSString *)callSiteFor:(RYGMCParam *)param;

- (NSString *)noteFor:(RYGMCParam *)param;
- (void)setNote:(NSString *)note for:(RYGMCParam *)param;

- (void)markLaunchStable;
- (BOOL)consumeCrashLoopFlag;
- (void)reapplyOverridesToNativeTable;

@end
