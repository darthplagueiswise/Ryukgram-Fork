// SCICSymbolStubBootstrap.x
// Relaunch-safe hard guard. The FBShared C-symbol browser is a runtime browser:
// it enumerates when the screen opens and attaches only for the current session.
// Never reinstall persisted C hooks at cold launch; old persisted toggles from
// previous builds caused startup crashes in MobileConfig/MCI paths.
#import "../../Utils.h"

%ctor {
    @autoreleasepool {
        if ([SCIUtils getBoolPref:@"sci_csym_stub_install_at_launch"]) {
            [SCIUtils setPref:@NO forKey:@"sci_csym_stub_install_at_launch"];
        }
    }
}
