#import "SCIDeletedMessagesViewController.h"
#import "SCIDeletedMessagesModels.h"
#import "../../UI/SCIPopupChrome.h"
#import "../../Lock/SCILockGate.h"
#import "../../Lock/SCILockGroups.h"
#import <AVFoundation/AVFoundation.h>
#import "SCIDeletedMessagesStorage.h"
#import "SCIDeletedMessagesFilter.h"
#import "SCIDeletedMessagesUserDetailViewController.h"
#import "../../Utils.h"
#import "../../SCIImageCache.h"
#import "../../Networking/SCIInstagramAPI.h"
#import "../../Localization/SCILocalization.h"
#import "SCIDeletedMessagesStorageViewController.h"
#import "SCIDeletedMessagesDate.h"
#import "SCIDeletedMessagesCapture.h"

#pragma mark - Sender row cell

@interface SCIDMSenderCell : UITableViewCell
@property (nonatomic, strong) UIImageView *avatarView;
@property (nonatomic, strong) UILabel *nameLabel;
@property (nonatomic, strong) UILabel *handleLabel;
@property (nonatomic, strong) UILabel *previewLabel;
@property (nonatomic, strong) UILabel *timeLabel;
@property (nonatomic, strong) UIView *countBadge;
@property (nonatomic, strong) UILabel *countLabel;
@property (nonatomic, copy) NSString *avatarURL;
- (void)applyGroup:(SCIDeletedMessageGroup *)g
			latest:(SCIDeletedMessage *)latest
			 owner:(NSString *)ownerPK
		 preview:(NSString *)preview
			  time:(NSString *)time
			unseen:(NSUInteger)unseen;
@end

@implementation SCIDMSenderCell

- (instancetype)initWithStyle:(UITableViewCellStyle)style reuseIdentifier:(NSString *)rid {
	if ((self = [super initWithStyle:style reuseIdentifier:rid])) {
		self.accessoryType = UITableViewCellAccessoryDisclosureIndicator;

		_avatarView = [self.class imageView];
		[self.contentView addSubview:_avatarView];

		_nameLabel = [self.class labelWithFont:[UIFont systemFontOfSize:16 weight:UIFontWeightSemibold]
										 color:UIColor.labelColor];
		[self.contentView addSubview:_nameLabel];

		_handleLabel = [self.class labelWithFont:[UIFont systemFontOfSize:13]
										  color:UIColor.secondaryLabelColor];
		[self.contentView addSubview:_handleLabel];

		_previewLabel = [self.class labelWithFont:[UIFont systemFontOfSize:13]
										   color:UIColor.tertiaryLabelColor];
		_previewLabel.numberOfLines = 1;
		[self.contentView addSubview:_previewLabel];

		_timeLabel = [self.class labelWithFont:[UIFont systemFontOfSize:12]
										color:UIColor.tertiaryLabelColor];
		_timeLabel.textAlignment = NSTextAlignmentRight;
		[self.contentView addSubview:_timeLabel];

		_countBadge = [UIView new];
		_countBadge.translatesAutoresizingMaskIntoConstraints = NO;
		_countBadge.layer.cornerRadius = 10;
		_countBadge.layer.masksToBounds = YES;
		_countBadge.backgroundColor = UIColor.systemRedColor;
		[self.contentView addSubview:_countBadge];

		_countLabel = [self.class labelWithFont:[UIFont systemFontOfSize:11 weight:UIFontWeightSemibold]
										 color:UIColor.whiteColor];
		_countLabel.textAlignment = NSTextAlignmentCenter;
		[_countBadge addSubview:_countLabel];

		UILayoutGuide *m = self.contentView.layoutMarginsGuide;
		[NSLayoutConstraint activateConstraints:@[
			[_avatarView.leadingAnchor constraintEqualToAnchor:m.leadingAnchor],
			[_avatarView.centerYAnchor constraintEqualToAnchor:self.contentView.centerYAnchor],
			[_avatarView.widthAnchor constraintEqualToConstant:52],
			[_avatarView.heightAnchor constraintEqualToConstant:52],

			[_nameLabel.leadingAnchor constraintEqualToAnchor:_avatarView.trailingAnchor constant:12],
			[_nameLabel.topAnchor constraintEqualToAnchor:self.contentView.topAnchor constant:10],
			[_nameLabel.trailingAnchor constraintLessThanOrEqualToAnchor:_timeLabel.leadingAnchor constant:-8],

			[_timeLabel.trailingAnchor constraintEqualToAnchor:m.trailingAnchor],
			[_timeLabel.firstBaselineAnchor constraintEqualToAnchor:_nameLabel.firstBaselineAnchor],

			[_handleLabel.leadingAnchor constraintEqualToAnchor:_nameLabel.leadingAnchor],
			[_handleLabel.topAnchor constraintEqualToAnchor:_nameLabel.bottomAnchor constant:1],
			[_handleLabel.trailingAnchor constraintLessThanOrEqualToAnchor:_countBadge.leadingAnchor constant:-8],

			[_previewLabel.leadingAnchor constraintEqualToAnchor:_nameLabel.leadingAnchor],
			[_previewLabel.topAnchor constraintEqualToAnchor:_handleLabel.bottomAnchor constant:3],
			[_previewLabel.trailingAnchor constraintEqualToAnchor:m.trailingAnchor],
			[_previewLabel.bottomAnchor constraintLessThanOrEqualToAnchor:self.contentView.bottomAnchor constant:-10],

			[_countBadge.trailingAnchor constraintEqualToAnchor:m.trailingAnchor],
			[_countBadge.topAnchor constraintEqualToAnchor:_timeLabel.bottomAnchor constant:4],
			[_countBadge.heightAnchor constraintEqualToConstant:20],
			[_countBadge.widthAnchor constraintGreaterThanOrEqualToConstant:24],

			[_countLabel.topAnchor constraintEqualToAnchor:_countBadge.topAnchor],
			[_countLabel.bottomAnchor constraintEqualToAnchor:_countBadge.bottomAnchor],
			[_countLabel.leadingAnchor constraintEqualToAnchor:_countBadge.leadingAnchor constant:6],
			[_countLabel.trailingAnchor constraintEqualToAnchor:_countBadge.trailingAnchor constant:-6],
		]];
	}
	return self;
}

