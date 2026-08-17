#import "../Settings/RYGSettingsViewController.h"
#import "../Settings/RYGSetting.h"
#import "RYGLiquidGlass.h"
#import <objc/runtime.h>

@interface RYGSettingsViewController (RYGMenuGlassPrivate)
- (UIListContentConfiguration *)configuredContent:(UIListContentConfiguration *)config
                                          forCell:(UITableViewCell *)cell
                                              row:(RYGSetting *)row
                                        indexPath:(NSIndexPath *)indexPath;
@end

static UIMenuElement *RYGCompactCloneMenuElement(UIMenuElement *element) {
    if ([element isKindOfClass:UICommand.class]) {
        UICommand *source = (UICommand *)element;
        NSString *title = source.title ?: @"";
        // UIKit reserves a complete leading state column when any command uses
        // UIMenuElementStateOn. In a narrow value picker that becomes the large,
        // fixed-looking left margin seen on iOS 26/27. Keep the selected mark in
        // the title instead so the expanded menu sizes from its actual content.
        if (source.state == UIMenuElementStateOn) {
            title = [NSString stringWithFormat:@"✓  %@", title];
        }
        UICommand *copy = [UICommand commandWithTitle:title
                                                image:source.image
                                               action:source.action
                                         propertyList:source.propertyList];
        copy.attributes = source.attributes;
        copy.state = UIMenuElementStateOff;
        return copy;
    }
    if ([element isKindOfClass:UIMenu.class]) {
        UIMenu *source = (UIMenu *)element;
        NSMutableArray<UIMenuElement *> *children = [NSMutableArray arrayWithCapacity:source.children.count];
        for (UIMenuElement *child in source.children) {
            UIMenuElement *copy = RYGCompactCloneMenuElement(child);
            if (copy) [children addObject:copy];
        }
        UIMenu *copy = [UIMenu menuWithTitle:source.title ?: @""
                                       image:source.image
                                  identifier:source.identifier
                                     options:source.options
                                    children:children];
        if (@available(iOS 16.0, *)) {
            // Large preserves the vertical picker semantics. Width is now driven
            // by content because the artificial state column above is gone.
            copy.preferredElementSize = UIMenuElementSizeLarge;
        }
        return copy;
    }
    return element;
}

@implementation RYGSettingsViewController (RYGSettingsMenuGlassFix)

- (UIListContentConfiguration *)ryg_menuFixedConfiguredContent:(UIListContentConfiguration *)config
                                                       forCell:(UITableViewCell *)cell
                                                           row:(RYGSetting *)row
                                                     indexPath:(NSIndexPath *)indexPath {
    UIListContentConfiguration *result = [self ryg_menuFixedConfiguredContent:config
                                                                       forCell:cell
                                                                           row:row
                                                                     indexPath:indexPath];
    if (row.type != RYGTableCellMenu) return result;

    UIButton *button = [cell.accessoryView isKindOfClass:UIButton.class] ? (UIButton *)cell.accessoryView : nil;
    if (!button) return result;

    NSString *visibleTitle = [button titleForState:UIControlStateNormal] ?: button.configuration.title ?: @"•••";
    UIMenu *menu = button.menu;
    if (menu) button.menu = (UIMenu *)RYGCompactCloneMenuElement(menu);

    // Configure Glass *before* the final sizeToFit. The previous order measured
    // the plain 8pt button and later replaced its configuration with Glass while
    // it was already installed as accessoryView, leaving a stale narrow frame
    // ("Off" became "O\nff").
    RYGLiquidGlassConfigureButton(button, NO);
    UIButtonConfiguration *configuration = button.configuration ?: UIButtonConfiguration.plainButtonConfiguration;
    configuration.title = visibleTitle;
    configuration.contentInsets = NSDirectionalEdgeInsetsMake(7.0, 12.0, 7.0, 12.0);
    configuration.cornerStyle = UIButtonConfigurationCornerStyleCapsule;
    configuration.buttonSize = UIButtonConfigurationSizeSmall;
    button.configuration = configuration;

    button.titleLabel.numberOfLines = 1;
    button.titleLabel.lineBreakMode = NSLineBreakByClipping;
    button.titleLabel.adjustsFontSizeToFitWidth = NO;
    [button invalidateIntrinsicContentSize];
    [button sizeToFit];

    CGRect frame = button.frame;
    frame.size.width = MAX(frame.size.width, 58.0);
    frame.size.height = MAX(frame.size.height, 34.0);
    button.frame = frame;
    cell.accessoryView = button;
    return result;
}

@end

__attribute__((constructor(65520))) static void RYGInstallSettingsMenuGlassFix(void) {
    @autoreleasepool {
        Class cls = RYGSettingsViewController.class;
        SEL originalSelector = @selector(configuredContent:forCell:row:indexPath:);
        SEL replacementSelector = @selector(ryg_menuFixedConfiguredContent:forCell:row:indexPath:);
        Method original = class_getInstanceMethod(cls, originalSelector);
        Method replacement = class_getInstanceMethod(cls, replacementSelector);
        if (original && replacement) method_exchangeImplementations(original, replacement);
    }
}
