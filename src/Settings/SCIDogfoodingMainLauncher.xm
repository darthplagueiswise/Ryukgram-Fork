#import <UIKit/UIKit.h>
#import <Foundation/Foundation.h>
#import <objc/runtime.h>
#import <objc/message.h>
#import <substrate.h>
#import "SCIDogfoodingMainLauncher.h"

static const NSInteger RYDogMainButtonTag = 0xD06F00D;
static const NSInteger RYDogNotesButtonTag = 0xD06F00E;

static __weak id RYDogCachedUserSession = nil;
static __weak id RYDogCachedConfig = nil;
static __weak UIViewController *RYDogCachedPresenter = nil;

static id (*origRYDogVCInitWithConfig)(id self, SEL _cmd, id config, id userSession);
static void (*origRYDogNativeOpenWithConfig)(id cls, SEL _cmd, id config, id viewController, id userSession);
static void (*origRYDogNativeNotesOpen)(id cls, SEL _cmd, id viewController, id userSession);
static void (*origSCIExpFlagsViewDidAppear)(id self, SEL _cmd, BOOL animated);
static id (*origIGMainAppUserSession)(id self, SEL _cmd);
static id (*origIGTabBarUserSession)(id self, SEL _cmd);

static NSString *RYDogClassName(id obj) {
    if (!obj) return @"nil";
    NSString *name = NSStringFromClass([obj class]);
    return name ?: @"?";
}

static NSString *RYDogPtr(id obj) {
    return obj ? [NSString stringWithFormat:@"%p", (__bridge void *)obj] : @"0x0";
}

static Class RYDogResolveClass(NSArray<NSString *> *names) {
    for (NSString *name in names) {
        if (!name.length) continue;
        Class cls = NSClassFromString(name);
        if (cls) return cls;
        cls = (Class)objc_getClass(name.UTF8String);
        if (cls) return cls;
    }
    return Nil;
}

static id RYDogSafeNoArg(id target, SEL sel) {
    if (!target || !sel || ![target respondsToSelector:sel]) return nil;
    @try {
        return ((id (*)(id, SEL))objc_msgSend)(target, sel);
    } @catch (__unused id e) {
        return nil;
    }
}

static id RYDogSafeObjectIvar(id target, Ivar ivar) {
    if (!target || !ivar) return nil;
    const char *type = ivar_getTypeEncoding(ivar);
    if (!type || type[0] != '@') return nil;
    @try {
        return object_getIvar(target, ivar);
    } @catch (__unused id e) {
        return nil;
    }
}

static BOOL RYDogLooksLikeUserSession(id obj) {
    if (!obj) return NO;
    NSString *name = RYDogClassName(obj);
    return [name isEqualToString:@"IGUserSession"] ||
           [name hasSuffix:@"IGUserSession"] ||
           [name hasSuffix:@"UserSession"];
}

static BOOL RYDogLooksLikeConfig(id obj) {
    if (!obj) return NO;
    NSString *name = RYDogClassName(obj);
    return [name isEqualToString:@"IGDogfoodingSettingsConfig"] ||
           [name hasSuffix:@"IGDogfoodingSettingsConfig"] ||
           [name containsString:@"DogfoodingSettingsConfig"];
}

static id RYDogUserSessionFromObject(id obj) {
    if (!obj) return nil;
    if (RYDogLooksLikeUserSession(obj)) return obj;

    NSArray<NSString *> *selectors = @[
        @"userSession",
        @"igUserSession",
        @"currentUserSession",
        @"activeUserSession",
        @"mainUserSession",
        @"loggedInUserSession"
    ];

    for (NSString *selectorName in selectors) {
        id value = RYDogSafeNoArg(obj, NSSelectorFromString(selectorName));
        if (RYDogLooksLikeUserSession(value)) return value;
    }

    const char *ivarNames[] = {
        "_userSession",
        "_igUserSession",
        "_currentUserSession",
        "_activeUserSession",
        "_mainUserSession",
        "_loggedInContext_userSession"
    };

    Class cls = [obj class];
    while (cls && cls != NSObject.class) {
        for (NSUInteger i = 0; i < sizeof(ivarNames) / sizeof(ivarNames[0]); i++) {
            Ivar ivar = class_getInstanceVariable(cls, ivarNames[i]);
            id value = RYDogSafeObjectIvar(obj, ivar);
            if (RYDogLooksLikeUserSession(value)) return value;
        }
        cls = class_getSuperclass(cls);
    }

    return nil;
}

