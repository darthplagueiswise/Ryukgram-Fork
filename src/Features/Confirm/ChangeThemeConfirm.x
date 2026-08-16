#import "../../InstagramHeaders.h"
#import "../../Utils.h"

static void rygConfirmThemeChange(void (^apply)(void)) {
    if ([RYGUtils getBoolPref:@"change_direct_theme_confirm"]) {
        [RYGUtils showConfirmation:apply title:RYGLocalized(@"Confirm changing theme")];
    } else {
        apply();
    }
}

%hook IGDirectThreadThemePickerViewController
- (void)themeNewPickerSectionController:(id)a didSelectTheme:(id)b atIndex:(NSInteger)c {
    rygConfirmThemeChange(^{
        %orig;
    });
}
- (void)themePickerSectionController:(id)a didSelectThemeId:(id)b {
    rygConfirmThemeChange(^{
        %orig;
    });
}
%end

%hook IGDirectThreadThemeKitSwift.IGDirectThreadThemePreviewController
- (void)primaryButtonTapped {
    rygConfirmThemeChange(^{
        %orig;
    });
}
%end
