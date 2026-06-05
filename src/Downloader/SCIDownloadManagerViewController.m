#import "SCIDownloadManagerViewController.h"
#import "SCIDownloadCenter.h"
#import "Download.h"
#import "../Utils.h"
#import "../UI/SCIPopupChrome.h"
#import <objc/runtime.h>

static NSString *const kHeaderKind = @"sci_dl_header";

@interface SCIDownloadManagerViewController (Helpers)
+ (NSString *)statusTextForJob:(SCIDownloadJob *)job;
@end

#pragma mark - Section header

@interface SCIDownloadSectionHeader : UICollectionReusableView
@property (nonatomic, strong) UILabel *label;
@end

@implementation SCIDownloadSectionHeader
- (instancetype)initWithFrame:(CGRect)frame {
	self = [super initWithFrame:frame];
	if (!self) return nil;
	_label = [UILabel new];
	_label.font = [UIFont systemFontOfSize:13 weight:UIFontWeightSemibold];
	_label.textColor = [UIColor secondaryLabelColor];
	_label.translatesAutoresizingMaskIntoConstraints = NO;
	[self addSubview:_label];
	[NSLayoutConstraint activateConstraints:@[
		[_label.leadingAnchor constraintEqualToAnchor:self.leadingAnchor constant:20],
		[_label.bottomAnchor constraintEqualToAnchor:self.bottomAnchor constant:-6],
		[_label.trailingAnchor constraintEqualToAnchor:self.trailingAnchor constant:-20],
	]];
	return self;
}
@end

#pragma mark - Card cell

static UIColor *sciAccentForState(SCIDownloadJobState s) {
	switch (s) {
		case SCIDownloadJobStateDownloading:
		case SCIDownloadJobStateEncoding:  return [UIColor systemBlueColor];
		case SCIDownloadJobStateQueued:    return [UIColor systemGrayColor];
		case SCIDownloadJobStateWaiting:   return [UIColor systemOrangeColor];
		case SCIDownloadJobStateFinished:  return [UIColor systemGreenColor];
		case SCIDownloadJobStateFailed:    return [UIColor systemRedColor];
		case SCIDownloadJobStateCancelled: return [UIColor systemOrangeColor];
	}
	return [UIColor systemGrayColor];
}

@interface SCIDownloadCardCell : UICollectionViewCell
@property (nonatomic, strong) UIView *card;
@property (nonatomic, strong) UIView *accent;
@property (nonatomic, strong) UIImageView *kindIcon;
@property (nonatomic, strong) UILabel *titleLabel;
@property (nonatomic, strong) UILabel *subtitleLabel;
@property (nonatomic, strong) UILabel *statusLabel;
@property (nonatomic, strong) UIProgressView *progressView;
@property (nonatomic, strong) UIButton *actionButton;
@property (nonatomic, strong) UIImageView *selectMark;
@property (nonatomic, copy) void (^onAction)(void);
- (void)applyJob:(SCIDownloadJob *)job editing:(BOOL)editing selected:(BOOL)selected;
@end

@implementation SCIDownloadCardCell {
	NSLayoutConstraint *_cardLeadingNormal;
	NSLayoutConstraint *_cardLeadingEditing;
}

