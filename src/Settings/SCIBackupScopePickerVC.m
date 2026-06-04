#import "SCIBackupScopePickerVC.h"
#import "SCIBackupDetailVC.h"
#import "GlassUI/SCIAdaptiveGlass.h"
#import "../Utils.h"
#import "../Localization/SCILocalization.h"

#pragma mark - Cell

@interface SCIPickerCell : UITableViewCell
@property (nonatomic, strong) UIButton *check;
@property (nonatomic, strong) UIImageView *icon;
@property (nonatomic, strong) UILabel *titleLabel;
@property (nonatomic, strong) UILabel *subtitleLabel;
@property (nonatomic, copy) void(^onToggle)(void);
- (void)setChecked:(BOOL)checked;
@end

@implementation SCIPickerCell

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
		[NSLayoutConstraint activateConstraints:@[
			[_check.leadingAnchor constraintEqualToAnchor:m.leadingAnchor],
			[_check.centerYAnchor constraintEqualToAnchor:self.contentView.centerYAnchor],
			[_check.widthAnchor constraintEqualToConstant:32],
			[_check.heightAnchor constraintEqualToConstant:32],

			[_icon.leadingAnchor constraintEqualToAnchor:_check.trailingAnchor constant:12],
			[_icon.centerYAnchor constraintEqualToAnchor:self.contentView.centerYAnchor],
			[_icon.widthAnchor constraintEqualToConstant:22],
			[_icon.heightAnchor constraintEqualToConstant:22],

			[_titleLabel.leadingAnchor constraintEqualToAnchor:_icon.trailingAnchor constant:10],
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
	self.icon.image = nil;
	self.titleLabel.text = nil;
	self.subtitleLabel.text = nil;
	self.accessoryType = UITableViewCellAccessoryNone;
}

- (void)toggleTapped { if (self.onToggle) self.onToggle(); }

- (void)setChecked:(BOOL)checked {
	UIImageSymbolConfiguration *cfg = [UIImageSymbolConfiguration configurationWithPointSize:22 weight:UIImageSymbolWeightRegular];
	UIImage *img = [[UIImage systemImageNamed:checked ? @"checkmark.circle.fill" : @"circle"] imageByApplyingSymbolConfiguration:cfg];

	[self.check setImage:img forState:UIControlStateNormal];
	self.check.tintColor = checked ? ([SCIUtils SCIColor_Primary] ?: UIColor.systemBlueColor) : UIColor.systemGray3Color;
}

@end

#pragma mark - VC

@interface SCIBackupScopePickerVC () <UITableViewDataSource, UITableViewDelegate>
@property (nonatomic, strong) UITableView *tableView;
@property (nonatomic, strong) UIButton *continueButton;
@property (nonatomic, strong) UIView *commitBar;
@property (nonatomic, assign) NSInteger selection;
@property (nonatomic, assign) NSInteger availableMask;
@end

@implementation SCIBackupScopePickerVC

- (instancetype)init {
	if ((self = [super init])) {
		_continueTitle = SCILocalized(@"Continue");
		_rows = @[];
	}
	return self;
}

- (void)viewDidLoad {
	[super viewDidLoad];

	SCIApplyGlassBackdropToViewController(self);
	self.availableMask = [self maskFromRows:self.rows];
	self.selection = self.initialSelection & self.availableMask;

	self.navigationItem.leftBarButtonItem = [[UIBarButtonItem alloc] initWithBarButtonSystemItem:UIBarButtonSystemItemCancel target:self action:@selector(cancelTapped)];
	self.navigationItem.rightBarButtonItem = [[UIBarButtonItem alloc] initWithTitle:nil style:UIBarButtonItemStylePlain target:self action:@selector(selectAllTapped)];

	[self buildTable];
	[self buildCommitBar];
	[self refreshUI];
}

- (NSInteger)maskFromRows:(NSArray *)rows {
	NSInteger mask = 0;
	for (NSDictionary *r in rows) {
		if (![r isKindOfClass:NSDictionary.class]) continue;
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
	SCIStyleTableViewForGlass(self.tableView);
	self.tableView.contentInsetAdjustmentBehavior = UIScrollViewContentInsetAdjustmentAutomatic;
	[self.tableView registerClass:SCIPickerCell.class forCellReuseIdentifier:@"scope"];
	[self.view addSubview:self.tableView];

	[NSLayoutConstraint activateConstraints:@[
		[self.tableView.topAnchor constraintEqualToAnchor:self.view.topAnchor],
		[self.tableView.leadingAnchor constraintEqualToAnchor:self.view.leadingAnchor],
		[self.tableView.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor],
	]];
}

- (void)buildCommitBar {
	self.commitBar = [[SCIAdaptiveGlassPanelView alloc] initWithRadius:0.0];
	self.commitBar.translatesAutoresizingMaskIntoConstraints = NO;
	self.commitBar.backgroundColor = UIColor.clearColor;
	[self.view addSubview:self.commitBar];

	self.continueButton = [UIButton buttonWithType:UIButtonTypeSystem];
	self.continueButton.translatesAutoresizingMaskIntoConstraints = NO;
	self.continueButton.titleLabel.font = [UIFont systemFontOfSize:16 weight:UIFontWeightSemibold];
	self.continueButton.backgroundColor = [SCIUtils SCIColor_Primary] ?: UIColor.systemBlueColor;
	self.continueButton.layer.cornerRadius = 14;
	self.continueButton.layer.cornerCurve = kCACornerCurveContinuous;
	[self.continueButton setTitleColor:UIColor.whiteColor forState:UIControlStateNormal];
	[self.continueButton addTarget:self action:@selector(continueTapped) forControlEvents:UIControlEventTouchUpInside];
	UIView *commitContent = [self.commitBar isKindOfClass:UIVisualEffectView.class] ? ((UIVisualEffectView *)self.commitBar).contentView : self.commitBar;
	[commitContent addSubview:self.continueButton];

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
	[self refreshUI];
}

- (void)continueTapped {
	NSInteger chosen = self.selection;
	void (^block)(NSInteger) = self.onContinue;
	[self dismissOrPop:^{ if (block && chosen) block(chosen); }];
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
	BOOL any = self.selection != 0;
	NSInteger n = __builtin_popcountll((unsigned long long)self.selection);

	self.continueButton.enabled = any;
	self.continueButton.alpha = any ? 1.0 : 0.4;
	[self.continueButton setTitle:any ? [NSString stringWithFormat:@"%@ (%ld)", self.continueTitle, (long)n] : self.continueTitle forState:UIControlStateNormal];
}

- (void)refreshSelectButton {
	BOOL all = [self isEverythingSelected];
	self.navigationItem.rightBarButtonItem.title = all ? SCILocalized(@"Deselect All") : SCILocalized(@"Select All");
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
	[self refreshUI];
}

- (void)reloadChangedRowsFrom:(NSInteger)oldSelection to:(NSInteger)newSelection {
	NSMutableArray<NSIndexPath *> *changed = NSMutableArray.array;

	for (NSInteger i = 0; i < (NSInteger)self.rows.count; i++) {
		NSDictionary *r = self.rows[i];
		if (![r isKindOfClass:NSDictionary.class]) continue;

		NSInteger bit = [r[@"bit"] integerValue];
		if (bit <= 0) continue;

		BOOL oldChecked = (oldSelection & bit) != 0;
		BOOL newChecked = (newSelection & bit) != 0;
		if (oldChecked != newChecked) [changed addObject:[NSIndexPath indexPathForRow:i inSection:0]];
	}

	if (changed.count) [self.tableView reloadData];
}

#pragma mark - Table

- (BOOL)hasRawSection { return self.rawJSON.length > 0; }

- (NSInteger)numberOfSectionsInTableView:(__unused UITableView *)tv { return self.hasRawSection ? 2 : 1; }

- (NSInteger)tableView:(__unused UITableView *)tv numberOfRowsInSection:(NSInteger)section {
	return section == 0 ? (NSInteger)self.rows.count : 1;
}

- (NSString *)tableView:(__unused UITableView *)tv titleForHeaderInSection:(NSInteger)section {
	return section == 0 ? SCILocalized(@"Include") : SCILocalized(@"Raw");
}

- (NSString *)tableView:(__unused UITableView *)tv titleForFooterInSection:(NSInteger)section {
	return section == 0 ? self.headerMessage : nil;
}

- (UITableViewCell *)jsonCellForTable:(UITableView *)tv {
	UITableViewCell *cell = [tv dequeueReusableCellWithIdentifier:@"json"];
	if (!cell) cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleSubtitle reuseIdentifier:@"json"];

	cell.textLabel.text = SCILocalized(@"Raw JSON");
	cell.detailTextLabel.text = SCILocalized(@"Inspect the full manifest");
	cell.imageView.image = [UIImage systemImageNamed:@"curlybraces"];
	cell.imageView.tintColor = UIColor.systemGrayColor;
	cell.accessoryType = UITableViewCellAccessoryDisclosureIndicator;
	return cell;
}

- (UITableViewCell *)tableView:(UITableView *)tv cellForRowAtIndexPath:(NSIndexPath *)ip {
	if (ip.section == 1) return [self jsonCellForTable:tv];

	SCIPickerCell *cell = [tv dequeueReusableCellWithIdentifier:@"scope" forIndexPath:ip];
	NSDictionary *r = self.rows[ip.row];

	NSInteger bit = [r[@"bit"] integerValue];
	NSString *symbol = [r[@"symbol"] isKindOfClass:NSString.class] ? r[@"symbol"] : @"circle";
	id color = r[@"color"];

	cell.titleLabel.text = [r[@"title"] isKindOfClass:NSString.class] ? r[@"title"] : @"";
	cell.subtitleLabel.text = [r[@"subtitle"] isKindOfClass:NSString.class] ? r[@"subtitle"] : nil;
	cell.icon.image = [UIImage systemImageNamed:symbol];
	cell.icon.tintColor = [color isKindOfClass:UIColor.class] ? color : UIColor.systemGrayColor;
	cell.accessoryType = [r[@"detailSections"] isKindOfClass:NSArray.class] ? UITableViewCellAccessoryDisclosureIndicator : UITableViewCellAccessoryNone;
	[cell setChecked:(self.selection & bit) != 0];

	__weak typeof(self) weakSelf = self;
	cell.onToggle = ^{ [weakSelf toggleBit:bit]; };
	return cell;
}

- (void)tableView:(UITableView *)tv didSelectRowAtIndexPath:(NSIndexPath *)ip {
	[tv deselectRowAtIndexPath:ip animated:YES];

	if (ip.section == 1) {
		[self pushRawJSON];
		return;
	}

	NSDictionary *r = self.rows[ip.row];
	NSArray *sections = r[@"detailSections"];

	if (![sections isKindOfClass:NSArray.class]) {
		[self toggleBit:[r[@"bit"] integerValue]];
		return;
	}

	SCIBackupDetailVC *vc = [[SCIBackupDetailVC alloc] initWithTitle:r[@"title"] sections:sections];
	[self.navigationController pushViewController:vc animated:YES];
}

- (void)pushRawJSON {
	UIViewController *vc = UIViewController.new;
	vc.title = SCILocalized(@"Raw JSON");
	SCIApplyGlassBackdropToViewController(vc);

	UITextView *tv = UITextView.new;
	tv.translatesAutoresizingMaskIntoConstraints = NO;
	tv.editable = NO;
	tv.font = [UIFont monospacedSystemFontOfSize:11 weight:UIFontWeightRegular];
	tv.text = self.rawJSON ?: @"{}";
	tv.textContainerInset = UIEdgeInsetsMake(12, 12, 12, 12);
	tv.backgroundColor = UIColor.clearColor;
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