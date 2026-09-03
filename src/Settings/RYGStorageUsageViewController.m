#import "RYGStorageUsageViewController.h"
#import "RYGSettingsBackup.h"
#import "../RYGAccountRegistry.h"
#import "../Localization/RYGLocalization.h"

#pragma mark - Cells

@interface RYGStorageTotalCell : UITableViewCell
@property (nonatomic, strong) UILabel *sizeLabel;
@property (nonatomic, strong) UILabel *captionLabel;
@property (nonatomic, strong) UIStackView *bar;
@end

@implementation RYGStorageTotalCell

- (instancetype)initWithStyle:(UITableViewCellStyle)style reuseIdentifier:(NSString *)rid {
	if ((self = [super initWithStyle:style reuseIdentifier:rid])) {
		self.selectionStyle = UITableViewCellSelectionStyleNone;

		_sizeLabel = UILabel.new;
		_sizeLabel.font = [UIFont monospacedDigitSystemFontOfSize:34 weight:UIFontWeightBold];
		_sizeLabel.textColor = UIColor.labelColor;

		_captionLabel = UILabel.new;
		_captionLabel.font = [UIFont systemFontOfSize:13 weight:UIFontWeightRegular];
		_captionLabel.textColor = UIColor.secondaryLabelColor;

		_bar = [[UIStackView alloc] init];
		_bar.axis = UILayoutConstraintAxisHorizontal;
		_bar.distribution = UIStackViewDistributionFill;
		_bar.layer.cornerRadius = 3;
		_bar.layer.cornerCurve = kCACornerCurveContinuous;
		_bar.clipsToBounds = YES;

		UIStackView *stack = [[UIStackView alloc] initWithArrangedSubviews:@[_sizeLabel, _captionLabel, _bar]];
		stack.translatesAutoresizingMaskIntoConstraints = NO;
		stack.axis = UILayoutConstraintAxisVertical;
		stack.alignment = UIStackViewAlignmentFill;
		stack.spacing = 4;
		[stack setCustomSpacing:14 afterView:_captionLabel];
		[self.contentView addSubview:stack];

		UILayoutGuide *m = self.contentView.layoutMarginsGuide;
		[NSLayoutConstraint activateConstraints:@[
			[stack.leadingAnchor constraintEqualToAnchor:m.leadingAnchor],
			[stack.trailingAnchor constraintEqualToAnchor:m.trailingAnchor],
			[stack.topAnchor constraintEqualToAnchor:self.contentView.topAnchor constant:14],
			[stack.bottomAnchor constraintEqualToAnchor:self.contentView.bottomAnchor constant:-14],
			[_bar.heightAnchor constraintEqualToConstant:6],
		]];
	}
	return self;
}

// One proportional segment per store.
- (void)setSegments:(NSArray<RYGStorageEntry *> *)entries total:(unsigned long long)total {
	for (UIView *v in self.bar.arrangedSubviews) [v removeFromSuperview];
	if (!total) {
		UIView *empty = UIView.new;
		empty.backgroundColor = UIColor.systemFillColor;
		[self.bar addArrangedSubview:empty];
		return;
	}
	for (RYGStorageEntry *e in entries) {
		if (!e.byteSize) continue;
		UIView *seg = UIView.new;
		seg.backgroundColor = e.color;
		[self.bar addArrangedSubview:seg];
		NSLayoutConstraint *w = [seg.widthAnchor constraintEqualToAnchor:self.bar.widthAnchor
															 multiplier:(CGFloat)((double)e.byteSize / (double)total)];
		// Shares sum to 1 in exact maths but not in floats — let the stack win.
		w.priority = UILayoutPriorityDefaultHigh;
		w.active = YES;
	}
}

@end

@interface RYGStorageRowCell : UITableViewCell
@property (nonatomic, strong) UIView *iconWell;
@property (nonatomic, strong) UIImageView *iconView;
@property (nonatomic, strong) UILabel *titleLabel;
@property (nonatomic, strong) UILabel *detailLabel;
@property (nonatomic, strong) UILabel *sizeLabel;
@property (nonatomic, strong) UIView *track;
@property (nonatomic, strong) UIView *fill;
@property (nonatomic, strong) NSLayoutConstraint *fillWidth;
@property (nonatomic, strong) NSLayoutConstraint *iconWellWidth;
@property (nonatomic, strong) NSLayoutConstraint *textToIcon;
@property (nonatomic, strong) NSLayoutConstraint *textToEdge;
@end

@implementation RYGStorageRowCell