+ (UILabel *)labelWithFont:(UIFont *)font color:(UIColor *)color {
	UILabel *l = [UILabel new];
	l.translatesAutoresizingMaskIntoConstraints = NO;
	l.font = font;
	l.textColor = color;
	return l;
}

+ (UIImageView *)imageView {
	UIImageView *iv = [UIImageView new];
	iv.translatesAutoresizingMaskIntoConstraints = NO;
	iv.contentMode = UIViewContentModeScaleAspectFill;
	iv.backgroundColor = UIColor.secondarySystemBackgroundColor;
	iv.layer.cornerRadius = 26;
	iv.layer.masksToBounds = YES;
	iv.tintColor = UIColor.systemGray3Color;
	iv.image = [UIImage systemImageNamed:@"person.circle.fill"];
	return iv;
}

- (void)prepareForReuse {
	[super prepareForReuse];
	self.avatarURL = nil;
	self.avatarView.image = [UIImage systemImageNamed:@"person.circle.fill"];
	self.avatarView.tintColor = UIColor.systemGray3Color;
	self.nameLabel.font = [UIFont systemFontOfSize:16 weight:UIFontWeightRegular];
}

- (void)applyGroup:(SCIDeletedMessageGroup *)g
			latest:(SCIDeletedMessage *)latest
			 owner:(NSString *)ownerPK
		 preview:(NSString *)preview
			  time:(NSString *)time
			unseen:(NSUInteger)unseen {
	self.previewLabel.text = preview;
	self.timeLabel.text = time;
	self.countLabel.text = [NSString stringWithFormat:@"%lu", (unsigned long)unseen];
	self.countBadge.hidden = unseen == 0;
	self.nameLabel.font = [UIFont systemFontOfSize:16 weight:(unseen ? UIFontWeightSemibold : UIFontWeightRegular)];

	if (g.isGroup) {
		self.nameLabel.text = g.threadTitle.length ? g.threadTitle : SCILocalized(@"Group chat");

		NSMutableArray<NSString *> *handles = [NSMutableArray array];
		for (SCIDeletedMessage *m in g.distinctSenders) {
			NSString *h = m.senderUsername.length ? [@"@" stringByAppendingString:m.senderUsername] : m.senderFullName;
			if (h.length) [handles addObject:h];
			if (handles.count >= 3) break;
		}
		self.handleLabel.text = handles.count ? [handles componentsJoinedByString:@", "] : SCILocalized(@"Group chat");

		self.avatarView.image = [UIImage systemImageNamed:@"person.2.circle.fill"];
		self.avatarView.tintColor = UIColor.systemGray3Color;
		self.avatarURL = g.threadAvatarURL;
		if (!g.threadAvatarURL.length) return;
		NSURL *gurl = [NSURL URLWithString:g.threadAvatarURL];
		if (!gurl) return;
		__weak typeof(self) wsg = self;
		[SCIImageCache loadImageFromURL:gurl completion:^(UIImage *img) {
			if (!img || ![wsg.avatarURL isEqualToString:g.threadAvatarURL]) return;
			wsg.avatarView.image = img;
		}];
		return;
	}

	self.nameLabel.text = g.senderFullName.length ? g.senderFullName : (g.senderUsername.length ? g.senderUsername : SCILocalized(@"Unknown user"));
	self.handleLabel.text = g.senderUsername.length ? [@"@" stringByAppendingString:g.senderUsername] : @"";

	self.avatarURL = g.senderProfilePicURL;
	if (!g.senderProfilePicURL.length) return;

	NSURL *url = [NSURL URLWithString:g.senderProfilePicURL];
	if (!url) return;

	__weak typeof(self) ws = self;
	[SCIImageCache loadImageFromURL:url completion:^(UIImage *img) {
		if (!img || ![ws.avatarURL isEqualToString:g.senderProfilePicURL]) return;
		ws.avatarView.image = img;
	}];
}

