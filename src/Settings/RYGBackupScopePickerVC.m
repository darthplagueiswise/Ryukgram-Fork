#import "RYGBackupScopePickerVC.h"
#import "RYGBackupDetailVC.h"
#import "RYGSymbol.h"
#import "../Utils.h"
#import "../Localization/RYGLocalization.h"

#pragma mark - Cell

@interface RYGPickerCell : UITableViewCell
@property (nonatomic, strong) UIButton *check;
@property (nonatomic, strong) UIImageView *icon;
@property (nonatomic, strong) UILabel *titleLabel;
@property (nonatomic, strong) UILabel *subtitleLabel;
@property (nonatomic, strong) NSLayoutConstraint *iconWidth;
@property (nonatomic, strong) NSLayoutConstraint *titleToIcon;
@property (nonatomic, strong) NSLayoutConstraint *titleToCheck;
@property (nonatomic, copy) void(^onToggle)(void);
- (void)setChecked:(BOOL)checked;
- (void)setIconSymbol:(RYGSymbol *)symbol tint:(UIColor *)tint;
@end

@implementation RYGPickerCell

- (instancetype)initWithStyle:(UITableViewCellStyle)style reuseIdentifier:(NSString *)rid {
	if ((self = [super initWithStyle:style reuseIdentifier:rid])) {
		self.selectionStyle = UITableViewCellSelectionStyleDefault;

		_check = [UIButton buttonWithType:UIButtonTypeSystem];
		_check.translatesAutoresizingMaskIntoConstraints = NO;
		_check.contentHorizontalAlignment = UIControlContentHorizontalAlignmentCenter;
		_check.contentVerticalAlignment = UIControlContentVerticalAlignmentCenter;
		[_check addTarget:self action:@selector(toggleTapped) forControlEvents:UIControlEventTouchUpInside];

		_icon = UIImageView.new;
		_icon.translatesAutoresizingMaskIntoConstraints = NO;
		_icon.contentMode = UIViewContentModeScaleAspectFit;

		_titleLabel = UILabel.new;
		_titleLabel.translatesAutoresizingMaskIntoConstraints = NO;
		_titleLabel.font = [UIFont systemFontOfSize:16 weight:UIFontWeightSemibold];
		_titleLabel.numberOfLines = 1;

		_subtitleLabel = UILabel.new;
		_subtitleLabel.translatesAutoresizingMaskIntoConstraints = NO;
		_subtitleLabel.font = [UIFont systemFontOfSize:12 weight:UIFontWeightRegular];
		_subtitleLabel.textColor = UIColor.secondaryLabelColor;
		_subtitleLabel.numberOfLines = 2;

		for (UIView *v in @[_check, _icon, _titleLabel, _subtitleLabel]) [self.contentView addSubview:v];

		UILayoutGuide *m = self.contentView.layoutMarginsGuide;
		_iconWidth = [_icon.widthAnchor constraintEqualToConstant:22];
		_titleToIcon = [_titleLabel.leadingAnchor constraintEqualToAnchor:_icon.trailingAnchor constant:10];
		_titleToCheck = [_titleLabel.leadingAnchor constraintEqualToAnchor:_check.trailingAnchor constant:12];
		_titleToCheck.active = NO;
		[NSLayoutConstraint activateConstraints:@[
			[_check.leadingAnchor constraintEqualToAnchor:m.leadingAnchor],
			[_check.centerYAnchor constraintEqualToAnchor:self.contentView.centerYAnchor],
			[_check.widthAnchor constraintEqualToConstant:32],
			[_check.heightAnchor constraintEqualToConstant:32],

			[_icon.leadingAnchor constraintEqualToAnchor:_check.trailingAnchor constant:12],
			[_icon.centerYAnchor constraintEqualToAnchor:self.contentView.centerYAnchor],
			_iconWidth,
			[_icon.heightAnchor constraintEqualToConstant:22],

			_titleToIcon,
			[_titleLabel.topAnchor constraintEqualToAnchor:self.contentView.topAnchor constant:10],
			[_titleLabel.trailingAnchor constraintEqualToAnchor:m.trailingAnchor],

			[_subtitleLabel.leadingAnchor constraintEqualToAnchor:_titleLabel.leadingAnchor],
			[_subtitleLabel.topAnchor constraintEqualToAnchor:_titleLabel.bottomAnchor constant:2],
			[_subtitleLabel.trailingAnchor constraintEqualToAnchor:_titleLabel.trailingAnchor],
			[_subtitleLabel.bottomAnchor constraintLessThanOrEqualToAnchor:self.contentView.bottomAnchor constant:-10],
		]];
	}
	return self;
}

