#import "RYGProfileAnalyzerListViewController.h"
#import "RYGProfileAnalyzerStorage.h"
#import "../../Networking/RYGInstagramAPI.h"
#import "../../Utils.h"
#import "../../Background/RYGBackgroundActivity.h"
#import "../../RYGProfileOpener.h"
#import "../../RYGImageCache.h"
#import "../../Settings/RYGSearchBarStyler.h"
#import "../../Localization/RYGLocalization.h"

// IG throttles /friendships/ — 50/session + 1.5s cushion stays inside the limit.
static const NSInteger kRYGPABatchCap = 50;
static const NSTimeInterval kRYGPABatchDelay = 1.5;
static const NSTimeInterval kRYGPAFriendshipTTL = 10 * 60;
static const NSTimeInterval kRYGPAPicRefreshTTL = 5 * 60;

@interface RYGPAFriendshipCache : NSObject
+ (NSNumber *)followingForPK:(NSString *)pk;
+ (void)setFollowing:(BOOL)following forPK:(NSString *)pk;
+ (void)invalidatePK:(NSString *)pk;
@end

// Key avatars on the pic id (stable per photo across sizes/signatures), not the
// URL — IG's signed URLs expire and vary by size, so a URL key drops on revisit.
static NSString *rygPicCacheKey(RYGProfileAnalyzerUser *user, NSURL *url) {
	if (user.profilePicID.length) return [@"papic:" stringByAppendingString:user.profilePicID];
	if (user.pk.length) return [@"papk:" stringByAppendingString:user.pk];
	NSString *path = url.path;
	return path.length > 1 ? path : url.absoluteString;
}

static NSMutableDictionary<NSString *, NSDate *> *rygPicRefreshAttempted(void) {
	static NSMutableDictionary *m;
	static dispatch_once_t once;
	dispatch_once(&once, ^{ m = [NSMutableDictionary dictionary]; });
	return m;
}

@implementation RYGPAFriendshipCache
+ (NSMutableDictionary *)store {
	static NSMutableDictionary *m;
	static dispatch_once_t once;
	dispatch_once(&once, ^{ m = [NSMutableDictionary dictionary]; });
	return m;
}
+ (NSNumber *)followingForPK:(NSString *)pk {
	if (!pk.length) return nil;
	NSDictionary *e = [self store][pk];
	if (!e) return nil;
	if (-[e[@"ts"] timeIntervalSinceNow] > kRYGPAFriendshipTTL) {
		[[self store] removeObjectForKey:pk];
		return nil;
	}
	return e[@"following"];
}
+ (void)setFollowing:(BOOL)following forPK:(NSString *)pk {
	if (!pk.length) return;
	[self store][pk] = @{ @"following": @(following), @"ts": [NSDate date] };
}
+ (void)invalidatePK:(NSString *)pk {
	if (!pk.length) return;
	[[self store] removeObjectForKey:pk];
}
@end

typedef NS_ENUM(NSInteger, RYGPASortMode) {
	RYGPASortModeDefault,
	RYGPASortModeAZ,
	RYGPASortModeZA,
	RYGPASortModeRecent,
	RYGPASortModeOldest,
	RYGPASortModeMostVisited,
	RYGPASortModeNewFirst,
};

typedef NS_ENUM(NSInteger, RYGPADateFilter) {
	RYGPADateFilterAny,
	RYGPADateFilterToday,
	RYGPADateFilter7d,
	RYGPADateFilter30d,
};

typedef NS_ENUM(NSInteger, RYGPABatchOp) {
	RYGPABatchOpFollow,
	RYGPABatchOpUnfollow,
	RYGPABatchOpRemoveFollower,
};

#pragma mark - Cell

// Pill label with horizontal insets so the text stays centered.
@interface RYGPAPaddedLabel : UILabel
@end
@implementation RYGPAPaddedLabel
- (void)drawTextInRect:(CGRect)rect {
	[super drawTextInRect:UIEdgeInsetsInsetRect(rect, UIEdgeInsetsMake(0, 6, 0, 6))];
}
- (CGSize)intrinsicContentSize {
	CGSize s = [super intrinsicContentSize];
	s.width += 12;
	return s;
}
@end

@interface RYGPAUserCell : UITableViewCell
@property (nonatomic, strong) UIImageView *avatar;
@property (nonatomic, strong) UIStackView *titleStack;
@property (nonatomic, strong) UILabel *usernameLabel;
@property (nonatomic, strong) UIImageView *verifiedBadge;
@property (nonatomic, strong) RYGPAPaddedLabel *freshBadge;
@property (nonatomic, strong) UILabel *subtitleLabel;
@property (nonatomic, strong) UIButton *actionButton;
@property (nonatomic, strong) UIActivityIndicatorView *actionSpinner;
@property (nonatomic, strong) NSLayoutConstraint *usernameTrailingToButton;
@property (nonatomic, strong) NSLayoutConstraint *usernameTrailingToEdge;
@property (nonatomic, copy) NSString *boundPK;
@property (nonatomic, copy) void(^onActionTap)(RYGPAUserCell *);
@end

@implementation RYGPAUserCell
- (instancetype)initWithStyle:(UITableViewCellStyle)style reuseIdentifier:(NSString *)reuseIdentifier {
	self = [super initWithStyle:style reuseIdentifier:reuseIdentifier];
	if (!self) return self;
	self.selectionStyle = UITableViewCellSelectionStyleDefault;

	_avatar = [UIImageView new];
	_avatar.translatesAutoresizingMaskIntoConstraints = NO;
	_avatar.backgroundColor = [UIColor secondarySystemBackgroundColor];
	_avatar.layer.cornerRadius = 24;
	_avatar.layer.masksToBounds = YES;
	_avatar.contentMode = UIViewContentModeScaleAspectFill;
	[self.contentView addSubview:_avatar];

	_usernameLabel = [UILabel new];
	_usernameLabel.font = [UIFont systemFontOfSize:16 weight:UIFontWeightSemibold];
	_usernameLabel.textColor = [UIColor labelColor];
	[_usernameLabel setContentHuggingPriority:UILayoutPriorityDefaultHigh forAxis:UILayoutConstraintAxisHorizontal];
	[_usernameLabel setContentCompressionResistancePriority:UILayoutPriorityDefaultLow forAxis:UILayoutConstraintAxisHorizontal];

	_verifiedBadge = [[UIImageView alloc] initWithImage:[UIImage systemImageNamed:@"checkmark.seal.fill"]];
	_verifiedBadge.tintColor = [UIColor systemBlueColor];
	_verifiedBadge.contentMode = UIViewContentModeScaleAspectFit;
	_verifiedBadge.hidden = YES;
	[_verifiedBadge setContentHuggingPriority:UILayoutPriorityRequired forAxis:UILayoutConstraintAxisHorizontal];
	[_verifiedBadge.widthAnchor constraintEqualToConstant:14].active = YES;
	[_verifiedBadge.heightAnchor constraintEqualToConstant:14].active = YES;

	_freshBadge = [RYGPAPaddedLabel new];
	_freshBadge.font = [UIFont systemFontOfSize:10 weight:UIFontWeightHeavy];
	_freshBadge.textColor = [UIColor whiteColor];
	_freshBadge.backgroundColor = [RYGUtils RYGColor_Primary] ?: [UIColor systemBlueColor];
	_freshBadge.textAlignment = NSTextAlignmentCenter;
	_freshBadge.layer.cornerRadius = 8;
	_freshBadge.layer.masksToBounds = YES;
	_freshBadge.hidden = YES;
	[_freshBadge setContentHuggingPriority:UILayoutPriorityRequired forAxis:UILayoutConstraintAxisHorizontal];
	[_freshBadge.heightAnchor constraintEqualToConstant:16].active = YES;

	_titleStack = [[UIStackView alloc] initWithArrangedSubviews:@[_usernameLabel, _verifiedBadge, _freshBadge]];
	_titleStack.translatesAutoresizingMaskIntoConstraints = NO;
	_titleStack.axis = UILayoutConstraintAxisHorizontal;
	_titleStack.alignment = UIStackViewAlignmentCenter;
	_titleStack.spacing = 4;
	[self.contentView addSubview:_titleStack];

	_subtitleLabel = [UILabel new];
	_subtitleLabel.translatesAutoresizingMaskIntoConstraints = NO;
	_subtitleLabel.font = [UIFont systemFontOfSize:13];
	_subtitleLabel.textColor = [UIColor secondaryLabelColor];
	_subtitleLabel.numberOfLines = 2;
	[self.contentView addSubview:_subtitleLabel];

	_actionButton = [UIButton buttonWithType:UIButtonTypeSystem];
	_actionButton.translatesAutoresizingMaskIntoConstraints = NO;
	_actionButton.titleLabel.font = [UIFont systemFontOfSize:14 weight:UIFontWeightSemibold];
	_actionButton.layer.cornerRadius = 8;
	_actionButton.contentEdgeInsets = UIEdgeInsetsMake(6, 14, 6, 14);
	_actionButton.hidden = YES;
	[_actionButton addTarget:self action:@selector(onAction) forControlEvents:UIControlEventTouchUpInside];
	[_actionButton setContentCompressionResistancePriority:UILayoutPriorityRequired forAxis:UILayoutConstraintAxisHorizontal];
	[self.contentView addSubview:_actionButton];

	_actionSpinner = [[UIActivityIndicatorView alloc] initWithActivityIndicatorStyle:UIActivityIndicatorViewStyleMedium];
	_actionSpinner.translatesAutoresizingMaskIntoConstraints = NO;
	_actionSpinner.color = [UIColor secondaryLabelColor];
	_actionSpinner.hidesWhenStopped = YES;
	[self.contentView addSubview:_actionSpinner];

	_usernameTrailingToButton = [_titleStack.trailingAnchor constraintLessThanOrEqualToAnchor:_actionButton.leadingAnchor constant:-10];
	_usernameTrailingToEdge = [_titleStack.trailingAnchor constraintLessThanOrEqualToAnchor:self.contentView.layoutMarginsGuide.trailingAnchor];

	[NSLayoutConstraint activateConstraints:@[
		[_avatar.leadingAnchor constraintEqualToAnchor:self.contentView.layoutMarginsGuide.leadingAnchor],
		[_avatar.centerYAnchor constraintEqualToAnchor:self.contentView.centerYAnchor],
		[_avatar.widthAnchor constraintEqualToConstant:48],
		[_avatar.heightAnchor constraintEqualToConstant:48],

		[_titleStack.leadingAnchor constraintEqualToAnchor:_avatar.trailingAnchor constant:12],
		[_titleStack.topAnchor constraintEqualToAnchor:_avatar.topAnchor constant:2],

		[_subtitleLabel.leadingAnchor constraintEqualToAnchor:_titleStack.leadingAnchor],
		[_subtitleLabel.topAnchor constraintEqualToAnchor:_titleStack.bottomAnchor constant:2],
		[_subtitleLabel.trailingAnchor constraintLessThanOrEqualToAnchor:_actionButton.leadingAnchor constant:-10],
		[_subtitleLabel.bottomAnchor constraintLessThanOrEqualToAnchor:self.contentView.bottomAnchor constant:-8],

		[_actionButton.trailingAnchor constraintEqualToAnchor:self.contentView.layoutMarginsGuide.trailingAnchor],
		[_actionButton.centerYAnchor constraintEqualToAnchor:self.contentView.centerYAnchor],

		[_actionSpinner.centerXAnchor constraintEqualToAnchor:_actionButton.centerXAnchor],
		[_actionSpinner.centerYAnchor constraintEqualToAnchor:_actionButton.centerYAnchor],

		_usernameTrailingToButton,
	]];
	return self;
}

