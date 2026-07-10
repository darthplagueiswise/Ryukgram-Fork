#import "SCIFollowRequestsViewController.h"
#import "SCIFollowRequestStorage.h"
#import "SCIFollowRequestModels.h"
#import "SCIFollowRequestTracker.h"
#import "../../Utils.h"
#import "../../SCIImageCache.h"
#import "../../SCIURLOpener.h"
#import "../../Networking/SCIInstagramAPI.h"
#import "../../Settings/SCISearchBarStyler.h"
#import "../../UI/SCIPopupChrome.h"
#import "../../Localization/SCILocalization.h"

typedef NS_ENUM(NSInteger, SCIFRFilter) {
	SCIFRFilterAll = 0,
	SCIFRFilterSent,
	SCIFRFilterAccepted,
	SCIFRFilterRejected,
	SCIFRFilterCancelled,
};

typedef NS_ENUM(NSInteger, SCIFRSort) {
	SCIFRSortNewest = 0,
	SCIFRSortOldest,
	SCIFRSortNameAZ,
};

static NSString *frPicKey(SCIFollowRequest *r) {
	if (r.profilePicID.length) return [@"frpic:" stringByAppendingString:r.profilePicID];
	if (r.profilePicURL.length) return [@"frurl:" stringByAppendingString:r.profilePicURL];
	return [@"frpk:" stringByAppendingString:(r.userPK ?: @"?")];
}

#pragma mark - Cell

@interface SCIFRCell : UITableViewCell
@property (nonatomic, strong) UIImageView *avatar;
@property (nonatomic, strong) UILabel *nameLabel;
@property (nonatomic, strong) UILabel *subLabel;       // status + outcome time
@property (nonatomic, strong) UILabel *appearedLabel;  // when it was sent/received
@property (nonatomic, strong) UIImageView *typeIcon;
@property (nonatomic, strong) UIButton *actionButton;
@property (nonatomic, strong) UIActivityIndicatorView *spinner;
@property (nonatomic, copy) NSString *boundPK;
@property (nonatomic, copy) void (^onAction)(SCIFRCell *);
@end

@implementation SCIFRCell