- (void)prepareForReuse {
	[super prepareForReuse];
	self.onToggle = nil;
	[self setIconSymbol:nil tint:UIColor.systemGrayColor];
	self.titleLabel.text = nil;
	self.subtitleLabel.text = nil;
	self.accessoryType = UITableViewCellAccessoryNone;
}

- (void)toggleTapped { if (self.onToggle) self.onToggle(); }

// A nil symbol collapses the icon slot.
- (void)setIconSymbol:(RYGSymbol *)symbol tint:(UIColor *)tint {
	BOOL hasIcon = symbol != nil;
	self.icon.image = hasIcon ? [symbol image] : nil;
	self.icon.tintColor = tint ?: UIColor.systemGrayColor;
	self.icon.hidden = !hasIcon;
	self.iconWidth.constant = hasIcon ? 22 : 0;
	self.titleToIcon.active = hasIcon;
	self.titleToCheck.active = !hasIcon;
}

- (void)setChecked:(BOOL)checked {
	UIImageSymbolConfiguration *cfg = [UIImageSymbolConfiguration configurationWithPointSize:22 weight:UIImageSymbolWeightRegular];
	UIImage *img = [[UIImage systemImageNamed:checked ? @"checkmark.circle.fill" : @"circle"] imageByApplyingSymbolConfiguration:cfg];

	[self.check setImage:img forState:UIControlStateNormal];
	self.check.tintColor = checked ? ([RYGUtils RYGColor_Primary] ?: UIColor.systemBlueColor) : UIColor.systemGray3Color;
}

@end

#pragma mark - VC

typedef NS_ENUM(NSInteger, RYGPickerSection) {
	RYGPickerSectionMode,
	RYGPickerSectionAccounts,
	RYGPickerSectionInclude,
	RYGPickerSectionEncrypt,
	RYGPickerSectionRaw,
};

@interface RYGBackupScopePickerVC () <UITableViewDataSource, UITableViewDelegate>
@property (nonatomic, strong) UITableView *tableView;
@property (nonatomic, strong) UIButton *continueButton;
@property (nonatomic, strong) UIView *commitBar;
@property (nonatomic, assign) NSInteger selection;
@property (nonatomic, assign) NSInteger availableMask;
@property (nonatomic, assign) NSInteger accountSelection;
@property (nonatomic, assign) NSInteger accountMask;
@property (nonatomic, assign) BOOL mergeMode;
@property (nonatomic, copy, nullable) NSString *exportPassword;
@property (nonatomic, strong, nullable) UIView *loadingView;
@end

@implementation RYGBackupScopePickerVC

- (instancetype)init {
	if ((self = [super init])) {
		_continueTitle = RYGLocalized(@"Continue");
		_rows = @[];
		_accountRows = @[];
	}
	return self;
}

- (void)viewDidLoad {
	[super viewDidLoad];

	self.view.backgroundColor = UIColor.systemGroupedBackgroundColor;
	self.availableMask = [self maskFromRows:self.rows];
	self.selection = self.initialSelection & self.availableMask;
	self.accountMask = [self maskFromRows:self.accountRows];
	self.accountSelection = self.initialAccountSelection & self.accountMask;

	if (!self.subPicker) self.navigationItem.leftBarButtonItem = [[UIBarButtonItem alloc] initWithBarButtonSystemItem:UIBarButtonSystemItemCancel target:self action:@selector(cancelTapped)];
	self.navigationItem.rightBarButtonItem = [[UIBarButtonItem alloc] initWithTitle:nil style:UIBarButtonItemStylePlain target:self action:@selector(selectAllTapped)];

	[self buildTable];
	if (self.subPicker) {
		[self.tableView.bottomAnchor constraintEqualToAnchor:self.view.safeAreaLayoutGuide.bottomAnchor].active = YES;
	} else {
		[self buildCommitBar];
	}
	if (self.loadingContent) [self buildLoadingView];
	[self refreshUI];
}

- (void)buildLoadingView {
	UIActivityIndicatorView *spinner = [[UIActivityIndicatorView alloc] initWithActivityIndicatorStyle:UIActivityIndicatorViewStyleMedium];
	[spinner startAnimating];

	UILabel *label = UILabel.new;
	label.text = RYGLocalized(@"Loading…");
	label.font = [UIFont systemFontOfSize:14 weight:UIFontWeightMedium];
	label.textColor = UIColor.secondaryLabelColor;

	UIStackView *stack = [[UIStackView alloc] initWithArrangedSubviews:@[spinner, label]];
	stack.translatesAutoresizingMaskIntoConstraints = NO;
	stack.axis = UILayoutConstraintAxisVertical;
	stack.alignment = UIStackViewAlignmentCenter;
	stack.spacing = 10;
	[self.view addSubview:stack];

	self.loadingView = stack;
	self.tableView.hidden = YES;

	[NSLayoutConstraint activateConstraints:@[
		[stack.centerXAnchor constraintEqualToAnchor:self.view.centerXAnchor],
		[stack.centerYAnchor constraintEqualToAnchor:self.view.centerYAnchor],
	]];
}

