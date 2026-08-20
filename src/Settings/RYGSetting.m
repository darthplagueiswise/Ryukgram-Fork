#import "RYGSetting.h"
#import "../UI/RYGLiquidGlass.h"

@interface RYGSetting ()
@property (nonatomic, readwrite) RYGTableCell type;
- (instancetype)initWithType:(RYGTableCell)type NS_DESIGNATED_INITIALIZER;
- (instancetype)init NS_UNAVAILABLE;
@end

@implementation RYGSetting

- (instancetype)initWithType:(RYGTableCell)type {
    self = [super init];
    if (self) self.type = type;
    return self;
}

+ (instancetype)staticCellWithTitle:(NSString *)title subtitle:(nullable NSString *)subtitle icon:(nullable RYGSymbol *)icon { RYGSetting *setting = [[self alloc] initWithType:RYGTableCellStatic]; setting.title = title; setting.subtitle = subtitle; setting.icon = icon; return setting; }
+ (instancetype)linkCellWithTitle:(NSString *)title subtitle:(nullable NSString *)subtitle icon:(nullable RYGSymbol *)icon url:(NSString *)url { RYGSetting *setting = [[self alloc] initWithType:RYGTableCellLink]; setting.title = title; setting.subtitle = subtitle; setting.icon = icon; setting.url = [NSURL URLWithString:url]; return setting; }
+ (instancetype)linkCellWithTitle:(NSString *)title subtitle:(nullable NSString *)subtitle imageUrl:(NSString *)imageUrl url:(NSString *)url { RYGSetting *setting = [[self alloc] initWithType:RYGTableCellLink]; setting.title = title; setting.subtitle = subtitle; setting.imageUrl = [NSURL URLWithString:imageUrl]; setting.url = [NSURL URLWithString:url]; return setting; }
+ (instancetype)switchCellWithTitle:(NSString *)title subtitle:(nullable NSString *)subtitle defaultsKey:(NSString *)defaultsKey { RYGSetting *setting = [[self alloc] initWithType:RYGTableCellSwitch]; setting.title = title; setting.subtitle = subtitle; setting.defaultsKey = defaultsKey; return setting; }
+ (instancetype)switchCellWithTitle:(NSString *)title subtitle:(nullable NSString *)subtitle defaultsKey:(NSString *)defaultsKey requiresRestart:(BOOL)requiresRestart { RYGSetting *setting = [[self alloc] initWithType:RYGTableCellSwitch]; setting.title = title; setting.subtitle = subtitle; setting.defaultsKey = defaultsKey; setting.requiresRestart = requiresRestart; return setting; }
+ (instancetype)switchCellWithTitle:(NSString *)title subtitle:(nullable NSString *)subtitle value:(BOOL (^)(void))value action:(void (^)(BOOL on))action { RYGSetting *setting = [[self alloc] initWithType:RYGTableCellSwitch]; setting.title = title; setting.subtitle = subtitle; setting.switchValueProvider = value; setting.switchAction = action; return setting; }
+ (instancetype)customCellWithHeight:(CGFloat)height provider:(UITableViewCell *(^)(UITableView *tableView, NSIndexPath *indexPath))provider { RYGSetting *setting = [[self alloc] initWithType:RYGTableCellCustom]; setting.customHeight = height; setting.customCellProvider = provider; return setting; }
+ (instancetype)stepperCellWithTitle:(NSString *)title subtitle:(nullable NSString *)subtitle defaultsKey:(NSString *)defaultsKey min:(double)min max:(double)max step:(double)step label:(NSString *)label singularLabel:(NSString *)singularLabel { RYGSetting *setting = [[self alloc] initWithType:RYGTableCellStepper]; setting.title = title; setting.subtitle = subtitle; setting.defaultsKey = defaultsKey; setting.min = min; setting.max = max; setting.step = step; setting.label = label; setting.singularLabel = singularLabel; return setting; }
+ (instancetype)actionCellWithTitle:(NSString *)title color:(UIColor *)color action:(void (^)(void))action { RYGSetting *setting = [[self alloc] initWithType:RYGTableCellButton]; setting.title = title; setting.action = action; setting.titleColor = color; setting.centeredTitle = YES; setting.hidesDisclosureIndicator = YES; return setting; }
+ (instancetype)buttonCellWithTitle:(NSString *)title subtitle:(nullable NSString *)subtitle icon:(nullable RYGSymbol *)icon action:(void (^)(void))action { RYGSetting *setting = [[self alloc] initWithType:RYGTableCellButton]; setting.title = title; setting.subtitle = subtitle; setting.icon = icon; setting.action = action; return setting; }
+ (instancetype)colorCellWithTitle:(NSString *)title subtitle:(nullable NSString *)subtitle defaultsKey:(NSString *)defaultsKey defaultColor:(nullable UIColor *)defaultColor { RYGSetting *setting = [[self alloc] initWithType:RYGTableCellColor]; setting.title = title; setting.subtitle = subtitle; setting.defaultsKey = defaultsKey; setting.defaultColor = defaultColor; return setting; }
+ (instancetype)menuCellWithTitle:(NSString *)title subtitle:(nullable NSString *)subtitle menu:(UIMenu *)menu { RYGSetting *setting = [[self alloc] initWithType:RYGTableCellMenu]; setting.title = title; setting.subtitle = subtitle; setting.baseMenu = menu; return setting; }
+ (instancetype)navigationCellWithTitle:(NSString *)title subtitle:(nullable NSString *)subtitle icon:(nullable RYGSymbol *)icon navSections:(NSArray *)navSections { RYGSetting *setting = [[self alloc] initWithType:RYGTableCellNavigation]; setting.title = title; setting.subtitle = subtitle; setting.icon = icon; setting.navSections = navSections; return setting; }
+ (instancetype)navigationCellWithTitle:(NSString *)title subtitle:(nullable NSString *)subtitle icon:(nullable RYGSymbol *)icon viewController:(UIViewController *)viewController { RYGSetting *setting = [[self alloc] initWithType:RYGTableCellNavigation]; setting.title = title; setting.subtitle = subtitle; setting.icon = icon; setting.navViewController = viewController; return setting; }

