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
+ (instancetype)actionCellWithTitle:(NSString *)title color:(UIColor *)color action:(void (^)(void))action { RYGSetting *setting = [[self alloc] initWithType:RYGTableCellButton]; setting.title = title; setting.subtitle = nil; setting.action = action; setting.titleColor = color; setting.centeredTitle = YES; setting.hidesDisclosureIndicator = YES; return setting; }
+ (instancetype)buttonCellWithTitle:(NSString *)title subtitle:(nullable NSString *)subtitle icon:(nullable RYGSymbol *)icon action:(void (^)(void))action { RYGSetting *setting = [[self alloc] initWithType:RYGTableCellButton]; setting.title = title; setting.subtitle = subtitle; setting.icon = icon; setting.action = action; return setting; }
+ (instancetype)colorCellWithTitle:(NSString *)title subtitle:(nullable NSString *)subtitle defaultsKey:(NSString *)defaultsKey defaultColor:(nullable UIColor *)defaultColor { RYGSetting *setting = [[self alloc] initWithType:RYGTableCellColor]; setting.title = title; setting.subtitle = subtitle; setting.defaultsKey = defaultsKey; setting.defaultColor = defaultColor; return setting; }
+ (instancetype)menuCellWithTitle:(NSString *)title subtitle:(nullable NSString *)subtitle menu:(UIMenu *)menu { RYGSetting *setting = [[self alloc] initWithType:RYGTableCellMenu]; setting.title = title; setting.subtitle = subtitle; setting.baseMenu = menu; return setting; }
+ (instancetype)navigationCellWithTitle:(NSString *)title subtitle:(nullable NSString *)subtitle icon:(nullable RYGSymbol *)icon navSections:(NSArray *)navSections { RYGSetting *setting = [[self alloc] initWithType:RYGTableCellNavigation]; setting.title = title; setting.subtitle = subtitle; setting.icon = icon; setting.navSections = navSections; return setting; }
+ (instancetype)navigationCellWithTitle:(NSString *)title subtitle:(nullable NSString *)subtitle icon:(nullable RYGSymbol *)icon viewController:(UIViewController *)viewController { RYGSetting *setting = [[self alloc] initWithType:RYGTableCellNavigation]; setting.title = title; setting.subtitle = subtitle; setting.icon = icon; setting.navViewController = viewController; return setting; }

static NSDictionary *RYGMenuPropertyList(UIMenuElement *element) {
    if ([element isKindOfClass:UICommand.class]) {
        id value = ((UICommand *)element).propertyList;
        return [value isKindOfClass:NSDictionary.class] ? value : nil;
    }
    return nil;
}

static NSString *RYGSelectedTitleForMenu(UIMenu *menu) {
    for (UIMenuElement *element in menu.children) {
        if ([element isKindOfClass:UIMenu.class]) {
            NSString *nested = RYGSelectedTitleForMenu((UIMenu *)element);
            if (nested.length) return nested;
            continue;
        }

        NSDictionary *plist = RYGMenuPropertyList(element);
        BOOL noTitle = [plist[@"noTitle"] boolValue];
        if ([element isKindOfClass:UICommand.class]) {
            UICommand *command = (UICommand *)element;
            NSString *saved = [NSUserDefaults.standardUserDefaults stringForKey:plist[@"defaultsKey"]];
            BOOL selected = command.state == UIMenuElementStateOn;
            if (plist[@"value"] && plist[@"defaultsKey"]) selected = [plist[@"value"] isEqualToString:saved];
            if (selected && !noTitle && command.title.length) return command.title;
        } else if ([element isKindOfClass:UIAction.class]) {
            UIAction *action = (UIAction *)element;
            if (action.state == UIMenuElementStateOn && !noTitle && action.title.length) return action.title;
        }
    }
    return nil;
}

static void RYGUpdateMenuButtonPresentation(UIButton *button) {
    if (!button) return;
    NSString *selectedTitle = RYGSelectedTitleForMenu(button.menu);
    NSString *title = selectedTitle.length ? selectedTitle : @"•••";

    UIButtonConfiguration *configuration = button.configuration;
    if (configuration) {
        configuration.title = title;
        // Menu selectors are labels/choices, not blue link-style actions.
        // Keep UIKit's Glass material but use semantic label foreground.
        configuration.baseForegroundColor = UIColor.labelColor;
        if (@available(iOS 26.0, *)) [configuration setDefaultContentInsets];
        button.configuration = configuration;
    } else {
        [button setTitle:title forState:UIControlStateNormal];
        [button setTitleColor:UIColor.labelColor forState:UIControlStateNormal];
    }
    [button invalidateIntrinsicContentSize];
}

- (UIMenu *)menuForButton:(UIButton *)button {
    UIMenu *menu = [self submenuForButton:nil submenu:self.baseMenu];
    if (!button) return menu;

    button.menu = menu;
    button.showsMenuAsPrimaryAction = YES;
    button.changesSelectionAsPrimaryAction = YES;
    button.tintColor = UIColor.labelColor;

    // Configure only the real menu-source button. UIKit owns the source size,
    // expanded menu geometry and closed→expanded Liquid Glass morph.
    RYGLiquidGlassConfigureButton(button, NO);
    button.configurationUpdateHandler = ^(UIButton *source) {
        RYGUpdateMenuButtonPresentation(source);
    };
    RYGUpdateMenuButtonPresentation(button);
    [button setNeedsUpdateConfiguration];
    return menu;
}

- (UIMenu *)submenuForButton:(UIButton *)button submenu:(UIMenu *)submenu {
    (void)button;
    NSMutableArray<UIMenuElement *> *children = [NSMutableArray arrayWithCapacity:submenu.children.count];
    for (UIMenuElement *element in submenu.children) {
        if ([element isKindOfClass:UIMenu.class]) {
            [children addObject:[self submenuForButton:nil submenu:(UIMenu *)element]];
            continue;
        }

        if ([element isKindOfClass:UICommand.class]) {
            UICommand *child = (UICommand *)element;
            UICommand *command = [UICommand commandWithTitle:child.title image:child.image action:child.action propertyList:child.propertyList];
            NSDictionary *plist = [child.propertyList isKindOfClass:NSDictionary.class] ? child.propertyList : nil;
            NSString *saved = [NSUserDefaults.standardUserDefaults stringForKey:plist[@"defaultsKey"]];
            if (plist[@"value"] && plist[@"defaultsKey"]) command.state = [plist[@"value"] isEqualToString:saved] ? UIMenuElementStateOn : UIMenuElementStateOff;
            else command.state = child.state;
            command.attributes = child.attributes;
            [children addObject:command];
            continue;
        }

        // UIAction owns its handler/state. Preserve the original UIKit element;
        // changesSelectionAsPrimaryAction updates its single-selection state and
        // the button's configurationUpdateHandler mirrors that state in the pill.
        [children addObject:element];
    }

    UIMenuOptions options = submenu.options | UIMenuOptionsSingleSelection;
    return [UIMenu menuWithTitle:submenu.title
                           image:submenu.image
                      identifier:submenu.identifier
                         options:options
                        children:children];
}

@end