typedef NS_ENUM(NSInteger, RYGPACellAction) {
	RYGPACellActionLoading,
	RYGPACellActionFollow,
	RYGPACellActionUnfollow,
	RYGPACellActionPending,
};

- (void)resetButtonMenu {
	self.actionButton.menu = nil;
	self.actionButton.showsMenuAsPrimaryAction = NO;
	[self.actionButton setImage:nil forState:UIControlStateNormal];
	self.actionButton.semanticContentAttribute = UISemanticContentAttributeUnspecified;
	self.actionButton.imageEdgeInsets = UIEdgeInsetsZero;
}

// Follow-back list rows: tap opens a menu instead of a single follow action.
- (void)applyFollowMenu:(UIMenu *)menu pending:(BOOL)pending tint:(UIColor *)tint {
	self.usernameTrailingToButton.active = YES;
	self.usernameTrailingToEdge.active = NO;
	self.actionButton.hidden = NO;
	[self.actionSpinner stopAnimating];
	[self.actionButton setTitle:RYGLocalized(@"Follow") forState:UIControlStateNormal];
	self.actionButton.backgroundColor = tint ?: [UIColor systemBlueColor];
	[self.actionButton setTitleColor:[UIColor whiteColor] forState:UIControlStateNormal];
	self.actionButton.tintColor = [UIColor whiteColor];
	UIImageSymbolConfiguration *cfg = [UIImageSymbolConfiguration configurationWithPointSize:10 weight:UIImageSymbolWeightBold];
	[self.actionButton setImage:[UIImage systemImageNamed:@"chevron.down" withConfiguration:cfg] forState:UIControlStateNormal];
	self.actionButton.semanticContentAttribute = UISemanticContentAttributeForceRightToLeft;
	self.actionButton.imageEdgeInsets = UIEdgeInsetsMake(0, 6, 0, -2);
	self.actionButton.menu = menu;
	self.actionButton.showsMenuAsPrimaryAction = YES;
	self.actionButton.enabled = !pending;
	self.actionButton.alpha = pending ? 0.55 : 1.0;
}

- (void)applyAction:(RYGPACellAction)state pending:(BOOL)pending tint:(UIColor *)tint {
	self.usernameTrailingToButton.active = YES;
	self.usernameTrailingToEdge.active = NO;
	[self resetButtonMenu];
	UIColor *primary = tint ?: [UIColor systemBlueColor];

	switch (state) {
		case RYGPACellActionLoading:
			self.actionButton.hidden = YES;
			[self.actionSpinner startAnimating];
			break;
		case RYGPACellActionFollow:
			self.actionButton.hidden = NO;
			[self.actionSpinner stopAnimating];
			[self.actionButton setTitle:RYGLocalized(@"Follow") forState:UIControlStateNormal];
			self.actionButton.backgroundColor = primary;
			[self.actionButton setTitleColor:[UIColor whiteColor] forState:UIControlStateNormal];
			self.actionButton.enabled = !pending;
			self.actionButton.alpha = pending ? 0.55 : 1.0;
			break;
		case RYGPACellActionUnfollow:
			self.actionButton.hidden = NO;
			[self.actionSpinner stopAnimating];
			[self.actionButton setTitle:RYGLocalized(@"Unfollow") forState:UIControlStateNormal];
			self.actionButton.backgroundColor = [[UIColor systemRedColor] colorWithAlphaComponent:0.12];
			[self.actionButton setTitleColor:[UIColor systemRedColor] forState:UIControlStateNormal];
			self.actionButton.enabled = !pending;
			self.actionButton.alpha = pending ? 0.55 : 1.0;
			break;
		case RYGPACellActionPending:
			self.actionButton.hidden = NO;
			self.actionButton.enabled = NO;
			self.actionButton.alpha = 0.55;
			[self.actionSpinner startAnimating];
			break;
	}
}

- (void)hideAction {
	self.actionButton.hidden = YES;
	[self.actionSpinner stopAnimating];
	self.usernameTrailingToButton.active = NO;
	self.usernameTrailingToEdge.active = YES;
}

- (void)setShowsNew:(BOOL)shows {
	if (shows && !self.freshBadge.text.length) self.freshBadge.text = RYGLocalized(@"NEW");
	self.freshBadge.hidden = !shows;
}

- (void)onAction { if (self.onActionTap) self.onActionTap(self); }
- (void)prepareForReuse {
	[super prepareForReuse];
	self.avatar.image = nil;
	self.onActionTap = nil;
	self.verifiedBadge.hidden = YES;
	self.freshBadge.hidden = YES;
	self.boundPK = nil;
	[self.actionSpinner stopAnimating];
	self.actionButton.hidden = YES;
	[self resetButtonMenu];
}
@end

#pragma mark - VC

@interface RYGProfileAnalyzerListViewController () <UITableViewDataSource, UITableViewDelegate, UISearchResultsUpdating, UISearchControllerDelegate>
@property (nonatomic, copy) NSArray<RYGProfileAnalyzerUser *> *allUsers;
@property (nonatomic, copy) NSArray<RYGProfileAnalyzerUser *> *filteredUsers;
@property (nonatomic, copy) NSArray<RYGProfileAnalyzerProfileChange *> *allChanges;
@property (nonatomic, copy) NSArray<RYGProfileAnalyzerProfileChange *> *filteredChanges;
@property (nonatomic, assign) RYGPAListKind kind;
@property (nonatomic, strong) UITableView *tableView;
@property (nonatomic, strong) UISearchController *searchController;
@property (nonatomic, strong) UILabel *emptyLabel;
@property (nonatomic, strong) NSMutableSet<NSString *> *pendingPKs;

@property (nonatomic, assign) BOOL selectionMode;
@property (nonatomic, strong) NSMutableSet<NSString *> *selectedPKs;
@property (nonatomic, strong) UIView *batchBar;
@property (nonatomic, strong) UIButton *batchActionButton;

@property (nonatomic, assign) RYGPASortMode sortMode;
@property (nonatomic, assign) BOOL filterVerifiedOnly;
@property (nonatomic, assign) BOOL filterNotVerifiedOnly;
@property (nonatomic, assign) BOOL filterPrivateOnly;
@property (nonatomic, assign) BOOL filterNewOnly;
@property (nonatomic, assign) RYGPADateFilter dateFilter;
@property (nonatomic, copy) NSString *currentQuery;

@property (nonatomic, copy) NSArray<RYGProfileAnalyzerVisit *> *allVisits;
@property (nonatomic, copy) NSArray<RYGProfileAnalyzerVisit *> *filteredVisits;

// nil = unknown, @YES = following, @NO = not. Only written on successful
// show_many or confirmed action; errors leave entries nil so cells stay loading.
@property (nonatomic, strong) NSMutableDictionary<NSString *, NSNumber *> *friendshipStatus;
@property (nonatomic, strong) NSMutableSet<NSString *> *lookupQueue;
@property (nonatomic, strong) NSMutableSet<NSString *> *lookupInflight;
@property (nonatomic, strong) NSMutableDictionary<NSString *, NSDate *> *lookupBackoff;
@property (nonatomic, assign) BOOL lookupFlushScheduled;
@end

@implementation RYGProfileAnalyzerListViewController

- (instancetype)initWithTitle:(NSString *)title
						users:(NSArray<RYGProfileAnalyzerUser *> *)users
						 kind:(RYGPAListKind)kind {
	self = [super init];
	if (!self) return self;
	self.title = title;
	self.kind = kind;
	self.allUsers = users ?: @[];
	self.filteredUsers = self.allUsers;
	self.pendingPKs = [NSMutableSet set];
	self.selectedPKs = [NSMutableSet set];
	self.friendshipStatus = [NSMutableDictionary dictionary];
	self.lookupQueue = [NSMutableSet set];
	self.lookupInflight = [NSMutableSet set];
	self.lookupBackoff = [NSMutableDictionary dictionary];
	return self;
}

- (instancetype)initVisitedListWithTitle:(NSString *)title
								   visits:(NSArray<RYGProfileAnalyzerVisit *> *)visits {
	self = [super init];
	if (!self) return self;
	self.title = title;
	self.kind = RYGPAListKindVisited;
	self.allVisits = visits ?: @[];
	self.filteredVisits = self.allVisits;
	self.sortMode = RYGPASortModeRecent;
	self.pendingPKs = [NSMutableSet set];
	self.selectedPKs = [NSMutableSet set];
	self.friendshipStatus = [NSMutableDictionary dictionary];
	self.lookupQueue = [NSMutableSet set];
	self.lookupInflight = [NSMutableSet set];
	self.lookupBackoff = [NSMutableDictionary dictionary];
	return self;
}

