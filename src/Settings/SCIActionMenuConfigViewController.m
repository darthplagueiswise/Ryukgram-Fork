#import "SCIActionMenuConfigViewController.h"
#import "GlassUI/SCIAdaptiveGlass.h"
#import "../ActionButton/SCIActionMenuConfig.h"
#import "../UI/SCIIcon.h"
#import "../UI/SCIPopupChrome.h"
#import "../Utils.h"

#pragma mark - Shared helpers

static UIImage *sciLoadIcon(NSString *name) {
	if (!name.length) return nil;
	return [SCIIcon sfImageNamed:name pointSize:18] ?: [UIImage systemImageNamed:name];
}

static UITableViewCell *sciCell(void) {
	return [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleDefault reuseIdentifier:nil];
}

static UIListContentConfiguration *sciContent(UITableViewCell *cell, NSString *title, NSString *subtitle) {
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

static void sciApplyIcon(UIListContentConfiguration *config, NSString *name, UIColor *tint) {
	UIImage *image = sciLoadIcon(name);
	if (!image) return;
	config.image = image;
	config.imageProperties.tintColor = tint ?: UIColor.labelColor;
	config.imageToTextPadding = 14.0;
}

static UISwitch *sciSwitch(BOOL on, id target, SEL action) {
	UISwitch *sw = UISwitch.new;
	sw.on = on;
	sw.onTintColor = [SCIUtils SCIColor_Primary];
	[sw addTarget:target action:action forControlEvents:UIControlEventValueChanged];
	return sw;
}

static UIImageView *sciSymbol(UIImage *image, UIColor *tint) {
	UIImageView *view = [[UIImageView alloc] initWithImage:image];
	view.translatesAutoresizingMaskIntoConstraints = NO;
	view.tintColor = tint;
	view.contentMode = UIViewContentModeCenter;
	return view;
}

static UIColor *sciBackground(void) {
	return SCIGlassBackdropColor();
}

static void sciInstallReorderRow(UITableViewCell *cell, NSString *iconName, NSString *title, UIView *accessory) {
	cell.selectionStyle = UITableViewCellSelectionStyleNone;

	UIImageView *grip = sciSymbol([UIImage systemImageNamed:@"line.3.horizontal"], UIColor.tertiaryLabelColor);
	UIImageView *icon = sciSymbol(sciLoadIcon(iconName), UIColor.labelColor);

	UILabel *label = UILabel.new;
	label.translatesAutoresizingMaskIntoConstraints = NO;
	label.text = title ?: @"";
	label.font = [UIFont preferredFontForTextStyle:UIFontTextStyleBody];
	label.textColor = UIColor.labelColor;
	label.numberOfLines = 1;

	UIView *cv = cell.contentView;
	[cv addSubview:grip];
	[cv addSubview:icon];
	[cv addSubview:label];
	if (accessory) {
		accessory.translatesAutoresizingMaskIntoConstraints = NO;
		[cv addSubview:accessory];
	}

	UILayoutGuide *m = cv.layoutMarginsGuide;
	NSMutableArray *cs = [@[
		[grip.leadingAnchor constraintEqualToAnchor:m.leadingAnchor],
		[grip.centerYAnchor constraintEqualToAnchor:cv.centerYAnchor],
		[grip.widthAnchor constraintEqualToConstant:20.0],
		[icon.leadingAnchor constraintEqualToAnchor:grip.trailingAnchor constant:14.0],
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

@interface SCISectionReorderViewController : UITableViewController <UITableViewDragDelegate, UITableViewDropDelegate>
- (instancetype)initWithConfig:(SCIActionMenuConfig *)config;
@end

@interface SCISectionReorderViewController ()
@property (nonatomic, strong) SCIActionMenuConfig *config;
@end

@implementation SCISectionReorderViewController

- (instancetype)initWithConfig:(SCIActionMenuConfig *)config {
	if (!(self = [super initWithStyle:UITableViewStyleInsetGrouped])) return nil;
	_config = config;
	self.title = SCILocalized(@"Reorder sections");
	return self;
}

- (void)viewDidLoad {
	[super viewDidLoad];
	SCIApplyGlassBackdropToViewController(self);
	SCIStyleTableViewForGlass(self.tableView);
	self.tableView.dragInteractionEnabled = YES;
	self.tableView.dragDelegate = self;
	self.tableView.dropDelegate = self;
}

- (NSInteger)numberOfSectionsInTableView:(UITableView *)tv { return 1; }
- (NSInteger)tableView:(UITableView *)tv numberOfRowsInSection:(NSInteger)s { return self.config.sections.count; }
- (NSString *)tableView:(UITableView *)tv titleForFooterInSection:(NSInteger)s { return SCILocalized(@"Drag the ≡ handle to reorder sections."); }
- (BOOL)tableView:(UITableView *)tv canMoveRowAtIndexPath:(NSIndexPath *)ip { return YES; }

- (UITableViewCell *)tableView:(UITableView *)tv cellForRowAtIndexPath:(NSIndexPath *)ip {
	UITableViewCell *cell = sciCell();
	SCIActionConfigSection *s = self.config.sections[ip.row];
	sciInstallReorderRow(cell, s.iconSF.length ? s.iconSF : @"folder", s.title.length ? s.title : s.identifier, nil);
	return cell;
}

- (NSArray<UIDragItem *> *)tableView:(UITableView *)tv itemsForBeginningDragSession:(id<UIDragSession>)session atIndexPath:(NSIndexPath *)ip {
	SCIActionConfigSection *s = self.config.sections[ip.row];
	UIDragItem *item = [[UIDragItem alloc] initWithItemProvider:[[NSItemProvider alloc] initWithObject:s.identifier ?: @""]];
	item.localObject = ip;
	return @[item];
}

- (UITableViewDropProposal *)tableView:(UITableView *)tv dropSessionDidUpdate:(id<UIDropSession>)session withDestinationIndexPath:(NSIndexPath *)dst {
	if (!session.localDragSession || !dst) return [[UITableViewDropProposal alloc] initWithDropOperation:UIDropOperationCancel];
	return [[UITableViewDropProposal alloc] initWithDropOperation:UIDropOperationMove intent:UITableViewDropIntentInsertAtDestinationIndexPath];
}

- (void)tableView:(UITableView *)tv performDropWithCoordinator:(id<UITableViewDropCoordinator>)coord {
	NSIndexPath *dst = coord.destinationIndexPath;
	if (!dst) return;
	for (id<UITableViewDropItem> drop in coord.items) {
		NSIndexPath *src = (NSIndexPath *)drop.dragItem.localObject;
		if (![src isKindOfClass:NSIndexPath.class] || src.row == dst.row) continue;
		[self.config moveSectionFromIndex:src.row toIndex:dst.row];
	}
	[self.config save];
	[tv reloadData];
}

@end

#pragma mark - Default tap picker

@interface SCIDefaultTapPickerViewController : UITableViewController
- (instancetype)initWithConfig:(SCIActionMenuConfig *)config;
@end

@interface SCIDefaultTapPickerViewController ()
@property (nonatomic, strong) SCIActionMenuConfig *config;
@property (nonatomic, copy) NSArray<SCIActionDescriptor *> *eligible;
@end

@implementation SCIDefaultTapPickerViewController

- (instancetype)initWithConfig:(SCIActionMenuConfig *)config {
	if (!(self = [super initWithStyle:UITableViewStyleInsetGrouped])) return nil;
	_config = config;
	NSMutableArray *items = NSMutableArray.array;
	for (SCIActionDescriptor *d in [SCIActionCatalog descriptorsForSource:config.source])
		if (d.eligibleForDefaultTap) [items addObject:d];
	_eligible = items.copy;
	self.title = SCILocalized(@"Default tap action");
	return self;
}

- (void)viewDidLoad {
	[super viewDidLoad];
	SCIApplyGlassBackdropToViewController(self);
	SCIStyleTableViewForGlass(self.tableView);
}

- (NSInteger)numberOfSectionsInTableView:(UITableView *)tv { return 1; }
- (NSInteger)tableView:(UITableView *)tv numberOfRowsInSection:(NSInteger)s { return self.eligible.count + 1; }
- (NSString *)tableView:(UITableView *)tv titleForFooterInSection:(NSInteger)s { return SCILocalized(@"What happens on a single tap. Long-press always opens the full menu."); }

- (UITableViewCell *)tableView:(UITableView *)tv cellForRowAtIndexPath:(NSIndexPath *)ip {
	UITableViewCell *cell = sciCell();
	BOOL isMenu = ip.row == 0;
	SCIActionDescriptor *d = isMenu ? nil : self.eligible[ip.row - 1];

	NSString *currentID = self.config.defaultTap.length ? self.config.defaultTap : @"menu";
	NSString *actionID = isMenu ? @"menu" : d.identifier;

	UIListContentConfiguration *config = sciContent(cell, isMenu ? SCILocalized(@"Open menu") : d.title, nil);
	sciApplyIcon(config, isMenu ? @"line.3.horizontal" : d.iconSF, UIColor.labelColor);
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

typedef NS_ENUM(NSInteger, SCIBehaviorRow) {
	SCIBehaviorRowShowDate = 0,
	SCIBehaviorRowDefaultTap,
	SCIBehaviorRowReorder,
	SCIBehaviorRowReset,
};

@interface SCIActionMenuConfigViewController () <UITableViewDragDelegate, UITableViewDropDelegate>
@property (nonatomic, assign) SCIActionSource source;
@property (nonatomic, strong) SCIActionMenuConfig *config;
@property (nonatomic, assign) BOOL supportsDate;
@end

@implementation SCIActionMenuConfigViewController

- (instancetype)initForSource:(SCIActionSource)source {
	if (!(self = [super initWithStyle:UITableViewStyleInsetGrouped])) return nil;
	_source = source;
	_config = [SCIActionMenuConfig configForSource:source];
	_supportsDate = [SCIActionCatalog sourceSupportsDate:source];
	self.title = [NSString stringWithFormat:SCILocalized(@"Configure: %@"), [SCIActionCatalog displayNameForSource:source]];
	return self;
}

- (void)viewDidLoad {
	[super viewDidLoad];
	SCIApplyGlassBackdropToViewController(self);
	SCIStyleTableViewForGlass(self.tableView);
	self.tableView.dragInteractionEnabled = YES;
	self.tableView.dragDelegate = self;
	self.tableView.dropDelegate = self;
}

- (void)viewWillAppear:(BOOL)animated {
	[super viewWillAppear:animated];
	[self.tableView reloadData];
}

#pragma mark - Indexing

- (BOOL)isBehaviorSection:(NSInteger)section { return section == 0; }

- (SCIActionConfigSection *)configSectionForUISection:(NSInteger)section {
	NSInteger idx = section - 1;
	return (idx < 0 || idx >= (NSInteger)self.config.sections.count) ? nil : self.config.sections[idx];
}

- (SCIBehaviorRow)behaviorRowForIndex:(NSInteger)index {
	return (SCIBehaviorRow)(self.supportsDate ? index : index + 1);
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
	if ([self isBehaviorSection:section]) return SCILocalized(@"Behavior");
	SCIActionConfigSection *cs = [self configSectionForUISection:section];
	return cs.title.length ? cs.title : cs.identifier;
}

- (NSString *)tableView:(UITableView *)tv titleForFooterInSection:(NSInteger)section {
	return section == 1 ? SCILocalized(@"Drag the ≡ handle to reorder. Toggle a row off to hide it from the menu. Mark a section as a submenu to collapse its actions behind a single entry.") : nil;
}

#pragma mark - Cells

- (UITableViewCell *)tableView:(UITableView *)tv cellForRowAtIndexPath:(NSIndexPath *)ip {
	if ([self isBehaviorSection:ip.section]) return [self behaviorCellForRow:ip.row];
	return [self actionCellForRow:ip.row section:[self configSectionForUISection:ip.section]];
}

- (UITableViewCell *)behaviorCellForRow:(NSInteger)row {
	UITableViewCell *cell = sciCell();
	UIListContentConfiguration *config = nil;

	switch ([self behaviorRowForIndex:row]) {
		case SCIBehaviorRowShowDate:
			config = sciContent(cell, SCILocalized(@"Show date"), nil);
			sciApplyIcon(config, @"calendar", UIColor.labelColor);
			cell.accessoryView = sciSwitch(self.config.showDate, self, @selector(showDateChanged:));
			cell.selectionStyle = UITableViewCellSelectionStyleNone;
			break;

		case SCIBehaviorRowDefaultTap: {
			SCIActionDescriptor *d = [SCIActionCatalog descriptorForActionID:self.config.defaultTap source:self.source];
			config = sciContent(cell, SCILocalized(@"Default tap action"), d ? d.title : SCILocalized(@"Open menu"));
			sciApplyIcon(config, @"hand.tap", UIColor.labelColor);
			cell.accessoryType = UITableViewCellAccessoryDisclosureIndicator;
			break;
		}

		case SCIBehaviorRowReorder:
			config = sciContent(cell, SCILocalized(@"Reorder sections"), nil);
			sciApplyIcon(config, @"arrow.up.arrow.down", UIColor.labelColor);
			cell.accessoryType = UITableViewCellAccessoryDisclosureIndicator;
			break;

		case SCIBehaviorRowReset: {
			config = sciContent(cell, SCILocalized(@"Reset to defaults"), nil);
			config.textProperties.color = UIColor.systemRedColor;
			config.image = [SCIIcon imageNamed:@"bcn_arrow-ccw_outline_24" pointSize:18 weight:UIImageSymbolWeightRegular] ?: [UIImage systemImageNamed:@"arrow.counterclockwise"];
			config.imageProperties.tintColor = UIColor.systemRedColor;
			config.imageToTextPadding = 14.0;
			break;
		}
	}

	cell.contentConfiguration = config;
	return cell;
}

- (UITableViewCell *)actionCellForRow:(NSInteger)row section:(SCIActionConfigSection *)section {
	UITableViewCell *cell = sciCell();
	if (!section) return cell;

	if (row == 0) {
		UIListContentConfiguration *config = sciContent(cell, SCILocalized(@"Show as submenu"), SCILocalized(@"Collapse this section's actions behind a single entry"));
		sciApplyIcon(config, section.iconSF.length ? section.iconSF : @"folder", UIColor.labelColor);

		UISwitch *sw = sciSwitch(section.collapsible, self, @selector(collapsibleChanged:));
		sw.tag = (NSInteger)[self.config.sections indexOfObject:section];

		cell.contentConfiguration = config;
		cell.accessoryView = sw;
		cell.selectionStyle = UITableViewCellSelectionStyleNone;
		return cell;
	}

	NSInteger actionIndex = row - 1;
	if (actionIndex < 0 || actionIndex >= (NSInteger)section.actionIDs.count) return cell;

	NSString *actionID = section.actionIDs[actionIndex];
	SCIActionDescriptor *d = [SCIActionCatalog descriptorForActionID:actionID source:self.source];

	UISwitch *sw = sciSwitch(![self.config isActionDisabled:actionID], self, @selector(actionToggleChanged:));
	sw.accessibilityIdentifier = actionID;

	sciInstallReorderRow(cell, d.iconSF, d ? d.title : actionID, sw);
	return cell;
}

#pragma mark - Selection

- (void)tableView:(UITableView *)tv didSelectRowAtIndexPath:(NSIndexPath *)ip {
	[tv deselectRowAtIndexPath:ip animated:YES];
	if (![self isBehaviorSection:ip.section]) return;

	switch ([self behaviorRowForIndex:ip.row]) {
		case SCIBehaviorRowShowDate:
			return;
		case SCIBehaviorRowDefaultTap:
			[self.navigationController pushViewController:[[SCIDefaultTapPickerViewController alloc] initWithConfig:self.config] animated:YES];
			return;
		case SCIBehaviorRowReorder:
			[self.navigationController pushViewController:[[SCISectionReorderViewController alloc] initWithConfig:self.config] animated:YES];
			return;
		case SCIBehaviorRowReset:
			[self presentResetConfirmation];
			return;
	}
}

- (void)presentResetConfirmation {
	UIAlertController *alert = [UIAlertController alertControllerWithTitle:[NSString stringWithFormat:@"%@?", SCILocalized(@"Reset to defaults")]
																   message:SCILocalized(@"This will restore the default sections, order, and toggles for this menu.")
															preferredStyle:UIAlertControllerStyleAlert];
	[alert addAction:[UIAlertAction actionWithTitle:SCILocalized(@"Cancel") style:UIAlertActionStyleCancel handler:nil]];

	__weak typeof(self) weakSelf = self;
	[alert addAction:[UIAlertAction actionWithTitle:SCILocalized(@"Reset") style:UIAlertActionStyleDestructive handler:^(__unused UIAlertAction *a) {
		__strong typeof(weakSelf) self = weakSelf;
		if (!self) return;
		[self.config resetToDefaults];
		[self.tableView reloadData];
	}]];

	[self presentViewController:alert animated:YES completion:nil];
}

#pragma mark - Drag and drop

- (NSArray<UIDragItem *> *)tableView:(UITableView *)tv itemsForBeginningDragSession:(id<UIDragSession>)session atIndexPath:(NSIndexPath *)ip {
	if ([self isBehaviorSection:ip.section] || ip.row == 0) return @[];

	SCIActionConfigSection *section = [self configSectionForUISection:ip.section];
	NSInteger actionIndex = ip.row - 1;
	if (!section || actionIndex < 0 || actionIndex >= (NSInteger)section.actionIDs.count) return @[];

	NSString *actionID = section.actionIDs[actionIndex] ?: @"";
	UIDragItem *item = [[UIDragItem alloc] initWithItemProvider:[[NSItemProvider alloc] initWithObject:actionID]];
	item.localObject = ip;
	return @[item];
}

- (UITableViewDropProposal *)tableView:(UITableView *)tv dropSessionDidUpdate:(id<UIDropSession>)session withDestinationIndexPath:(NSIndexPath *)dst {
	if (!session.localDragSession || !dst || [self isBehaviorSection:dst.section]) {
		return [[UITableViewDropProposal alloc] initWithDropOperation:UIDropOperationCancel];
	}
	return [[UITableViewDropProposal alloc] initWithDropOperation:UIDropOperationMove intent:UITableViewDropIntentInsertAtDestinationIndexPath];
}

- (void)tableView:(UITableView *)tv performDropWithCoordinator:(id<UITableViewDropCoordinator>)coord {
	NSIndexPath *dst = coord.destinationIndexPath;
	if (!dst || [self isBehaviorSection:dst.section]) return;

	SCIActionConfigSection *dstSection = [self configSectionForUISection:dst.section];
	if (!dstSection) return;

	NSInteger dstIndex = MAX(0, dst.row - 1);

	for (id<UITableViewDropItem> drop in coord.items) {
		NSIndexPath *src = (NSIndexPath *)drop.dragItem.localObject;
		if (![src isKindOfClass:NSIndexPath.class] || [self isBehaviorSection:src.section] || src.row == 0) continue;

		SCIActionConfigSection *srcSection = [self configSectionForUISection:src.section];
		NSInteger srcIndex = src.row - 1;
		if (!srcSection || srcIndex < 0 || srcIndex >= (NSInteger)srcSection.actionIDs.count) continue;

		NSString *actionID = srcSection.actionIDs[srcIndex];
		if (srcSection == dstSection) {
			[self.config moveActionInSection:srcSection fromIndex:srcIndex toIndex:dstIndex];
		} else {
			[self.config moveActionID:actionID toSection:dstSection index:dstIndex];
		}
	}

	[self.config save];
	[tv reloadData];
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