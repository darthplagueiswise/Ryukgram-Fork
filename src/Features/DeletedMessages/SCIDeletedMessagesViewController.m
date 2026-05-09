#import "SCIDeletedMessagesViewController.h"
#import "SCIDeletedMessagesModels.h"
#import "../../UI/SCIPopupChrome.h"
#import <AVFoundation/AVFoundation.h>
#import "SCIDeletedMessagesStorage.h"
#import "SCIDeletedMessagesFilter.h"
#import "SCIDeletedMessagesChipBar.h"
#import "SCIDeletedMessagesUserDetailViewController.h"
#import "../../Utils.h"
#import "../../SCIImageCache.h"
#import "../../Networking/SCIInstagramAPI.h"
#import "../../Localization/SCILocalization.h"
#import "SCIDeletedMessagesStorageViewController.h"
#import "SCIDeletedMessagesDate.h"

#pragma mark - Sender row cell

@interface SCIDMSenderCell : UITableViewCell
@property (nonatomic, strong) UIImageView *avatarView;
@property (nonatomic, strong) UILabel *nameLabel;
@property (nonatomic, strong) UILabel *handleLabel;
@property (nonatomic, strong) UILabel *previewLabel;
@property (nonatomic, strong) UILabel *timeLabel;
@property (nonatomic, strong) UIView  *countBadge;
@property (nonatomic, strong) UILabel *countLabel;
@end

@implementation SCIDMSenderCell

- (instancetype)initWithStyle:(UITableViewCellStyle)style reuseIdentifier:(NSString *)rid {
    if ((self = [super initWithStyle:style reuseIdentifier:rid])) {
        self.accessoryType = UITableViewCellAccessoryDisclosureIndicator;

        _avatarView = [UIImageView new];
        _avatarView.translatesAutoresizingMaskIntoConstraints = NO;
        _avatarView.contentMode = UIViewContentModeScaleAspectFill;
        _avatarView.backgroundColor = [UIColor secondarySystemBackgroundColor];
        _avatarView.layer.cornerRadius = 26;
        _avatarView.layer.masksToBounds = YES;
        _avatarView.image = [UIImage systemImageNamed:@"person.circle.fill"];
        _avatarView.tintColor = [UIColor systemGray3Color];
        [self.contentView addSubview:_avatarView];

        _nameLabel = [UILabel new];
        _nameLabel.translatesAutoresizingMaskIntoConstraints = NO;
        _nameLabel.font = [UIFont systemFontOfSize:16 weight:UIFontWeightSemibold];
        [self.contentView addSubview:_nameLabel];

        _handleLabel = [UILabel new];
        _handleLabel.translatesAutoresizingMaskIntoConstraints = NO;
        _handleLabel.font = [UIFont systemFontOfSize:13];
        _handleLabel.textColor = [UIColor secondaryLabelColor];
        [self.contentView addSubview:_handleLabel];

        _previewLabel = [UILabel new];
        _previewLabel.translatesAutoresizingMaskIntoConstraints = NO;
        _previewLabel.font = [UIFont systemFontOfSize:13];
        _previewLabel.textColor = [UIColor tertiaryLabelColor];
        _previewLabel.numberOfLines = 1;
        [self.contentView addSubview:_previewLabel];

        _timeLabel = [UILabel new];
        _timeLabel.translatesAutoresizingMaskIntoConstraints = NO;
        _timeLabel.font = [UIFont systemFontOfSize:12];
        _timeLabel.textColor = [UIColor tertiaryLabelColor];
        _timeLabel.textAlignment = NSTextAlignmentRight;
        [self.contentView addSubview:_timeLabel];

        _countBadge = [UIView new];
        _countBadge.translatesAutoresizingMaskIntoConstraints = NO;
        _countBadge.layer.cornerRadius = 10;
        _countBadge.layer.masksToBounds = YES;
        _countBadge.backgroundColor = [UIColor systemRedColor];
        [self.contentView addSubview:_countBadge];

        _countLabel = [UILabel new];
        _countLabel.translatesAutoresizingMaskIntoConstraints = NO;
        _countLabel.font = [UIFont systemFontOfSize:11 weight:UIFontWeightSemibold];
        _countLabel.textColor = [UIColor whiteColor];
        _countLabel.textAlignment = NSTextAlignmentCenter;
        [_countBadge addSubview:_countLabel];

        UILayoutGuide *m = self.contentView.layoutMarginsGuide;
        [NSLayoutConstraint activateConstraints:@[
            [_avatarView.leadingAnchor constraintEqualToAnchor:m.leadingAnchor],
            [_avatarView.centerYAnchor constraintEqualToAnchor:self.contentView.centerYAnchor],
            [_avatarView.widthAnchor   constraintEqualToConstant:52],
            [_avatarView.heightAnchor  constraintEqualToConstant:52],

            [_nameLabel.leadingAnchor constraintEqualToAnchor:_avatarView.trailingAnchor constant:12],
            [_nameLabel.topAnchor     constraintEqualToAnchor:self.contentView.topAnchor constant:10],
            [_nameLabel.trailingAnchor constraintLessThanOrEqualToAnchor:_timeLabel.leadingAnchor constant:-8],

            [_timeLabel.trailingAnchor constraintEqualToAnchor:m.trailingAnchor],
            [_timeLabel.firstBaselineAnchor constraintEqualToAnchor:_nameLabel.firstBaselineAnchor],

            [_handleLabel.leadingAnchor constraintEqualToAnchor:_nameLabel.leadingAnchor],
            [_handleLabel.topAnchor     constraintEqualToAnchor:_nameLabel.bottomAnchor constant:1],
            [_handleLabel.trailingAnchor constraintLessThanOrEqualToAnchor:_countBadge.leadingAnchor constant:-8],

            [_previewLabel.leadingAnchor constraintEqualToAnchor:_nameLabel.leadingAnchor],
            [_previewLabel.topAnchor     constraintEqualToAnchor:_handleLabel.bottomAnchor constant:3],
            [_previewLabel.trailingAnchor constraintEqualToAnchor:m.trailingAnchor],
            [_previewLabel.bottomAnchor  constraintLessThanOrEqualToAnchor:self.contentView.bottomAnchor constant:-10],

            [_countBadge.trailingAnchor constraintEqualToAnchor:m.trailingAnchor],
            [_countBadge.topAnchor      constraintEqualToAnchor:_timeLabel.bottomAnchor constant:4],
            [_countBadge.heightAnchor   constraintEqualToConstant:20],
            [_countBadge.widthAnchor    constraintGreaterThanOrEqualToConstant:24],

            [_countLabel.topAnchor      constraintEqualToAnchor:_countBadge.topAnchor],
            [_countLabel.bottomAnchor   constraintEqualToAnchor:_countBadge.bottomAnchor],
            [_countLabel.leadingAnchor  constraintEqualToAnchor:_countBadge.leadingAnchor constant:6],
            [_countLabel.trailingAnchor constraintEqualToAnchor:_countBadge.trailingAnchor constant:-6],
        ]];
    }
    return self;
}

