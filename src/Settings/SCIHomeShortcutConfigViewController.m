#import "SCIHomeShortcutConfigViewController.h"
#import "../Utils.h"
#import "../Features/Feed/SCIHomeShortcutCatalog.h"
#import "../UI/SCIPopupChrome.h"

#pragma mark - Persistence

static NSMutableArray<NSMutableDictionary *> *sciLoadOrderedActions(void) {
	NSArray *stored = [SCIUtils getArrayPref:kSCIHomeShortcutActionsPrefKey];
	NSMutableArray<NSMutableDictionary *> *out = NSMutableArray.array;
	NSMutableSet<NSString *> *seen = NSMutableSet.set;

	for (NSDictionary *row in stored) {
		if (![row isKindOfClass:NSDictionary.class]) continue;

		NSString *aid = row[@"id"];
		if (![aid isKindOfClass:NSString.class] || !aid.length) continue;
		if (![SCIHomeShortcutCatalog actionForID:aid]) continue;
		if ([seen containsObject:aid]) continue;

		[seen addObject:aid];
		[out addObject:[@{@"id": aid, @"enabled": @([row[@"enabled"] boolValue])} mutableCopy]];
	}

	for (SCIHomeShortcutAction *action in [SCIHomeShortcutCatalog allActions]) {
		if ([seen containsObject:action.actionID]) continue;

		[seen addObject:action.actionID];
		[out addObject:[@{@"id": action.actionID, @"enabled": @NO} mutableCopy]];
	}

	return out;
}

static void sciSaveOrderedActions(NSArray<NSDictionary *> *actions) {
	[SCIUtils setPref:actions.copy forKey:kSCIHomeShortcutActionsPrefKey];
	[NSNotificationCenter.defaultCenter postNotificationName:SCIHomeShortcutConfigDidChangeNotification object:nil];
}

static NSString *sciCurrentIcon(void) {
	NSString *icon = [SCIUtils getStringPref:kSCIHomeShortcutIconPrefKey];
	return icon.length ? icon : @"auto";
}

static UISwitch *sciSwitch(BOOL on, id target, SEL action) {
	UISwitch *sw = UISwitch.new;
	sw.on = on;
	sw.onTintColor = [SCIUtils SCIColor_Primary];
	[sw addTarget:target action:action forControlEvents:UIControlEventValueChanged];
	return sw;
}

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

