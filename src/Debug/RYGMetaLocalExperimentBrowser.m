#import "RYGMetaLocalExperimentBrowser.h"
#import "../Utils.h"
#import <UIKit/UIKit.h>
#import <objc/runtime.h>
#import <objc/message.h>

@implementation RYGMetaLocalExperimentBrowser

+ (UIViewController *)topViewController {
    UIWindow *keyWindow = nil;
    for (UIScene *scene in UIApplication.sharedApplication.connectedScenes) {
        if (![scene isKindOfClass:UIWindowScene.class] ||
            scene.activationState != UISceneActivationStateForegroundActive) continue;
        for (UIWindow *window in ((UIWindowScene *)scene).windows) {
            if (window.isKeyWindow) { keyWindow = window; break; }
        }
        if (keyWindow) break;
    }
    UIViewController *top = keyWindow.rootViewController;
    while (top.presentedViewController && !top.presentedViewController.isBeingDismissed) {
        top = top.presentedViewController;
    }
    if ([top isKindOfClass:UINavigationController.class]) {
        return ((UINavigationController *)top).visibleViewController ?: top;
    }
    if ([top isKindOfClass:UITabBarController.class]) {
        return ((UITabBarController *)top).selectedViewController ?: top;
    }
    return top;
}

+ (NSArray *)experimentConfigs {
    Protocol *protocol = objc_getProtocol("MetaLocalExperimentConfigProtocol");
    if (!protocol) return @[];

    unsigned int count = 0;
    Class *classes = objc_copyClassList(&count);
    if (!classes) return @[];
    NSMutableArray *configs = [NSMutableArray array];
    for (unsigned int index = 0; index < count; index++) {
        Class cls = classes[index];
        if (!cls || !class_conformsToProtocol(cls, protocol)) continue;
        @try {
            id object = [[cls alloc] init];
            if (object) [configs addObject:object];
        } @catch (__unused id exception) {}
    }
    free(classes);
    return configs.copy;
}

+ (id)experimentGenerator {
    Class cls = NSClassFromString(@"LIDExperimentGenerator");
    SEL selector = NSSelectorFromString(@"initWithDeviceID:logger:");
    Method method = cls ? class_getInstanceMethod(cls, selector) : NULL;
    if (!method || method_getNumberOfArguments(method) != 4) return nil;
    @try {
        return ((id (*)(id, SEL, id, id))objc_msgSend)([cls alloc], selector, nil, nil);
    } @catch (__unused id exception) {
        return nil;
    }
}

+ (void)dismissMetaLocalExperiment:(__unused id)sender {
    dispatch_async(dispatch_get_main_queue(), ^{
        UIViewController *top = [self topViewController];
        UINavigationController *navigation = [top isKindOfClass:UINavigationController.class]
            ? (UINavigationController *)top : top.navigationController;
        UIViewController *target = navigation ?: top;
        if (target.presentingViewController && !target.isBeingDismissed) {
            [target dismissViewControllerAnimated:YES completion:nil];
        } else if (navigation.viewControllers.count > 1) {
            [navigation popViewControllerAnimated:YES];
        }
    });
}

+ (void)installCloseButton:(UIViewController *)controller {
    if (!controller) return;
    UIImage *image = [UIImage systemImageNamed:@"chevron.left"];
    controller.navigationItem.leftBarButtonItem = [[UIBarButtonItem alloc]
        initWithImage:image
                style:UIBarButtonItemStylePlain
               target:self
               action:@selector(dismissMetaLocalExperiment:)];
}

+ (void)presentFromCurrentViewController {
    dispatch_async(dispatch_get_main_queue(), ^{
        UIViewController *top = [self topViewController];
        if (!top) {
            [RYGUtils showErrorHUDWithDescription:@"No active presentation controller"];
            return;
        }

        Class listClass = NSClassFromString(@"MetaLocalExperimentListViewController");
        if (!listClass) {
            [RYGUtils showErrorHUDWithDescription:@"MetaLocalExperimentListViewController is not loaded"];
            return;
        }

        UIViewController *controller = nil;
        SEL initSelector = NSSelectorFromString(@"initWithExperimentConfigs:experimentGenerator:");
        @try {
            if ([listClass instancesRespondToSelector:initSelector]) {
                NSArray *configs = [self experimentConfigs];
                id generator = [self experimentGenerator];
                controller = ((id (*)(id, SEL, id, id))objc_msgSend)([listClass alloc], initSelector, configs, generator);
            } else {
                controller = [[listClass alloc] init];
            }
        } @catch (__unused id exception) {}

        if (![controller isKindOfClass:UIViewController.class]) {
            [RYGUtils showErrorHUDWithDescription:@"MetaLocalExperiment native controller could not be initialized"];
            return;
        }

        [self installCloseButton:controller];
        UINavigationController *navigation = [[UINavigationController alloc] initWithRootViewController:controller];
        navigation.modalPresentationStyle = UIModalPresentationFullScreen;
        navigation.navigationBar.prefersLargeTitles = NO;
        [top presentViewController:navigation animated:YES completion:nil];
    });
}

@end