static NSDictionary *RYGCommandPropertyList(UICommand *command) {
    id value = command.propertyList;
    return [value isKindOfClass:NSDictionary.class] ? value : nil;
}

static BOOL RYGCommandIsSelected(UICommand *command) {
    NSDictionary *plist = RYGCommandPropertyList(command);
    NSString *defaultsKey = [plist[@"defaultsKey"] isKindOfClass:NSString.class] ? plist[@"defaultsKey"] : nil;
    id representedValue = plist[@"value"];
    if (defaultsKey.length && representedValue) {
        NSString *saved = [NSUserDefaults.standardUserDefaults stringForKey:defaultsKey];
        return [representedValue isEqual:saved];
    }
    return command.state == UIMenuElementStateOn;
}

static UIAction *RYGActionFromCommand(UICommand *command) {
    UIAction *action = [UIAction actionWithTitle:command.title ?: @""
                                           image:command.image
                                      identifier:nil
                                         handler:^(__unused UIAction *item) {
        if (command.action) {
            [UIApplication.sharedApplication sendAction:command.action to:nil from:command forEvent:nil];
        }
    }];
    action.state = RYGCommandIsSelected(command) ? UIMenuElementStateOn : UIMenuElementStateOff;
    action.attributes = command.attributes;
    return action;
}

// Convert legacy UICommand leaves only. Preserve every UIMenu's original
// options exactly: forcing SingleSelection into nested inline/submenus changes
// UIKit's expanded geometry and selection contract and was the source of the
// oversized morphing panels.
static UIMenu *RYGMenuPreservingHierarchy(UIMenu *menu) {
    if (!menu) return nil;
    NSMutableArray<UIMenuElement *> *children = [NSMutableArray arrayWithCapacity:menu.children.count];
    for (UIMenuElement *element in menu.children) {
        if ([element isKindOfClass:UIMenu.class]) [children addObject:RYGMenuPreservingHierarchy((UIMenu *)element)];
        else if ([element isKindOfClass:UICommand.class]) [children addObject:RYGActionFromCommand((UICommand *)element)];
        else [children addObject:element];
    }
    return [UIMenu menuWithTitle:menu.title image:menu.image identifier:menu.identifier options:menu.options children:children];
}

static NSString *RYGSelectedTitleForMenu(UIMenu *menu) {
    for (UIMenuElement *element in menu.children) {
        if ([element isKindOfClass:UIMenu.class]) {
            NSString *nested = RYGSelectedTitleForMenu((UIMenu *)element);
            if (nested.length) return nested;
        } else if ([element isKindOfClass:UIAction.class]) {
            UIAction *action = (UIAction *)element;
            if (action.state == UIMenuElementStateOn && action.title.length) return action.title;
        }
    }
    return nil;
}

- (UIMenu *)menuForButton:(UIButton *)button {
    UIMenu *menu = RYGMenuPreservingHierarchy(self.baseMenu);
    if (!button) return menu;

    button.menu = menu;
    button.showsMenuAsPrimaryAction = YES;
    button.changesSelectionAsPrimaryAction = YES;
    button.tintColor = UIColor.labelColor;

    NSString *selectedTitle = RYGSelectedTitleForMenu(menu);
    UIButtonConfiguration *configuration = button.configuration ?: [UIButtonConfiguration plainButtonConfiguration];
    configuration.title = selectedTitle.length ? selectedTitle : @"•••";
    configuration.baseForegroundColor = UIColor.labelColor;
    button.configuration = configuration;

    // One source view owns both states of the morph. Do not create an overlay,
    // duplicate accessory, fixed expanded margin, or custom content insets.
    RYGLiquidGlassConfigureButton(button, NO);
    if (@available(iOS 26.0, *)) {
        UIButtonConfiguration *glass = button.configuration;
        [glass setDefaultContentInsets];
        button.configuration = glass;
    }
    [button invalidateIntrinsicContentSize];
    return menu;
}

- (UIMenu *)submenuForButton:(UIButton *)button submenu:(UIMenu *)submenu {
    (void)button;
    return RYGMenuPreservingHierarchy(submenu);
}

@end