- (instancetype)initWithStyle:(UITableViewCellStyle)style reuseIdentifier:(NSString *)rid {
	self = [super initWithStyle:UITableViewCellStyleDefault reuseIdentifier:rid];
	if (!self) return self;
	self.selectionStyle = UITableViewCellSelectionStyleDefault;

	_avatar = [UIImageView new];
	_avatar.translatesAutoresizingMaskIntoConstraints = NO;
	_avatar.layer.cornerRadius = 24;
	_avatar.clipsToBounds = YES;
	_avatar.contentMode = UIViewContentModeScaleAspectFill;
	_avatar.backgroundColor = UIColor.secondarySystemBackgroundColor;

	_typeIcon = [UIImageView new];
	_typeIcon.translatesAutoresizingMaskIntoConstraints = NO;
	_typeIcon.contentMode = UIViewContentModeScaleAspectFit;
	[_typeIcon setContentHuggingPriority:UILayoutPriorityRequired forAxis:UILayoutConstraintAxisHorizontal];
	[NSLayoutConstraint activateConstraints:@[
		[_typeIcon.widthAnchor constraintEqualToConstant:14],
		[_typeIcon.heightAnchor constraintEqualToConstant:14],
	]];

	_nameLabel = [UILabel new];
	_nameLabel.font = [UIFont systemFontOfSize:15 weight:UIFontWeightSemibold];
	_nameLabel.textColor = UIColor.labelColor;
	_nameLabel.lineBreakMode = NSLineBreakByTruncatingTail;

	_subLabel = [UILabel new];
	_subLabel.font = [UIFont systemFontOfSize:13 weight:UIFontWeightMedium];
	_subLabel.textColor = UIColor.secondaryLabelColor;

	_appearedLabel = [UILabel new];
	_appearedLabel.font = [UIFont systemFontOfSize:12];
	_appearedLabel.textColor = UIColor.tertiaryLabelColor;

	// Line 2: small status icon + status/outcome text.
	UIStackView *statusRow = [[UIStackView alloc] initWithArrangedSubviews:@[_typeIcon, _subLabel]];
	statusRow.axis = UILayoutConstraintAxisHorizontal;
	statusRow.alignment = UIStackViewAlignmentCenter;
	statusRow.spacing = 5;

	UIStackView *textStack = [[UIStackView alloc] initWithArrangedSubviews:@[_nameLabel, statusRow, _appearedLabel]];
	textStack.axis = UILayoutConstraintAxisVertical;
	textStack.alignment = UIStackViewAlignmentLeading;
	textStack.spacing = 2;
	textStack.translatesAutoresizingMaskIntoConstraints = NO;

	_actionButton = [UIButton buttonWithType:UIButtonTypeSystem];
	_actionButton.translatesAutoresizingMaskIntoConstraints = NO;
	_actionButton.titleLabel.font = [UIFont systemFontOfSize:13 weight:UIFontWeightSemibold];
	_actionButton.titleLabel.adjustsFontSizeToFitWidth = YES;
	_actionButton.titleLabel.minimumScaleFactor = 0.85;
	_actionButton.contentEdgeInsets = UIEdgeInsetsMake(7, 10, 7, 10);
	_actionButton.layer.cornerRadius = 8;
	[_actionButton setContentHuggingPriority:UILayoutPriorityRequired forAxis:UILayoutConstraintAxisHorizontal];
	[_actionButton setContentCompressionResistancePriority:UILayoutPriorityRequired forAxis:UILayoutConstraintAxisHorizontal];
	[_actionButton addTarget:self action:@selector(tapAction) forControlEvents:UIControlEventTouchUpInside];

	_spinner = [[UIActivityIndicatorView alloc] initWithActivityIndicatorStyle:UIActivityIndicatorViewStyleMedium];
	_spinner.translatesAutoresizingMaskIntoConstraints = NO;
	_spinner.hidesWhenStopped = YES;

	[self.contentView addSubview:_avatar];
	[self.contentView addSubview:textStack];
	[self.contentView addSubview:_actionButton];
	[self.contentView addSubview:_spinner];

	UILayoutGuide *g = self.contentView.layoutMarginsGuide;
	[NSLayoutConstraint activateConstraints:@[
		[_avatar.leadingAnchor constraintEqualToAnchor:g.leadingAnchor],
		[_avatar.centerYAnchor constraintEqualToAnchor:self.contentView.centerYAnchor],
		[_avatar.widthAnchor constraintEqualToConstant:48],
		[_avatar.heightAnchor constraintEqualToConstant:48],

		[_actionButton.trailingAnchor constraintEqualToAnchor:g.trailingAnchor],
		[_actionButton.centerYAnchor constraintEqualToAnchor:self.contentView.centerYAnchor],
		[_actionButton.widthAnchor constraintLessThanOrEqualToConstant:120],
		[_spinner.centerXAnchor constraintEqualToAnchor:_actionButton.centerXAnchor],
		[_spinner.centerYAnchor constraintEqualToAnchor:_actionButton.centerYAnchor],

		[textStack.leadingAnchor constraintEqualToAnchor:_avatar.trailingAnchor constant:12],
		[textStack.trailingAnchor constraintEqualToAnchor:_actionButton.leadingAnchor constant:-10],
		[textStack.centerYAnchor constraintEqualToAnchor:self.contentView.centerYAnchor],
	]];
	return self;
}

- (void)tapAction { if (self.onAction) self.onAction(self); }

- (void)setLoading:(BOOL)loading {
	if (loading) { [self.spinner startAnimating]; self.actionButton.hidden = YES; }
	else { [self.spinner stopAnimating]; self.actionButton.hidden = NO; }
}

- (void)configureWithRequest:(SCIFollowRequest *)r {
	self.boundPK = r.userPK;
	self.nameLabel.text = r.displayName;

	NSString *typeStr = [SCIFollowRequest stringForType:r.type];
	NSString *appeared = [SCIFRCell relativeDate:r.sentAt];
	NSString *origVerb = r.direction == SCIFollowRequestDirectionIncoming ? SCILocalized(@"Received") : SCILocalized(@"Sent");
	if (r.isPending) {
		self.subLabel.text = appeared.length ? [NSString stringWithFormat:@"%@ · %@", typeStr, appeared] : typeStr;
		self.appearedLabel.hidden = YES;
	} else {
		// Outcome + when it was detected, then when it originally appeared.
		NSString *outcome = [SCIFRCell relativeDate:r.resolvedAt];
		self.subLabel.text = outcome.length ? [NSString stringWithFormat:@"%@ · %@", typeStr, outcome] : typeStr;
		self.appearedLabel.text = appeared.length ? [NSString stringWithFormat:@"%@ %@", origVerb, appeared] : @"";
		self.appearedLabel.hidden = (appeared.length == 0);
	}
	self.subLabel.textColor = [SCIFollowRequest colorForType:r.type];

	UIImageSymbolConfiguration *cfg = [UIImageSymbolConfiguration configurationWithPointSize:13 weight:UIImageSymbolWeightSemibold];
	self.typeIcon.image = [UIImage systemImageNamed:[SCIFollowRequest symbolForType:r.type] withConfiguration:cfg];
	self.typeIcon.tintColor = [SCIFollowRequest colorForType:r.type];

	[self applyActionStyleForType:r.type];

	self.avatar.image = nil;
	NSString *key = frPicKey(r);
	NSURL *url = r.profilePicURL.length ? [NSURL URLWithString:r.profilePicURL] : nil;
	if (url) {
		NSString *bound = self.boundPK;
		[SCIImageCache loadImageFromURL:url cacheKey:key completion:^(UIImage *image) {
			if (image && [self.boundPK isEqualToString:bound]) self.avatar.image = image;
		}];
	}
	if (!self.avatar.image) {
		self.avatar.image = [UIImage systemImageNamed:@"person.crop.circle.fill"];
		self.avatar.tintColor = UIColor.tertiaryLabelColor;
	}
	[self setLoading:NO];
}

