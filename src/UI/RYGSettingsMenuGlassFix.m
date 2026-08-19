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
    if (!button || !button.showsMenuAsPrimaryAction) return result;

    // RYGSetting already turns the source button into an iOS 26 Glass button.
    // Keep UIKit's own intrinsic menu-source geometry: do not clone the UIMenu,
    // clear selection state, force a frame, add a corner radius, or copy closed
    // control margins into the expanded morph.
    RYGLiquidGlassConfigureButton(button, NO);
    if (@available(iOS 26.0, *)) {
        UIButtonConfiguration *configuration = button.configuration;
        if (configuration) {
            [configuration setDefaultContentInsets];
            button.configuration = configuration;
        }
    }
    button.titleLabel.numberOfLines = 1;
    button.titleLabel.lineBreakMode = NSLineBreakByClipping;
    [button invalidateIntrinsicContentSize];
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