- (void)prepareForReuse {
    [super prepareForReuse];
    self.avatarView.image = [UIImage systemImageNamed:@"person.circle.fill"];
    self.avatarView.tintColor = [UIColor systemGray3Color];
}

@end

#pragma mark - Empty state

@interface SCIDMEmptyView : UIView
@property (nonatomic, strong) UIImageView *iconView;
@property (nonatomic, strong) UILabel *titleLabel;
@property (nonatomic, strong) UILabel *messageLabel;
@end

@implementation SCIDMEmptyView
- (instancetype)initWithFrame:(CGRect)frame {
    if ((self = [super initWithFrame:frame])) {
        _iconView = [UIImageView new];
        _iconView.translatesAutoresizingMaskIntoConstraints = NO;
        _iconView.contentMode = UIViewContentModeScaleAspectFit;
        _iconView.tintColor = [UIColor tertiaryLabelColor];
        _iconView.preferredSymbolConfiguration =
            [UIImageSymbolConfiguration configurationWithPointSize:46 weight:UIImageSymbolWeightLight];
        _iconView.image = [UIImage systemImageNamed:@"tray"];
        [self addSubview:_iconView];

        _titleLabel = [UILabel new];
        _titleLabel.translatesAutoresizingMaskIntoConstraints = NO;
        _titleLabel.font = [UIFont systemFontOfSize:17 weight:UIFontWeightSemibold];
        _titleLabel.textColor = [UIColor secondaryLabelColor];
        _titleLabel.textAlignment = NSTextAlignmentCenter;
        [self addSubview:_titleLabel];

        _messageLabel = [UILabel new];
        _messageLabel.translatesAutoresizingMaskIntoConstraints = NO;
        _messageLabel.font = [UIFont systemFontOfSize:14];
        _messageLabel.textColor = [UIColor tertiaryLabelColor];
        _messageLabel.numberOfLines = 0;
        _messageLabel.textAlignment = NSTextAlignmentCenter;
        [self addSubview:_messageLabel];

        [NSLayoutConstraint activateConstraints:@[
            [_iconView.centerXAnchor constraintEqualToAnchor:self.centerXAnchor],
            [_iconView.centerYAnchor constraintEqualToAnchor:self.centerYAnchor constant:-30],
            [_iconView.widthAnchor   constraintEqualToConstant:64],
            [_iconView.heightAnchor  constraintEqualToConstant:64],

            [_titleLabel.topAnchor      constraintEqualToAnchor:_iconView.bottomAnchor constant:14],
            [_titleLabel.leadingAnchor  constraintEqualToAnchor:self.leadingAnchor constant:32],
            [_titleLabel.trailingAnchor constraintEqualToAnchor:self.trailingAnchor constant:-32],

            [_messageLabel.topAnchor      constraintEqualToAnchor:_titleLabel.bottomAnchor constant:6],
            [_messageLabel.leadingAnchor  constraintEqualToAnchor:self.leadingAnchor constant:32],
            [_messageLabel.trailingAnchor constraintEqualToAnchor:self.trailingAnchor constant:-32],
        ]];
    }
    return self;
}
@end