- (instancetype)initWithTitle:(NSString *)title
			  profileUpdates:(NSArray<RYGProfileAnalyzerProfileChange *> *)updates {
	self = [super init];
	if (!self) return self;
	self.title = title;
	self.kind = RYGPAListKindProfileUpdate;
	self.allChanges = updates ?: @[];
	self.filteredChanges = self.allChanges;
	self.pendingPKs = [NSMutableSet set];
	self.selectedPKs = [NSMutableSet set];
	self.friendshipStatus = [NSMutableDictionary dictionary];
	self.lookupQueue = [NSMutableSet set];
	self.lookupInflight = [NSMutableSet set];
	self.lookupBackoff = [NSMutableDictionary dictionary];
	return self;
}

- (void)viewDidLoad {
	[super viewDidLoad];
	self.view.backgroundColor = [UIColor systemBackgroundColor];
	[self setupTable];
	[self setupSearch];
	[self setupEmptyState];
	[self setupBatchBar];
	[self seedFriendshipStatusFromKind];
	[self applyFiltersAndSort];
}

// Snapshot-derived kinds imply a friendship direction; seed them so we skip
// the show_many roundtrip. Other kinds fall back to the cross-VC cache.
- (void)seedFriendshipStatusFromKind {
	NSNumber *seed;
	if (self.kind == RYGPAListKindUnfollow || self.kind == RYGPAListKindMutual) seed = @YES;
	else if (self.kind == RYGPAListKindFollow) seed = @NO;

	NSArray *src;
	if (self.kind == RYGPAListKindVisited) {
		NSMutableArray *us = [NSMutableArray arrayWithCapacity:self.allVisits.count];
		for (RYGProfileAnalyzerVisit *v in self.allVisits) [us addObject:v.user];
		src = us;
	} else if (self.kind == RYGPAListKindProfileUpdate) {
		NSMutableArray *us = [NSMutableArray arrayWithCapacity:self.allChanges.count];
		for (RYGProfileAnalyzerProfileChange *c in self.allChanges) [us addObject:c.current];
		src = us;
	} else {
		src = self.allUsers;
	}
	for (RYGProfileAnalyzerUser *u in src) {
		if (!u.pk.length) continue;
		if (seed) {
			self.friendshipStatus[u.pk] = seed;
			[RYGPAFriendshipCache setFollowing:seed.boolValue forPK:u.pk];
			continue;
		}
		NSNumber *cached = [RYGPAFriendshipCache followingForPK:u.pk];
		if (cached) self.friendshipStatus[u.pk] = cached;
	}
}

- (void)setupTable {
	self.tableView = [[UITableView alloc] initWithFrame:self.view.bounds style:UITableViewStylePlain];
	self.tableView.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
	self.tableView.dataSource = self;
	self.tableView.delegate = self;
	// Visited rows show two subtitle lines (fullName + timestamp); 72pt clips.
	self.tableView.rowHeight = (self.kind == RYGPAListKindVisited) ? 84 : 72;
	self.tableView.separatorInset = UIEdgeInsetsMake(0, 78, 0, 0);
	self.tableView.allowsMultipleSelection = NO;
	[self.tableView registerClass:[RYGPAUserCell class] forCellReuseIdentifier:@"cell"];
	[self.view addSubview:self.tableView];

	// Pull-to-refresh: visited list only — others are snapshot-bound.
	if (self.kind == RYGPAListKindVisited) {
		UIRefreshControl *rc = [UIRefreshControl new];
		[rc addTarget:self action:@selector(pullToRefresh:) forControlEvents:UIControlEventValueChanged];
		self.tableView.refreshControl = rc;
	}
}

- (void)setupSearch {
	self.searchController = [[UISearchController alloc] initWithSearchResultsController:nil];
	self.searchController.searchResultsUpdater = self;
	self.searchController.delegate = self;
	self.searchController.obscuresBackgroundDuringPresentation = NO;
	self.searchController.searchBar.placeholder = RYGLocalized(@"Search by username or name");
	self.navigationItem.searchController = self.searchController;
	self.navigationItem.hidesSearchBarWhenScrolling = NO;
	self.definesPresentationContext = YES;
}

- (void)viewWillAppear:(BOOL)animated {
	[super viewWillAppear:animated];
	[self rygStyleSearchBar];
}

- (void)rygStyleSearchBar {
	[RYGSearchBarStyler styleSearchBar:self.searchController.searchBar];
}

- (void)willPresentSearchController:(UISearchController *)searchController { [self rygStyleSearchBar]; }
- (void)didPresentSearchController:(UISearchController *)searchController {
	[self rygStyleSearchBar];
	dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.05 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
		[self rygStyleSearchBar];
	});
}

- (void)setupEmptyState {
	self.emptyLabel = [UILabel new];
	self.emptyLabel.text = RYGLocalized(@"No results");
	self.emptyLabel.textColor = [UIColor tertiaryLabelColor];
	self.emptyLabel.font = [UIFont systemFontOfSize:15];
	self.emptyLabel.textAlignment = NSTextAlignmentCenter;
	self.emptyLabel.hidden = YES;
	self.emptyLabel.translatesAutoresizingMaskIntoConstraints = NO;
	[self.view addSubview:self.emptyLabel];
	[NSLayoutConstraint activateConstraints:@[
		[self.emptyLabel.centerXAnchor constraintEqualToAnchor:self.view.centerXAnchor],
		[self.emptyLabel.centerYAnchor constraintEqualToAnchor:self.view.centerYAnchor constant:-40],
	]];
}

- (void)setupBatchBar {
	self.batchActionButton = [UIButton buttonWithType:UIButtonTypeSystem];
	self.batchActionButton.translatesAutoresizingMaskIntoConstraints = NO;
	self.batchActionButton.titleLabel.font = [UIFont systemFontOfSize:16 weight:UIFontWeightSemibold];
	[self.batchActionButton setTitleColor:[UIColor whiteColor] forState:UIControlStateNormal];
	self.batchActionButton.backgroundColor = [UIColor systemRedColor];
	self.batchActionButton.layer.cornerRadius = 26;
	self.batchActionButton.contentEdgeInsets = UIEdgeInsetsMake(0, 28, 0, 28);
	self.batchActionButton.layer.shadowColor = UIColor.blackColor.CGColor;
	self.batchActionButton.layer.shadowOffset = CGSizeMake(0, 6);
	self.batchActionButton.layer.shadowOpacity = 0.22;
	self.batchActionButton.layer.shadowRadius = 12;
	[self.batchActionButton addTarget:self action:@selector(batchActionTapped) forControlEvents:UIControlEventTouchUpInside];
	self.batchActionButton.hidden = YES;
	[self.view addSubview:self.batchActionButton];

	self.batchBar = self.batchActionButton;

	[NSLayoutConstraint activateConstraints:@[
		[self.batchActionButton.centerXAnchor constraintEqualToAnchor:self.view.centerXAnchor],
		[self.batchActionButton.bottomAnchor constraintEqualToAnchor:self.view.safeAreaLayoutGuide.bottomAnchor constant:-16],
		[self.batchActionButton.heightAnchor constraintEqualToConstant:52],
		[self.batchActionButton.widthAnchor constraintGreaterThanOrEqualToConstant:220],
		[self.batchActionButton.widthAnchor constraintLessThanOrEqualToAnchor:self.view.widthAnchor constant:-40],
	]];
}

- (BOOL)supportsBatchAction {
	return self.kind == RYGPAListKindUnfollow
		|| self.kind == RYGPAListKindFollow
		|| self.kind == RYGPAListKindRefollow
		|| self.kind == RYGPAListKindMutual;
}


- (void)updateNavBar {
	NSMutableArray *rights = [NSMutableArray array];
	if (self.supportsBatchAction) {
		NSString *t = self.selectionMode ? RYGLocalized(@"Done") : RYGLocalized(@"Select");
		UIBarButtonItem *sel = [[UIBarButtonItem alloc] initWithTitle:t
																style:UIBarButtonItemStylePlain
															   target:self action:@selector(toggleSelectionMode)];
		[rights addObject:sel];
	}
	NSString *symbol = [self hasActiveFilterOrSort]
		? @"line.3.horizontal.decrease.circle.fill"
		: @"line.3.horizontal.decrease.circle";
	UIBarButtonItem *filter = [[UIBarButtonItem alloc] initWithImage:[UIImage systemImageNamed:symbol]
																menu:[self buildFilterMenu]];
	[rights addObject:filter];
	self.navigationItem.rightBarButtonItems = rights;
}