- (instancetype)initWithFrame:(CGRect)frame {
	self = [super initWithFrame:frame];
	if (!self) return nil;

	_card = [UIView new];
	_card.backgroundColor = [UIColor secondarySystemGroupedBackgroundColor];
	_card.layer.cornerRadius = 14;
	_card.layer.cornerCurve = kCACornerCurveContinuous;
	_card.clipsToBounds = YES;
	_card.translatesAutoresizingMaskIntoConstraints = NO;
	[self.contentView addSubview:_card];

	_accent = [UIView new];
	_accent.translatesAutoresizingMaskIntoConstraints = NO;
	[_card addSubview:_accent];

	_selectMark = [UIImageView new];
	_selectMark.contentMode = UIViewContentModeScaleAspectFit;
	_selectMark.hidden = YES;
	_selectMark.translatesAutoresizingMaskIntoConstraints = NO;

	_kindIcon = [UIImageView new];
	_kindIcon.contentMode = UIViewContentModeScaleAspectFit;
	_kindIcon.translatesAutoresizingMaskIntoConstraints = NO;
	[_kindIcon setContentHuggingPriority:UILayoutPriorityRequired forAxis:UILayoutConstraintAxisHorizontal];

	_titleLabel = [UILabel new];
	_titleLabel.font = [UIFont systemFontOfSize:15 weight:UIFontWeightSemibold];
	_titleLabel.lineBreakMode = NSLineBreakByTruncatingMiddle;

	_subtitleLabel = [UILabel new];
	_subtitleLabel.font = [UIFont systemFontOfSize:12];
	_subtitleLabel.textColor = [UIColor tertiaryLabelColor];

	_statusLabel = [UILabel new];
	_statusLabel.font = [UIFont systemFontOfSize:12.5 weight:UIFontWeightMedium];
	_statusLabel.textColor = [UIColor secondaryLabelColor];

	_progressView = [[UIProgressView alloc] initWithProgressViewStyle:UIProgressViewStyleBar];
	_progressView.layer.cornerRadius = 1.5;
	_progressView.clipsToBounds = YES;

	UIStackView *text = [[UIStackView alloc] initWithArrangedSubviews:@[_titleLabel, _subtitleLabel, _statusLabel, _progressView]];
	text.axis = UILayoutConstraintAxisVertical;
	text.spacing = 3;
	text.translatesAutoresizingMaskIntoConstraints = NO;
	[_card addSubview:text];

	_actionButton = [UIButton buttonWithType:UIButtonTypeSystem];
	_actionButton.translatesAutoresizingMaskIntoConstraints = NO;
	[_actionButton addTarget:self action:@selector(actionTapped) forControlEvents:UIControlEventTouchUpInside];
	UIImageSymbolConfiguration *bigSym = [UIImageSymbolConfiguration configurationWithPointSize:24 weight:UIImageSymbolWeightRegular];
	[_actionButton setPreferredSymbolConfiguration:bigSym forImageInState:UIControlStateNormal];
	[_card addSubview:_actionButton];
	[_card addSubview:_kindIcon];
	[self.contentView addSubview:_selectMark];

	[NSLayoutConstraint activateConstraints:@[
		[_selectMark.leadingAnchor constraintEqualToAnchor:self.contentView.leadingAnchor constant:2],
		[_selectMark.centerYAnchor constraintEqualToAnchor:self.contentView.centerYAnchor],
		[_selectMark.widthAnchor constraintEqualToConstant:24],
		[_selectMark.heightAnchor constraintEqualToConstant:24],

		[_card.topAnchor constraintEqualToAnchor:self.contentView.topAnchor constant:5],
		[_card.bottomAnchor constraintEqualToAnchor:self.contentView.bottomAnchor constant:-5],
		[_card.trailingAnchor constraintEqualToAnchor:self.contentView.trailingAnchor],

		[_accent.leadingAnchor constraintEqualToAnchor:_card.leadingAnchor],
		[_accent.topAnchor constraintEqualToAnchor:_card.topAnchor],
		[_accent.bottomAnchor constraintEqualToAnchor:_card.bottomAnchor],
		[_accent.widthAnchor constraintEqualToConstant:4],

		[_kindIcon.leadingAnchor constraintEqualToAnchor:_card.leadingAnchor constant:16],
		[_kindIcon.centerYAnchor constraintEqualToAnchor:_card.centerYAnchor],
		[_kindIcon.widthAnchor constraintEqualToConstant:24],
		[_kindIcon.heightAnchor constraintEqualToConstant:24],

		[text.leadingAnchor constraintEqualToAnchor:_kindIcon.trailingAnchor constant:12],
		[text.topAnchor constraintEqualToAnchor:_card.topAnchor constant:11],
		[text.bottomAnchor constraintEqualToAnchor:_card.bottomAnchor constant:-11],
		[text.trailingAnchor constraintEqualToAnchor:_actionButton.leadingAnchor constant:-8],

		[_actionButton.trailingAnchor constraintEqualToAnchor:_card.trailingAnchor constant:-10],
		[_actionButton.centerYAnchor constraintEqualToAnchor:_card.centerYAnchor],
		[_actionButton.widthAnchor constraintEqualToConstant:34],
		[_actionButton.heightAnchor constraintEqualToConstant:34],
	]];
	_cardLeadingNormal = [_card.leadingAnchor constraintEqualToAnchor:self.contentView.leadingAnchor];
	_cardLeadingEditing = [_card.leadingAnchor constraintEqualToAnchor:_selectMark.trailingAnchor constant:8];
	_cardLeadingNormal.active = YES;
	return self;
}

- (void)actionTapped { if (self.onAction) self.onAction(); }