static UIViewController *RYDogTopViewControllerFrom(UIViewController *vc) {
    UIViewController *cur = vc;
    BOOL changed = YES;

    while (cur && changed) {
        changed = NO;

        if ([cur isKindOfClass:UINavigationController.class]) {
            UIViewController *next = ((UINavigationController *)cur).visibleViewController ?: ((UINavigationController *)cur).topViewController;
            if (next && next != cur) {
                cur = next;
                changed = YES;
                continue;
            }
        }

        if ([cur isKindOfClass:UITabBarController.class]) {
            UIViewController *next = ((UITabBarController *)cur).selectedViewController;
            if (next && next != cur) {
                cur = next;
                changed = YES;
                continue;
            }
        }

        UIViewController *presented = cur.presentedViewController;
        if (presented && presented != cur) {
            cur = presented;
            changed = YES;
        }
    }

    return cur;
}

static UIViewController *RYDogRootViewController(void) {
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

static BOOL RYDogUsefulIvarName(NSString *name) {
    NSString *n = name.lowercaseString;
    return [n containsString:@"dogfood"] ||
           [n containsString:@"config"] ||
           [n containsString:@"settings"] ||
           [n containsString:@"coordinator"] ||
           [n containsString:@"session"] ||
           [n containsString:@"mainapp"] ||
           [n containsString:@"tabbar"] ||
           [n containsString:@"root"] ||
           [n containsString:@"delegate"] ||
           [n containsString:@"context"] ||
           [n containsString:@"manager"];
}

static void RYDogQueuePush(NSMutableArray *queue, NSMutableSet *seen, id obj) {
    if (!obj || ![obj isKindOfClass:NSObject.class]) return;
    NSString *key = RYDogPtr(obj);
    if ([seen containsObject:key]) return;
    [seen addObject:key];
    [queue addObject:obj];
}

static void RYDogSeedObjectGraph(NSMutableArray *queue, NSMutableSet *seen, UIViewController *presenter) {
    RYDogQueuePush(queue, seen, presenter);
    RYDogQueuePush(queue, seen, presenter.navigationController);
    RYDogQueuePush(queue, seen, presenter.tabBarController);
    RYDogQueuePush(queue, seen, presenter.view.window);
    RYDogQueuePush(queue, seen, presenter.view.window.rootViewController);
    RYDogQueuePush(queue, seen, RYDogRootViewController());
    RYDogQueuePush(queue, seen, UIApplication.sharedApplication.delegate);

    UIApplication *app = UIApplication.sharedApplication;
    for (UIScene *scene in app.connectedScenes) {
        if (![scene isKindOfClass:UIWindowScene.class]) continue;
        for (UIWindow *window in ((UIWindowScene *)scene).windows) {
            RYDogQueuePush(queue, seen, window);
            RYDogQueuePush(queue, seen, window.rootViewController);
        }
    }
}

static id RYDogFindObjectInGraph(UIViewController *presenter, BOOL (^match)(id obj), NSMutableString *log) {
    NSMutableArray *queue = [NSMutableArray array];
    NSMutableSet *seen = [NSMutableSet set];
    RYDogSeedObjectGraph(queue, seen, presenter);

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
        @"loggedInUserSession",
        @"mainAppViewController",
        @"rootViewController",
        @"selectedViewController",
        @"visibleViewController",
        @"topViewController",
        @"delegate",
        @"appCoordinator",
        @"sessionManager"
    ];

    NSUInteger cursor = 0;
    NSUInteger budget = 1200;
    while (cursor < queue.count && budget-- > 0) {
        id obj = queue[cursor++];
        if (match && match(obj)) {
            if (log) [log appendFormat:@"FOUND %@ <%@>\n", RYDogClassName(obj), RYDogPtr(obj)];
            return obj;
        }

        for (NSString *selectorName in selectors) {
            RYDogQueuePush(queue, seen, RYDogSafeNoArg(obj, NSSelectorFromString(selectorName)));
        }

        unsigned int count = 0;
        Ivar *ivars = class_copyIvarList([obj class], &count);
        for (unsigned int i = 0; i < count; i++) {
            NSString *name = [NSString stringWithUTF8String:ivar_getName(ivars[i]) ?: ""];
            if (!RYDogUsefulIvarName(name)) continue;
            RYDogQueuePush(queue, seen, RYDogSafeObjectIvar(obj, ivars[i]));
        }
        if (ivars) free(ivars);
    }

    if (log) [log appendFormat:@"No match found. visited=%lu\n", (unsigned long)seen.count];
    return nil;
}