- (UIMenu *)buildFilterMenu {
	__weak typeof(self) weakSelf = self;

	NSMutableArray *sortChildren = [NSMutableArray array];
	if (self.unseenEntryIDs.count) {
		UIAction *newFirst = [UIAction actionWithTitle:RYGLocalized(@"New first")
												 image:[UIImage systemImageNamed:@"sparkles"]
											identifier:nil
											   handler:^(__kindof UIAction *_) {
			weakSelf.sortMode = (weakSelf.sortMode == RYGPASortModeNewFirst) ? RYGPASortModeDefault : RYGPASortModeNewFirst;
			[weakSelf applyFiltersAndSort];
		}];
		newFirst.state = (self.sortMode == RYGPASortModeNewFirst) ? UIMenuElementStateOn : UIMenuElementStateOff;
		[sortChildren addObject:newFirst];
	}
	if (self.kind == RYGPAListKindVisited) {
		UIAction *recent = [UIAction actionWithTitle:RYGLocalized(@"Most recent")
											   image:[UIImage systemImageNamed:@"clock.arrow.circlepath"]
										  identifier:nil
											 handler:^(__kindof UIAction *_) {
			weakSelf.sortMode = RYGPASortModeRecent; [weakSelf applyFiltersAndSort];
		}];
		recent.state = (self.sortMode == RYGPASortModeRecent) ? UIMenuElementStateOn : UIMenuElementStateOff;

		UIAction *oldest = [UIAction actionWithTitle:RYGLocalized(@"Oldest first")
											   image:[UIImage systemImageNamed:@"clock"]
										  identifier:nil
											 handler:^(__kindof UIAction *_) {
			weakSelf.sortMode = RYGPASortModeOldest; [weakSelf applyFiltersAndSort];
		}];
		oldest.state = (self.sortMode == RYGPASortModeOldest) ? UIMenuElementStateOn : UIMenuElementStateOff;

		UIAction *mostVisited = [UIAction actionWithTitle:RYGLocalized(@"Most visited")
													image:[UIImage systemImageNamed:@"flame.fill"]
											   identifier:nil
												  handler:^(__kindof UIAction *_) {
			weakSelf.sortMode = RYGPASortModeMostVisited; [weakSelf applyFiltersAndSort];
		}];
		mostVisited.state = (self.sortMode == RYGPASortModeMostVisited) ? UIMenuElementStateOn : UIMenuElementStateOff;
		[sortChildren addObjectsFromArray:@[recent, oldest, mostVisited]];
	}

	UIAction *az = [UIAction actionWithTitle:RYGLocalized(@"Username A → Z")
										image:[UIImage systemImageNamed:@"arrow.up"]
								   identifier:nil
									  handler:^(__kindof UIAction *_) {
		weakSelf.sortMode = weakSelf.sortMode == RYGPASortModeAZ ? RYGPASortModeDefault : RYGPASortModeAZ;
		[weakSelf applyFiltersAndSort];
	}];
	az.state = (self.sortMode == RYGPASortModeAZ) ? UIMenuElementStateOn : UIMenuElementStateOff;

	UIAction *za = [UIAction actionWithTitle:RYGLocalized(@"Username Z → A")
										image:[UIImage systemImageNamed:@"arrow.down"]
								   identifier:nil
									  handler:^(__kindof UIAction *_) {
		weakSelf.sortMode = weakSelf.sortMode == RYGPASortModeZA ? RYGPASortModeDefault : RYGPASortModeZA;
		[weakSelf applyFiltersAndSort];
	}];
	za.state = (self.sortMode == RYGPASortModeZA) ? UIMenuElementStateOn : UIMenuElementStateOff;
	[sortChildren addObjectsFromArray:@[az, za]];

	UIMenu *sortGroup = [UIMenu menuWithTitle:RYGLocalized(@"Sort")
										image:nil identifier:nil
									  options:UIMenuOptionsDisplayInline
									 children:sortChildren];

	UIAction *verified = [UIAction actionWithTitle:RYGLocalized(@"Verified only")
											  image:[UIImage systemImageNamed:@"checkmark.seal.fill"]
										 identifier:nil
											handler:^(__kindof UIAction *_) {
		weakSelf.filterVerifiedOnly = !weakSelf.filterVerifiedOnly;
		if (weakSelf.filterVerifiedOnly) weakSelf.filterNotVerifiedOnly = NO;
		[weakSelf applyFiltersAndSort];
	}];
	verified.state = self.filterVerifiedOnly ? UIMenuElementStateOn : UIMenuElementStateOff;

	UIAction *notVerified = [UIAction actionWithTitle:RYGLocalized(@"Not verified only")
												 image:[UIImage systemImageNamed:@"seal"]
											identifier:nil
											   handler:^(__kindof UIAction *_) {
		weakSelf.filterNotVerifiedOnly = !weakSelf.filterNotVerifiedOnly;
		if (weakSelf.filterNotVerifiedOnly) weakSelf.filterVerifiedOnly = NO;
		[weakSelf applyFiltersAndSort];
	}];
	notVerified.state = self.filterNotVerifiedOnly ? UIMenuElementStateOn : UIMenuElementStateOff;

	UIAction *priv = [UIAction actionWithTitle:RYGLocalized(@"Private only")
										  image:[UIImage systemImageNamed:@"lock.fill"]
									 identifier:nil
										handler:^(__kindof UIAction *_) {
		weakSelf.filterPrivateOnly = !weakSelf.filterPrivateOnly;
		[weakSelf applyFiltersAndSort];
	}];
	priv.state = self.filterPrivateOnly ? UIMenuElementStateOn : UIMenuElementStateOff;

	NSMutableArray *filterChildren = [NSMutableArray arrayWithObjects:verified, notVerified, priv, nil];
	if (self.unseenEntryIDs.count) {
		UIAction *newOnly = [UIAction actionWithTitle:RYGLocalized(@"New only")
												image:[UIImage systemImageNamed:@"sparkles"]
										   identifier:nil
											  handler:^(__kindof UIAction *_) {
			weakSelf.filterNewOnly = !weakSelf.filterNewOnly;
			[weakSelf applyFiltersAndSort];
		}];
		newOnly.state = self.filterNewOnly ? UIMenuElementStateOn : UIMenuElementStateOff;
		[filterChildren addObject:newOnly];
	}
	UIMenu *filterGroup = [UIMenu menuWithTitle:RYGLocalized(@"Filter")
										  image:nil identifier:nil
										options:UIMenuOptionsDisplayInline
									   children:filterChildren];

	NSMutableArray *children = [NSMutableArray arrayWithObjects:sortGroup, filterGroup, nil];

	if (self.kind == RYGPAListKindVisited) {
		UIAction *(^df)(NSString *, NSString *, RYGPADateFilter) =
		^UIAction *(NSString *title, NSString *symbol, RYGPADateFilter mode) {
			UIAction *a = [UIAction actionWithTitle:title
											  image:[UIImage systemImageNamed:symbol]
										 identifier:nil
											handler:^(__kindof UIAction *_) {
				weakSelf.dateFilter = (weakSelf.dateFilter == mode) ? RYGPADateFilterAny : mode;
				[weakSelf applyFiltersAndSort];
			}];
			a.state = (self.dateFilter == mode) ? UIMenuElementStateOn : UIMenuElementStateOff;
			return a;
		};
		UIMenu *dateGroup = [UIMenu menuWithTitle:RYGLocalized(@"Visited")
											image:nil identifier:nil
										  options:UIMenuOptionsDisplayInline
										 children:@[
			df(RYGLocalized(@"Today"),		 @"sun.max",		 RYGPADateFilterToday),
			df(RYGLocalized(@"Last 7 days"),   @"calendar.badge.clock", RYGPADateFilter7d),
			df(RYGLocalized(@"Last 30 days"),  @"calendar",		RYGPADateFilter30d),
		]];
		[children insertObject:dateGroup atIndex:1];
	}

	if ([self hasActiveFilterOrSort]) {
		UIAction *clear = [UIAction actionWithTitle:RYGLocalized(@"Clear")
											  image:[UIImage systemImageNamed:@"arrow.counterclockwise"]
										 identifier:nil
											handler:^(__kindof UIAction *_) {
			weakSelf.sortMode = [weakSelf neutralSortMode];
			weakSelf.filterVerifiedOnly = NO;
			weakSelf.filterNotVerifiedOnly = NO;
			weakSelf.filterPrivateOnly = NO;
			weakSelf.filterNewOnly = NO;
			weakSelf.dateFilter = RYGPADateFilterAny;
			[weakSelf applyFiltersAndSort];
		}];
		clear.attributes = UIMenuElementAttributesDestructive;
		[children addObject:[UIMenu menuWithTitle:@"" image:nil identifier:nil
										   options:UIMenuOptionsDisplayInline children:@[clear]]];
	}
	return [UIMenu menuWithChildren:children];
}

- (void)refreshCounts {
	NSUInteger total, shown;
	if (self.kind == RYGPAListKindProfileUpdate) {
		total = self.allChanges.count; shown = self.filteredChanges.count;
	} else if (self.kind == RYGPAListKindVisited) {
		total = self.allVisits.count;  shown = self.filteredVisits.count;
	} else {
		total = self.allUsers.count;   shown = self.filteredUsers.count;
	}
	self.navigationItem.prompt = [NSString stringWithFormat:RYGLocalized(@"%lu of %lu"),
								  (unsigned long)shown, (unsigned long)total];
	self.emptyLabel.hidden = shown > 0;
}

#pragma mark - Search

- (void)updateSearchResultsForSearchController:(UISearchController *)searchController {
	self.currentQuery = [searchController.searchBar.text stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceCharacterSet]];
	[self applyFiltersAndSort];
}

- (void)setUnseenEntryIDs:(NSSet<NSString *> *)unseenEntryIDs {
	_unseenEntryIDs = [unseenEntryIDs copy];
	// Land on New-first so unseen entries open at the top.
	if (_unseenEntryIDs.count) self.sortMode = [self neutralSortMode];
}

- (RYGPASortMode)neutralSortMode {
	if (self.kind == RYGPAListKindVisited) return RYGPASortModeRecent;
	if (self.unseenEntryIDs.count) return RYGPASortModeNewFirst;
	return RYGPASortModeDefault;
}

// Mirrors -identityIDsForCategory: in the analyzer VC so newness lines up 1:1.
- (NSString *)identityForUser:(RYGProfileAnalyzerUser *)u change:(RYGProfileAnalyzerProfileChange *)c {
	if (self.kind == RYGPAListKindProfileUpdate) {
		RYGProfileAnalyzerUser *cur = c.current;
		return [NSString stringWithFormat:@"%@|%@|%@|%@",
				cur.pk ?: @"", cur.username ?: @"", cur.fullName ?: @"", cur.profilePicID ?: @""];
	}
	return u.pk ?: @"";
}

- (BOOL)isNewUser:(RYGProfileAnalyzerUser *)u change:(RYGProfileAnalyzerProfileChange *)c {
	if (!self.unseenEntryIDs.count) return NO;
	return [self.unseenEntryIDs containsObject:[self identityForUser:u change:c]];
}