- (void)applyActionStyleForType:(SCIFollowRequestType)type {
	NSString *title; UIColor *bg; UIColor *fg;
	switch (type) {
		case SCIFollowRequestTypeSent:
			title = SCILocalized(@"Requested"); bg = UIColor.tertiarySystemFillColor; fg = UIColor.labelColor; break;
		case SCIFollowRequestTypeAccepted:
			title = SCILocalized(@"Following"); bg = UIColor.tertiarySystemFillColor; fg = UIColor.labelColor; break;
		case SCIFollowRequestTypeRejected:
		case SCIFollowRequestTypeCancelled:
			title = SCILocalized(@"Follow"); bg = UIColor.systemBlueColor; fg = UIColor.whiteColor; break;
		default: // incoming — follow the requester back
			title = SCILocalized(@"Follow back"); bg = UIColor.systemBlueColor; fg = UIColor.whiteColor; break;
	}
	[self.actionButton setTitle:title forState:UIControlStateNormal];
	[self.actionButton setTitleColor:fg forState:UIControlStateNormal];
	self.actionButton.backgroundColor = bg;
}

+ (NSString *)relativeDate:(NSTimeInterval)ts {
	if (ts <= 0) return @"";
	static NSDateFormatter *df; static dispatch_once_t once;
	dispatch_once(&once, ^{ df = [NSDateFormatter new]; df.dateStyle = NSDateFormatterMediumStyle; df.timeStyle = NSDateFormatterNoStyle; });
	NSTimeInterval ago = [NSDate date].timeIntervalSince1970 - ts;
	if (ago < 60) return SCILocalized(@"just now");
	if (ago < 3600) return [NSString stringWithFormat:SCILocalized(@"%ld minutes ago"), (long)(ago / 60)];
	if (ago < 86400) return [NSString stringWithFormat:SCILocalized(@"%ld hours ago"), (long)(ago / 3600)];
	if (ago < 604800) return [NSString stringWithFormat:SCILocalized(@"%ld days ago"), (long)(ago / 86400)];
	return [df stringFromDate:[NSDate dateWithTimeIntervalSince1970:ts]];
}

@end

#pragma mark - Controller

@interface SCIFollowRequestsViewController () <UITableViewDataSource, UITableViewDelegate, UISearchResultsUpdating, UISearchControllerDelegate>
@property (nonatomic, strong) UITableView *tableView;
@property (nonatomic, strong) UISegmentedControl *scopeControl;
@property (nonatomic, strong) UISegmentedControl *filterControl;
@property (nonatomic, strong) UISearchController *searchController;
@property (nonatomic, strong) UILabel *emptyLabel;
@property (nonatomic, strong) NSArray<SCIFollowRequest *> *all;
@property (nonatomic, strong) NSArray<SCIFollowRequest *> *shown;
@property (nonatomic, assign) SCIFollowRequestDirection scope;
@property (nonatomic, assign) SCIFRFilter filter;
@property (nonatomic, assign) SCIFRSort sortMode;
@property (nonatomic, assign) BOOL selectMode;
@property (nonatomic, strong) UIView *bottomBar;
@property (nonatomic, strong) UIButton *bulkActionBtn;
@property (nonatomic, strong) UIButton *bulkDeleteBtn;
@end

@implementation SCIFollowRequestsViewController {
	SCIFollowRequestDirection _initialScope;
}

- (instancetype)initWithScope:(SCIFollowRequestDirection)scope {
	if ((self = [super init])) _initialScope = scope;
	return self;
}

+ (void)presentAtScope:(SCIFollowRequestDirection)scope {
	dispatch_async(dispatch_get_main_queue(), ^{
		[SCIPopupChrome presentVC:[[SCIFollowRequestsViewController alloc] initWithScope:scope] from:nil];
	});
}