- (void)applyContent:(NSDictionary *)payload {
	self.rows = payload[@"rows"] ?: @[];
	self.accountRows = payload[@"accountRows"] ?: @[];
	self.rawJSON = payload[@"rawJSON"];
	self.availableMask = [self maskFromRows:self.rows];
	self.selection = [payload[@"initialSelection"] integerValue] & self.availableMask;
	self.accountMask = [self maskFromRows:self.accountRows];
	self.accountSelection = [payload[@"initialAccountSelection"] integerValue] & self.accountMask;

	self.loadingContent = NO;
	[self.loadingView removeFromSuperview];
	self.loadingView = nil;
	self.tableView.hidden = NO;
	[self.tableView reloadData];
	[self refreshUI];
}

- (NSInteger)maskFromRows:(NSArray *)rows {
	NSInteger mask = 0;
	for (NSDictionary *r in rows) {
		if (![r isKindOfClass:NSDictionary.class]) continue;
		if ([r[@"isGroup"] boolValue]) { mask |= [r[@"groupMask"] integerValue]; continue; }
		NSInteger bit = [r[@"bit"] integerValue];
		if (bit > 0) mask |= bit;
	}
	return mask;
}

- (void)buildTable {
	self.tableView = [[UITableView alloc] initWithFrame:CGRectZero style:UITableViewStyleInsetGrouped];
	self.tableView.translatesAutoresizingMaskIntoConstraints = NO;
	self.tableView.dataSource = self;
	self.tableView.delegate = self;
	self.tableView.estimatedRowHeight = 64;
	self.tableView.rowHeight = UITableViewAutomaticDimension;
	self.tableView.backgroundColor = UIColor.systemGroupedBackgroundColor;
	self.tableView.contentInsetAdjustmentBehavior = UIScrollViewContentInsetAdjustmentAutomatic;
	[self.tableView registerClass:RYGPickerCell.class forCellReuseIdentifier:@"scope"];
	[self.view addSubview:self.tableView];

	[NSLayoutConstraint activateConstraints:@[
		[self.tableView.topAnchor constraintEqualToAnchor:self.view.topAnchor],
		[self.tableView.leadingAnchor constraintEqualToAnchor:self.view.leadingAnchor],
		[self.tableView.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor],
	]];
}

- (void)buildCommitBar {
	self.commitBar = UIView.new;
	self.commitBar.translatesAutoresizingMaskIntoConstraints = NO;
	self.commitBar.backgroundColor = UIColor.systemGroupedBackgroundColor;
	[self.view addSubview:self.commitBar];

	self.continueButton = [UIButton buttonWithType:UIButtonTypeSystem];
	self.continueButton.translatesAutoresizingMaskIntoConstraints = NO;
	self.continueButton.titleLabel.font = [UIFont systemFontOfSize:16 weight:UIFontWeightSemibold];
	self.continueButton.backgroundColor = [RYGUtils RYGColor_Primary] ?: UIColor.systemBlueColor;
	self.continueButton.layer.cornerRadius = 14;
	self.continueButton.layer.cornerCurve = kCACornerCurveContinuous;
	[self.continueButton setTitleColor:UIColor.whiteColor forState:UIControlStateNormal];
	[self.continueButton addTarget:self action:@selector(continueTapped) forControlEvents:UIControlEventTouchUpInside];
	[self.commitBar addSubview:self.continueButton];

	[NSLayoutConstraint activateConstraints:@[
		[self.commitBar.leadingAnchor constraintEqualToAnchor:self.view.leadingAnchor],
		[self.commitBar.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor],
		[self.commitBar.bottomAnchor constraintEqualToAnchor:self.view.bottomAnchor],
		[self.commitBar.topAnchor constraintEqualToAnchor:self.tableView.bottomAnchor],

		[self.continueButton.leadingAnchor constraintEqualToAnchor:self.commitBar.leadingAnchor constant:16],
		[self.continueButton.trailingAnchor constraintEqualToAnchor:self.commitBar.trailingAnchor constant:-16],
		[self.continueButton.topAnchor constraintEqualToAnchor:self.commitBar.topAnchor constant:10],
		[self.continueButton.bottomAnchor constraintEqualToAnchor:self.view.safeAreaLayoutGuide.bottomAnchor constant:-10],
		[self.continueButton.heightAnchor constraintEqualToConstant:48],
	]];
}

