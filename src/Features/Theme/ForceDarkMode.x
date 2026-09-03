// Forces IG into the chosen appearance when `theme_force` is on.

#import "../../Utils.h"
#import "RYGTheme.h"

%group ForceAppearanceGroup

%hook UIWindow
- (void)makeKeyAndVisible {
    %orig;
    self.overrideUserInterfaceStyle = [RYGTheme overrideStyle];
}
- (void)becomeKeyWindow {
    %orig;
    self.overrideUserInterfaceStyle = [RYGTheme overrideStyle];
}
%end

%end

%ctor {
    [RYGTheme migrateLegacyPrefs];
    if ([RYGTheme shouldOverrideAppearance]) {
        %init(ForceAppearanceGroup);
    }
}