- (void)viewDidLoad {
	[super viewDidLoad];
	self.title = SCILocalized(@"Follow Requests");
	self.view.backgroundColor = UIColor.systemBackgroundColor;
	self.sortMode = SCIFRSortNewest;

	self.scope = _initialScope;
	self.scopeControl = [[UISegmentedControl alloc] initWithItems:@[ SCILocalized(@"Sent by me"), SCILocalized(@"Received") ]];
	self.scopeControl.selectedSegmentIndex = (self.scope == SCIFollowRequestDirectionIncoming) ? 1 : 0;
	[self.scopeControl addTarget:self action:@selector(scopeChanged) forControlEvents:UIControlEventValueChanged];

	self.filterControl = [[UISegmentedControl alloc] initWithItems:@[@"", @"", @"", @"", @""]];
	self.filterControl.selectedSegmentIndex = 0;
	[self.filterControl addTarget:self action:@selector(filterChanged) forControlEvents:UIControlEventValueChanged];
	[self rebuildFilterSegments];

	UIView *header = [[UIView alloc] initWithFrame:CGRectMake(0, 0, self.view.bounds.size.width, 92)];
	self.scopeControl.translatesAutoresizingMaskIntoConstraints = NO;
	self.filterControl.translatesAutoresizingMaskIntoConstraints = NO;
	[header addSubview:self.scopeControl];
	[header addSubview:self.filterControl];
	[NSLayoutConstraint activateConstraints:@[
		[self.scopeControl.leadingAnchor constraintEqualToAnchor:header.layoutMarginsGuide.leadingAnchor],
		[self.scopeControl.trailingAnchor constraintEqualToAnchor:header.layoutMarginsGuide.trailingAnchor],
		[self.scopeControl.topAnchor constraintEqualToAnchor:header.topAnchor constant:8],
		[self.filterControl.leadingAnchor constraintEqualToAnchor:header.layoutMarginsGuide.leadingAnchor],
		[self.filterControl.trailingAnchor constraintEqualToAnchor:header.layoutMarginsGuide.trailingAnchor],
		[self.filterControl.topAnchor constraintEqualToAnchor:self.scopeControl.bottomAnchor constant:8],
	]];

	self.tableView = [[UITableView alloc] initWithFrame:self.view.bounds style:UITableViewStylePlain];
	self.tableView.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
	self.tableView.dataSource = self;
	self.tableView.delegate = self;
	self.tableView.rowHeight = 76;
	self.tableView.separatorInset = UIEdgeInsetsMake(0, 76, 0, 0);
	self.tableView.tableHeaderView = header;
	self.tableView.allowsMultipleSelectionDuringEditing = YES;
	[self.tableView registerClass:[SCIFRCell class] forCellReuseIdentifier:@"cell"];
	[self.view addSubview:self.tableView];

	[self setupBottomBar];

	UIRefreshControl *rc = [UIRefreshControl new];
	[rc addTarget:self action:@selector(pullToRefresh:) forControlEvents:UIControlEventValueChanged];
	self.tableView.refreshControl = rc;

	self.emptyLabel = [UILabel new];
	self.emptyLabel.text = SCILocalized(@"No follow requests tracked yet");
	self.emptyLabel.textColor = UIColor.tertiaryLabelColor;
	self.emptyLabel.font = [UIFont systemFontOfSize:15];
	self.emptyLabel.textAlignment = NSTextAlignmentCenter;
	self.emptyLabel.numberOfLines = 0;
	self.emptyLabel.translatesAutoresizingMaskIntoConstraints = NO;
	[self.view addSubview:self.emptyLabel];
	[NSLayoutConstraint activateConstraints:@[
		[self.emptyLabel.centerXAnchor constraintEqualToAnchor:self.view.centerXAnchor],
		[self.emptyLabel.centerYAnchor constraintEqualToAnchor:self.view.centerYAnchor],
		[self.emptyLabel.leadingAnchor constraintEqualToAnchor:self.view.leadingAnchor constant:32],
		[self.emptyLabel.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor constant:-32],
	]];

	self.searchController = [[UISearchController alloc] initWithSearchResultsController:nil];
	self.searchController.searchResultsUpdater = self;
	self.searchController.delegate = self;
	self.searchController.obscuresBackgroundDuringPresentation = NO;
	self.searchController.searchBar.placeholder = SCILocalized(@"Search by username or name");
	self.navigationItem.searchController = self.searchController;
	self.navigationItem.hidesSearchBarWhenScrolling = NO;
	self.definesPresentationContext = YES;

	[self updateRightBarButton];

	[NSNotificationCenter.defaultCenter addObserver:self selector:@selector(storeChanged)
											   name:SCIFollowRequestsDidChangeNotification object:nil];
	[self reload];
	[SCIFollowRequestStorage markAllSeenForOwnerPK:[SCIUtils currentUserPK]];
}