static id RYDogFindUserSession(UIViewController *presenter) {
    if (RYDogLooksLikeUserSession(RYDogCachedUserSession)) return RYDogCachedUserSession;

    id session = RYDogFindObjectInGraph(presenter, ^BOOL(id obj) {
        return RYDogLooksLikeUserSession(obj) || RYDogLooksLikeUserSession(RYDogUserSessionFromObject(obj));
    }, nil);

    if (!RYDogLooksLikeUserSession(session)) session = RYDogUserSessionFromObject(session);
    if (RYDogLooksLikeUserSession(session)) {
        RYDogCachedUserSession = session;
        NSLog(@"[RyukGram][Dogfood] found IGUserSession %@ <%p>", RYDogClassName(session), session);
        return session;
    }

    return nil;
}

static id RYDogFindLiveConfig(UIViewController *presenter, NSMutableString *log) {
    if (RYDogLooksLikeConfig(RYDogCachedConfig)) return RYDogCachedConfig;

    id config = RYDogFindObjectInGraph(presenter, ^BOOL(id obj) {
        return RYDogLooksLikeConfig(obj);
    }, log);

    if (RYDogLooksLikeConfig(config)) {
        RYDogCachedConfig = config;
        return config;
    }

    return nil;
}

static void RYDogShowAlert(UIViewController *presenter, NSString *title, NSString *message) {
    dispatch_async(dispatch_get_main_queue(), ^{
        UIViewController *top = RYDogTopViewControllerFrom(presenter ?: RYDogRootViewController());
        if (!top) return;
        UIAlertController *alert = [UIAlertController alertControllerWithTitle:title ?: @"Dogfooding"
                                                                       message:message ?: @""
                                                                preferredStyle:UIAlertControllerStyleAlert];
        [alert addAction:[UIAlertAction actionWithTitle:@"OK" style:UIAlertActionStyleDefault handler:nil]];
        [top presentViewController:alert animated:YES completion:nil];
    });
}

static void RYDogCacheNativeOpenArguments(id config, id viewController, id userSession, NSString *source) {
    if (RYDogLooksLikeConfig(config)) RYDogCachedConfig = config;
    if ([viewController isKindOfClass:UIViewController.class]) RYDogCachedPresenter = viewController;
    if (RYDogLooksLikeUserSession(userSession)) RYDogCachedUserSession = userSession;
    NSLog(@"[RyukGram][Dogfood] cached %@ config=%@ <%p> presenter=%@ <%p> session=%@ <%p>",
          source ?: @"native args",
          RYDogClassName(config), config,
          RYDogClassName(viewController), viewController,
          RYDogClassName(userSession), userSession);
}

static id hookRYDogVCInitWithConfig(id self, SEL _cmd, id config, id userSession) {
    RYDogCacheNativeOpenArguments(config, self, userSession, @"-initWithConfig:userSession:");
    return origRYDogVCInitWithConfig ? origRYDogVCInitWithConfig(self, _cmd, config, userSession) : self;
}

static void hookRYDogNativeOpenWithConfig(id cls, SEL _cmd, id config, id viewController, id userSession) {
    RYDogCacheNativeOpenArguments(config, viewController, userSession, @"+openWithConfig:onViewController:userSession:");
    if (origRYDogNativeOpenWithConfig) {
        origRYDogNativeOpenWithConfig(cls, _cmd, config, viewController, userSession);
    }
}

static void hookRYDogNativeNotesOpen(id cls, SEL _cmd, id viewController, id userSession) {
    RYDogCacheNativeOpenArguments(nil, viewController, userSession, @"+notesDogfoodingSettingsOpenOnViewController:userSession:");
    if (origRYDogNativeNotesOpen) {
        origRYDogNativeNotesOpen(cls, _cmd, viewController, userSession);
    }
}

