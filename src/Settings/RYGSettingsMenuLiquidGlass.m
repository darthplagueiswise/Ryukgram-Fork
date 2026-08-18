#import "RYGSettingsViewController.h"
#import "RYGSetting.h"
#import "../UI/RYGLiquidGlass.h"
#import <objc/runtime.h>

static NSString *RYGSelectedMenuTitle(UIMenu *menu) {
    for (UIMenuElement *element in menu.children) {
        if ([element isKindOfClass:UIMenu.class]) {
            NSString *nested = RYGSelectedMenuTitle((UIMenu *)element);
            if (nested.length) return nested;
            continue;
        }
        if ([element isKindOfClass:UICommand.class]) {
            UICommand *command = (UICommand *)element;
            if (command.state != UIMenuElementStateOn) continue;
            id propertyList = command.propertyList;
            if ([propertyList isKindOfClass:NSDictionary.class]
                && [((NSDictionary *)propertyList)[@"noTitle"] boolValue]) continue;
            if (command.title.length) return command.title;
        }
    }
    return nil;
}

static UIButtonConfiguration *RYGMenuSourceConfiguration(NSString *title) {
    UIButtonConfiguration *configuration = nil;
    if (@available(iOS 26.0, *)) {
        if (RYGLiquidGlassIsAvailable()) {
            configuration = [UIButtonConfiguration glassButtonConfiguration];
        }
    }
    if (!configuration) configuration = [UIButtonConfiguration borderedButtonConfiguration];

    configuration.title = title.length ? title : @"•••";
    configuration.baseForegroundColor = UIColor.labelColor;
    // No custom image, contentInsets, buttonSize or minimumSize here. The source
    // control is the geometry UIKit morphs into the expanded menu on iOS 26+;
    // imposing RyukGram metrics is what produced the oversized preselected
    // margin and the loose blue value labels shown in Feed/Stories/Advanced.
    return configuration;
}

/// Final renderer for every RYGTableCellMenu row in the tweak.
/// Feed, Stories, Advanced and every other multi-selection row flow through
/// this single path so their closed and expanded states cannot drift apart.
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

    // menuForButton: has already resolved the preference-backed selected title.
    // Prefer that exact title, then fall back to the checked command in the tree.
    NSString *selectedTitle = [legacyButton titleForState:UIControlStateNormal];
    if (!selectedTitle.length || [selectedTitle isEqualToString:@"•••"]) {
        selectedTitle = legacyButton.configuration.title;
    }
    if (!selectedTitle.length || [selectedTitle isEqualToString:@"•••"]) {
        selectedTitle = RYGSelectedMenuTitle(menu);
    }

    UIButton *button = [UIButton buttonWithConfiguration:RYGMenuSourceConfiguration(selectedTitle)
                                            primaryAction:nil];
    button.menu = menu;
    button.showsMenuAsPrimaryAction = YES;
    button.changesSelectionAsPrimaryAction = NO;
    button.enabled = !row.disabled;
    button.accessibilityLabel = row.title;
    button.contentHorizontalAlignment = UIControlContentHorizontalAlignmentCenter;
    [button setContentCompressionResistancePriority:UILayoutPriorityRequired
                                            forAxis:UILayoutConstraintAxisHorizontal];
    [button setContentHuggingPriority:UILayoutPriorityRequired
                              forAxis:UILayoutConstraintAxisHorizontal];

    // UITableViewCell.accessoryView is frame-based. sizeToFit asks UIKit for the
    // native control size; unlike the previous code, no RyukGram minimum width,
    // height or padding is layered on top of that result.
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
