#import <Foundation/Foundation.h>

typedef NS_ENUM(uint8_t, RYGMCType) {
    RYGMCTypeBool   = 1,
    RYGMCTypeInt    = 2,
    RYGMCTypeDouble = 3,
    RYGMCTypeString = 4,
};

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
@property (nonatomic, copy)   NSString *name;
@property (nonatomic, readonly) NSString *typeName;
@property (nonatomic, readonly) NSString *normalizedName;
@end

@interface RYGMCConfig : NSObject
@property (nonatomic, assign) unsigned int number;
@property (nonatomic, copy)   NSString *name;
@property (nonatomic, strong) NSArray<RYGMCParam *> *params;
@property (nonatomic, readonly) NSString *displayName;
@property (nonatomic, readonly) NSString *normalizedName;
@end

@interface RYGMobileConfig : NSObject

+ (instancetype)shared;

+ (NSString *)storageDirectory;
+ (void)mergeImportedStoreAtPath:(NSString *)importedDir;
+ (void)resetStore;
+ (void)reloadStoreFromDisk;

@property (nonatomic, readonly) BOOL ready;
@property (nonatomic, readonly) NSUInteger namedConfigCount;

- (void)prepare;
- (NSArray<RYGMCConfig *> *)allConfigs;
- (NSArray<RYGMCConfig *> *)configsMatching:(NSString *)query onlyOverridden:(BOOL)onlyOverridden;
- (NSArray<NSString *> *)paramNamesMatching:(NSString *)query inConfig:(RYGMCConfig *)c;
- (NSArray<RYGMCParam *> *)paramsMatching:(NSString *)query inConfig:(RYGMCConfig *)c;

- (id)liveValueFor:(RYGMCParam *)p;

- (RYGMCOverrideState)overrideStateFor:(RYGMCParam *)p;
- (id)overrideValueFor:(RYGMCParam *)p;
- (BOOL)setOverride:(id)value for:(RYGMCParam *)p;
- (void)clearOverrideFor:(RYGMCParam *)p;
- (NSUInteger)overrideCount;
- (void)resetAllOverrides;
- (void)resetOverridesForConfig:(RYGMCConfig *)config;

- (NSString *)callSiteFor:(RYGMCParam *)p;

- (NSString *)noteFor:(RYGMCParam *)p;
- (void)setNote:(NSString *)note for:(RYGMCParam *)p;

- (void)markLaunchStable;
- (BOOL)consumeCrashLoopFlag;
- (void)reapplyOverridesToNativeTable;

- (NSArray<NSDictionary *> *)exportEntries;
- (void)importEntries:(NSArray<NSDictionary *> *)entries
              replace:(BOOL)replace
              applied:(NSUInteger *)applied
              skipped:(NSUInteger *)skipped;

@end
