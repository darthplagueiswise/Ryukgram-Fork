#import "SCIActionMenuConfigViewController.h"
#import "../ActionButton/SCIActionMenuConfig.h"
#import "../UI/SCIIcon.h"
#import "../UI/SCIPopupChrome.h"
#import "../Utils.h"

#pragma mark - Helpers

static UITableViewCell *sciCell(UITableViewCellStyle style) {
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

static UIListContentConfiguration *sciContentForCell(UITableViewCell *cell, NSString *title, NSString *subtitle) {
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
	if (!name.length) return;

	UIImage *image = [SCIIcon sfImageNamed:name pointSize:18];
	if (!image) image = [UIImage systemImageNamed:name];
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

static UIImageView *sciGripView(void) {
	UIImageView *view = [[UIImageView alloc] initWithImage:[UIImage systemImageNamed:@"line.3.horizontal"]];
	view.translatesAutoresizingMaskIntoConstraints = NO;
	view.tintColor = UIColor.tertiaryLabelColor;
	view.contentMode = UIViewContentModeCenter;
	return view;
}

static UIImageView *sciRowIconView(NSString *name) {
	UIImage *image = name.length ? [SCIIcon sfImageNamed:name pointSize:18] : nil;
	if (!image && name.length) image = [UIImage systemImageNamed:name];

	UIImageView *view = [[UIImageView alloc] initWithImage:image];
	view.translatesAutoresizingMaskIntoConstraints = NO;
	view.tintColor = UIColor.labelColor;
	view.contentMode = UIViewContentModeCenter;
	return view;
}

static UILabel *sciRowTitleLabel(NSString *title) {
	UILabel *label = UILabel.new;
	label.translatesAutoresizingMaskIntoConstraints = NO;
	label.text = title ?: @"";
	label.font = [UIFont preferredFontForTextStyle:UIFontTextStyleBody];
	label.textColor = UIColor.labelColor;
	label.numberOfLines = 1;
	return label;
}

static void sciInstallReorderRow(UITableViewCell *cell, NSString *iconName, NSString *title, UIView *accessory) {
	cell.selectionStyle = UITableViewCellSelectionStyleNone;
	cell.textLabel.text = nil;
	cell.detailTextLabel.text = nil;
	cell.imageView.image = nil;

	UIImageView *grip = sciGripView();
	UIImageView *icon = sciRowIconView(iconName);
	UILabel *titleLabel = sciRowTitleLabel(title);

	[cell.contentView addSubview:grip];
	[cell.contentView addSubview:icon];
	[cell.contentView addSubview:titleLabel];

	if (accessory) {
		accessory.translatesAutoresizingMaskIntoConstraints = NO;
		[cell.contentView addSubview:accessory];
	}

	NSMutableArray *constraints = [NSMutableArray arrayWithArray:@[
		[grip.leadingAnchor constraintEqualToAnchor:cell.contentView.layoutMarginsGuide.leadingAnchor],
		[grip.centerYAnchor constraintEqualToAnchor:cell.contentView.centerYAnchor],
		[grip.widthAnchor constraintEqualToConstant:20.0],

		[icon.leadingAnchor constraintEqualToAnchor:grip.trailingAnchor constant:14.0],
		[icon.centerYAnchor constraintEqualToAnchor:cell.contentView.centerYAnchor],
		[icon.widthAnchor constraintEqualToConstant:24.0],

		[titleLabel.leadingAnchor constraintEqualToAnchor:icon.trailingAnchor constant:12.0],
		[titleLabel.centerYAnchor constraintEqualToAnchor:cell.contentView.centerYAnchor],
	]];

	if (accessory) {
		[constraints addObjectsFromArray:@[
			[accessory.trailingAnchor constraintEqualToAnchor:cell.contentView.layoutMarginsGuide.trailingAnchor],
			[accessory.centerYAnchor constraintEqualToAnchor:cell.contentView.centerYAnchor],
			[titleLabel.trailingAnchor constraintLessThanOrEqualToAnchor:accessory.leadingAnchor constant:-12.0],
		]];
	} else {
		[constraints addObject:[titleLabel.trailingAnchor constraintLessThanOrEqualToAnchor:cell.contentView.layoutMarginsGuide.trailingAnchor]];
	}

	[NSLayoutConstraint activateConstraints:constraints];
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
	self = [super initWithStyle:UITableViewStyleInsetGrouped];
	if (!self) return nil;

	self.config = config;
	self.title = SCILocalized(@"Reorder sections");

	return self;
}

- (void)viewDidLoad {
	[super viewDidLoad];

	self.view.backgroundColor = [SCIPopupChrome backgroundColor] ?: UIColor.systemGroupedBackgroundColor;
	self.tableView.backgroundColor = self.view.backgroundColor;
	self.tableView.dragInteractionEnabled = YES;
	self.tableView.dragDelegate = self;
	self.tableView.dropDelegate = self;
}

- (NSInteger)numberOfSectionsInTableView:(UITableView *)tableView {
	return 1;
}

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section {
	return self.config.sections.count;
}

- (NSString *)tableView:(UITableView *)tableView titleForFooterInSection:(NSInteger)section {
	return SCILocalized(@"Drag the ≡ handle to reorder sections.");
}

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath {
	UITableViewCell *cell = sciCell(UITableViewCellStyleDefault);
	SCIActionConfigSection *section = self.config.sections[indexPath.row];
	NSString *title = section.title.length ? section.title : section.identifier;
	NSString *icon = section.iconSF.length ? section.iconSF : @"folder";

	sciInstallReorderRow(cell, icon, title, nil);

	return cell;
}

- (BOOL)tableView:(UITableView *)tableView canMoveRowAtIndexPath:(NSIndexPath *)indexPath {
	return YES;
}

- (NSArray<UIDragItem *> *)tableView:(UITableView *)tableView itemsForBeginningDragSession:(id<UIDragSession>)session atIndexPath:(NSIndexPath *)indexPath {
	SCIActionConfigSection *section = self.config.sections[indexPath.row];
	NSItemProvider *provider = [[NSItemProvider alloc] initWithObject:section.identifier ?: @""];
	UIDragItem *item = [[UIDragItem alloc] initWithItemProvider:provider];

	item.localObject = indexPath;

	return @[item];
}

- (UITableViewDropProposal *)tableView:(UITableView *)tableView dropSessionDidUpdate:(id<UIDropSession>)session withDestinationIndexPath:(NSIndexPath *)destinationIndexPath {
	if (!session.localDragSession || !destinationIndexPath) {
		return [[UITableViewDropProposal alloc] initWithDropOperation:UIDropOperationCancel];
	}

	return [[UITableViewDropProposal alloc] initWithDropOperation:UIDropOperationMove intent:UITableViewDropIntentInsertAtDestinationIndexPath];
}

- (void)tableView:(UITableView *)tableView performDropWithCoordinator:(id<UITableViewDropCoordinator>)coordinator {
	NSIndexPath *dst = coordinator.destinationIndexPath;
	if (!dst) return;

	for (id<UITableViewDropItem> dropItem in coordinator.items) {
		NSIndexPath *src = (NSIndexPath *)dropItem.dragItem.localObject;
		if (![src isKindOfClass:NSIndexPath.class]) continue;
		if (src.row == dst.row) continue;

		[self.config moveSectionFromIndex:src.row toIndex:dst.row];
	}

	[self.config save];
	[tableView reloadData];
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
	self = [super initWithStyle:UITableViewStyleInsetGrouped];
	if (!self) return nil;

	self.config = config;

	NSMutableArray *items = NSMutableArray.array;
	for (SCIActionDescriptor *descriptor in [SCIActionCatalog descriptorsForSource:config.source]) {
		if (descriptor.eligibleForDefaultTap) [items addObject:descriptor];
	}

	self.eligible = items.copy;
	self.title = SCILocalized(@"Default tap action");

	return self;
}

- (void)viewDidLoad {
	[super viewDidLoad];

	self.view.backgroundColor = [SCIPopupChrome backgroundColor] ?: UIColor.systemGroupedBackgroundColor;
	self.tableView.backgroundColor = self.view.backgroundColor;
}

- (NSInteger)numberOfSectionsInTableView:(UITableView *)tableView {
	return 1;
}

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section {
	return self.eligible.count + 1;
}

- (NSString *)tableView:(UITableView *)tableView titleForFooterInSection:(NSInteger)section {
	return SCILocalized(@"What happens on a single tap. Long-press always opens the full menu.");
}

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath {
	UITableViewCell *cell = sciCell(UITableViewCellStyleDefault);

	NSString *currentID = self.config.defaultTap.length ? self.config.defaultTap : @"menu";
	NSString *actionID = indexPath.row == 0 ? @"menu" : self.eligible[indexPath.row - 1].identifier;
	NSString *title = indexPath.row == 0 ? SCILocalized(@"Open menu") : self.eligible[indexPath.row - 1].title;
	NSString *icon = indexPath.row == 0 ? @"line.3.horizontal" : self.eligible[indexPath.row - 1].iconSF;

	UIListContentConfiguration *config = sciContentForCell(cell, title, nil);
	sciApplyIcon(config, icon, UIColor.labelColor);

	cell.contentConfiguration = config;
	cell.accessoryType = [actionID isEqualToString:currentID] ? UITableViewCellAccessoryCheckmark : UITableViewCellAccessoryNone;

	return cell;
}

- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath {
	[tableView deselectRowAtIndexPath:indexPath animated:YES];

	self.config.defaultTap = indexPath.row == 0 ? @"menu" : self.eligible[indexPath.row - 1].identifier;
	[self.config save];
	[tableView reloadData];
}

@end

#pragma mark - Main configure VC

@interface SCIActionMenuConfigViewController () <UITableViewDragDelegate, UITableViewDropDelegate>
@property (nonatomic, assign) SCIActionSource source;
@property (nonatomic, strong) SCIActionMenuConfig *config;
@end

@implementation SCIActionMenuConfigViewController

- (instancetype)initForSource:(SCIActionSource)source {
	self = [super initWithStyle:UITableViewStyleInsetGrouped];
	if (!self) return nil;

	self.source = source;
	self.config = [SCIActionMenuConfig configForSource:source];
	self.title = [NSString stringWithFormat:SCILocalized(@"Configure: %@"), [SCIActionCatalog displayNameForSource:source]];

	return self;
}

- (void)viewDidLoad {
	[super viewDidLoad];

	self.view.backgroundColor = [SCIPopupChrome backgroundColor] ?: UIColor.systemGroupedBackgroundColor;
	self.tableView.backgroundColor = self.view.backgroundColor;
	self.tableView.dragInteractionEnabled = YES;
	self.tableView.dragDelegate = self;
	self.tableView.dropDelegate = self;
}

- (void)viewWillAppear:(BOOL)animated {
	[super viewWillAppear:animated];
	[self.tableView reloadData];
}

#pragma mark - Sections

- (NSInteger)numberOfSectionsInTableView:(UITableView *)tableView {
	return 1 + (NSInteger)self.config.sections.count;
}

- (BOOL)isBehaviorSection:(NSInteger)section {
	return section == 0;
}

- (SCIActionConfigSection *)configSectionForUISection:(NSInteger)section {
	NSInteger index = section - 1;
	if (index < 0 || index >= (NSInteger)self.config.sections.count) return nil;
	return self.config.sections[index];
}

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section {
	if ([self isBehaviorSection:section]) {
		NSInteger count = 3;
		if ([SCIActionCatalog sourceSupportsDate:self.source]) count++;
		return count;
	}

	SCIActionConfigSection *configSection = [self configSectionForUISection:section];
	return 1 + (NSInteger)configSection.actionIDs.count;
}

- (NSString *)tableView:(UITableView *)tableView titleForHeaderInSection:(NSInteger)section {
	if ([self isBehaviorSection:section]) return SCILocalized(@"Behavior");

	SCIActionConfigSection *configSection = [self configSectionForUISection:section];
	return configSection.title.length ? configSection.title : configSection.identifier;
}

- (NSString *)tableView:(UITableView *)tableView titleForFooterInSection:(NSInteger)section {
	if (section == 1) {
		return SCILocalized(@"Drag the ≡ handle to reorder. Toggle a row off to hide it from the menu. Mark a section as a submenu to collapse its actions behind a single entry.");
	}

	return nil;
}

#pragma mark - Cells

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath {
	if ([self isBehaviorSection:indexPath.section]) {
		return [self behaviorCellForRow:indexPath.row];
	}

	SCIActionConfigSection *section = [self configSectionForUISection:indexPath.section];
	return [self actionCellForRow:indexPath.row section:section];
}

- (UITableViewCell *)behaviorCellForRow:(NSInteger)row {
	UITableViewCell *cell = sciCell(UITableViewCellStyleDefault);

	NSInteger index = row;
	BOOL hasDate = [SCIActionCatalog sourceSupportsDate:self.source];

	if (hasDate && index == 0) {
		UIListContentConfiguration *config = sciContentForCell(cell, SCILocalized(@"Show date"), nil);
		sciApplyIcon(config, @"calendar", UIColor.labelColor);

		cell.contentConfiguration = config;
		cell.accessoryView = sciSwitch(self.config.showDate, self, @selector(showDateChanged:));
		cell.selectionStyle = UITableViewCellSelectionStyleNone;

		return cell;
	}

	if (hasDate) index--;

	if (index == 0) {
		SCIActionDescriptor *descriptor = [SCIActionCatalog descriptorForActionID:self.config.defaultTap source:self.source];
		NSString *detail = descriptor ? descriptor.title : SCILocalized(@"Open menu");

		UIListContentConfiguration *config = sciContentForCell(cell, SCILocalized(@"Default tap action"), detail);
		sciApplyIcon(config, @"hand.tap", UIColor.labelColor);

		cell.contentConfiguration = config;
		cell.accessoryType = UITableViewCellAccessoryDisclosureIndicator;

		return cell;
	}

	index--;

	if (index == 0) {
		UIListContentConfiguration *config = sciContentForCell(cell, SCILocalized(@"Reorder sections"), nil);
		sciApplyIcon(config, @"arrow.up.arrow.down", UIColor.labelColor);

		cell.contentConfiguration = config;
		cell.accessoryType = UITableViewCellAccessoryDisclosureIndicator;

		return cell;
	}

	UIListContentConfiguration *config = sciContentForCell(cell, SCILocalized(@"Reset to defaults"), nil);
	config.textProperties.color = UIColor.systemRedColor;

	UIImage *resetIcon = [SCIIcon imageNamed:@"bcn_arrow-ccw_outline_24" pointSize:18 weight:UIImageSymbolWeightRegular];
	if (!resetIcon) resetIcon = [UIImage systemImageNamed:@"arrow.counterclockwise"];

	config.image = resetIcon;
	config.imageProperties.tintColor = UIColor.systemRedColor;
	config.imageToTextPadding = 14.0;

	cell.contentConfiguration = config;

	return cell;
}

- (UITableViewCell *)actionCellForRow:(NSInteger)row section:(SCIActionConfigSection *)section {
	UITableViewCell *cell = sciCell(UITableViewCellStyleDefault);
	if (!section) return cell;

	if (row == 0) {
		UIListContentConfiguration *config = sciContentForCell(cell,
															   SCILocalized(@"Show as submenu"),
															   SCILocalized(@"Collapse this section's actions behind a single entry"));
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
	SCIActionDescriptor *descriptor = [SCIActionCatalog descriptorForActionID:actionID source:self.source];

	UISwitch *sw = sciSwitch(![self.config isActionDisabled:actionID], self, @selector(actionToggleChanged:));
	sw.accessibilityIdentifier = actionID;

	sciInstallReorderRow(cell,
						 descriptor.iconSF.length ? descriptor.iconSF : nil,
						 descriptor ? descriptor.title : actionID,
						 sw);

	return cell;
}

#pragma mark - Selection

- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath {
	[tableView deselectRowAtIndexPath:indexPath animated:YES];

	if (![self isBehaviorSection:indexPath.section]) return;

	[self didSelectBehaviorRow:indexPath.row];
}

- (void)didSelectBehaviorRow:(NSInteger)row {
	NSInteger index = row;
	BOOL hasDate = [SCIActionCatalog sourceSupportsDate:self.source];

	if (hasDate && index == 0) return;
	if (hasDate) index--;

	if (index == 0) {
		SCIDefaultTapPickerViewController *vc = [[SCIDefaultTapPickerViewController alloc] initWithConfig:self.config];
		[self.navigationController pushViewController:vc animated:YES];
		return;
	}

	index--;

	if (index == 0) {
		SCISectionReorderViewController *vc = [[SCISectionReorderViewController alloc] initWithConfig:self.config];
		[self.navigationController pushViewController:vc animated:YES];
		return;
	}

	UIAlertController *alert = [UIAlertController alertControllerWithTitle:[NSString stringWithFormat:@"%@?", SCILocalized(@"Reset to defaults")]
																   message:SCILocalized(@"This will restore the default sections, order, and toggles for this menu.")
															preferredStyle:UIAlertControllerStyleAlert];

	[alert addAction:[UIAlertAction actionWithTitle:SCILocalized(@"Cancel") style:UIAlertActionStyleCancel handler:nil]];

	__weak typeof(self) weakSelf = self;
	[alert addAction:[UIAlertAction actionWithTitle:SCILocalized(@"Reset") style:UIAlertActionStyleDestructive handler:^(__unused UIAlertAction *action) {
		__strong typeof(weakSelf) self = weakSelf;
		if (!self) return;

		[self.config resetToDefaults];
		[self.tableView reloadData];
	}]];

	[self presentViewController:alert animated:YES completion:nil];
}

#pragma mark - Drag and drop

- (NSArray<UIDragItem *> *)tableView:(UITableView *)tableView itemsForBeginningDragSession:(id<UIDragSession>)session atIndexPath:(NSIndexPath *)indexPath {
	if ([self isBehaviorSection:indexPath.section] || indexPath.row == 0) return @[];

	SCIActionConfigSection *section = [self configSectionForUISection:indexPath.section];
	NSInteger actionIndex = indexPath.row - 1;

	if (!section || actionIndex < 0 || actionIndex >= (NSInteger)section.actionIDs.count) return @[];

	NSString *actionID = section.actionIDs[actionIndex] ?: @"";
	NSItemProvider *provider = [[NSItemProvider alloc] initWithObject:actionID];
	UIDragItem *item = [[UIDragItem alloc] initWithItemProvider:provider];

	item.localObject = indexPath;

	return @[item];
}

- (UITableViewDropProposal *)tableView:(UITableView *)tableView dropSessionDidUpdate:(id<UIDropSession>)session withDestinationIndexPath:(NSIndexPath *)destinationIndexPath {
	if (!session.localDragSession || !destinationIndexPath || [self isBehaviorSection:destinationIndexPath.section]) {
		return [[UITableViewDropProposal alloc] initWithDropOperation:UIDropOperationCancel];
	}

	return [[UITableViewDropProposal alloc] initWithDropOperation:UIDropOperationMove intent:UITableViewDropIntentInsertAtDestinationIndexPath];
}

- (void)tableView:(UITableView *)tableView performDropWithCoordinator:(id<UITableViewDropCoordinator>)coordinator {
	NSIndexPath *dst = coordinator.destinationIndexPath;
	if (!dst || [self isBehaviorSection:dst.section]) return;

	SCIActionConfigSection *dstSection = [self configSectionForUISection:dst.section];
	if (!dstSection) return;

	NSInteger dstIndex = MAX(0, dst.row - 1);

	for (id<UITableViewDropItem> dropItem in coordinator.items) {
		NSIndexPath *src = (NSIndexPath *)dropItem.dragItem.localObject;
		if (![src isKindOfClass:NSIndexPath.class]) continue;
		if ([self isBehaviorSection:src.section] || src.row == 0) continue;

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
	[tableView reloadData];
}

#pragma mark - Toggles

- (void)showDateChanged:(UISwitch *)sender {
	self.config.showDate = sender.isOn;
	[self.config save];
}

- (void)collapsibleChanged:(UISwitch *)sender {
	NSInteger index = sender.tag;
	if (index < 0 || index >= (NSInteger)self.config.sections.count) return;

	[self.config setSection:self.config.sections[index] collapsible:sender.isOn];
	[self.config save];
}

- (void)actionToggleChanged:(UISwitch *)sender {
	NSString *actionID = sender.accessibilityIdentifier;
	if (!actionID.length) return;

	[self.config setAction:actionID disabled:!sender.isOn];
	[self.config save];
}

@end