#pragma mark - VC

@interface SCIDeletedMessagesViewController () <UITableViewDataSource, UITableViewDelegate, UISearchResultsUpdating>
@property (nonatomic, strong) UITableView *tableView;
@property (nonatomic, strong) SCIDMEmptyView *emptyView;
@property (nonatomic, strong) UISearchController *searchCtl;
@property (nonatomic, strong) UILabel *footerLabel;

@property (nonatomic, strong) NSArray<SCIDeletedMessageGroup *> *allGroups;
@property (nonatomic, strong) NSArray<SCIDeletedMessageGroup *> *visibleGroups;
@property (nonatomic, strong) SCIDeletedMessagesFilter *filter;

@property (nonatomic, copy) NSString *ownerPK;
@end

#pragma mark - Seen tracking

// senderPk → unix timestamp of the last "viewed detail" event, per account.
static NSString *const kSCIDMSeenPrefKey = @"deleted_messages_seen";

static NSString *sciSeenKey(NSString *ownerPk, NSString *senderPk) {
    return [NSString stringWithFormat:@"%@:%@", ownerPk ?: @"", senderPk ?: @""];
}

static NSTimeInterval sciSeenTimestamp(NSString *ownerPk, NSString *senderPk) {
    NSDictionary *all = [[NSUserDefaults standardUserDefaults] dictionaryForKey:kSCIDMSeenPrefKey];
    id v = all[sciSeenKey(ownerPk, senderPk)];
    return [v isKindOfClass:[NSNumber class]] ? [(NSNumber *)v doubleValue] : 0;
}

static void sciMarkSenderSeen(NSString *ownerPk, NSString *senderPk) {
    if (!senderPk.length) return;
    NSMutableDictionary *m = [([[NSUserDefaults standardUserDefaults] dictionaryForKey:kSCIDMSeenPrefKey] ?: @{}) mutableCopy];
    m[sciSeenKey(ownerPk, senderPk)] = @([[NSDate date] timeIntervalSince1970]);
    [[NSUserDefaults standardUserDefaults] setObject:m forKey:kSCIDMSeenPrefKey];
}

static NSUInteger sciUnseenCountForGroup(SCIDeletedMessageGroup *g, NSString *ownerPk) {
    NSTimeInterval seen = sciSeenTimestamp(ownerPk, g.senderPk);
    if (seen <= 0) return g.count;
    NSUInteger n = 0;
    for (SCIDeletedMessage *m in g.messages) {
        NSDate *d = m.deletedAt ?: m.capturedAt ?: m.sentAt;
        if (!d) continue;
        if (d.timeIntervalSince1970 > seen) n++;
    }
    return n;
}

@implementation SCIDeletedMessagesViewController

+ (void)presentFromViewController:(UIViewController *)presenter {
    [SCIPopupChrome presentVC:[SCIDeletedMessagesViewController new] from:presenter];
}

