#import "SCIPopupChrome.h"
#import "../Settings/GlassUI/SCIAdaptiveGlass.h"

@implementation SCIPopupChrome

+ (UIColor *)backgroundColor {
    return SCIGlassBackdropColor();
}

+ (void)applyBackdropTo:(UIViewController *)vc {
    if (!vc.isViewLoaded) [vc loadViewIfNeeded];
    if (SCIIsIOS26OrNewer()) {
        SCIApplyGlassBackdropToViewController(vc);
        return;
    }
    UIColor *bg = [self backgroundColor];
    vc.view.backgroundColor = bg;
    NSMutableArray *stack = [NSMutableArray arrayWithObject:vc.view];
    while (stack.count) {
        UIView *v = stack.lastObject;
        [stack removeLastObject];
        if ([v isKindOfClass:[UITableView class]]) {
            SCIStyleTableViewForGlass((UITableView *)v);
            return;
        }
        if ([v isKindOfClass:[UICollectionView class]]) {
            SCIStyleCollectionViewForGlass((UICollectionView *)v);
            return;
        }
        for (UIView *sub in v.subviews) [stack addObject:sub];
    }
}

+ (UINavigationController *)wrap:(UIViewController *)content {
    UINavigationController *nav = [[UINavigationController alloc] initWithRootViewController:content];
    nav.modalPresentationStyle = SCIIsIOS26OrNewer() ? UIModalPresentationPageSheet : UIModalPresentationFullScreen;
    nav.view.backgroundColor = [self backgroundColor];
    nav.navigationBar.backgroundColor = UIColor.clearColor;
    nav.navigationBar.translucent = YES;
    [self applyBackdropTo:content];
    if (!content.navigationItem.leftBarButtonItem
        && !content.navigationItem.leftBarButtonItems.count) {
        UIBarButtonItem *close = [[UIBarButtonItem alloc] initWithImage:[UIImage systemImageNamed:@"xmark"]
                                                                   style:UIBarButtonItemStylePlain
                                                                  target:self
                                                                  action:@selector(closeTopMost:)];
        content.navigationItem.leftBarButtonItem = close;
    }
    return nav;
}

+ (void)presentVC:(UIViewController *)content from:(UIViewController *)presenter {
    if (!presenter) presenter = [self topMostController];
    if (!presenter || !content) return;
    UINavigationController *nav = [self wrap:content];
    [presenter presentViewController:nav animated:YES completion:nil];
}

#pragma mark - Helpers

+ (UIViewController *)topMostController {
    UIWindow *key = nil;
    for (UIScene *s in [UIApplication sharedApplication].connectedScenes) {
        if (![s isKindOfClass:[UIWindowScene class]]) continue;
        for (UIWindow *w in ((UIWindowScene *)s).windows) {
            if (w.isKeyWindow) { key = w; break; }
        }
        if (key) break;
    }
    if (!key) key = [UIApplication sharedApplication].windows.firstObject;
    UIViewController *top = key.rootViewController;
    while (top.presentedViewController) top = top.presentedViewController;
    return top;
}

+ (void)closeTopMost:(UIBarButtonItem *)sender {
    dispatch_async(dispatch_get_main_queue(), ^{
        UIViewController *top = [self topMostController];
        if (!top || top.isBeingDismissed) return;
        [top.view endEditing:YES];
        UINavigationController *nav = [top isKindOfClass:UINavigationController.class] ? (UINavigationController *)top : top.navigationController;
        if (nav && nav.viewControllers.count > 1) {
            [nav popViewControllerAnimated:YES];
            return;
        }
        UIViewController *target = nav ?: top;
        [target dismissViewControllerAnimated:YES completion:nil];
    });
}

@end