void RYDogOpenMainFrom(UIViewController *sourceVC) {
    UIViewController *presenter = RYDogTopViewControllerFrom(sourceVC ?: RYDogCachedPresenter ?: RYDogRootViewController());
    if (!presenter) {
        NSLog(@"[RyukGram][Dogfood] main abort: no presenter");
        return;
    }

    Class entryClass = RYDogResolveClass(@[
        @"IGDogfoodingSettings.IGDogfoodingSettings",
        @"_TtC20IGDogfoodingSettings20IGDogfoodingSettings"
    ]);
    SEL openSel = NSSelectorFromString(@"openWithConfig:onViewController:userSession:");
    Method openMethod = entryClass ? class_getClassMethod(entryClass, openSel) : NULL;
    if (!entryClass || !openMethod) {
        RYDogShowAlert(presenter, @"Dogfooding", @"Runtime não expôs +openWithConfig:onViewController:userSession: nesta build.");
        return;
    }

    id userSession = RYDogFindUserSession(presenter);
    if (!userSession) {
        RYDogShowAlert(presenter, @"Dogfooding", @"Selector encontrado, mas não achei IGUserSession vivo. Abre feed/perfil/configurações e tenta de novo.");
        return;
    }

    id config = RYDogLooksLikeConfig(RYDogCachedConfig) ? RYDogCachedConfig : nil;
    if (!config) {
        RYDogShowAlert(presenter,
                       @"Dogfooding",
                       @"Selector existe, mas nenhum IGDogfoodingSettingsConfig nativo foi observado ainda. Sem fallback: não cria config fake, não usa alloc/init sintético. O hook agora cacheia o config quando o próprio Instagram chamar +openWithConfig ou -initWithConfig.");
        return;
    }

    NSLog(@"[RyukGram][Dogfood] CALL selector +[%@ openWithConfig:onViewController:userSession:] config=%@ <%p> presenter=%@ <%p> userSession=%@ <%p>",
          NSStringFromClass(entryClass), RYDogClassName(config), config, RYDogClassName(presenter), presenter, RYDogClassName(userSession), userSession);

    @try {
        IMP imp = method_getImplementation(openMethod);
        ((void (*)(id, SEL, id, id, id))imp)((id)entryClass, openSel, config, presenter, userSession);
    } @catch (id e) {
        RYDogShowAlert(presenter, @"Dogfooding", [NSString stringWithFormat:@"openWithConfig exception: %@", e]);
    }
}

void RYDogOpenDirectNotesFrom(UIViewController *sourceVC) {
    UIViewController *presenter = RYDogTopViewControllerFrom(sourceVC ?: RYDogCachedPresenter ?: RYDogRootViewController());
    if (!presenter) {
        NSLog(@"[RyukGram][Dogfood] notes abort: no presenter");
        return;
    }

    Class notesClass = RYDogResolveClass(@[
        @"IGDirectNotesDogfoodingSettings.IGDirectNotesDogfoodingSettingsStaticFuncs",
        @"_TtC31IGDirectNotesDogfoodingSettings42IGDirectNotesDogfoodingSettingsStaticFuncs"
    ]);
    SEL notesSel = NSSelectorFromString(@"notesDogfoodingSettingsOpenOnViewController:userSession:");
    Method notesMethod = notesClass ? class_getClassMethod(notesClass, notesSel) : NULL;
    if (!notesClass || !notesMethod) {
        RYDogShowAlert(presenter, @"Dogfooding Notes", @"Runtime não expôs +notesDogfoodingSettingsOpenOnViewController:userSession: nesta build.");
        return;
    }

    id userSession = RYDogFindUserSession(presenter);
    if (!userSession) {
        RYDogShowAlert(presenter, @"Dogfooding Notes", @"Selector encontrado, mas não achei IGUserSession vivo.");
        return;
    }

    NSLog(@"[RyukGram][Dogfood] CALL selector +[%@ notesDogfoodingSettingsOpenOnViewController:userSession:] presenter=%@ <%p> userSession=%@ <%p>",
          NSStringFromClass(notesClass), RYDogClassName(presenter), presenter, RYDogClassName(userSession), userSession);

    @try {
        IMP imp = method_getImplementation(notesMethod);
        ((void (*)(id, SEL, id, id))imp)((id)notesClass, notesSel, presenter, userSession);
    } @catch (id e) {
        RYDogShowAlert(presenter, @"Dogfooding Notes", [NSString stringWithFormat:@"notes opener exception: %@", e]);
    }
}

