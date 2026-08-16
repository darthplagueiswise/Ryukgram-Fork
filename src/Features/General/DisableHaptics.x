#import "../../Utils.h"

static inline BOOL rygHapticsMuted(void) {
    return [RYGUtils getBoolPref:@"disable_haptics"];
}

%hook UIImpactFeedbackGenerator
- (void)impactOccurred {
    if (rygHapticsMuted()) return;
    %orig;
}
- (void)impactOccurredWithIntensity:(CGFloat)intensity {
    if (rygHapticsMuted()) return;
    %orig(intensity);
}
%end

%hook UINotificationFeedbackGenerator
- (void)notificationOccurred:(UINotificationFeedbackType)type {
    if (rygHapticsMuted()) return;
    %orig(type);
}
%end

%hook UISelectionFeedbackGenerator
- (void)selectionChanged {
    if (rygHapticsMuted()) return;
    %orig;
}
%end

%hook CHHapticEngine
- (BOOL)startAndReturnError:(NSError **)outError {
    return rygHapticsMuted() ? NO : %orig(outError);
}
%end
