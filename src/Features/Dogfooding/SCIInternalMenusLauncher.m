#import "SCIInternalMenusLauncher.h"
#import "SCIDogfoodObjectRuntime.h"
#import <UIKit/UIKit.h>
#import <objc/message.h>
#import <objc/runtime.h>
#import <os/log.h>
#import <string.h>

#define MLOG(fmt,...) os_log(OS_LOG_DEFAULT,"[SCIGate] Menus " fmt,##__VA_ARGS__)

@implementation SCIInternalMenusLauncher

+ (UIViewController *)topVC { return [SCIDogfoodObjectRuntime topViewController]; }
+ (id)session               { return [SCIDogfoodObjectRuntime activeUserSession]; }

+ (UIViewController *)deepestPresentedFrom:(UIViewController *)controller {
    UIViewController *top = controller;
    while (top.presentedViewController) top = top.presentedViewController;
    if ([top isKindOfClass:UINavigationController.class]) {
        UIViewController *visible = ((UINavigationController *)top).visibleViewController;
        if (visible) top = visible;
    }
    return top;
}

+ (UIWindow *)activeIGWindow {
    Class igWindowClass = NSClassFromString(@"IGWindow");
    if (!igWindowClass) return nil;

    UIWindow *fallback = nil;
    for (UIScene *scene in UIApplication.sharedApplication.connectedScenes) {
        if (![scene isKindOfClass:UIWindowScene.class] ||
            scene.activationState != UISceneActivationStateForegroundActive) continue;
        for (UIWindow *window in ((UIWindowScene *)scene).windows) {
            if (![window isKindOfClass:igWindowClass]) continue;
            if (window.isKeyWindow) return window;
            if (!fallback) fallback = window;
        }
    }
    return fallback;
}

+ (BOOL)isNativeDebugController:(UIViewController *)controller {
    if (!controller) return NO;
    NSString *name = NSStringFromClass([controller class]) ?: @"";
    NSArray<NSString *> *needles = @[
        @"BugReport", @"RageShake", @"InternalSettings", @"Dogfooding"
    ];
    for (NSString *needle in needles) {
        if ([name rangeOfString:needle options:NSCaseInsensitiveSearch].location != NSNotFound) return YES;
    }
    return NO;
}

// Revalidated in Instagram(2): -showDebugMenu is only a thunk that calls
// -showDebugMenuWithEntryPoint:0. Entry point 3 is the native settings source.
// The native method also exits when user-opted-in-for-rageshake is explicitly
// false or when another modal is covering IGWindow. The old implementation hit
// those cases and still returned a false "opened" result.
+ (void)openInstagramDebugMenuWithCompletion:(void (^)(NSString *result))completion {
    void (^finish)(NSString *) = ^(NSString *result) {
        if (completion) completion(result ?: @"unknown result");
    };

    dispatch_async(dispatch_get_main_queue(), ^{
        UIWindow *target = [self activeIGWindow];
        if (!target) { finish(@"no active IGWindow"); return; }

        SEL selector = NSSelectorFromString(@"showDebugMenuWithEntryPoint:");
        Method method = class_getInstanceMethod([target class], selector);
        const char *encoding = method ? method_getTypeEncoding(method) : NULL;
        if (!method || !encoding || strcmp(encoding, "v24@0:8q16") != 0) {
            finish([NSString stringWithFormat:@"IGWindow debug-menu ABI unavailable or changed: %s",
                    encoding ?: "missing"]);
            return;
        }

        void (^invokeNative)(void) = ^{
            NSUserDefaults *defaults = NSUserDefaults.standardUserDefaults;
            NSString *optInKey = @"user-opted-in-for-rageshake";
            id previous = [defaults objectForKey:optInKey];
            BOOL hadPrevious = previous != nil;
            [defaults setObject:@YES forKey:optInKey];

            UIViewController *before = [self deepestPresentedFrom:target.rootViewController];
            @try {
                // 3 is the validated settings entry point.
                ((void (*)(id, SEL, NSInteger))objc_msgSend)(target, selector, 3);
            } @catch (id exception) {
                hadPrevious ? [defaults setObject:previous forKey:optInKey]
                            : [defaults removeObjectForKey:optInKey];
                finish([NSString stringWithFormat:@"showDebugMenuWithEntryPoint: threw: %@", exception]);
                return;
            }

            hadPrevious ? [defaults setObject:previous forKey:optInKey]
                        : [defaults removeObjectForKey:optInKey];

            // This is post-tap UI verification, not hook installation/retry.
            // The native path performs an async build-status callback before
            // presenting, so verify once after that callback can run.
            dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(1.5 * NSEC_PER_SEC)),
                           dispatch_get_main_queue(), ^{
                UIViewController *after = [self deepestPresentedFrom:target.rootViewController];
                BOOL changed = after && after != before;
                BOOL native = [self isNativeDebugController:after];
                if (changed || native) {
                    MLOG("Instagram debug menu presented via settings entry point");
                    finish([NSString stringWithFormat:@"presented %@", NSStringFromClass([after class])]);
                } else {
                    finish(@"Native debug-menu request ran, but no controller was presented. The client reached its build/account-status path and returned without UI; enable Employee / Internal, refresh GraphQL dogfood hooks, and inspect the snapshot for the server result.");
                }
            });
        };

        UIViewController *presented = target.rootViewController.presentedViewController;
        if (presented) {
            // The button lives inside RyukGram settings. IGWindow's native opener
            // refuses several paths while another controller is presented.
            [presented dismissViewControllerAnimated:YES completion:invokeNative];
        } else {
            invokeNative();
        }
    });
}