- (instancetype)initWithStyle:(UITableViewCellStyle)style reuseIdentifier:(NSString *)rid {
	if ((self = [super initWithStyle:style reuseIdentifier:rid])) {
		_iconWell = UIView.new;
		_iconWell.translatesAutoresizingMaskIntoConstraints = NO;
		_iconWell.layer.cornerRadius = 8;
		_iconWell.layer.cornerCurve = kCACornerCurveContinuous;

		_iconView = UIImageView.new;
		_iconView.translatesAutoresizingMaskIntoConstraints = NO;
		_iconView.contentMode = UIViewContentModeScaleAspectFit;
		[_iconWell addSubview:_iconView];

		_titleLabel = UILabel.new;
		_titleLabel.translatesAutoresizingMaskIntoConstraints = NO;
		_titleLabel.font = [UIFont systemFontOfSize:16 weight:UIFontWeightSemibold];

		_detailLabel = UILabel.new;
		_detailLabel.translatesAutoresizingMaskIntoConstraints = NO;
		_detailLabel.font = [UIFont systemFontOfSize:12];
		_detailLabel.textColor = UIColor.secondaryLabelColor;

		_sizeLabel = UILabel.new;
		_sizeLabel.translatesAutoresizingMaskIntoConstraints = NO;
		_sizeLabel.font = [UIFont monospacedDigitSystemFontOfSize:15 weight:UIFontWeightSemibold];
		_sizeLabel.textAlignment = NSTextAlignmentRight;
		[_sizeLabel setContentCompressionResistancePriority:UILayoutPriorityRequired forAxis:UILayoutConstraintAxisHorizontal];
		[_sizeLabel setContentHuggingPriority:UILayoutPriorityRequired forAxis:UILayoutConstraintAxisHorizontal];

		_track = UIView.new;
		_track.translatesAutoresizingMaskIntoConstraints = NO;
		_track.backgroundColor = UIColor.quaternarySystemFillColor;
		_track.layer.cornerRadius = 2;
		_track.clipsToBounds = YES;

		_fill = UIView.new;
		_fill.translatesAutoresizingMaskIntoConstraints = NO;
		_fill.layer.cornerRadius = 2;
		[_track addSubview:_fill];

		for (UIView *v in @[_iconWell, _titleLabel, _detailLabel, _sizeLabel, _track]) [self.contentView addSubview:v];

		UILayoutGuide *m = self.contentView.layoutMarginsGuide;
		_iconWellWidth = [_iconWell.widthAnchor constraintEqualToConstant:32];
		_textToIcon = [_titleLabel.leadingAnchor constraintEqualToAnchor:_iconWell.trailingAnchor constant:12];
		_textToEdge = [_titleLabel.leadingAnchor constraintEqualToAnchor:m.leadingAnchor];
		_textToEdge.active = NO;
		_fillWidth = [_fill.widthAnchor constraintEqualToAnchor:_track.widthAnchor multiplier:0];

		[NSLayoutConstraint activateConstraints:@[
			[_iconWell.leadingAnchor constraintEqualToAnchor:m.leadingAnchor],
			[_iconWell.centerYAnchor constraintEqualToAnchor:self.contentView.centerYAnchor],
			[_iconWell.heightAnchor constraintEqualToConstant:32],
			_iconWellWidth,

			[_iconView.centerXAnchor constraintEqualToAnchor:_iconWell.centerXAnchor],
			[_iconView.centerYAnchor constraintEqualToAnchor:_iconWell.centerYAnchor],
			[_iconView.widthAnchor constraintEqualToConstant:18],
			[_iconView.heightAnchor constraintEqualToConstant:18],

			_textToIcon,
			[_titleLabel.topAnchor constraintEqualToAnchor:self.contentView.topAnchor constant:11],
			[_titleLabel.trailingAnchor constraintLessThanOrEqualToAnchor:_sizeLabel.leadingAnchor constant:-8],

			[_sizeLabel.trailingAnchor constraintEqualToAnchor:m.trailingAnchor],
			[_sizeLabel.centerYAnchor constraintEqualToAnchor:_titleLabel.centerYAnchor],

			[_detailLabel.leadingAnchor constraintEqualToAnchor:_titleLabel.leadingAnchor],
			[_detailLabel.topAnchor constraintEqualToAnchor:_titleLabel.bottomAnchor constant:2],
			[_detailLabel.trailingAnchor constraintLessThanOrEqualToAnchor:m.trailingAnchor],

			[_track.leadingAnchor constraintEqualToAnchor:_titleLabel.leadingAnchor],
			[_track.trailingAnchor constraintEqualToAnchor:m.trailingAnchor],
			[_track.topAnchor constraintEqualToAnchor:_detailLabel.bottomAnchor constant:7],
			[_track.heightAnchor constraintEqualToConstant:4],
			[_track.bottomAnchor constraintEqualToAnchor:self.contentView.bottomAnchor constant:-12],

			[_fill.leadingAnchor constraintEqualToAnchor:_track.leadingAnchor],
			[_fill.topAnchor constraintEqualToAnchor:_track.topAnchor],
			[_fill.bottomAnchor constraintEqualToAnchor:_track.bottomAnchor],
			_fillWidth,
		]];
	}
	return self;
}

