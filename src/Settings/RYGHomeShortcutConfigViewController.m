#import "RYGHomeShortcutConfigViewController.h"
#import "../Utils.h"
#import "../Features/Feed/RYGHomeShortcutCatalog.h"
#import "../UI/RYGPopupChrome.h"
#import "../UI/RYGIcon.h"
#import "../UI/RYGIconBrowserViewController.h"

#pragma mark - Persistence

static NSMutableArray<NSMutableDictionary *> *rygLoadOrderedActions(void) {
	NSArray *stored = [RYGUtils getArrayPref:kRYGHomeShortcutActionsPrefKey];
	NSMutableArray<NSMutableDictionary *> *out = NSMutableArray.array;
	NSMutableSet<NSString *> *seen = NSMutableSet.set;

	for (NSDictionary *row in stored) {
		if (![row isKindOfClass:NSDictionary.class]) continue;

		NSString *aid = row[@"id"];
		if (![aid isKindOfClass:NSString.class] || !aid.length) continue;
		if (![RYGHomeShortcutCatalog actionForID:aid]) continue;
		if ([seen containsObject:aid]) continue;

		[seen addObject:aid];
		[out addObject:[@{@"id": aid, @"enabled": @([row[@"enabled"] boolValue])} mutableCopy]];
	}

	for (RYGHomeShortcutAction *action in [RYGHomeShortcutCatalog allActions]) {
		if ([seen containsObject:action.actionID]) continue;

		[seen addObject:action.actionID];
		[out addObject:[@{@"id": action.actionID, @"enabled": @NO} mutableCopy]];
	}

	return out;
}

static void rygSaveOrderedActions(NSArray<NSDictionary *> *actions) {
	[RYGUtils setPref:actions.copy forKey:kRYGHomeShortcutActionsPrefKey];
	[NSNotificationCenter.defaultCenter postNotificationName:RYGHomeShortcutConfigDidChangeNotification object:nil];
}

static NSString *rygCurrentIcon(void) {
	NSString *icon = [RYGUtils getStringPref:kRYGHomeShortcutIconPrefKey];
	return icon.length ? icon : @"auto";
}

static UISwitch *rygSwitch(BOOL on, id target, SEL action) {
	UISwitch *sw = UISwitch.new;
	sw.on = on;
	sw.onTintColor = [RYGUtils RYGColor_Primary];
	[sw addTarget:target action:action forControlEvents:UIControlEventValueChanged];
	return sw;
}

static UITableViewCell *rygCell(UITableViewCellStyle style) {
	UITableViewCell *cell = [[UITableViewCell alloc] initWithStyle:style reuseIdentifier:nil];

	cell.accessoryView = nil;
	cell.accessoryType = UITableViewCellAccessoryNone;
	cell.selectionStyle = UITableViewCellSelectionStyleDefault;
	cell.contentView.alpha = 1.0;
	cell.textLabel.text = nil;
	cell.detailTextLabel.text = nil;
	cell.imageView.image = nil;

	return cell;
}

static UIListContentConfiguration *rygContent(NSString *title, NSString *subtitle) {
	UITableViewCell *cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleDefault reuseIdentifier:nil];
	UIListContentConfiguration *config = cell.defaultContentConfiguration;

	config.text = title ?: @"";
	config.textProperties.color = UIColor.labelColor;

	if (subtitle.length) {
		config.secondaryText = subtitle;
		config.secondaryTextProperties.color = UIColor.secondaryLabelColor;
		config.textToSecondaryTextVerticalPadding = 4.5;
	}

	return config;
}

static void rygApplyIcon(UIListContentConfiguration *config, NSString *symbol, UIColor *tint) {
	if (!symbol.length) return;

	UIImage *image = [RYGIcon imageNamed:symbol pointSize:22 weight:UIImageSymbolWeightRegular];
	if (!image) return;

	config.image = image;
	config.imageProperties.tintColor = tint ?: UIColor.labelColor;
	config.imageToTextPadding = 14.0;
}