- (instancetype)init {
    if ((self = [super init])) {
        _filter = [SCIDeletedMessagesFilter new];
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

    [[NSNotificationCenter defaultCenter] addObserver:self
                                             selector:@selector(storeChanged:)
                                                 name:SCIDeletedMessagesDidChangeNotification
                                               object:nil];
}

- (void)dealloc {
    [[NSNotificationCenter defaultCenter] removeObserver:self];
}

- (void)viewWillAppear:(BOOL)animated {
    [super viewWillAppear:animated];
    [self reload];
}

- (void)viewDidAppear:(BOOL)animated {
    [super viewDidAppear:animated];
    // Page sheet keeps reels/story/voice playing behind the card.
    // notify-others deactivation triggers IG's session-interruption pause.
    @try {
        [[AVAudioSession sharedInstance] setActive:NO
                                       withOptions:AVAudioSessionSetActiveOptionNotifyOthersOnDeactivation
                                             error:nil];
    } @catch (__unused id e) {}
}

#pragma mark - Setup

- (void)installNavigationItems {
    self.navigationItem.largeTitleDisplayMode = UINavigationItemLargeTitleDisplayModeNever;

    UIBarButtonItem *menuItem = [[UIBarButtonItem alloc] initWithImage:[UIImage systemImageNamed:@"ellipsis.circle"]
                                                                  menu:[self buildOverflowMenu]];
    self.navigationItem.rightBarButtonItem = menuItem;

    if (self.navigationController.viewControllers.firstObject == self) {
        UIBarButtonItem *closeItem = [[UIBarButtonItem alloc] initWithImage:[UIImage systemImageNamed:@"xmark"]
                                                                       style:UIBarButtonItemStylePlain
                                                                      target:self
                                                                      action:@selector(closeTapped)];
        self.navigationItem.leftBarButtonItem = closeItem;
    }
}

- (UIMenu *)buildOverflowMenu {
    NSArray *dateRanges = @[
        @[SCILocalized(@"All time"), @(SCIDMDateRangeAll),   @"infinity"],
        @[SCILocalized(@"Today"),    @(SCIDMDateRangeToday), @"sun.max"],
        @[SCILocalized(@"Last 7 days"),  @(SCIDMDateRangeWeek),  @"calendar"],
        @[SCILocalized(@"Last 30 days"), @(SCIDMDateRangeMonth), @"calendar.badge.clock"],
    ];
    NSMutableArray *dateActions = [NSMutableArray array];
    for (NSArray *e in dateRanges) {
        SCIDMDateRange r = [e[1] integerValue];
        UIAction *a = [UIAction actionWithTitle:e[0]
                                          image:[UIImage systemImageNamed:e[2]]
                                     identifier:nil
                                        handler:^(__kindof UIAction *_) {
            self.filter.dateRange = r;
            [self refilter];
            [self refreshNavMenu];
        }];
        a.state = (self.filter.dateRange == r) ? UIMenuElementStateOn : UIMenuElementStateOff;
        [dateActions addObject:a];
    }
    UIMenu *dateMenu = [UIMenu menuWithTitle:SCILocalized(@"Date range")
                                       image:[UIImage systemImageNamed:@"calendar"]
                                  identifier:nil
                                     options:0
                                    children:dateActions];

    NSArray *sorts = @[
        @[SCILocalized(@"Most recent"),  @(SCIDMSortRecent),    @"clock.arrow.circlepath"],
        @[SCILocalized(@"Oldest first"), @(SCIDMSortOldest),    @"arrow.up.to.line"],
        @[SCILocalized(@"Most messages"),@(SCIDMSortCountDesc), @"number"],
    ];
    NSMutableArray *sortActions = [NSMutableArray array];
    for (NSArray *e in sorts) {
        SCIDMSort s = [e[1] integerValue];
        UIAction *a = [UIAction actionWithTitle:e[0]
                                          image:[UIImage systemImageNamed:e[2]]
                                     identifier:nil
                                        handler:^(__kindof UIAction *_) {
            self.filter.sort = s;
            [self refilter];
            [self refreshNavMenu];
        }];
        a.state = (self.filter.sort == s) ? UIMenuElementStateOn : UIMenuElementStateOff;
        [sortActions addObject:a];
    }
    UIMenu *sortMenu = [UIMenu menuWithTitle:SCILocalized(@"Sort")
                                       image:[UIImage systemImageNamed:@"arrow.up.arrow.down"]
                                  identifier:nil
                                     options:0
                                    children:sortActions];

    NSArray *dateFormats = @[
        @[SCILocalized(@"Relative (1m / 3h / 3d ago)"), @"relative"],
        @[SCILocalized(@"Absolute date + time"),         @"absolute"],
    ];
    NSMutableArray *dateFmtActions = [NSMutableArray array];
    NSString *currentFmt = [SCIUtils getStringPref:@"dm_log_date_format"] ?: @"relative";
    for (NSArray *e in dateFormats) {
        NSString *value = e[1];
        UIAction *a = [UIAction actionWithTitle:e[0]
                                          image:nil
                                     identifier:nil
                                        handler:^(__kindof UIAction *_) {
            [SCIUtils setPref:value forKey:@"dm_log_date_format"];
            [self refilter];
            [self refreshNavMenu];
        }];
        a.state = [currentFmt isEqualToString:value] ? UIMenuElementStateOn : UIMenuElementStateOff;
        [dateFmtActions addObject:a];
    }
    UIMenu *dateFormatMenu = [UIMenu menuWithTitle:SCILocalized(@"Date format")
                                              image:[UIImage systemImageNamed:@"clock"]
                                         identifier:nil
                                            options:0
                                           children:dateFmtActions];

    UIAction *storage = [UIAction actionWithTitle:SCILocalized(@"Storage")
                                             image:[UIImage systemImageNamed:@"externaldrive"]
                                        identifier:nil
                                           handler:^(__kindof UIAction *_) { [self storageTapped]; }];

    UIAction *clearAll = [UIAction actionWithTitle:SCILocalized(@"Clear log")
                                              image:[UIImage systemImageNamed:@"trash"]
                                         identifier:nil
                                            handler:^(__kindof UIAction *_) { [self clearAllTapped]; }];
    clearAll.attributes = UIMenuElementAttributesDestructive;

    return [UIMenu menuWithTitle:@"" children:@[dateMenu, sortMenu, dateFormatMenu,
        [UIMenu menuWithTitle:@"" image:nil identifier:nil
                      options:UIMenuOptionsDisplayInline children:@[storage, clearAll]]]];
}

- (void)storageTapped {
    SCIDeletedMessagesStorageViewController *vc = [SCIDeletedMessagesStorageViewController new];
    [self.navigationController pushViewController:vc animated:YES];
}

- (void)refreshNavMenu {
    self.navigationItem.rightBarButtonItem.menu = [self buildOverflowMenu];
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
    // Force stacked placement — iOS 26 bottom-of-nav default looks wrong here.
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
    [self.tableView registerClass:[SCIDMSenderCell class] forCellReuseIdentifier:@"sender"];

    UIRefreshControl *rc = [UIRefreshControl new];
    [rc addTarget:self action:@selector(pulled:) forControlEvents:UIControlEventValueChanged];
    self.tableView.refreshControl = rc;
    [self.view addSubview:self.tableView];

    [NSLayoutConstraint activateConstraints:@[
        [self.tableView.leadingAnchor  constraintEqualToAnchor:self.view.leadingAnchor],
        [self.tableView.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor],
        [self.tableView.topAnchor      constraintEqualToAnchor:self.view.safeAreaLayoutGuide.topAnchor],
        [self.tableView.bottomAnchor   constraintEqualToAnchor:self.view.bottomAnchor],
    ]];

    self.footerLabel = [UILabel new];
    self.footerLabel.font = [UIFont systemFontOfSize:12];
    self.footerLabel.textColor = [UIColor tertiaryLabelColor];
    self.footerLabel.textAlignment = NSTextAlignmentCenter;
    self.footerLabel.numberOfLines = 0;
    self.footerLabel.frame = CGRectMake(0, 0, 320, 60);
    self.tableView.tableFooterView = self.footerLabel;
}

- (void)installEmptyView {
    self.emptyView = [[SCIDMEmptyView alloc] init];
    self.emptyView.translatesAutoresizingMaskIntoConstraints = NO;
    self.emptyView.hidden = YES;
    [self.view addSubview:self.emptyView];
    [NSLayoutConstraint activateConstraints:@[
        [self.emptyView.leadingAnchor  constraintEqualToAnchor:self.view.leadingAnchor],
        [self.emptyView.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor],
        [self.emptyView.topAnchor      constraintEqualToAnchor:self.tableView.topAnchor],
        [self.emptyView.bottomAnchor   constraintEqualToAnchor:self.view.bottomAnchor],
    ]];
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
    self.allGroups = [SCIDeletedMessagesStorage groupedBySenderForOwnerPK:self.ownerPK];
    [self refilter];
}

- (void)refilter {
    self.visibleGroups = [self.filter applyToGroups:self.allGroups];
    [self.tableView reloadData];
    [self refreshEmptyState];
    [self refreshFooter];
}

- (void)refreshEmptyState {
    BOOL noRecords = self.allGroups.count == 0;
    BOOL filteredEmpty = self.visibleGroups.count == 0;
    self.emptyView.hidden = !filteredEmpty;
    self.tableView.hidden = filteredEmpty;
    if (noRecords) {
        BOOL on = [SCIUtils getBoolPref:@"deleted_messages_log_enabled"];
        self.emptyView.iconView.image = [UIImage systemImageNamed:on ? @"tray" : @"tray.full"];
        self.emptyView.titleLabel.text = on
            ? SCILocalized(@"No deleted messages yet")
            : SCILocalized(@"Logging is off");
        self.emptyView.messageLabel.text = on
            ? SCILocalized(@"When someone unsends a message, it will appear here grouped by sender.")
            : SCILocalized(@"Enable Settings → Messages → Deleted messages log to start recording.");
    } else if (filteredEmpty) {
        self.emptyView.iconView.image = [UIImage systemImageNamed:@"line.3.horizontal.decrease.circle"];
        self.emptyView.titleLabel.text = SCILocalized(@"No matches");
        self.emptyView.messageLabel.text = SCILocalized(@"Adjust the filters or clear the search to see more.");
    }
}

- (void)refreshFooter {
    NSUInteger total = 0;
    for (SCIDeletedMessageGroup *g in self.allGroups) total += g.count;
    if (!total) { self.footerLabel.text = @""; return; }
    self.footerLabel.text = [NSString stringWithFormat:
                             SCILocalized(@"%lu messages from %lu users"),
                             (unsigned long)total, (unsigned long)self.allGroups.count];
    [self.footerLabel sizeToFit];
    CGRect f = self.footerLabel.frame;
    f.size.width = self.tableView.bounds.size.width;
    f.size.height = MAX(60, f.size.height + 24);
    self.footerLabel.frame = f;
    self.tableView.tableFooterView = self.footerLabel;
}

#pragma mark - Search / chip / actions

- (void)updateSearchResultsForSearchController:(UISearchController *)sc {
    self.filter.searchText = sc.searchBar.text;
    [self refilter];
}

- (void)closeTapped {
    [self dismissViewControllerAnimated:YES completion:nil];
}

- (void)clearAllTapped {
    UIAlertController *a = [UIAlertController alertControllerWithTitle:SCILocalized(@"Clear deleted-message log?")
                                                              message:SCILocalized(@"Removes every preserved deleted message and its captured media for this account.")
                                                       preferredStyle:UIAlertControllerStyleAlert];
    [a addAction:[UIAlertAction actionWithTitle:SCILocalized(@"Cancel") style:UIAlertActionStyleCancel handler:nil]];
    [a addAction:[UIAlertAction actionWithTitle:SCILocalized(@"Clear")  style:UIAlertActionStyleDestructive
                                        handler:^(UIAlertAction *_) {
        [SCIDeletedMessagesStorage resetForOwnerPK:self.ownerPK];
    }]];
    [self presentViewController:a animated:YES completion:nil];
}

#pragma mark - Table

- (NSInteger)tableView:(UITableView *)tv numberOfRowsInSection:(NSInteger)section {
    return (NSInteger)self.visibleGroups.count;
}

- (UITableViewCell *)tableView:(UITableView *)tv cellForRowAtIndexPath:(NSIndexPath *)ip {
    SCIDMSenderCell *cell = [tv dequeueReusableCellWithIdentifier:@"sender" forIndexPath:ip];
    SCIDeletedMessageGroup *g = self.visibleGroups[ip.row];
    SCIDeletedMessage *latest = g.latest;

    cell.nameLabel.text   = g.senderFullName.length ? g.senderFullName
                          : (g.senderUsername.length ? g.senderUsername : SCILocalized(@"Unknown user"));
    cell.handleLabel.text = g.senderUsername.length ? [@"@" stringByAppendingString:g.senderUsername] : @"";
    cell.previewLabel.text = [self previewTextForMessage:latest];
    cell.timeLabel.text   = [SCIDeletedMessagesDate stringForDate:g.lastDeletedAt];

    NSUInteger unseen = sciUnseenCountForGroup(g, self.ownerPK);
    cell.countLabel.text  = [NSString stringWithFormat:@"%lu", (unsigned long)unseen];
    cell.countBadge.hidden = (unseen == 0);
    cell.nameLabel.font   = (unseen > 0) ? [UIFont systemFontOfSize:16 weight:UIFontWeightSemibold]
                                         : [UIFont systemFontOfSize:16 weight:UIFontWeightRegular];

    if (g.senderProfilePicURL.length) {
        __weak UIImageView *iv = cell.avatarView;
        [SCIImageCache loadImageFromURL:[NSURL URLWithString:g.senderProfilePicURL]
                             completion:^(UIImage *img) { if (img) iv.image = img; }];
    } else {
        [self backfillSenderIfNeeded:g];
    }
    return cell;
}

// One-shot users/<pk>/info/ backfill for senders the capture resolver had no cache for.
// In-flight set throttles duplicate requests during scroll.
- (void)backfillSenderIfNeeded:(SCIDeletedMessageGroup *)g {
    if (!g.senderPk.length) return;
    static NSMutableSet<NSString *> *inflight;
    static dispatch_once_t once;
    dispatch_once(&once, ^{ inflight = [NSMutableSet set]; });
    @synchronized (inflight) {
        if ([inflight containsObject:g.senderPk]) return;
        [inflight addObject:g.senderPk];
    }
    NSString *senderPk = g.senderPk;
    NSString *ownerPK  = self.ownerPK;
    [SCIInstagramAPI sendRequestWithMethod:@"GET"
                                      path:[NSString stringWithFormat:@"users/%@/info/", senderPk]
                                      body:nil
                                completion:^(NSDictionary *resp, NSError *error) {
        @synchronized (inflight) { [inflight removeObject:senderPk]; }
        NSDictionary *user = [resp[@"user"] isKindOfClass:[NSDictionary class]] ? resp[@"user"] : nil;
        if (!user.count) return;
        [SCIDeletedMessagesStorage applySenderInfo:user forSenderPK:senderPk ownerPK:ownerPK];
    }];
}

- (void)tableView:(UITableView *)tv didSelectRowAtIndexPath:(NSIndexPath *)ip {
    [tv deselectRowAtIndexPath:ip animated:YES];
    SCIDeletedMessageGroup *g = self.visibleGroups[ip.row];
    sciMarkSenderSeen(self.ownerPK, g.senderPk);
    [self.tableView reloadRowsAtIndexPaths:@[ip] withRowAnimation:UITableViewRowAnimationNone];
    SCIDeletedMessagesUserDetailViewController *vc =
        [[SCIDeletedMessagesUserDetailViewController alloc] initWithGroup:g ownerPK:self.ownerPK];
    [self.navigationController pushViewController:vc animated:YES];
}

- (UISwipeActionsConfiguration *)tableView:(UITableView *)tv trailingSwipeActionsConfigurationForRowAtIndexPath:(NSIndexPath *)ip {
    SCIDeletedMessageGroup *g = self.visibleGroups[ip.row];
    UIContextualAction *del = [UIContextualAction contextualActionWithStyle:UIContextualActionStyleDestructive
                                                                      title:SCILocalized(@"Clear")
                                                                    handler:^(UIContextualAction *a, __kindof UIView *src, void (^done)(BOOL)) {
        [SCIDeletedMessagesStorage deleteMessagesForSenderPK:g.senderPk ownerPK:self.ownerPK];
        done(YES);
    }];
    del.image = [UIImage systemImageNamed:@"trash"];
    return [UISwipeActionsConfiguration configurationWithActions:@[del]];
}

#pragma mark - Helpers

- (NSString *)previewTextForMessage:(SCIDeletedMessage *)m {
    if (!m) return @"";
    if (m.kind == SCIDeletedMessageKindText && m.text.length) return m.text;
    if (m.previewText.length) return m.previewText;
    NSString *kind = SCIDeletedMessageKindLocalizedName(m.kind);
    return [@"⚑ " stringByAppendingString:kind];
}

@end