#pragma mark - Actions

- (void)cancelTapped { [self dismissOrPop:nil]; }

- (void)selectAllTapped {
	BOOL all = [self isEverythingSelected];
	NSInteger old = self.selection;

	self.selection = all ? 0 : self.availableMask;
	[self reloadChangedRowsFrom:old to:self.selection];
	[self selectionDidChange];
}

- (void)selectionDidChange {
	[self refreshUI];
	if (self.subPicker && self.onSelectionChanged) self.onSelectionChanged(self.selection);
}

- (void)continueTapped {
	NSInteger chosen = self.selection;
	NSInteger accounts = self.accountSelection;
	BOOL merge = self.showsImportMode && self.mergeMode;
	NSString *pw = self.showsEncryptOption ? self.exportPassword : nil;
	void (^block)(NSInteger, NSInteger, BOOL, NSString *) = self.onContinue;
	[self dismissOrPop:^{ if (block && chosen) block(chosen, accounts, merge, pw); }];
}

- (void)dismissOrPop:(void(^)(void))completion {
	if (self.navigationController.viewControllers.firstObject == self) {
		[self dismissViewControllerAnimated:YES completion:completion];
		return;
	}

	[self.navigationController popViewControllerAnimated:YES];
	if (completion) dispatch_async(dispatch_get_main_queue(), completion);
}

- (void)refreshUI {
	[self refreshContinue];
	[self refreshSelectButton];
}

- (void)refreshContinue {
	if (!self.continueButton) return;
	// An empty account filter would make every per-account row a no-op.
	BOOL any = self.selection != 0 && (self.accountMask == 0 || self.accountSelection != 0);
	NSInteger n = __builtin_popcountll((unsigned long long)self.selection);

	self.continueButton.enabled = any;
	self.continueButton.alpha = any ? 1.0 : 0.4;
	[self.continueButton setTitle:any ? [NSString stringWithFormat:@"%@ (%ld)", self.continueTitle, (long)n] : self.continueTitle forState:UIControlStateNormal];
}

- (void)refreshSelectButton {
	BOOL all = [self isEverythingSelected];
	self.navigationItem.rightBarButtonItem.title = all ? RYGLocalized(@"Deselect All") : RYGLocalized(@"Select All");
	self.navigationItem.rightBarButtonItem.enabled = self.availableMask != 0;
}

- (BOOL)isEverythingSelected {
	return self.availableMask != 0 && (self.selection & self.availableMask) == self.availableMask;
}

- (void)toggleBit:(NSInteger)bit {
	if (!(self.availableMask & bit)) return;

	NSInteger old = self.selection;
	self.selection = (self.selection & bit) ? (self.selection & ~bit) : (self.selection | bit);

	[self reloadChangedRowsFrom:old to:self.selection];
	[self selectionDidChange];
}

// Feature-data group checkbox: any-selected → clear the group, none → select all.
- (void)toggleGroupMask:(NSInteger)groupMask {
	groupMask &= self.availableMask;
	if (!groupMask) return;

	NSInteger old = self.selection;
	self.selection = (self.selection & groupMask) ? (self.selection & ~groupMask) : (self.selection | groupMask);

	[self reloadChangedRowsFrom:old to:self.selection];
	[self selectionDidChange];
}

- (void)reloadChangedRowsFrom:(NSInteger)oldSelection to:(NSInteger)newSelection {
	NSMutableArray<NSIndexPath *> *changed = NSMutableArray.array;
	NSInteger includeSection = [[self sectionKinds] indexOfObject:@(RYGPickerSectionInclude)];
	if (includeSection == NSNotFound) return;

	for (NSInteger i = 0; i < (NSInteger)self.rows.count; i++) {
		NSDictionary *r = self.rows[i];
		if (![r isKindOfClass:NSDictionary.class]) continue;

		NSInteger bits = [r[@"isGroup"] boolValue] ? [r[@"groupMask"] integerValue] : [r[@"bit"] integerValue];
		if (bits == 0) continue;

		if ((oldSelection & bits) != (newSelection & bits)) [changed addObject:[NSIndexPath indexPathForRow:i inSection:includeSection]];
	}

	if (changed.count) [self.tableView reloadRowsAtIndexPaths:changed withRowAnimation:UITableViewRowAnimationNone];
}

#pragma mark - Table

- (BOOL)hasRawSection { return self.rawJSON.length > 0; }

