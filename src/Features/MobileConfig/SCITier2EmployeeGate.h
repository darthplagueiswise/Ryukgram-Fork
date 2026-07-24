#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

/// Enables or disables the canonical Tier-2 `_ig_is_employee` gate. Disabling
/// preserves the installed ElleKit function hook and delegates to the untouched
/// shared evaluator with the exact employee descriptor.
FOUNDATION_EXPORT void SCITier2EmployeeGateSetEnabled(BOOL enabled);
FOUNDATION_EXPORT BOOL SCITier2EmployeeGateEnabled(void);
FOUNDATION_EXPORT BOOL SCITier2EmployeeGateInstalled(void);

NS_ASSUME_NONNULL_END