- (void)applyJob:(SCIDownloadJob *)job editing:(BOOL)editing selected:(BOOL)selected {
	UIColor *accent = sciAccentForState(job.state);
	self.accent.backgroundColor = accent;

	self.titleLabel.text = job.title;
	self.subtitleLabel.text = job.subtitle;
	self.subtitleLabel.hidden = (job.subtitle.length == 0);
	self.statusLabel.text = [SCIDownloadManagerViewController statusTextForJob:job];

	BOOL active = (job.state == SCIDownloadJobStateDownloading || job.state == SCIDownloadJobStateEncoding);
	self.progressView.hidden = !active;
	self.progressView.progressTintColor = accent;
	if (active) {
		BOOL forward = job.progress >= self.progressView.progress;  // don't animate a reset backwards
		[self.progressView setProgress:job.progress animated:forward];
	}

	switch (job.state) {
		case SCIDownloadJobStateFailed:    self.statusLabel.textColor = [UIColor systemRedColor]; break;
		case SCIDownloadJobStateFinished:  self.statusLabel.textColor = [UIColor systemGreenColor]; break;
		case SCIDownloadJobStateCancelled: self.statusLabel.textColor = [UIColor systemOrangeColor]; break;
		default:                           self.statusLabel.textColor = [UIColor secondaryLabelColor]; break;
	}

	NSString *kindSym;
	switch (job.state) {
		case SCIDownloadJobStateFailed:    kindSym = @"exclamationmark.triangle.fill"; break;
		case SCIDownloadJobStateCancelled: kindSym = @"slash.circle"; break;
		case SCIDownloadJobStateWaiting:   kindSym = @"clock.arrow.circlepath"; break;
		default: kindSym = (job.kind == SCIDownloadJobKindDashMux) ? @"film.fill" : @"arrow.down.circle.fill"; break;
	}
	self.kindIcon.image = [UIImage systemImageNamed:kindSym];
	self.kindIcon.tintColor = accent;

	// Trailing action: cancel in-flight, retry/redownload terminal.
	NSString *actSym = nil;
	if (!job.isTerminal) actSym = @"xmark.circle.fill";
	else if (job.retryBlock) actSym = @"arrow.clockwise.circle.fill";
	[self.actionButton setImage:(actSym ? [UIImage systemImageNamed:actSym] : nil) forState:UIControlStateNormal];
	BOOL isCancel = !job.isTerminal;
	self.actionButton.tintColor = isCancel ? [UIColor systemGray2Color] : [UIColor systemBlueColor];
	self.actionButton.hidden = (actSym == nil) || editing;

	// Editing / selection chrome.
	self.selectMark.hidden = !editing;
	self.selectMark.image = [UIImage systemImageNamed:(selected ? @"checkmark.circle.fill" : @"circle")];
	self.selectMark.tintColor = selected ? [UIColor systemBlueColor] : [UIColor systemGray3Color];
	_cardLeadingNormal.active = !editing;
	_cardLeadingEditing.active = editing;
}
@end

#pragma mark - Settings page (shares prefs with Media saving)

@interface SCIDownloadSettingsViewController : UITableViewController
@end

@implementation SCIDownloadSettingsViewController

- (void)viewDidLoad {
	[super viewDidLoad];
	self.title = SCILocalized(@"Download settings");
	self.view.backgroundColor = [SCIPopupChrome backgroundColor];
}

- (NSInteger)numberOfSectionsInTableView:(UITableView *)tv { return 3; }
- (NSInteger)tableView:(UITableView *)tv numberOfRowsInSection:(NSInteger)s { return s == 1 ? 2 : 1; }
- (NSString *)tableView:(UITableView *)tv titleForHeaderInSection:(NSInteger)s {
	if (s == 0) return SCILocalized(@"Download queue");
	if (s == 1) return SCILocalized(@"Auto-retry");
	return SCILocalized(@"Background");
}
- (NSString *)tableView:(UITableView *)tv titleForFooterInSection:(NSInteger)s {
	if (s == 0) return SCILocalized(@"Extra downloads wait in line and start as slots free up.");
	if (s == 1) return SCILocalized(@"Retry automatically when a download drops on a network error");
	return SCILocalized(@"Don't pause downloads, encoding, or profile scans when you leave the app");
}

- (UITableViewCell *)tableView:(UITableView *)tv cellForRowAtIndexPath:(NSIndexPath *)ip {
	UITableViewCell *cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleValue1 reuseIdentifier:nil];
	cell.selectionStyle = UITableViewCellSelectionStyleNone;

	if (ip.section == 0) {
		cell.textLabel.text = SCILocalized(@"Max simultaneous downloads");
		[self attachStepperTo:cell key:@"dl_max_concurrent" min:1 max:6];
	} else if (ip.section == 1 && ip.row == 0) {
		cell.textLabel.text = SCILocalized(@"Auto-retry failed downloads");
		UISwitch *sw = [UISwitch new];
		sw.on = [SCIUtils getBoolPref:@"dl_auto_retry"];
		[sw addTarget:self action:@selector(autoRetryToggled:) forControlEvents:UIControlEventValueChanged];
		cell.accessoryView = sw;
	} else if (ip.section == 1) {
		cell.textLabel.text = SCILocalized(@"Auto-retry attempts");
		cell.textLabel.enabled = [SCIUtils getBoolPref:@"dl_auto_retry"];
		[self attachStepperTo:cell key:@"dl_auto_retry_count" min:1 max:5];
		((UIStepper *)cell.accessoryView).enabled = [SCIUtils getBoolPref:@"dl_auto_retry"];
	} else {
		cell.textLabel.text = SCILocalized(@"Keep running in background");
		UISwitch *sw = [UISwitch new];
		sw.on = [SCIUtils getBoolPref:@"bg_keepalive"];
		[sw addTarget:self action:@selector(keepAliveToggled:) forControlEvents:UIControlEventValueChanged];
		cell.accessoryView = sw;
	}
	return cell;
}

