#pragma once
#import <UIKit/UIKit.h>

/// Settings submenu for IGDSLauncherConfig BOOL gating methods.
/// Confirmed via FLEX runtime dump: 102 methods, _launcherSet = IGMobileConfigUserSessionContextManager.
/// canSupportLauncher + isEligibleForLaunch are already hooked by the base launcher hook.
@interface SCIIGDSLauncherConfigViewController : UITableViewController
@end
