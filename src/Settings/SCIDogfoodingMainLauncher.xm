#import <UIKit/UIKit.h>
#import <Foundation/Foundation.h>
#import <objc/runtime.h>
#import <objc/message.h>
#import <substrate.h>
#import "SCIDogfoodingMainLauncher.h"

static const NSInteger RYDogMainButtonTag = 0xD06F00D;
static const NSInteger RYDogNotesButtonTag = 0xD06F00E;
static __weak id RYDogCachedUserSession = nil;

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
    return [name isEqualToString:@"IGUserSession"] || [name hasSuffix:@"IGUserSession"] || [name hasSuffix:@"UserSession"];
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

static void RYDogRememberUserSession(id maybeSession, NSString *source) {
    id session = RYDogUserSessionFromObject(maybeSession);
    if (!session) return;
    RYDogCachedUserSession = session;
    NSLog(@"[RyukGram][Dogfood] cached IGUserSession from %@ -> %@ <%p>", source ?: @"?", RYDogClassName(session), session);
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

static id RYDogFindUserSession(UIViewController *presenter) {
    if (RYDogLooksLikeUserSession(RYDogCachedUserSession)) return RYDogCachedUserSession;

    NSMutableArray *roots = [NSMutableArray array];
    if (presenter) [roots addObject:presenter];
    if (presenter.navigationController) [roots addObject:presenter.navigationController];
    if (presenter.tabBarController) [roots addObject:presenter.tabBarController];
    if (presenter.view.window) [roots addObject:presenter.view.window];
    if (presenter.view.window.rootViewController) [roots addObject:presenter.view.window.rootViewController];

    UIViewController *root = RYDogRootViewController();
    if (root) [roots addObject:root];
    UIViewController *top = RYDogTopViewControllerFrom(root);
    if (top) [roots addObject:top];

    UIApplication *app = UIApplication.sharedApplication;
    if (app.delegate) [roots addObject:app.delegate];

    for (UIScene *scene in app.connectedScenes) {
        if (![scene isKindOfClass:UIWindowScene.class]) continue;
        for (UIWindow *window in ((UIWindowScene *)scene).windows) {
            [roots addObject:window];
            if (window.rootViewController) [roots addObject:window.rootViewController];
        }
    }

    for (id obj in roots) {
        id session = RYDogUserSessionFromObject(obj);
        if (session) {
            RYDogCachedUserSession = session;
            NSLog(@"[RyukGram][Dogfood] found IGUserSession from %@ -> %@ <%p>", RYDogClassName(obj), RYDogClassName(session), session);
            return session;
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
           [n containsString:@"context"];
}

static id RYDogFindLiveObjectNamed(UIViewController *presenter, NSString *className, NSMutableString *log) {
    NSMutableArray *queue = [NSMutableArray array];
    NSMutableSet *seen = [NSMutableSet set];

    void (^push)(id) = ^(id obj) {
        if (!obj || ![obj isKindOfClass:NSObject.class]) return;
        NSString *key = RYDogPtr(obj);
        if ([seen containsObject:key]) return;
        [seen addObject:key];
        [queue addObject:obj];
    };

    push(presenter);
    push(presenter.navigationController);
    push(presenter.tabBarController);
    push(presenter.view.window);
    push(presenter.view.window.rootViewController);
    push(RYDogRootViewController());
    push(UIApplication.sharedApplication.delegate);

    NSArray<NSString *> *selectors = @[
        @"config",
        @"settingsConfig",
        @"dogfoodingConfig",
        @"dogfoodingSettingsConfig",
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
    NSUInteger budget = 900;
    while (cursor < queue.count && budget-- > 0) {
        id obj = queue[cursor++];
        if ([RYDogClassName(obj) isEqualToString:className]) {
            if (log) [log appendFormat:@"FOUND %@ <%@>\n", RYDogClassName(obj), RYDogPtr(obj)];
            return obj;
        }

        for (NSString *selectorName in selectors) {
            push(RYDogSafeNoArg(obj, NSSelectorFromString(selectorName)));
        }

        unsigned int count = 0;
        Ivar *ivars = class_copyIvarList([obj class], &count);
        for (unsigned int i = 0; i < count; i++) {
            NSString *name = [NSString stringWithUTF8String:ivar_getName(ivars[i]) ?: ""];
            if (!RYDogUsefulIvarName(name)) continue;
            id child = RYDogSafeObjectIvar(obj, ivars[i]);
            if ([RYDogClassName(child) isEqualToString:className]) {
                if (log) [log appendFormat:@"%@ <%@> ivar %@ -> %@ <%@>\n", RYDogClassName(obj), RYDogPtr(obj), name, RYDogClassName(child), RYDogPtr(child)];
                if (ivars) free(ivars);
                return child;
            }
            push(child);
        }
        if (ivars) free(ivars);
    }

    if (log) [log appendFormat:@"No %@ found. visited=%lu\n", className, (unsigned long)seen.count];
    return nil;
}

static void RYDogShowAlert(UIViewController *presenter, NSString *title, NSString *message) {
    if (!presenter) return;
    dispatch_async(dispatch_get_main_queue(), ^{
        UIAlertController *alert = [UIAlertController alertControllerWithTitle:title ?: @"Dogfooding"
                                                                       message:message ?: @""
                                                                preferredStyle:UIAlertControllerStyleAlert];
        [alert addAction:[UIAlertAction actionWithTitle:@"OK" style:UIAlertActionStyleDefault handler:nil]];
        [presenter presentViewController:alert animated:YES completion:nil];
    });
}

static void RYDogOpenMainFrom(UIViewController *sourceVC) {
    UIViewController *presenter = RYDogTopViewControllerFrom(sourceVC ?: RYDogRootViewController());
    if (!presenter) {
        NSLog(@"[RyukGram][Dogfood] main abort: no presenter");
        return;
    }

    NSUserDefaults *ud = [NSUserDefaults standardUserDefaults];
    BOOL master = [ud boolForKey:@"igt_employee_master"];
    BOOL gate = [ud boolForKey:@"igt_employee_devoptions_gate"];
    if (!master && !gate) {
        RYDogShowAlert(presenter, @"Employee required", @"É necessário ativar 'Employee Master' ou 'Employee DevOptions gate' primeiro nas configurações experimentais e reiniciar o app.");
        return;
    }

    id userSession = RYDogFindUserSession(presenter);
    if (!userSession) {
        RYDogShowAlert(presenter, @"Dogfooding", @"Não achei IGUserSession vivo. Abre feed/perfil/configurações e tenta de novo.");
        return;
    }

    Class entryClass = RYDogResolveClass(@[
        @"IGDogfoodingSettings.IGDogfoodingSettings",
        @"_TtC20IGDogfoodingSettings20IGDogfoodingSettings"
    ]);
    SEL openSel = NSSelectorFromString(@"openWithConfig:onViewController:userSession:");
    if (!entryClass || !class_getClassMethod(entryClass, openSel)) {
        RYDogShowAlert(presenter, @"Dogfooding", @"Não achei o entrypoint principal do Dogfooding Settings.");
        return;
    }

    NSMutableString *configLog = [NSMutableString string];
    id config = RYDogFindLiveObjectNamed(presenter, @"IGDogfoodingSettingsConfig", configLog);
    if (!config) {
        NSString *msg = [NSString stringWithFormat:@"Não achei IGDogfoodingSettingsConfig vivo.\n\n%@\nSem alloc/init fake para evitar crash.", configLog];
        RYDogShowAlert(presenter, @"Dogfooding", msg);
        return;
    }

    NSLog(@"[RyukGram][Dogfood] opening main entrypoint config=%@ <%p> presenter=%@ <%p> userSession=%@ <%p>",
          RYDogClassName(config), config, RYDogClassName(presenter), presenter, RYDogClassName(userSession), userSession);

    @try {
        ((void (*)(id, SEL, id, id, id))objc_msgSend)((id)entryClass, openSel, config, presenter, userSession);
    } @catch (id e) {
        RYDogShowAlert(presenter, @"Dogfooding", [NSString stringWithFormat:@"openWithConfig exception: %@", e]);
    }
}

static void RYDogOpenDirectNotesFrom(UIViewController *sourceVC) {
    UIViewController *presenter = RYDogTopViewControllerFrom(sourceVC ?: RYDogRootViewController());
    if (!presenter) {
        NSLog(@"[RyukGram][Dogfood] notes abort: no presenter");
        return;
    }

    NSUserDefaults *ud = [NSUserDefaults standardUserDefaults];
    BOOL master = [ud boolForKey:@"igt_employee_master"];
    BOOL gate = [ud boolForKey:@"igt_employee_devoptions_gate"];
    if (!master && !gate) {
        RYDogShowAlert(presenter, @"Employee required", @"É necessário ativar 'Employee Master' ou 'Employee DevOptions gate' primeiro nas configurações experimentais e reiniciar o app.");
        return;
    }

    id userSession = RYDogFindUserSession(presenter);
    if (!userSession) {
        RYDogShowAlert(presenter, @"Dogfooding Notes", @"Não achei IGUserSession vivo. Abre feed/perfil/configurações e tenta de novo.");
        return;
    }

    Class notesClass = RYDogResolveClass(@[
        @"IGDirectNotesDogfoodingSettings.IGDirectNotesDogfoodingSettingsStaticFuncs"
    ]);
    SEL notesSel = NSSelectorFromString(@"notesDogfoodingSettingsOpenOnViewController:userSession:");
    if (!notesClass || !class_getClassMethod(notesClass, notesSel)) {
        RYDogShowAlert(presenter, @"Dogfooding Notes", @"Não achei o opener nativo do Direct Notes Dogfooding.");
        return;
    }

    NSLog(@"[RyukGram][Dogfood] opening Direct Notes native opener presenter=%@ <%p> userSession=%@ <%p>",
          RYDogClassName(presenter), presenter, RYDogClassName(userSession), userSession);

    @try {
        ((void (*)(id, SEL, id, id))objc_msgSend)((id)notesClass, notesSel, presenter, userSession);
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

static void (*origSCIExpFlagsViewDidAppear)(id self, SEL _cmd, BOOL animated);
static void hookSCIExpFlagsViewDidAppear(id self, SEL _cmd, BOOL animated) {
    if (origSCIExpFlagsViewDidAppear) origSCIExpFlagsViewDidAppear(self, _cmd, animated);
    if ([self isKindOfClass:UIViewController.class]) {
        RYDogRememberUserSession(self, @"SCIExpFlagsViewController");
        RYDogAttachButtons((UIViewController *)self);
    }
}

static id (*origIGMainAppUserSession)(id self, SEL _cmd);
static id hookIGMainAppUserSession(id self, SEL _cmd) {
    id ret = origIGMainAppUserSession ? origIGMainAppUserSession(self, _cmd) : nil;
    RYDogRememberUserSession(ret ?: self, @"IGMainAppViewController.userSession");
    return ret;
}

static id (*origIGTabBarUserSession)(id self, SEL _cmd);
static id hookIGTabBarUserSession(id self, SEL _cmd) {
    id ret = origIGTabBarUserSession ? origIGTabBarUserSession(self, _cmd) : nil;
    RYDogRememberUserSession(ret ?: self, @"IGTabBarController.userSession");
    return ret;
}

__attribute__((constructor))
static void RYDogNativeOpenersInit(void) {
    @autoreleasepool {
        Class expCls = NSClassFromString(@"SCIExpFlagsViewController");
        if (expCls) {
            MSHookMessageEx(expCls,
                            @selector(viewDidAppear:),
                            (IMP)hookSCIExpFlagsViewDidAppear,
                            (IMP *)&origSCIExpFlagsViewDidAppear);
        }

        Class mainAppCls = NSClassFromString(@"IGMainAppViewController");
        if (mainAppCls && class_getInstanceMethod(mainAppCls, @selector(userSession))) {
            MSHookMessageEx(mainAppCls,
                            @selector(userSession),
                            (IMP)hookIGMainAppUserSession,
                            (IMP *)&origIGMainAppUserSession);
        }

        Class tabCls = NSClassFromString(@"IGTabBarController");
        if (tabCls && class_getInstanceMethod(tabCls, @selector(userSession))) {
            MSHookMessageEx(tabCls,
                            @selector(userSession),
                            (IMP)hookIGTabBarUserSession,
                            (IMP *)&origIGTabBarUserSession);
        }

        NSLog(@"[RyukGram][Dogfood] bottom native openers loaded");
    }
}