- (void)setIcon:(nullable UIImage *)image tint:(UIColor *)tint {
	BOOL hasIcon = image != nil;
	self.iconWell.hidden = !hasIcon;
	self.iconWellWidth.constant = hasIcon ? 32 : 0;
	self.textToIcon.active = hasIcon;
	self.textToEdge.active = !hasIcon;
	self.iconView.image = image;
	self.iconView.tintColor = tint;
	self.iconWell.backgroundColor = [tint colorWithAlphaComponent:0.14];
}

- (void)setShare:(double)share color:(UIColor *)color {
	self.fill.backgroundColor = color;
	self.fillWidth.active = NO;
	self.fillWidth = [self.fill.widthAnchor constraintEqualToAnchor:self.track.widthAnchor
														 multiplier:(CGFloat)MAX(share, 0.0)];
	self.fillWidth.active = YES;
}

@end

#pragma mark - VC

@interface RYGStorageUsageViewController () <UITableViewDataSource, UITableViewDelegate>
@property (nonatomic, strong) UITableView *tableView;
@property (nonatomic, strong) UIActivityIndicatorView *spinner;
@property (nonatomic, strong) UIRefreshControl *refresher;
@property (nonatomic, copy, nullable) NSArray<RYGStorageEntry *> *entries;
@property (nonatomic) unsigned long long total;
@property (nonatomic, strong, nullable) RYGStorageEntry *accountsEntry;
@end

@implementation RYGStorageUsageViewController

- (instancetype)initWithAccountsOfEntry:(RYGStorageEntry *)entry {
	self = [super init];
	if (!self) return self;
	_accountsEntry = entry;
	return self;
}

- (BOOL)isAccountList { return self.accountsEntry != nil; }

- (void)viewDidLoad {
	[super viewDidLoad];
	self.title = self.isAccountList ? self.accountsEntry.title : RYGLocalized(@"Storage");
	self.view.backgroundColor = [UIColor systemGroupedBackgroundColor];

	self.tableView = [[UITableView alloc] initWithFrame:self.view.bounds style:UITableViewStyleInsetGrouped];
	self.tableView.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
	self.tableView.dataSource = self;
	self.tableView.delegate = self;
	self.tableView.estimatedRowHeight = 68;
	self.tableView.rowHeight = UITableViewAutomaticDimension;
	[self.tableView registerClass:RYGStorageTotalCell.class forCellReuseIdentifier:@"total"];
	[self.tableView registerClass:RYGStorageRowCell.class forCellReuseIdentifier:@"row"];
	[self.view addSubview:self.tableView];

	[[NSNotificationCenter defaultCenter] addObserver:self
											 selector:@selector(accountNamesChanged)
												 name:RYGAccountRegistryDidChangeNotification
											   object:nil];

	if (self.isAccountList) {
		self.total = self.accountsEntry.byteSize;
		return;
	}

	self.spinner = [[UIActivityIndicatorView alloc] initWithActivityIndicatorStyle:UIActivityIndicatorViewStyleLarge];
	self.spinner.center = CGPointMake(CGRectGetMidX(self.view.bounds), CGRectGetMidY(self.view.bounds));
	self.spinner.autoresizingMask = UIViewAutoresizingFlexibleTopMargin | UIViewAutoresizingFlexibleBottomMargin |
									UIViewAutoresizingFlexibleLeftMargin | UIViewAutoresizingFlexibleRightMargin;
	[self.view addSubview:self.spinner];

	self.refresher = [UIRefreshControl new];
	[self.refresher addTarget:self action:@selector(reload) forControlEvents:UIControlEventValueChanged];
	self.tableView.refreshControl = self.refresher;

	[self.spinner startAnimating];
	[self reload];
}

// The settings row holds one instance, so a revisit has to rescan.
- (void)viewWillAppear:(BOOL)animated {
	[super viewWillAppear:animated];
	if (!self.isAccountList && self.entries) [self reload];
}