// Visible sections in order: [Accounts]? Include [Mode]? [Encrypt]? [Raw]?
- (NSArray<NSNumber *> *)sectionKinds {
	NSMutableArray *k = [NSMutableArray array];
	if (self.accountRows.count) [k addObject:@(RYGPickerSectionAccounts)];
	[k addObject:@(RYGPickerSectionInclude)];
	if (self.showsImportMode) [k addObject:@(RYGPickerSectionMode)];
	if (self.showsEncryptOption) [k addObject:@(RYGPickerSectionEncrypt)];
	if (self.hasRawSection) [k addObject:@(RYGPickerSectionRaw)];
	return k;
}

- (RYGPickerSection)kindForSection:(NSInteger)section {
	NSArray *kinds = [self sectionKinds];
	return section < (NSInteger)kinds.count ? [kinds[section] integerValue] : RYGPickerSectionRaw;
}

- (NSInteger)numberOfSectionsInTableView:(__unused UITableView *)tv {
	return (NSInteger)[self sectionKinds].count;
}

- (NSInteger)tableView:(__unused UITableView *)tv numberOfRowsInSection:(NSInteger)section {
	switch ([self kindForSection:section]) {
		case RYGPickerSectionMode: return 2;
		case RYGPickerSectionAccounts: return 1;
		case RYGPickerSectionInclude: return (NSInteger)self.rows.count;
		case RYGPickerSectionEncrypt: return 1;
		case RYGPickerSectionRaw: return 1;
	}
	return 0;
}

- (NSString *)tableView:(__unused UITableView *)tv titleForHeaderInSection:(NSInteger)section {
	switch ([self kindForSection:section]) {
		case RYGPickerSectionMode: return RYGLocalized(@"Import mode");
		case RYGPickerSectionAccounts: return RYGLocalized(@"Accounts");
		case RYGPickerSectionInclude: return RYGLocalized(@"Include");
		case RYGPickerSectionEncrypt: return RYGLocalized(@"Protection");
		case RYGPickerSectionRaw: return RYGLocalized(@"Raw");
	}
	return nil;
}

- (NSString *)tableView:(__unused UITableView *)tv titleForFooterInSection:(NSInteger)section {
	switch ([self kindForSection:section]) {
		case RYGPickerSectionMode:
			return self.mergeMode
				? RYGLocalized(@"Merge keeps what's on this device and adds the backup's data — duplicates are combined, including the gallery.")
				: RYGLocalized(@"Replace clears existing data for each ticked item, then applies the backup.");
		case RYGPickerSectionAccounts: return [self accountsFooterText];
		case RYGPickerSectionInclude: return self.headerMessage;
		case RYGPickerSectionEncrypt:
			return self.exportPassword.length
				? RYGLocalized(@"The backup is scrambled with AES-256. You'll need this password to restore it — there's no way to recover it if lost.")
				: RYGLocalized(@"Optional. Lock the backup behind a password so only you can restore it.");
		case RYGPickerSectionRaw: return nil;
	}
	return nil;
}

- (UITableViewCell *)modeCellForTable:(UITableView *)tv row:(NSInteger)row {
	UITableViewCell *cell = [tv dequeueReusableCellWithIdentifier:@"mode"];
	if (!cell) cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleSubtitle reuseIdentifier:@"mode"];

	BOOL isMerge = row == 1;
	cell.textLabel.text = isMerge ? RYGLocalized(@"Merge") : RYGLocalized(@"Replace");
	cell.detailTextLabel.text = isMerge
		? RYGLocalized(@"Add the backup's data to what's already here")
		: RYGLocalized(@"Clear existing data, then apply the backup");
	cell.detailTextLabel.textColor = UIColor.secondaryLabelColor;
	cell.imageView.image = [UIImage systemImageNamed:isMerge ? @"arrow.triangle.merge" : @"arrow.2.squarepath"];
	cell.imageView.tintColor = isMerge ? UIColor.systemGreenColor : UIColor.systemOrangeColor;
	cell.accessoryType = (isMerge == self.mergeMode) ? UITableViewCellAccessoryCheckmark : UITableViewCellAccessoryNone;
	return cell;
}

#pragma mark - Accounts

- (BOOL)allAccountsSelected { return self.accountMask != 0 && (self.accountSelection & self.accountMask) == self.accountMask; }
- (BOOL)accountFilterActive { return self.accountMask != 0 && ![self allAccountsSelected]; }

- (NSString *)accountsFooterText {
	if (self.accountSelection == 0) return RYGLocalized(@"Pick at least one account.");
	return RYGLocalized(@"Rows marked Shared aren't tied to an account and always follow their own tick.");
}