@end

#pragma mark - Empty state

@interface SCIDMEmptyView : UIView
@property (nonatomic, strong) UIImageView *iconView;
@property (nonatomic, strong) UILabel *titleLabel;
@property (nonatomic, strong) UILabel *messageLabel;
- (void)applyIcon:(NSString *)icon title:(NSString *)title message:(NSString *)message;
@end

@implementation SCIDMEmptyView

- (instancetype)initWithFrame:(CGRect)frame {
	if ((self = [super initWithFrame:frame])) {
		_iconView = [UIImageView new];
		_iconView.translatesAutoresizingMaskIntoConstraints = NO;
		_iconView.contentMode = UIViewContentModeScaleAspectFit;
		_iconView.tintColor = UIColor.tertiaryLabelColor;
		_iconView.preferredSymbolConfiguration = [UIImageSymbolConfiguration configurationWithPointSize:46 weight:UIImageSymbolWeightLight];
		[self addSubview:_iconView];

		_titleLabel = [self.class labelWithFont:[UIFont systemFontOfSize:17 weight:UIFontWeightSemibold]
										 color:UIColor.secondaryLabelColor];
		_titleLabel.textAlignment = NSTextAlignmentCenter;
		[self addSubview:_titleLabel];

		_messageLabel = [self.class labelWithFont:[UIFont systemFontOfSize:14]
										   color:UIColor.tertiaryLabelColor];
		_messageLabel.numberOfLines = 0;
		_messageLabel.textAlignment = NSTextAlignmentCenter;
		[self addSubview:_messageLabel];

		[NSLayoutConstraint activateConstraints:@[
			[_iconView.centerXAnchor constraintEqualToAnchor:self.centerXAnchor],
			[_iconView.centerYAnchor constraintEqualToAnchor:self.centerYAnchor constant:-30],
			[_iconView.widthAnchor constraintEqualToConstant:64],
			[_iconView.heightAnchor constraintEqualToConstant:64],

			[_titleLabel.topAnchor constraintEqualToAnchor:_iconView.bottomAnchor constant:14],
			[_titleLabel.leadingAnchor constraintEqualToAnchor:self.leadingAnchor constant:32],
			[_titleLabel.trailingAnchor constraintEqualToAnchor:self.trailingAnchor constant:-32],

			[_messageLabel.topAnchor constraintEqualToAnchor:_titleLabel.bottomAnchor constant:6],
			[_messageLabel.leadingAnchor constraintEqualToAnchor:self.leadingAnchor constant:32],
			[_messageLabel.trailingAnchor constraintEqualToAnchor:self.trailingAnchor constant:-32],
		]];
	}
	return self;
}

+ (UILabel *)labelWithFont:(UIFont *)font color:(UIColor *)color {
	UILabel *l = [UILabel new];
	l.translatesAutoresizingMaskIntoConstraints = NO;
	l.font = font;
	l.textColor = color;
	return l;
}

- (void)applyIcon:(NSString *)icon title:(NSString *)title message:(NSString *)message {
	self.iconView.image = [UIImage systemImageNamed:icon];
	self.titleLabel.text = title;
	self.messageLabel.text = message;
}

@end

#pragma mark - Seen tracking

static NSString *const kSCIDMSeenPrefKey = @"deleted_messages_seen";

static NSString *sciSeenKey(NSString *ownerPk, NSString *senderPk) {
	return [NSString stringWithFormat:@"%@:%@", ownerPk ?: @"", senderPk ?: @""];
}

static NSTimeInterval sciSeenTimestamp(NSString *ownerPk, NSString *senderPk) {
	NSDictionary *all = [NSUserDefaults.standardUserDefaults dictionaryForKey:kSCIDMSeenPrefKey];
	id v = all[sciSeenKey(ownerPk, senderPk)];
	return [v isKindOfClass:NSNumber.class] ? [v doubleValue] : 0;
}

static void sciMarkSenderSeen(NSString *ownerPk, NSString *senderPk) {
	if (!senderPk.length) return;

	NSUserDefaults *d = NSUserDefaults.standardUserDefaults;
	NSMutableDictionary *m = [[d dictionaryForKey:kSCIDMSeenPrefKey] ?: @{} mutableCopy];
	m[sciSeenKey(ownerPk, senderPk)] = @(NSDate.date.timeIntervalSince1970);
	[d setObject:m forKey:kSCIDMSeenPrefKey];
	[d synchronize];
}

