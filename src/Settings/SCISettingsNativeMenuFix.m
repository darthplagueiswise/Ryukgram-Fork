#import "SCISettingsViewController.h"
#import "SCISetting.h"
#import "../Features/Gating/SCIBulkGatingPresets.h"
#import "../UI/SCIUIKit26LiquidGlass.h"
#import "../Localization/SCILocalization.h"
#import "../Utils.h"
#import <objc/runtime.h>

static NSString *const kSCINativeWordmarkKey = @"sci_ig_wordmark_variant";

static UIImage *SCINativeWordmarkImageNamed(NSString *name) {
    if (!name.length) return nil;
    NSBundle *bundle = SCILocalizationBundle();
    UIImage *img = bundle ? [UIImage imageNamed:name inBundle:bundle compatibleWithTraitCollection:nil] : nil;
    return img ?: [UIImage imageNamed:name];
}

static NSString *SCINativeWordmarkImageNameForValue(NSString *value) {
    NSString *v = value.length ? value : @"off";
    if ([v isEqualToString:@"1a"]) return @"instagram-wordmark-1a";
    if ([v isEqualToString:@"1a_alt"]) return @"instagram-wordmark-1a-alt";
    if ([v isEqualToString:@"1b"]) return @"instagram-wordmark-1b";
    if ([v isEqualToString:@"1b_alt"]) return @"instagram-wordmark-1b-alt";
    return @"instagram-wordmark-default";
}

static UIImage *SCINativeWordmarkCanvas(UIImage *source, CGSize canvas) {
    if (!source) return nil;
    CGSize size = source.size;
    if (size.width <= 0.0 || size.height <= 0.0) return [source imageWithRenderingMode:UIImageRenderingModeAlwaysTemplate];
    CGFloat scale = MIN(canvas.width / size.width, canvas.height / size.height);
    if (scale <= 0.0 || !isfinite(scale)) scale = 1.0;
    CGSize target = CGSizeMake(floor(size.width * scale), floor(size.height * scale));
    CGRect rect = CGRectMake((canvas.width - target.width) * 0.5, (canvas.height - target.height) * 0.5, target.width, target.height);
    UIGraphicsImageRendererFormat *fmt = [UIGraphicsImageRendererFormat preferredFormat];
    fmt.opaque = NO;
    fmt.scale = UIScreen.mainScreen.scale;
    UIGraphicsImageRenderer *renderer = [[UIGraphicsImageRenderer alloc] initWithSize:canvas format:fmt];
    UIImage *image = [renderer imageWithActions:^(UIGraphicsImageRendererContext * _Nonnull ctx) {
        [source drawInRect:rect];
    }];
    return [image imageWithRenderingMode:UIImageRenderingModeAlwaysTemplate];
}

static BOOL SCINativeMenuHasWordmark(UIMenu *menu) {
    for (UIMenuElement *el in menu.children) {
        if ([el isKindOfClass:UIMenu.class] && SCINativeMenuHasWordmark((UIMenu *)el)) return YES;
        if (![el isKindOfClass:UICommand.class]) continue;
        NSDictionary *props = [((UICommand *)el).propertyList isKindOfClass:NSDictionary.class] ? ((UICommand *)el).propertyList : nil;
        if ([props[@"defaultsKey"] isEqualToString:kSCINativeWordmarkKey]) return YES;
    }
    return NO;
}

static void SCINativeCollectWordmarkCommands(UIMenu *menu, NSMutableArray<UICommand *> *out) {
    for (UIMenuElement *el in menu.children) {
        if ([el isKindOfClass:UIMenu.class]) {
            SCINativeCollectWordmarkCommands((UIMenu *)el, out);
            continue;
        }
        if (![el isKindOfClass:UICommand.class]) continue;
        UICommand *cmd = (UICommand *)el;
        NSDictionary *props = [cmd.propertyList isKindOfClass:NSDictionary.class] ? cmd.propertyList : nil;
        if ([props[@"defaultsKey"] isEqualToString:kSCINativeWordmarkKey]) [out addObject:cmd];
    }
}

static UIMenu *SCINativeWordmarkMenu(UIMenu *sourceMenu, __weak UITableView *tableView) {
    NSMutableArray<UICommand *> *commands = [NSMutableArray array];
    SCINativeCollectWordmarkCommands(sourceMenu, commands);
    NSMutableArray<UIMenuElement *> *items = [NSMutableArray array];
    NSString *current = [NSUserDefaults.standardUserDefaults stringForKey:kSCINativeWordmarkKey] ?: @"off";

    for (UICommand *cmd in commands) {
        NSDictionary *props = [cmd.propertyList isKindOfClass:NSDictionary.class] ? cmd.propertyList : nil;
        NSString *value = [props[@"value"] isKindOfClass:NSString.class] ? props[@"value"] : @"off";
        NSString *asset = [props[@"wordmarkImageName"] isKindOfClass:NSString.class] ? props[@"wordmarkImageName"] : SCINativeWordmarkImageNameForValue(value);
        UIImage *icon = SCINativeWordmarkCanvas(SCINativeWordmarkImageNamed(asset), CGSizeMake(92.0, 24.0));
        UIAction *action = [UIAction actionWithTitle:@" " image:icon identifier:nil handler:^(__kindof UIAction * _Nonnull action) {
            [NSUserDefaults.standardUserDefaults setObject:value forKey:kSCINativeWordmarkKey];
            [SCIBulkGatingPresets applyIGWordmarkMode:value];
            [tableView reloadData];
        }];
        action.discoverabilityTitle = cmd.title.length ? cmd.title : value;
        action.state = [value isEqualToString:current] ? UIMenuElementStateOn : UIMenuElementStateOff;
        [items addObject:action];
    }

    UIMenuOptions options = 0;
    if (@available(iOS 15.0, *)) options |= UIMenuOptionsSingleSelection;
    return [UIMenu menuWithTitle:@"" image:nil identifier:nil options:options children:items];
}