- (NSString *)accountsSummary {
	NSInteger total = __builtin_popcountll((unsigned long long)self.accountMask);
	if ([self allAccountsSelected]) return [NSString stringWithFormat:RYGLocalized(@"All accounts (%ld)"), (long)total];

	NSMutableArray *names = [NSMutableArray array];
	for (NSDictionary *r in self.accountRows) {
		if (self.accountSelection & [r[@"bit"] integerValue]) [names addObject:r[@"title"] ?: @""];
	}
	if (!names.count) return RYGLocalized(@"(none)");
	return [names componentsJoinedByString:@", "];
}

- (UITableViewCell *)accountsCellForTable:(UITableView *)tv indexPath:(NSIndexPath *)ip {
	RYGPickerCell *cell = [tv dequeueReusableCellWithIdentifier:@"scope" forIndexPath:ip];
	cell.titleLabel.text = RYGLocalized(@"Accounts");
	cell.subtitleLabel.text = [self accountsSummary];
	[cell setIconSymbol:[RYGSymbol symbolWithIGName:@"ig_icon_user_circle_filled_24" fallback:@"person.2.fill"] tint:UIColor.systemBlueColor];
	[cell setChecked:self.accountSelection != 0];
	cell.accessoryType = UITableViewCellAccessoryDisclosureIndicator;

	__weak typeof(self) weakSelf = self;
	cell.onToggle = ^{ [weakSelf toggleAllAccounts]; };
	return cell;
}

- (void)toggleAllAccounts {
	self.accountSelection = [self allAccountsSelected] ? 0 : self.accountMask;
	[self reloadAccountsSection];
	[self refreshUI];
}

- (void)reloadAccountsSection {
	NSInteger idx = [[self sectionKinds] indexOfObject:@(RYGPickerSectionAccounts)];
	if (idx != NSNotFound) [self.tableView reloadSections:[NSIndexSet indexSetWithIndex:idx] withRowAnimation:UITableViewRowAnimationNone];
}

- (void)pushAccountPicker {
	RYGBackupScopePickerVC *child = [RYGBackupScopePickerVC new];
	child.title = RYGLocalized(@"Accounts");
	child.subPicker = YES;
	child.rows = self.accountRows;
	child.headerMessage = RYGLocalized(@"Per-account data is limited to the accounts ticked here.");
	child.initialSelection = self.accountSelection;

	__weak typeof(self) weakSelf = self;
	child.onSelectionChanged = ^(NSInteger sub) {
		typeof(self) s = weakSelf;
		if (!s) return;
		s.accountSelection = sub & s.accountMask;
		[s reloadAccountsSection];
		[s refreshUI];
	};

	[self.navigationController pushViewController:child animated:YES];
}

- (UITableViewCell *)encryptCellForTable:(UITableView *)tv {
	UITableViewCell *cell = [tv dequeueReusableCellWithIdentifier:@"encrypt"];
	if (!cell) cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleSubtitle reuseIdentifier:@"encrypt"];

	BOOL on = self.exportPassword.length > 0;
	cell.textLabel.text = RYGLocalized(@"Password-protect");
	cell.detailTextLabel.text = on ? RYGLocalized(@"On — tap to change") : RYGLocalized(@"Off");
	cell.detailTextLabel.textColor = UIColor.secondaryLabelColor;
	cell.imageView.image = [UIImage systemImageNamed:on ? @"lock.fill" : @"lock.open"];
	cell.imageView.tintColor = on ? UIColor.systemGreenColor : UIColor.systemGrayColor;
	cell.selectionStyle = UITableViewCellSelectionStyleDefault;

	UISwitch *sw = [UISwitch new];
	sw.on = on;
	[sw addTarget:self action:@selector(encryptSwitchChanged:) forControlEvents:UIControlEventValueChanged];
	cell.accessoryView = sw;
	return cell;
}

- (void)encryptSwitchChanged:(UISwitch *)sw {
	if (sw.on) [self promptSetPasswordFromSwitch:sw];
	else { self.exportPassword = nil; [self reloadEncryptSection]; }
}

- (void)reloadEncryptSection {
	NSInteger idx = [[self sectionKinds] indexOfObject:@(RYGPickerSectionEncrypt)];
	if (idx != NSNotFound) [self.tableView reloadSections:[NSIndexSet indexSetWithIndex:idx] withRowAnimation:UITableViewRowAnimationNone];
}

