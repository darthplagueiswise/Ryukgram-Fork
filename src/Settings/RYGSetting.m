#import "RYGSetting.h"
#import "../UI/RYGLiquidGlass.h"

@interface RYGSetting ()

@property (nonatomic, readwrite) RYGTableCell type;

- (instancetype)initWithType:(RYGTableCell)type NS_DESIGNATED_INITIALIZER;
- (instancetype)init NS_UNAVAILABLE;

@end

///

@implementation RYGSetting

// MARK: - - initWithType

- (instancetype)initWithType:(RYGTableCell)type {
	self = [super init];

	if (self) {
		self.type = type;
	}

	return self;
}


// MARK: - + staticCellWithTitle

+ (instancetype)staticCellWithTitle:(NSString *)title
						   subtitle:(NSString *)subtitle
							   icon:(nullable RYGSymbol *)icon
{
	RYGSetting *setting = [[self alloc] initWithType:RYGTableCellStatic];

	setting.title = title;
	setting.subtitle = subtitle;
	setting.icon = icon;

	return setting;
}

// MARK: - + linkCellWithTitle

+ (instancetype)linkCellWithTitle:(NSString *)title
						 subtitle:(NSString *)subtitle
							 icon:(nullable RYGSymbol *)icon
							  url:(NSString *)url
{
	RYGSetting *setting = [[self alloc] initWithType:RYGTableCellLink];

	setting.title = title;
	setting.subtitle = subtitle;
	setting.icon = icon;
	setting.url = [NSURL URLWithString:url];

	return setting;
}

+ (instancetype)linkCellWithTitle:(NSString *)title
						 subtitle:(NSString *)subtitle
						 imageUrl:(NSString *)imageUrl
							  url:(NSString *)url
{
	RYGSetting *setting = [[self alloc] initWithType:RYGTableCellLink];

	setting.title = title;
	setting.subtitle = subtitle;

	setting.imageUrl = [NSURL URLWithString:imageUrl];
	setting.url = [NSURL URLWithString:url];

	return setting;
}

// MARK: - + switchCellWithTitle

+ (instancetype)switchCellWithTitle:(NSString *)title
						   subtitle:(NSString *)subtitle
						defaultsKey:(NSString *)defaultsKey
{
	RYGSetting *setting = [[self alloc] initWithType:RYGTableCellSwitch];

	setting.title = title;
	setting.subtitle = subtitle;
	setting.defaultsKey = defaultsKey;

	return setting;
}

+ (instancetype)switchCellWithTitle:(NSString *)title
						   subtitle:(NSString *)subtitle
						defaultsKey:(NSString *)defaultsKey
					requiresRestart:(BOOL)requiresRestart
{
	RYGSetting *setting = [[self alloc] initWithType:RYGTableCellSwitch];

	setting.title = title;
	setting.subtitle = subtitle;
	setting.defaultsKey = defaultsKey;
	setting.requiresRestart = requiresRestart;

	return setting;
}

+ (instancetype)switchCellWithTitle:(NSString *)title
						   subtitle:(nullable NSString *)subtitle
							  value:(BOOL (^)(void))value
							 action:(void (^)(BOOL on))action
{
	RYGSetting *setting = [[self alloc] initWithType:RYGTableCellSwitch];

	setting.title = title;
	setting.subtitle = subtitle;
	setting.switchValueProvider = value;
	setting.switchAction = action;

	return setting;
}

+ (instancetype)customCellWithHeight:(CGFloat)height
							provider:(UITableViewCell *(^)(UITableView *tableView, NSIndexPath *indexPath))provider
{
	RYGSetting *setting = [[self alloc] initWithType:RYGTableCellCustom];

	setting.customHeight = height;
	setting.customCellProvider = provider;

	return setting;
}

// MARK: - + stepperCellWithTitle

+ (instancetype)stepperCellWithTitle:(NSString *)title
							subtitle:(NSString *)subtitle
						 defaultsKey:(NSString *)defaultsKey
								 min:(double)min
								 max:(double)max
								step:(double)step
							   label:(NSString *)label
					   singularLabel:(NSString *)singularLabel
{
	RYGSetting *setting = [[self alloc] initWithType:RYGTableCellStepper];

	setting.title = title;
	setting.subtitle = subtitle;
	setting.defaultsKey = defaultsKey;

	setting.min = min;
	setting.max = max;
	setting.step = step;
	setting.label = label;
	setting.singularLabel = singularLabel;

	return setting;
}

// MARK: - + actionCellWithTitle

+ (instancetype)actionCellWithTitle:(NSString *)title
							  color:(UIColor *)color
							 action:(void (^)(void))action
{
	RYGSetting *setting = [[self alloc] initWithType:RYGTableCellButton];

	setting.title = title;
	setting.subtitle = @"";
	setting.action = action;
	setting.titleColor = color;
	setting.centeredTitle = YES;
	setting.hidesDisclosureIndicator = YES;

	return setting;
}

