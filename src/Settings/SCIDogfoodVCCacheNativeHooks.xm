#import <UIKit/UIKit.h>
#import <Foundation/Foundation.h>
#import <objc/runtime.h>
#import <objc/message.h>
#import <substrate.h>

static __weak UIViewController *RYDogLiveVC = nil;
static __weak UIViewController *RYDogLivePresenter = nil;
static __weak id RYDogLiveConfig = nil;
static __weak id RYDogLiveUserSession = nil;

static id (*origRYDogLiveInitWithConfig)(id self, SEL _cmd, id config, id userSession);
static void (*origRYDogLiveViewDidLoad)(id self, SEL _cmd);
static void (*origRYDogLiveViewWillAppear)(id self, SEL _cmd, BOOL animated);
static void (*origRYDogLiveViewDidAppear)(id self, SEL _cmd, BOOL animated);
static void (*origRYDogLiveOpenWithConfig)(id cls, SEL _cmd, id config, id viewController, id userSession);
static void (*origRYDogLiveNotesOpen)(id cls, SEL _cmd, id viewController, id userSession);

static NSString *RYDogLiveClassName(id obj) {
    return obj ? (NSStringFromClass([obj class]) ?: @"?") : @"nil";
}

static BOOL RYDogLiveLooksLikeConfig(id obj) {
    if (!obj) return NO;
    NSString *name = RYDogLiveClassName(obj);
    return [name isEqualToString:@"IGDogfoodingSettingsConfig"] ||
           [name hasSuffix:@"IGDogfoodingSettingsConfig"] ||
           [name containsString:@"DogfoodingSettingsConfig"];
}

static BOOL RYDogLiveLooksLikeSession(id obj) {
    if (!obj) return NO;
    NSString *name = RYDogLiveClassName(obj);
    return [name isEqualToString:@"IGUserSession"] ||
           [name hasSuffix:@"IGUserSession"] ||
           [name hasSuffix:@"UserSession"];
}

static Class RYDogLiveResolveClass(NSArray<NSString *> *names) {
    for (NSString *name in names) {
        if (!name.length) continue;
        Class cls = NSClassFromString(name);
        if (cls) return cls;
        cls = (Class)objc_getClass(name.UTF8String);
        if (cls) return cls;
    }
    return Nil;
}

static id RYDogLiveSafeNoArg(id target, SEL sel) {
    if (!target || !sel || ![target respondsToSelector:sel]) return nil;
    @try { return ((id (*)(id, SEL))objc_msgSend)(target, sel); }
    @catch (__unused id e) { return nil; }
}

static id RYDogLiveSafeObjectIvar(id target, Ivar ivar) {
    if (!target || !ivar) return nil;
    const char *type = ivar_getTypeEncoding(ivar);
    if (!type || type[0] != '@') return nil;
    @try { return object_getIvar(target, ivar); }
    @catch (__unused id e) { return nil; }
}

static UIViewController *RYDogLiveRoot(void) {
    UIApplication *app = UIApplication.sharedApplication;
    for (UIScene *scene in app.connectedScenes) {
        if (![scene isKindOfClass:UIWindowScene.class]) continue;
        for (UIWindow *window in ((UIWindowScene *)scene).windows) {
            if (window.isKeyWindow && window.rootViewController) return window.rootViewController;
        }
    }
    for (UIScene *scene in app.connectedScenes) {
        if (![scene isKindOfClass:UIWindowScene.class]) continue;
        for (UIWindow *window in ((UIWindowScene *)scene).windows) {
            if (window.rootViewController) return window.rootViewController;
        }
    }
    return nil;
}

static UIViewController *RYDogLiveTop(UIViewController *vc) {
    UIViewController *cur = vc ?: RYDogLiveVC ?: RYDogLivePresenter ?: RYDogLiveRoot();
    BOOL changed = YES;
    while (cur && changed) {
        changed = NO;
        if ([cur isKindOfClass:UINavigationController.class]) {
            UIViewController *next = ((UINavigationController *)cur).visibleViewController ?: ((UINavigationController *)cur).topViewController;
            if (next && next != cur) { cur = next; changed = YES; continue; }
        }
        if ([cur isKindOfClass:UITabBarController.class]) {
            UIViewController *next = ((UITabBarController *)cur).selectedViewController;
            if (next && next != cur) { cur = next; changed = YES; continue; }
        }
        if (cur.presentedViewController && cur.presentedViewController != cur) {
            cur = cur.presentedViewController;
            changed = YES;
        }
    }
    return cur;
}

