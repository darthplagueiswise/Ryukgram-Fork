#import "SCIGatingCatalog.h"
#import "SCIBulkGatingPresets.h"

// Runs very early. If a previous on-demand gating evaluation armed the crash guard and
// the app then crashed (uncatchable fault inside a getter), the offending getter is moved
// to the blacklist here so it is never auto-evaluated again. No hooks, no class scan —
// just a defaults reconcile, so it is safe for a sideloaded build's launch path.
%ctor {
    @autoreleasepool {
        [SCIGatingCatalog reconcileCrashGuardOnLaunch];
        [SCIGatingCatalog installPersistedDirectOverrideHooks];
        // SCIPrefObserver para o seletor de wordmark: aplica imediatamente quando
        // o menu muda sem precisar de restart.
        [SCIBulkGatingPresets installWordmarkPrefObserver];
    }
}
