#import "RYGSettingsViewController.h"
#import "RYGSetting.h"
#import "../UI/RYGLiquidGlass.h"
#import <objc/runtime.h>

static void RYGCollectMenuPreferenceKeys(UIMenu *menu, NSMutableSet<NSString *> *keys) {
    for (UIMenuElement *element in menu.children) {
        if ([element isKindOfClass:UIMenu.class]) {
            RYGCollectMenuPreferenceKeys((UIMenu *)element, keys);
            continue;
        }
        if (![element isKindOfClass:UICommand.class]) continue;
        id propertyList = ((UICommand *)element).propertyList;
        if (![propertyList isKindOfClass:NSDictionary.class]) continue;
        NSString *key = ((NSDictionary *)propertyList)[@"defaultsKey"];
        if (key.length) [keys addObject:key];
    }
}

static NSString *RYGSelectedMenuTitle(UIMenu *menu) {
    for (UIMenuElement *element in menu.children) {
        if ([element isKindOfClass:UIMenu.class]) {
            NSString *nested = RYGSelectedMenuTitle((UIMenu *)element);
            if (nested.length) return nested;
            continue;
        }
        if (![element isKindOfClass:UICommand.class]) continue;
        UICommand *command = (UICommand *)element;
        if (command.state != UIMenuElementStateOn) continue;
        id propertyList = command.propertyList;
        if ([propertyList isKindOfClass:NSDictionary.class]
            && [((NSDictionary *)propertyList)[@"noTitle"] boolValue]) continue;
        if (command.title.length) return command.title;
    }
    return nil;
}

static UIButtonConfiguration *RYGMenuSourceConfiguration(NSString *title) {
    UIButtonConfiguration *configuration = nil;
    if (@available(iOS 26.0, *)) {
        if (RYGLiquidGlassIsAvailable()) {
            // A menu source is interactive by definition. Use UIKit's native
            // glass button rather than wrapping a legacy UIButton in a custom
            // visual-effect view. This is the geometry UIKit knows how to morph.
            configuration = [UIButtonConfiguration glassButtonConfiguration];
        }
    }
    if (!configuration) configuration = [UIButtonConfiguration borderedButtonConfiguration];

    configuration.title = title.length ? title : @"•••";
    configuration.baseForegroundColor = UIColor.labelColor;
    configuration.image = [UIImage systemImageNamed:@"chevron.down"];
    configuration.imagePlacement = NSDirectionalRectEdgeTrailing;
    configuration.imagePadding = 5.0;
    // Deliberately no contentInsets/minimumSize. The source control and the
    // expanded UIMenu are both system-sized; there is no preselected margin to
    // leak into the morph animation.
    return configuration;
}

/// Final renderer for every RYGTableCellMenu row.
///
/// The old path mixed setTitle:, buttonWithType:, a later UIButtonConfiguration,
/// and fixed contentInsets. On iOS 26/27 that can make the legacy title label
/// survive independently of the configured button; the selected value then
/// appears as loose blue text over the cell (the exact "Default / Main feed"
/// overlap from the device screenshot).
///
/// Do not mutate that legacy button. Build a fresh modern menu-source UIButton
/// from UIButtonConfiguration after the menu has resolved its selected command.
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

    UIButton *legacyButton = (UIButton *)cell.accessoryView;
    UIMenu *menu = legacyButton.menu;
    if (!menu) return result;

    NSString *selectedTitle = RYGSelectedMenuTitle(menu);
    if (!selectedTitle.length) selectedTitle = [legacyButton titleForState:UIControlStateNormal];
    if (!selectedTitle.length) selectedTitle = legacyButton.configuration.title;

    UIButtonConfiguration *configuration = RYGMenuSourceConfiguration(selectedTitle);
    UIButton *button = [UIButton buttonWithConfiguration:configuration primaryAction:nil];
    button.menu = menu;
    button.showsMenuAsPrimaryAction = YES;
    button.enabled = !row.disabled;
    button.accessibilityLabel = row.title;
    button.contentHorizontalAlignment = UIControlContentHorizontalAlignmentCenter;
    [button setContentCompressionResistancePriority:UILayoutPriorityRequired forAxis:UILayoutConstraintAxisHorizontal];
    [button setContentHuggingPriority:UILayoutPriorityRequired forAxis:UILayoutConstraintAxisHorizontal];

    NSMutableSet<NSString *> *preferenceKeys = [NSMutableSet set];
    RYGCollectMenuPreferenceKeys(menu, preferenceKeys);
    // When the tree represents one preference, opt into UIKit's native pop-up
    // selection model. UIKit then owns selectedElements and keeps the closed
    // button title synchronized with the checked menu item. Multi-preference
    // trees retain RyukGram's command-state model and never collapse unrelated
    // nested settings into one selection.
    button.changesSelectionAsPrimaryAction = preferenceKeys.count == 1;

    // UITableViewCell.accessoryView is frame-based. Give it only its compressed
    // intrinsic size; never the cell width. This prevents the menu source from
    // extending over the primary/secondary labels.
    CGSize size = [button systemLayoutSizeFittingSize:UILayoutFittingCompressedSize];
    if (size.width <= 0.0 || size.height <= 0.0) size = button.intrinsicContentSize;
    button.frame = CGRectMake(0.0, 0.0, ceil(MAX(44.0, size.width)), ceil(MAX(34.0, size.height)));

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
