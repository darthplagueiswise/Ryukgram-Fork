#import "RYGDeveloperTopicRuntimeBridgeViewController.h"
#import "RYGRuntimeBrowserV2ViewController.h"

@implementation RYGDeveloperTopicRuntimeBridgeViewController

- (void)pushRuntimeBrowserWithTitle:(NSString *)title query:(NSString *)query bulk:(BOOL)bulk {
    (void)bulk;
    RYGRuntimeBrowserV2ViewController *browser = [[RYGRuntimeBrowserV2ViewController alloc]
        initWithTitle:title ?: @"Runtime Browser"
         initialQuery:query ?: @""];
    if (self.navigationController) {
        [self.navigationController pushViewController:browser animated:YES];
        return;
    }
    UINavigationController *nav = [[UINavigationController alloc] initWithRootViewController:browser];
    nav.modalPresentationStyle = UIModalPresentationPageSheet;
    [self presentViewController:nav animated:YES completion:nil];
}

@end