- (void)attachStepperTo:(UITableViewCell *)cell key:(NSString *)key min:(double)min max:(double)max {
	double v = [SCIUtils getDoublePref:key];
	cell.detailTextLabel.text = [NSString stringWithFormat:@"%d", (int)v];
	UIStepper *st = [UIStepper new];
	st.minimumValue = min; st.maximumValue = max; st.value = v; st.stepValue = 1;
	objc_setAssociatedObject(st, @selector(attachStepperTo:key:min:max:), key, OBJC_ASSOCIATION_COPY_NONATOMIC);
	[st addTarget:self action:@selector(stepperChanged:) forControlEvents:UIControlEventValueChanged];
	cell.accessoryView = st;
}

- (void)stepperChanged:(UIStepper *)st {
	NSString *key = objc_getAssociatedObject(st, @selector(attachStepperTo:key:min:max:));
	[[NSUserDefaults standardUserDefaults] setObject:@((int)st.value) forKey:key];
	UITableViewCell *cell = (UITableViewCell *)st.superview;
	while (cell && ![cell isKindOfClass:UITableViewCell.class]) cell = (id)cell.superview;
	cell.detailTextLabel.text = [NSString stringWithFormat:@"%d", (int)st.value];
}

- (void)autoRetryToggled:(UISwitch *)sw {
	[[NSUserDefaults standardUserDefaults] setObject:@(sw.on) forKey:@"dl_auto_retry"];
	[self.tableView reloadSections:[NSIndexSet indexSetWithIndex:1] withRowAnimation:UITableViewRowAnimationNone];
}

- (void)keepAliveToggled:(UISwitch *)sw {
	[[NSUserDefaults standardUserDefaults] setObject:@(sw.on) forKey:@"bg_keepalive"];
}

@end

#pragma mark - Controller

@interface SCIDownloadManagerViewController () <UICollectionViewDelegate>
@property (nonatomic, strong) UICollectionView *collectionView;
@property (nonatomic, strong) UILabel *emptyLabel;
@property (nonatomic, strong) UICollectionViewDiffableDataSource<NSString *, NSString *> *dataSource;
@property (nonatomic, strong) NSDictionary<NSString *, SCIDownloadJob *> *jobsByID;
@property (nonatomic, strong) NSArray<NSString *> *lastStructure;   // section+item id signature
@property (nonatomic, strong) NSMutableSet<NSString *> *selected;
@property (nonatomic, assign) BOOL selecting;
@property (nonatomic, assign) BOOL reloadPending;
@end

@implementation SCIDownloadManagerViewController

+ (void)load {
	[[SCINotificationCenter shared] setDefaultTapProvider:^{
		return ^{ [SCIDownloadManagerViewController present]; };
	} forAction:SCI_NOTIF_DOWNLOAD];
}

+ (void)present {
	[SCIPopupChrome presentVC:[SCIDownloadManagerViewController new] from:nil];
}

+ (NSString *)statusTextForJob:(SCIDownloadJob *)job {
	switch (job.state) {
		case SCIDownloadJobStateQueued:      return SCILocalized(@"Queued");
		case SCIDownloadJobStateDownloading: return job.stageText ?: SCILocalized(@"Downloading…");
		case SCIDownloadJobStateEncoding:    return job.stageText ?: SCILocalized(@"Encoding…");
		case SCIDownloadJobStateWaiting:     return job.stageText ?: SCILocalized(@"Waiting…");
		case SCIDownloadJobStateFinished:    return job.successText ?: SCILocalized(@"Done");
		case SCIDownloadJobStateFailed:      return job.error.localizedDescription ?: SCILocalized(@"Failed");
		case SCIDownloadJobStateCancelled:   return SCILocalized(@"Cancelled");
	}
	return @"";
}

