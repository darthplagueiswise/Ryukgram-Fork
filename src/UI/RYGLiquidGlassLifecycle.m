#import "RYGLiquidGlass.h"
#import <objc/runtime.h>

static IMP RYGOriginalViewDidLayoutSubviews = NULL;
static const void *kRYGApplyingGlassKey = &kRYGApplyingGlassKey;

static void RYGLiquidGlassViewDidLayoutSubviews(UIViewController *controller, SEL selector) {
    if (RYGOriginalViewDidLayoutSubviews) {
        ((void (*)(id, SEL))RYGOriginalViewDidLayoutSubviews)(controller, selector);
    }
    if (!controller || !RYGIsOwnedViewController(controller)) return;
    if ([objc_getAssociatedObject(controller, kRYGApplyingGlassKey) boolValue]) return;

    objc_setAssociatedObject(controller, kRYGApplyingGlassKey, @YES, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    RYGLiquidGlassApplyToViewController(controller);
    objc_setAssociatedObject(controller, kRYGApplyingGlassKey, nil, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
}

__attribute__((constructor)) static void RYGLiquidGlassInstallLifecycle(void) {
    Class cls = UIViewController.class;
    Method method = class_getInstanceMethod(cls, @selector(viewDidLayoutSubviews));
    if (!method) return;
    IMP current = method_getImplementation(method);
    if (current == (IMP)RYGLiquidGlassViewDidLayoutSubviews) return;
    RYGOriginalViewDidLayoutSubviews = current;
    method_setImplementation(method, (IMP)RYGLiquidGlassViewDidLayoutSubviews);
}