static NSUInteger sciUnseenCountForGroup(SCIDeletedMessageGroup *g, NSString *ownerPk) {
	NSTimeInterval seen = sciSeenTimestamp(ownerPk, g.identifier);
	if (seen <= 0) return g.count;

	NSUInteger n = 0;
	for (SCIDeletedMessage *m in g.messages) {
		NSDate *d = m.deletedAt ?: m.capturedAt ?: m.sentAt;
		if (d.timeIntervalSince1970 > seen) n++;
	}
	return n;
}

#pragma mark - VC

@interface SCIDeletedMessagesViewController () <UITableViewDataSource, UITableViewDelegate, UISearchResultsUpdating>
@property (nonatomic, strong) UITableView *tableView;
@property (nonatomic, strong) SCIDMEmptyView *emptyView;
@property (nonatomic, strong) UISearchController *searchCtl;
@property (nonatomic, strong) UILabel *footerLabel;
@property (nonatomic, strong) NSArray<SCIDeletedMessageGroup *> *allGroups;
@property (nonatomic, strong) NSArray<SCIDeletedMessageGroup *> *visibleGroups;
@property (nonatomic, strong) NSMutableSet<NSString *> *resolvedThreadIds;
@property (nonatomic, strong) SCIDeletedMessagesFilter *filter;
@property (nonatomic, copy) NSString *ownerPK;
@end

@implementation SCIDeletedMessagesViewController

+ (void)load {
	for (NSString *action in @[SCI_NOTIF_UNSENT_MESSAGE, SCI_NOTIF_REACTION_REMOVED]) {
		[SCINotificationCenter.shared setDefaultTapProvider:^void (^(void))(void) {
			return ^{ [SCIDeletedMessagesViewController presentFromViewController:nil]; };
		} ownerVCClass:[SCIDeletedMessagesViewController class]
		  forAction:action];
	}
}

+ (void)presentFromViewController:(UIViewController *)presenter {
	[SCILockGate presentLockedVC:[SCIDeletedMessagesViewController new]
						forGroup:SCILockGroupKeepDeleted
							from:presenter];
}

- (instancetype)init {
	if ((self = [super init])) {
		_filter = [SCIDeletedMessagesFilter new];
		_allGroups = @[];
		_visibleGroups = @[];
	}
	return self;
}

- (void)viewDidLoad {
	[super viewDidLoad];

	self.title = SCILocalized(@"Deleted messages");
	self.view.backgroundColor = [SCIPopupChrome backgroundColor];

	[self installNavigationItems];
	[self installSearchController];
	[self installTable];
	[self installEmptyView];

	[NSNotificationCenter.defaultCenter addObserver:self
										   selector:@selector(storeChanged:)
											   name:SCIDeletedMessagesDidChangeNotification
											 object:nil];
}

- (void)dealloc {
	[NSNotificationCenter.defaultCenter removeObserver:self];
}

- (void)viewWillAppear:(BOOL)animated {
	[super viewWillAppear:animated];
	[self reload];
}

- (void)viewDidAppear:(BOOL)animated {
	[super viewDidAppear:animated];

	@try {
		[AVAudioSession.sharedInstance setActive:NO
									 withOptions:AVAudioSessionSetActiveOptionNotifyOthersOnDeactivation
										   error:nil];
	} @catch (__unused id e) {}
}

#pragma mark - Setup

- (void)installNavigationItems {
	self.navigationItem.largeTitleDisplayMode = UINavigationItemLargeTitleDisplayModeNever;
	self.navigationItem.rightBarButtonItem = [[UIBarButtonItem alloc] initWithImage:[UIImage systemImageNamed:@"ellipsis.circle"]
																			   menu:[self buildOverflowMenu]];

	if (self.navigationController.viewControllers.firstObject == self) {
		self.navigationItem.leftBarButtonItem = [[UIBarButtonItem alloc] initWithImage:[UIImage systemImageNamed:@"xmark"]
																				 style:UIBarButtonItemStylePlain
																				target:self
																				action:@selector(closeTapped)];
	}
}

- (void)installSearchController {
	UISearchController *sc = [[UISearchController alloc] initWithSearchResultsController:nil];
	sc.searchResultsUpdater = self;
	sc.obscuresBackgroundDuringPresentation = NO;
	sc.hidesNavigationBarDuringPresentation = NO;
	sc.searchBar.placeholder = SCILocalized(@"Search senders or messages");
	sc.searchBar.autocapitalizationType = UITextAutocapitalizationTypeNone;

	self.searchCtl = sc;
	self.navigationItem.searchController = sc;
	self.navigationItem.hidesSearchBarWhenScrolling = YES;

	if (@available(iOS 16.0, *)) {
		self.navigationItem.preferredSearchBarPlacement = UINavigationItemSearchBarPlacementStacked;
	}

	self.definesPresentationContext = YES;
}

