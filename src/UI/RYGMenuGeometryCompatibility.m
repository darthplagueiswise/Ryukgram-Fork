#import "RYGLiquidGlass.h"
#import "../Settings/RYGSettingsViewController.h"
#import <objc/runtime.h>

static UIMenu *RYGMenuByRemovingSelectionGutter(UIMenu *menu) {
    if (!menu) return nil;
    for (UIMenuElement *element in menu.children) {
        if ([element isKindOfClass:UIMenu.class]) {
            RYGMenuByRemovingSelectionGutter((UIMenu *)element);
            continue;
        }
        // RYGSetting builds pickers with UIAction. The previous compatibility
        // layer only handled UICommand, so the actual selected UIAction still
        // requested UIKit's dedicated leading-state column. Clearing the state
        // in place preserves the action's native handler and lets the popover
        // use its intrinsic Liquid Glass geometry with no synthetic gutter.
        if ([element isKindOfClass:UIAction.class]) {
            ((UIAction *)element).state = UIMenuElementStateOff;
            continue;
        }
        if ([element isKindOfClass:UICommand.class]) {
            ((UICommand *)element).state = UIMenuElementStateOff;
        }
    }
    if (@available(iOS 17.0, *)) {
        menu.preferredElementSize = UIMenuElementSizeAutomatic;
    }
    return menu;
}

@implementation RYGSettingsViewController (RYGMenuGeometryCompatibility)

- (void)ryg_nativeMenu_setupTableView {
    [self ryg_nativeMenu_setupTableView];
    self.tableView.contentInset = UIEdgeInsetsZero;
    self.tableView.scrollIndicatorInsets = UIEdgeInsetsZero;
}

- (UITableViewCell *)ryg_nativeMenu_tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath {
    UITableViewCell *cell = [self ryg_nativeMenu_tableView:tableView cellForRowAtIndexPath:indexPath];
    UIButton *oldButton = [cell.accessoryView isKindOfClass:UIButton.class] ? (UIButton *)cell.accessoryView : nil;
    if (!oldButton || !oldButton.showsMenuAsPrimaryAction || !oldButton.menu) return cell;

    UIButton *button = [UIButton buttonWithType:UIButtonTypeSystem];
    NSString *title = [oldButton titleForState:UIControlStateNormal] ?: @"•••";
    [button setTitle:title forState:UIControlStateNormal];
    button.menu = RYGMenuByRemovingSelectionGutter(oldButton.menu);
    button.showsMenuAsPrimaryAction = YES;
    button.enabled = oldButton.enabled;
    button.accessibilityLabel = oldButton.accessibilityLabel;
    RYGLiquidGlassConfigureButton(button, NO);

    if (@available(iOS 26.0, *)) {
        UIButtonConfiguration *configuration = button.configuration;
        if (configuration) {
            [configuration setDefaultContentInsets];
            button.configuration = configuration;
        }
    }
    cell.accessoryView = button;
    return cell;
}

@end

static void RYGSwapInstanceMethod(Class cls, SEL originalSelector, SEL replacementSelector) {
    Method original = class_getInstanceMethod(cls, originalSelector);
    Method replacement = class_getInstanceMethod(cls, replacementSelector);
    if (original && replacement) method_exchangeImplementations(original, replacement);
}

__attribute__((constructor(125))) static void RYGInstallNativeMenuGeometryCompatibility(void) {
    Class cls = RYGSettingsViewController.class;
    RYGSwapInstanceMethod(cls,
                          NSSelectorFromString(@"setupTableView"),
                          @selector(ryg_nativeMenu_setupTableView));
    RYGSwapInstanceMethod(cls,
                          @selector(tableView:cellForRowAtIndexPath:),
                          @selector(ryg_nativeMenu_tableView:cellForRowAtIndexPath:));
}
