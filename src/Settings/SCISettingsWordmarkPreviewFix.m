#import "SCISettingsViewController.h"
#import "SCISetting.h"
#import "../UI/SCIUIKit26LiquidGlass.h"
#import "../Localization/SCILocalization.h"
#import "../Utils.h"
#import <objc/runtime.h>

static NSString *const kSCIWordmarkPreviewKey = @"sci_ig_wordmark_variant";

@interface SCISettingsViewController ()
- (void)menuChanged:(UICommand *)command;
@end

static UIImage *SCIWPImageNamed(NSString *name) {
    NSBundle *bundle = SCILocalizationBundle();
    UIImage *img = bundle ? [UIImage imageNamed:name inBundle:bundle compatibleWithTraitCollection:nil] : nil;
    return img ?: [UIImage imageNamed:name];
}

static NSString *SCIWPImageNameForValue(NSString *value) {
    NSString *v = value.length ? value : @"off";
    if ([v isEqualToString:@"1a"]) return @"instagram-wordmark-1a";
    if ([v isEqualToString:@"1a_alt"]) return @"instagram-wordmark-1a-alt";
    if ([v isEqualToString:@"1b"]) return @"instagram-wordmark-1b";
    if ([v isEqualToString:@"1b_alt"]) return @"instagram-wordmark-1b-alt";
    return @"instagram-wordmark-default";
}

static UIImage *SCIWPPreview(UIImage *img, CGSize canvas) {
    if (!img) return nil;
    CGSize size = img.size;
    if (size.width <= 0.0 || size.height <= 0.0 || canvas.width <= 0.0 || canvas.height <= 0.0) return [img imageWithRenderingMode:UIImageRenderingModeAlwaysTemplate];
    CGFloat ratio = MIN(canvas.width / size.width, canvas.height / size.height);
    if (ratio <= 0.0 || !isfinite(ratio)) ratio = 1.0;
    CGSize target = CGSizeMake(floor(size.width * ratio), floor(size.height * ratio));
    CGRect rect = CGRectMake((canvas.width - target.width) * 0.5, (canvas.height - target.height) * 0.5, target.width, target.height);
    UIGraphicsImageRendererFormat *fmt = [UIGraphicsImageRendererFormat preferredFormat];
    fmt.opaque = NO;
    fmt.scale = UIScreen.mainScreen.scale;
    UIGraphicsImageRenderer *renderer = [[UIGraphicsImageRenderer alloc] initWithSize:canvas format:fmt];
    UIImage *scaled = [renderer imageWithActions:^(UIGraphicsImageRendererContext * _Nonnull ctx) {
        [img drawInRect:rect];
    }];
    return [scaled imageWithRenderingMode:UIImageRenderingModeAlwaysTemplate];
}

static BOOL SCIWPMenuHasWordmark(UIMenu *menu) {
    for (UIMenuElement *el in menu.children) {
        if ([el isKindOfClass:UIMenu.class] && SCIWPMenuHasWordmark((UIMenu *)el)) return YES;
        if (![el isKindOfClass:UICommand.class]) continue;
        NSDictionary *props = [((UICommand *)el).propertyList isKindOfClass:NSDictionary.class] ? ((UICommand *)el).propertyList : nil;
        if ([props[@"defaultsKey"] isEqualToString:kSCIWordmarkPreviewKey]) return YES;
    }
    return NO;
}

static void SCIWPCollect(UIMenu *menu, NSMutableArray<UICommand *> *out) {
    for (UIMenuElement *el in menu.children) {
        if ([el isKindOfClass:UIMenu.class]) { SCIWPCollect((UIMenu *)el, out); continue; }
        if (![el isKindOfClass:UICommand.class]) continue;
        UICommand *cmd = (UICommand *)el;
        NSDictionary *props = [cmd.propertyList isKindOfClass:NSDictionary.class] ? cmd.propertyList : nil;
        if ([props[@"defaultsKey"] isEqualToString:kSCIWordmarkPreviewKey]) [out addObject:cmd];
    }
}

static void SCIWPDeactivateSizingConstraints(UIView *view) {
    NSMutableArray<NSLayoutConstraint *> *kill = [NSMutableArray array];
    for (NSLayoutConstraint *c in view.constraints) {
        if ((c.firstItem == view || c.secondItem == view)
            && (c.firstAttribute == NSLayoutAttributeWidth || c.firstAttribute == NSLayoutAttributeHeight)) [kill addObject:c];
    }
    if (kill.count) [NSLayoutConstraint deactivateConstraints:kill];
}

@interface SCIWPButton : UIButton
@property (nonatomic, weak) SCISettingsViewController *presenter;
@property (nonatomic, strong) UIMenu *sourceMenu;
@end
@implementation SCIWPButton @end