- (void)installTable {
	self.tableView = [[UITableView alloc] initWithFrame:CGRectZero style:UITableViewStylePlain];
	self.tableView.translatesAutoresizingMaskIntoConstraints = NO;
	self.tableView.dataSource = self;
	self.tableView.delegate = self;
	self.tableView.rowHeight = 76;
	self.tableView.backgroundColor = [SCIPopupChrome backgroundColor];
	self.tableView.separatorInset = UIEdgeInsetsMake(0, 80, 0, 0);
	[self.tableView registerClass:SCIDMSenderCell.class forCellReuseIdentifier:@"sender"];

	UIRefreshControl *rc = [UIRefreshControl new];
	[rc addTarget:self action:@selector(pulled:) forControlEvents:UIControlEventValueChanged];
	self.tableView.refreshControl = rc;

	[self.view addSubview:self.tableView];

	[NSLayoutConstraint activateConstraints:@[
		[self.tableView.leadingAnchor constraintEqualToAnchor:self.view.leadingAnchor],
		[self.tableView.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor],
		[self.tableView.topAnchor constraintEqualToAnchor:self.view.safeAreaLayoutGuide.topAnchor],
		[self.tableView.bottomAnchor constraintEqualToAnchor:self.view.bottomAnchor],
	]];

	self.footerLabel = [UILabel new];
	self.footerLabel.font = [UIFont systemFontOfSize:12];
	self.footerLabel.textColor = UIColor.tertiaryLabelColor;
	self.footerLabel.textAlignment = NSTextAlignmentCenter;
	self.footerLabel.numberOfLines = 0;
	self.footerLabel.frame = CGRectMake(0, 0, 320, 60);
	self.tableView.tableFooterView = self.footerLabel;
}

- (void)installEmptyView {
	self.emptyView = [SCIDMEmptyView new];
	self.emptyView.translatesAutoresizingMaskIntoConstraints = NO;
	self.emptyView.hidden = YES;
	[self.view addSubview:self.emptyView];

	[NSLayoutConstraint activateConstraints:@[
		[self.emptyView.leadingAnchor constraintEqualToAnchor:self.view.leadingAnchor],
		[self.emptyView.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor],
		[self.emptyView.topAnchor constraintEqualToAnchor:self.tableView.topAnchor],
		[self.emptyView.bottomAnchor constraintEqualToAnchor:self.view.bottomAnchor],
	]];
}

#pragma mark - Menu

- (UIAction *)menuAction:(NSArray *)e handler:(void (^)(void))handler checked:(BOOL)checked {
	UIAction *a = [UIAction actionWithTitle:e[0]
									  image:[UIImage systemImageNamed:e[2]]
								 identifier:nil
									handler:^(__unused UIAction *_) {
		if (handler) handler();
	}];
	a.state = checked ? UIMenuElementStateOn : UIMenuElementStateOff;
	return a;
}

- (UIMenu *)menuWithTitle:(NSString *)title icon:(NSString *)icon entries:(NSArray<NSArray *> *)entries handler:(void (^)(NSInteger value))handler current:(NSInteger)current {
	NSMutableArray *items = [NSMutableArray arrayWithCapacity:entries.count];

	for (NSArray *e in entries) {
		NSInteger value = [e[1] integerValue];
		[items addObject:[self menuAction:e handler:^{
			if (handler) handler(value);
			[self refilter];
			[self refreshNavMenu];
		} checked:value == current]];
	}

	return [UIMenu menuWithTitle:title image:[UIImage systemImageNamed:icon] identifier:nil options:0 children:items];
}