static UIListContentConfiguration *sciContent(NSString *title, NSString *subtitle) {
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

static void sciApplyIcon(UIListContentConfiguration *config, NSString *symbol, UIColor *tint) {
	if (!symbol.length) return;

	UIImage *image = [UIImage systemImageNamed:symbol];
	if (!image) return;

	config.image = image;
	config.imageProperties.tintColor = tint ?: UIColor.labelColor;
	config.imageToTextPadding = 14.0;
}

#pragma mark - Reorder row helpers

static UIImageView *sciGripView(void) {
	UIImageView *view = [[UIImageView alloc] initWithImage:[UIImage systemImageNamed:@"line.3.horizontal"]];

	view.translatesAutoresizingMaskIntoConstraints = NO;
	view.tintColor = UIColor.tertiaryLabelColor;
	view.contentMode = UIViewContentModeCenter;

	return view;
}

static UIImageView *sciIconView(NSString *symbol) {
	UIImageView *view = [[UIImageView alloc] initWithImage:(symbol.length ? [UIImage systemImageNamed:symbol] : nil)];

	view.translatesAutoresizingMaskIntoConstraints = NO;
	view.tintColor = UIColor.labelColor;
	view.contentMode = UIViewContentModeCenter;

	return view;
}

static UILabel *sciTitleLabel(NSString *title) {
	UILabel *label = UILabel.new;

	label.translatesAutoresizingMaskIntoConstraints = NO;
	label.text = title ?: @"";
	label.font = [UIFont preferredFontForTextStyle:UIFontTextStyleBody];
	label.textColor = UIColor.labelColor;

	return label;
}

static void sciInstallActionRow(UITableViewCell *cell, NSString *symbol, NSString *title, UISwitch *sw) {
	cell.selectionStyle = UITableViewCellSelectionStyleNone;
	cell.textLabel.text = nil;
	cell.imageView.image = nil;

	UIImageView *grip = sciGripView();
	UIImageView *icon = sciIconView(symbol);
	UILabel *titleLabel = sciTitleLabel(title);

	sw.translatesAutoresizingMaskIntoConstraints = NO;

	[cell.contentView addSubview:grip];
	[cell.contentView addSubview:icon];
	[cell.contentView addSubview:titleLabel];
	[cell.contentView addSubview:sw];

	[NSLayoutConstraint activateConstraints:@[
		[grip.leadingAnchor constraintEqualToAnchor:cell.contentView.layoutMarginsGuide.leadingAnchor],
		[grip.centerYAnchor constraintEqualToAnchor:cell.contentView.centerYAnchor],
		[grip.widthAnchor constraintEqualToConstant:20.0],

		[icon.leadingAnchor constraintEqualToAnchor:grip.trailingAnchor constant:14.0],
		[icon.centerYAnchor constraintEqualToAnchor:cell.contentView.centerYAnchor],
		[icon.widthAnchor constraintEqualToConstant:24.0],

		[titleLabel.leadingAnchor constraintEqualToAnchor:icon.trailingAnchor constant:12.0],
		[titleLabel.centerYAnchor constraintEqualToAnchor:cell.contentView.centerYAnchor],
		[titleLabel.trailingAnchor constraintLessThanOrEqualToAnchor:sw.leadingAnchor constant:-12.0],

		[sw.trailingAnchor constraintEqualToAnchor:cell.contentView.layoutMarginsGuide.trailingAnchor],
		[sw.centerYAnchor constraintEqualToAnchor:cell.contentView.centerYAnchor],
	]];
}

#pragma mark - Icon picker

@interface SCIHomeShortcutIconPickerCell : UICollectionViewCell
- (void)configureWithSymbol:(NSString *)symbol selected:(BOOL)selected;
@end

@interface SCIHomeShortcutIconPickerCell ()
@property (nonatomic, strong) UIImageView *iconView;
@property (nonatomic, strong) UIImageView *checkBadge;
@property (nonatomic, strong) UILabel *autoLabel;
@property (nonatomic, strong) NSLayoutConstraint *iconCenterYConstraint;
@end

@implementation SCIHomeShortcutIconPickerCell

- (instancetype)initWithFrame:(CGRect)frame {
	self = [super initWithFrame:frame];
	if (!self) return nil;

	self.contentView.layer.cornerRadius = 16.0;
	self.contentView.layer.cornerCurve = kCACornerCurveContinuous;
	self.contentView.layer.borderWidth = 1.0 / UIScreen.mainScreen.scale;
	self.contentView.layer.borderColor = UIColor.separatorColor.CGColor;
	self.contentView.backgroundColor = UIColor.secondarySystemGroupedBackgroundColor;

	_iconView = UIImageView.new;
	_iconView.translatesAutoresizingMaskIntoConstraints = NO;
	_iconView.contentMode = UIViewContentModeCenter;
	_iconView.tintColor = UIColor.labelColor;
	[self.contentView addSubview:_iconView];

	_autoLabel = UILabel.new;
	_autoLabel.translatesAutoresizingMaskIntoConstraints = NO;
	_autoLabel.text = SCILocalized(@"Auto");
	_autoLabel.font = [UIFont systemFontOfSize:11.0 weight:UIFontWeightSemibold];
	_autoLabel.textColor = UIColor.secondaryLabelColor;
	_autoLabel.hidden = YES;
	[self.contentView addSubview:_autoLabel];

	UIImageSymbolConfiguration *checkCfg = [UIImageSymbolConfiguration configurationWithPointSize:18.0 weight:UIImageSymbolWeightBold];
	_checkBadge = [[UIImageView alloc] initWithImage:[UIImage systemImageNamed:@"checkmark.circle.fill" withConfiguration:checkCfg]];
	_checkBadge.translatesAutoresizingMaskIntoConstraints = NO;
	_checkBadge.tintColor = [SCIUtils SCIColor_Primary];
	_checkBadge.backgroundColor = UIColor.whiteColor;
	_checkBadge.layer.cornerRadius = 9.0;
	_checkBadge.layer.masksToBounds = YES;
	_checkBadge.hidden = YES;
	[self.contentView addSubview:_checkBadge];

	self.iconCenterYConstraint = [_iconView.centerYAnchor constraintEqualToAnchor:self.contentView.centerYAnchor];

	[NSLayoutConstraint activateConstraints:@[
		[_iconView.centerXAnchor constraintEqualToAnchor:self.contentView.centerXAnchor],
		self.iconCenterYConstraint,

		[_autoLabel.centerXAnchor constraintEqualToAnchor:self.contentView.centerXAnchor],
		[_autoLabel.topAnchor constraintEqualToAnchor:_iconView.bottomAnchor constant:4.0],

		[_checkBadge.topAnchor constraintEqualToAnchor:self.contentView.topAnchor constant:6.0],
		[_checkBadge.trailingAnchor constraintEqualToAnchor:self.contentView.trailingAnchor constant:-6.0],
		[_checkBadge.widthAnchor constraintEqualToConstant:18.0],
		[_checkBadge.heightAnchor constraintEqualToConstant:18.0],
	]];

	return self;
}

- (void)applySelected:(BOOL)selected {
	UIColor *primary = [SCIUtils SCIColor_Primary];

	self.checkBadge.hidden = !selected;
	self.iconView.tintColor = selected ? primary : UIColor.labelColor;
	self.autoLabel.textColor = selected ? primary : UIColor.secondaryLabelColor;
	self.contentView.backgroundColor = selected ? [primary colorWithAlphaComponent:0.16] : UIColor.secondarySystemGroupedBackgroundColor;
	self.contentView.layer.borderColor = (selected ? primary : UIColor.separatorColor).CGColor;
	self.contentView.layer.borderWidth = selected ? 2.0 : (1.0 / UIScreen.mainScreen.scale);
}

- (void)configureWithSymbol:(NSString *)symbol selected:(BOOL)selected {
	BOOL isAuto = [symbol isEqualToString:@"auto"];
	UIImageSymbolConfiguration *cfg = [UIImageSymbolConfiguration configurationWithPointSize:24.0 weight:UIImageSymbolWeightSemibold];

	self.iconView.image = [UIImage systemImageNamed:(isAuto ? @"wand.and.stars" : symbol) withConfiguration:cfg];
	self.autoLabel.hidden = !isAuto;
	self.iconCenterYConstraint.constant = isAuto ? -6.0 : 0.0;

	[self applySelected:selected];
}

- (void)prepareForReuse {
	[super prepareForReuse];

	self.iconView.image = nil;
	self.autoLabel.hidden = YES;
	self.iconCenterYConstraint.constant = 0.0;

	[self applySelected:NO];
}

@end

@interface SCIHomeShortcutIconPickerViewController : UIViewController <UICollectionViewDataSource, UICollectionViewDelegate>
@property (nonatomic, strong) UICollectionView *collectionView;
@property (nonatomic, strong) NSArray<NSString *> *icons;
@end

@implementation SCIHomeShortcutIconPickerViewController

- (void)viewDidLoad {
	[super viewDidLoad];

	self.title = SCILocalized(@"Icon");
	self.view.backgroundColor = [SCIPopupChrome backgroundColor] ?: UIColor.systemGroupedBackgroundColor;

	NSMutableArray *valid = [NSMutableArray arrayWithObject:@"auto"];

	for (NSString *name in [SCIHomeShortcutCatalog availableIcons]) {
		if ([UIImage systemImageNamed:name]) [valid addObject:name];
	}

	self.icons = valid.copy;

	UICollectionViewFlowLayout *layout = UICollectionViewFlowLayout.new;
	layout.minimumInteritemSpacing = 10.0;
	layout.minimumLineSpacing = 10.0;
	layout.sectionInset = UIEdgeInsetsMake(16.0, 16.0, 24.0, 16.0);

	self.collectionView = [[UICollectionView alloc] initWithFrame:CGRectZero collectionViewLayout:layout];
	self.collectionView.translatesAutoresizingMaskIntoConstraints = NO;
	self.collectionView.backgroundColor = UIColor.clearColor;
	self.collectionView.delegate = self;
	self.collectionView.dataSource = self;
	self.collectionView.alwaysBounceVertical = YES;

	[self.collectionView registerClass:SCIHomeShortcutIconPickerCell.class forCellWithReuseIdentifier:@"icon"];
	[self.view addSubview:self.collectionView];

	[NSLayoutConstraint activateConstraints:@[
		[self.collectionView.topAnchor constraintEqualToAnchor:self.view.safeAreaLayoutGuide.topAnchor],
		[self.collectionView.bottomAnchor constraintEqualToAnchor:self.view.bottomAnchor],
		[self.collectionView.leadingAnchor constraintEqualToAnchor:self.view.leadingAnchor],
		[self.collectionView.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor],
	]];
}

- (void)viewDidAppear:(BOOL)animated {
	[super viewDidAppear:animated];

	NSUInteger idx = [self.icons indexOfObject:sciCurrentIcon()];
	if (idx != NSNotFound && idx > 4) {
		[self.collectionView scrollToItemAtIndexPath:[NSIndexPath indexPathForItem:idx inSection:0]
									atScrollPosition:UICollectionViewScrollPositionCenteredVertically
											animated:NO];
	}
}

- (void)viewWillLayoutSubviews {
	[super viewWillLayoutSubviews];

	UICollectionViewFlowLayout *layout = (UICollectionViewFlowLayout *)self.collectionView.collectionViewLayout;
	CGFloat available = self.view.bounds.size.width - 32.0;
	NSInteger cols = MAX(4, (NSInteger)floor(available / 76.0));
	CGFloat side = floor((available - layout.minimumInteritemSpacing * (cols - 1)) / cols);

	layout.itemSize = CGSizeMake(side, side);
}

- (NSInteger)collectionView:(UICollectionView *)collectionView numberOfItemsInSection:(NSInteger)section {
	return self.icons.count;
}

- (UICollectionViewCell *)collectionView:(UICollectionView *)collectionView cellForItemAtIndexPath:(NSIndexPath *)indexPath {
	SCIHomeShortcutIconPickerCell *cell = [collectionView dequeueReusableCellWithReuseIdentifier:@"icon" forIndexPath:indexPath];
	NSString *name = self.icons[indexPath.item];

	[cell configureWithSymbol:name selected:[name isEqualToString:sciCurrentIcon()]];

	return cell;
}

- (void)collectionView:(UICollectionView *)collectionView didSelectItemAtIndexPath:(NSIndexPath *)indexPath {
	NSString *picked = self.icons[indexPath.item];

	if ([picked isEqualToString:sciCurrentIcon()]) {
		[collectionView deselectItemAtIndexPath:indexPath animated:YES];
		return;
	}

	[SCIUtils setPref:picked forKey:kSCIHomeShortcutIconPrefKey];
	[NSNotificationCenter.defaultCenter postNotificationName:SCIHomeShortcutConfigDidChangeNotification object:nil];

	[collectionView reloadData];
	[[[UIImpactFeedbackGenerator alloc] initWithStyle:UIImpactFeedbackStyleLight] impactOccurred];
}

@end

#pragma mark - Main config VC

@interface SCIHomeShortcutConfigViewController () <UITableViewDragDelegate, UITableViewDropDelegate>
@property (nonatomic, strong) NSMutableArray<NSMutableDictionary *> *actions;
@end

@implementation SCIHomeShortcutConfigViewController

- (instancetype)init {
	self = [super initWithStyle:UITableViewStyleInsetGrouped];
	if (!self) return nil;

	self.title = SCILocalized(@"Home shortcut button");

	return self;
}

- (void)viewDidLoad {
	[super viewDidLoad];

	self.view.backgroundColor = [SCIPopupChrome backgroundColor] ?: UIColor.systemGroupedBackgroundColor;
	self.tableView.backgroundColor = self.view.backgroundColor;
	self.actions = sciLoadOrderedActions();

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
	return 2;
}

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section {
	return section == 0 ? 1 : (NSInteger)self.actions.count;
}

- (NSString *)tableView:(UITableView *)tableView titleForHeaderInSection:(NSInteger)section {
	return section == 0 ? SCILocalized(@"Appearance") : SCILocalized(@"Actions");
}

- (NSString *)tableView:(UITableView *)tableView titleForFooterInSection:(NSInteger)section {
	if (section == 0) {
		return SCILocalized(@"Choose the icon shown on the home top bar. Auto uses the selected action icon when only one action is enabled.");
	}

	return SCILocalized(@"Drag the ≡ handle to reorder. Toggle actions off to hide them. With one action enabled, tapping fires it directly. With two or more, tapping opens a menu.");
}

#pragma mark - Cells

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath {
	return indexPath.section == 0 ? [self iconCell] : [self actionCellForRow:indexPath.row];
}

- (UITableViewCell *)iconCell {
	UITableViewCell *cell = sciCell(UITableViewCellStyleDefault);

	NSString *cur = sciCurrentIcon();
	BOOL isAuto = [cur isEqualToString:@"auto"];
	NSString *symbol = isAuto ? @"wand.and.stars" : cur;

	UIListContentConfiguration *config = sciContent(SCILocalized(@"Icon"), isAuto ? SCILocalized(@"Auto") : cur);
	sciApplyIcon(config, symbol, UIColor.labelColor);

	cell.contentConfiguration = config;
	cell.accessoryType = UITableViewCellAccessoryDisclosureIndicator;

	return cell;
}

- (UITableViewCell *)actionCellForRow:(NSInteger)row {
	UITableViewCell *cell = sciCell(UITableViewCellStyleDefault);

	if (row < 0 || row >= (NSInteger)self.actions.count) return cell;

	NSDictionary *rowDict = self.actions[row];
	NSString *aid = rowDict[@"id"];
	SCIHomeShortcutAction *entry = [SCIHomeShortcutCatalog actionForID:aid];

	UISwitch *sw = sciSwitch([rowDict[@"enabled"] boolValue], self, @selector(actionToggleChanged:));
	sw.accessibilityIdentifier = aid;

	sciInstallActionRow(cell, entry.symbol, entry.title ?: aid, sw);

	return cell;
}

#pragma mark - Selection

- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath {
	[tableView deselectRowAtIndexPath:indexPath animated:YES];

	if (indexPath.section == 0 && indexPath.row == 0) {
		[self.navigationController pushViewController:SCIHomeShortcutIconPickerViewController.new animated:YES];
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

	sciSaveOrderedActions(self.actions);
}

#pragma mark - Drag and drop

- (BOOL)tableView:(UITableView *)tableView canMoveRowAtIndexPath:(NSIndexPath *)indexPath {
	return indexPath.section == 1;
}

- (NSArray<UIDragItem *> *)tableView:(UITableView *)tableView itemsForBeginningDragSession:(id<UIDragSession>)session atIndexPath:(NSIndexPath *)indexPath {
	if (indexPath.section != 1 || indexPath.row >= (NSInteger)self.actions.count) return @[];

	NSString *aid = self.actions[indexPath.row][@"id"] ?: @"";
	NSItemProvider *provider = [[NSItemProvider alloc] initWithObject:aid];
	UIDragItem *item = [[UIDragItem alloc] initWithItemProvider:provider];

	item.localObject = indexPath;

	return @[item];
}

- (UITableViewDropProposal *)tableView:(UITableView *)tableView dropSessionDidUpdate:(id<UIDropSession>)session withDestinationIndexPath:(NSIndexPath *)destinationIndexPath {
	if (!session.localDragSession || !destinationIndexPath || destinationIndexPath.section != 1) {
		return [[UITableViewDropProposal alloc] initWithDropOperation:UIDropOperationCancel];
	}

	return [[UITableViewDropProposal alloc] initWithDropOperation:UIDropOperationMove intent:UITableViewDropIntentInsertAtDestinationIndexPath];
}

- (void)tableView:(UITableView *)tableView performDropWithCoordinator:(id<UITableViewDropCoordinator>)coordinator {
	NSIndexPath *dst = coordinator.destinationIndexPath;
	if (!dst || dst.section != 1) return;

	for (id<UITableViewDropItem> dropItem in coordinator.items) {
		NSIndexPath *src = (NSIndexPath *)dropItem.dragItem.localObject;

		if (![src isKindOfClass:NSIndexPath.class]) continue;
		if (src.section != 1 || src.row == dst.row) continue;
		if (src.row >= (NSInteger)self.actions.count) continue;

		NSMutableDictionary *item = self.actions[src.row];
		[self.actions removeObjectAtIndex:src.row];

		NSInteger insertIndex = MIN(dst.row, (NSInteger)self.actions.count);
		[self.actions insertObject:item atIndex:insertIndex];

		[tableView reloadData];
	}

	sciSaveOrderedActions(self.actions);
}

@end