- (void)applyFiltersAndSort {
	NSString *q = self.currentQuery;
	BOOL hasQuery = q.length > 0;
	BOOL verified = self.filterVerifiedOnly;
	BOOL notVerified = self.filterNotVerifiedOnly;
	BOOL priv = self.filterPrivateOnly;
	BOOL newOnly = self.filterNewOnly;

	NSArray *(^applyToUsers)(NSArray *) = ^NSArray *(NSArray *src) {
		NSMutableArray *out = [NSMutableArray arrayWithCapacity:src.count];
		for (RYGProfileAnalyzerUser *u in src) {
			if (hasQuery && ![u.username localizedCaseInsensitiveContainsString:q]
						 && ![u.fullName localizedCaseInsensitiveContainsString:q]) continue;
			if (verified && !u.isVerified) continue;
			if (notVerified && u.isVerified) continue;
			if (priv && !u.isPrivate) continue;
			if (newOnly && ![self isNewUser:u change:nil]) continue;
			[out addObject:u];
		}
		return [self sortUsers:out];
	};

	if (self.kind == RYGPAListKindProfileUpdate) {
		NSMutableArray *out = [NSMutableArray arrayWithCapacity:self.allChanges.count];
		for (RYGProfileAnalyzerProfileChange *c in self.allChanges) {
			RYGProfileAnalyzerUser *u = c.current;
			if (hasQuery && ![u.username localizedCaseInsensitiveContainsString:q]
						 && ![u.fullName localizedCaseInsensitiveContainsString:q]) continue;
			if (verified && !u.isVerified) continue;
			if (notVerified && u.isVerified) continue;
			if (priv && !u.isPrivate) continue;
			if (newOnly && ![self isNewUser:u change:c]) continue;
			[out addObject:c];
		}
		self.filteredChanges = [self sortChanges:out];
	} else if (self.kind == RYGPAListKindVisited) {
		NSDate *cutoff = [self dateCutoffForCurrentFilter];
		NSMutableArray *out = [NSMutableArray arrayWithCapacity:self.allVisits.count];
		for (RYGProfileAnalyzerVisit *vst in self.allVisits) {
			RYGProfileAnalyzerUser *u = vst.user;
			if (hasQuery && ![u.username localizedCaseInsensitiveContainsString:q]
						 && ![u.fullName localizedCaseInsensitiveContainsString:q]) continue;
			if (verified && !u.isVerified) continue;
			if (notVerified && u.isVerified) continue;
			if (priv && !u.isPrivate) continue;
			if (newOnly && ![self isNewUser:u change:nil]) continue;
			if (cutoff && [vst.lastSeen compare:cutoff] == NSOrderedAscending) continue;
			[out addObject:vst];
		}
		self.filteredVisits = [self sortVisits:out];
	} else {
		self.filteredUsers = applyToUsers(self.allUsers);
	}
	[self refreshCounts];
	[self updateNavBar];  // refresh filter-icon "active" state
	[self.tableView reloadData];
}

- (NSArray *)sortUsers:(NSArray<RYGProfileAnalyzerUser *> *)src {
	if (self.sortMode == RYGPASortModeDefault) return src;
	if (self.sortMode == RYGPASortModeNewFirst) {
		NSMutableArray *fresh = [NSMutableArray array], *rest = [NSMutableArray array];
		for (RYGProfileAnalyzerUser *u in src) [([self isNewUser:u change:nil] ? fresh : rest) addObject:u];
		[fresh addObjectsFromArray:rest];
		return fresh;
	}
	BOOL asc = (self.sortMode == RYGPASortModeAZ);
	return [src sortedArrayUsingComparator:^NSComparisonResult(RYGProfileAnalyzerUser *a, RYGProfileAnalyzerUser *b) {
		NSComparisonResult r = [a.username caseInsensitiveCompare:b.username ?: @""];
		return asc ? r : -r;
	}];
}

- (NSDate *)dateCutoffForCurrentFilter {
	NSTimeInterval secs = 0;
	switch (self.dateFilter) {
		case RYGPADateFilterToday: secs = 86400;		break;
		case RYGPADateFilter7d:	secs = 7  * 86400;   break;
		case RYGPADateFilter30d:   secs = 30 * 86400;   break;
		default: return nil;
	}
	return [NSDate dateWithTimeIntervalSinceNow:-secs];
}

- (NSArray *)sortVisits:(NSArray<RYGProfileAnalyzerVisit *> *)src {
	RYGPASortMode m = self.sortMode;
	if (m == RYGPASortModeNewFirst) {
		NSMutableArray *fresh = [NSMutableArray array], *rest = [NSMutableArray array];
		for (RYGProfileAnalyzerVisit *v in src) [([self isNewUser:v.user change:nil] ? fresh : rest) addObject:v];
		[fresh addObjectsFromArray:rest];
		return fresh;
	}
	if (m == RYGPASortModeRecent || m == RYGPASortModeDefault) {
		return [src sortedArrayUsingComparator:^NSComparisonResult(RYGProfileAnalyzerVisit *a, RYGProfileAnalyzerVisit *b) {
			return [b.lastSeen compare:a.lastSeen];
		}];
	}
	if (m == RYGPASortModeOldest) {
		return [src sortedArrayUsingComparator:^NSComparisonResult(RYGProfileAnalyzerVisit *a, RYGProfileAnalyzerVisit *b) {
			return [a.lastSeen compare:b.lastSeen];
		}];
	}
	if (m == RYGPASortModeMostVisited) {
		return [src sortedArrayUsingComparator:^NSComparisonResult(RYGProfileAnalyzerVisit *a, RYGProfileAnalyzerVisit *b) {
			if (a.visitCount == b.visitCount) return [b.lastSeen compare:a.lastSeen];
			return (a.visitCount < b.visitCount) ? NSOrderedDescending : NSOrderedAscending;
		}];
	}
	BOOL asc = (m == RYGPASortModeAZ);
	return [src sortedArrayUsingComparator:^NSComparisonResult(RYGProfileAnalyzerVisit *a, RYGProfileAnalyzerVisit *b) {
		NSComparisonResult r = [a.user.username caseInsensitiveCompare:b.user.username ?: @""];
		return asc ? r : -r;
	}];
}

- (NSArray *)sortChanges:(NSArray<RYGProfileAnalyzerProfileChange *> *)src {
	if (self.sortMode == RYGPASortModeDefault) return src;
	if (self.sortMode == RYGPASortModeNewFirst) {
		NSMutableArray *fresh = [NSMutableArray array], *rest = [NSMutableArray array];
		for (RYGProfileAnalyzerProfileChange *c in src) [([self isNewUser:c.current change:c] ? fresh : rest) addObject:c];
		[fresh addObjectsFromArray:rest];
		return fresh;
	}
	BOOL asc = (self.sortMode == RYGPASortModeAZ);
	return [src sortedArrayUsingComparator:^NSComparisonResult(RYGProfileAnalyzerProfileChange *a, RYGProfileAnalyzerProfileChange *b) {
		NSComparisonResult r = [a.current.username caseInsensitiveCompare:b.current.username ?: @""];
		return asc ? r : -r;
	}];
}

- (BOOL)hasActiveFilterOrSort {
	return self.filterVerifiedOnly || self.filterNotVerifiedOnly || self.filterPrivateOnly
		|| self.filterNewOnly
		|| self.dateFilter != RYGPADateFilterAny
		|| self.sortMode != [self neutralSortMode];
}

#pragma mark - Table

- (NSInteger)tableView:(UITableView *)tv numberOfRowsInSection:(NSInteger)section {
	if (self.kind == RYGPAListKindProfileUpdate) return self.filteredChanges.count;
	if (self.kind == RYGPAListKindVisited)	   return self.filteredVisits.count;
	return self.filteredUsers.count;
}

- (UITableViewCell *)tableView:(UITableView *)tv cellForRowAtIndexPath:(NSIndexPath *)indexPath {
	RYGPAUserCell *cell = [tv dequeueReusableCellWithIdentifier:@"cell" forIndexPath:indexPath];
	RYGProfileAnalyzerUser *user;
	RYGProfileAnalyzerProfileChange *change = nil;
	RYGProfileAnalyzerVisit *visit = nil;
	if (self.kind == RYGPAListKindProfileUpdate) {
		change = self.filteredChanges[indexPath.row];
		user = change.current;
	} else if (self.kind == RYGPAListKindVisited) {
		visit = self.filteredVisits[indexPath.row];
		user = visit.user;
	} else {
		user = self.filteredUsers[indexPath.row];
	}

	cell.usernameLabel.text = user.username.length ? [NSString stringWithFormat:@"@%@", user.username] : RYGLocalized(@"(unknown)");
	cell.verifiedBadge.hidden = !user.isVerified;
	[cell setShowsNew:[self isNewUser:user change:change]];

	if (self.kind == RYGPAListKindProfileUpdate) {
		NSMutableArray *lines = [NSMutableArray array];
		if (change.usernameChanged) {
			[lines addObject:[NSString stringWithFormat:RYGLocalized(@"Username: @%@ → @%@"),
							  change.previous.username ?: @"", change.current.username ?: @""]];
		}
		if (change.fullNameChanged) {
			[lines addObject:[NSString stringWithFormat:RYGLocalized(@"Name: %@ → %@"),
							  change.previous.fullName.length ? change.previous.fullName : @"—",
							  change.current.fullName.length ? change.current.fullName : @"—"]];
		}
		if (change.profilePicChanged) [lines addObject:RYGLocalized(@"Profile picture changed")];
		cell.subtitleLabel.text = [lines componentsJoinedByString:@"\n"];
		cell.subtitleLabel.numberOfLines = 3;
	} else if (self.kind == RYGPAListKindVisited) {
		NSString *when = [self relativeStringForDate:visit.lastSeen];
		NSString *dateLine = (visit.visitCount > 1)
			? [NSString stringWithFormat:RYGLocalized(@"%@ · %ld"), when, (long)visit.visitCount]
			: when;
		NSString *first = user.fullName.length ? user.fullName : (user.isPrivate ? RYGLocalized(@"Private account") : @"");
		if (first.length) {
			cell.subtitleLabel.text = [NSString stringWithFormat:@"%@\n%@", first, dateLine];
			cell.subtitleLabel.numberOfLines = 2;
		} else {
			cell.subtitleLabel.text = dateLine;
			cell.subtitleLabel.numberOfLines = 1;
		}
	} else {
		cell.subtitleLabel.text = user.fullName.length ? user.fullName : (user.isPrivate ? RYGLocalized(@"Private account") : @"");
		cell.subtitleLabel.numberOfLines = 1;
	}

	[self configureActionForCell:cell user:user];

	if (self.selectionMode) {
		BOOL on = [self.selectedPKs containsObject:user.pk];
		cell.accessoryType = on ? UITableViewCellAccessoryCheckmark : UITableViewCellAccessoryNone;
	} else {
		cell.accessoryType = UITableViewCellAccessoryNone;
	}

	// Skip avatar reset when reconfiguring the same row — avoids a grey flash.
	BOOL pkChanged = ![cell.boundPK isEqualToString:user.pk];
	if (pkChanged) {
		cell.boundPK = user.pk;
		cell.avatar.image = [UIImage systemImageNamed:@"person.circle.fill"];
		cell.avatar.tintColor = [UIColor systemGrayColor];
	}
	if (user.profilePicURL.length) {
		NSURL *url = [NSURL URLWithString:user.profilePicURL];
		NSString *boundPK = user.pk;
		__weak typeof(self) weakSelf = self;
		__weak RYGPAUserCell *weakCell = cell;
		[RYGImageCache loadImageFromURL:url cacheKey:rygPicCacheKey(user, url) completion:^(UIImage *image) {
			RYGPAUserCell *strongCell = weakCell;
			if (image) {
				if ([strongCell.boundPK isEqualToString:boundPK]) strongCell.avatar.image = image;
				return;
			}
			// CDN URL expired — fetch a fresh one.
			[weakSelf refreshProfilePicForUser:user];
		}];
	} else {
		// Visit captured before fieldCache populated — fetch identity now.
		[self refreshProfilePicForUser:user];
	}
	return cell;
}

