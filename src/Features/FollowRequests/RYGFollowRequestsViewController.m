#import "RYGFollowRequestsViewController.h"
#import "RYGFollowRequestStorage.h"
#import "RYGFollowRequestModels.h"
#import "RYGFollowRequestTracker.h"
#import "../../Utils.h"
#import "../../RYGImageCache.h"
#import "../../RYGProfileOpener.h"
#import "../../ActionButton/RYGMediaViewer.h"
#import "../../UI/RYGIcon.h"
#import "../../Networking/RYGInstagramAPI.h"
#import "../../Settings/RYGSearchBarStyler.h"
#import "../../UI/RYGPopupChrome.h"
#import "../../Localization/RYGLocalization.h"

typedef NS_ENUM(NSInteger, RYGFRFilter) {
	RYGFRFilterAll = 0,
	RYGFRFilterSent,
	RYGFRFilterAccepted,
	RYGFRFilterRejected,
	RYGFRFilterCancelled,
};

typedef NS_ENUM(NSInteger, RYGFRSort) {
	RYGFRSortNewest = 0,
	RYGFRSortOldest,
	RYGFRSortNameAZ,
};

static NSString *frPicKey(RYGFollowRequest *r) {
	if (r.profilePicID.length) return [@"frpic:" stringByAppendingString:r.profilePicID];
	if (r.profilePicURL.length) return [@"frurl:" stringByAppendingString:r.profilePicURL];
	return [@"frpk:" stringByAppendingString:(r.userPK ?: @"?")];
}

#pragma mark - Cell

@interface RYGFRCell : UITableViewCell
@property (nonatomic, strong) UIImageView *avatar;
@property (nonatomic, strong) UILabel *nameLabel;
@property (nonatomic, strong) UILabel *subLabel;       // status + outcome time
@property (nonatomic, strong) UILabel *appearedLabel;  // when it was sent/received
@property (nonatomic, strong) UIImageView *typeIcon;
@property (nonatomic, strong) UIButton *actionButton;
@property (nonatomic, strong) UIActivityIndicatorView *spinner;
@property (nonatomic, copy) NSString *boundPK;
@property (nonatomic, copy) void (^onAction)(RYGFRCell *);
@end

@implementation RYGFRCell

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

- (void)configureWithRequest:(RYGFollowRequest *)r {
	self.boundPK = r.userPK;
	self.nameLabel.text = r.displayName;

	NSString *typeStr = [RYGFollowRequest stringForType:r.type];
	NSString *appeared = [RYGFRCell relativeDate:r.sentAt];
	NSString *origVerb = r.direction == RYGFollowRequestDirectionIncoming ? RYGLocalized(@"Received") : RYGLocalized(@"Sent");
	if (r.isPending) {
		self.subLabel.text = appeared.length ? [NSString stringWithFormat:@"%@ · %@", typeStr, appeared] : typeStr;
		self.appearedLabel.hidden = YES;
	} else {
		// Outcome + when it was detected, then when it originally appeared.
		NSString *outcome = [RYGFRCell relativeDate:r.resolvedAt];
		self.subLabel.text = outcome.length ? [NSString stringWithFormat:@"%@ · %@", typeStr, outcome] : typeStr;
		self.appearedLabel.text = appeared.length ? [NSString stringWithFormat:@"%@ %@", origVerb, appeared] : @"";
		self.appearedLabel.hidden = (appeared.length == 0);
	}
	self.subLabel.textColor = [RYGFollowRequest colorForType:r.type];

	UIImageSymbolConfiguration *cfg = [UIImageSymbolConfiguration configurationWithPointSize:13 weight:UIImageSymbolWeightSemibold];
	self.typeIcon.image = [UIImage systemImageNamed:[RYGFollowRequest symbolForType:r.type] withConfiguration:cfg];
	self.typeIcon.tintColor = [RYGFollowRequest colorForType:r.type];

	[self applyActionStyleForType:r.type];

	self.avatar.image = nil;
	NSString *key = frPicKey(r);
	NSURL *url = r.profilePicURL.length ? [NSURL URLWithString:r.profilePicURL] : nil;
	if (url) {
		NSString *bound = self.boundPK;
		[RYGImageCache loadImageFromURL:url cacheKey:key completion:^(UIImage *image) {
			if (image && [self.boundPK isEqualToString:bound]) self.avatar.image = image;
		}];
	}
	if (!self.avatar.image) {
		self.avatar.image = [UIImage systemImageNamed:@"person.crop.circle.fill"];
		self.avatar.tintColor = UIColor.tertiaryLabelColor;
	}
	[self setLoading:NO];
}