- (UIMenu *)buildOverflowMenu {
	__weak typeof(self) ws = self;

	UIMenu *dateMenu = [self menuWithTitle:SCILocalized(@"Date range")
									  icon:@"calendar"
								   entries:@[
		@[SCILocalized(@"All time"), @(SCIDMDateRangeAll), @"infinity"],
		@[SCILocalized(@"Today"), @(SCIDMDateRangeToday), @"sun.max"],
		@[SCILocalized(@"Last 7 days"), @(SCIDMDateRangeWeek), @"calendar"],
		@[SCILocalized(@"Last 30 days"), @(SCIDMDateRangeMonth), @"calendar.badge.clock"],
	] handler:^(NSInteger value) {
		ws.filter.dateRange = (SCIDMDateRange)value;
	} current:self.filter.dateRange];

	UIMenu *sortMenu = [self menuWithTitle:SCILocalized(@"Sort")
									  icon:@"arrow.up.arrow.down"
								   entries:@[
		@[SCILocalized(@"Most recent"), @(SCIDMSortRecent), @"clock.arrow.circlepath"],
		@[SCILocalized(@"Oldest first"), @(SCIDMSortOldest), @"arrow.up.to.line"],
		@[SCILocalized(@"Most messages"), @(SCIDMSortCountDesc), @"number"],
	] handler:^(NSInteger value) {
		ws.filter.sort = (SCIDMSort)value;
	} current:self.filter.sort];

	NSString *fmt = [SCIUtils getStringPref:@"dm_log_date_format"] ?: @"relative";
	UIAction *(^fmtAction)(NSString *, NSString *) = ^UIAction *(NSString *title, NSString *value) {
		UIAction *a = [UIAction actionWithTitle:title image:nil identifier:nil handler:^(__unused UIAction *_) {
			[SCIUtils setPref:value forKey:@"dm_log_date_format"];
			[ws refilter];
			[ws refreshNavMenu];
		}];
		a.state = [fmt isEqualToString:value] ? UIMenuElementStateOn : UIMenuElementStateOff;
		return a;
	};

	UIMenu *formatMenu = [UIMenu menuWithTitle:SCILocalized(@"Date format")
										 image:[UIImage systemImageNamed:@"clock"]
									identifier:nil
									   options:0
									  children:@[
		fmtAction(SCILocalized(@"Relative (1m / 3h / 3d ago)"), @"relative"),
		fmtAction(SCILocalized(@"Absolute date + time"), @"absolute"),
	]];

	UIAction *refresh = [UIAction actionWithTitle:SCILocalized(@"Refresh names & photos")
											image:[UIImage systemImageNamed:@"arrow.clockwise"]
									   identifier:nil
										  handler:^(__unused UIAction *_) {
		[ws refreshAllMetadata];
	}];
	if (!self.allGroups.count) refresh.attributes = UIMenuElementAttributesDisabled;

	UIAction *storage = [UIAction actionWithTitle:SCILocalized(@"Storage")
											image:[UIImage systemImageNamed:@"externaldrive"]
									   identifier:nil
										  handler:^(__unused UIAction *_) {
		[ws storageTapped];
	}];

	UIAction *clear = [UIAction actionWithTitle:SCILocalized(@"Clear log")
										  image:[UIImage systemImageNamed:@"trash"]
									 identifier:nil
										handler:^(__unused UIAction *_) {
		[ws clearAllTapped];
	}];
	clear.attributes = self.allGroups.count ? UIMenuElementAttributesDestructive : UIMenuElementAttributesDisabled;

	return [UIMenu menuWithTitle:@"" children:@[
		dateMenu,
		sortMenu,
		formatMenu,
		[UIMenu menuWithTitle:@"" image:nil identifier:nil options:UIMenuOptionsDisplayInline children:@[refresh, storage, clear]]
	]];
}

- (void)refreshNavMenu {
	self.navigationItem.rightBarButtonItem.menu = [self buildOverflowMenu];
}

#pragma mark - Data

- (void)pulled:(UIRefreshControl *)rc {
	[self reload];
	[rc endRefreshing];
}

- (void)storeChanged:(NSNotification *)note {
	if (!self.isViewLoaded || !self.view.window) return;
	[self reload];
}

- (void)reload {
	self.ownerPK = [SCIUtils currentUserPK];
	self.allGroups = [SCIDeletedMessagesStorage groupedByThreadForOwnerPK:self.ownerPK];
	[self resolveThreadsNeedingInfo];
	[self refilter];
	[self refreshNavMenu];
}

// Resolve group flag/title + avatars for any thread still missing them (legacy / switched-in account).
- (void)resolveThreadsNeedingInfo {
	if (!self.resolvedThreadIds) self.resolvedThreadIds = [NSMutableSet set];

	for (SCIDeletedMessageGroup *g in self.allGroups) {
		if (!g.threadId.length || [self.resolvedThreadIds containsObject:g.threadId]) continue;

		BOOL needs = !g.threadTitle.length;
		if (!needs && g.isGroup) {
			for (SCIDeletedMessage *m in g.distinctSenders) {
				if (!m.senderProfilePicURL.length) { needs = YES; break; }
			}
		}
		if (!needs) continue;

		// Once per thread per session — don't re-fire for members who have no avatar.
		[self.resolvedThreadIds addObject:g.threadId];
		sciDMResolveThreadInfo(g.threadId, self.ownerPK);
	}
}

- (void)refilter {
	self.visibleGroups = [self.filter applyToGroups:self.allGroups];
	[self.tableView reloadData];
	[self refreshEmptyState];
	[self refreshFooter];
}

