#import "RYGSettingsViewController.h"
#import "../UI/RYGLiquidGlass.h"
#import <RyukGram-Swift.h>
#import <objc/runtime.h>

static const void *kRYGAdaptiveGlassMenuKey = &kRYGAdaptiveGlassMenuKey;

@implementation RYGSettingsViewController (RYGAdaptiveGlassMenuBridge)

+ (void)load {
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        Class cls = RYGSettingsViewController.class;
        SEL originalSelector = @selector(tableView:cellForRowAtIndexPath:);
        SEL replacementSelector = @selector(ryg_glass_tableView:cellForRowAtIndexPath:);
        Method original = class_getInstanceMethod(cls, originalSelector);
        Method replacement = class_getInstanceMethod(cls, replacementSelector);
        if (original && replacement) method_exchangeImplementations(original, replacement);
    });
}

- (UITableViewCell *)ryg_glass_tableView:(UITableView *)tableView
                   cellForRowAtIndexPath:(NSIndexPath *)indexPath {
    // Calls the original implementation after method exchange.
    UITableViewCell *cell = [self ryg_glass_tableView:tableView cellForRowAtIndexPath:indexPath];

    if (@available(iOS 26.0, *)) {
        UIButton *button = [cell.accessoryView isKindOfClass:UIButton.class]
            ? (UIButton *)cell.accessoryView
            : nil;
        UIMenu *menu = button.menu;
        if (!button || !menu) return cell;

        // Keep UIMenu as the canonical model so all existing commands,
        // propertyList payloads, selected states and submenus remain intact.
        // Only its presentation changes on iOS 26 because UIKit's contextual
        // menu column has a system full-width layout with no public width knob.
        objc_setAssociatedObject(button,
                                 kRYGAdaptiveGlassMenuKey,
                                 menu,
                                 OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        button.menu = nil;
        button.showsMenuAsPrimaryAction = NO;

        NSString *title = button.configuration.title ?: [button titleForState:UIControlStateNormal] ?: @"";
        UIButtonConfiguration *configuration = [UIButtonConfiguration clearGlassButtonConfiguration];
        configuration.title = title;
        configuration.baseForegroundColor = UIColor.labelColor;
        [configuration setDefaultContentInsets];
        button.configuration = configuration;
        button.backgroundColor = UIColor.clearColor;
        [button invalidateIntrinsicContentSize];

        [button addTarget:self
                   action:@selector(ryg_presentAdaptiveGlassMenu:)
         forControlEvents:UIControlEventTouchUpInside];
    }
    return cell;
}

- (void)ryg_presentAdaptiveGlassMenu:(UIButton *)sender {
    if (@available(iOS 26.0, *)) {
        UIMenu *menu = objc_getAssociatedObject(sender, kRYGAdaptiveGlassMenuKey);
        if (menu) {
            [RYGAdaptiveGlassMenuPresenter presentFrom:sender menu:menu];
            return;
        }
    }
}

@end