- (void)dealloc { [[NSNotificationCenter defaultCenter] removeObserver:self]; }

- (void)accountNamesChanged { [self.tableView reloadData]; }

- (void)reload {
	__weak typeof(self) weakSelf = self;
	[RYGStorageUsage scanWithCompletion:^(NSArray<RYGStorageEntry *> *entries, unsigned long long total) {
		__strong typeof(weakSelf) self = weakSelf;
		if (!self) return;
		self.entries = entries;
		self.total = total;
		[self.spinner stopAnimating];
		[self.refresher endRefreshing];
		[self.tableView reloadData];
	}];
}

- (NSArray *)rows { return self.isAccountList ? (self.accountsEntry.accounts ?: @[]) : (self.entries ?: @[]); }

#pragma mark - Table

- (BOOL)hasClearAllSection { return !self.isAccountList && self.total > 0; }

- (NSArray<RYGStorageComponentEntry *> *)components {
	return self.isAccountList ? (self.accountsEntry.components ?: @[]) : @[];
}

- (NSInteger)numberOfSectionsInTableView:(__unused UITableView *)tv {
	if (!self.isAccountList && !self.entries) return 0;
	return ([self hasClearAllSection] || [self components].count) ? 3 : 2;
}

- (NSInteger)tableView:(__unused UITableView *)tv numberOfRowsInSection:(NSInteger)section {
	if (section == 0) return 1;
	if (section == 1) return (NSInteger)[self rows].count;
	return [self components].count ? (NSInteger)[self components].count : 1;
}

- (NSString *)tableView:(__unused UITableView *)tv titleForFooterInSection:(NSInteger)section {
	if (section != 1) return nil;
	return RYGLocalized(@"Swipe a row to clear it.");
}

- (UITableViewCell *)tableView:(UITableView *)tv cellForRowAtIndexPath:(NSIndexPath *)ip {
	if (ip.section == 0) {
		RYGStorageTotalCell *cell = [tv dequeueReusableCellWithIdentifier:@"total" forIndexPath:ip];
		cell.sizeLabel.text = [RYGStorageUsage formattedSize:self.total];
		cell.captionLabel.text = self.isAccountList ? self.accountsEntry.title : RYGLocalized(@"Total size");
		[cell setSegments:(self.isAccountList ? @[] : (self.entries ?: @[])) total:self.total];
		return cell;
	}

	if (ip.section == 2 && [self components].count) {
		RYGStorageComponentEntry *c = [self components][ip.row];
		RYGStorageRowCell *cell = [tv dequeueReusableCellWithIdentifier:@"row" forIndexPath:ip];
		cell.titleLabel.text = c.title;
		cell.titleLabel.textColor = c.byteSize ? UIColor.labelColor : UIColor.tertiaryLabelColor;
		cell.sizeLabel.text = [RYGStorageUsage formattedSize:c.byteSize];
		cell.sizeLabel.textColor = cell.titleLabel.textColor;
		cell.detailLabel.text = [NSString stringWithFormat:RYGLocalized(@"%lu file(s)"), (unsigned long)c.fileCount];
		[cell setIcon:nil tint:UIColor.systemGrayColor];
		[cell setShare:self.total ? (double)c.byteSize / (double)self.total : 0 color:self.accountsEntry.color];
		cell.accessoryType = UITableViewCellAccessoryNone;
		cell.selectionStyle = UITableViewCellSelectionStyleNone;
		return cell;
	}

	if (ip.section == 2) {
		UITableViewCell *cell = [tv dequeueReusableCellWithIdentifier:@"clearall"];
		if (!cell) cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleDefault reuseIdentifier:@"clearall"];
		cell.textLabel.text = RYGLocalized(@"Clear all data");
		cell.textLabel.textColor = UIColor.systemRedColor;
		cell.textLabel.textAlignment = NSTextAlignmentCenter;
		return cell;
	}

	RYGStorageRowCell *cell = [tv dequeueReusableCellWithIdentifier:@"row" forIndexPath:ip];
	id row = [self rows][ip.row];
	unsigned long long bytes;
	NSUInteger files;
	BOOL drills = NO;

	if (self.isAccountList) {
		RYGStorageAccountEntry *a = row;
		bytes = a.byteSize;
		files = a.fileCount;
		cell.titleLabel.text = a.displayName;
		[cell setIcon:nil tint:UIColor.systemGrayColor];
		[cell setShare:self.total ? (double)bytes / (double)self.total : 0 color:self.accountsEntry.color];
	} else {
		RYGStorageEntry *e = row;
		bytes = e.byteSize;
		files = e.fileCount;
		drills = e.accounts.count > 0;
		cell.titleLabel.text = e.title;
		[cell setIcon:[e.symbol image] tint:bytes ? e.color : UIColor.systemGrayColor];
		[cell setShare:self.total ? (double)bytes / (double)self.total : 0 color:e.color];
	}

	cell.titleLabel.textColor = bytes ? UIColor.labelColor : UIColor.tertiaryLabelColor;
	cell.sizeLabel.text = [RYGStorageUsage formattedSize:bytes];
	cell.sizeLabel.textColor = bytes ? UIColor.labelColor : UIColor.tertiaryLabelColor;
	cell.detailLabel.text = [NSString stringWithFormat:RYGLocalized(@"%lu file(s)"), (unsigned long)files];
	cell.accessoryType = drills ? UITableViewCellAccessoryDisclosureIndicator : UITableViewCellAccessoryNone;
	cell.selectionStyle = drills ? UITableViewCellSelectionStyleDefault : UITableViewCellSelectionStyleNone;
	return cell;
}