static void RYDogLiveAlert(UIViewController *presenter, NSString *title, NSString *message) {
    dispatch_async(dispatch_get_main_queue(), ^{
        UIViewController *top = RYDogLiveTop(presenter);
        if (!top) return;
        UIAlertController *alert = [UIAlertController alertControllerWithTitle:title ?: @"Dogfood"
                                                                       message:message ?: @""
                                                                preferredStyle:UIAlertControllerStyleAlert];
        [alert addAction:[UIAlertAction actionWithTitle:@"OK" style:UIAlertActionStyleDefault handler:nil]];
        [top presentViewController:alert animated:YES completion:nil];
    });
}

static void RYDogLiveCacheObject(id value, NSString *source, NSString *slot) {
    if (RYDogLiveLooksLikeConfig(value)) {
        RYDogLiveConfig = value;
        NSLog(@"[RyukGram][DogfoodLive] cached config from %@ %@ -> %@ <%p>", source, slot, RYDogLiveClassName(value), value);
    }
    if (RYDogLiveLooksLikeSession(value)) {
        RYDogLiveUserSession = value;
        NSLog(@"[RyukGram][DogfoodLive] cached userSession from %@ %@ -> %@ <%p>", source, slot, RYDogLiveClassName(value), value);
    }
}

static void RYDogLiveCacheFromVC(id vc, NSString *source) {
    if (!vc) return;
    if ([vc isKindOfClass:UIViewController.class]) {
        RYDogLiveVC = vc;
        RYDogLivePresenter = vc;
    }

    NSArray<NSString *> *selectors = @[
        @"config",
        @"settingsConfig",
        @"dogfoodingConfig",
        @"dogfoodingSettingsConfig",
        @"userSession",
        @"igUserSession",
        @"currentUserSession",
        @"activeUserSession",
        @"mainUserSession",
        @"loggedInUserSession"
    ];

    for (NSString *name in selectors) {
        id value = RYDogLiveSafeNoArg(vc, NSSelectorFromString(name));
        RYDogLiveCacheObject(value, source, name);
    }

    Class cls = [vc class];
    while (cls && cls != NSObject.class) {
        unsigned int count = 0;
        Ivar *ivars = class_copyIvarList(cls, &count);
        for (unsigned int i = 0; i < count; i++) {
            Ivar ivar = ivars[i];
            const char *rawName = ivar_getName(ivar) ?: "";
            NSString *name = [NSString stringWithUTF8String:rawName];
            NSString *lower = name.lowercaseString;
            if (![lower containsString:@"config"] && ![lower containsString:@"session"] && ![lower containsString:@"dogfood"] && ![lower containsString:@"settings"]) continue;
            id value = RYDogLiveSafeObjectIvar(vc, ivar);
            RYDogLiveCacheObject(value, source, name);
        }
        if (ivars) free(ivars);
        cls = class_getSuperclass(cls);
    }
}

static void RYDogLiveCacheNativeArgs(id config, id viewController, id userSession, NSString *source) {
    RYDogLiveCacheObject(config, source, @"argument.config");
    RYDogLiveCacheObject(userSession, source, @"argument.userSession");
    if ([viewController isKindOfClass:UIViewController.class]) {
        RYDogLivePresenter = viewController;
        RYDogLiveCacheFromVC(viewController, source);
    }
}

static id hookRYDogLiveInitWithConfig(id self, SEL _cmd, id config, id userSession) {
    id ret = origRYDogLiveInitWithConfig ? origRYDogLiveInitWithConfig(self, _cmd, config, userSession) : self;
    RYDogLiveCacheNativeArgs(config, ret ?: self, userSession, @"-initWithConfig:userSession:");
    RYDogLiveCacheFromVC(ret ?: self, @"-initWithConfig:userSession:");
    return ret;
}

static void hookRYDogLiveViewDidLoad(id self, SEL _cmd) {
    if (origRYDogLiveViewDidLoad) origRYDogLiveViewDidLoad(self, _cmd);
    RYDogLiveCacheFromVC(self, @"viewDidLoad");
}

static void hookRYDogLiveViewWillAppear(id self, SEL _cmd, BOOL animated) {
    if (origRYDogLiveViewWillAppear) origRYDogLiveViewWillAppear(self, _cmd, animated);
    RYDogLiveCacheFromVC(self, @"viewWillAppear:");
}