@interface SCIWPPicker : UIViewController <UITableViewDataSource, UITableViewDelegate, UIPopoverPresentationControllerDelegate>
@property (nonatomic, weak) SCISettingsViewController *presenter;
@property (nonatomic, copy) NSArray<UICommand *> *commands;
@property (nonatomic, strong) UITableView *tableView;
@end

@implementation SCIWPPicker
- (void)viewDidLoad {
    [super viewDidLoad];
    self.view.backgroundColor = SCIUIKit26PanelFillColor();
    self.view.layer.cornerRadius = 22.0;
    if ([self.view.layer respondsToSelector:@selector(setCornerCurve:)]) self.view.layer.cornerCurve = kCACornerCurveContinuous;
    self.view.clipsToBounds = YES;
    SCIUIKit26ApplyContainerBackgroundToViewController(self);
    _tableView = [[UITableView alloc] initWithFrame:CGRectZero style:UITableViewStylePlain];
    _tableView.translatesAutoresizingMaskIntoConstraints = NO;
    _tableView.dataSource = self;
    _tableView.delegate = self;
    _tableView.rowHeight = 44.0;
    _tableView.separatorStyle = UITableViewCellSeparatorStyleNone;
    _tableView.backgroundColor = UIColor.clearColor;
    _tableView.alwaysBounceVertical = NO;
    _tableView.showsVerticalScrollIndicator = NO;
    if (@available(iOS 11.0, *)) _tableView.contentInsetAdjustmentBehavior = UIScrollViewContentInsetAdjustmentNever;
    [self.view addSubview:_tableView];
    [NSLayoutConstraint activateConstraints:@[
        [_tableView.topAnchor constraintEqualToAnchor:self.view.topAnchor constant:6.0],
        [_tableView.leadingAnchor constraintEqualToAnchor:self.view.leadingAnchor constant:8.0],
        [_tableView.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor constant:-8.0],
        [_tableView.bottomAnchor constraintEqualToAnchor:self.view.bottomAnchor constant:-6.0],
    ]];
}
- (CGSize)preferredContentSize { return CGSizeMake(244.0, MIN(252.0, MAX(1, (NSInteger)self.commands.count) * 44.0 + 12.0)); }
- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section { return (NSInteger)self.commands.count; }
- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath {
    UITableViewCell *cell = [tableView dequeueReusableCellWithIdentifier:@"w"] ?: [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleDefault reuseIdentifier:@"w"];
    cell.contentConfiguration = nil;
    cell.backgroundColor = UIColor.clearColor;
    cell.contentView.backgroundColor = UIColor.clearColor;
    UIImageView *iv = (UIImageView *)[cell.contentView viewWithTag:9181];
    if (!iv) {
        iv = [[UIImageView alloc] init]; iv.tag = 9181; iv.translatesAutoresizingMaskIntoConstraints = NO; iv.contentMode = UIViewContentModeScaleAspectFit;
        [cell.contentView addSubview:iv];
        [NSLayoutConstraint activateConstraints:@[[iv.centerXAnchor constraintEqualToAnchor:cell.contentView.centerXAnchor], [iv.centerYAnchor constraintEqualToAnchor:cell.contentView.centerYAnchor], [iv.widthAnchor constraintEqualToConstant:150.0], [iv.heightAnchor constraintEqualToConstant:28.0]]];
    }
    UICommand *cmd = self.commands[(NSUInteger)indexPath.row];
    NSDictionary *props = [cmd.propertyList isKindOfClass:NSDictionary.class] ? cmd.propertyList : nil;
    NSString *value = [props[@"value"] isKindOfClass:NSString.class] ? props[@"value"] : @"off";
    NSString *selected = [NSUserDefaults.standardUserDefaults stringForKey:kSCIWordmarkPreviewKey] ?: @"off";
    NSString *imageName = [props[@"wordmarkImageName"] isKindOfClass:NSString.class] ? props[@"wordmarkImageName"] : SCIWPImageNameForValue(value);
    iv.image = SCIWPPreview(SCIWPImageNamed(imageName), CGSizeMake(150.0, 28.0));
    iv.tintColor = [value isEqualToString:selected] ? [SCIUtils SCIColor_Primary] : UIColor.labelColor;
    SCIUIKit26ApplyTableCellSelectionTint(cell, [value isEqualToString:selected]);
    return cell;
}
- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath {
    UICommand *cmd = self.commands[(NSUInteger)indexPath.row];
    [self.presenter menuChanged:cmd];
    [self dismissViewControllerAnimated:YES completion:nil];
}
- (UIModalPresentationStyle)adaptivePresentationStyleForPresentationController:(UIPresentationController *)controller { return UIModalPresentationNone; }
@end