- (void)tableView:(UITableView *)tv didSelectRowAtIndexPath:(NSIndexPath *)ip {
	[tv deselectRowAtIndexPath:ip animated:YES];
	if (ip.section == 2) { if (![self components].count) [self clearAll]; return; }
	if (self.isAccountList || ip.section == 0) return;

	RYGStorageEntry *e = [self rows][ip.row];
	if (!e.accounts.count) return;
	[self.navigationController pushViewController:[[RYGStorageUsageViewController alloc] initWithAccountsOfEntry:e] animated:YES];
}

#pragma mark - Clearing

- (UISwipeActionsConfiguration *)tableView:(__unused UITableView *)tv trailingSwipeActionsConfigurationForRowAtIndexPath:(NSIndexPath *)ip {
	if (ip.section == 2 && [self components].count) {
		RYGStorageComponentEntry *c = [self components][ip.row];
		if (!c.byteSize || !c.clearAction) return nil;

		__weak typeof(self) weakSelf = self;
		UIContextualAction *clear = [UIContextualAction contextualActionWithStyle:UIContextualActionStyleDestructive
																		   title:RYGLocalized(@"Clear")
																		 handler:^(__unused UIContextualAction *action, __unused UIView *src, void (^finish)(BOOL)) {
			[RYGSettingsBackup presentClearConfirmationWithLabel:c.title work:c.clearAction done:^(BOOL cleared) {
				finish(cleared);
				if (cleared) [weakSelf reloadAfterClear];
			}];
		}];
		clear.image = [UIImage systemImageNamed:@"trash"];
		return [UISwipeActionsConfiguration configurationWithActions:@[clear]];
	}

	if (ip.section != 1) return nil;

	NSString *storageID = self.isAccountList ? self.accountsEntry.identifier : nil;
	NSString *pk = nil;
	NSString *label = nil;
	unsigned long long bytes = 0;

	if (self.isAccountList) {
		RYGStorageAccountEntry *a = [self rows][ip.row];
		// The Other bucket isn't one account's — nothing to scope a clear to.
		if (!a.pk.length) return nil;
		pk = a.pk;
		label = self.accountsEntry.title;
		bytes = a.byteSize;
	} else {
		RYGStorageEntry *e = [self rows][ip.row];
		storageID = e.identifier;
		label = e.title;
		bytes = e.byteSize;
	}
	if (!bytes) return nil;

	__weak typeof(self) weakSelf = self;
	UIContextualAction *clear = [UIContextualAction contextualActionWithStyle:UIContextualActionStyleDestructive
																	   title:RYGLocalized(@"Clear")
																	 handler:^(__unused UIContextualAction *action, __unused UIView *src, void (^finish)(BOOL)) {
		[RYGSettingsBackup presentClearConfirmationForStorageID:storageID accountPK:pk label:label done:^(BOOL cleared) {
			finish(cleared);
			if (cleared) [weakSelf reloadAfterClear];
		}];
	}];
	clear.image = [UIImage systemImageNamed:@"trash"];
	return [UISwipeActionsConfiguration configurationWithActions:@[clear]];
}

// This list is a snapshot — once cleared its numbers are stale, so hand back.
- (void)reloadAfterClear {
	if (self.isAccountList) { [self.navigationController popViewControllerAnimated:YES]; return; }
	[self reload];
}

- (void)clearAll {
	__weak typeof(self) weakSelf = self;
	[RYGSettingsBackup presentClearAllStorageConfirmationDone:^(BOOL cleared) {
		if (cleared) [weakSelf reload];
	}];
}

@end
