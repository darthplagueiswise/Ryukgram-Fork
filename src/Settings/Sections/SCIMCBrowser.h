// SCIMCBrowser.h — RyukGram-Fork
// Native-style MobileConfig override browser + store.
//
// Reads the id-name mapping and the current overrides from the app-group
// mobileconfig dir, lets you browse every config/param by NAME, toggle
// overrides, and exports them back to mc_overrides.json in the exact
// format Instagram consumes. Non-destructive: this is a NEW section, it
// does not replace your existing menus.
//
// Wiring (add ONE specifier to your Dev section — see SCISettings_Dev wiring
// snippet in the delivery notes):
//   [SCIMCBrowserListController class] pushes the browser below "Dev".

#import <Foundation/Foundation.h>
#import <Preferences/PSListController.h>

// App-group id used for the mobileconfig dir. Confirm/replace for your sideload.
// Runtime fallback scans known candidates, then the app's own Documents.
#ifndef SCI_APPGROUP
#define SCI_APPGROUP @"group.com.burbn.instagram"
#endif

NS_ASSUME_NONNULL_BEGIN

/// Loads/saves mc_overrides.json and reads names from id_name_mapping.json,
/// both in <AppGroup>/Documents/mobileconfig/. Format is preserved exactly:
///   {"<config>:":["<idx>: : <value>", ...], ..., "_qe_overrides_":[]}
@interface SCIMCOverrideStore : NSObject
+ (instancetype)shared;

@property (nonatomic, readonly) NSURL *mobileconfigDir;      // .../Documents/mobileconfig/
@property (nonatomic, readonly) NSArray<NSNumber *> *configIDs;  // sorted, from mapping

- (void)reload;                                             // re-read both files from disk
- (NSString *)nameForConfig:(NSInteger)cid;                // config name from mapping
- (NSDictionary<NSNumber *, NSString *> *)paramsForConfig:(NSInteger)cid; // idx -> param name
- (NSArray<NSNumber *> *)configIDsMatching:(nullable NSString *)query;

/// Write/overwrite id_name_mapping.json into the mobileconfig dir (the "correct
/// location" the app reads names from). Returns NO on failure.
- (BOOL)writeMappingData:(NSData *)data error:(NSError **)error;
/// Copy the tweak-bundled id_name_mapping.json into the mobileconfig dir,
/// overwriting. Used on first run and by the "Deploy mapping" button.
- (BOOL)deployBundledMappingOverwrite:(NSError **)error;

- (nullable NSString *)overrideValueForConfig:(NSInteger)cid param:(NSInteger)idx; // nil = not overridden
- (void)setOverrideValue:(nullable NSString *)value forConfig:(NSInteger)cid param:(NSInteger)idx; // nil clears
- (BOOL)save:(NSError **)error;                            // write mc_overrides.json (exact format)

/// Merge a preset (dict of "<config>:" -> ["<idx>: : <value>"]) into current overrides.
- (void)applyPreset:(NSDictionary<NSString *, NSArray<NSString *> *> *)preset;
/// The built-in internal/dogfood/dev/qe/igplus preset (the 55-config delta).
- (NSDictionary<NSString *, NSArray<NSString *> *> *)internalUnlockPreset;
@end

/// Root: search + presets + a row per config (name + number). Drills into detail.
@interface SCIMCBrowserListController : PSListController
@end

/// Per-config: one switch per param, bound to the store.
@interface SCIMCConfigDetailController : PSListController
@property (nonatomic, assign) NSInteger configID;
@end

NS_ASSUME_NONNULL_END