- (void)dealloc { [NSNotificationCenter.defaultCenter removeObserver:self]; }

- (void)viewWillAppear:(BOOL)animated {
	[super viewWillAppear:animated];
	[self sciStyleSearchBar];
	[self reload];
	[[SCIFollowRequestTracker shared] checkNowForced:NO completion:nil]; // event-driven, throttled
}
- (void)sciStyleSearchBar { [SCISearchBarStyler styleSearchBar:self.searchController.searchBar]; }
- (void)willPresentSearchController:(UISearchController *)sc { [self sciStyleSearchBar]; }

- (void)updateRightBarButton {
	if (self.selectMode) {
		UIBarButtonItem *done = [[UIBarButtonItem alloc] initWithBarButtonSystemItem:UIBarButtonSystemItemDone target:self action:@selector(toggleSelectMode)];
		UIBarButtonItem *all = [[UIBarButtonItem alloc] initWithTitle:SCILocalized(@"Select All") style:UIBarButtonItemStylePlain target:self action:@selector(toggleSelectAll)];
		self.navigationItem.rightBarButtonItems = @[done, all];
		return;
	}
	UIBarButtonItem *select = [[UIBarButtonItem alloc] initWithImage:[UIImage systemImageNamed:@"checkmark.circle"]
															   style:UIBarButtonItemStylePlain target:self action:@selector(toggleSelectMode)];
	UIBarButtonItem *sort = [[UIBarButtonItem alloc] initWithImage:[UIImage systemImageNamed:@"arrow.up.arrow.down"] menu:[self sortMenu]];
	UIBarButtonItem *clear = [[UIBarButtonItem alloc] initWithImage:[UIImage systemImageNamed:@"trash"]
															  style:UIBarButtonItemStylePlain target:self action:@selector(clearAll)];
	self.navigationItem.rightBarButtonItems = @[clear, sort, select];
}

#pragma mark - Select / bulk

- (void)setupBottomBar {
	self.bottomBar = [[UIView alloc] init];
	self.bottomBar.translatesAutoresizingMaskIntoConstraints = NO;
	self.bottomBar.backgroundColor = [UIColor.systemBackgroundColor colorWithAlphaComponent:0.96];
	self.bottomBar.hidden = YES;
	UIView *hair = [UIView new];
	hair.translatesAutoresizingMaskIntoConstraints = NO;
	hair.backgroundColor = UIColor.separatorColor;
	[self.bottomBar addSubview:hair];

	self.bulkActionBtn = [self barButtonTitle:@"" color:UIColor.systemBlueColor action:@selector(bulkPrimary)];
	self.bulkDeleteBtn = [self barButtonTitle:SCILocalized(@"Delete") color:UIColor.systemRedColor action:@selector(bulkDelete)];
	UIStackView *stack = [[UIStackView alloc] initWithArrangedSubviews:@[self.bulkActionBtn, self.bulkDeleteBtn]];
	stack.axis = UILayoutConstraintAxisHorizontal;
	stack.distribution = UIStackViewDistributionFillEqually;
	stack.spacing = 8;
	stack.translatesAutoresizingMaskIntoConstraints = NO;
	[self.bottomBar addSubview:stack];
	[self.view addSubview:self.bottomBar];

	[NSLayoutConstraint activateConstraints:@[
		[self.bottomBar.leadingAnchor constraintEqualToAnchor:self.view.leadingAnchor],
		[self.bottomBar.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor],
		[self.bottomBar.bottomAnchor constraintEqualToAnchor:self.view.bottomAnchor],
		[hair.topAnchor constraintEqualToAnchor:self.bottomBar.topAnchor],
		[hair.leadingAnchor constraintEqualToAnchor:self.bottomBar.leadingAnchor],
		[hair.trailingAnchor constraintEqualToAnchor:self.bottomBar.trailingAnchor],
		[hair.heightAnchor constraintEqualToConstant:0.5],
		[stack.topAnchor constraintEqualToAnchor:self.bottomBar.topAnchor constant:8],
		[stack.leadingAnchor constraintEqualToAnchor:self.bottomBar.leadingAnchor constant:16],
		[stack.trailingAnchor constraintEqualToAnchor:self.bottomBar.trailingAnchor constant:-16],
		[stack.bottomAnchor constraintEqualToAnchor:self.bottomBar.safeAreaLayoutGuide.bottomAnchor constant:-8],
	]];
}

