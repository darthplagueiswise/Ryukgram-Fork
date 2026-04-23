#import <UIKit/UIKit.h>
#import <objc/runtime.h>
#import <substrate.h>

static void (*orig_openNativeBrowser)(id, SEL) = NULL;

static void sciCloseNativeExperimentBrowser(id self, SEL _cmd) {
    if ([self respondsToSelector:@selector(dismissViewControllerAnimated:completion:)]) {
        ((void (*)(id, SEL, BOOL, id))objc_msgSend)(self, @selector(dismissViewControllerAnimated:completion:), YES, nil);
    }
}

static void new_openNativeBrowser(id self, SEL _cmd) {
    if (orig_openNativeBrowser) orig_openNativeBrowser(self, _cmd);

    UIViewController *presented = nil;
    @try { presented = [self valueForKey:@"presentedViewController"]; } @catch (__unused id e) {}
    UINavigationController *nav = [presented isKindOfClass:[UINavigationController class]] ? (UINavigationController *)presented : nil;
    UIViewController *root = nav.viewControllers.firstObject;
    if (!root) return;

    UIBarButtonItem *back = [[UIBarButtonItem alloc]
        initWithImage:[UIImage systemImageNamed:@"chevron.backward"]
                style:UIBarButtonItemStylePlain
               target:self
               action:@selector(sci_closeNativeExperimentBrowser)];
    back.accessibilityLabel = @"Back";
    root.navigationItem.leftBarButtonItem = back;
}

__attribute__((constructor))
static void SCIInstallExpNativeBackButton(void) {
    Class cls = NSClassFromString(@"SCIExpFlagsViewController");
    if (!cls) return;

    SEL closeSel = NSSelectorFromString(@"sci_closeNativeExperimentBrowser");
    class_addMethod(cls, closeSel, (IMP)sciCloseNativeExperimentBrowser, "v@:");

    SEL openSel = NSSelectorFromString(@"openNativeBrowser");
    if (class_getInstanceMethod(cls, openSel)) {
        MSHookMessageEx(cls, openSel, (IMP)new_openNativeBrowser, (IMP *)&orig_openNativeBrowser);
    }
}