- (void)applyActionStyleForType:(RYGFollowRequestType)type {
	NSString *title; UIColor *bg; UIColor *fg;
	switch (type) {
		case RYGFollowRequestTypeSent:
			title = RYGLocalized(@"Requested"); bg = UIColor.tertiarySystemFillColor; fg = UIColor.labelColor; break;
		case RYGFollowRequestTypeAccepted:
			title = RYGLocalized(@"Following"); bg = UIColor.tertiarySystemFillColor; fg = UIColor.labelColor; break;
		case RYGFollowRequestTypeRejected:
		case RYGFollowRequestTypeCancelled:
		case RYGFollowRequestTypeWithdrawn: // they never followed you — plain follow
			title = RYGLocalized(@"Follow"); bg = UIColor.systemBlueColor; fg = UIColor.whiteColor; break;
		default: // incoming pending/approved/ignored — follow the requester back
			title = RYGLocalized(@"Follow back"); bg = UIColor.systemBlueColor; fg = UIColor.whiteColor; break;
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
	if (ago < 60) return RYGLocalized(@"just now");
	if (ago < 3600) return [NSString stringWithFormat:RYGLocalized(@"%ld minutes ago"), (long)(ago / 60)];
	if (ago < 86400) return [NSString stringWithFormat:RYGLocalized(@"%ld hours ago"), (long)(ago / 3600)];
	if (ago < 604800) return [NSString stringWithFormat:RYGLocalized(@"%ld days ago"), (long)(ago / 86400)];
	return [df stringFromDate:[NSDate dateWithTimeIntervalSince1970:ts]];
}

@end

#pragma mark - Controller

@interface RYGFollowRequestsViewController () <UITableViewDataSource, UITableViewDelegate, UISearchResultsUpdating, UISearchControllerDelegate>
@property (nonatomic, strong) UITableView *tableView;
@property (nonatomic, strong) UISegmentedControl *scopeControl;
@property (nonatomic, strong) UISegmentedControl *filterControl;
@property (nonatomic, strong) UISearchController *searchController;
@property (nonatomic, strong) UILabel *emptyLabel;
@property (nonatomic, strong) NSArray<RYGFollowRequest *> *all;
@property (nonatomic, strong) NSArray<RYGFollowRequest *> *shown;
@property (nonatomic, assign) RYGFollowRequestDirection scope;
@property (nonatomic, assign) RYGFRFilter filter;
@property (nonatomic, assign) RYGFRSort sortMode;
@property (nonatomic, assign) BOOL selectMode;
@property (nonatomic, strong) UIView *bottomBar;
@property (nonatomic, strong) UIButton *bulkActionBtn;
@property (nonatomic, strong) UIButton *bulkDeleteBtn;
@end

@implementation RYGFollowRequestsViewController {
	RYGFollowRequestDirection _initialScope;
}

- (instancetype)initWithScope:(RYGFollowRequestDirection)scope {
	if ((self = [super init])) _initialScope = scope;
	return self;
}

+ (void)presentAtScope:(RYGFollowRequestDirection)scope {
	dispatch_async(dispatch_get_main_queue(), ^{
		[RYGPopupChrome presentVC:[[RYGFollowRequestsViewController alloc] initWithScope:scope] from:nil];
	});
}

- (void)viewDidLoad {
	[super viewDidLoad];
	self.title = RYGLocalized(@"Follow Requests");
	self.view.backgroundColor = UIColor.systemBackgroundColor;
	self.sortMode = RYGFRSortNewest;

	self.scope = _initialScope;
	self.scopeControl = [[UISegmentedControl alloc] initWithItems:@[ RYGLocalized(@"Sent by me"), RYGLocalized(@"Received") ]];
	self.scopeControl.selectedSegmentIndex = (self.scope == RYGFollowRequestDirectionIncoming) ? 1 : 0;
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
	[self.tableView registerClass:[RYGFRCell class] forCellReuseIdentifier:@"cell"];
	[self.view addSubview:self.tableView];

	[self setupBottomBar];

	UIRefreshControl *rc = [UIRefreshControl new];
	[rc addTarget:self action:@selector(pullToRefresh:) forControlEvents:UIControlEventValueChanged];
	self.tableView.refreshControl = rc;

	self.emptyLabel = [UILabel new];
	self.emptyLabel.text = RYGLocalized(@"No follow requests tracked yet");
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
	self.searchController.searchBar.placeholder = RYGLocalized(@"Search by username or name");
	self.navigationItem.searchController = self.searchController;
	self.navigationItem.hidesSearchBarWhenScrolling = NO;
	self.definesPresentationContext = YES;

	[self updateRightBarButton];

	[NSNotificationCenter.defaultCenter addObserver:self selector:@selector(storeChanged)
											   name:RYGFollowRequestsDidChangeNotification object:nil];
	[self reload];
	[RYGFollowRequestStorage markAllSeenForOwnerPK:[RYGUtils currentUserPK]];
}

- (void)dealloc { [NSNotificationCenter.defaultCenter removeObserver:self]; }

- (void)viewWillAppear:(BOOL)animated {
	[super viewWillAppear:animated];
	[self rygStyleSearchBar];
	[self reload];
	[[RYGFollowRequestTracker shared] checkNowForced:NO completion:nil]; // event-driven, throttled
}
- (void)rygStyleSearchBar { [RYGSearchBarStyler styleSearchBar:self.searchController.searchBar]; }
- (void)willPresentSearchController:(UISearchController *)sc { [self rygStyleSearchBar]; }

- (void)updateRightBarButton {
	if (self.selectMode) {
		UIBarButtonItem *done = [[UIBarButtonItem alloc] initWithBarButtonSystemItem:UIBarButtonSystemItemDone target:self action:@selector(toggleSelectMode)];
		UIBarButtonItem *all = [[UIBarButtonItem alloc] initWithTitle:RYGLocalized(@"Select All") style:UIBarButtonItemStylePlain target:self action:@selector(toggleSelectAll)];
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
	self.bulkDeleteBtn = [self barButtonTitle:RYGLocalized(@"Delete") color:UIColor.systemRedColor action:@selector(bulkDelete)];
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

- (NSArray<RYGFollowRequest *> *)selectedRequests {
	NSMutableArray *out = [NSMutableArray array];
	for (NSIndexPath *ip in [self.tableView indexPathsForSelectedRows]) if (ip.row < (NSInteger)self.shown.count) [out addObject:self.shown[ip.row]];
	return out;
}

- (void)updateBulkBar {
	NSUInteger n = [self.tableView indexPathsForSelectedRows].count;
	NSString *del = n ? [NSString stringWithFormat:RYGLocalized(@"Delete (%lu)"), (unsigned long)n] : RYGLocalized(@"Delete");
	[self.bulkDeleteBtn setTitle:del forState:UIControlStateNormal];

	NSString *primary = self.scope == RYGFollowRequestDirectionIncoming ? RYGLocalized(@"Follow back") : RYGLocalized(@"Cancel requests");
	if (n) primary = [NSString stringWithFormat:@"%@ (%lu)", primary, (unsigned long)n];
	[self.bulkActionBtn setTitle:primary forState:UIControlStateNormal];

	self.bulkDeleteBtn.enabled = self.bulkActionBtn.enabled = n > 0;
	self.bulkDeleteBtn.alpha = self.bulkActionBtn.alpha = n > 0 ? 1.0 : 0.4;
}

- (void)bulkDelete {
	NSArray<RYGFollowRequest *> *sel = [self selectedRequests];
	if (!sel.count) return;
	NSString *owner = [RYGUtils currentUserPK];
	NSString *msg = [NSString stringWithFormat:RYGLocalized(@"Delete %lu record(s) from history?"), (unsigned long)sel.count];
	[RYGUtils showConfirmation:^{
		for (RYGFollowRequest *r in sel) [RYGFollowRequestStorage deleteRecordID:r.recordID ownerPK:owner];
		[self toggleSelectMode];
	} title:msg];
}

- (void)bulkPrimary {
	NSArray<RYGFollowRequest *> *sel = [self selectedRequests];
	if (!sel.count) return;
	NSString *owner = [RYGUtils currentUserPK];
	BOOL incoming = self.scope == RYGFollowRequestDirectionIncoming;
	NSString *title = incoming
		? [NSString stringWithFormat:RYGLocalized(@"Follow back %lu account(s)?"), (unsigned long)sel.count]
		: [NSString stringWithFormat:RYGLocalized(@"Cancel %lu pending request(s)?"), (unsigned long)sel.count];
	[RYGUtils showConfirmation:^{
		for (RYGFollowRequest *r in sel) {
			if (!r.userPK.length) continue;
			if (incoming) {
				[RYGInstagramAPI followUserPK:r.userPK completion:^(NSDictionary *resp, NSError *err) {
					if (!err) [[RYGFollowRequestTracker shared] recordManualFollowForPK:r.userPK username:r.username fullName:r.fullName picURL:r.profilePicURL picID:r.profilePicID];
				}];
			} else if (r.type == RYGFollowRequestTypeSent) {
				[RYGInstagramAPI unfollowUserPK:r.userPK completion:^(NSDictionary *resp, NSError *err) {
					if (!err) [RYGFollowRequestStorage resolveTargetPK:r.userPK fromType:RYGFollowRequestTypeSent toType:RYGFollowRequestTypeCancelled ownerPK:owner];
				}];
			}
		}
		[RYGUtils showToastForDuration:1.5 title:RYGLocalized(@"Working…")];
		[self toggleSelectMode];
	} title:title];
}

- (UIMenu *)sortMenu {
	RYGFRSort cur = self.sortMode;
	UIAction *(^mk)(NSString *, RYGFRSort) = ^(NSString *title, RYGFRSort mode) {
		UIAction *a = [UIAction actionWithTitle:title image:nil identifier:nil handler:^(UIAction *x) {
			self.sortMode = mode; [self applyFilterAndSort]; [self updateRightBarButton];
		}];
		a.state = (cur == mode) ? UIMenuElementStateOn : UIMenuElementStateOff;
		return a;
	};
	return [UIMenu menuWithTitle:RYGLocalized(@"Sort") children:@[
		mk(RYGLocalized(@"Newest first"), RYGFRSortNewest),
		mk(RYGLocalized(@"Oldest first"), RYGFRSortOldest),
		mk(RYGLocalized(@"Name (A–Z)"), RYGFRSortNameAZ),
	]];
}

#pragma mark - Data

- (void)storeChanged { dispatch_async(dispatch_get_main_queue(), ^{ [self reload]; }); }

- (void)reload {
	NSString *owner = [RYGUtils currentUserPK];
	self.all = owner ? [RYGFollowRequestStorage allForOwnerPK:owner] : @[];
	[self applyFilterAndSort];
}

- (void)filterChanged { self.filter = (RYGFRFilter)self.filterControl.selectedSegmentIndex; [self applyFilterAndSort]; }

- (void)scopeChanged {
	self.scope = (RYGFollowRequestDirection)self.scopeControl.selectedSegmentIndex;
	self.filter = RYGFRFilterAll;
	[self rebuildFilterSegments];
	[self applyFilterAndSort];
	if (self.selectMode) [self updateBulkBar];
}

- (void)rebuildFilterSegments {
	NSArray *titles = self.scope == RYGFollowRequestDirectionIncoming
		? @[ RYGLocalized(@"All"), RYGLocalized(@"Received"), RYGLocalized(@"Approved"), RYGLocalized(@"Ignored"), RYGLocalized(@"Withdrawn") ]
		: @[ RYGLocalized(@"All"), RYGLocalized(@"Sent"), RYGLocalized(@"Accepted"), RYGLocalized(@"Rejected"), RYGLocalized(@"Cancelled") ];
	for (NSUInteger i = 0; i < titles.count; i++) [self.filterControl setTitle:titles[i] forSegmentAtIndex:i];
	self.filterControl.selectedSegmentIndex = 0;
}

// Selected status filter → concrete type for the current scope (or -1 for All).
- (NSInteger)selectedType {
	if (self.filter == RYGFRFilterAll) return -1;
	NSInteger base = self.scope == RYGFollowRequestDirectionIncoming ? RYGFollowRequestTypeReceived : RYGFollowRequestTypeSent;
	return base + (self.filter - 1);
}

- (void)applyFilterAndSort {
	NSString *q = self.searchController.searchBar.text;
	NSInteger wantType = [self selectedType];
	NSMutableArray *out = [NSMutableArray array];
	for (RYGFollowRequest *r in self.all) {
		if (r.direction != self.scope) continue;
		if (wantType >= 0 && (NSInteger)r.type != wantType) continue;
		if (q.length) {
			NSString *hay = [NSString stringWithFormat:@"%@ %@", r.username ?: @"", r.fullName ?: @""];
			if ([hay rangeOfString:q options:NSCaseInsensitiveSearch].location == NSNotFound) continue;
		}
		[out addObject:r];
	}
	[out sortUsingComparator:^NSComparisonResult(RYGFollowRequest *a, RYGFollowRequest *b) {
		if (self.sortMode == RYGFRSortNameAZ) {
			NSComparisonResult n = [a.displayName caseInsensitiveCompare:b.displayName];
			return n != NSOrderedSame ? n : (a.sortDate > b.sortDate ? NSOrderedAscending : NSOrderedDescending);
		}
		NSComparisonResult c = a.sortDate < b.sortDate ? NSOrderedAscending : (a.sortDate > b.sortDate ? NSOrderedDescending : NSOrderedSame);
		return self.sortMode == RYGFRSortOldest ? c : (NSComparisonResult)(-c);
	}];
	self.shown = out;
	self.emptyLabel.hidden = out.count > 0;
	[self.tableView reloadData];
}

#pragma mark - Refresh / clear

- (void)pullToRefresh:(UIRefreshControl *)rc {
	[[RYGFollowRequestTracker shared] checkNowWithCompletion:^{
		[rc endRefreshing];
		[self reload];
	}];
}

- (void)clearAll {
	if (!self.all.count) return;
	[RYGUtils showConfirmation:^{
		[RYGFollowRequestStorage resetForOwnerPK:[RYGUtils currentUserPK]];
	} title:RYGLocalized(@"Clear all tracked follow requests?")];
}

#pragma mark - Table

- (NSInteger)tableView:(UITableView *)tv numberOfRowsInSection:(NSInteger)s { return self.shown.count; }

- (UITableViewCell *)tableView:(UITableView *)tv cellForRowAtIndexPath:(NSIndexPath *)ip {
	RYGFRCell *cell = [tv dequeueReusableCellWithIdentifier:@"cell" forIndexPath:ip];
	RYGFollowRequest *r = self.shown[ip.row];
	[cell configureWithRequest:r];
	cell.actionButton.hidden = tv.isEditing; // no per-row action while multi-selecting
	__weak typeof(self) ws = self;
	cell.onAction = ^(RYGFRCell *c) { [ws handleActionForRequest:r cell:c]; };
	return cell;
}

- (void)tableView:(UITableView *)tv didSelectRowAtIndexPath:(NSIndexPath *)ip {
	if (self.selectMode) { [self updateBulkBar]; return; }
	[tv deselectRowAtIndexPath:ip animated:YES];
	RYGFollowRequest *r = self.shown[ip.row];
	if (r.username.length || r.userPK.length) [RYGProfileOpener openProfileForPK:r.userPK username:r.username from:self];
}

- (void)tableView:(UITableView *)tv didDeselectRowAtIndexPath:(NSIndexPath *)ip {
	if (self.selectMode) [self updateBulkBar];
}

- (UISwipeActionsConfiguration *)tableView:(UITableView *)tv trailingSwipeActionsConfigurationForRowAtIndexPath:(NSIndexPath *)ip {
	RYGFollowRequest *r = self.shown[ip.row];
	UIContextualAction *del = [UIContextualAction contextualActionWithStyle:UIContextualActionStyleDestructive
																	  title:RYGLocalized(@"Delete")
																	handler:^(UIContextualAction *a, UIView *v, void (^done)(BOOL)) {
		[RYGFollowRequestStorage deleteRecordID:r.recordID ownerPK:[RYGUtils currentUserPK]];
		done(YES);
	}];
	return [UISwipeActionsConfiguration configurationWithActions:@[del]];
}

- (UIContextMenuConfiguration *)tableView:(UITableView *)tv
	contextMenuConfigurationForRowAtIndexPath:(NSIndexPath *)ip
										point:(CGPoint)point {
	if (self.selectMode || ip.row >= (NSInteger)self.shown.count) return nil;
	RYGFollowRequest *r = self.shown[ip.row];
	__weak typeof(self) ws = self;

	return [UIContextMenuConfiguration configurationWithIdentifier:nil previewProvider:nil
		actionProvider:^UIMenu *(NSArray<UIMenuElement *> *suggested) {
		NSMutableArray<UIMenuElement *> *items = [NSMutableArray array];

		if (r.userPK.length || r.username.length)
			[items addObject:[UIAction actionWithTitle:RYGLocalized(@"Open profile")
												 image:[RYGIcon menuImageNamed:@"ig_icon_user_outline_24" pointSize:18]
											identifier:nil
											   handler:^(UIAction *a) {
				[RYGProfileOpener openProfileForPK:r.userPK username:r.username from:ws];
			}]];

		NSURL *pic = r.profilePicURL.length ? [NSURL URLWithString:r.profilePicURL] : nil;
		if (pic)
			[items addObject:[UIAction actionWithTitle:RYGLocalized(@"View picture")
												 image:[UIImage systemImageNamed:@"person.crop.circle"]
											identifier:nil
											   handler:^(UIAction *a) {
				[RYGMediaViewer showItem:[RYGMediaViewerItem itemWithVideoURL:nil photoURL:pic
																	 caption:r.displayName]];
			}]];

		if (r.username.length) {
			[items addObject:[UIAction actionWithTitle:RYGLocalized(@"View all from this user")
												 image:[UIImage systemImageNamed:@"line.3.horizontal.decrease.circle"]
											identifier:nil
											   handler:^(UIAction *a) {
				[ws showAllFromUsername:r.username];
			}]];
			[items addObject:[UIAction actionWithTitle:RYGLocalized(@"Copy username")
												 image:[RYGIcon menuImageNamed:@"bcn_copy_outline_24" pointSize:18]
											identifier:nil
											   handler:^(UIAction *a) {
				UIPasteboard.generalPasteboard.string = r.username;
				RYGNotifySuccess(RYG_NOTIF_COPY_PROFILE, RYGLocalized(@"Copied"), r.username);
			}]];
		}

		UIAction *del = [UIAction actionWithTitle:RYGLocalized(@"Delete")
											image:[UIImage systemImageNamed:@"trash"]
									   identifier:nil
										  handler:^(UIAction *a) {
			[RYGFollowRequestStorage deleteRecordID:r.recordID ownerPK:[RYGUtils currentUserPK]];
		}];
		del.attributes = UIMenuElementAttributesDestructive;
		[items addObject:del];

		return [UIMenu menuWithTitle:r.displayName children:items];
	}];
}

// Search survives a scope change, so the other direction is one tap away.
- (void)showAllFromUsername:(NSString *)username {
	self.filter = RYGFRFilterAll;
	self.filterControl.selectedSegmentIndex = 0;
	self.searchController.searchBar.text = username;
	[self applyFilterAndSort];
}

#pragma mark - Per-row action

- (void)handleActionForRequest:(RYGFollowRequest *)r cell:(RYGFRCell *)cell {
	NSString *owner = [RYGUtils currentUserPK];
	if (!r.userPK.length || !owner.length) return;
	[cell setLoading:YES];

	if (r.type == RYGFollowRequestTypeSent) {              // cancel pending outgoing request
		[RYGInstagramAPI unfollowUserPK:r.userPK completion:^(NSDictionary *resp, NSError *err) {
			if (!err) [RYGFollowRequestStorage resolveTargetPK:r.userPK fromType:RYGFollowRequestTypeSent toType:RYGFollowRequestTypeCancelled ownerPK:owner];
			[cell setLoading:NO];
		}];
	} else if (r.type == RYGFollowRequestTypeAccepted) {   // unfollow (historical record stays)
		[RYGInstagramAPI unfollowUserPK:r.userPK completion:^(NSDictionary *resp, NSError *err) { [cell setLoading:NO]; }];
	} else {                                                // re-follow outgoing, or follow-back incoming
		[RYGInstagramAPI followUserPK:r.userPK completion:^(NSDictionary *resp, NSError *err) {
			[cell setLoading:NO];
			if (!err) [[RYGFollowRequestTracker shared] recordManualFollowForPK:r.userPK username:r.username
																	   fullName:r.fullName picURL:r.profilePicURL picID:r.profilePicID];
		}];
	}
}

#pragma mark - Search

- (void)updateSearchResultsForSearchController:(UISearchController *)sc { [self applyFilterAndSort]; }

@end
