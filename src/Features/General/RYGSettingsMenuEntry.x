#import "../../InstagramHeaders.h"
#import "../../Settings/RYGSettingsViewController.h"
#import <objc/runtime.h>
#import <substrate.h>
#import <mach-o/dyld.h>

// Hold the profile "more" button to open tweak settings. IG 432 moved
// IGBadgedNavigationButton into a Swift module, so both shortcuts are installed
// lazily as their defining images load instead of assuming ctor load order.
static void (*orig_badgedNav_didMoveToWindow)(UIView *, SEL);
static void (*orig_tabBar_didMoveToSuperview)(UIView *, SEL);
static const void *kRYGProfileSettingsLongPressKey = &kRYGProfileSettingsLongPressKey;
static const void *kRYGTabSettingsLongPressKey = &kRYGTabSettingsLongPressKey;
static BOOL gRYGProfileSettingsHookInstalled;
static BOOL gRYGTabSettingsHookInstalled;
static BOOL gRYGSettingsHookInstallScheduled;

static void ryg_badgedNavSettingsLongPress(UIView *self, SEL _cmd, UILongPressGestureRecognizer *sender) {
    if (sender.state != UIGestureRecognizerStateBegan) return;
    if (![self.accessibilityIdentifier isEqualToString:@"profile-more-button"]) return;
    [RYGUtils showSettingsVC:[self window]];
}

static void new_badgedNav_didMoveToWindow(UIView *self, SEL _cmd) {
    if (orig_badgedNav_didMoveToWindow) orig_badgedNav_didMoveToWindow(self, _cmd);

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
static void ryg_tabBarSettingsLongPress(UIView *self, SEL _cmd, UILongPressGestureRecognizer *sender) {
    if (sender.state != UIGestureRecognizerStateBegan) return;
    if (![RYGUtils getBoolPref:@"settings_shortcut"]) return;
    BOOL msgOnly = [RYGUtils getBoolPref:@"messages_only"];
    NSString *target = msgOnly ? @"direct-inbox-tab" : @"mainfeed-tab";
    if (![self.accessibilityIdentifier isEqualToString:target]) return;
    [RYGUtils showSettingsVC:[self window]];
}

static void new_tabBar_didMoveToSuperview(UIView *self, SEL _cmd) {
    if (orig_tabBar_didMoveToSuperview) orig_tabBar_didMoveToSuperview(self, _cmd);

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
            initWithTarget:self action:@selector(ryg_tabBarSettingsLongPress:)];
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

static BOOL RYGAddGestureActionIfNeeded(Class cls, SEL selector, IMP implementation) {
    if (!cls || !selector || !implementation) return NO;
    Method existing = class_getInstanceMethod(cls, selector);
    if (existing) return method_getImplementation(existing) == implementation;
    return class_addMethod(cls, selector, implementation, "v@:@");
}

static void RYGInstallSettingsLongPressHooks(void) {
    @synchronized(RYGSettingsViewController.class) {
        if (!gRYGProfileSettingsHookInstalled) {
            Class cls = NSClassFromString(@"_TtC19IGProfileNavigation24IGBadgedNavigationButton");
            if (!cls) cls = objc_getClass("IGBadgedNavigationButton");
            SEL lifecycle = @selector(didMoveToWindow);
            SEL action = @selector(ryg_badgedNavSettingsLongPress:);
            Method method = cls ? class_getInstanceMethod(cls, lifecycle) : NULL;
            if (method && RYGAddGestureActionIfNeeded(cls, action, (IMP)ryg_badgedNavSettingsLongPress)) {
                MSHookMessageEx(cls, lifecycle,
                                (IMP)new_badgedNav_didMoveToWindow,
                                (IMP *)&orig_badgedNav_didMoveToWindow);
                gRYGProfileSettingsHookInstalled = orig_badgedNav_didMoveToWindow != NULL;
            }
        }

        if (!gRYGTabSettingsHookInstalled) {
            Class cls = objc_getClass("IGTabBarButton");
            SEL lifecycle = @selector(didMoveToSuperview);
            SEL action = @selector(ryg_tabBarSettingsLongPress:);
            Method method = cls ? class_getInstanceMethod(cls, lifecycle) : NULL;
            if (method && RYGAddGestureActionIfNeeded(cls, action, (IMP)ryg_tabBarSettingsLongPress)) {
                MSHookMessageEx(cls, lifecycle,
                                (IMP)new_tabBar_didMoveToSuperview,
                                (IMP *)&orig_tabBar_didMoveToSuperview);
                gRYGTabSettingsHookInstalled = orig_tabBar_didMoveToSuperview != NULL;
            }
        }
    }
}

static void RYGScheduleSettingsLongPressHookInstall(void) {
    @synchronized(RYGSettingsViewController.class) {
        if (gRYGSettingsHookInstallScheduled ||
            (gRYGProfileSettingsHookInstalled && gRYGTabSettingsHookInstalled)) return;
        gRYGSettingsHookInstallScheduled = YES;
    }
    dispatch_async(dispatch_get_main_queue(), ^{
        @synchronized(RYGSettingsViewController.class) {
            gRYGSettingsHookInstallScheduled = NO;
        }
        RYGInstallSettingsLongPressHooks();
    });
}

static void RYGSettingsShortcutImageDidLoad(const struct mach_header *header, intptr_t slide) {
    (void)header;
    (void)slide;
    RYGScheduleSettingsLongPressHookInstall();
}

%ctor {
    RYGInstallSettingsLongPressHooks();
    _dyld_register_func_for_add_image(RYGSettingsShortcutImageDidLoad);
}