- (void)promptSetPasswordFromSwitch:(UISwitch *)sw {
	UIAlertController *a = [UIAlertController alertControllerWithTitle:RYGLocalized(@"Backup password")
															 message:RYGLocalized(@"You'll need this to restore. It can't be recovered if lost.")
													  preferredStyle:UIAlertControllerStyleAlert];
	[a addTextFieldWithConfigurationHandler:^(UITextField *tf) {
		tf.placeholder = RYGLocalized(@"Password");
		tf.secureTextEntry = YES;
		tf.textContentType = UITextContentTypeNewPassword;
	}];
	[a addTextFieldWithConfigurationHandler:^(UITextField *tf) {
		tf.placeholder = RYGLocalized(@"Confirm password");
		tf.secureTextEntry = YES;
		tf.textContentType = UITextContentTypeNewPassword;
	}];
	[a addAction:[UIAlertAction actionWithTitle:RYGLocalized(@"Cancel") style:UIAlertActionStyleCancel handler:^(__unused UIAlertAction *_) {
		[self reloadEncryptSection];
	}]];
	[a addAction:[UIAlertAction actionWithTitle:RYGLocalized(@"Set") style:UIAlertActionStyleDefault handler:^(__unused UIAlertAction *_) {
		NSString *p1 = a.textFields[0].text ?: @"";
		NSString *p2 = a.textFields[1].text ?: @"";
		if (p1.length < 4) { [self passwordError:RYGLocalized(@"Use at least 4 characters.") retrySwitch:sw]; return; }
		if (![p1 isEqualToString:p2]) { [self passwordError:RYGLocalized(@"The passwords don't match.") retrySwitch:sw]; return; }
		self.exportPassword = p1;
		[self reloadEncryptSection];
	}]];
	[self presentViewController:a animated:YES completion:nil];
}

- (void)passwordError:(NSString *)msg retrySwitch:(UISwitch *)sw {
	UIAlertController *a = [UIAlertController alertControllerWithTitle:RYGLocalized(@"Try again") message:msg preferredStyle:UIAlertControllerStyleAlert];
	[a addAction:[UIAlertAction actionWithTitle:RYGLocalized(@"OK") style:UIAlertActionStyleDefault handler:^(__unused UIAlertAction *_) {
		[self promptSetPasswordFromSwitch:sw];
	}]];
	[self presentViewController:a animated:YES completion:nil];
}

- (UITableViewCell *)jsonCellForTable:(UITableView *)tv {
	UITableViewCell *cell = [tv dequeueReusableCellWithIdentifier:@"json"];
	if (!cell) cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleSubtitle reuseIdentifier:@"json"];

	cell.textLabel.text = RYGLocalized(@"Raw JSON");
	cell.detailTextLabel.text = RYGLocalized(@"Inspect the full manifest");
	cell.imageView.image = [UIImage systemImageNamed:@"curlybraces"];
	cell.imageView.tintColor = UIColor.systemGrayColor;
	cell.accessoryType = UITableViewCellAccessoryDisclosureIndicator;
	return cell;
}

// The Shared tag only means something once a filter is narrowing.
- (NSString *)subtitleForRow:(NSDictionary *)r {
	NSString *base = [r[@"subtitle"] isKindOfClass:NSString.class] ? r[@"subtitle"] : @"";
	BOOL tag = [r[@"shared"] boolValue] && (self.showsSharedTags || [self accountFilterActive]);
	if (!tag) return base.length ? base : nil;
	return base.length ? [NSString stringWithFormat:@"%@ · %@", RYGLocalized(@"Shared"), base] : RYGLocalized(@"Shared");
}

- (UITableViewCell *)tableView:(UITableView *)tv cellForRowAtIndexPath:(NSIndexPath *)ip {
	RYGPickerSection kind = [self kindForSection:ip.section];
	if (kind == RYGPickerSectionMode) return [self modeCellForTable:tv row:ip.row];
	if (kind == RYGPickerSectionAccounts) return [self accountsCellForTable:tv indexPath:ip];
	if (kind == RYGPickerSectionEncrypt) return [self encryptCellForTable:tv];
	if (kind == RYGPickerSectionRaw) return [self jsonCellForTable:tv];

	RYGPickerCell *cell = [tv dequeueReusableCellWithIdentifier:@"scope" forIndexPath:ip];
	NSDictionary *r = self.rows[ip.row];

	BOOL isGroup = [r[@"isGroup"] boolValue];
	NSInteger bits = isGroup ? [r[@"groupMask"] integerValue] : [r[@"bit"] integerValue];
	RYGSymbol *symbol = [r[@"symbol"] isKindOfClass:RYGSymbol.class] ? r[@"symbol"] : nil;
	id color = r[@"color"];

	cell.titleLabel.text = [r[@"title"] isKindOfClass:NSString.class] ? r[@"title"] : @"";
	if (isGroup) {
		NSInteger sel = __builtin_popcountll((unsigned long long)(self.selection & bits));
		NSInteger total = __builtin_popcountll((unsigned long long)bits);
		NSString *base = [r[@"subtitle"] isKindOfClass:NSString.class] ? r[@"subtitle"] : @"";
		cell.subtitleLabel.text = [NSString stringWithFormat:RYGLocalized(@"%ld of %ld selected · %@"), (long)sel, (long)total, base];
	} else {
		cell.subtitleLabel.text = [self subtitleForRow:r];
	}
	[cell setIconSymbol:symbol tint:[color isKindOfClass:UIColor.class] ? color : UIColor.systemGrayColor];
	cell.accessoryType = (isGroup || [r[@"detailSections"] isKindOfClass:NSArray.class]) ? UITableViewCellAccessoryDisclosureIndicator : UITableViewCellAccessoryNone;
	[cell setChecked:(self.selection & bits) != 0];

	__weak typeof(self) weakSelf = self;
	cell.onToggle = isGroup ? ^{ [weakSelf toggleGroupMask:bits]; } : ^{ [weakSelf toggleBit:bits]; };
	return cell;
}