- (void)viewDidLoad {
	[super viewDidLoad];
	self.title = SCILocalized(@"Downloads");
	self.view.backgroundColor = [SCIPopupChrome backgroundColor];
	self.selected = [NSMutableSet set];

	[self setupCollectionView];
	[self setupDataSource];
	[self updateBars];

	[[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(centerChanged)
	                                             name:SCIDownloadCenterDidChangeNotification object:nil];
	[self applySnapshotAnimated:NO];
}

- (void)dealloc { [[NSNotificationCenter defaultCenter] removeObserver:self]; }

- (void)viewWillAppear:(BOOL)animated {
	[super viewWillAppear:animated];
	self.navigationController.toolbarHidden = NO;
}

#pragma mark - Layout / data source

- (void)setupCollectionView {
	UICollectionViewCompositionalLayoutConfiguration *cfg = [UICollectionViewCompositionalLayoutConfiguration new];
	UICollectionViewLayout *layout = [[UICollectionViewCompositionalLayout alloc] initWithSectionProvider:^NSCollectionLayoutSection *(NSInteger section, id<NSCollectionLayoutEnvironment> env) {
		NSCollectionLayoutSize *itemSize = [NSCollectionLayoutSize sizeWithWidthDimension:[NSCollectionLayoutDimension fractionalWidthDimension:1.0]
		                                                                   heightDimension:[NSCollectionLayoutDimension estimatedDimension:68]];
		NSCollectionLayoutItem *item = [NSCollectionLayoutItem itemWithLayoutSize:itemSize];
		NSCollectionLayoutGroup *group = [NSCollectionLayoutGroup verticalGroupWithLayoutSize:itemSize subitems:@[item]];
		NSCollectionLayoutSection *sec = [NSCollectionLayoutSection sectionWithGroup:group];
		sec.contentInsets = NSDirectionalEdgeInsetsMake(2, 16, 8, 16);
		NSCollectionLayoutSize *hSize = [NSCollectionLayoutSize sizeWithWidthDimension:[NSCollectionLayoutDimension fractionalWidthDimension:1.0]
		                                                               heightDimension:[NSCollectionLayoutDimension estimatedDimension:30]];
		NSCollectionLayoutBoundarySupplementaryItem *header = [NSCollectionLayoutBoundarySupplementaryItem boundarySupplementaryItemWithLayoutSize:hSize elementKind:kHeaderKind alignment:NSRectAlignmentTop];
		sec.boundarySupplementaryItems = @[header];
		return sec;
	} configuration:cfg];

	self.collectionView = [[UICollectionView alloc] initWithFrame:self.view.bounds collectionViewLayout:layout];
	self.collectionView.backgroundColor = [UIColor clearColor];
	self.collectionView.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
	self.collectionView.delegate = self;
	self.collectionView.alwaysBounceVertical = YES;
	[self.view addSubview:self.collectionView];

	UILabel *empty = [UILabel new];
	empty.text = SCILocalized(@"No downloads yet");
	empty.font = [UIFont systemFontOfSize:16 weight:UIFontWeightMedium];
	empty.textColor = [UIColor tertiaryLabelColor];
	empty.textAlignment = NSTextAlignmentCenter;
	self.emptyLabel = empty;
	self.collectionView.backgroundView = empty;
}

- (void)setupDataSource {
	UICollectionViewCellRegistration *cellReg = [UICollectionViewCellRegistration registrationWithCellClass:SCIDownloadCardCell.class
		configurationHandler:^(SCIDownloadCardCell *cell, NSIndexPath *ip, NSString *jobID) {
			SCIDownloadJob *job = self.jobsByID[jobID];
			if (!job) return;
			[cell applyJob:job editing:self.selecting selected:[self.selected containsObject:jobID]];
			__weak typeof(self) weakSelf = self;
			cell.onAction = ^{ [weakSelf handleCardActionForJob:job]; };
		}];

	self.dataSource = [[UICollectionViewDiffableDataSource alloc] initWithCollectionView:self.collectionView
		cellProvider:^UICollectionViewCell *(UICollectionView *cv, NSIndexPath *ip, NSString *jobID) {
			return [cv dequeueConfiguredReusableCellWithRegistration:cellReg forIndexPath:ip item:jobID];
		}];

	UICollectionViewSupplementaryRegistration *headerReg = [UICollectionViewSupplementaryRegistration registrationWithSupplementaryClass:SCIDownloadSectionHeader.class
		elementKind:kHeaderKind configurationHandler:^(SCIDownloadSectionHeader *header, NSString *kind, NSIndexPath *ip) {
			NSString *sectionID = [self.dataSource sectionIdentifierForIndex:ip.section];
			header.label.text = [self titleForSection:sectionID];
		}];
	__weak typeof(self) weakSelf = self;
	self.dataSource.supplementaryViewProvider = ^UICollectionReusableView *(UICollectionView *cv, NSString *kind, NSIndexPath *ip) {
		return [weakSelf.collectionView dequeueConfiguredReusableSupplementaryViewWithRegistration:headerReg forIndexPath:ip];
	};
}

- (NSString *)titleForSection:(NSString *)sectionID {
	if ([sectionID isEqualToString:@"active"])    return SCILocalized(@"Active");
	if ([sectionID isEqualToString:@"waiting"])   return SCILocalized(@"Waiting…");
	if ([sectionID isEqualToString:@"queued"])    return SCILocalized(@"Queued");
	if ([sectionID isEqualToString:@"failed"])    return SCILocalized(@"Failed");
	if ([sectionID isEqualToString:@"cancelled"]) return SCILocalized(@"Cancelled");
	if ([sectionID isEqualToString:@"completed"]) return SCILocalized(@"Completed");
	return @"";
}

#pragma mark - Snapshot

- (void)centerChanged {
	if (self.reloadPending) return;
	self.reloadPending = YES;
	__weak typeof(self) weakSelf = self;
	dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.18 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
		weakSelf.reloadPending = NO;
		[weakSelf applySnapshotAnimated:YES];
	});
}