static void SCINativeDropSizingConstraints(UIView *view) {
    NSMutableArray<NSLayoutConstraint *> *kill = [NSMutableArray array];
    for (NSLayoutConstraint *constraint in view.constraints) {
        BOOL touchesView = constraint.firstItem == view || constraint.secondItem == view;
        BOOL size = constraint.firstAttribute == NSLayoutAttributeWidth || constraint.firstAttribute == NSLayoutAttributeHeight;
        if (touchesView && size) [kill addObject:constraint];
    }
    if (kill.count) [NSLayoutConstraint deactivateConstraints:kill];
}

static void SCINativeFitMenuButton(UIButton *button, CGFloat minWidth) {
    if (!button) return;
    SCINativeDropSizingConstraints(button);
    [button setContentCompressionResistancePriority:UILayoutPriorityRequired forAxis:UILayoutConstraintAxisHorizontal];
    [button setContentHuggingPriority:UILayoutPriorityRequired forAxis:UILayoutConstraintAxisHorizontal];
    [button sizeToFit];
    CGSize intrinsic = button.intrinsicContentSize;
    CGRect frame = button.frame;
    frame.size.width = MAX(minWidth, ceil(intrinsic.width));
    frame.size.height = MAX(36.0, ceil(intrinsic.height));
    button.frame = frame;
}

static void SCINativeNormalizeCellSeparator(UITableViewCell *cell) {
    cell.preservesSuperviewLayoutMargins = NO;
    cell.layoutMargins = UIEdgeInsetsMake(0.0, 16.0, 0.0, 16.0);
    cell.separatorInset = UIEdgeInsetsMake(0.0, 16.0, 0.0, 16.0);
}

@implementation SCISettingsViewController (SCISettingsNativeMenuFix)

+ (void)load {
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        Method original = class_getInstanceMethod(self, @selector(configuredContent:forCell:row:indexPath:));
        Method replacement = class_getInstanceMethod(self, @selector(sci_nativeMenu_configuredContent:forCell:row:indexPath:));
        if (original && replacement) method_exchangeImplementations(original, replacement);
    });
}

- (UIListContentConfiguration *)sci_nativeMenu_configuredContent:(UIListContentConfiguration *)config forCell:(UITableViewCell *)cell row:(SCISetting *)row indexPath:(NSIndexPath *)indexPath {
    UIListContentConfiguration *out = [self sci_nativeMenu_configuredContent:config forCell:cell row:row indexPath:indexPath];
    SCINativeNormalizeCellSeparator(cell);

    if (row.type != SCITableCellMenu) return out;
    UIButton *button = [cell.accessoryView isKindOfClass:UIButton.class] ? (UIButton *)cell.accessoryView : nil;
    if (!button) return out;

    if (@available(iOS 15.0, *)) button.changesSelectionAsPrimaryAction = YES;
    button.showsMenuAsPrimaryAction = YES;

    if (SCINativeMenuHasWordmark(row.baseMenu)) {
        NSString *current = [NSUserDefaults.standardUserDefaults stringForKey:kSCINativeWordmarkKey] ?: @"off";
        UIImage *selected = SCINativeWordmarkCanvas(SCINativeWordmarkImageNamed(SCINativeWordmarkImageNameForValue(current)), CGSizeMake(118.0, 28.0));
        UIButtonConfiguration *bc = button.configuration ?: UIButtonConfiguration.plainButtonConfiguration;
        bc.title = nil;
        bc.subtitle = nil;
        bc.image = selected;
        bc.imagePadding = 0.0;
        bc.contentInsets = NSDirectionalEdgeInsetsMake(6.0, 10.0, 6.0, 10.0);
        bc.baseForegroundColor = UIColor.labelColor;
        button.configuration = bc;
        button.tintColor = UIColor.labelColor;
        button.menu = SCINativeWordmarkMenu(row.baseMenu, self.tableView);
        SCINativeFitMenuButton(button, 142.0);
        return out;
    }

    UIButtonConfiguration *bc = button.configuration ?: UIButtonConfiguration.plainButtonConfiguration;
    bc.contentInsets = NSDirectionalEdgeInsetsMake(6.0, 10.0, 6.0, 10.0);
    bc.indicator = UIButtonConfigurationIndicatorPopup;
    button.configuration = bc;
    SCINativeFitMenuButton(button, 74.0);
    return out;
}

@end
