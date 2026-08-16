#import "RYGActionMenuConfigViewController.h"
#import "../ActionButton/RYGActionMenuConfig.h"
#import "../UI/RYGIcon.h"
#import "../UI/RYGPopupChrome.h"
#import "../Utils.h"

#pragma mark - Shared helpers

static UIImage *rygLoadIcon(NSString *name) {
	if (!name.length) return nil;
	return [RYGIcon menuImageNamed:name pointSize:20] ?: [UIImage systemImageNamed:name];
}

static UITableViewCell *rygCell(void) {
	return [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleDefault reuseIdentifier:nil];
}

static UIListContentConfiguration *rygContent(UITableViewCell *cell, NSString *title, NSString *subtitle) {
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

static void rygApplyIcon(UIListContentConfiguration *config, NSString *name, UIColor *tint) {
	UIImage *image = rygLoadIcon(name);
	if (!image) return;
	config.image = image;
	config.imageProperties.tintColor = tint ?: UIColor.labelColor;
	config.imageToTextPadding = 14.0;
}

static UISwitch *rygSwitch(BOOL on, id target, SEL action) {
	UISwitch *sw = UISwitch.new;
	sw.on = on;
	sw.onTintColor = [RYGUtils RYGColor_Primary];
	[sw addTarget:target action:action forControlEvents:UIControlEventValueChanged];
	return sw;
}

static UIImageView *rygSymbol(UIImage *image, UIColor *tint) {
	UIImageView *view = [[UIImageView alloc] initWithImage:image];
	view.translatesAutoresizingMaskIntoConstraints = NO;
	view.tintColor = tint;
	view.contentMode = UIViewContentModeCenter;
	return view;
}

static UIColor *rygBackground(void) {
	return [RYGPopupChrome backgroundColor] ?: UIColor.systemGroupedBackgroundColor;
}

static void rygInstallReorderRow(UITableViewCell *cell, NSString *iconName, NSString *title, UIView *accessory) {
	cell.selectionStyle = UITableViewCellSelectionStyleNone;

	UIImageView *icon = rygSymbol(rygLoadIcon(iconName), UIColor.labelColor);

	UILabel *label = UILabel.new;
	label.translatesAutoresizingMaskIntoConstraints = NO;
	label.text = title ?: @"";
	label.font = [UIFont preferredFontForTextStyle:UIFontTextStyleBody];
	label.textColor = UIColor.labelColor;
	label.numberOfLines = 1;

	UIView *cv = cell.contentView;
	[cv addSubview:icon];
	[cv addSubview:label];
	if (accessory) {
		accessory.translatesAutoresizingMaskIntoConstraints = NO;
		[cv addSubview:accessory];
	}

	UILayoutGuide *m = cv.layoutMarginsGuide;
	NSMutableArray *cs = [@[
		[icon.leadingAnchor constraintEqualToAnchor:m.leadingAnchor],
		[icon.centerYAnchor constraintEqualToAnchor:cv.centerYAnchor],
		[icon.widthAnchor constraintEqualToConstant:24.0],
		[label.leadingAnchor constraintEqualToAnchor:icon.trailingAnchor constant:12.0],
		[label.centerYAnchor constraintEqualToAnchor:cv.centerYAnchor],
	] mutableCopy];

	if (accessory) {
		[cs addObjectsFromArray:@[
			[accessory.trailingAnchor constraintEqualToAnchor:m.trailingAnchor],
			[accessory.centerYAnchor constraintEqualToAnchor:cv.centerYAnchor],
			[label.trailingAnchor constraintLessThanOrEqualToAnchor:accessory.leadingAnchor constant:-12.0],
		]];
	} else {
		[cs addObject:[label.trailingAnchor constraintLessThanOrEqualToAnchor:m.trailingAnchor]];
	}

	[NSLayoutConstraint activateConstraints:cs];
}

#pragma mark - Section reorder VC

@interface RYGSectionReorderViewController : RYGReorderTableViewController
- (instancetype)initWithConfig:(RYGActionMenuConfig *)config;
@end

@interface RYGSectionReorderViewController ()
@property (nonatomic, strong) RYGActionMenuConfig *config;
@end

@implementation RYGSectionReorderViewController

- (instancetype)initWithConfig:(RYGActionMenuConfig *)config {
	if (!(self = [super initWithStyle:UITableViewStyleInsetGrouped])) return nil;
	_config = config;
	self.title = RYGLocalized(@"Reorder sections");
	return self;
}

- (void)viewDidLoad {
	[super viewDidLoad];
	UIColor *bg = rygBackground();
	self.view.backgroundColor = bg;
	self.tableView.backgroundColor = bg;
}

- (NSInteger)numberOfSectionsInTableView:(UITableView *)tv { return 1; }
- (NSInteger)tableView:(UITableView *)tv numberOfRowsInSection:(NSInteger)s { return self.config.sections.count; }
- (NSString *)tableView:(UITableView *)tv titleForFooterInSection:(NSInteger)s { return RYGLocalized(@"Drag the ≡ handle to reorder sections."); }

- (UITableViewCell *)tableView:(UITableView *)tv cellForRowAtIndexPath:(NSIndexPath *)ip {
	UITableViewCell *cell = rygCell();
	RYGActionConfigSection *s = self.config.sections[ip.row];
	rygInstallReorderRow(cell, s.iconSF.length ? s.iconSF : @"folder", s.title.length ? s.title : s.identifier, nil);
	return cell;
}

- (BOOL)isReorderableSection:(NSInteger)section {
	return section == 0;
}

- (void)didMoveRowFromIndexPath:(NSIndexPath *)src toIndexPath:(NSIndexPath *)dst {
	[self.config moveSectionFromIndex:src.row toIndex:dst.row];
	[self.config save];
}

@end

#pragma mark - Default tap picker

@interface RYGDefaultTapPickerViewController : UITableViewController
- (instancetype)initWithConfig:(RYGActionMenuConfig *)config;
@end

@interface RYGDefaultTapPickerViewController ()
@property (nonatomic, strong) RYGActionMenuConfig *config;
@property (nonatomic, copy) NSArray<RYGActionDescriptor *> *eligible;
@end

@implementation RYGDefaultTapPickerViewController

- (instancetype)initWithConfig:(RYGActionMenuConfig *)config {
	if (!(self = [super initWithStyle:UITableViewStyleInsetGrouped])) return nil;
	_config = config;
	NSMutableArray *items = NSMutableArray.array;
	for (RYGActionDescriptor *d in [RYGActionCatalog descriptorsForSource:config.source])
		if (d.eligibleForDefaultTap) [items addObject:d];
	_eligible = items.copy;
	self.title = RYGLocalized(@"Default tap action");
	return self;
}

- (void)viewDidLoad {
	[super viewDidLoad];
	UIColor *bg = rygBackground();
	self.view.backgroundColor = bg;
	self.tableView.backgroundColor = bg;
}

- (NSInteger)numberOfSectionsInTableView:(UITableView *)tv { return 1; }
- (NSInteger)tableView:(UITableView *)tv numberOfRowsInSection:(NSInteger)s { return self.eligible.count + 1; }
- (NSString *)tableView:(UITableView *)tv titleForFooterInSection:(NSInteger)s { return RYGLocalized(@"What happens on a single tap. Long-press always opens the full menu."); }

- (UITableViewCell *)tableView:(UITableView *)tv cellForRowAtIndexPath:(NSIndexPath *)ip {
	UITableViewCell *cell = rygCell();
	BOOL isMenu = ip.row == 0;
	RYGActionDescriptor *d = isMenu ? nil : self.eligible[ip.row - 1];

	NSString *currentID = self.config.defaultTap.length ? self.config.defaultTap : @"menu";
	NSString *actionID = isMenu ? @"menu" : d.identifier;

	UIListContentConfiguration *config = rygContent(cell, isMenu ? RYGLocalized(@"Open menu") : d.title, nil);
	rygApplyIcon(config, isMenu ? @"line.3.horizontal" : d.iconSF, UIColor.labelColor);
	cell.contentConfiguration = config;
	cell.accessoryType = [actionID isEqualToString:currentID] ? UITableViewCellAccessoryCheckmark : UITableViewCellAccessoryNone;
	return cell;
}

- (void)tableView:(UITableView *)tv didSelectRowAtIndexPath:(NSIndexPath *)ip {
	[tv deselectRowAtIndexPath:ip animated:YES];
	self.config.defaultTap = ip.row == 0 ? @"menu" : self.eligible[ip.row - 1].identifier;
	[self.config save];
	[tv reloadData];
}

@end

#pragma mark - Main configure VC

typedef NS_ENUM(NSInteger, RYGBehaviorRow) {
	RYGBehaviorRowShowDate = 0,
	RYGBehaviorRowDefaultTap,
	RYGBehaviorRowReorder,
	RYGBehaviorRowReset,
};

@interface RYGActionMenuConfigViewController ()
@property (nonatomic, assign) RYGActionSource source;
@property (nonatomic, strong) RYGActionMenuConfig *config;
@property (nonatomic, assign) BOOL supportsDate;
@end

@implementation RYGActionMenuConfigViewController

- (instancetype)initForSource:(RYGActionSource)source {
	if (!(self = [super initWithStyle:UITableViewStyleInsetGrouped])) return nil;
	_source = source;
	_config = [RYGActionMenuConfig configForSource:source];
	_supportsDate = [RYGActionCatalog sourceSupportsDate:source];
	self.title = [NSString stringWithFormat:RYGLocalized(@"Configure: %@"), [RYGActionCatalog displayNameForSource:source]];
	return self;
}

- (void)viewDidLoad {
	[super viewDidLoad];
	UIColor *bg = rygBackground();
	self.view.backgroundColor = bg;
	self.tableView.backgroundColor = bg;
}

- (void)viewWillAppear:(BOOL)animated {
	[super viewWillAppear:animated];
	[self.tableView reloadData];
}

#pragma mark - Indexing

- (BOOL)isBehaviorSection:(NSInteger)section { return section == 0; }

- (RYGActionConfigSection *)configSectionForUISection:(NSInteger)section {
	NSInteger idx = section - 1;
	return (idx < 0 || idx >= (NSInteger)self.config.sections.count) ? nil : self.config.sections[idx];
}

- (RYGBehaviorRow)behaviorRowForIndex:(NSInteger)index {
	return (RYGBehaviorRow)(self.supportsDate ? index : index + 1);
}

#pragma mark - Sections

- (NSInteger)numberOfSectionsInTableView:(UITableView *)tv {
	return 1 + (NSInteger)self.config.sections.count;
}

- (NSInteger)tableView:(UITableView *)tv numberOfRowsInSection:(NSInteger)section {
	if ([self isBehaviorSection:section]) return self.supportsDate ? 4 : 3;
	return 1 + (NSInteger)[self configSectionForUISection:section].actionIDs.count;
}

- (NSString *)tableView:(UITableView *)tv titleForHeaderInSection:(NSInteger)section {
	if ([self isBehaviorSection:section]) return RYGLocalized(@"Behavior");
	RYGActionConfigSection *cs = [self configSectionForUISection:section];
	return cs.title.length ? cs.title : cs.identifier;
}

- (NSString *)tableView:(UITableView *)tv titleForFooterInSection:(NSInteger)section {
	return section == 1 ? RYGLocalized(@"Drag the ≡ handle to reorder. Toggle a row off to hide it from the menu. Mark a section as a submenu to collapse its actions behind a single entry.") : nil;
}

#pragma mark - Cells

- (UITableViewCell *)tableView:(UITableView *)tv cellForRowAtIndexPath:(NSIndexPath *)ip {
	if ([self isBehaviorSection:ip.section]) return [self behaviorCellForRow:ip.row];
	return [self actionCellForRow:ip.row section:[self configSectionForUISection:ip.section]];
}

- (UITableViewCell *)behaviorCellForRow:(NSInteger)row {
	UITableViewCell *cell = rygCell();
	UIListContentConfiguration *config = nil;

	switch ([self behaviorRowForIndex:row]) {
		case RYGBehaviorRowShowDate:
			config = rygContent(cell, RYGLocalized(@"Show date"), nil);
			rygApplyIcon(config, @"calendar", UIColor.labelColor);
			cell.accessoryView = rygSwitch(self.config.showDate, self, @selector(showDateChanged:));
			cell.selectionStyle = UITableViewCellSelectionStyleNone;
			break;

		case RYGBehaviorRowDefaultTap: {
			RYGActionDescriptor *d = [RYGActionCatalog descriptorForActionID:self.config.defaultTap source:self.source];
			config = rygContent(cell, RYGLocalized(@"Default tap action"), d ? d.title : RYGLocalized(@"Open menu"));
			rygApplyIcon(config, @"hand.tap", UIColor.labelColor);
			cell.accessoryType = UITableViewCellAccessoryDisclosureIndicator;
			break;
		}

		case RYGBehaviorRowReorder:
			config = rygContent(cell, RYGLocalized(@"Reorder sections"), nil);
			rygApplyIcon(config, @"arrow.up.arrow.down", UIColor.labelColor);
			cell.accessoryType = UITableViewCellAccessoryDisclosureIndicator;
			break;

		case RYGBehaviorRowReset: {
			config = rygContent(cell, RYGLocalized(@"Reset to defaults"), nil);
			config.textProperties.color = UIColor.systemRedColor;
			config.textProperties.alignment = UIListContentTextAlignmentCenter;
			break;
		}
	}

	cell.contentConfiguration = config;
	// Plain accessories hide while the table is in (permanent) editing mode.
	cell.editingAccessoryView = cell.accessoryView;
	cell.editingAccessoryType = cell.accessoryType;
	return cell;
}

- (UITableViewCell *)actionCellForRow:(NSInteger)row section:(RYGActionConfigSection *)section {
	UITableViewCell *cell = rygCell();
	if (!section) return cell;

	if (row == 0) {
		UIListContentConfiguration *config = rygContent(cell, RYGLocalized(@"Show as submenu"), RYGLocalized(@"Collapse this section's actions behind a single entry"));
		rygApplyIcon(config, section.iconSF.length ? section.iconSF : @"folder", UIColor.labelColor);

		UISwitch *sw = rygSwitch(section.collapsible, self, @selector(collapsibleChanged:));
		sw.tag = (NSInteger)[self.config.sections indexOfObject:section];

		cell.contentConfiguration = config;
		cell.accessoryView = sw;
		cell.editingAccessoryView = sw;
		cell.selectionStyle = UITableViewCellSelectionStyleNone;
		return cell;
	}

	NSInteger actionIndex = row - 1;
	if (actionIndex < 0 || actionIndex >= (NSInteger)section.actionIDs.count) return cell;

	NSString *actionID = section.actionIDs[actionIndex];
	RYGActionDescriptor *d = [RYGActionCatalog descriptorForActionID:actionID source:self.source];

	UISwitch *sw = rygSwitch(![self.config isActionDisabled:actionID], self, @selector(actionToggleChanged:));
	sw.accessibilityIdentifier = actionID;

	rygInstallReorderRow(cell, d.iconSF, d ? d.title : actionID, sw);
	return cell;
}

#pragma mark - Selection

- (void)tableView:(UITableView *)tv didSelectRowAtIndexPath:(NSIndexPath *)ip {
	[tv deselectRowAtIndexPath:ip animated:YES];
	if (![self isBehaviorSection:ip.section]) return;

	switch ([self behaviorRowForIndex:ip.row]) {
		case RYGBehaviorRowShowDate:
			return;
		case RYGBehaviorRowDefaultTap:
			[self.navigationController pushViewController:[[RYGDefaultTapPickerViewController alloc] initWithConfig:self.config] animated:YES];
			return;
		case RYGBehaviorRowReorder:
			[self.navigationController pushViewController:[[RYGSectionReorderViewController alloc] initWithConfig:self.config] animated:YES];
			return;
		case RYGBehaviorRowReset:
			[self presentResetConfirmation];
			return;
	}
}

- (void)presentResetConfirmation {
	UIAlertController *alert = [UIAlertController alertControllerWithTitle:RYGLocalized(@"Reset to defaults")
																   message:RYGLocalized(@"This will restore the default sections, order, and toggles for this menu.")
															preferredStyle:UIAlertControllerStyleAlert];
	[alert addAction:[UIAlertAction actionWithTitle:RYGLocalized(@"Cancel") style:UIAlertActionStyleCancel handler:nil]];

	__weak typeof(self) weakSelf = self;
	[alert addAction:[UIAlertAction actionWithTitle:RYGLocalized(@"Reset") style:UIAlertActionStyleDestructive handler:^(__unused UIAlertAction *a) {
		__strong typeof(weakSelf) self = weakSelf;
		if (!self) return;
		[self.config resetToDefaults];
		[self.tableView reloadData];
	}]];

	[self presentViewController:alert animated:YES completion:nil];
}

#pragma mark - Reorder

- (BOOL)isReorderableSection:(NSInteger)section {
	return ![self isBehaviorSection:section] && [self configSectionForUISection:section] != nil;
}

// Row 0 of every action section is the "Show as submenu" toggle.
- (NSInteger)firstReorderableRowInSection:(NSInteger)section {
	return 1;
}

- (void)didMoveRowFromIndexPath:(NSIndexPath *)src toIndexPath:(NSIndexPath *)dst {
	RYGActionConfigSection *srcSection = [self configSectionForUISection:src.section];
	RYGActionConfigSection *dstSection = [self configSectionForUISection:dst.section];
	NSInteger srcIndex = src.row - 1;
	NSInteger dstIndex = dst.row - 1;
	if (!srcSection || !dstSection || srcIndex < 0 || srcIndex >= (NSInteger)srcSection.actionIDs.count) return;

	NSString *actionID = srcSection.actionIDs[srcIndex];
	if (srcSection == dstSection) {
		[self.config moveActionInSection:srcSection fromIndex:srcIndex toIndex:dstIndex];
	} else {
		[self.config moveActionID:actionID toSection:dstSection index:dstIndex];
	}

	[self.config save];
}

#pragma mark - Toggles

- (void)showDateChanged:(UISwitch *)sender {
	self.config.showDate = sender.isOn;
	[self.config save];
}

- (void)collapsibleChanged:(UISwitch *)sender {
	NSInteger idx = sender.tag;
	if (idx < 0 || idx >= (NSInteger)self.config.sections.count) return;
	[self.config setSection:self.config.sections[idx] collapsible:sender.isOn];
	[self.config save];
}

- (void)actionToggleChanged:(UISwitch *)sender {
	NSString *actionID = sender.accessibilityIdentifier;
	if (!actionID.length) return;
	[self.config setAction:actionID disabled:!sender.isOn];
	[self.config save];
}

@end