- (void)refreshEmptyState {
	BOOL noRecords = self.allGroups.count == 0;
	BOOL empty = self.visibleGroups.count == 0;

	self.emptyView.hidden = !empty;
	self.tableView.hidden = empty;

	if (!empty) return;

	if (noRecords) {
		BOOL enabled = [SCIUtils getBoolPref:@"deleted_messages_log_enabled"];
		[self.emptyView applyIcon:(enabled ? @"tray" : @"tray.full")
							 title:(enabled ? SCILocalized(@"No deleted messages yet") : SCILocalized(@"Logging is off"))
						   message:(enabled
									? SCILocalized(@"When someone unsends a message, it will appear here grouped by chat.")
									: SCILocalized(@"Enable Settings → Messages → Deleted messages log to start recording."))];
	} else {
		[self.emptyView applyIcon:@"line.3.horizontal.decrease.circle"
							 title:SCILocalized(@"No matches")
						   message:SCILocalized(@"Adjust the filters or clear the search to see more.")];
	}
}

- (void)refreshFooter {
	NSUInteger total = 0;
	for (SCIDeletedMessageGroup *g in self.allGroups) total += g.count;

	if (!total) {
		self.footerLabel.text = @"";
		self.tableView.tableFooterView = self.footerLabel;
		return;
	}

	self.footerLabel.text = [NSString stringWithFormat:SCILocalized(@"%lu messages in %lu chats"),
							 (unsigned long)total,
							 (unsigned long)self.allGroups.count];

	[self.footerLabel sizeToFit];

	CGRect f = self.footerLabel.frame;
	f.size.width = self.tableView.bounds.size.width;
	f.size.height = MAX(60, f.size.height + 24);
	self.footerLabel.frame = f;
	self.tableView.tableFooterView = self.footerLabel;
}

#pragma mark - Actions

- (void)updateSearchResultsForSearchController:(UISearchController *)sc {
	self.filter.searchText = sc.searchBar.text;
	[self refilter];
}

- (void)closeTapped {
	[self dismissViewControllerAnimated:YES completion:nil];
}

- (void)storageTapped {
	[self.navigationController pushViewController:[SCIDeletedMessagesStorageViewController new] animated:YES];
}

- (void)refreshAllMetadata {
	[self.resolvedThreadIds removeAllObjects];
	NSString *owner = self.ownerPK;
	NSMutableSet<NSString *> *threads = [NSMutableSet set];
	NSMutableSet<NSString *> *legacySenders = [NSMutableSet set];

	for (SCIDeletedMessageGroup *g in self.allGroups) {
		if (g.threadId.length) [threads addObject:g.threadId];
		else if (g.senderPk.length) [legacySenders addObject:g.senderPk];
	}

	for (NSString *tid in threads) sciDMRefreshThreadInfo(tid, owner);

	// Legacy threadless records: refresh the sender via the user-info endpoint.
	for (NSString *pk in legacySenders) {
		[SCIInstagramAPI sendRequestWithMethod:@"GET"
										  path:[NSString stringWithFormat:@"users/%@/info/", pk]
										  body:nil
									completion:^(NSDictionary *resp, NSError *error) {
			NSDictionary *user = [resp[@"user"] isKindOfClass:NSDictionary.class] ? resp[@"user"] : nil;
			if (user.count) [SCIDeletedMessagesStorage applySenderInfo:user forSenderPK:pk ownerPK:owner overwrite:YES];
		}];
	}

	SCINotifyInfo(SCI_NOTIF_GENERIC, SCILocalized(@"Refreshing names & photos"), nil);
}

- (void)clearAllTapped {
	if (!self.allGroups.count) return;

	UIAlertController *a = [UIAlertController alertControllerWithTitle:SCILocalized(@"Clear deleted-message log?")
															  message:SCILocalized(@"Removes every preserved deleted message and its captured media for this account.")
													   preferredStyle:UIAlertControllerStyleAlert];

	[a addAction:[UIAlertAction actionWithTitle:SCILocalized(@"Cancel") style:UIAlertActionStyleCancel handler:nil]];
	[a addAction:[UIAlertAction actionWithTitle:SCILocalized(@"Clear") style:UIAlertActionStyleDestructive handler:^(__unused UIAlertAction *_) {
		[SCIDeletedMessagesStorage resetForOwnerPK:self.ownerPK];
	}]];

	[self presentViewController:a animated:YES completion:nil];
}

#pragma mark - Table

- (NSInteger)tableView:(UITableView *)tv numberOfRowsInSection:(NSInteger)section {
	return (NSInteger)self.visibleGroups.count;
}

- (SCIDeletedMessageGroup *)groupAtIndexPath:(NSIndexPath *)ip {
	return ip.row < (NSInteger)self.visibleGroups.count ? self.visibleGroups[ip.row] : nil;
}

