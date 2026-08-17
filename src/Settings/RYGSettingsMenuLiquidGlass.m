#import "RYGSettingsViewController.h"
#import "RYGSetting.h"
#import "../UI/RYGLiquidGlass.h"
#import <objc/runtime.h>

/// Central presentation fix for every RYGTableCellMenu row.
///
/// menuForButton: resolves the selected command first. The base cell renderer
/// then used to reapply fixed contentInsets after that menu-source button had
/// already been configured, which constrained the iOS 26/27 Liquid Glass source
/// capsule and could leave its selected title drawing over the cell text.
/// Normalize the FINAL button configuration here, after the base renderer, so
/// every expandable settings menu gets the same system-owned geometry.
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

    // Several RyukGram menu trees contain independent nested preferences. Do
    // not make UIButton reinterpret the entire tree as one single-selection
    // pop-up; command states/defaults remain the source of truth.
    button.showsMenuAsPrimaryAction = YES;
    button.changesSelectionAsPrimaryAction = NO;
    button.enabled = !row.disabled;
    button.tintColor = UIColor.labelColor;
    button.contentHorizontalAlignment = UIControlContentHorizontalAlignmentCenter;

    UIButtonConfiguration *presentation = nil;
    if (@available(iOS 26.0, *)) {
        if (RYGLiquidGlassIsAvailable()) {
            presentation = UIButtonConfiguration.glassButtonConfiguration;
        }
    }
    if (!presentation) presentation = UIButtonConfiguration.borderedButtonConfiguration;

    presentation.title = selectedTitle;
    presentation.baseForegroundColor = UIColor.labelColor;
    presentation.image = [UIImage systemImageNamed:@"chevron.down"];
    presentation.imagePlacement = NSDirectionalRectEdgeTrailing;
    presentation.imagePadding = 5.0;
    // No custom contentInsets: UIKit owns the menu-source capsule size and its
    // Liquid Glass morph into the expanded UIMenu.
    button.configuration = presentation;

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
