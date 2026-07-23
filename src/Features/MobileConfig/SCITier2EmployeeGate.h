#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

/// Enables or disables the Tier-2 MobileConfig gate. Disabling preserves the
/// installed message hook but delegates every evaluation to its original IMP.
FOUNDATION_EXPORT void SCITier2EmployeeGateSetEnabled(BOOL enabled);
FOUNDATION_EXPORT BOOL SCITier2EmployeeGateEnabled(void);
FOUNDATION_EXPORT BOOL SCITier2EmployeeGateInstalled(void);

NS_ASSUME_NONNULL_END
