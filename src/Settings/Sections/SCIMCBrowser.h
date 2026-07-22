// SCIMCBrowser.h — RyukGram-Fork
// Native-style MobileConfig override browser + store.
//
// Reads id_name_mapping.json and mc_overrides.json from the app-group
// mobileconfig directory. Both raw and named override records are accepted:
//   "<config_id>:"             -> ["<param_id>: : <value>"]
//   "<config_id>:<config_name>" -> ["<param_id>: <param_name>: <value>"]
// Saving normalizes known configs/params to the richer named form used by
// internal backups, while preserving unknown names and _qe_overrides_.

#import <Foundation/Foundation.h>
#import <Preferences/PSListController.h>

#ifndef SCI_APPGROUP
#define SCI_APPGROUP @"group.com.burbn.instagram"
#endif

NS_ASSUME_NONNULL_BEGIN

@interface SCIMCOverrideStore : NSObject
+ (instancetype)shared;

@property (nonatomic, readonly) NSURL *mobileconfigDir;
@property (nonatomic, readonly) NSArray<NSNumber *> *configIDs;

- (void)reload;
- (NSString *)nameForConfig:(NSInteger)configID;
- (NSDictionary<NSNumber *, NSString *> *)paramsForConfig:(NSInteger)configID;
- (NSArray<NSNumber *> *)configIDsMatching:(nullable NSString *)query;

- (BOOL)writeMappingData:(NSData *)data error:(NSError **)error;
- (BOOL)deployBundledMappingOverwrite:(NSError **)error;

- (nullable NSString *)overrideValueForConfig:(NSInteger)configID
                                         param:(NSInteger)paramIndex;
- (void)setOverrideValue:(nullable NSString *)value
               forConfig:(NSInteger)configID
                   param:(NSInteger)paramIndex;
- (BOOL)save:(NSError **)error;

- (void)applyPreset:(NSDictionary<NSString *, NSArray<NSString *> *> *)preset;
- (NSDictionary<NSString *, NSArray<NSString *> *> *)internalUnlockPreset;
@end

@interface SCIMCBrowserListController : PSListController
@end

@interface SCIMCConfigDetailController : PSListController
@property (nonatomic, assign) NSInteger configID;
@end

NS_ASSUME_NONNULL_END