- (void)refreshProfilePicForUser:(RYGProfileAnalyzerUser *)user {
	if (!user.pk.length) return;
	NSMutableDictionary *seen = rygPicRefreshAttempted();
	@synchronized (seen) {
		NSDate *last = seen[user.pk];
		if (last && -[last timeIntervalSinceNow] < kRYGPAPicRefreshTTL) return;
		seen[user.pk] = [NSDate date];
	}
	__weak typeof(self) weakSelf = self;
	[RYGInstagramAPI sendRequestWithMethod:@"GET"
									  path:[NSString stringWithFormat:@"users/%@/info/", user.pk]
									  body:nil
								completion:^(NSDictionary *resp, NSError *error) {
		NSDictionary *info = [resp[@"user"] isKindOfClass:[NSDictionary class]] ? resp[@"user"] : nil;
		if (!info.count) return;

		NSString *fresh = [info[@"profile_pic_url"] isKindOfClass:[NSString class]] ? info[@"profile_pic_url"] : nil;
		if (!fresh.length) {
			// Some private / restricted accounts only expose the HD url.
			NSDictionary *hd = info[@"hd_profile_pic_url_info"];
			if ([hd isKindOfClass:[NSDictionary class]]) {
				id u = hd[@"url"];
				if ([u isKindOfClass:[NSString class]]) fresh = u;
			}
		}

		BOOL changed = NO;
		if (fresh.length && ![user.profilePicURL isEqualToString:fresh]) {
			user.profilePicURL = fresh; changed = YES;
		}
		NSString *un = [info[@"username"] isKindOfClass:[NSString class]] ? info[@"username"] : nil;
		if (un.length && ![user.username isEqualToString:un]) { user.username = un; changed = YES; }
		NSString *fn = [info[@"full_name"] isKindOfClass:[NSString class]] ? info[@"full_name"] : nil;
		if (fn && ![(user.fullName ?: @"") isEqualToString:fn]) { user.fullName = fn; changed = YES; }
		BOOL ver = [info[@"is_verified"] boolValue];
		BOOL pri = [info[@"is_private"] boolValue];
		if (user.isVerified != ver) { user.isVerified = ver; changed = YES; }
		if (user.isPrivate  != pri) { user.isPrivate  = pri; changed = YES; }

		if (!changed) return;

		if (weakSelf.kind == RYGPAListKindVisited) {
			[RYGProfileAnalyzerStorage refreshVisitedUser:user forUserPK:[RYGUtils currentUserPK]];
		}
		[weakSelf reloadVisibleRowsForPKs:@[user.pk]];
	}];
}

- (NSString *)relativeStringForDate:(NSDate *)date {
	if (!date) return @"—";
	NSTimeInterval delta = -[date timeIntervalSinceNow];
	if (delta < 60)	return RYGLocalized(@"just now");
	if (delta < 3600)  return [NSString stringWithFormat:RYGLocalized(@"%dm ago"), MAX(1, (int)(delta / 60))];
	if (delta < 86400) return [NSString stringWithFormat:RYGLocalized(@"%dh ago"), (int)(delta / 3600)];
	if (delta < 7 * 86400) return [NSString stringWithFormat:RYGLocalized(@"%dd ago"), (int)(delta / 86400)];
	NSDateFormatter *f = [NSDateFormatter new];
	f.dateStyle = NSDateFormatterMediumStyle;
	f.timeStyle = NSDateFormatterNoStyle;
	return [f stringFromDate:date];
}

- (void)configureActionForCell:(RYGPAUserCell *)cell user:(RYGProfileAnalyzerUser *)user {
	if (self.selectionMode) {
		[cell hideAction];
		return;
	}
	BOOL pending = [self.pendingPKs containsObject:user.pk];
	NSNumber *status = self.friendshipStatus[user.pk];
	UIColor *primary = [RYGUtils RYGColor_Primary] ?: [UIColor systemBlueColor];

	if (pending) {
		[cell applyAction:RYGPACellActionPending pending:YES tint:primary];
	} else if (!status) {
		[cell applyAction:RYGPACellActionLoading pending:NO tint:primary];
	} else if ([status boolValue]) {
		[cell applyAction:RYGPACellActionUnfollow pending:NO tint:primary];
	} else if (self.kind == RYGPAListKindFollow) {
		// They follow you, you don't follow back — offer follow-back or remove-follower.
		[cell applyFollowMenu:[self followRowMenuForUser:user] pending:NO tint:primary];
		cell.onActionTap = nil;
		return;
	} else {
		[cell applyAction:RYGPACellActionFollow pending:NO tint:primary];
	}
	__weak typeof(self) weakSelf = self;
	cell.onActionTap = ^(RYGPAUserCell *c) { [weakSelf performActionForUser:user]; };
}

- (UIMenu *)followRowMenuForUser:(RYGProfileAnalyzerUser *)user {
	__weak typeof(self) weakSelf = self;
	UIAction *follow = [UIAction actionWithTitle:RYGLocalized(@"Follow back")
										   image:[UIImage systemImageNamed:@"person.badge.plus"]
									  identifier:nil
										 handler:^(__kindof UIAction *_) {
		[weakSelf sendFriendshipForUser:user follow:YES reload:YES];
	}];
	UIAction *remove = [UIAction actionWithTitle:RYGLocalized(@"Remove follower")
										   image:[UIImage systemImageNamed:@"person.fill.xmark"]
									  identifier:nil
										 handler:^(__kindof UIAction *_) {
		[weakSelf confirmRemoveFollowerForUser:user];
	}];
	remove.attributes = UIMenuElementAttributesDestructive;
	return [UIMenu menuWithChildren:@[follow, remove]];
}

- (void)confirmRemoveFollowerForUser:(RYGProfileAnalyzerUser *)user {
	if ([self.pendingPKs containsObject:user.pk]) return;
	NSString *msg = [NSString stringWithFormat:RYGLocalized(@"Remove @%@ as a follower?"), user.username ?: @""];
	UIAlertController *a = [UIAlertController alertControllerWithTitle:nil message:msg preferredStyle:UIAlertControllerStyleAlert];
	[a addAction:[UIAlertAction actionWithTitle:RYGLocalized(@"Cancel") style:UIAlertActionStyleCancel handler:nil]];
	__weak typeof(self) weakSelf = self;
	[a addAction:[UIAlertAction actionWithTitle:RYGLocalized(@"Remove") style:UIAlertActionStyleDestructive handler:^(UIAlertAction *_) {
		[weakSelf removeFollowerForUser:user];
	}]];
	[self presentViewController:a animated:YES completion:nil];
}

- (void)removeFollowerForUser:(RYGProfileAnalyzerUser *)user {
	if ([self.pendingPKs containsObject:user.pk]) return;
	[self.pendingPKs addObject:user.pk];
	[self reloadVisibleRowsForPKs:@[user.pk]];
	__weak typeof(self) weakSelf = self;
	[RYGInstagramAPI removeFollowerPK:user.pk completion:^(NSDictionary *resp, NSError *err) {
		typeof(self) strongSelf = weakSelf;
		if (!strongSelf) return;
		[strongSelf.pendingPKs removeObject:user.pk];
		BOOL ok = (err == nil) && ([resp[@"status"] isEqualToString:@"ok"] || resp[@"friendship_status"]);
		if (ok) {
			[strongSelf persistFollowerRemovalForUser:user];
			[strongSelf removeUserFromList:user];
		} else {
			[RYGUtils showErrorHUDWithDescription:err.localizedDescription ?: RYGLocalized(@"Request failed")];
			[strongSelf reloadVisibleRowsForPKs:@[user.pk]];
		}
	}];
}

// Mirror a follower removal into the snapshot so category counts update live.
- (void)persistFollowerRemovalForUser:(RYGProfileAnalyzerUser *)user {
	NSString *pk = [RYGUtils currentUserPK];
	RYGProfileAnalyzerSnapshot *snap = [RYGProfileAnalyzerStorage currentSnapshotForUserPK:pk];
	if (!snap) return;
	NSMutableArray *followers = [snap.followers mutableCopy] ?: [NSMutableArray array];
	if (![followers containsObject:user]) return;
	[followers removeObject:user];
	snap.followers = followers;
	snap.followerCount = MAX(0, snap.followerCount - 1);
	[RYGProfileAnalyzerStorage updateCurrentSnapshot:snap forUserPK:pk];
}

#pragma mark - Single-row action

- (void)performActionForUser:(RYGProfileAnalyzerUser *)user {
	if ([self.pendingPKs containsObject:user.pk]) return;
	NSNumber *status = self.friendshipStatus[user.pk];
	if (!status) return;
	BOOL currentlyFollowing = [status boolValue];
	if (currentlyFollowing) {
		NSString *msg = [NSString stringWithFormat:RYGLocalized(@"Unfollow @%@?"), user.username ?: @""];
		UIAlertController *a = [UIAlertController alertControllerWithTitle:nil message:msg preferredStyle:UIAlertControllerStyleAlert];
		[a addAction:[UIAlertAction actionWithTitle:RYGLocalized(@"Cancel") style:UIAlertActionStyleCancel handler:nil]];
		__weak typeof(self) weakSelf = self;
		[a addAction:[UIAlertAction actionWithTitle:RYGLocalized(@"Unfollow") style:UIAlertActionStyleDestructive handler:^(UIAlertAction *_) {
			[weakSelf sendFriendshipForUser:user follow:NO reload:YES];
		}]];
		[self presentViewController:a animated:YES completion:nil];
	} else {
		[self sendFriendshipForUser:user follow:YES reload:YES];
	}
}

