#import "../../InstagramHeaders.h"
#import "../../Settings/SCISettingsViewController.h"
#import "../Dogfooding/SCIInstallOnce.h"
#import <objc/runtime.h>
#import <substrate.h>
#import <string.h>

// Instagram 376 configures IGTabBarButton after construction and inherits the
// UIView lifecycle methods. The former Logos hook could run before that class
// was ready, added duplicate recognizers after reparenting, and made every
// native gesture wait. Install after UIApplication is active and attach once.

static char kSCISettingsShortcutRecognizerKey;

@interface SCISettingsShortcutTarget : NSObject <UIGestureRecognizerDelegate>
+ (instancetype)shared;
- (void)handleLongPress:(UILongPressGestureRecognizer *)gesture;
@end

@implementation SCISettingsShortcutTarget
+ (instancetype)shared {
    static SCISettingsShortcutTarget *target = nil;
    static dispatch_once_t once;
    dispatch_once(&once, ^{ target = [SCISettingsShortcutTarget new]; });
    return target;
}
- (void)handleLongPress:(UILongPressGestureRecognizer *)gesture {
    if (gesture.state != UIGestureRecognizerStateBegan) return;
    [SCIUtils showSettingsVC:gesture.view.window];
}
- (BOOL)gestureRecognizer:(UIGestureRecognizer *)gesture
        shouldRecognizeSimultaneouslyWithGestureRecognizer:(UIGestureRecognizer *)other {
    (void)gesture; (void)other;
    return YES;
}
@end

static BOOL SCIIsSettingsShortcutView(UIView *view) {
    NSString *identifier = view.accessibilityIdentifier ?: @"";
    return [identifier isEqualToString:@"mainfeed-tab"] ||
           [identifier isEqualToString:@"direct-inbox-tab"] ||
           [identifier isEqualToString:@"profile-more-button"];
}