- (void)applySnapshotAnimated:(BOOL)animated {
	NSMutableArray<SCIDownloadJob *> *active = [NSMutableArray array];
	NSMutableArray<SCIDownloadJob *> *waiting = [NSMutableArray array];
	NSMutableArray<SCIDownloadJob *> *queued = [NSMutableArray array];
	NSMutableArray<SCIDownloadJob *> *done = [NSMutableArray array];
	NSMutableArray<SCIDownloadJob *> *failed = [NSMutableArray array];
	NSMutableArray<SCIDownloadJob *> *cancelled = [NSMutableArray array];
	NSMutableDictionary<NSString *, SCIDownloadJob *> *map = [NSMutableDictionary dictionary];

	for (SCIDownloadJob *j in [[SCIDownloadCenter shared] allJobs]) {
		map[j.jobID] = j;
		switch (j.state) {
			case SCIDownloadJobStateDownloading:
			case SCIDownloadJobStateEncoding:  [active addObject:j]; break;
			case SCIDownloadJobStateWaiting:   [waiting addObject:j]; break;
			case SCIDownloadJobStateQueued:    [queued addObject:j]; break;
			case SCIDownloadJobStateFinished:  [done insertObject:j atIndex:0]; break;
			case SCIDownloadJobStateFailed:    [failed insertObject:j atIndex:0]; break;
			case SCIDownloadJobStateCancelled: [cancelled insertObject:j atIndex:0]; break;
		}
	}
	self.jobsByID = map;
	self.emptyLabel.hidden = (map.count > 0);

	NSDiffableDataSourceSnapshot<NSString *, NSString *> *snap = [NSDiffableDataSourceSnapshot new];
	NSMutableArray<NSString *> *structure = [NSMutableArray array];
	void (^addSec)(NSString *, NSArray<SCIDownloadJob *> *) = ^(NSString *secID, NSArray<SCIDownloadJob *> *jobs) {
		if (!jobs.count) return;
		[snap appendSectionsWithIdentifiers:@[secID]];
		NSMutableArray<NSString *> *ids = [NSMutableArray array];
		for (SCIDownloadJob *j in jobs) [ids addObject:j.jobID];
		[snap appendItemsWithIdentifiers:ids intoSectionWithIdentifier:secID];
		[structure addObject:secID];
		[structure addObjectsFromArray:ids];
	};
	addSec(@"active", active);
	addSec(@"waiting", waiting);
	addSec(@"queued", queued);
	addSec(@"failed", failed);
	addSec(@"cancelled", cancelled);
	addSec(@"completed", done);

	// Always reconfigure — a diffable *move* (active→failed/cancelled) keeps the
	// cell's old content otherwise, leaving a stale progress bar / button.
	if (snap.numberOfItems > 0)
		[snap reconfigureItemsWithIdentifiers:snap.itemIdentifiers];
	BOOL structureSame = [structure isEqualToArray:self.lastStructure];
	self.lastStructure = structure;

	// Drop stale selections.
	[self.selected intersectSet:[NSSet setWithArray:map.allKeys]];

	[self.dataSource applySnapshot:snap animatingDifferences:(animated && !structureSame)];
	[self updateBars];
}

#pragma mark - Bars

