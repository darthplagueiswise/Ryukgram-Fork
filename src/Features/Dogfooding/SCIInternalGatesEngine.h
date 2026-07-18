// SCIInternalGatesEngine.h
// Single source for forcing the internal/employee/test-user/dogfooder gates and
// exposing their live state to the "Internal Gates" settings screen.
#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

// C entrypoint — called once from the %ctor in SCIInternalGates.x. Idempotent,
// gated by prefs (employeeInternalMaster || sci_force_easygating_internal ||
// sci_force_internal_apps_gate). Safe: only installs what is enabled.
void SCIInternalGatesInstall(void);

// Snapshot API for the settings UI (reads C statics; never touches the hot path).
@interface SCIInternalGatesEngine : NSObject
+ (BOOL)installed;
+ (BOOL)easyGatingForceActive;            // force flag latched at install
+ (BOOL)internalAppsForceActive;
+ (NSInteger)easyGatingEvaluatorsHooked;  // 0..3 (fishhook rc)
+ (BOOL)internalAppsHooked;
+ (NSInteger)gateCount;
// Per gate: @{ @"name": NSString, @"resolved": @(BOOL), @"forced": @(NSInteger) }
+ (NSArray<NSDictionary *> *)gateStatuses;
+ (NSInteger)totalForcedHits;
@end

NS_ASSUME_NONNULL_END