- (void)tableView:(UITableView *)tv didSelectRowAtIndexPath:(NSIndexPath *)ip {
	[tv deselectRowAtIndexPath:ip animated:YES];

	RYGPickerSection kind = [self kindForSection:ip.section];
	if (kind == RYGPickerSectionMode) {
		BOOL newMerge = ip.row == 1;
		if (newMerge != self.mergeMode) {
			self.mergeMode = newMerge;
			[tv reloadSections:[NSIndexSet indexSetWithIndex:ip.section] withRowAnimation:UITableViewRowAnimationNone];
		}
		return;
	}
	if (kind == RYGPickerSectionAccounts) {
		[self pushAccountPicker];
		return;
	}
	if (kind == RYGPickerSectionEncrypt) {
		[self promptSetPasswordFromSwitch:nil];
		return;
	}
	if (kind == RYGPickerSectionRaw) {
		[self pushRawJSON];
		return;
	}

	NSDictionary *r = self.rows[ip.row];

	if ([r[@"isGroup"] boolValue]) {
		[self pushFeatureGroup:r];
		return;
	}

	NSArray *sections = r[@"detailSections"];
	if (![sections isKindOfClass:NSArray.class]) {
		[self toggleBit:[r[@"bit"] integerValue]];
		return;
	}

	RYGBackupDetailVC *vc = [[RYGBackupDetailVC alloc] initWithTitle:r[@"title"] sections:sections];
	[self.navigationController pushViewController:vc animated:YES];
}

- (void)pushFeatureGroup:(NSDictionary *)r {
	NSInteger groupMask = [r[@"groupMask"] integerValue];
	NSArray *subs = [r[@"submodules"] isKindOfClass:NSArray.class] ? r[@"submodules"] : @[];

	RYGBackupScopePickerVC *child = [RYGBackupScopePickerVC new];
	child.title = [r[@"title"] isKindOfClass:NSString.class] ? r[@"title"] : RYGLocalized(@"Feature data");
	child.subPicker = YES;
	child.showsSharedTags = [self accountFilterActive];
	child.rows = subs;
	child.headerMessage = RYGLocalized(@"Tick each store to include. Tap a row to inspect what's stored.");
	child.initialSelection = self.selection & groupMask;

	__weak typeof(self) weakSelf = self;
	child.onSelectionChanged = ^(NSInteger sub) {
		typeof(self) s = weakSelf;
		if (!s) return;
		NSInteger old = s.selection;
		s.selection = (s.selection & ~groupMask) | (sub & groupMask);
		[s reloadChangedRowsFrom:old to:s.selection];
		[s refreshUI];
	};

	[self.navigationController pushViewController:child animated:YES];
}

- (void)pushRawJSON {
	UIViewController *vc = UIViewController.new;
	vc.title = RYGLocalized(@"Raw JSON");
	vc.view.backgroundColor = UIColor.systemBackgroundColor;

	UITextView *tv = UITextView.new;
	tv.translatesAutoresizingMaskIntoConstraints = NO;
	tv.editable = NO;
	tv.font = [UIFont monospacedSystemFontOfSize:11 weight:UIFontWeightRegular];
	tv.text = self.rawJSON ?: @"{}";
	tv.textContainerInset = UIEdgeInsetsMake(12, 12, 12, 12);
	tv.backgroundColor = UIColor.secondarySystemBackgroundColor;
	[vc.view addSubview:tv];

	[NSLayoutConstraint activateConstraints:@[
		[tv.topAnchor constraintEqualToAnchor:vc.view.topAnchor],
		[tv.leadingAnchor constraintEqualToAnchor:vc.view.leadingAnchor],
		[tv.trailingAnchor constraintEqualToAnchor:vc.view.trailingAnchor],
		[tv.bottomAnchor constraintEqualToAnchor:vc.view.bottomAnchor],
	]];

	[self.navigationController pushViewController:vc animated:YES];
}

@end