#pragma mark - Reorder row helpers

static UIImageView *rygIconView(NSString *symbol) {
	UIImageView *view = [[UIImageView alloc] initWithImage:(symbol.length ? [RYGIcon imageNamed:symbol pointSize:22 weight:UIImageSymbolWeightRegular] : nil)];

	view.translatesAutoresizingMaskIntoConstraints = NO;
	view.tintColor = UIColor.labelColor;
	view.contentMode = UIViewContentModeCenter;

	return view;
}

static UILabel *rygTitleLabel(NSString *title) {
	UILabel *label = UILabel.new;

	label.translatesAutoresizingMaskIntoConstraints = NO;
	label.text = title ?: @"";
	label.font = [UIFont preferredFontForTextStyle:UIFontTextStyleBody];
	label.textColor = UIColor.labelColor;

	return label;
}

static void rygInstallActionRow(UITableViewCell *cell, NSString *symbol, NSString *title, UISwitch *sw) {
	cell.selectionStyle = UITableViewCellSelectionStyleNone;
	cell.textLabel.text = nil;
	cell.imageView.image = nil;

	UIImageView *icon = rygIconView(symbol);
	UILabel *titleLabel = rygTitleLabel(title);

	sw.translatesAutoresizingMaskIntoConstraints = NO;

	[cell.contentView addSubview:icon];
	[cell.contentView addSubview:titleLabel];
	[cell.contentView addSubview:sw];

	[NSLayoutConstraint activateConstraints:@[
		[icon.leadingAnchor constraintEqualToAnchor:cell.contentView.layoutMarginsGuide.leadingAnchor],
		[icon.centerYAnchor constraintEqualToAnchor:cell.contentView.centerYAnchor],
		[icon.widthAnchor constraintEqualToConstant:24.0],

		[titleLabel.leadingAnchor constraintEqualToAnchor:icon.trailingAnchor constant:12.0],
		[titleLabel.centerYAnchor constraintEqualToAnchor:cell.contentView.centerYAnchor],
		[titleLabel.trailingAnchor constraintLessThanOrEqualToAnchor:sw.leadingAnchor constant:-12.0],

		[sw.trailingAnchor constraintEqualToAnchor:cell.contentView.layoutMarginsGuide.trailingAnchor],
		[sw.centerYAnchor constraintEqualToAnchor:cell.contentView.centerYAnchor],
	]];
}


#pragma mark - Main config VC

@interface RYGHomeShortcutConfigViewController ()
@property (nonatomic, strong) NSMutableArray<NSMutableDictionary *> *actions;
@end

@implementation RYGHomeShortcutConfigViewController

- (instancetype)init {
	self = [super initWithStyle:UITableViewStyleInsetGrouped];
	if (!self) return nil;

	self.title = RYGLocalized(@"Home shortcut button");

	return self;
}

- (void)viewDidLoad {
	[super viewDidLoad];

	self.view.backgroundColor = [RYGPopupChrome backgroundColor] ?: UIColor.systemGroupedBackgroundColor;
	self.tableView.backgroundColor = self.view.backgroundColor;
	self.actions = rygLoadOrderedActions();
}

- (void)viewWillAppear:(BOOL)animated {
	[super viewWillAppear:animated];
	[self.tableView reloadData];
}

#pragma mark - Sections

- (NSInteger)numberOfSectionsInTableView:(UITableView *)tableView {
	return 2;
}

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section {
	return section == 0 ? 1 : (NSInteger)self.actions.count;
}

- (NSString *)tableView:(UITableView *)tableView titleForHeaderInSection:(NSInteger)section {
	return section == 0 ? RYGLocalized(@"Appearance") : RYGLocalized(@"Actions");
}

