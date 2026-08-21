#import "../../InstagramHeaders.h"
#import "../../Settings/RYGSettingsViewController.h"
#import <objc/runtime.h>
#import <substrate.h>

// Hold the profile "more" button to open tweak settings. IG 432 moved
// IGBadgedNavigationButton into a Swift module, so hook it at runtime.
static void (*orig_badgedNav_didMoveToWindow)(UIView *, SEL);
static const void *kRYGProfileSettingsLongPressKey = &kRYGProfileSettingsLongPressKey;
static const void *kRYGTabSettingsLongPressKey = &kRYGTabSettingsLongPressKey;

static void ryg_badgedNavSettingsLongPress(UIView *self, SEL _cmd, UILongPressGestureRecognizer *sender) {
    if (sender.state != UIGestureRecognizerStateBegan) return;
    if (![self.accessibilityIdentifier isEqualToString:@"profile-more-button"]) return;
    [RYGUtils showSettingsVC:[self window]];
}

static void new_badgedNav_didMoveToWindow(UIView *self, SEL _cmd) {
    orig_badgedNav_didMoveToWindow(self, _cmd);

    BOOL isProfileMoreButton =
        [self.accessibilityIdentifier isEqualToString:@"profile-more-button"];
    UILongPressGestureRecognizer *longPress =
        objc_getAssociatedObject(self, kRYGProfileSettingsLongPressKey);
    if (!isProfileMoreButton) {
        longPress.enabled = NO;
        return;
    }
    if (!longPress) {
        longPress = [[UILongPressGestureRecognizer alloc]
            initWithTarget:self action:@selector(ryg_badgedNavSettingsLongPress:)];
        longPress.minimumPressDuration = 0.45;
        longPress.cancelsTouchesInView = YES;
        [self addGestureRecognizer:longPress];
        objc_setAssociatedObject(self,
                                 kRYGProfileSettingsLongPressKey,
                                 longPress,
                                 OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    }
    longPress.enabled = YES;
}

// Hold the home tab (inbox tab in messages-only mode) to open tweak settings.
%hook IGTabBarButton
- (void)didMoveToSuperview {
    %orig;

    BOOL msgOnly = [RYGUtils getBoolPref:@"messages_only"];
    NSString *target = msgOnly ? @"direct-inbox-tab" : @"mainfeed-tab";
    BOOL isTarget = [self.accessibilityIdentifier isEqualToString:target];
    UILongPressGestureRecognizer *longPress =
        objc_getAssociatedObject(self, kRYGTabSettingsLongPressKey);
    if (!isTarget) {
        longPress.enabled = NO;
        return;
    }
    if (!longPress) {
        longPress = [[UILongPressGestureRecognizer alloc]
            initWithTarget:self action:@selector(ryg_settingsShortcutLongPress:)];
        longPress.minimumPressDuration = 0.3;
        longPress.cancelsTouchesInView = YES;
        [self addGestureRecognizer:longPress];
        objc_setAssociatedObject(self,
                                 kRYGTabSettingsLongPressKey,
                                 longPress,
                                 OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    }
    longPress.enabled = [RYGUtils getBoolPref:@"settings_shortcut"];
}
%new - (void)ryg_settingsShortcutLongPress:(UILongPressGestureRecognizer *)sender {
    if (sender.state != UIGestureRecognizerStateBegan) return;
    if (![RYGUtils getBoolPref:@"settings_shortcut"]) return;
    BOOL msgOnly = [RYGUtils getBoolPref:@"messages_only"];
    NSString *target = msgOnly ? @"direct-inbox-tab" : @"mainfeed-tab";
    if (![self.accessibilityIdentifier isEqualToString:target]) return;
    [RYGUtils showSettingsVC:[self window]];
}
%end

%ctor {
    %init;

    Class cls = NSClassFromString(@"_TtC19IGProfileNavigation24IGBadgedNavigationButton");
    if (!cls) cls = objc_getClass("IGBadgedNavigationButton");
    if (!cls) return;

    class_addMethod(cls, @selector(ryg_badgedNavSettingsLongPress:),
                    (IMP)ryg_badgedNavSettingsLongPress, "v@:@");
    MSHookMessageEx(cls, @selector(didMoveToWindow),
                    (IMP)new_badgedNav_didMoveToWindow,
                    (IMP *)&orig_badgedNav_didMoveToWindow);
}