static void SCIAttachSettingsShortcut(UIView *view) {
    if (!view || !SCIIsSettingsShortcutView(view)) return;
    UILongPressGestureRecognizer *recognizer =
        objc_getAssociatedObject(view, &kSCISettingsShortcutRecognizerKey);
    BOOL enabled = [SCIUtils getBoolPref:@"settings_shortcut"];
    if (recognizer) {
        recognizer.enabled = enabled;
        return;
    }
    if (!enabled) return;

    recognizer = [[UILongPressGestureRecognizer alloc]
        initWithTarget:[SCISettingsShortcutTarget shared]
                action:@selector(handleLongPress:)];
    recognizer.minimumPressDuration = 0.35;
    recognizer.cancelsTouchesInView = YES;
    recognizer.delaysTouchesBegan = NO;
    recognizer.delegate = [SCISettingsShortcutTarget shared];

    // Only a competing long-press waits. Native taps and pans retain their
    // original recognition timing.
    for (UIGestureRecognizer *existing in view.gestureRecognizers.copy) {
        if ([existing isKindOfClass:UILongPressGestureRecognizer.class]) {
            [existing requireGestureRecognizerToFail:recognizer];
        }
    }
    [view addGestureRecognizer:recognizer];
    objc_setAssociatedObject(view, &kSCISettingsShortcutRecognizerKey,
                             recognizer, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
}

static void (*orig_tabConfigure)(id, SEL, id, id) = NULL;
static void SCI_tabConfigure(id self, SEL cmd, id config, id overlay) {
    if (orig_tabConfigure) orig_tabConfigure(self, cmd, config, overlay);
    SCIAttachSettingsShortcut(self);
}

static void (*orig_tabDidMoveToWindow)(id, SEL) = NULL;
static void SCI_tabDidMoveToWindow(id self, SEL cmd) {
    if (orig_tabDidMoveToWindow) orig_tabDidMoveToWindow(self, cmd);
    SCIAttachSettingsShortcut(self);
}

static void (*orig_tabSetAccessibilityIdentifier)(id, SEL, id) = NULL;
static void SCI_tabSetAccessibilityIdentifier(id self, SEL cmd, id identifier) {
    if (orig_tabSetAccessibilityIdentifier) {
        orig_tabSetAccessibilityIdentifier(self, cmd, identifier);
    }
    SCIAttachSettingsShortcut(self);
}

static void (*orig_badgedDidMoveToWindow)(id, SEL) = NULL;
static void SCI_badgedDidMoveToWindow(id self, SEL cmd) {
    if (orig_badgedDidMoveToWindow) orig_badgedDidMoveToWindow(self, cmd);
    SCIAttachSettingsShortcut(self);
}

static BOOL SCIObjectArgument(Method method, unsigned index) {
    if (!method || index >= method_getNumberOfArguments(method)) return NO;
    char type[32] = {0};
    method_getArgumentType(method, index, type, sizeof(type));
    const char *p = type;
    while (strchr("rnNoORV", *p)) p++;
    return *p == '@';
}

static BOOL SCIVoidReturn(Method method) {
    if (!method) return NO;
    char type[16] = {0};
    method_getReturnType(method, type, sizeof(type));
    return type[0] == 'v';
}

static void SCIInstallSettingsShortcutHooks(void) {
    Class tab = objc_getClass("IGTabBarButton");
    if (tab) {
        SEL configure = NSSelectorFromString(@"configureWithConfig:customOverlayView:");
        Method configureMethod = class_getInstanceMethod(tab, configure);
        if (!orig_tabConfigure && configureMethod &&
            SCIVoidReturn(configureMethod) &&
            method_getNumberOfArguments(configureMethod) == 4 &&
            SCIObjectArgument(configureMethod, 2) &&
            SCIObjectArgument(configureMethod, 3)) {
            MSHookMessageEx(tab, configure, (IMP)SCI_tabConfigure,
                            (IMP *)&orig_tabConfigure);
        }

        Method movedMethod = class_getInstanceMethod(tab, @selector(didMoveToWindow));
        if (!orig_tabDidMoveToWindow && movedMethod &&
            SCIVoidReturn(movedMethod) &&
            method_getNumberOfArguments(movedMethod) == 2) {
            MSHookMessageEx(tab, @selector(didMoveToWindow),
                            (IMP)SCI_tabDidMoveToWindow,
                            (IMP *)&orig_tabDidMoveToWindow);
        }

        SEL setIdentifier = @selector(setAccessibilityIdentifier:);
        Method identifierMethod = class_getInstanceMethod(tab, setIdentifier);
        if (!orig_tabSetAccessibilityIdentifier && identifierMethod &&
            SCIVoidReturn(identifierMethod) &&
            method_getNumberOfArguments(identifierMethod) == 3 &&
            SCIObjectArgument(identifierMethod, 2)) {
            MSHookMessageEx(tab, setIdentifier,
                            (IMP)SCI_tabSetAccessibilityIdentifier,
                            (IMP *)&orig_tabSetAccessibilityIdentifier);
        }
    }

    // Compatibility with the later Swift profile-navigation implementation.
    // It is absent from 376; home/inbox above is the verified path there.
    Class badged = NSClassFromString(
        @"_TtC19IGProfileNavigation24IGBadgedNavigationButton");
    if (!badged) badged = objc_getClass("IGBadgedNavigationButton");
    Method movedMethod = badged
        ? class_getInstanceMethod(badged, @selector(didMoveToWindow)) : NULL;
    if (badged && !orig_badgedDidMoveToWindow && movedMethod &&
        SCIVoidReturn(movedMethod) &&
        method_getNumberOfArguments(movedMethod) == 2) {
        MSHookMessageEx(badged, @selector(didMoveToWindow),
                        (IMP)SCI_badgedDidMoveToWindow,
                        (IMP *)&orig_badgedDidMoveToWindow);
    }
}

%ctor {
    @autoreleasepool {
        SCIInstallOnceOnActive(^{ SCIInstallSettingsShortcutHooks(); });
    }
}
