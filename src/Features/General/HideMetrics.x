#import "../../Utils.h"
#import <objc/runtime.h>
#import <substrate.h>

// Reels counts are written to the label via Swift -setText: (no hookable configure*),
// so we scope a global setText: hook to the two Sundial count buttons. The pref is
// cached behind a stale-flag and checked first — off costs one bool read per label.

static BOOL sHide = NO;
static BOOL sHideStale = YES;
static Class sCountBtn1, sCountBtn2;

static inline BOOL rygHide(void) {
    if (sHideStale) { sHide = [RYGUtils getBoolPref:@"hide_metrics"]; sHideStale = NO; }
    return sHide;
}

static inline BOOL rygIsCountLabel(UIView *label) {
    UIView *host = label.superview.superview;
    return host && ([host isKindOfClass:sCountBtn1] || [host isKindOfClass:sCountBtn2]);
}

static void (*orig_setText)(id, SEL, id);
static void new_setText(id self, SEL _cmd, id text) {
    if (rygHide() && rygIsCountLabel(self)) text = @"";
    orig_setText(self, _cmd, text);
}

%ctor {
    sCountBtn1 = NSClassFromString(@"_TtC18IGSundialViewerUFI27IGSundialUFIButtonWithCount");
    sCountBtn2 = NSClassFromString(@"_TtC18IGSundialViewerUFI24IGSundialLikeCountButton");
    MSHookMessageEx(UILabel.class, @selector(setText:), (IMP)new_setText, (IMP *)&orig_setText);
    [NSNotificationCenter.defaultCenter addObserverForName:NSUserDefaultsDidChangeNotification
                                                    object:nil queue:nil
                                                usingBlock:^(__unused NSNotification *n) { sHideStale = YES; }];
}

%hook IGUFIButtonWithCountsView
- (void)setCountString:(id)string showButton:(BOOL)showButton {
    return %orig(rygHide() ? @"" : string, showButton);
}
%end
