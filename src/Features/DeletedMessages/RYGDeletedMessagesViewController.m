#import "RYGDeletedMessagesViewController.h"
#import "../Feed/RYGHomeShortcutBadges.h"
#import "RYGDeletedMessagesModels.h"
#import "../../UI/RYGPopupChrome.h"
#import "../../Lock/RYGLockGate.h"
#import "../../Lock/RYGLockGroups.h"
#import <AVFoundation/AVFoundation.h>
#import "RYGDeletedMessagesStorage.h"
#import "RYGDeletedMessagesFilter.h"
#import "RYGDeletedMessagesUserDetailViewController.h"
#import "../../Utils.h"
#import "../../RYGImageCache.h"
#import "../../Networking/RYGInstagramAPI.h"
#import "../../Localization/RYGLocalization.h"
#import "RYGDeletedMessagesStorageViewController.h"
#import "RYGDeletedMessagesDate.h"
#import "RYGDeletedMessagesCapture.h"

#pragma mark - Sender row cell

@interface RYGDMSenderCell : UITableViewCell
@property (nonatomic, strong) UIImageView *avatarView;
@property (nonatomic, strong) UILabel *nameLabel;
@property (nonatomic, strong) UILabel *handleLabel;
@property (nonatomic, strong) UILabel *previewLabel;
@property (nonatomic, strong) UILabel *timeLabel;
@property (nonatomic, strong) UIView *countBadge;
@property (nonatomic, strong) UILabel *countLabel;
@property (nonatomic, strong) NSLayoutConstraint *handleTrailingToTime;
@property (nonatomic, strong) NSLayoutConstraint *handleTrailingToBadge;
@property (nonatomic, copy) NSString *avatarURL;
- (void)applyGroup:(RYGDeletedMessageGroup *)g
			latest:(RYGDeletedMessage *)latest
			 owner:(NSString *)ownerPK
		 preview:(NSString *)preview
			  time:(NSString *)time
			unseen:(NSUInteger)unseen;
@end

@implementation RYGDMSenderCell