- (void)sendFriendshipForUser:(RYGProfileAnalyzerUser *)user follow:(BOOL)follow reload:(BOOL)reload {
	[self.pendingPKs addObject:user.pk];
	if (reload) [self reloadVisibleRowsForPKs:@[user.pk]];
	__weak typeof(self) weakSelf = self;
	void(^done)(NSDictionary *, NSError *) = ^(NSDictionary *resp, NSError *err) {
		typeof(self) strongSelf = weakSelf;
		if (!strongSelf) return;
		[strongSelf.pendingPKs removeObject:user.pk];
		BOOL success = (err == nil) && ([resp[@"status"] isEqualToString:@"ok"] || resp[@"friendship_status"]);
		if (success) {
			strongSelf.friendshipStatus[user.pk] = @(follow);
			[RYGPAFriendshipCache setFollowing:follow forPK:user.pk];
			[strongSelf persistFriendshipChangeForUser:user followed:follow];
			BOOL membershipChanged =
				((strongSelf.kind == RYGPAListKindUnfollow || strongSelf.kind == RYGPAListKindMutual) && !follow)
			 || (strongSelf.kind == RYGPAListKindFollow && follow);
			if (membershipChanged) {
				[strongSelf removeUserFromList:user];
			} else {
				[strongSelf reloadVisibleRowsForPKs:@[user.pk]];
			}
		} else {
			[RYGUtils showErrorHUDWithDescription:err.localizedDescription ?: RYGLocalized(@"Request failed")];
			[strongSelf reloadVisibleRowsForPKs:@[user.pk]];
		}
	};
	if (follow) [RYGInstagramAPI followUserPK:user.pk completion:done];
	else		[RYGInstagramAPI unfollowUserPK:user.pk completion:done];
}

// Mirror in-app follow/unfollow into the snapshot so category counts update live.
- (void)persistFriendshipChangeForUser:(RYGProfileAnalyzerUser *)user followed:(BOOL)followed {
	NSString *pk = [RYGUtils currentUserPK];
	RYGProfileAnalyzerSnapshot *snap = [RYGProfileAnalyzerStorage currentSnapshotForUserPK:pk];
	if (!snap) return;
	NSMutableArray *following = [snap.following mutableCopy] ?: [NSMutableArray array];
	BOOL alreadyIn = [following containsObject:user];
	if (followed && !alreadyIn) {
		[following addObject:user];
		snap.followingCount = MAX(0, snap.followingCount + 1);
	} else if (!followed && alreadyIn) {
		[following removeObject:user];
		snap.followingCount = MAX(0, snap.followingCount - 1);
	} else {
		return;
	}
	snap.following = following;
	[RYGProfileAnalyzerStorage updateCurrentSnapshot:snap forUserPK:pk];
}

- (void)removeUserFromList:(RYGProfileAnalyzerUser *)user {
	if (self.kind == RYGPAListKindVisited || self.kind == RYGPAListKindProfileUpdate) {
		[self reloadVisibleRowsForPKs:@[user.pk]];   // history kinds keep the row
		return;
	}
	NSMutableArray *all = [self.allUsers mutableCopy];
	[all removeObject:user];
	self.allUsers = all;
	NSMutableArray *filt = [self.filteredUsers mutableCopy];
	[filt removeObject:user];
	self.filteredUsers = filt;
	[self.selectedPKs removeObject:user.pk];
	[self refreshCounts];
	[self.tableView reloadData];
}

#pragma mark - Tap row

- (void)tableView:(UITableView *)tv didSelectRowAtIndexPath:(NSIndexPath *)indexPath {
	[tv deselectRowAtIndexPath:indexPath animated:YES];
	RYGProfileAnalyzerUser *user;
	if (self.kind == RYGPAListKindProfileUpdate) {
		user = self.filteredChanges[indexPath.row].current;
	} else if (self.kind == RYGPAListKindVisited) {
		user = self.filteredVisits[indexPath.row].user;
	} else {
		user = self.filteredUsers[indexPath.row];
	}

	if (self.selectionMode) {
		if ([self.selectedPKs containsObject:user.pk]) [self.selectedPKs removeObject:user.pk];
		else [self.selectedPKs addObject:user.pk];
		[self refreshBatchBar];
		[tv reloadRowsAtIndexPaths:@[indexPath] withRowAnimation:UITableViewRowAnimationNone];
		return;
	}

	if (!user.username.length && !user.pk.length) return;
	[RYGProfileOpener openProfileForPK:user.pk username:user.username from:self];
}

#pragma mark - Pull-to-refresh

- (void)pullToRefresh:(UIRefreshControl *)sender {
	// Re-read disk, drop cached friendship/pic dedup, then force a fresh
	// /users/{pk}/info/ for every visible row so identity + pic resync.
	self.allVisits = [RYGProfileAnalyzerStorage visitedProfilesForUserPK:[RYGUtils currentUserPK]] ?: @[];

	@synchronized (rygPicRefreshAttempted()) {
		for (RYGProfileAnalyzerVisit *v in self.allVisits) {
			NSString *pk = v.user.pk;
			if (!pk.length) continue;
			[rygPicRefreshAttempted() removeObjectForKey:pk];
			[self.friendshipStatus removeObjectForKey:pk];
			[self.lookupBackoff removeObjectForKey:pk];
			[RYGPAFriendshipCache invalidatePK:pk];
		}
	}

	[self applyFiltersAndSort];

	NSMutableSet<RYGProfileAnalyzerUser *> *visibleUsers = [NSMutableSet set];
	for (NSIndexPath *ip in self.tableView.indexPathsForVisibleRows) {
		if (ip.row >= (NSInteger)self.filteredVisits.count) continue;
		RYGProfileAnalyzerUser *u = self.filteredVisits[ip.row].user;
		if (u.pk.length) [visibleUsers addObject:u];
	}
	for (RYGProfileAnalyzerUser *u in visibleUsers) [self refreshProfilePicForUser:u];

	[self.tableView reloadData];

	dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.5 * NSEC_PER_SEC)),
				   dispatch_get_main_queue(), ^{
		[sender endRefreshing];
	});
}

#pragma mark - Lazy friendship lookup

- (NSString *)pkAtIndexPath:(NSIndexPath *)indexPath {
	if (self.kind == RYGPAListKindProfileUpdate) {
		if (indexPath.row >= (NSInteger)self.filteredChanges.count) return nil;
		return self.filteredChanges[indexPath.row].current.pk;
	}
	if (self.kind == RYGPAListKindVisited) {
		if (indexPath.row >= (NSInteger)self.filteredVisits.count) return nil;
		return self.filteredVisits[indexPath.row].user.pk;
	}
	if (indexPath.row >= (NSInteger)self.filteredUsers.count) return nil;
	return self.filteredUsers[indexPath.row].pk;
}

- (void)tableView:(UITableView *)tv willDisplayCell:(UITableViewCell *)cell forRowAtIndexPath:(NSIndexPath *)indexPath {
	NSString *pk = [self pkAtIndexPath:indexPath];
	if (!pk.length) return;
	if (self.friendshipStatus[pk]) return;
	if ([self.lookupInflight containsObject:pk]) return;
	NSDate *backoff = self.lookupBackoff[pk];
	if (backoff && -[backoff timeIntervalSinceNow] < 60.0) return;
	[self.lookupQueue addObject:pk];
	[self scheduleLookupFlush];
}

- (void)scheduleLookupFlush {
	if (self.lookupFlushScheduled) return;
	self.lookupFlushScheduled = YES;
	__weak typeof(self) weakSelf = self;
	dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.18 * NSEC_PER_SEC)),
				   dispatch_get_main_queue(), ^{
		weakSelf.lookupFlushScheduled = NO;
		[weakSelf flushPendingLookups];
	});
}

- (void)flushPendingLookups {
	if (!self.lookupQueue.count) return;
	NSArray *all = [self.lookupQueue allObjects];
	[self.lookupQueue removeAllObjects];
	NSInteger chunkSize = 80;   // show_many caps around ~100 ids
	for (NSInteger i = 0; i < (NSInteger)all.count; i += chunkSize) {
		NSArray *chunk = [all subarrayWithRange:NSMakeRange(i, MIN(chunkSize, (NSInteger)all.count - i))];
		for (NSString *pk in chunk) [self.lookupInflight addObject:pk];
		__weak typeof(self) weakSelf = self;
		[RYGInstagramAPI fetchFriendshipStatusesForPKs:chunk
											 completion:^(NSDictionary *statuses, NSError *error) {
			typeof(self) strongSelf = weakSelf;
			if (!strongSelf) return;
			for (NSString *pk in chunk) [strongSelf.lookupInflight removeObject:pk];
			if (error || !statuses.count) {
				// Back off so willDisplay doesn't re-queue the same pks each scroll.
				NSDate *now = [NSDate date];
				for (NSString *pk in chunk) strongSelf.lookupBackoff[pk] = now;
			} else {
				for (NSString *pk in chunk) {
					NSDictionary *st = statuses[pk];
					BOOL following = [st isKindOfClass:[NSDictionary class]] ? [st[@"following"] boolValue] : NO;
					strongSelf.friendshipStatus[pk] = @(following);
					[RYGPAFriendshipCache setFollowing:following forPK:pk];
				}
			}
			[strongSelf reloadVisibleRowsForPKs:chunk];
		}];
	}
}

- (void)reloadVisibleRowsForPKs:(NSArray<NSString *> *)pks {
	NSSet *set = [NSSet setWithArray:pks];
	NSMutableArray *paths = [NSMutableArray array];
	for (NSIndexPath *ip in self.tableView.indexPathsForVisibleRows) {
		NSString *pk = [self pkAtIndexPath:ip];
		if (pk && [set containsObject:pk]) [paths addObject:ip];
	}
	if (paths.count) [self.tableView reloadRowsAtIndexPaths:paths withRowAnimation:UITableViewRowAnimationFade];
}

#pragma mark - Swipe actions (visited only)

- (UISwipeActionsConfiguration *)tableView:(UITableView *)tv
		trailingSwipeActionsConfigurationForRowAtIndexPath:(NSIndexPath *)indexPath {
	if (self.kind != RYGPAListKindVisited) return nil;
	if (indexPath.row >= (NSInteger)self.filteredVisits.count) return nil;
	RYGProfileAnalyzerVisit *vst = self.filteredVisits[indexPath.row];
	__weak typeof(self) weakSelf = self;
	UIContextualAction *del = [UIContextualAction
		contextualActionWithStyle:UIContextualActionStyleDestructive
							title:RYGLocalized(@"Remove")
						  handler:^(UIContextualAction *_, UIView *__, void(^done)(BOOL)) {
		[RYGProfileAnalyzerStorage removeVisitForUserPK:[RYGUtils currentUserPK] visitedPK:vst.user.pk];
		NSMutableArray *all = [weakSelf.allVisits mutableCopy];
		[all removeObject:vst];
		weakSelf.allVisits = all;
		[weakSelf applyFiltersAndSort];
		done(YES);
	}];
	del.image = [UIImage systemImageNamed:@"trash"];
	return [UISwipeActionsConfiguration configurationWithActions:@[del]];
}

