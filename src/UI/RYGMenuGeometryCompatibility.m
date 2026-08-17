#import "RYGLiquidGlass.h"
#import "../Settings/RYGSettingsViewController.h"
#import <objc/runtime.h>

static UIMenu *RYGMenuByRemovingSelectionGutter(UIMenu *menu) {
    if (!menu) return nil;
    NSMutableArray<UIMenuElement *> *children = [NSMutableArray arrayWithCapacity:menu.children.count];
    for (UIMenuElement *element in menu.children) {
        if ([element isKindOfClass:UIMenu.class]) {
            [children addObject:RYGMenuByRemovingSelectionGutter((UIMenu *)element)];
            continue;
        }
        if ([element isKindOfClass:UICommand.class]) {
            UICommand *source = (UICommand *)element;
            BOOL selected = source.state == UIMenuElementStateOn;
            NSString *title = selected ? [NSString stringWithFormat:@"✓  %@", source.title ?: @""] : (source.title ?: @"");
            UICommand *copy = [UICommand commandWithTitle:title
                                                   image:source.image
                                                  action:source.action
                                            propertyList:source.propertyList];
            // Do not set UIMenuElementStateOn here. That state asks UIKit to
            // reserve a dedicated leading selection column for every row,
            // which is the giant preselected gutter visible in the expanded
            // Liquid Glass menu. The checkmark above conveys selection without
            // changing the system menu geometry.
            copy.state = UIMenuElementStateOff;
            [children addObject:copy];
            continue;
        }
        [children addObject:element];
    }

    UIMenu *copy = [UIMenu menuWithTitle:menu.title ?: @""
                                   image:menu.image
                              identifier:menu.identifier
                                 options:menu.options
                                children:children];
    if (@available(iOS 17.0, *)) {
        // Automatic is UIKit's context-aware default on modern systems. Do not
        // force the full-width `large` geometry during a Liquid Glass morph.
        copy.preferredElementSize = UIMenuElementSizeAutomatic;
    }
    return copy;
}

@implementation RYGSettingsViewController (RYGMenuGeometryCompatibility)

- (void)ryg_nativeMenu_setupTableView {
    [self ryg_nativeMenu_setupTableView];
    // The former -30/-10 top inset moved rows underneath the glass navigation
    // title. A zero additional inset lets UIKit's safe-area/scroll-edge system
    // determine the correct content origin.
    self.tableView.contentInset = UIEdgeInsetsZero;
    self.tableView.scrollIndicatorInsets = UIEdgeInsetsZero;
}

- (UITableViewCell *)ryg_nativeMenu_tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath {
    UITableViewCell *cell = [self ryg_nativeMenu_tableView:tableView cellForRowAtIndexPath:indexPath];
    UIButton *oldButton = [cell.accessoryView isKindOfClass:UIButton.class] ? (UIButton *)cell.accessoryView : nil;
    if (!oldButton || !oldButton.showsMenuAsPrimaryAction || !oldButton.menu) return cell;

    // Recreate the accessory without copying the base implementation's fixed
    // 8pt configuration or its sizeToFit result. UIKit owns both the closed
    // Glass capsule and the expanded morph geometry.
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
