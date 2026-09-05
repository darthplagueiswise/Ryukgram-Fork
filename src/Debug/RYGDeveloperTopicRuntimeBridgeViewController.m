#import "RYGDeveloperTopicRuntimeBridgeViewController.h"
#import "RYGPortedRuntimeBrowserViewController.h"

@implementation RYGDeveloperTopicRuntimeBridgeViewController

- (void)pushRuntimeBrowserWithTitle:(NSString *)title query:(NSString *)query bulk:(BOOL)bulk {
    RYGPortedRuntimeBrowserViewController *browser = [[RYGPortedRuntimeBrowserViewController alloc]
        initWithTitle:title ?: @"Runtime Browser"
         initialQuery:query ?: @""
allowsBulkVisibilityOverride:bulk];
    if (self.navigationController) {
        [self.navigationController pushViewController:browser animated:YES];
        return;
    }
    UINavigationController *nav = [[UINavigationController alloc] initWithRootViewController:browser];
    nav.modalPresentationStyle = UIModalPresentationPageSheet;
    [self presentViewController:nav animated:YES completion:nil];
}

@end