// MARK: - + buttonCellWithTitle

+ (instancetype)buttonCellWithTitle:(NSString *)title
						   subtitle:(NSString *)subtitle
							   icon:(nullable RYGSymbol *)icon
							 action:(void (^)(void))action
{
	RYGSetting *setting = [[self alloc] initWithType:RYGTableCellButton];

	setting.title = title;
	setting.subtitle = subtitle;

	setting.icon = icon;
	setting.action = action;

	return setting;
}

// MARK: - + colorCellWithTitle

+ (instancetype)colorCellWithTitle:(NSString *)title
						  subtitle:(NSString *)subtitle
					   defaultsKey:(NSString *)defaultsKey
					  defaultColor:(nullable UIColor *)defaultColor
{
	RYGSetting *setting = [[self alloc] initWithType:RYGTableCellColor];

	setting.title = title;
	setting.subtitle = subtitle;
	setting.defaultsKey = defaultsKey;
	setting.defaultColor = defaultColor;

	return setting;
}

# pragma mark + menuCellWithTitle

+ (instancetype)menuCellWithTitle:(NSString *)title
						 subtitle:(NSString *)subtitle
							 menu:(UIMenu *)menu
{
	RYGSetting *setting = [[self alloc] initWithType:RYGTableCellMenu];

	setting.title = title;
	setting.subtitle = subtitle;

	setting.baseMenu = menu;

	return setting;
}

// MARK: - + navigationCellWithTitle

+ (instancetype)navigationCellWithTitle:(NSString *)title
							   subtitle:(NSString *)subtitle
								   icon:(nullable RYGSymbol *)icon
							navSections:(NSArray *)navSections
{
	RYGSetting *setting = [[self alloc] initWithType:RYGTableCellNavigation];

	setting.title = title;
	setting.subtitle = subtitle;

	setting.icon = icon;
	setting.navSections = navSections;

	return setting;
}

+ (instancetype)navigationCellWithTitle:(NSString *)title
							   subtitle:(NSString *)subtitle
								   icon:(nullable RYGSymbol *)icon
						 viewController:(UIViewController *)viewController
{
	RYGSetting *setting = [[self alloc] initWithType:RYGTableCellNavigation];

	setting.title = title;
	setting.subtitle = subtitle;

	setting.icon = icon;
	setting.navViewController = viewController;

	return setting;
}


// MARK: -  Instance methods

- (UIMenu *)menuForButton:(UIButton *)button {
	UIMenu *menu = [self submenuForButton:button submenu:self.baseMenu];
	// The selected value belongs inside the menu source control. On iOS 26+
	// this turns the accessory into a native Liquid Glass capsule rather than a
	// bare system-blue title floating over the cell's primary/secondary text.
	// Configure after submenuForButton: has resolved and assigned the selected
	// title so the glass configuration preserves the real value.
	if (button) {
		button.showsMenuAsPrimaryAction = YES;
		RYGLiquidGlassConfigureButton(button, NO);
	}
	return menu;
}

- (UIMenu *)submenuForButton:(UIButton *)button submenu:(UIMenu*)submenu {
	NSMutableArray<UIMenuElement *> *children = [NSMutableArray array];
	NSString *selectedChildTitle = nil;

	for (id obj in submenu.children) {
		// Handle recursive submenus
		if ([obj isKindOfClass:[UIMenu class]]) {
			[children addObject:[self submenuForButton:button submenu:(UIMenu *)obj]];
			continue;
		}
		else if (![obj isKindOfClass:[UICommand class]]) {
			continue;
		}

		UICommand *child = obj;

		NSString *saved = [[NSUserDefaults standardUserDefaults] stringForKey:child.propertyList[@"defaultsKey"]];

		UICommand *command = [UICommand commandWithTitle:child.title
												   image:child.image
												  action:child.action
											propertyList:child.propertyList];

		if ([child.propertyList[@"value"] isEqualToString:saved]) {
			command.state = YES;
			selectedChildTitle = command.title;

			// noTitle: submenu entries keyed to another pref must not clobber
			// the button's value title.
			if (![child.propertyList[@"noTitle"] boolValue])
				[button setTitle:command.title forState:UIControlStateNormal];
		}
		else {
			command.state = NO;
		}

		[children addObject:command];
	}

	// Titled submenus show their current selection inline (e.g. Background mirror).
	NSString *title = submenu.title;
	if (title.length && selectedChildTitle.length)
		title = [NSString stringWithFormat:@"%@: %@", submenu.title, selectedChildTitle];

	return [UIMenu menuWithTitle:title image:submenu.image identifier:nil options:submenu.options children:children];
}

@end
