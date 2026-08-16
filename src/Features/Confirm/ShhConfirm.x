#import "../../Utils.h"

%hook IGDirectThreadViewBottomSwipeFeatureController
- (void)setupBottomSwipeableScrollManagerIfNecessary {
    if ([RYGUtils getBoolPref:@"disable_disappearing_mode_swipe"]) return;
    %orig;
}
%end

%hook IGDirectDisappearingModeSwipeHandler
- (void)handleBottomSwipeableScrollUpdate {
    if ([RYGUtils getBoolPref:@"disable_disappearing_mode_swipe"]) return;
    if ([RYGUtils getBoolPref:@"shh_mode_confirm"])
        [RYGUtils showConfirmation:^(void) { %orig; } title:RYGLocalized(@"Confirm vanish mode")];
    else %orig;
}
- (id)getSwipeableScrollHintTextInfo {
    if ([RYGUtils getBoolPref:@"disable_disappearing_mode_swipe"]) return nil;
    return %orig;
}
%end

%hook IGDirectThreadViewController
- (void)messageListViewControllerDidToggleShhMode:(id)arg1 {
    if ([RYGUtils getBoolPref:@"shh_mode_confirm"])
        [RYGUtils showConfirmation:^(void) { %orig; } title:RYGLocalized(@"Confirm vanish mode")];
    else %orig;
}

- (void)messageListViewControllerDidReplayInShhMode:(id)arg1 {
    if ([RYGUtils getBoolPref:@"shh_mode_confirm"])
        [RYGUtils showConfirmation:^(void) { %orig; } title:RYGLocalized(@"Confirm vanish mode")];
    else %orig;
}
%end