- (UIButton *)barButtonTitle:(NSString *)title color:(UIColor *)color action:(SEL)action {
	UIButton *b = [UIButton buttonWithType:UIButtonTypeSystem];
	[b setTitle:title forState:UIControlStateNormal];
	[b setTitleColor:color forState:UIControlStateNormal];
	b.titleLabel.font = [UIFont systemFontOfSize:16 weight:UIFontWeightSemibold];
	b.backgroundColor = [color colorWithAlphaComponent:0.12];
	b.layer.cornerRadius = 10;
	[b.heightAnchor constraintEqualToConstant:44].active = YES;
	[b addTarget:self action:action forControlEvents:UIControlEventTouchUpInside];
	return b;
}

- (void)toggleSelectMode {
	self.selectMode = !self.selectMode;
	[self.tableView setEditing:self.selectMode animated:YES];
	self.bottomBar.hidden = !self.selectMode;
	self.navigationItem.searchController = self.selectMode ? nil : self.searchController;
	UIEdgeInsets ins = self.tableView.contentInset;
	ins.bottom = self.selectMode ? (60 + self.view.safeAreaInsets.bottom) : 0;
	self.tableView.contentInset = ins;
	[self updateRightBarButton];
	[self updateBulkBar];
	[self.tableView reloadData]; // refresh per-row action button visibility
}

- (void)toggleSelectAll {
	NSArray *sel = [self.tableView indexPathsForSelectedRows];
	if (sel.count == self.shown.count) {
		for (NSIndexPath *ip in sel) [self.tableView deselectRowAtIndexPath:ip animated:NO];
	} else {
		for (NSInteger i = 0; i < (NSInteger)self.shown.count; i++)
			[self.tableView selectRowAtIndexPath:[NSIndexPath indexPathForRow:i inSection:0] animated:NO scrollPosition:UITableViewScrollPositionNone];
	}
	[self updateBulkBar];
}

- (NSArray<SCIFollowRequest *> *)selectedRequests {
	NSMutableArray *out = [NSMutableArray array];
	for (NSIndexPath *ip in [self.tableView indexPathsForSelectedRows]) if (ip.row < (NSInteger)self.shown.count) [out addObject:self.shown[ip.row]];
	return out;
}

- (void)updateBulkBar {
	NSUInteger n = [self.tableView indexPathsForSelectedRows].count;
	NSString *del = n ? [NSString stringWithFormat:SCILocalized(@"Delete (%lu)"), (unsigned long)n] : SCILocalized(@"Delete");
	[self.bulkDeleteBtn setTitle:del forState:UIControlStateNormal];

	NSString *primary = self.scope == SCIFollowRequestDirectionIncoming ? SCILocalized(@"Follow back") : SCILocalized(@"Cancel requests");
	if (n) primary = [NSString stringWithFormat:@"%@ (%lu)", primary, (unsigned long)n];
	[self.bulkActionBtn setTitle:primary forState:UIControlStateNormal];

	self.bulkDeleteBtn.enabled = self.bulkActionBtn.enabled = n > 0;
	self.bulkDeleteBtn.alpha = self.bulkActionBtn.alpha = n > 0 ? 1.0 : 0.4;
}

- (void)bulkDelete {
	NSArray<SCIFollowRequest *> *sel = [self selectedRequests];
	if (!sel.count) return;
	NSString *owner = [SCIUtils currentUserPK];
	NSString *msg = [NSString stringWithFormat:SCILocalized(@"Delete %lu record(s) from history?"), (unsigned long)sel.count];
	[SCIUtils showConfirmation:^{
		for (SCIFollowRequest *r in sel) [SCIFollowRequestStorage deleteRecordID:r.recordID ownerPK:owner];
		[self toggleSelectMode];
	} title:msg];
}

- (void)bulkPrimary {
	NSArray<SCIFollowRequest *> *sel = [self selectedRequests];
	if (!sel.count) return;
	NSString *owner = [SCIUtils currentUserPK];
	BOOL incoming = self.scope == SCIFollowRequestDirectionIncoming;
	NSString *title = incoming
		? [NSString stringWithFormat:SCILocalized(@"Follow back %lu account(s)?"), (unsigned long)sel.count]
		: [NSString stringWithFormat:SCILocalized(@"Cancel %lu pending request(s)?"), (unsigned long)sel.count];
	[SCIUtils showConfirmation:^{
		for (SCIFollowRequest *r in sel) {
			if (!r.userPK.length) continue;
			if (incoming) {
				[SCIInstagramAPI followUserPK:r.userPK completion:^(NSDictionary *resp, NSError *err) {
					if (!err) [[SCIFollowRequestTracker shared] recordManualFollowForPK:r.userPK username:r.username fullName:r.fullName picURL:r.profilePicURL picID:r.profilePicID];
				}];
			} else if (r.type == SCIFollowRequestTypeSent) {
				[SCIInstagramAPI unfollowUserPK:r.userPK completion:^(NSDictionary *resp, NSError *err) {
					if (!err) [SCIFollowRequestStorage resolveTargetPK:r.userPK fromType:SCIFollowRequestTypeSent toType:SCIFollowRequestTypeCancelled ownerPK:owner];
				}];
			}
		}
		[SCIUtils showToastForDuration:1.5 title:SCILocalized(@"Working…")];
		[self toggleSelectMode];
	} title:title];
}