@interface NSObject (RYDogNativeOpeners)
- (void)ryDogOpenMainButtonTapped:(id)sender;
- (void)ryDogOpenNotesButtonTapped:(id)sender;
@end

@implementation NSObject (RYDogNativeOpeners)
- (void)ryDogOpenMainButtonTapped:(id)sender {
    UIViewController *vc = [self isKindOfClass:UIViewController.class] ? (UIViewController *)self : nil;
    RYDogOpenMainFrom(vc);
}

- (void)ryDogOpenNotesButtonTapped:(id)sender {
    UIViewController *vc = [self isKindOfClass:UIViewController.class] ? (UIViewController *)self : nil;
    RYDogOpenDirectNotesFrom(vc);
}
@end

static UIButton *RYDogMakeButton(NSString *title, NSInteger tag, SEL action, UIViewController *target) {
    UIButton *button = [UIButton buttonWithType:UIButtonTypeSystem];
    button.tag = tag;
    button.translatesAutoresizingMaskIntoConstraints = NO;
    button.layer.cornerRadius = 18.0;
    button.clipsToBounds = YES;
    button.backgroundColor = [UIColor colorWithWhite:0.12 alpha:0.88];
    [button setTitle:title forState:UIControlStateNormal];
    [button setTitleColor:UIColor.whiteColor forState:UIControlStateNormal];
    button.titleLabel.font = [UIFont boldSystemFontOfSize:13.0];
    [button addTarget:target action:action forControlEvents:UIControlEventTouchUpInside];
    return button;
}

static void RYDogAttachButtons(UIViewController *vc) {
    if (!vc || !vc.view) return;

    UIView *existingMain = [vc.view viewWithTag:RYDogMainButtonTag];
    UIView *existingNotes = [vc.view viewWithTag:RYDogNotesButtonTag];
    if (existingMain && existingNotes) return;

    UILayoutGuide *guide = vc.view.safeAreaLayoutGuide;
    UIButton *notes = existingNotes ? (UIButton *)existingNotes : RYDogMakeButton(@"Notes", RYDogNotesButtonTag, @selector(ryDogOpenNotesButtonTapped:), vc);
    UIButton *main = existingMain ? (UIButton *)existingMain : RYDogMakeButton(@"Dogfood", RYDogMainButtonTag, @selector(ryDogOpenMainButtonTapped:), vc);

    if (!existingNotes) [vc.view addSubview:notes];
    if (!existingMain) [vc.view addSubview:main];

    [NSLayoutConstraint activateConstraints:@[
        [notes.leadingAnchor constraintEqualToAnchor:guide.leadingAnchor constant:14.0],
        [notes.bottomAnchor constraintEqualToAnchor:guide.bottomAnchor constant:-14.0],
        [notes.widthAnchor constraintGreaterThanOrEqualToConstant:84.0],
        [notes.heightAnchor constraintEqualToConstant:36.0],
        [main.trailingAnchor constraintEqualToAnchor:guide.trailingAnchor constant:-14.0],
        [main.bottomAnchor constraintEqualToAnchor:guide.bottomAnchor constant:-14.0],
        [main.widthAnchor constraintGreaterThanOrEqualToConstant:104.0],
        [main.heightAnchor constraintEqualToConstant:36.0]
    ]];
}

static void hookSCIExpFlagsViewDidAppear(id self, SEL _cmd, BOOL animated) {
    if (origSCIExpFlagsViewDidAppear) origSCIExpFlagsViewDidAppear(self, _cmd, animated);
    if ([self isKindOfClass:UIViewController.class]) {
        RYDogAttachButtons((UIViewController *)self);
    }
}

static id hookIGMainAppUserSession(id self, SEL _cmd) {
    id ret = origIGMainAppUserSession ? origIGMainAppUserSession(self, _cmd) : nil;
    if (RYDogLooksLikeUserSession(ret)) RYDogCachedUserSession = ret;
    return ret;
}