- (NSString *)tableView:(UITableView *)tableView titleForFooterInSection:(NSInteger)section {
	if (section == 0) {
		return RYGLocalized(@"Choose the icon shown on the home top bar. Auto uses the selected action icon when only one action is enabled.");
	}

	return RYGLocalized(@"Drag the ≡ handle to reorder. Toggle actions off to hide them. With one action enabled, tapping fires it directly. With two or more, tapping opens a menu.");
}

#pragma mark - Cells

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath {
	return indexPath.section == 0 ? [self iconCell] : [self actionCellForRow:indexPath.row];
}

- (UITableViewCell *)iconCell {
	UITableViewCell *cell = rygCell(UITableViewCellStyleDefault);

	NSString *cur = rygCurrentIcon();
	BOOL isAuto = [cur isEqualToString:@"auto"];
	NSString *symbol = isAuto ? @"ellipsis.circle" : cur;

	UIListContentConfiguration *config = rygContent(RYGLocalized(@"Icon"), isAuto ? RYGLocalized(@"Default") : cur);
	rygApplyIcon(config, symbol, UIColor.labelColor);

	cell.contentConfiguration = config;
	cell.accessoryType = UITableViewCellAccessoryDisclosureIndicator;
	cell.editingAccessoryType = UITableViewCellAccessoryDisclosureIndicator;

	return cell;
}

- (UITableViewCell *)actionCellForRow:(NSInteger)row {
	UITableViewCell *cell = rygCell(UITableViewCellStyleDefault);

	if (row < 0 || row >= (NSInteger)self.actions.count) return cell;

	NSDictionary *rowDict = self.actions[row];
	NSString *aid = rowDict[@"id"];
	RYGHomeShortcutAction *entry = [RYGHomeShortcutCatalog actionForID:aid];

	UISwitch *sw = rygSwitch([rowDict[@"enabled"] boolValue], self, @selector(actionToggleChanged:));
	sw.accessibilityIdentifier = aid;

	rygInstallActionRow(cell, entry.symbol, entry.title ?: aid, sw);

	return cell;
}

#pragma mark - Selection

- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath {
	[tableView deselectRowAtIndexPath:indexPath animated:YES];

	if (indexPath.section == 0 && indexPath.row == 0) {
		RYGIconBrowserViewController *browser =
			[[RYGIconBrowserViewController alloc] initWithTitle:RYGLocalized(@"Icon")
													currentName:rygCurrentIcon()
												   specialTitle:RYGLocalized(@"Default")
													specialIcon:@"ellipsis.circle"
												   specialValue:@"auto"
													 completion:^(NSString *picked) {
				[RYGUtils setPref:picked forKey:kRYGHomeShortcutIconPrefKey];
				[NSNotificationCenter.defaultCenter postNotificationName:RYGHomeShortcutConfigDidChangeNotification object:nil];
			}];
		[self.navigationController pushViewController:browser animated:YES];
	}
}

#pragma mark - Toggles

- (void)actionToggleChanged:(UISwitch *)sender {
	NSString *aid = sender.accessibilityIdentifier;
	if (!aid.length) return;

	for (NSMutableDictionary *row in self.actions) {
		if ([row[@"id"] isEqualToString:aid]) {
			row[@"enabled"] = @(sender.isOn);
			break;
		}
	}

	rygSaveOrderedActions(self.actions);
}

#pragma mark - Reorder

- (BOOL)isReorderableSection:(NSInteger)section {
	return section == 1;
}

- (void)didMoveRowFromIndexPath:(NSIndexPath *)src toIndexPath:(NSIndexPath *)dst {
	if (src.row >= (NSInteger)self.actions.count || dst.row >= (NSInteger)self.actions.count) return;

	NSMutableDictionary *item = self.actions[src.row];
	[self.actions removeObjectAtIndex:src.row];
	[self.actions insertObject:item atIndex:dst.row];

	rygSaveOrderedActions(self.actions);
}

@end