- (void)updateBars {
	NSInteger jobCount = self.jobsByID.count;
	UIBarButtonItem *gear = [[UIBarButtonItem alloc] initWithImage:[UIImage systemImageNamed:@"gearshape"]
	                                                         style:UIBarButtonItemStylePlain target:self action:@selector(openSettings)];
	// Leading slot (chrome's X) is never touched here, so the user can always close.
	if (self.selecting) {
		BOOL allSelected = self.jobsByID.count > 0 && self.selected.count == self.jobsByID.count;
		UIBarButtonItem *done = [[UIBarButtonItem alloc] initWithTitle:SCILocalized(@"Done")
			style:UIBarButtonItemStyleDone target:self action:@selector(toggleSelecting)];
		UIBarButtonItem *all = [[UIBarButtonItem alloc]
			initWithTitle:(allSelected ? SCILocalized(@"Deselect All") : SCILocalized(@"Select All"))
			style:UIBarButtonItemStylePlain target:self action:@selector(selectAllTapped)];
		self.navigationItem.rightBarButtonItems = @[done, all];
	} else if (jobCount) {
		UIBarButtonItem *select = [[UIBarButtonItem alloc] initWithTitle:SCILocalized(@"Select")
			style:UIBarButtonItemStylePlain target:self action:@selector(toggleSelecting)];
		self.navigationItem.rightBarButtonItems = @[select, gear];
	} else {
		self.navigationItem.rightBarButtonItems = @[gear];
	}

	UIBarButtonItem *flex = [[UIBarButtonItem alloc] initWithBarButtonSystemItem:UIBarButtonSystemItemFlexibleSpace target:nil action:nil];

	if (self.selecting) {
		UIBarButtonItem *cancel = [[UIBarButtonItem alloc] initWithTitle:SCILocalized(@"Cancel") style:UIBarButtonItemStylePlain target:self action:@selector(bulkCancel)];
		UIBarButtonItem *retry  = [[UIBarButtonItem alloc] initWithTitle:SCILocalized(@"Retry") style:UIBarButtonItemStylePlain target:self action:@selector(bulkRetry)];
		UIBarButtonItem *remove = [[UIBarButtonItem alloc] initWithTitle:SCILocalized(@"Remove") style:UIBarButtonItemStylePlain target:self action:@selector(bulkRemove)];
		remove.tintColor = [UIColor systemRedColor];
		BOOL any = self.selected.count > 0;
		cancel.enabled = retry.enabled = remove.enabled = any;
		self.toolbarItems = @[cancel, flex, retry, flex, remove];
	} else {
		UIBarButtonItem *clear = [[UIBarButtonItem alloc] initWithTitle:SCILocalized(@"Clear completed") style:UIBarButtonItemStylePlain target:self action:@selector(clearTapped)];
		self.toolbarItems = @[flex, clear, flex];
	}
}

- (void)toggleSelecting {
	self.selecting = !self.selecting;
	if (!self.selecting) [self.selected removeAllObjects];
	[self updateBars];
	// Reconfigure all to show/hide select chrome.
	self.lastStructure = nil;
	[self applySnapshotAnimated:NO];
}

- (void)selectAllTapped {
	if (self.selected.count == self.jobsByID.count) [self.selected removeAllObjects];
	else { [self.selected removeAllObjects]; [self.selected addObjectsFromArray:self.jobsByID.allKeys]; }
	[self updateBars];
	self.lastStructure = nil;
	[self applySnapshotAnimated:NO];
}

- (void)clearTapped { [[SCIDownloadCenter shared] clearFinished]; }

- (void)openSettings {
	UIViewController *vc = [[SCIDownloadSettingsViewController alloc] initWithStyle:UITableViewStyleInsetGrouped];
	[self.navigationController pushViewController:vc animated:YES];
}

// Refresh immediately (don't wait for the throttle) so the button flips state
// before a second tap can land — otherwise a stale "cancel" tap becomes a retry.
- (void)handleCardActionForJob:(SCIDownloadJob *)job {
	SCIDownloadCenter *center = [SCIDownloadCenter shared];
	if (!job.isTerminal) [center cancelJob:job];
	else if (job.retryBlock) [center retryJob:job];
	[self applySnapshotAnimated:YES];
}

- (void)forEachSelectedJob:(void (^)(SCIDownloadJob *job))block {
	for (NSString *jobID in [self.selected copy]) {
		SCIDownloadJob *j = self.jobsByID[jobID];
		if (j) block(j);
	}
}

- (void)bulkCancel {
	SCIDownloadCenter *c = [SCIDownloadCenter shared];
	[self forEachSelectedJob:^(SCIDownloadJob *j) { if (!j.isTerminal) [c cancelJob:j]; }];
	[self exitSelection];
}
- (void)bulkRetry {
	SCIDownloadCenter *c = [SCIDownloadCenter shared];
	[self forEachSelectedJob:^(SCIDownloadJob *j) { if (j.isTerminal && j.retryBlock) [c retryJob:j]; }];
	[self exitSelection];
}
- (void)bulkRemove {
	SCIDownloadCenter *c = [SCIDownloadCenter shared];
	[self forEachSelectedJob:^(SCIDownloadJob *j) { if (j.isTerminal) [c removeJob:j]; }];
	[self exitSelection];
}
- (void)exitSelection {
	[self.selected removeAllObjects];
	self.selecting = NO;
	self.lastStructure = nil;
	[self updateBars];
	[self applySnapshotAnimated:YES];
}