static id hookIGTabBarUserSession(id self, SEL _cmd) {
    id ret = origIGTabBarUserSession ? origIGTabBarUserSession(self, _cmd) : nil;
    if (RYDogLooksLikeUserSession(ret)) RYDogCachedUserSession = ret;
    return ret;
}

static void RYDogInstallRuntimeHooks(void) {
    Class expCls = NSClassFromString(@"SCIExpFlagsViewController");
    if (expCls && class_getInstanceMethod(expCls, @selector(viewDidAppear:)) && !origSCIExpFlagsViewDidAppear) {
        MSHookMessageEx(expCls,
                        @selector(viewDidAppear:),
                        (IMP)hookSCIExpFlagsViewDidAppear,
                        (IMP *)&origSCIExpFlagsViewDidAppear);
    }

    Class mainAppCls = NSClassFromString(@"IGMainAppViewController");
    if (mainAppCls && class_getInstanceMethod(mainAppCls, @selector(userSession)) && !origIGMainAppUserSession) {
        MSHookMessageEx(mainAppCls,
                        @selector(userSession),
                        (IMP)hookIGMainAppUserSession,
                        (IMP *)&origIGMainAppUserSession);
    }

    Class tabCls = NSClassFromString(@"IGTabBarController");
    if (tabCls && class_getInstanceMethod(tabCls, @selector(userSession)) && !origIGTabBarUserSession) {
        MSHookMessageEx(tabCls,
                        @selector(userSession),
                        (IMP)hookIGTabBarUserSession,
                        (IMP *)&origIGTabBarUserSession);
    }

    Class dogEntry = RYDogResolveClass(@[
        @"IGDogfoodingSettings.IGDogfoodingSettings",
        @"_TtC20IGDogfoodingSettings20IGDogfoodingSettings"
    ]);
    SEL openSel = NSSelectorFromString(@"openWithConfig:onViewController:userSession:");
    if (dogEntry && class_getClassMethod(dogEntry, openSel) && !origRYDogNativeOpenWithConfig) {
        MSHookMessageEx(object_getClass(dogEntry),
                        openSel,
                        (IMP)hookRYDogNativeOpenWithConfig,
                        (IMP *)&origRYDogNativeOpenWithConfig);
    }

    Class notesEntry = RYDogResolveClass(@[
        @"IGDirectNotesDogfoodingSettings.IGDirectNotesDogfoodingSettingsStaticFuncs",
        @"_TtC31IGDirectNotesDogfoodingSettings42IGDirectNotesDogfoodingSettingsStaticFuncs"
    ]);
    SEL notesSel = NSSelectorFromString(@"notesDogfoodingSettingsOpenOnViewController:userSession:");
    if (notesEntry && class_getClassMethod(notesEntry, notesSel) && !origRYDogNativeNotesOpen) {
        MSHookMessageEx(object_getClass(notesEntry),
                        notesSel,
                        (IMP)hookRYDogNativeNotesOpen,
                        (IMP *)&origRYDogNativeNotesOpen);
    }

    Class dogVC = RYDogResolveClass(@[
        @"IGDogfoodingSettings.IGDogfoodingSettingsViewController",
        @"_TtC20IGDogfoodingSettings34IGDogfoodingSettingsViewController"
    ]);
    SEL initSel = NSSelectorFromString(@"initWithConfig:userSession:");
    if (dogVC && class_getInstanceMethod(dogVC, initSel) && !origRYDogVCInitWithConfig) {
        MSHookMessageEx(dogVC,
                        initSel,
                        (IMP)hookRYDogVCInitWithConfig,
                        (IMP *)&origRYDogVCInitWithConfig);
    }
}

__attribute__((constructor))
static void RYDogNativeOpenersInit(void) {
    @autoreleasepool {
        RYDogInstallRuntimeHooks();
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.75 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
            RYDogInstallRuntimeHooks();
        });
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(2.0 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
            RYDogInstallRuntimeHooks();
        });
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(5.0 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
            RYDogInstallRuntimeHooks();
        });
        NSLog(@"[RyukGram][Dogfood] native selector hooks loaded");
    }
}