- (UIMenu *)sortMenu {
	SCIFRSort cur = self.sortMode;
	UIAction *(^mk)(NSString *, SCIFRSort) = ^(NSString *title, SCIFRSort mode) {
		UIAction *a = [UIAction actionWithTitle:title image:nil identifier:nil handler:^(UIAction *x) {
			self.sortMode = mode; [self applyFilterAndSort]; [self updateRightBarButton];
		}];
		a.state = (cur == mode) ? UIMenuElementStateOn : UIMenuElementStateOff;
		return a;
	};
	return [UIMenu menuWithTitle:SCILocalized(@"Sort") children:@[
		mk(SCILocalized(@"Newest first"), SCIFRSortNewest),
		mk(SCILocalized(@"Oldest first"), SCIFRSortOldest),
		mk(SCILocalized(@"Name (A–Z)"), SCIFRSortNameAZ),
	]];
}

#pragma mark - Data

- (void)storeChanged { dispatch_async(dispatch_get_main_queue(), ^{ [self reload]; }); }

- (void)reload {
	NSString *owner = [SCIUtils currentUserPK];
	self.all = owner ? [SCIFollowRequestStorage allForOwnerPK:owner] : @[];
	[self applyFilterAndSort];
}

- (void)filterChanged { self.filter = (SCIFRFilter)self.filterControl.selectedSegmentIndex; [self applyFilterAndSort]; }

- (void)scopeChanged {
	self.scope = (SCIFollowRequestDirection)self.scopeControl.selectedSegmentIndex;
	self.filter = SCIFRFilterAll;
	[self rebuildFilterSegments];
	[self applyFilterAndSort];
	if (self.selectMode) [self updateBulkBar];
}

- (void)rebuildFilterSegments {
	NSArray *titles = self.scope == SCIFollowRequestDirectionIncoming
		? @[ SCILocalized(@"All"), SCILocalized(@"Received"), SCILocalized(@"Approved"), SCILocalized(@"Ignored"), SCILocalized(@"Withdrawn") ]
		: @[ SCILocalized(@"All"), SCILocalized(@"Sent"), SCILocalized(@"Accepted"), SCILocalized(@"Rejected"), SCILocalized(@"Cancelled") ];
	for (NSUInteger i = 0; i < titles.count; i++) [self.filterControl setTitle:titles[i] forSegmentAtIndex:i];
	self.filterControl.selectedSegmentIndex = 0;
}

// Selected status filter → concrete type for the current scope (or -1 for All).
- (NSInteger)selectedType {
	if (self.filter == SCIFRFilterAll) return -1;
	NSInteger base = self.scope == SCIFollowRequestDirectionIncoming ? SCIFollowRequestTypeReceived : SCIFollowRequestTypeSent;
	return base + (self.filter - 1);
}

- (void)applyFilterAndSort {
	NSString *q = self.searchController.searchBar.text;
	NSInteger wantType = [self selectedType];
	NSMutableArray *out = [NSMutableArray array];
	for (SCIFollowRequest *r in self.all) {
		if (r.direction != self.scope) continue;
		if (wantType >= 0 && (NSInteger)r.type != wantType) continue;
		if (q.length) {
			NSString *hay = [NSString stringWithFormat:@"%@ %@", r.username ?: @"", r.fullName ?: @""];
			if ([hay rangeOfString:q options:NSCaseInsensitiveSearch].location == NSNotFound) continue;
		}
		[out addObject:r];
	}
	[out sortUsingComparator:^NSComparisonResult(SCIFollowRequest *a, SCIFollowRequest *b) {
		if (self.sortMode == SCIFRSortNameAZ) {
			NSComparisonResult n = [a.displayName caseInsensitiveCompare:b.displayName];
			return n != NSOrderedSame ? n : (a.sortDate > b.sortDate ? NSOrderedAscending : NSOrderedDescending);
		}
		NSComparisonResult c = a.sortDate < b.sortDate ? NSOrderedAscending : (a.sortDate > b.sortDate ? NSOrderedDescending : NSOrderedSame);
		return self.sortMode == SCIFRSortOldest ? c : (NSComparisonResult)(-c);
	}];
	self.shown = out;
	self.emptyLabel.hidden = out.count > 0;
	[self.tableView reloadData];
}