- (instancetype)initWithStyle:(UITableViewCellStyle)style reuseIdentifier:(NSString *)rid {
	if ((self = [super initWithStyle:style reuseIdentifier:rid])) {
		self.accessoryType = UITableViewCellAccessoryDisclosureIndicator;
		self.backgroundColor = UIColor.secondarySystemGroupedBackgroundColor;

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
		[_timeLabel setContentCompressionResistancePriority:UILayoutPriorityRequired forAxis:UILayoutConstraintAxisHorizontal];
		[_timeLabel setContentHuggingPriority:UILayoutPriorityRequired forAxis:UILayoutConstraintAxisHorizontal];
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

		_handleTrailingToTime = [_handleLabel.trailingAnchor constraintLessThanOrEqualToAnchor:_timeLabel.leadingAnchor constant:-8];
		_handleTrailingToBadge = [_handleLabel.trailingAnchor constraintLessThanOrEqualToAnchor:_countBadge.leadingAnchor constant:-8];
		_handleTrailingToTime.active = YES;

		[NSLayoutConstraint activateConstraints:@[
			[_avatarView.leadingAnchor constraintEqualToAnchor:self.contentView.leadingAnchor constant:16],
			[_avatarView.centerYAnchor constraintEqualToAnchor:self.contentView.centerYAnchor],
			[_avatarView.widthAnchor constraintEqualToConstant:46],
			[_avatarView.heightAnchor constraintEqualToConstant:46],

			[_nameLabel.leadingAnchor constraintEqualToAnchor:_avatarView.trailingAnchor constant:12],
			[_nameLabel.topAnchor constraintEqualToAnchor:self.contentView.topAnchor constant:10],
			[_nameLabel.trailingAnchor constraintLessThanOrEqualToAnchor:_timeLabel.leadingAnchor constant:-8],

			[_timeLabel.trailingAnchor constraintEqualToAnchor:self.contentView.trailingAnchor constant:-8],
			[_timeLabel.centerYAnchor constraintEqualToAnchor:self.contentView.centerYAnchor],

			[_handleLabel.leadingAnchor constraintEqualToAnchor:_nameLabel.leadingAnchor],
			[_handleLabel.topAnchor constraintEqualToAnchor:_nameLabel.bottomAnchor constant:1],

			[_previewLabel.leadingAnchor constraintEqualToAnchor:_nameLabel.leadingAnchor],
			[_previewLabel.topAnchor constraintEqualToAnchor:_handleLabel.bottomAnchor constant:3],
			[_previewLabel.trailingAnchor constraintLessThanOrEqualToAnchor:_timeLabel.leadingAnchor constant:-8],
			[_previewLabel.bottomAnchor constraintLessThanOrEqualToAnchor:self.contentView.bottomAnchor constant:-10],

			[_countBadge.trailingAnchor constraintEqualToAnchor:_timeLabel.leadingAnchor constant:-6],
			[_countBadge.centerYAnchor constraintEqualToAnchor:_timeLabel.centerYAnchor],
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
	iv.layer.cornerRadius = 23;
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

- (void)applyGroup:(RYGDeletedMessageGroup *)g
			latest:(RYGDeletedMessage *)latest
			 owner:(NSString *)ownerPK
		 preview:(NSString *)preview
			  time:(NSString *)time
			unseen:(NSUInteger)unseen {
	self.previewLabel.text = preview;
	self.timeLabel.text = time;
	self.countLabel.text = [NSString stringWithFormat:@"%lu", (unsigned long)unseen];
	self.countBadge.hidden = unseen == 0;
	self.handleTrailingToTime.active = unseen == 0;
	self.handleTrailingToBadge.active = unseen > 0;
	self.nameLabel.font = [UIFont systemFontOfSize:16 weight:(unseen ? UIFontWeightSemibold : UIFontWeightRegular)];

	if (g.isGroup) {
		self.nameLabel.text = g.threadTitle.length ? g.threadTitle : RYGLocalized(@"Group chat");

		NSMutableArray<NSString *> *handles = [NSMutableArray array];
		for (RYGDeletedMessage *m in g.distinctSenders) {
			NSString *h = m.senderUsername.length ? [@"@" stringByAppendingString:m.senderUsername] : m.senderFullName;
			if (h.length) [handles addObject:h];
			if (handles.count >= 3) break;
		}
		self.handleLabel.text = handles.count ? [handles componentsJoinedByString:@", "] : RYGLocalized(@"Group chat");

		self.avatarView.image = [UIImage systemImageNamed:@"person.2.circle.fill"];
		self.avatarView.tintColor = UIColor.systemGray3Color;
		self.avatarURL = g.threadAvatarURL;
		if (!g.threadAvatarURL.length) return;
		NSURL *gurl = [NSURL URLWithString:g.threadAvatarURL];
		if (!gurl) return;
		__weak typeof(self) wsg = self;
		[RYGImageCache loadImageFromURL:gurl completion:^(UIImage *img) {
			if (!img || ![wsg.avatarURL isEqualToString:g.threadAvatarURL]) return;
			wsg.avatarView.image = img;
		}];
		return;
	}

	self.nameLabel.text = g.senderFullName.length ? g.senderFullName : (g.senderUsername.length ? g.senderUsername : RYGLocalized(@"Unknown user"));
	self.handleLabel.text = g.senderUsername.length ? [@"@" stringByAppendingString:g.senderUsername] : @"";

	self.avatarURL = g.senderProfilePicURL;
	if (!g.senderProfilePicURL.length) return;

	NSURL *url = [NSURL URLWithString:g.senderProfilePicURL];
	if (!url) return;

	__weak typeof(self) ws = self;
	[RYGImageCache loadImageFromURL:url completion:^(UIImage *img) {
		if (!img || ![ws.avatarURL isEqualToString:g.senderProfilePicURL]) return;
		ws.avatarView.image = img;
	}];
}

@end

#pragma mark - Empty state

@interface RYGDMEmptyView : UIView
@property (nonatomic, strong) UIImageView *iconView;
@property (nonatomic, strong) UILabel *titleLabel;
@property (nonatomic, strong) UILabel *messageLabel;
- (void)applyIcon:(NSString *)icon title:(NSString *)title message:(NSString *)message;
@end

@implementation RYGDMEmptyView

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

static NSString *const kRYGDMSeenPrefKey = @"deleted_messages_seen";

static NSString *rygSeenKey(NSString *ownerPk, NSString *senderPk) {
	return [NSString stringWithFormat:@"%@:%@", ownerPk ?: @"", senderPk ?: @""];
}

static NSTimeInterval rygSeenTimestamp(NSString *ownerPk, NSString *senderPk) {
	NSDictionary *all = [NSUserDefaults.standardUserDefaults dictionaryForKey:kRYGDMSeenPrefKey];
	id v = all[rygSeenKey(ownerPk, senderPk)];
	return [v isKindOfClass:NSNumber.class] ? [v doubleValue] : 0;
}

static void rygMarkSenderSeen(NSString *ownerPk, NSString *senderPk) {
	if (!senderPk.length) return;

	NSUserDefaults *d = NSUserDefaults.standardUserDefaults;
	NSMutableDictionary *m = [[d dictionaryForKey:kRYGDMSeenPrefKey] ?: @{} mutableCopy];
	m[rygSeenKey(ownerPk, senderPk)] = @(NSDate.date.timeIntervalSince1970);
	[d setObject:m forKey:kRYGDMSeenPrefKey];
	[d synchronize];
}

static NSUInteger rygUnseenCountForGroup(RYGDeletedMessageGroup *g, NSString *ownerPk) {
	NSTimeInterval seen = rygSeenTimestamp(ownerPk, g.identifier);
	if (seen <= 0) return g.count;

	NSUInteger n = 0;
	for (RYGDeletedMessage *m in g.messages) {
		NSDate *d = m.deletedAt ?: m.capturedAt ?: m.sentAt;
		if (d.timeIntervalSince1970 > seen) n++;
	}
	return n;
}

#pragma mark - Ignored chats management

@interface RYGDMIgnoredViewController : UIViewController <UITableViewDataSource, UITableViewDelegate>
@property (nonatomic, copy) NSString *ownerPK;
@property (nonatomic, strong) UITableView *tableView;
@property (nonatomic, strong) NSArray<NSString *> *ids;                              // raw exclude identifiers
@property (nonatomic, strong) NSDictionary<NSString *, NSDictionary *> *meta;        // id -> {title, subtitle}
@end

@implementation RYGDMIgnoredViewController
- (void)viewDidLoad {
	[super viewDidLoad];
	self.title = RYGLocalized(@"Ignored");
	self.view.backgroundColor = [RYGPopupChrome backgroundColor];
	self.tableView = [[UITableView alloc] initWithFrame:self.view.bounds style:UITableViewStyleInsetGrouped];
	self.tableView.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
	self.tableView.backgroundColor = UIColor.clearColor;
	self.tableView.dataSource = self;
	self.tableView.delegate = self;
	[self.view addSubview:self.tableView];
	self.navigationItem.rightBarButtonItem = [[UIBarButtonItem alloc] initWithTitle:RYGLocalized(@"Clear all")
																			 style:UIBarButtonItemStylePlain
																			target:self
																			action:@selector(clearAll)];
	[self reload];
	[NSNotificationCenter.defaultCenter addObserver:self selector:@selector(reload) name:RYGDeletedMessagesDidChangeNotification object:nil];
}
- (void)dealloc { [NSNotificationCenter.defaultCenter removeObserver:self]; }

- (void)reload {
	self.ids = [RYGDeletedMessagesStorage excludedIdentifiersForOwnerPK:self.ownerPK];

	NSMutableDictionary *m = [NSMutableDictionary dictionary];
	for (RYGDeletedMessageGroup *g in [RYGDeletedMessagesStorage groupedByThreadForOwnerPK:self.ownerPK]) {
		NSString *title = g.isGroup ? (g.threadTitle.length ? g.threadTitle : RYGLocalized(@"Group chat"))
									: (g.senderUsername.length ? [@"@" stringByAppendingString:g.senderUsername]
															   : (g.senderFullName.length ? g.senderFullName : g.senderPk));
		m[g.identifier] = @{ @"title": title ?: @"", @"subtitle": g.isGroup ? RYGLocalized(@"Chat") : RYGLocalized(@"Person") };
	}
	self.meta = m;
	self.navigationItem.rightBarButtonItem.enabled = self.ids.count > 0;
	[self.tableView reloadData];
}

- (void)clearAll {
	for (NSString *id_ in self.ids.copy) [RYGDeletedMessagesStorage setExcludedIdentifier:id_ excluded:NO ownerPK:self.ownerPK];
}

- (NSInteger)tableView:(UITableView *)t numberOfRowsInSection:(NSInteger)s { return self.ids.count; }

- (NSString *)tableView:(UITableView *)t titleForFooterInSection:(NSInteger)s {
	return self.ids.count ? RYGLocalized(@"Swipe to remove. Removing resumes logging for that person or chat.")
						  : RYGLocalized(@"Nothing is ignored. Long-press someone in the log to stop logging them.");
}

- (UITableViewCell *)tableView:(UITableView *)t cellForRowAtIndexPath:(NSIndexPath *)ip {
	UITableViewCell *c = [t dequeueReusableCellWithIdentifier:@"i"] ?: [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleSubtitle reuseIdentifier:@"i"];
	c.backgroundColor = UIColor.secondarySystemGroupedBackgroundColor;
	c.selectionStyle = UITableViewCellSelectionStyleNone;
	NSString *id_ = self.ids[ip.row];
	NSDictionary *info = self.meta[id_];
	BOOL isPerson = [id_ hasPrefix:@"s:"];
	c.textLabel.text = [info[@"title"] length] ? info[@"title"] : (isPerson ? [id_ substringFromIndex:2] : id_);
	c.detailTextLabel.text = info[@"subtitle"] ?: (isPerson ? RYGLocalized(@"Person") : RYGLocalized(@"Chat"));
	c.detailTextLabel.textColor = UIColor.secondaryLabelColor;
	c.imageView.image = [UIImage systemImageNamed:@"nosign"];
	c.imageView.tintColor = UIColor.systemGray2Color;
	return c;
}

- (UISwipeActionsConfiguration *)tableView:(UITableView *)t trailingSwipeActionsConfigurationForRowAtIndexPath:(NSIndexPath *)ip {
	NSString *id_ = self.ids[ip.row];
	NSString *owner = self.ownerPK;
	UIContextualAction *rm = [UIContextualAction contextualActionWithStyle:UIContextualActionStyleDestructive
																	title:RYGLocalized(@"Remove")
																  handler:^(UIContextualAction *a, UIView *v, void (^done)(BOOL)) {
		[RYGDeletedMessagesStorage setExcludedIdentifier:id_ excluded:NO ownerPK:owner];
		done(YES);
	}];
	return [UISwipeActionsConfiguration configurationWithActions:@[rm]];
}
@end

#pragma mark - VC

@interface RYGDeletedMessagesViewController () <UITableViewDataSource, UITableViewDelegate, UISearchResultsUpdating>
@property (nonatomic, strong) UITableView *tableView;
@property (nonatomic, strong) RYGDMEmptyView *emptyView;
@property (nonatomic, strong) UISearchController *searchCtl;
@property (nonatomic, strong) UILabel *footerLabel;
@property (nonatomic, strong) NSArray<RYGDeletedMessageGroup *> *allGroups;
@property (nonatomic, strong) NSArray<RYGDeletedMessageGroup *> *visibleGroups;
@property (nonatomic, strong) NSMutableSet<NSString *> *resolvedThreadIds;
@property (nonatomic, strong) RYGDeletedMessagesFilter *filter;
@property (nonatomic, copy) NSString *ownerPK;
@end

@implementation RYGDeletedMessagesViewController

+ (void)load {
	for (NSString *action in @[RYG_NOTIF_UNSENT_MESSAGE, RYG_NOTIF_REACTION_REMOVED]) {
		[RYGNotificationCenter.shared setDefaultTapProvider:^void (^(void))(void) {
			return ^{ [RYGDeletedMessagesViewController presentFromViewController:nil]; };
		} ownerVCClass:[RYGDeletedMessagesViewController class]
		  forAction:action];
	}
}

+ (void)presentFromViewController:(UIViewController *)presenter {
	[RYGLockGate presentLockedVC:[RYGDeletedMessagesViewController new]
						forGroup:RYGLockGroupKeepDeleted
							from:presenter];
}

- (instancetype)init {
	if ((self = [super init])) {
		_filter = [RYGDeletedMessagesFilter new];
		_allGroups = @[];
		_visibleGroups = @[];
	}
	return self;
}

- (void)viewDidLoad {
	[super viewDidLoad];

	[RYGHomeShortcutBadges clearActionID:@"deleted_messages"];
	self.title = RYGLocalized(@"Deleted messages");
	self.view.backgroundColor = [RYGPopupChrome backgroundColor];

	[self installNavigationItems];
	[self installSearchController];
	[self installTable];
	[self installEmptyView];

	[NSNotificationCenter.defaultCenter addObserver:self
										   selector:@selector(storeChanged:)
											   name:RYGDeletedMessagesDidChangeNotification
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
	sc.searchBar.placeholder = RYGLocalized(@"Search senders or messages");
	sc.searchBar.autocapitalizationType = UITextAutocapitalizationTypeNone;

	self.searchCtl = sc;
	self.navigationItem.searchController = sc;
	// Collapsing search bar + UIRefreshControl recurse into a stack overflow on pull-to-refresh.
	self.navigationItem.hidesSearchBarWhenScrolling = NO;

	// iOS 26 defaults search to the bottom edge — force stacked under the title.
	if (@available(iOS 26.0, *)) {
		@try {
			[self.navigationItem setValue:@2 forKey:@"preferredSearchBarPlacement"];
		} @catch (NSException *exception) {
			(void)exception;
		}
	}

	self.definesPresentationContext = YES;
}

- (void)installTable {
	self.tableView = [[UITableView alloc] initWithFrame:CGRectZero style:UITableViewStyleInsetGrouped];
	self.tableView.translatesAutoresizingMaskIntoConstraints = NO;
	self.tableView.dataSource = self;
	self.tableView.delegate = self;
	self.tableView.rowHeight = 76;
	self.tableView.backgroundColor = UIColor.clearColor;
	self.tableView.sectionHeaderTopPadding = 0;
	[self.tableView registerClass:RYGDMSenderCell.class forCellReuseIdentifier:@"sender"];

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
	self.emptyView = [RYGDMEmptyView new];
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

	UIMenu *dateMenu = [self menuWithTitle:RYGLocalized(@"Date range")
									  icon:@"calendar"
								   entries:@[
		@[RYGLocalized(@"All time"), @(RYGDMDateRangeAll), @"infinity"],
		@[RYGLocalized(@"Today"), @(RYGDMDateRangeToday), @"sun.max"],
		@[RYGLocalized(@"Last 7 days"), @(RYGDMDateRangeWeek), @"calendar"],
		@[RYGLocalized(@"Last 30 days"), @(RYGDMDateRangeMonth), @"calendar.badge.clock"],
	] handler:^(NSInteger value) {
		ws.filter.dateRange = (RYGDMDateRange)value;
	} current:self.filter.dateRange];

	UIMenu *sortMenu = [self menuWithTitle:RYGLocalized(@"Sort")
									  icon:@"arrow.up.arrow.down"
								   entries:@[
		@[RYGLocalized(@"Most recent"), @(RYGDMSortRecent), @"clock.arrow.circlepath"],
		@[RYGLocalized(@"Oldest first"), @(RYGDMSortOldest), @"arrow.up.to.line"],
		@[RYGLocalized(@"Most messages"), @(RYGDMSortCountDesc), @"number"],
	] handler:^(NSInteger value) {
		ws.filter.sort = (RYGDMSort)value;
	} current:self.filter.sort];

	NSString *fmt = [RYGUtils getStringPref:@"dm_log_date_format"] ?: @"relative";
	UIAction *(^fmtAction)(NSString *, NSString *) = ^UIAction *(NSString *title, NSString *value) {
		UIAction *a = [UIAction actionWithTitle:title image:nil identifier:nil handler:^(__unused UIAction *_) {
			[RYGUtils setPref:value forKey:@"dm_log_date_format"];
			[ws refilter];
			[ws refreshNavMenu];
		}];
		a.state = [fmt isEqualToString:value] ? UIMenuElementStateOn : UIMenuElementStateOff;
		return a;
	};

	UIMenu *formatMenu = [UIMenu menuWithTitle:RYGLocalized(@"Date format")
										 image:[UIImage systemImageNamed:@"clock"]
									identifier:nil
									   options:0
									  children:@[
		fmtAction(RYGLocalized(@"Relative (1m / 3h / 3d ago)"), @"relative"),
		fmtAction(RYGLocalized(@"Absolute date + time"), @"absolute"),
	]];

	UIAction *refresh = [UIAction actionWithTitle:RYGLocalized(@"Refresh names & photos")
											image:[UIImage systemImageNamed:@"arrow.clockwise"]
									   identifier:nil
										  handler:^(__unused UIAction *_) {
		[ws refreshAllMetadata];
	}];
	if (!self.allGroups.count) refresh.attributes = UIMenuElementAttributesDisabled;

	UIAction *storage = [UIAction actionWithTitle:RYGLocalized(@"Storage")
											image:[UIImage systemImageNamed:@"externaldrive"]
									   identifier:nil
										  handler:^(__unused UIAction *_) {
		[ws storageTapped];
	}];

	UIAction *ignored = [UIAction actionWithTitle:RYGLocalized(@"Ignored people & chats")
											image:[UIImage systemImageNamed:@"nosign"]
									   identifier:nil
										  handler:^(__unused UIAction *_) {
		[ws openIgnoredList];
	}];

	UIAction *clear = [UIAction actionWithTitle:RYGLocalized(@"Clear log")
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
		[UIMenu menuWithTitle:@"" image:nil identifier:nil options:UIMenuOptionsDisplayInline children:@[refresh, storage, ignored, clear]]
	]];
}

- (void)openIgnoredList {
	RYGDMIgnoredViewController *vc = [RYGDMIgnoredViewController new];
	vc.ownerPK = self.ownerPK;
	[self.navigationController pushViewController:vc animated:YES];
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
	self.ownerPK = [RYGUtils currentUserPK];

	NSArray<RYGDeletedMessageGroup *> *groups = [RYGDeletedMessagesStorage groupedByThreadForOwnerPK:self.ownerPK];
	NSArray<NSString *> *excluded = [RYGDeletedMessagesStorage excludedIdentifiersForOwnerPK:self.ownerPK];
	if (excluded.count) {
		NSSet<NSString *> *ex = [NSSet setWithArray:excluded];
		NSMutableArray *kept = [NSMutableArray arrayWithCapacity:groups.count];
		for (RYGDeletedMessageGroup *g in groups) if (![ex containsObject:g.identifier]) [kept addObject:g];
		groups = kept;
	}
	self.allGroups = groups;

	[self resolveThreadsNeedingInfo];
	[self refilter];
	[self refreshNavMenu];
}

// Resolve group flag/title + avatars for any thread still missing them (legacy / switched-in account).
- (void)resolveThreadsNeedingInfo {
	if (!self.resolvedThreadIds) self.resolvedThreadIds = [NSMutableSet set];

	for (RYGDeletedMessageGroup *g in self.allGroups) {
		if (!g.threadId.length || [self.resolvedThreadIds containsObject:g.threadId]) continue;

		BOOL needs = !g.threadTitle.length;
		if (!needs && g.isGroup) {
			for (RYGDeletedMessage *m in g.distinctSenders) {
				if (!m.senderProfilePicURL.length) { needs = YES; break; }
			}
		}
		if (!needs) continue;

		// Once per thread per session — don't re-fire for members who have no avatar.
		[self.resolvedThreadIds addObject:g.threadId];
		rygDMResolveThreadInfo(g.threadId, self.ownerPK);
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
		BOOL enabled = [RYGUtils getBoolPref:@"deleted_messages_log_enabled"];
		[self.emptyView applyIcon:(enabled ? @"tray" : @"tray.full")
							 title:(enabled ? RYGLocalized(@"No deleted messages yet") : RYGLocalized(@"Logging is off"))
						   message:(enabled
									? RYGLocalized(@"When someone unsends a message, it will appear here grouped by chat.")
									: RYGLocalized(@"Enable Settings → Messages → Deleted messages log to start recording."))];
	} else {
		[self.emptyView applyIcon:@"line.3.horizontal.decrease.circle"
							 title:RYGLocalized(@"No matches")
						   message:RYGLocalized(@"Adjust the filters or clear the search to see more.")];
	}
}

- (void)refreshFooter {
	NSUInteger total = 0;
	for (RYGDeletedMessageGroup *g in self.allGroups) total += g.count;

	if (!total) {
		self.footerLabel.text = @"";
		self.tableView.tableFooterView = self.footerLabel;
		return;
	}

	self.footerLabel.text = [NSString stringWithFormat:RYGLocalized(@"%lu messages in %lu chats"),
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
	[self.navigationController pushViewController:[RYGDeletedMessagesStorageViewController new] animated:YES];
}

- (void)refreshAllMetadata {
	[self.resolvedThreadIds removeAllObjects];
	NSString *owner = self.ownerPK;
	NSMutableSet<NSString *> *threads = [NSMutableSet set];
	NSMutableSet<NSString *> *legacySenders = [NSMutableSet set];

	for (RYGDeletedMessageGroup *g in self.allGroups) {
		if (g.threadId.length) [threads addObject:g.threadId];
		else if (g.senderPk.length) [legacySenders addObject:g.senderPk];
	}

	for (NSString *tid in threads) rygDMRefreshThreadInfo(tid, owner);

	// Legacy threadless records: refresh the sender via the user-info endpoint.
	for (NSString *pk in legacySenders) {
		[RYGInstagramAPI sendRequestWithMethod:@"GET"
										  path:[NSString stringWithFormat:@"users/%@/info/", pk]
										  body:nil
									completion:^(NSDictionary *resp, NSError *error) {
			NSDictionary *user = [resp[@"user"] isKindOfClass:NSDictionary.class] ? resp[@"user"] : nil;
			if (user.count) [RYGDeletedMessagesStorage applySenderInfo:user forSenderPK:pk ownerPK:owner overwrite:YES];
		}];
	}

	RYGNotifyInfo(RYG_NOTIF_GENERIC, RYGLocalized(@"Refreshing names & photos"), nil);
}

- (void)clearAllTapped {
	if (!self.allGroups.count) return;

	UIAlertController *a = [UIAlertController alertControllerWithTitle:RYGLocalized(@"Clear deleted-message log?")
															  message:RYGLocalized(@"Removes every preserved deleted message and its captured media for this account.")
													   preferredStyle:UIAlertControllerStyleAlert];

	[a addAction:[UIAlertAction actionWithTitle:RYGLocalized(@"Cancel") style:UIAlertActionStyleCancel handler:nil]];
	[a addAction:[UIAlertAction actionWithTitle:RYGLocalized(@"Clear") style:UIAlertActionStyleDestructive handler:^(__unused UIAlertAction *_) {
		[RYGDeletedMessagesStorage resetForOwnerPK:self.ownerPK];
	}]];

	[self presentViewController:a animated:YES completion:nil];
}

#pragma mark - Table

- (NSInteger)tableView:(UITableView *)tv numberOfRowsInSection:(NSInteger)section {
	return (NSInteger)self.visibleGroups.count;
}

// Kill the default grouped-style gap above the first card.
- (CGFloat)tableView:(UITableView *)tv heightForHeaderInSection:(NSInteger)section { return 10; }
- (UIView *)tableView:(UITableView *)tv viewForHeaderInSection:(NSInteger)section { return nil; }

- (RYGDeletedMessageGroup *)groupAtIndexPath:(NSIndexPath *)ip {
	return ip.row < (NSInteger)self.visibleGroups.count ? self.visibleGroups[ip.row] : nil;
}

- (UITableViewCell *)tableView:(UITableView *)tv cellForRowAtIndexPath:(NSIndexPath *)ip {
	RYGDMSenderCell *cell = [tv dequeueReusableCellWithIdentifier:@"sender" forIndexPath:ip];
	RYGDeletedMessageGroup *g = [self groupAtIndexPath:ip];
	RYGDeletedMessage *latest = g.latest;

	[cell applyGroup:g
			  latest:latest
			   owner:self.ownerPK
			 preview:[self previewTextForGroup:g latest:latest]
				time:[RYGDeletedMessagesDate stringForDate:g.lastDeletedAt]
			  unseen:rygUnseenCountForGroup(g, self.ownerPK)];

	if (!g.isGroup && !g.senderProfilePicURL.length) [self backfillSenderIfNeeded:g];
	return cell;
}

- (void)tableView:(UITableView *)tv didSelectRowAtIndexPath:(NSIndexPath *)ip {
	[tv deselectRowAtIndexPath:ip animated:YES];

	RYGDeletedMessageGroup *g = [self groupAtIndexPath:ip];
	if (!g) return;

	rygMarkSenderSeen(self.ownerPK, g.identifier);
	[tv reloadRowsAtIndexPaths:@[ip] withRowAnimation:UITableViewRowAnimationNone];

	RYGDeletedMessagesUserDetailViewController *vc = [[RYGDeletedMessagesUserDetailViewController alloc] initWithGroup:g ownerPK:self.ownerPK];
	[self.navigationController pushViewController:vc animated:YES];
}

- (UISwipeActionsConfiguration *)tableView:(UITableView *)tv trailingSwipeActionsConfigurationForRowAtIndexPath:(NSIndexPath *)ip {
	RYGDeletedMessageGroup *g = [self groupAtIndexPath:ip];
	if (!g) return nil;

	__weak typeof(self) ws = self;
	UIContextualAction *del = [UIContextualAction contextualActionWithStyle:UIContextualActionStyleDestructive
																	  title:RYGLocalized(@"Clear")
																	handler:^(__unused UIContextualAction *a, __unused UIView *src, void (^done)(BOOL)) {
		if (g.threadId.length) [RYGDeletedMessagesStorage deleteMessagesForThreadId:g.threadId ownerPK:ws.ownerPK];
		else [RYGDeletedMessagesStorage deleteMessagesForSenderPK:g.senderPk ownerPK:ws.ownerPK threadlessOnly:YES];
		done(YES);
	}];
	del.image = [UIImage systemImageNamed:@"trash"];
	return [UISwipeActionsConfiguration configurationWithActions:@[del]];
}

- (UIContextMenuConfiguration *)tableView:(UITableView *)tv contextMenuConfigurationForRowAtIndexPath:(NSIndexPath *)ip point:(CGPoint)point {
	RYGDeletedMessageGroup *g = [self groupAtIndexPath:ip];
	if (!g.identifier.length) return nil;

	__weak typeof(self) ws = self;
	NSString *who = g.isGroup ? (g.threadTitle.length ? g.threadTitle : RYGLocalized(@"Group chat"))
							  : (g.senderUsername.length ? [@"@" stringByAppendingString:g.senderUsername] : RYGLocalized(@"Someone"));
	NSString *identifier = g.identifier;

	return [UIContextMenuConfiguration configurationWithIdentifier:nil previewProvider:nil actionProvider:^UIMenu *(NSArray<UIMenuElement *> *suggested) {
		UIAction *stop = [UIAction actionWithTitle:[NSString stringWithFormat:RYGLocalized(@"Stop logging %@"), who]
											 image:[UIImage systemImageNamed:@"nosign"]
										identifier:nil
										   handler:^(__unused UIAction *_) {
			[RYGDeletedMessagesStorage setExcludedIdentifier:identifier excluded:YES ownerPK:ws.ownerPK];
		}];
		stop.attributes = UIMenuElementAttributesDestructive;

		UIAction *ignored = [UIAction actionWithTitle:RYGLocalized(@"Ignored people & chats")
												image:[UIImage systemImageNamed:@"nosign"]
										   identifier:nil
											  handler:^(__unused UIAction *_) {
			[ws openIgnoredList];
		}];

		return [UIMenu menuWithTitle:@"" children:@[stop, ignored]];
	}];
}

#pragma mark - Backfill

- (void)backfillSenderIfNeeded:(RYGDeletedMessageGroup *)g {
	if (!g.senderPk.length) return;

	static NSMutableSet<NSString *> *inflight;
	static dispatch_once_t once;
	dispatch_once(&once, ^{ inflight = [NSMutableSet set]; });

	NSString *senderPk = g.senderPk.copy;
	NSString *ownerPK = self.ownerPK.copy;
	NSString *key = rygSeenKey(ownerPK, senderPk);

	@synchronized (inflight) {
		if ([inflight containsObject:key]) return;
		[inflight addObject:key];
	}

	[RYGInstagramAPI sendRequestWithMethod:@"GET"
									  path:[NSString stringWithFormat:@"users/%@/info/", senderPk]
									  body:nil
								completion:^(NSDictionary *resp, NSError *error) {
		@synchronized (inflight) { [inflight removeObject:key]; }

		NSDictionary *user = [resp[@"user"] isKindOfClass:NSDictionary.class] ? resp[@"user"] : nil;
		if (user.count) [RYGDeletedMessagesStorage applySenderInfo:user forSenderPK:senderPk ownerPK:ownerPK];
	}];
}

#pragma mark - Helpers

- (NSString *)previewTextForMessage:(RYGDeletedMessage *)m {
	if (!m) return @"";
	if (m.kind == RYGDeletedMessageKindReactionRemoved) {
		NSString *e = m.reactionEmoji.length ? m.reactionEmoji : @"♡";
		return m.text.length ? [NSString stringWithFormat:RYGLocalized(@"removed %@ on: %@"), e, m.text]
							 : [NSString stringWithFormat:RYGLocalized(@"removed reaction %@"), e];
	}
	if (m.kind == RYGDeletedMessageKindText && m.text.length) return m.text;
	if (m.previewText.length) return m.previewText;
	return RYGDeletedMessageKindLocalizedName(m.kind);
}

- (NSString *)previewTextForGroup:(RYGDeletedMessageGroup *)g latest:(RYGDeletedMessage *)latest {
	NSString *body = [self previewTextForMessage:latest];
	if (!g.isGroup) return body;

	NSString *who = latest.senderUsername.length ? latest.senderUsername : latest.senderFullName;
	return who.length ? [NSString stringWithFormat:@"%@: %@", who, body] : body;
}

@end