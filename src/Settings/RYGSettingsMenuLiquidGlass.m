#import "RYGSettingsViewController.h"
#import "RYGSetting.h"
#import "../UI/RYGLiquidGlass.h"
#import <objc/runtime.h>

/// Central presentation fix for every RYGTableCellMenu row.
///
/// The base table renderer builds the UIMenu correctly, but it historically
/// mixed the legacy UIButton title API with a later UIButtonConfiguration and
/// fixed contentInsets. On iOS 26 that can leave the selected value rendered as
/// loose blue text over the cell while also preventing the menu-source control
/// from using UIKit's native Liquid Glass capsule/morph geometry.
///
/// Keep the existing menu semantics/actions intact and normalize only the final
/// button presentation after the base renderer has populated its UIMenu.
@interface RYGSettingsViewController (RYGSettingsMenuLiquidGlass)
- (UIListContentConfiguration *)ryg_menuGlass_configuredContent:(UIListContentConfiguration *)config
                                                       forCell:(UITableViewCell *)cell
                                                           row:(RYGSetting *)row
                                                     indexPath:(NSIndexPath *)indexPath;
@end

@implementation RYGSettingsViewController (RYGSettingsMenuLiquidGlass)

- (UIListContentConfiguration *)ryg_menuGlass_configuredContent:(UIListContentConfiguration *)config
                                                       forCell:(UITableViewCell *)cell
                                                           row:(RYGSetting *)row
                                                     indexPath:(NSIndexPath *)indexPath {
    UIListContentConfiguration *result = [self ryg_menuGlass_configuredContent:config
                                                                       forCell:cell
                                                                           row:row
                                                                     indexPath:indexPath];
    if (row.type != RYGTableCellMenu || ![cell.accessoryView isKindOfClass:UIButton.class]) return result;

    UIButton *button = (UIButton *)cell.accessoryView;
    NSString *selectedTitle = [button titleForState:UIControlStateNormal];
    if (!selectedTitle.length) selectedTitle = button.configuration.title;
    if (!selectedTitle.length) selectedTitle = @"•••";

    // These RyukGram menus may contain nested choices for more than one pref.
    // Keep their existing command state model instead of asking UIButton to
    // reinterpret the whole tree as one single-selection pop-up.
    button.showsMenuAsPrimaryAction = YES;
    button.changesSelectionAsPrimaryAction = NO;
    button.enabled = !row.disabled;
    button.tintColor = UIColor.labelColor;
    button.contentHorizontalAlignment = UIControlContentHorizontalAlignmentCenter;

    UIButtonConfiguration *presentation = UIButtonConfiguration.borderedButtonConfiguration;
    presentation.title = selectedTitle;
    presentation.baseForegroundColor = UIColor.labelColor;
    presentation.image = [UIImage systemImageNamed:@"chevron.down"];
    presentation.imagePlacement = NSDirectionalRectEdgeTrailing;
    presentation.imagePadding = 5.0;
    // Intentionally do not set contentInsets. UIKit owns the source capsule's
    // geometry so iOS 26 can expand/morph it into the presented menu.
    button.configuration = presentation;

    RYGLiquidGlassConfigureButton(button, NO);
    [button sizeToFit];
    cell.accessoryView = button;
    cell.selectionStyle = UITableViewCellSelectionStyleNone;
    return result;
}

@end

__attribute__((constructor(65510))) static void RYGInstallSettingsMenuLiquidGlass(void) {
    @autoreleasepool {
        Class cls = RYGSettingsViewController.class;
        SEL originalSelector = NSSelectorFromString(@"configuredContent:forCell:row:indexPath:");
        SEL replacementSelector = @selector(ryg_menuGlass_configuredContent:forCell:row:indexPath:);
        Method original = class_getInstanceMethod(cls, originalSelector);
        Method replacement = class_getInstanceMethod(cls, replacementSelector);
        if (original && replacement) method_exchangeImplementations(original, replacement);
    }
}
