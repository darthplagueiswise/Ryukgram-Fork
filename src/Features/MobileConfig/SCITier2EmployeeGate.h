#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

/// Enables or disables the canonical Tier-2 `_ig_is_employee` gate. The
/// installed hook is ElleKit-only; disabling delegates to ElleKit's preserved
/// original thunk trampoline without touching combined employee/test gates.
FOUNDATION_EXPORT void SCITier2EmployeeGateSetEnabled(BOOL enabled);
FOUNDATION_EXPORT BOOL SCITier2EmployeeGateEnabled(void);
FOUNDATION_EXPORT BOOL SCITier2EmployeeGateInstalled(void);

NS_ASSUME_NONNULL_END
