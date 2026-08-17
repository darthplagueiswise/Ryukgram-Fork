#import "RYGLiquidGlass.h"
#import "../Settings/RYGSettingsViewController.h"
#import <objc/runtime.h>

@implementation RYGSettingsViewController (RYGMenuGeometryCompatibility)

- (UITableViewCell *)ryg_nativeMenu_tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath {
    UITableViewCell *cell = [self ryg_nativeMenu_tableView:tableView cellForRowAtIndexPath:indexPath];
    UIButton *oldButton = [cell.accessoryView isKindOfClass:UIButton.class] ? (UIButton *)cell.accessoryView : nil;
    if (!oldButton || !oldButton.showsMenuAsPrimaryAction || !oldButton.menu) return cell;

    // Do not mutate contentInsets, bounds or intrinsic size for menu sources.
    // A fresh system button gives UIKit/iOS 26 complete ownership of both the
    // collapsed capsule and the expanded UIMenu morph geometry.
    UIButton *button = [UIButton buttonWithType:UIButtonTypeSystem];
    NSString *title = [oldButton titleForState:UIControlStateNormal] ?: @"•••";
    [button setTitle:title forState:UIControlStateNormal];
    button.menu = oldButton.menu;
    button.showsMenuAsPrimaryAction = YES;
    button.enabled = oldButton.enabled;
    button.accessibilityLabel = oldButton.accessibilityLabel;
    RYGLiquidGlassConfigureButton(button, NO);
    cell.accessoryView = button;
    return cell;
}

@end

__attribute__((constructor(125))) static void RYGInstallNativeMenuGeometryCompatibility(void) {
    Class cls = RYGSettingsViewController.class;
    SEL originalSelector = @selector(tableView:cellForRowAtIndexPath:);
    SEL replacementSelector = @selector(ryg_nativeMenu_tableView:cellForRowAtIndexPath:);
    Method original = class_getInstanceMethod(cls, originalSelector);
    Method replacement = class_getInstanceMethod(cls, replacementSelector);
    if (original && replacement) method_exchangeImplementations(original, replacement);
}