+ (NSString *)openInstagramDebugMenu {
    [self openInstagramDebugMenuWithCompletion:nil];
    return @"debug-menu request scheduled";
}

+ (UINavigationController *)navFor:(UIViewController *)vc {
    if (!vc) return nil;
    if ([vc isKindOfClass:UINavigationController.class]) return (UINavigationController *)vc;
    return vc.navigationController;
}

+ (NSString *)openDogfoodingNotesSettings {
    id session = [self session];
    if (!session) return @"no live user session (open after login)";

    Class C = NSClassFromString(@"IGDirectNotesDogfoodingSettingsStaticFuncs");
    if (!C) C = NSClassFromString(
        @"_TtC31IGDirectNotesDogfoodingSettings42IGDirectNotesDogfoodingSettingsStaticFuncs");
    if (!C) return @"IGDirectNotesDogfoodingSettingsStaticFuncs not found";

    SEL s = NSSelectorFromString(@"notesDogfoodingSettingsOpenOnViewController:userSession:");
    if (![C respondsToSelector:s]) return @"selector not found on class";

    UIViewController *top = [self topVC];
    UIViewController *presenter = [self navFor:top] ?: top;

    @try {
        ((void(*)(id,SEL,id,id))objc_msgSend)(C, s, presenter, session);
        MLOG("notes dogfooding opened");
        return @"opened Notes dogfooding settings";
    } @catch (id e) {
        return [NSString stringWithFormat:@"threw: %@", e];
    }
}

+ (NSString *)openDogfoodingSettingsVC {
    id session = [self session];
    if (!session) return @"no live user session (open after login)";

    Class cfgCls = NSClassFromString(@"IGDogfoodingSettingsConfig");
    if (!cfgCls) return @"IGDogfoodingSettingsConfig not found in this build";

    id config = nil;
    @try {
        config = [[cfgCls alloc] init];
    } @catch (id e) {
        return [NSString stringWithFormat:@"config init threw: %@", e];
    }
    if (!config) return @"IGDogfoodingSettingsConfig init returned nil";

    UIViewController *top = [self topVC];

    Class factory = NSClassFromString(@"_TtC20IGDogfoodingSettings20IGDogfoodingSettings");
    SEL openSel = NSSelectorFromString(@"openWithConfig:onViewController:userSession:");
    if (factory && [factory respondsToSelector:openSel]) {
        @try {
            ((void(*)(id,SEL,id,id,id))objc_msgSend)(factory, openSel, config, top, session);
            MLOG("dogfooding settings opened via factory");
            return @"opened native Dogfooding Settings";
        } @catch (__unused id e) {
            MLOG("factory threw, trying VC init fallback");
        }
    }

    Class vcCls = NSClassFromString(@"_TtC20IGDogfoodingSettings34IGDogfoodingSettingsViewController");
    SEL initSel = NSSelectorFromString(@"initWithConfig:userSession:");
    if (vcCls && [vcCls instancesRespondToSelector:initSel]) {
        @try {
            UIViewController *vc = ((id(*)(id,SEL,id,id))objc_msgSend)([vcCls alloc], initSel, config, session);
            if ([vc isKindOfClass:UIViewController.class]) {
                UINavigationController *nav = [[UINavigationController alloc] initWithRootViewController:vc];
                nav.modalPresentationStyle = UIModalPresentationPageSheet;
                if (!vc.navigationItem.leftBarButtonItem && [vc respondsToSelector:NSSelectorFromString(@"closeButtonTapped")]) {
                    vc.navigationItem.leftBarButtonItem =
                        [[UIBarButtonItem alloc] initWithBarButtonSystemItem:UIBarButtonSystemItemDone
                                                                      target:vc
                                                                      action:NSSelectorFromString(@"closeButtonTapped")];
                }
                [top presentViewController:nav animated:YES completion:nil];
                MLOG("dogfooding settings opened via VC init");
                return @"opened native Dogfooding Settings (VC)";
            }
        } @catch (id e) {
            return [NSString stringWithFormat:@"threw: %@", e];
        }
    }
    return @"IGDogfoodingSettings entrypoints not found in this build";
}

+ (NSString *)openInternalURLString:(NSString *)urlString {
    id session = [self session];
    if (!session) return @"no live user session";
    Class C = NSClassFromString(@"IGURLHandler");
    SEL s = NSSelectorFromString(
        @"openInternalURL:presentationConfig:controller:animated:userSession:annotation:");
    if (!C || ![C respondsToSelector:s]) return @"IGURLHandler.openInternalURL not found";
    UIViewController *top = [self topVC];
    NSURL *url = [NSURL URLWithString:urlString];
    @try {
        BOOL ok = ((BOOL(*)(id,SEL,id,id,id,BOOL,id,id))objc_msgSend)(
            C, s, url, nil, top, YES, session, nil);
        return ok ? [NSString stringWithFormat:@"opened: %@", urlString]
                  : @"openInternalURL returned NO";
    } @catch (id e) {
        return [NSString stringWithFormat:@"threw: %@", e];
    }
}

@end
