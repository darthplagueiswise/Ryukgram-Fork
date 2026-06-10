#import "SCIGatingCatalog.h"

// Startup-safe bootstrap.
// Do not reinstall persisted runtime/direct hooks here. Stale persisted overrides can
// crash before the app UI appears. Runtime/Feature Gating hooks are installed when the
// user explicitly toggles/applies a getter. SCIGatingCatalog persists first, then tries
// the selected getter once during that explicit UI action.
%ctor {
    @autoreleasepool {
        [SCIGatingCatalog reconcileCrashGuardOnLaunch];
    }
}