static void SCIWPRefreshButton(SCIWPButton *button) {
    NSString *value = [NSUserDefaults.standardUserDefaults stringForKey:kSCIWordmarkPreviewKey] ?: @"off";
    UIImage *image = SCIWPPreview(SCIWPImageNamed(SCIWPImageNameForValue(value)), CGSizeMake(118.0, 28.0));
    UIButtonConfiguration *cfg = button.configuration ?: UIButtonConfiguration.plainButtonConfiguration;
    cfg.title = nil; cfg.subtitle = nil; cfg.image = image; cfg.imagePadding = 0.0;
    cfg.contentInsets = NSDirectionalEdgeInsetsMake(6.0, 10.0, 6.0, 10.0);
    cfg.background.backgroundColor = UIColor.clearColor;
    cfg.background.visualEffect = SCIUIKit26GlassEffect(YES, YES, nil);
    cfg.baseForegroundColor = UIColor.labelColor;
    button.configuration = cfg;
    button.tintColor = UIColor.labelColor;
    button.clipsToBounds = YES;
    button.imageView.contentMode = UIViewContentModeScaleAspectFit;
}

@implementation SCISettingsViewController (SCIWordmarkPreviewFix)
+ (void)load {
    Method a = class_getInstanceMethod(self, @selector(configuredContent:forCell:row:indexPath:));
    Method b = class_getInstanceMethod(self, @selector(sci_wp_configuredContent:forCell:row:indexPath:));
    if (a && b) method_exchangeImplementations(a, b);
}
- (UIListContentConfiguration *)sci_wp_configuredContent:(UIListContentConfiguration *)config forCell:(UITableViewCell *)cell row:(SCISetting *)row indexPath:(NSIndexPath *)indexPath {
    UIListContentConfiguration *out = [self sci_wp_configuredContent:config forCell:cell row:row indexPath:indexPath];
    if (row.type != SCITableCellMenu) return out;
    BOOL wordmark = SCIWPMenuHasWordmark(row.baseMenu);
    if (!wordmark) {
        UIButton *menuButton = [cell.accessoryView isKindOfClass:UIButton.class] ? (UIButton *)cell.accessoryView : nil;
        if (menuButton) {
            if (@available(iOS 15.0, *)) menuButton.changesSelectionAsPrimaryAction = YES;
            SCIWPDeactivateSizingConstraints(menuButton);
            UIButtonConfiguration *cfg = menuButton.configuration ?: UIButtonConfiguration.plainButtonConfiguration;
            cfg.contentInsets = NSDirectionalEdgeInsetsMake(6.0, 10.0, 6.0, 10.0);
            cfg.indicator = UIButtonConfigurationIndicatorPopup;
            menuButton.configuration = cfg;
        }
        return out;
    }

    UIView *container = [UIView new];
    container.translatesAutoresizingMaskIntoConstraints = NO;
    container.clipsToBounds = YES;
    SCIWPButton *button = [SCIWPButton buttonWithType:UIButtonTypeSystem];
    button.translatesAutoresizingMaskIntoConstraints = NO;
    button.presenter = self; button.sourceMenu = row.baseMenu; button.showsMenuAsPrimaryAction = NO; button.menu = nil;
    SCIUIKit26ConfigureButton(button); SCIWPRefreshButton(button);
    [button addTarget:self action:@selector(sci_wp_openWordmarkPicker:) forControlEvents:UIControlEventTouchUpInside];
    [container addSubview:button];
    [NSLayoutConstraint activateConstraints:@[
        [container.widthAnchor constraintEqualToConstant:142.0],
        [container.heightAnchor constraintEqualToConstant:38.0],
        [button.topAnchor constraintEqualToAnchor:container.topAnchor],
        [button.leadingAnchor constraintEqualToAnchor:container.leadingAnchor],
        [button.trailingAnchor constraintEqualToAnchor:container.trailingAnchor],
        [button.bottomAnchor constraintEqualToAnchor:container.bottomAnchor],
    ]];
    cell.accessoryView = container;
    return out;
}
- (void)sci_wp_openWordmarkPicker:(SCIWPButton *)button {
    NSMutableArray<UICommand *> *commands = [NSMutableArray array]; SCIWPCollect(button.sourceMenu, commands); if (!commands.count) return;
    SCIWPPicker *picker = [SCIWPPicker new]; picker.presenter = self; picker.commands = commands.copy; picker.modalPresentationStyle = UIModalPresentationPopover; picker.preferredContentSize = picker.preferredContentSize;
    UIPopoverPresentationController *pop = picker.popoverPresentationController; pop.sourceView = button; pop.sourceRect = button.bounds; pop.permittedArrowDirections = UIPopoverArrowDirectionAny; pop.delegate = picker; pop.backgroundColor = UIColor.clearColor;
    [self presentViewController:picker animated:YES completion:nil];
}
@end
