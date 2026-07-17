#import <Foundation/Foundation.h>
NS_ASSUME_NONNULL_BEGIN
@interface SCIInternalSettingsApplier : NSObject
// Applies native internal/debug settings using the LIVE user session:
//   [session autofillInternalSettings] -> setDebugFooterEnabledWithEnabled:YES (+ Bloks),
//   IGLiquidGlassNavigationExperimentHelper.shared -> overrideIsEnabled: etc.
// Returns a short human-readable summary of what was applied.
+ (NSString *)applyNow;
// Performs one deterministic main-turn apply if sci_apply_internal_native is enabled.
+ (void)scheduleAutoApplyIfEnabled;
@end
NS_ASSUME_NONNULL_END