#pragma mark - Selection / tap

- (void)collectionView:(UICollectionView *)collectionView didSelectItemAtIndexPath:(NSIndexPath *)indexPath {
	[collectionView deselectItemAtIndexPath:indexPath animated:NO];
	NSString *jobID = [self.dataSource itemIdentifierForIndexPath:indexPath];
	SCIDownloadJob *job = self.jobsByID[jobID];
	if (!job) return;

	if (self.selecting) {
		if ([self.selected containsObject:jobID]) [self.selected removeObject:jobID];
		else [self.selected addObject:jobID];
		[self updateBars];
		NSDiffableDataSourceSnapshot *snap = self.dataSource.snapshot;
		[snap reconfigureItemsWithIdentifiers:@[jobID]];
		[self.dataSource applySnapshot:snap animatingDifferences:NO];
		return;
	}

	if (job.state == SCIDownloadJobStateFinished && job.resultFileURL)
		[SCIUtils showQuickLookVC:@[job.resultFileURL]];
}

#pragma mark - Context menu (long press)

- (UIContextMenuConfiguration *)collectionView:(UICollectionView *)collectionView
        contextMenuConfigurationForItemAtIndexPath:(NSIndexPath *)indexPath
                                             point:(CGPoint)point {
	NSString *jobID = [self.dataSource itemIdentifierForIndexPath:indexPath];
	SCIDownloadJob *job = self.jobsByID[jobID];
	if (!job) return nil;
	__weak typeof(self) weakSelf = self;
	return [UIContextMenuConfiguration configurationWithIdentifier:nil
	                                              previewProvider:nil
	                                               actionProvider:^UIMenu *(NSArray<UIMenuElement *> *suggested) {
		return [weakSelf menuForJob:job];
	}];
}

- (UIMenu *)menuForJob:(SCIDownloadJob *)job {
	SCIDownloadCenter *center = [SCIDownloadCenter shared];
	NSMutableArray<UIMenuElement *> *items = [NSMutableArray array];

	if (!job.isTerminal) {
		UIAction *cancel = [UIAction actionWithTitle:SCILocalized(@"Cancel") image:[UIImage systemImageNamed:@"xmark.circle"] identifier:nil handler:^(__unused id a) { [center cancelJob:job]; }];
		cancel.attributes = UIMenuElementAttributesDestructive;
		return [UIMenu menuWithTitle:@"" children:@[cancel]];
	}

	NSURL *file = job.resultFileURL;
	BOOL exists = file && [NSFileManager.defaultManager fileExistsAtPath:file.path];
	if (exists) {
		[items addObject:[UIAction actionWithTitle:SCILocalized(@"Preview") image:[UIImage systemImageNamed:@"eye"] identifier:nil handler:^(__unused id a) { [SCIUtils showQuickLookVC:@[file]]; }]];
		[items addObject:[UIAction actionWithTitle:SCILocalized(@"Share") image:[UIImage systemImageNamed:@"square.and.arrow.up"] identifier:nil handler:^(__unused id a) { [SCIUtils showShareVC:file]; }]];
		[items addObject:[UIAction actionWithTitle:SCILocalized(@"Save to Photos") image:[UIImage systemImageNamed:@"square.and.arrow.down"] identifier:nil handler:^(__unused id a) { [self saveLocalFile:file action:saveToPhotos]; }]];
		if ([SCIUtils getBoolPref:@"sci_gallery_enabled"])
			[items addObject:[UIAction actionWithTitle:SCILocalized(@"Save to Gallery") image:[UIImage systemImageNamed:@"square.stack"] identifier:nil handler:^(__unused id a) { [self saveLocalFile:file action:saveToGallery]; }]];
	}

	if (job.retryBlock)
		[items addObject:[UIAction actionWithTitle:SCILocalized(@"Redownload") image:[UIImage systemImageNamed:@"arrow.clockwise"] identifier:nil handler:^(__unused id a) { [center retryJob:job]; }]];

	UIAction *remove = [UIAction actionWithTitle:SCILocalized(@"Remove") image:[UIImage systemImageNamed:@"trash"] identifier:nil handler:^(__unused id a) { [center removeJob:job]; }];
	remove.attributes = UIMenuElementAttributesDestructive;
	[items addObject:remove];

	return [UIMenu menuWithTitle:@"" children:items];
}

- (void)saveLocalFile:(NSURL *)file action:(DownloadAction)action {
	SCIDownloadDelegate *dl = [[SCIDownloadDelegate alloc] initWithAction:action showProgress:NO];
	[dl saveLocalFileURL:file hudLabel:nil];
}

@end