static void hookRYDogLiveViewDidAppear(id self, SEL _cmd, BOOL animated) {
    if (origRYDogLiveViewDidAppear) origRYDogLiveViewDidAppear(self, _cmd, animated);
    RYDogLiveCacheFromVC(self, @"viewDidAppear:");
}

static void hookRYDogLiveOpenWithConfig(id cls, SEL _cmd, id config, id viewController, id userSession) {
    RYDogLiveCacheNativeArgs(config, viewController, userSession, @"+openWithConfig:onViewController:userSession:");
    if (origRYDogLiveOpenWithConfig) origRYDogLiveOpenWithConfig(cls, _cmd, config, viewController, userSession);
}

static void hookRYDogLiveNotesOpen(id cls, SEL _cmd, id viewController, id userSession) {
    RYDogLiveCacheNativeArgs(nil, viewController, userSession, @"+notesDogfoodingSettingsOpenOnViewController:userSession:");
    if (origRYDogLiveNotesOpen) origRYDogLiveNotesOpen(cls, _cmd, viewController, userSession);
}

static void RYDogLiveCallMain(UIViewController *source) {
    UIViewController *presenter = RYDogLiveTop(source);
    if (RYDogLiveVC) RYDogLiveCacheFromVC(RYDogLiveVC, @"button.preflight.liveVC");
    if (presenter) RYDogLiveCacheFromVC(presenter, @"button.preflight.presenter");

    Class entry = RYDogLiveResolveClass(@[@"IGDogfoodingSettings.IGDogfoodingSettings", @"_TtC20IGDogfoodingSettings20IGDogfoodingSettings"]);
    SEL sel = NSSelectorFromString(@"openWithConfig:onViewController:userSession:");
    Method method = entry ? class_getClassMethod(entry, sel) : NULL;

    if (!method) { RYDogLiveAlert(presenter, @"Dogfood", @"Selector +openWithConfig:onViewController:userSession: não existe no runtime."); return; }
    if (!RYDogLiveLooksLikeConfig(RYDogLiveConfig)) { RYDogLiveAlert(presenter, @"Dogfood", @"IGDogfoodingSettingsViewController existe, mas nenhum IGDogfoodingSettingsConfig foi encontrado nos ivars/selectors dele. Sem fallback e sem config fake."); return; }
    if (!RYDogLiveLooksLikeSession(RYDogLiveUserSession)) { RYDogLiveAlert(presenter, @"Dogfood", @"IGDogfoodingSettingsViewController existe, mas nenhum IGUserSession foi encontrado nos ivars/selectors dele. Sem fallback."); return; }

    NSLog(@"[RyukGram][DogfoodLive] DIRECT CALL +openWithConfig config=%@ <%p> presenter=%@ <%p> session=%@ <%p>", RYDogLiveClassName(RYDogLiveConfig), RYDogLiveConfig, RYDogLiveClassName(presenter), presenter, RYDogLiveClassName(RYDogLiveUserSession), RYDogLiveUserSession);
    IMP imp = method_getImplementation(method);
    ((void (*)(id, SEL, id, id, id))imp)((id)entry, sel, RYDogLiveConfig, presenter, RYDogLiveUserSession);
}

static void RYDogLiveCallNotes(UIViewController *source) {
    UIViewController *presenter = RYDogLiveTop(source);
    if (RYDogLiveVC) RYDogLiveCacheFromVC(RYDogLiveVC, @"notes.preflight.liveVC");
    if (presenter) RYDogLiveCacheFromVC(presenter, @"notes.preflight.presenter");

    Class entry = RYDogLiveResolveClass(@[@"IGDirectNotesDogfoodingSettings.IGDirectNotesDogfoodingSettingsStaticFuncs", @"_TtC31IGDirectNotesDogfoodingSettings42IGDirectNotesDogfoodingSettingsStaticFuncs"]);
    SEL sel = NSSelectorFromString(@"notesDogfoodingSettingsOpenOnViewController:userSession:");
    Method method = entry ? class_getClassMethod(entry, sel) : NULL;

    if (!method) { RYDogLiveAlert(presenter, @"Dogfood Notes", @"Selector +notesDogfoodingSettingsOpenOnViewController:userSession: não existe no runtime."); return; }
    if (!RYDogLiveLooksLikeSession(RYDogLiveUserSession)) { RYDogLiveAlert(presenter, @"Dogfood Notes", @"Nenhum IGUserSession foi capturado do controller nativo. Sem fallback."); return; }

    IMP imp = method_getImplementation(method);
    ((void (*)(id, SEL, id, id))imp)((id)entry, sel, presenter, RYDogLiveUserSession);
}

