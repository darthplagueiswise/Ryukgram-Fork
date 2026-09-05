#import "RYGDeveloperTopicRuntimeBridgeViewController.h"
#import "RYGPortedRuntimeBrowserViewController.h"
#include <math.h>

static UIView *RYGDeveloperStableAccessoryView(UIView *accessory) {
    if (!accessory) return nil;
    if (![accessory isKindOfClass:UIButton.class]) return accessory;

    UIButton *button = (UIButton *)accessory;
    [button invalidateIntrinsicContentSize];
    CGSize intrinsic = button.intrinsicContentSize;
    CGFloat width = intrinsic.width > 0.0 ? MIN(132.0, MAX(92.0, ceil(intrinsic.width))) : 108.0;
    CGFloat height = intrinsic.height > 0.0 ? MAX(36.0, ceil(intrinsic.height)) : 36.0;

    // UITableViewCell.accessoryView is frame-driven. Keep the iOS 26 glass button
    // inside a concrete trailing box so its title can never paint over the
    // Developer row's title/subtitle while the UIMenu is collapsed.
    UIView *container = [[UIView alloc] initWithFrame:CGRectMake(0.0, 0.0, width, height)];
    container.backgroundColor = UIColor.clearColor;
    button.frame = container.bounds;
    button.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
    [container addSubview:button];
    return container;
}

@implementation RYGDeveloperTopicRuntimeBridgeViewController

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath {
    UITableViewCell *cell = [super tableView:tableView cellForRowAtIndexPath:indexPath];
    if ([cell.accessoryView isKindOfClass:UIButton.class]) {
        cell.accessoryView = RYGDeveloperStableAccessoryView(cell.accessoryView);
    }
    return cell;
}

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