#pragma mark - Multi-select

- (void)toggleSelectionMode {
	self.selectionMode = !self.selectionMode;
	[self.selectedPKs removeAllObjects];
	self.batchActionButton.hidden = !self.selectionMode;
	self.tableView.contentInset = UIEdgeInsetsMake(0, 0, self.selectionMode ? 96 : 0, 0);
	[self updateNavBar];
	[self refreshBatchBar];
	[self.tableView reloadData];
}

- (void)refreshBatchBar {
	NSUInteger n = self.selectedPKs.count;
	BOOL follow = (self.kind == RYGPAListKindFollow || self.kind == RYGPAListKindRefollow);
	NSString *t = follow
		? [NSString stringWithFormat:RYGLocalized(@"%lu selected"), (unsigned long)n]
		: [NSString stringWithFormat:RYGLocalized(@"Unfollow %lu"), (unsigned long)n];
	[self.batchActionButton setTitle:t forState:UIControlStateNormal];
	self.batchActionButton.backgroundColor = follow
		? ([RYGUtils RYGColor_Primary] ?: [UIColor systemBlueColor])
		: [UIColor systemRedColor];
	self.batchActionButton.enabled = n > 0;
	self.batchActionButton.alpha = n > 0 ? 1.0 : 0.5;
}

- (NSString *)verbForBatchOp:(RYGPABatchOp)op {
	switch (op) {
		case RYGPABatchOpFollow:         return RYGLocalized(@"Follow");
		case RYGPABatchOpRemoveFollower: return RYGLocalized(@"Remove");
		case RYGPABatchOpUnfollow:       return RYGLocalized(@"Unfollow");
	}
}

- (void)batchActionTapped {
	NSUInteger n = self.selectedPKs.count;
	if (!n) return;
	// Follow-back list: pick follow-back vs remove-follower before confirming.
	if (self.kind == RYGPAListKindFollow) {
		UIAlertController *sheet = [UIAlertController
			alertControllerWithTitle:[NSString stringWithFormat:RYGLocalized(@"%lu selected"), (unsigned long)n]
							 message:nil preferredStyle:UIAlertControllerStyleActionSheet];
		__weak typeof(self) weakSelf = self;
		[sheet addAction:[UIAlertAction actionWithTitle:RYGLocalized(@"Follow back") style:UIAlertActionStyleDefault handler:^(UIAlertAction *_) {
			[weakSelf confirmBatchOp:RYGPABatchOpFollow];
		}]];
		[sheet addAction:[UIAlertAction actionWithTitle:RYGLocalized(@"Remove follower") style:UIAlertActionStyleDestructive handler:^(UIAlertAction *_) {
			[weakSelf confirmBatchOp:RYGPABatchOpRemoveFollower];
		}]];
		[sheet addAction:[UIAlertAction actionWithTitle:RYGLocalized(@"Cancel") style:UIAlertActionStyleCancel handler:nil]];
		sheet.popoverPresentationController.sourceView = self.batchActionButton;
		sheet.popoverPresentationController.sourceRect = self.batchActionButton.bounds;
		[self presentViewController:sheet animated:YES completion:nil];
		return;
	}
	if (self.kind == RYGPAListKindRefollow) {
		[self confirmBatchOp:RYGPABatchOpFollow];
		return;
	}
	[self confirmBatchOp:RYGPABatchOpUnfollow];
}

- (void)confirmBatchOp:(RYGPABatchOp)op {
	NSUInteger n = self.selectedPKs.count;
	if (!n) return;
	NSString *verb = [self verbForBatchOp:op];
	NSString *title;
	switch (op) {
		case RYGPABatchOpFollow:         title = RYGLocalized(@"Batch follow"); break;
		case RYGPABatchOpRemoveFollower: title = RYGLocalized(@"Batch remove followers"); break;
		case RYGPABatchOpUnfollow:       title = RYGLocalized(@"Batch unfollow"); break;
	}
	NSString *msg;
	if (n > kRYGPABatchCap) {
		msg = [NSString stringWithFormat:RYGLocalized(@"%@ %lu accounts? The first %ld will be processed to avoid rate limits."),
			   verb, (unsigned long)n, (long)kRYGPABatchCap];
	} else {
		msg = [NSString stringWithFormat:RYGLocalized(@"%@ %lu accounts? This runs sequentially with a short pause between each."),
			   verb, (unsigned long)n];
	}
	UIAlertController *a = [UIAlertController alertControllerWithTitle:title
															  message:msg preferredStyle:UIAlertControllerStyleAlert];
	[a addAction:[UIAlertAction actionWithTitle:RYGLocalized(@"Cancel") style:UIAlertActionStyleCancel handler:nil]];
	UIAlertActionStyle style = (op == RYGPABatchOpFollow) ? UIAlertActionStyleDefault : UIAlertActionStyleDestructive;
	__weak typeof(self) weakSelf = self;
	[a addAction:[UIAlertAction actionWithTitle:verb style:style handler:^(UIAlertAction *_) {
		[weakSelf runBatchActionForOp:op];
	}]];
	[self presentViewController:a animated:YES completion:nil];
}

- (void)runBatchActionForOp:(RYGPABatchOp)op {
	NSMutableArray<RYGProfileAnalyzerUser *> *queue = [NSMutableArray array];
	for (RYGProfileAnalyzerUser *u in self.allUsers) {
		if (![self.selectedPKs containsObject:u.pk]) continue;
		// Skip users already in the target follow state (remove-follower has no such state).
		NSNumber *st = self.friendshipStatus[u.pk];
		if (op == RYGPABatchOpFollow   && st && [st boolValue])  continue;
		if (op == RYGPABatchOpUnfollow && st && ![st boolValue]) continue;
		[queue addObject:u];
		if (queue.count >= kRYGPABatchCap) break;
	}
	[self.selectedPKs removeAllObjects];
	[self refreshBatchBar];
	if (queue.count) [RYGBackgroundActivity setSource:@"analyzer_batch" active:YES];
	[self batchStep:queue op:op done:0 total:queue.count];
}

- (void)batchStep:(NSMutableArray<RYGProfileAnalyzerUser *> *)queue
			   op:(RYGPABatchOp)op
			 done:(NSUInteger)done
			total:(NSUInteger)total {
	if (!queue.count) {
		[RYGBackgroundActivity setSource:@"analyzer_batch" active:NO];
		NSString *finishedTitle, *finishedSub;
		switch (op) {
			case RYGPABatchOpFollow:
				finishedTitle = RYGLocalized(@"Batch follow finished");
				finishedSub = [NSString stringWithFormat:RYGLocalized(@"%lu accounts followed"), (unsigned long)total];
				break;
			case RYGPABatchOpRemoveFollower:
				finishedTitle = RYGLocalized(@"Batch remove followers finished");
				finishedSub = [NSString stringWithFormat:RYGLocalized(@"%lu followers removed"), (unsigned long)total];
				break;
			case RYGPABatchOpUnfollow:
				finishedTitle = RYGLocalized(@"Batch unfollow finished");
				finishedSub = [NSString stringWithFormat:RYGLocalized(@"%lu accounts unfollowed"), (unsigned long)total];
				break;
		}
		RYGNotifySuccess(RYG_NOTIF_ANALYZER_DONE, finishedTitle, finishedSub);
		self.navigationItem.prompt = nil;
		[self toggleSelectionMode];
		[self refreshCounts];
		return;
	}
	RYGProfileAnalyzerUser *u = queue.firstObject;
	[queue removeObjectAtIndex:0];
	__weak typeof(self) weakSelf = self;
	void(^handler)(NSDictionary *, NSError *) = ^(NSDictionary *resp, NSError *err) {
		typeof(self) strongSelf = weakSelf;
		if (!strongSelf) return;
		NSUInteger nextDone = done + 1;
		BOOL ok = (err == nil) && ([resp[@"status"] isEqualToString:@"ok"] || resp[@"friendship_status"]);
		if (ok) {
			if (op == RYGPABatchOpRemoveFollower) {
				[strongSelf persistFollowerRemovalForUser:u];
			} else {
				BOOL follow = (op == RYGPABatchOpFollow);
				strongSelf.friendshipStatus[u.pk] = @(follow);
				[RYGPAFriendshipCache setFollowing:follow forPK:u.pk];
				[strongSelf persistFriendshipChangeForUser:u followed:follow];
			}
			[strongSelf removeUserFromList:u];
		}
		NSString *progressFmt;
		switch (op) {
			case RYGPABatchOpFollow:         progressFmt = RYGLocalized(@"Following… %lu / %lu"); break;
			case RYGPABatchOpRemoveFollower: progressFmt = RYGLocalized(@"Removing… %lu / %lu"); break;
			case RYGPABatchOpUnfollow:       progressFmt = RYGLocalized(@"Unfollowing… %lu / %lu"); break;
		}
		strongSelf.navigationItem.prompt = [NSString stringWithFormat:progressFmt,
											(unsigned long)nextDone, (unsigned long)total];
		dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(kRYGPABatchDelay * NSEC_PER_SEC)),
					   dispatch_get_main_queue(), ^{
			[weakSelf batchStep:queue op:op done:nextDone total:total];
		});
	};
	switch (op) {
		case RYGPABatchOpFollow:         [RYGInstagramAPI followUserPK:u.pk completion:handler]; break;
		case RYGPABatchOpRemoveFollower: [RYGInstagramAPI removeFollowerPK:u.pk completion:handler]; break;
		case RYGPABatchOpUnfollow:       [RYGInstagramAPI unfollowUserPK:u.pk completion:handler]; break;
	}
}

// Dismissing mid-batch stops the step chain via the weak self — clear keep-alive here.
- (void)dealloc {
	[RYGBackgroundActivity setSource:@"analyzer_batch" active:NO];
}

@end