- (UITableViewCell *)tableView:(UITableView *)tv cellForRowAtIndexPath:(NSIndexPath *)ip {
	SCIDMSenderCell *cell = [tv dequeueReusableCellWithIdentifier:@"sender" forIndexPath:ip];
	SCIDeletedMessageGroup *g = [self groupAtIndexPath:ip];
	SCIDeletedMessage *latest = g.latest;

	[cell applyGroup:g
			  latest:latest
			   owner:self.ownerPK
			 preview:[self previewTextForGroup:g latest:latest]
				time:[SCIDeletedMessagesDate stringForDate:g.lastDeletedAt]
			  unseen:sciUnseenCountForGroup(g, self.ownerPK)];

	if (!g.isGroup && !g.senderProfilePicURL.length) [self backfillSenderIfNeeded:g];
	return cell;
}

- (void)tableView:(UITableView *)tv didSelectRowAtIndexPath:(NSIndexPath *)ip {
	[tv deselectRowAtIndexPath:ip animated:YES];

	SCIDeletedMessageGroup *g = [self groupAtIndexPath:ip];
	if (!g) return;

	sciMarkSenderSeen(self.ownerPK, g.identifier);
	[tv reloadRowsAtIndexPaths:@[ip] withRowAnimation:UITableViewRowAnimationNone];

	SCIDeletedMessagesUserDetailViewController *vc = [[SCIDeletedMessagesUserDetailViewController alloc] initWithGroup:g ownerPK:self.ownerPK];
	[self.navigationController pushViewController:vc animated:YES];
}

- (UISwipeActionsConfiguration *)tableView:(UITableView *)tv trailingSwipeActionsConfigurationForRowAtIndexPath:(NSIndexPath *)ip {
	SCIDeletedMessageGroup *g = [self groupAtIndexPath:ip];
	if (!g) return nil;

	__weak typeof(self) ws = self;
	UIContextualAction *del = [UIContextualAction contextualActionWithStyle:UIContextualActionStyleDestructive
																	  title:SCILocalized(@"Clear")
																	handler:^(__unused UIContextualAction *a, __unused UIView *src, void (^done)(BOOL)) {
		if (g.threadId.length) [SCIDeletedMessagesStorage deleteMessagesForThreadId:g.threadId ownerPK:ws.ownerPK];
		else [SCIDeletedMessagesStorage deleteMessagesForSenderPK:g.senderPk ownerPK:ws.ownerPK threadlessOnly:YES];
		done(YES);
	}];
	del.image = [UIImage systemImageNamed:@"trash"];
	return [UISwipeActionsConfiguration configurationWithActions:@[del]];
}

#pragma mark - Backfill

- (void)backfillSenderIfNeeded:(SCIDeletedMessageGroup *)g {
	if (!g.senderPk.length) return;

	static NSMutableSet<NSString *> *inflight;
	static dispatch_once_t once;
	dispatch_once(&once, ^{ inflight = [NSMutableSet set]; });

	NSString *senderPk = g.senderPk.copy;
	NSString *ownerPK = self.ownerPK.copy;
	NSString *key = sciSeenKey(ownerPK, senderPk);

	@synchronized (inflight) {
		if ([inflight containsObject:key]) return;
		[inflight addObject:key];
	}

	[SCIInstagramAPI sendRequestWithMethod:@"GET"
									  path:[NSString stringWithFormat:@"users/%@/info/", senderPk]
									  body:nil
								completion:^(NSDictionary *resp, NSError *error) {
		@synchronized (inflight) { [inflight removeObject:key]; }

		NSDictionary *user = [resp[@"user"] isKindOfClass:NSDictionary.class] ? resp[@"user"] : nil;
		if (user.count) [SCIDeletedMessagesStorage applySenderInfo:user forSenderPK:senderPk ownerPK:ownerPK];
	}];
}

#pragma mark - Helpers

- (NSString *)previewTextForMessage:(SCIDeletedMessage *)m {
	if (!m) return @"";
	if (m.kind == SCIDeletedMessageKindReactionRemoved) {
		NSString *e = m.reactionEmoji.length ? m.reactionEmoji : @"♡";
		return m.text.length ? [NSString stringWithFormat:SCILocalized(@"removed %@ on: %@"), e, m.text]
							 : [NSString stringWithFormat:SCILocalized(@"removed reaction %@"), e];
	}
	if (m.kind == SCIDeletedMessageKindText && m.text.length) return m.text;
	if (m.previewText.length) return m.previewText;
	return SCIDeletedMessageKindLocalizedName(m.kind);
}

- (NSString *)previewTextForGroup:(SCIDeletedMessageGroup *)g latest:(SCIDeletedMessage *)latest {
	NSString *body = [self previewTextForMessage:latest];
	if (!g.isGroup) return body;

	NSString *who = latest.senderUsername.length ? latest.senderUsername : latest.senderFullName;
	return who.length ? [NSString stringWithFormat:@"%@: %@", who, body] : body;
}

@end