static void RYDogLiveMainAction(id self, SEL _cmd, id sender) {
    UIViewController *vc = [self isKindOfClass:UIViewController.class] ? (UIViewController *)self : nil;
    RYDogLiveCallMain(vc);
}

static void RYDogLiveNotesAction(id self, SEL _cmd, id sender) {
    UIViewController *vc = [self isKindOfClass:UIViewController.class] ? (UIViewController *)self : nil;
    RYDogLiveCallNotes(vc);
}

static void RYDogLiveInstall(void) {
    Class dogVC = RYDogLiveResolveClass(@[@"IGDogfoodingSettings.IGDogfoodingSettingsViewController", @"_TtC20IGDogfoodingSettings34IGDogfoodingSettingsViewController"]);
    SEL initSel = NSSelectorFromString(@"initWithConfig:userSession:");
    if (dogVC && class_getInstanceMethod(dogVC, initSel) && !origRYDogLiveInitWithConfig) MSHookMessageEx(dogVC, initSel, (IMP)hookRYDogLiveInitWithConfig, (IMP *)&origRYDogLiveInitWithConfig);
    if (dogVC && class_getInstanceMethod(dogVC, @selector(viewDidLoad)) && !origRYDogLiveViewDidLoad) MSHookMessageEx(dogVC, @selector(viewDidLoad), (IMP)hookRYDogLiveViewDidLoad, (IMP *)&origRYDogLiveViewDidLoad);
    if (dogVC && class_getInstanceMethod(dogVC, @selector(viewWillAppear:)) && !origRYDogLiveViewWillAppear) MSHookMessageEx(dogVC, @selector(viewWillAppear:), (IMP)hookRYDogLiveViewWillAppear, (IMP *)&origRYDogLiveViewWillAppear);
    if (dogVC && class_getInstanceMethod(dogVC, @selector(viewDidAppear:)) && !origRYDogLiveViewDidAppear) MSHookMessageEx(dogVC, @selector(viewDidAppear:), (IMP)hookRYDogLiveViewDidAppear, (IMP *)&origRYDogLiveViewDidAppear);

    Class dogEntry = RYDogLiveResolveClass(@[@"IGDogfoodingSettings.IGDogfoodingSettings", @"_TtC20IGDogfoodingSettings20IGDogfoodingSettings"]);
    SEL openSel = NSSelectorFromString(@"openWithConfig:onViewController:userSession:");
    if (dogEntry && class_getClassMethod(dogEntry, openSel) && !origRYDogLiveOpenWithConfig) MSHookMessageEx(object_getClass(dogEntry), openSel, (IMP)hookRYDogLiveOpenWithConfig, (IMP *)&origRYDogLiveOpenWithConfig);

    Class notesEntry = RYDogLiveResolveClass(@[@"IGDirectNotesDogfoodingSettings.IGDirectNotesDogfoodingSettingsStaticFuncs", @"_TtC31IGDirectNotesDogfoodingSettings42IGDirectNotesDogfoodingSettingsStaticFuncs"]);
    SEL notesSel = NSSelectorFromString(@"notesDogfoodingSettingsOpenOnViewController:userSession:");
    if (notesEntry && class_getClassMethod(notesEntry, notesSel) && !origRYDogLiveNotesOpen) MSHookMessageEx(object_getClass(notesEntry), notesSel, (IMP)hookRYDogLiveNotesOpen, (IMP *)&origRYDogLiveNotesOpen);

    class_replaceMethod(NSObject.class, @selector(ryDogOpenMainButtonTapped:), (IMP)RYDogLiveMainAction, "v@:@");
    class_replaceMethod(NSObject.class, @selector(ryDogOpenNotesButtonTapped:), (IMP)RYDogLiveNotesAction, "v@:@");
}

__attribute__((constructor))
static void RYDogLiveNativeHooksInit(void) {
    @autoreleasepool {
        RYDogLiveInstall();
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.75 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{ RYDogLiveInstall(); });
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(2.0 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{ RYDogLiveInstall(); });
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(5.0 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{ RYDogLiveInstall(); });
        NSLog(@"[RyukGram][DogfoodLive] live VC native selector hooks loaded");
    }
}