#pragma mark - Refresh / clear

- (void)pullToRefresh:(UIRefreshControl *)rc {
	[[SCIFollowRequestTracker shared] checkNowWithCompletion:^{
		[rc endRefreshing];
		[self reload];
	}];
}

- (void)clearAll {
	if (!self.all.count) return;
	[SCIUtils showConfirmation:^{
		[SCIFollowRequestStorage resetForOwnerPK:[SCIUtils currentUserPK]];
	} title:SCILocalized(@"Clear all tracked follow requests?")];
}

#pragma mark - Table

- (NSInteger)tableView:(UITableView *)tv numberOfRowsInSection:(NSInteger)s { return self.shown.count; }

- (UITableViewCell *)tableView:(UITableView *)tv cellForRowAtIndexPath:(NSIndexPath *)ip {
	SCIFRCell *cell = [tv dequeueReusableCellWithIdentifier:@"cell" forIndexPath:ip];
	SCIFollowRequest *r = self.shown[ip.row];
	[cell configureWithRequest:r];
	cell.actionButton.hidden = tv.isEditing; // no per-row action while multi-selecting
	__weak typeof(self) ws = self;
	cell.onAction = ^(SCIFRCell *c) { [ws handleActionForRequest:r cell:c]; };
	return cell;
}

- (void)tableView:(UITableView *)tv didSelectRowAtIndexPath:(NSIndexPath *)ip {
	if (self.selectMode) { [self updateBulkBar]; return; }
	[tv deselectRowAtIndexPath:ip animated:YES];
	SCIFollowRequest *r = self.shown[ip.row];
	if (r.username.length) [SCIURLOpener dismiss:self thenOpenInstagramProfileForUsername:r.username];
}

- (void)tableView:(UITableView *)tv didDeselectRowAtIndexPath:(NSIndexPath *)ip {
	if (self.selectMode) [self updateBulkBar];
}

- (UISwipeActionsConfiguration *)tableView:(UITableView *)tv trailingSwipeActionsConfigurationForRowAtIndexPath:(NSIndexPath *)ip {
	SCIFollowRequest *r = self.shown[ip.row];
	UIContextualAction *del = [UIContextualAction contextualActionWithStyle:UIContextualActionStyleDestructive
																	  title:SCILocalized(@"Delete")
																	handler:^(UIContextualAction *a, UIView *v, void (^done)(BOOL)) {
		[SCIFollowRequestStorage deleteRecordID:r.recordID ownerPK:[SCIUtils currentUserPK]];
		done(YES);
	}];
	return [UISwipeActionsConfiguration configurationWithActions:@[del]];
}

#pragma mark - Per-row action

- (void)handleActionForRequest:(SCIFollowRequest *)r cell:(SCIFRCell *)cell {
	NSString *owner = [SCIUtils currentUserPK];
	if (!r.userPK.length || !owner.length) return;
	[cell setLoading:YES];

	if (r.type == SCIFollowRequestTypeSent) {              // cancel pending outgoing request
		[SCIInstagramAPI unfollowUserPK:r.userPK completion:^(NSDictionary *resp, NSError *err) {
			if (!err) [SCIFollowRequestStorage resolveTargetPK:r.userPK fromType:SCIFollowRequestTypeSent toType:SCIFollowRequestTypeCancelled ownerPK:owner];
			[cell setLoading:NO];
		}];
	} else if (r.type == SCIFollowRequestTypeAccepted) {   // unfollow (historical record stays)
		[SCIInstagramAPI unfollowUserPK:r.userPK completion:^(NSDictionary *resp, NSError *err) { [cell setLoading:NO]; }];
	} else {                                                // re-follow outgoing, or follow-back incoming
		[SCIInstagramAPI followUserPK:r.userPK completion:^(NSDictionary *resp, NSError *err) {
			[cell setLoading:NO];
			if (!err) [[SCIFollowRequestTracker shared] recordManualFollowForPK:r.userPK username:r.username
																	   fullName:r.fullName picURL:r.profilePicURL picID:r.profilePicID];
		}];
	}
}

#pragma mark - Search

- (void)updateSearchResultsForSearchController:(UISearchController *)sc { [self applyFilterAndSort]; }

@end
