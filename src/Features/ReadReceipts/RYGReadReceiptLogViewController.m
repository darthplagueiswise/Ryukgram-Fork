#import "RYGReadReceiptLogViewController.h"
#import "../Feed/RYGHomeShortcutBadges.h"
#import "RYGReadReceiptModels.h"
#import "RYGReadReceiptStorage.h"
#import "../Activity/RYGActivityConfig.h"
#import "../../UI/RYGPopupChrome.h"
#import "../../Lock/RYGLockGate.h"
#import "../../Lock/RYGLockGroups.h"
#import "../../RYGImageCache.h"
#import "../StoriesAndMessages/RYGDirectThreadInfo.h"
#import "../StoriesAndMessages/RYGDirectUserResolver.h"
#import "../Activity/RYGActivityLogStore.h"
#import "../Activity/RYGActivityConfig.h"
#import "../Activity/RYGActivityMatrixViewController.h"
#import "../Activity/RYGActivityPersonViewController.h"
#import "../../Utils.h"

typedef NS_ENUM(NSInteger, RYGRRDateRange) { RYGRRDateAll = 0, RYGRRDateToday, RYGRRDate7, RYGRRDate30 };
typedef NS_ENUM(NSInteger, RYGRRSort)      { RYGRRSortRecent = 0, RYGRRSortMostReads, RYGRRSortName };
typedef NS_ENUM(NSInteger, RYGActKind)     { RYGActRead = 0, RYGActOnline, RYGActOffline, RYGActTyping };

static NSString *rrRelative(NSDate *d) {
    if (!d) return @"";
    if (@available(iOS 13.0, *)) {
        static NSRelativeDateTimeFormatter *f; static dispatch_once_t once;
        dispatch_once(&once, ^{ f = [NSRelativeDateTimeFormatter new]; });
        return [f localizedStringForDate:d relativeToDate:[NSDate date]];
    }
    return d.description;
}
static NSString *rrAbsolute(NSDate *d) {
    if (!d) return @"";
    static NSDateFormatter *f; static dispatch_once_t once;
    dispatch_once(&once, ^{ f = [NSDateFormatter new]; f.dateStyle = NSDateFormatterMediumStyle; f.timeStyle = NSDateFormatterShortStyle; });
    return [f stringFromDate:d];
}
static BOOL rrDateInRange(NSDate *d, RYGRRDateRange r) {
    if (r == RYGRRDateAll || !d) return YES;
    NSTimeInterval age = -[d timeIntervalSinceNow];
    switch (r) {
        case RYGRRDateToday: { NSCalendar *c = NSCalendar.currentCalendar; return [c isDateInToday:d]; }
        case RYGRRDate7:  return age <= 7  * 86400;
        case RYGRRDate30: return age <= 30 * 86400;
        default: return YES;
    }
}

static RYGActivityType rrTypeForKind(RYGActKind k) {
    switch (k) {
        case RYGActOnline:  return RYGActivityTypeOnline;
        case RYGActOffline: return RYGActivityTypeOffline;
        case RYGActTyping:  return RYGActivityTypeTyping;
        default:            return RYGActivityTypeRead;
    }
}
static NSString *kindLabel(RYGActKind k) {
    switch (k) {
        case RYGActOnline:  return RYGLocalized(@"Came online");
        case RYGActOffline: return RYGLocalized(@"Went offline");
        case RYGActTyping:  return RYGLocalized(@"Started typing");
        default:            return RYGLocalized(@"Read your message");
    }
}
static NSString *kindPillTitle(RYGActKind k) {
    switch (k) {
        case RYGActOnline:  return RYGLocalized(@"Online");
        case RYGActOffline: return RYGLocalized(@"Offline");
        case RYGActTyping:  return RYGLocalized(@"Typing");
        default:            return RYGLocalized(@"Reads");
    }
}
static NSArray<NSNumber *> *rrAllKinds(void) {
    return @[@(RYGActRead), @(RYGActOnline), @(RYGActOffline), @(RYGActTyping)];
}

#pragma mark - Unified model

@interface RYGActItem : NSObject
@property (nonatomic, assign) RYGActKind kind;
@property (nonatomic, strong) NSDate *date;
@property (nonatomic, copy, nullable) NSString *text;    // read preview
@property (nonatomic, copy, nullable) NSString *who;     // group read: @username
@property (nonatomic, copy, nullable) NSString *whoPic;
@property (nonatomic, copy, nullable) NSString *messageId;
@property (nonatomic, copy, nullable) NSString *readerPk;
@property (nonatomic, copy, nullable) NSString *threadId;
@end
@implementation RYGActItem
@end

@interface RYGActRow : NSObject
@property (nonatomic, assign) BOOL isGroup;
@property (nonatomic, copy, nullable) NSString *pk;
@property (nonatomic, copy, nullable) NSString *threadId;
@property (nonatomic, copy) NSString *title;
@property (nonatomic, copy, nullable) NSString *avatarURL;
@property (nonatomic, strong) NSArray<RYGActItem *> *items;   // newest-first
@property (nonatomic, assign) NSUInteger readCount;
@end
@implementation RYGActRow
- (NSDate *)lastDate { return self.items.firstObject.date; }
- (RYGActItem *)latest { return self.items.firstObject; }
- (NSString *)identifier { return self.isGroup ? (self.threadId ?: @"") : [@"u:" stringByAppendingString:self.pk ?: @""]; }
- (NSUInteger)distinctReaderCount {
    NSMutableSet *s = [NSMutableSet set];
    for (RYGActItem *it in self.items) if (it.kind == RYGActRead && it.who.length) [s addObject:it.who];
    return s.count;
}
@end

#pragma mark - Avatar helper

static void rrLoadAvatar(UIImageView *iv, NSString *urlStr, NSString *pk) {
    iv.image = [UIImage systemImageNamed:@"person.circle.fill"];
    iv.tintColor = UIColor.systemGray3Color;
    iv.accessibilityValue = urlStr;
    if (!urlStr.length) return;
    NSURL *url = [NSURL URLWithString:urlStr];
    if (!url) return;
    [RYGImageCache loadImageFromURL:url cacheKey:nil completion:^(UIImage *img) {
        if (img && [iv.accessibilityValue isEqualToString:urlStr]) iv.image = img;
    }];
}

#pragma mark - Seen tracking

static NSString *const kRYGRRSeenPrefKey = @"read_receipts_seen";

static NSString *rrSeenKey(NSString *ownerPk, NSString *identifier) {
    return [NSString stringWithFormat:@"%@:%@", ownerPk ?: @"", identifier ?: @""];
}
static NSTimeInterval rrSeenTimestamp(NSString *ownerPk, NSString *identifier) {
    NSDictionary *all = [NSUserDefaults.standardUserDefaults dictionaryForKey:kRYGRRSeenPrefKey];
    id v = all[rrSeenKey(ownerPk, identifier)];
    return [v isKindOfClass:NSNumber.class] ? [v doubleValue] : 0;
}
static void rrMarkSeen(NSString *ownerPk, NSString *identifier) {
    if (!identifier.length) return;
    NSUserDefaults *d = NSUserDefaults.standardUserDefaults;
    NSMutableDictionary *m = [[d dictionaryForKey:kRYGRRSeenPrefKey] ?: @{} mutableCopy];
    m[rrSeenKey(ownerPk, identifier)] = @(NSDate.date.timeIntervalSince1970);
    [d setObject:m forKey:kRYGRRSeenPrefKey];
    [d synchronize];
}
static NSUInteger rrUnseenForRow(RYGActRow *row, NSString *ownerPk) {
    NSTimeInterval seen = rrSeenTimestamp(ownerPk, row.identifier);
    if (seen <= 0) return row.items.count;
    NSUInteger n = 0;
    for (RYGActItem *it in row.items) if (it.date.timeIntervalSince1970 > seen) n++;
    return n;
}

#pragma mark - Cell

@interface RYGRRGroupCell : UITableViewCell
@property (nonatomic, strong) UIImageView *avatar;
@property (nonatomic, strong) UILabel *titleLbl;
@property (nonatomic, strong) UILabel *subLbl;
@property (nonatomic, strong) UIImageView *mutedIcon;
@property (nonatomic, strong) UIView *countBadge;
@property (nonatomic, strong) UILabel *countLabel;
@end
@implementation RYGRRGroupCell
- (instancetype)initWithStyle:(UITableViewCellStyle)style reuseIdentifier:(NSString *)rid {
    if ((self = [super initWithStyle:UITableViewCellStyleDefault reuseIdentifier:rid])) {
        self.backgroundColor = UIColor.secondarySystemGroupedBackgroundColor;
        _avatar = [UIImageView new];
        _avatar.contentMode = UIViewContentModeScaleAspectFill;
        _avatar.layer.cornerRadius = 23; _avatar.layer.masksToBounds = YES;
        _avatar.backgroundColor = UIColor.secondarySystemBackgroundColor;
        _titleLbl = [UILabel new]; _titleLbl.font = [UIFont systemFontOfSize:16 weight:UIFontWeightSemibold];
        _subLbl = [UILabel new]; _subLbl.font = [UIFont systemFontOfSize:13]; _subLbl.textColor = UIColor.secondaryLabelColor;
        _mutedIcon = [[UIImageView alloc] initWithImage:[UIImage systemImageNamed:@"eye.slash.fill"]];
        _mutedIcon.tintColor = UIColor.systemGray3Color; _mutedIcon.contentMode = UIViewContentModeScaleAspectFit;
        _countBadge = [UIView new];
        _countBadge.layer.cornerRadius = 10; _countBadge.layer.masksToBounds = YES;
        _countBadge.backgroundColor = UIColor.systemRedColor;
        _countBadge.hidden = YES;
        _countLabel = [UILabel new];
        _countLabel.translatesAutoresizingMaskIntoConstraints = NO;
        _countLabel.font = [UIFont systemFontOfSize:11 weight:UIFontWeightSemibold];
        _countLabel.textColor = UIColor.whiteColor;
        _countLabel.textAlignment = NSTextAlignmentCenter;
        [_countBadge addSubview:_countLabel];
        for (UIView *v in @[_avatar, _titleLbl, _subLbl, _mutedIcon, _countBadge]) { v.translatesAutoresizingMaskIntoConstraints = NO; [self.contentView addSubview:v]; }
        [NSLayoutConstraint activateConstraints:@[
            [_avatar.leadingAnchor constraintEqualToAnchor:self.contentView.leadingAnchor constant:16],
            [_avatar.centerYAnchor constraintEqualToAnchor:self.contentView.centerYAnchor],
            [_avatar.widthAnchor constraintEqualToConstant:46], [_avatar.heightAnchor constraintEqualToConstant:46],
            [_titleLbl.leadingAnchor constraintEqualToAnchor:_avatar.trailingAnchor constant:12],
            [_titleLbl.topAnchor constraintEqualToAnchor:self.contentView.topAnchor constant:12],
            [_titleLbl.trailingAnchor constraintLessThanOrEqualToAnchor:_mutedIcon.leadingAnchor constant:-8],
            [_subLbl.leadingAnchor constraintEqualToAnchor:_titleLbl.leadingAnchor],
            [_subLbl.topAnchor constraintEqualToAnchor:_titleLbl.bottomAnchor constant:3],
            [_subLbl.trailingAnchor constraintLessThanOrEqualToAnchor:_mutedIcon.leadingAnchor constant:-8],
            [_subLbl.bottomAnchor constraintEqualToAnchor:self.contentView.bottomAnchor constant:-12],
            [_mutedIcon.trailingAnchor constraintEqualToAnchor:self.contentView.trailingAnchor constant:-16],
            [_mutedIcon.centerYAnchor constraintEqualToAnchor:self.contentView.centerYAnchor],
            [_mutedIcon.widthAnchor constraintEqualToConstant:18], [_mutedIcon.heightAnchor constraintEqualToConstant:18],
            [_countBadge.trailingAnchor constraintEqualToAnchor:self.contentView.trailingAnchor constant:-12],
            [_countBadge.centerYAnchor constraintEqualToAnchor:self.contentView.centerYAnchor],
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
@end

#pragma mark - Detail (one person's / chat's timeline)

@interface RYGRRDetailViewController : UIViewController <UITableViewDataSource, UITableViewDelegate>
@property (nonatomic, strong) RYGActRow *row;
@property (nonatomic, copy) NSString *ownerPK;
@property (nonatomic, strong) UITableView *tableView;
@end

@interface RYGRRDetailViewController ()
@property (nonatomic, strong) NSArray<RYGActItem *> *allItems;
@property (nonatomic, strong) NSArray<RYGActItem *> *visible;
@property (nonatomic, assign) RYGActivityType typeFilter;
@property (nonatomic, assign) RYGRRDateRange dateRange;
@property (nonatomic, assign) BOOL oldestFirst;
@property (nonatomic, strong) UIScrollView *pillBar;
@property (nonatomic, strong) UIStackView *pillStack;
@property (nonatomic, strong) NSLayoutConstraint *pillBarHeight;
@property (nonatomic, strong) UILabel *emptyLabel;
@property (nonatomic, strong) UIBarButtonItem *selectItem;
@property (nonatomic, strong) UIBarButtonItem *deleteItem;
@property (nonatomic, strong) UIBarButtonItem *selectAllItem;
@property (nonatomic, assign) BOOL batching;
@end

@implementation RYGRRDetailViewController

- (void)viewDidLoad {
    [super viewDidLoad];
    self.view.backgroundColor = [RYGPopupChrome backgroundColor];
    self.title = self.row.title.length ? self.row.title : RYGLocalized(@"Activity");

    self.pillBar = [UIScrollView new];
    self.pillBar.translatesAutoresizingMaskIntoConstraints = NO;
    self.pillBar.showsHorizontalScrollIndicator = NO;
    self.pillBar.alwaysBounceHorizontal = YES;
    [self.view addSubview:self.pillBar];

    self.pillStack = [UIStackView new];
    self.pillStack.translatesAutoresizingMaskIntoConstraints = NO;
    self.pillStack.axis = UILayoutConstraintAxisHorizontal;
    self.pillStack.spacing = 8;
    self.pillStack.alignment = UIStackViewAlignmentCenter;
    [self.pillBar addSubview:self.pillStack];

    self.tableView = [[UITableView alloc] initWithFrame:CGRectZero style:UITableViewStyleInsetGrouped];
    self.tableView.translatesAutoresizingMaskIntoConstraints = NO;
    self.tableView.backgroundColor = UIColor.clearColor;
    self.tableView.rowHeight = UITableViewAutomaticDimension;
    self.tableView.estimatedRowHeight = 60;
    self.tableView.allowsMultipleSelectionDuringEditing = YES;
    self.tableView.dataSource = self; self.tableView.delegate = self;
    [self.view addSubview:self.tableView];

    self.pillBarHeight = [self.pillBar.heightAnchor constraintEqualToConstant:52];
    [NSLayoutConstraint activateConstraints:@[
        [self.pillBar.topAnchor constraintEqualToAnchor:self.view.safeAreaLayoutGuide.topAnchor],
        [self.pillBar.leadingAnchor constraintEqualToAnchor:self.view.leadingAnchor],
        [self.pillBar.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor],
        self.pillBarHeight,
        [self.pillStack.topAnchor constraintEqualToAnchor:self.pillBar.topAnchor constant:10],
        [self.pillStack.bottomAnchor constraintEqualToAnchor:self.pillBar.bottomAnchor constant:-10],
        [self.pillStack.leadingAnchor constraintEqualToAnchor:self.pillBar.leadingAnchor constant:16],
        [self.pillStack.trailingAnchor constraintEqualToAnchor:self.pillBar.trailingAnchor constant:-16],
        [self.tableView.topAnchor constraintEqualToAnchor:self.pillBar.bottomAnchor],
        [self.tableView.leadingAnchor constraintEqualToAnchor:self.view.leadingAnchor],
        [self.tableView.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor],
        [self.tableView.bottomAnchor constraintEqualToAnchor:self.view.bottomAnchor],
    ]];

    self.emptyLabel = [UILabel new];
    self.emptyLabel.translatesAutoresizingMaskIntoConstraints = NO;
    self.emptyLabel.numberOfLines = 0; self.emptyLabel.textAlignment = NSTextAlignmentCenter;
    self.emptyLabel.textColor = UIColor.secondaryLabelColor;
    self.emptyLabel.text = RYGLocalized(@"Nothing here yet.");
    [self.view addSubview:self.emptyLabel];
    [NSLayoutConstraint activateConstraints:@[
        [self.emptyLabel.centerXAnchor constraintEqualToAnchor:self.tableView.centerXAnchor],
        [self.emptyLabel.centerYAnchor constraintEqualToAnchor:self.tableView.centerYAnchor],
        [self.emptyLabel.leadingAnchor constraintEqualToAnchor:self.view.leadingAnchor constant:32],
        [self.emptyLabel.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor constant:-32],
    ]];

    self.selectItem = [[UIBarButtonItem alloc] initWithTitle:RYGLocalized(@"Select") style:UIBarButtonItemStylePlain target:self action:@selector(beginSelecting)];
    self.navigationItem.rightBarButtonItem = self.selectItem;
    self.deleteItem = [[UIBarButtonItem alloc] initWithTitle:RYGLocalized(@"Delete") style:UIBarButtonItemStylePlain target:self action:@selector(deleteSelected)];
    self.deleteItem.tintColor = UIColor.systemRedColor;
    self.selectAllItem = [[UIBarButtonItem alloc] initWithTitle:RYGLocalized(@"Select All") style:UIBarButtonItemStylePlain target:self action:@selector(toggleSelectAll)];

    [self reload];
    [NSNotificationCenter.defaultCenter addObserver:self selector:@selector(onStoreChanged) name:RYGReadReceiptsDidChangeNotification object:nil];
    [NSNotificationCenter.defaultCenter addObserver:self selector:@selector(onStoreChanged) name:RYGActivityLogDidChangeNotification object:nil];
}
- (void)dealloc { [NSNotificationCenter.defaultCenter removeObserver:self]; }
- (void)onStoreChanged { if (!self.batching) [self reload]; }

#pragma mark - Header (avatar)

- (UIView *)tableView:(UITableView *)t viewForHeaderInSection:(NSInteger)s {
    UIView *h = [[UIView alloc] initWithFrame:CGRectMake(0, 0, t.bounds.size.width, 92)];
    UIImageView *av = [UIImageView new];
    av.translatesAutoresizingMaskIntoConstraints = NO;
    av.contentMode = UIViewContentModeScaleAspectFill;
    av.layer.cornerRadius = 32; av.layer.masksToBounds = YES;
    if (self.row.isGroup && !self.row.avatarURL.length) { av.image = [UIImage systemImageNamed:@"person.2.circle.fill"]; av.tintColor = UIColor.systemGray2Color; }
    else rrLoadAvatar(av, self.row.avatarURL, self.row.pk);
    [h addSubview:av];
    [NSLayoutConstraint activateConstraints:@[
        [av.centerXAnchor constraintEqualToAnchor:h.centerXAnchor],
        [av.topAnchor constraintEqualToAnchor:h.topAnchor constant:14],
        [av.widthAnchor constraintEqualToConstant:64],
        [av.heightAnchor constraintEqualToConstant:64],
    ]];
    return h;
}
- (CGFloat)tableView:(UITableView *)t heightForHeaderInSection:(NSInteger)s { return 92; }

#pragma mark - Data

- (NSArray<RYGActItem *> *)buildItems {
    NSString *owner = self.ownerPK;
    NSMutableArray<RYGActItem *> *items = [NSMutableArray array];
    if (self.row.isGroup) {
        for (RYGReadReceipt *r in [RYGReadReceiptStorage receiptsForThreadId:self.row.threadId ownerPK:owner]) {
            RYGActItem *it = [RYGActItem new];
            it.kind = RYGActRead; it.date = r.readAt; it.text = r.messagePreview;
            it.who = r.readerUsername.length ? [@"@" stringByAppendingString:r.readerUsername] : r.readerPk; it.whoPic = r.readerProfilePicURL;
            it.messageId = r.messageId; it.readerPk = r.readerPk; it.threadId = r.threadId;
            [items addObject:it];
        }
    } else {
        NSString *pk = self.row.pk;
        for (RYGReadReceipt *r in [RYGReadReceiptStorage receiptsForReaderPK:pk ownerPK:owner]) {
            RYGActItem *it = [RYGActItem new];
            it.kind = RYGActRead; it.date = r.readAt; it.text = r.messagePreview;
            it.messageId = r.messageId; it.readerPk = r.readerPk; it.threadId = r.threadId;
            [items addObject:it];
        }
        for (RYGActivityLogEvent *ev in [RYGActivityLogStore eventsForPK:pk ownerPK:owner]) {
            RYGActItem *it = [RYGActItem new];
            it.kind = ev.type == RYGActivityTypeOnline ? RYGActOnline : (ev.type == RYGActivityTypeOffline ? RYGActOffline : RYGActTyping);
            it.date = ev.at;
            [items addObject:it];
        }
    }
    [items sortUsingComparator:^NSComparisonResult(RYGActItem *a, RYGActItem *b) { return [b.date compare:a.date]; }];
    return items;
}

- (void)reload {
    self.allItems = [self buildItems];
    [self rebuildPills];
    [self applyFilter];
}

- (void)applyFilter {
    RYGActivityType mask = self.typeFilter;
    NSMutableArray *out = [NSMutableArray array];
    for (RYGActItem *it in self.allItems)
        if ((mask == 0 || (rrTypeForKind(it.kind) & mask)) && rrDateInRange(it.date, self.dateRange)) [out addObject:it];
    if (self.oldestFirst)
        [out sortUsingComparator:^NSComparisonResult(RYGActItem *a, RYGActItem *b) { return [a.date compare:b.date]; }];
    self.visible = out;
    self.emptyLabel.hidden = out.count > 0;
    [self.tableView reloadData];
    if (self.tableView.isEditing) [self updateEditUI];
}

#pragma mark - Filter pills

- (RYGActivityType)presentKinds {
    RYGActivityType m = 0;
    for (RYGActItem *it in self.allItems) m |= rrTypeForKind(it.kind);
    return m;
}

- (UIButton *)pillWithTitle:(NSString *)title on:(BOOL)on tint:(UIColor *)tint action:(void (^)(void))action {
    UIButtonConfiguration *cfg = [UIButtonConfiguration grayButtonConfiguration];
    cfg.title = title;
    cfg.buttonSize = UIButtonConfigurationSizeSmall;
    cfg.cornerStyle = UIButtonConfigurationCornerStyleCapsule;
    cfg.contentInsets = NSDirectionalEdgeInsetsMake(7, 14, 7, 14);
    cfg.baseForegroundColor = on ? UIColor.whiteColor : UIColor.labelColor;
    cfg.baseBackgroundColor = on ? (tint ?: UIColor.systemBlueColor) : UIColor.tertiarySystemFillColor;
    cfg.titleTextAttributesTransformer = ^NSDictionary *(NSDictionary *incoming) {
        NSMutableDictionary *a = [incoming mutableCopy];
        a[NSFontAttributeName] = [UIFont systemFontOfSize:14 weight:UIFontWeightMedium];
        return a;
    };
    UIButton *b = [UIButton buttonWithConfiguration:cfg primaryAction:nil];
    __weak typeof(self) ws = self;
    [b addAction:[UIAction actionWithHandler:^(UIAction *a) { action(); [ws applyFilter]; [ws rebuildPills]; }] forControlEvents:UIControlEventTouchUpInside];
    return b;
}

- (UIView *)pillDivider {
    UIView *line = [UIView new];
    line.backgroundColor = UIColor.separatorColor;
    [line.widthAnchor constraintEqualToConstant:1].active = YES;
    [line.heightAnchor constraintEqualToConstant:22].active = YES;
    return line;
}

- (BOOL)hasActiveFilter { return self.dateRange != RYGRRDateAll || self.oldestFirst; }

- (UIButton *)menuPillWithTitle:(NSString *)title on:(BOOL)on {
    UIButtonConfiguration *cfg = [UIButtonConfiguration grayButtonConfiguration];
    cfg.title = title;
    cfg.image = [UIImage systemImageNamed:@"line.3.horizontal.decrease"];
    cfg.imagePadding = 5;
    cfg.buttonSize = UIButtonConfigurationSizeSmall;
    cfg.cornerStyle = UIButtonConfigurationCornerStyleCapsule;
    cfg.contentInsets = NSDirectionalEdgeInsetsMake(7, 14, 7, 14);
    cfg.baseForegroundColor = on ? UIColor.whiteColor : UIColor.labelColor;
    cfg.baseBackgroundColor = on ? UIColor.systemBlueColor : UIColor.tertiarySystemFillColor;
    cfg.titleTextAttributesTransformer = ^NSDictionary *(NSDictionary *incoming) {
        NSMutableDictionary *a = [incoming mutableCopy];
        a[NSFontAttributeName] = [UIFont systemFontOfSize:14 weight:UIFontWeightMedium];
        return a;
    };
    UIButton *b = [UIButton buttonWithConfiguration:cfg primaryAction:nil];
    return b;
}

- (UIMenu *)filtersMenu {
    __weak typeof(self) ws = self;
    UIAction *(^d)(NSString *, RYGRRDateRange) = ^(NSString *t, RYGRRDateRange r) {
        UIAction *a = [UIAction actionWithTitle:t image:nil identifier:nil handler:^(UIAction *x){ ws.dateRange = r; [ws applyFilter]; [ws rebuildPills]; }];
        a.state = ws.dateRange == r ? UIMenuElementStateOn : UIMenuElementStateOff; return a;
    };
    UIMenu *date = [UIMenu menuWithTitle:RYGLocalized(@"Date") image:[UIImage systemImageNamed:@"calendar"] identifier:nil options:UIMenuOptionsDisplayInline children:@[
        d(RYGLocalized(@"All time"), RYGRRDateAll), d(RYGLocalized(@"Today"), RYGRRDateToday), d(RYGLocalized(@"Last 7 days"), RYGRRDate7), d(RYGLocalized(@"Last 30 days"), RYGRRDate30) ]];
    UIAction *(^so)(NSString *, BOOL) = ^(NSString *t, BOOL oldest) {
        UIAction *a = [UIAction actionWithTitle:t image:nil identifier:nil handler:^(UIAction *x){ ws.oldestFirst = oldest; [ws applyFilter]; [ws rebuildPills]; }];
        a.state = ws.oldestFirst == oldest ? UIMenuElementStateOn : UIMenuElementStateOff; return a;
    };
    UIMenu *sort = [UIMenu menuWithTitle:RYGLocalized(@"Sort") image:[UIImage systemImageNamed:@"arrow.up.arrow.down"] identifier:nil options:UIMenuOptionsDisplayInline children:@[
        so(RYGLocalized(@"Newest first"), NO), so(RYGLocalized(@"Oldest first"), YES) ]];
    return [UIMenu menuWithTitle:@"" children:@[date, sort]];
}

- (void)rebuildPills {
    for (UIView *v in self.pillStack.arrangedSubviews.copy) { [self.pillStack removeArrangedSubview:v]; [v removeFromSuperview]; }
    __weak typeof(self) ws = self;

    UIButton *filters = [self menuPillWithTitle:RYGLocalized(@"Filters") on:[self hasActiveFilter]];
    filters.showsMenuAsPrimaryAction = YES;
    filters.menu = [self filtersMenu];
    [self.pillStack addArrangedSubview:filters];

    RYGActivityType present = [self presentKinds];
    NSMutableArray<NSNumber *> *kinds = [NSMutableArray array];
    for (NSNumber *n in rrAllKinds()) if (present & rrTypeForKind((RYGActKind)n.integerValue)) [kinds addObject:n];
    if (kinds.count > 1) {
        [self.pillStack addArrangedSubview:[self pillDivider]];
        for (NSNumber *n in kinds) {
            RYGActKind k = (RYGActKind)n.integerValue;
            RYGActivityType t = rrTypeForKind(k);
            [self.pillStack addArrangedSubview:[self pillWithTitle:kindPillTitle(k) on:(self.typeFilter & t) != 0 tint:[RYGActivityConfig tintForType:t] action:^{ ws.typeFilter ^= t; }]];
        }
    }

    self.pillBarHeight.constant = 52;
    self.pillBar.hidden = NO;
}

#pragma mark - Table

- (NSInteger)tableView:(UITableView *)t numberOfRowsInSection:(NSInteger)s { return self.visible.count; }
- (UITableViewCell *)tableView:(UITableView *)t cellForRowAtIndexPath:(NSIndexPath *)ip {
    UITableViewCell *c = [t dequeueReusableCellWithIdentifier:@"d"];
    if (!c) c = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleSubtitle reuseIdentifier:@"d"];
    c.backgroundColor = UIColor.secondarySystemGroupedBackgroundColor;
    c.textLabel.numberOfLines = 0;
    c.detailTextLabel.numberOfLines = 0;
    RYGActItem *it = self.visible[ip.row];
    c.imageView.image = [RYGActivityConfig imageForType:rrTypeForKind(it.kind)];
    c.imageView.tintColor = [RYGActivityConfig tintForType:rrTypeForKind(it.kind)];
    NSString *main;
    if (it.kind == RYGActRead) {
        NSString *msg = it.text.length ? it.text : RYGLocalized(@"Your message");
        main = it.who.length ? [NSString stringWithFormat:@"%@ — %@", it.who, msg] : msg;
    } else {
        main = kindLabel(it.kind);
    }
    c.textLabel.text = main;
    c.detailTextLabel.text = [NSString stringWithFormat:@"%@ · %@", rrRelative(it.date), rrAbsolute(it.date)];
    c.detailTextLabel.textColor = UIColor.secondaryLabelColor;
    return c;
}

- (void)tableView:(UITableView *)t didSelectRowAtIndexPath:(NSIndexPath *)ip {
    if (t.isEditing) { [self updateEditUI]; return; }
    [t deselectRowAtIndexPath:ip animated:YES];
}
- (void)tableView:(UITableView *)t didDeselectRowAtIndexPath:(NSIndexPath *)ip {
    if (t.isEditing) [self updateEditUI];
}

- (UISwipeActionsConfiguration *)tableView:(UITableView *)t trailingSwipeActionsConfigurationForRowAtIndexPath:(NSIndexPath *)ip {
    if (ip.row >= (NSInteger)self.visible.count) return nil;
    RYGActItem *it = self.visible[ip.row];
    __weak typeof(self) ws = self;
    UIContextualAction *del = [UIContextualAction contextualActionWithStyle:UIContextualActionStyleDestructive title:RYGLocalized(@"Delete") handler:^(UIContextualAction *a, UIView *v, void (^done)(BOOL)) {
        [ws deleteActItem:it];
        done(YES);
    }];
    del.image = [UIImage systemImageNamed:@"trash"];
    return [UISwipeActionsConfiguration configurationWithActions:@[del]];
}

#pragma mark - Delete

- (void)deleteActItem:(RYGActItem *)it {
    NSString *owner = self.ownerPK;
    if (it.kind == RYGActRead)
        [RYGReadReceiptStorage deleteReceiptWithMessageId:it.messageId readerPk:it.readerPk threadId:it.threadId ownerPK:owner];
    else
        [RYGActivityLogStore deleteEventOfType:rrTypeForKind(it.kind) atTimestamp:it.date.timeIntervalSince1970 forPK:self.row.pk ownerPK:owner];
}

#pragma mark - Multi-select

- (void)beginSelecting { [self setEditing:YES animated:YES]; }
- (void)endSelecting { [self setEditing:NO animated:YES]; }

- (void)setEditing:(BOOL)editing animated:(BOOL)animated {
    [super setEditing:editing animated:animated];
    [self.tableView setEditing:editing animated:animated];
    if (editing) {
        self.navigationItem.rightBarButtonItem = [[UIBarButtonItem alloc] initWithBarButtonSystemItem:UIBarButtonSystemItemDone target:self action:@selector(endSelecting)];
        UIBarButtonItem *flex = [[UIBarButtonItem alloc] initWithBarButtonSystemItem:UIBarButtonSystemItemFlexibleSpace target:nil action:nil];
        self.toolbarItems = @[self.deleteItem, flex, self.selectAllItem];
        self.navigationController.toolbarHidden = NO;
    } else {
        self.navigationItem.rightBarButtonItem = self.selectItem;
        self.navigationController.toolbarHidden = YES;
    }
    [self updateEditUI];
}

- (void)updateEditUI {
    if (!self.tableView.isEditing) { self.title = self.row.title.length ? self.row.title : RYGLocalized(@"Activity"); return; }
    NSUInteger n = self.tableView.indexPathsForSelectedRows.count;
    self.title = n ? [NSString stringWithFormat:RYGLocalized(@"%lu selected"), (unsigned long)n] : RYGLocalized(@"Select");
    self.deleteItem.enabled = n > 0;
    self.deleteItem.title = n ? [NSString stringWithFormat:RYGLocalized(@"Delete (%lu)"), (unsigned long)n] : RYGLocalized(@"Delete");
    BOOL all = n > 0 && n == self.visible.count;
    self.selectAllItem.title = all ? RYGLocalized(@"Deselect All") : RYGLocalized(@"Select All");
}

- (void)toggleSelectAll {
    BOOL all = self.tableView.indexPathsForSelectedRows.count == self.visible.count;
    if (all) {
        for (NSIndexPath *ip in self.tableView.indexPathsForSelectedRows.copy) [self.tableView deselectRowAtIndexPath:ip animated:NO];
    } else {
        for (NSInteger i = 0; i < (NSInteger)self.visible.count; i++)
            [self.tableView selectRowAtIndexPath:[NSIndexPath indexPathForRow:i inSection:0] animated:NO scrollPosition:UITableViewScrollPositionNone];
    }
    [self updateEditUI];
}

- (void)deleteSelected {
    NSArray<NSIndexPath *> *sel = self.tableView.indexPathsForSelectedRows;
    if (!sel.count) return;
    NSMutableArray<RYGActItem *> *items = [NSMutableArray array];
    for (NSIndexPath *ip in sel) if (ip.row < (NSInteger)self.visible.count) [items addObject:self.visible[ip.row]];
    NSString *msg = RYGLocalized(@"Delete the selected records? This can't be undone.");
    UIAlertController *a = [UIAlertController alertControllerWithTitle:RYGLocalized(@"Delete records") message:msg preferredStyle:UIAlertControllerStyleAlert];
    [a addAction:[UIAlertAction actionWithTitle:RYGLocalized(@"Cancel") style:UIAlertActionStyleCancel handler:nil]];
    [a addAction:[UIAlertAction actionWithTitle:RYGLocalized(@"Delete") style:UIAlertActionStyleDestructive handler:^(UIAlertAction *x) {
        self.batching = YES;
        for (RYGActItem *it in items) [self deleteActItem:it];
        self.batching = NO;
        [self endSelecting];
        [self reload];
    }]];
    [self presentViewController:a animated:YES completion:nil];
}

@end

#pragma mark - Ignored management

@interface RYGRRIgnoredViewController : UIViewController <UITableViewDataSource, UITableViewDelegate>
@property (nonatomic, copy) NSString *ownerPK;
@property (nonatomic, strong) UITableView *tableView;
@property (nonatomic, strong) NSArray<NSString *> *ids;
@property (nonatomic, strong) NSDictionary<NSString *, NSString *> *pkNames;
@property (nonatomic, strong) NSDictionary<NSString *, NSString *> *threadTitles;
@end
@implementation RYGRRIgnoredViewController
- (void)viewDidLoad {
    [super viewDidLoad];
    self.title = RYGLocalized(@"Ignored");
    self.view.backgroundColor = [RYGPopupChrome backgroundColor];
    self.tableView = [[UITableView alloc] initWithFrame:self.view.bounds style:UITableViewStyleInsetGrouped];
    self.tableView.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
    self.tableView.backgroundColor = UIColor.clearColor;
    self.tableView.dataSource = self; self.tableView.delegate = self;
    [self.view addSubview:self.tableView];
    self.navigationItem.rightBarButtonItem = [[UIBarButtonItem alloc] initWithTitle:RYGLocalized(@"Clear all") style:UIBarButtonItemStylePlain target:self action:@selector(clearAll)];
    [self reload];
    [NSNotificationCenter.defaultCenter addObserver:self selector:@selector(reload) name:RYGReadReceiptsDidChangeNotification object:nil];
}
- (void)dealloc { [NSNotificationCenter.defaultCenter removeObserver:self]; }
- (void)reload {
    self.ids = [RYGReadReceiptStorage excludedIdentifiersForOwnerPK:self.ownerPK];
    NSMutableDictionary *m = [NSMutableDictionary dictionary];
    NSMutableDictionary *tt = [NSMutableDictionary dictionary];
    for (RYGReadReceipt *r in [RYGReadReceiptStorage allReceiptsForOwnerPK:self.ownerPK]) {
        if (r.readerPk && r.readerUsername) m[r.readerPk] = r.readerUsername;
        if (r.isGroup && r.threadId && r.threadTitle.length) tt[r.threadId] = r.threadTitle;
    }
    self.pkNames = m;
    self.threadTitles = tt;
    self.navigationItem.rightBarButtonItem.enabled = self.ids.count > 0;
    [self.tableView reloadData];
}
- (void)clearAll {
    for (NSString *id_ in self.ids.copy) {
        if ([id_ hasPrefix:@"u:"]) [RYGReadReceiptStorage setReader:[id_ substringFromIndex:2] excluded:NO ownerPK:self.ownerPK];
        else [RYGReadReceiptStorage setThread:id_ excluded:NO ownerPK:self.ownerPK];
    }
}
- (NSInteger)tableView:(UITableView *)t numberOfRowsInSection:(NSInteger)s { return self.ids.count; }
- (NSString *)tableView:(UITableView *)t titleForFooterInSection:(NSInteger)s {
    return self.ids.count ? RYGLocalized(@"Swipe to remove. Removing resumes logging for that person or chat.") : RYGLocalized(@"Nothing is ignored. Long-press someone in the log to stop logging them.");
}
- (UITableViewCell *)tableView:(UITableView *)t cellForRowAtIndexPath:(NSIndexPath *)ip {
    UITableViewCell *c = [t dequeueReusableCellWithIdentifier:@"i"] ?: [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleSubtitle reuseIdentifier:@"i"];
    c.backgroundColor = UIColor.secondarySystemGroupedBackgroundColor;
    NSString *id_ = self.ids[ip.row];
    if ([id_ hasPrefix:@"u:"]) {
        NSString *pk = [id_ substringFromIndex:2];
        c.textLabel.text = self.pkNames[pk] ? [@"@" stringByAppendingString:self.pkNames[pk]] : pk;
        c.detailTextLabel.text = RYGLocalized(@"Person");
    } else {
        c.textLabel.text = self.threadTitles[id_] ?: RYGLocalized(@"Group chat");
        c.detailTextLabel.text = RYGLocalized(@"Chat");
    }
    c.detailTextLabel.textColor = UIColor.secondaryLabelColor;
    c.imageView.image = [UIImage systemImageNamed:@"eye.slash"];
    c.imageView.tintColor = UIColor.systemGray2Color;
    return c;
}
- (UISwipeActionsConfiguration *)tableView:(UITableView *)t trailingSwipeActionsConfigurationForRowAtIndexPath:(NSIndexPath *)ip {
    NSString *id_ = self.ids[ip.row];
    NSString *owner = self.ownerPK;
    UIContextualAction *rm = [UIContextualAction contextualActionWithStyle:UIContextualActionStyleDestructive title:RYGLocalized(@"Remove") handler:^(UIContextualAction *a, UIView *v, void (^done)(BOOL)) {
        if ([id_ hasPrefix:@"u:"]) [RYGReadReceiptStorage setReader:[id_ substringFromIndex:2] excluded:NO ownerPK:owner];
        else [RYGReadReceiptStorage setThread:id_ excluded:NO ownerPK:owner];
        done(YES);
    }];
    return [UISwipeActionsConfiguration configurationWithActions:@[rm]];
}
@end

#pragma mark - Main list

@interface RYGReadReceiptLogViewController () <UITableViewDataSource, UITableViewDelegate, UISearchResultsUpdating>
@property (nonatomic, strong) UITableView *tableView;
@property (nonatomic, strong) UILabel *emptyLabel;
@property (nonatomic, strong) UISearchController *search;
@property (nonatomic, strong) NSArray<RYGActRow *> *allRows;
@property (nonatomic, strong) NSArray<RYGActRow *> *visible;
@property (nonatomic, copy) NSString *ownerPK;
@property (nonatomic, assign) RYGRRDateRange dateRange;
@property (nonatomic, assign) RYGRRSort sort;
@property (nonatomic, strong) UIBarButtonItem *filterItem;
@property (nonatomic, strong) UIBarButtonItem *moreItem;
@property (nonatomic, strong) UIBarButtonItem *deleteItem;
@property (nonatomic, strong) UIBarButtonItem *selectAllItem;
@property (nonatomic, assign) BOOL batching;
@end

@implementation RYGReadReceiptLogViewController

+ (void)load {
    [RYGNotificationCenter.shared setDefaultTapProvider:^void (^(void))(void) {
        if ([RYGActivityConfig globalModeForType:RYGActivityTypeRead] == RYGActivityModeOff) return (void (^)(void))nil;
        return ^{ [RYGReadReceiptLogViewController presentFromViewController:nil]; };
    } ownerVCClass:[RYGReadReceiptLogViewController class]
      forAction:RYG_NOTIF_READ_RECEIPT];
}

+ (void)presentFromViewController:(UIViewController *)presenter {
    [RYGLockGate presentLockedVC:[RYGReadReceiptLogViewController new] forGroup:RYGLockGroupActivityLog from:presenter];
}

- (void)viewDidLoad {
    [super viewDidLoad];
    [RYGHomeShortcutBadges clearActionID:@"read_receipts"];
    self.ownerPK = [RYGUtils currentUserPK];
    self.title = RYGLocalized(@"Activity log");
    self.view.backgroundColor = [RYGPopupChrome backgroundColor];

    self.tableView = [[UITableView alloc] initWithFrame:self.view.bounds style:UITableViewStyleInsetGrouped];
    self.tableView.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
    self.tableView.backgroundColor = UIColor.clearColor;
    self.tableView.rowHeight = 70;
    self.tableView.allowsMultipleSelectionDuringEditing = YES;
    self.tableView.dataSource = self; self.tableView.delegate = self;
    [self.tableView registerClass:[RYGRRGroupCell class] forCellReuseIdentifier:@"g"];
    [self.view addSubview:self.tableView];

    self.emptyLabel = [[UILabel alloc] initWithFrame:CGRectInset(self.view.bounds, 32, 0)];
    self.emptyLabel.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
    self.emptyLabel.numberOfLines = 0; self.emptyLabel.textAlignment = NSTextAlignmentCenter;
    self.emptyLabel.textColor = UIColor.secondaryLabelColor;
    self.emptyLabel.text = RYGLocalized(@"No activity yet.\nWhen someone reads your message or comes online, it shows up here.");
    [self.view addSubview:self.emptyLabel];

    self.search = [[UISearchController alloc] initWithSearchResultsController:nil];
    self.search.searchResultsUpdater = self;
    self.search.obscuresBackgroundDuringPresentation = NO;
    self.search.searchBar.placeholder = RYGLocalized(@"Search by username");
    self.navigationItem.searchController = self.search;
    self.navigationItem.hidesSearchBarWhenScrolling = NO;

    self.filterItem = [[UIBarButtonItem alloc] initWithImage:[UIImage systemImageNamed:@"line.3.horizontal.decrease.circle"] menu:[self filterMenu]];
    self.moreItem = [[UIBarButtonItem alloc] initWithImage:[UIImage systemImageNamed:@"ellipsis.circle"] menu:[self moreMenu]];
    self.navigationItem.rightBarButtonItems = @[self.moreItem, self.filterItem];

    self.deleteItem = [[UIBarButtonItem alloc] initWithTitle:RYGLocalized(@"Delete") style:UIBarButtonItemStylePlain target:self action:@selector(deleteSelected)];
    self.deleteItem.tintColor = UIColor.systemRedColor;
    self.selectAllItem = [[UIBarButtonItem alloc] initWithTitle:RYGLocalized(@"Select All") style:UIBarButtonItemStylePlain target:self action:@selector(toggleSelectAll)];

    [self reload];
    [NSNotificationCenter.defaultCenter addObserver:self selector:@selector(reload) name:RYGReadReceiptsDidChangeNotification object:nil];
    [NSNotificationCenter.defaultCenter addObserver:self selector:@selector(reload) name:RYGActivityLogDidChangeNotification object:nil];
}
- (void)dealloc { [NSNotificationCenter.defaultCenter removeObserver:self]; }

- (UIMenu *)filterMenu {
    __weak typeof(self) ws = self;
    UIAction *(^d)(NSString *, RYGRRDateRange) = ^(NSString *t, RYGRRDateRange r) {
        UIAction *a = [UIAction actionWithTitle:t image:nil identifier:nil handler:^(UIAction *x){ ws.dateRange = r; [ws applyFilter]; [ws refreshMenus]; }];
        a.state = ws.dateRange == r ? UIMenuElementStateOn : UIMenuElementStateOff; return a;
    };
    UIMenu *date = [UIMenu menuWithTitle:RYGLocalized(@"Date") image:[UIImage systemImageNamed:@"calendar"] identifier:nil options:UIMenuOptionsDisplayInline children:@[
        d(RYGLocalized(@"All time"), RYGRRDateAll), d(RYGLocalized(@"Today"), RYGRRDateToday), d(RYGLocalized(@"Last 7 days"), RYGRRDate7), d(RYGLocalized(@"Last 30 days"), RYGRRDate30) ]];
    UIAction *(^so)(NSString *, RYGRRSort) = ^(NSString *t, RYGRRSort s) {
        UIAction *a = [UIAction actionWithTitle:t image:nil identifier:nil handler:^(UIAction *x){ ws.sort = s; [ws applyFilter]; [ws refreshMenus]; }];
        a.state = ws.sort == s ? UIMenuElementStateOn : UIMenuElementStateOff; return a;
    };
    UIMenu *sort = [UIMenu menuWithTitle:RYGLocalized(@"Sort") image:[UIImage systemImageNamed:@"arrow.up.arrow.down"] identifier:nil options:UIMenuOptionsDisplayInline children:@[
        so(RYGLocalized(@"Most recent"), RYGRRSortRecent), so(RYGLocalized(@"Most reads"), RYGRRSortMostReads), so(RYGLocalized(@"Username"), RYGRRSortName) ]];
    return [UIMenu menuWithTitle:@"" children:@[date, sort]];
}
- (UIMenu *)moreMenu {
    __weak typeof(self) ws = self;
    UIAction *select = [UIAction actionWithTitle:RYGLocalized(@"Select") image:[UIImage systemImageNamed:@"checkmark.circle"] identifier:nil handler:^(UIAction *x){ [ws beginSelecting]; }];
    UIAction *refresh = [UIAction actionWithTitle:RYGLocalized(@"Refresh names & photos") image:[UIImage systemImageNamed:@"arrow.clockwise"] identifier:nil handler:^(UIAction *x){ [ws refreshMetadata]; }];
    UIAction *perPerson = [UIAction actionWithTitle:RYGLocalized(@"Per-person notifications") image:[UIImage systemImageNamed:@"person.crop.circle.badge.checkmark"] identifier:nil handler:^(UIAction *x){
        [ws.navigationController pushViewController:[RYGActivityMatrixViewController new] animated:YES];
    }];
    UIAction *ignored = [UIAction actionWithTitle:RYGLocalized(@"Ignored people & chats") image:[UIImage systemImageNamed:@"eye.slash"] identifier:nil handler:^(UIAction *x){
        RYGRRIgnoredViewController *v = [RYGRRIgnoredViewController new]; v.ownerPK = ws.ownerPK;
        [ws.navigationController pushViewController:v animated:YES];
    }];
    UIAction *clear = [UIAction actionWithTitle:RYGLocalized(@"Clear all records") image:[UIImage systemImageNamed:@"trash"] identifier:nil handler:^(UIAction *x){ [ws confirmReset]; }];
    clear.attributes = UIMenuElementAttributesDestructive;
    UIMenu *top = [UIMenu menuWithTitle:@"" image:nil identifier:nil options:UIMenuOptionsDisplayInline children:@[select]];
    return [UIMenu menuWithTitle:@"" children:@[top, refresh, perPerson, ignored, clear]];
}

- (void)refreshMetadata {
    NSString *owner = self.ownerPK;
    for (RYGReadReceiptGroup *g in [RYGReadReceiptStorage groupedByThreadForOwnerPK:owner]) {
        NSString *tid = g.threadId; BOOL grp = g.isGroup;
        if (!tid.length) continue;
        [RYGDirectThreadInfo fetchThreadId:tid ownerPK:owner completion:^(id thread) {
            if (!thread) return;
            if (grp) {
                NSDictionary *gi = [RYGDirectThreadInfo groupInfoForThread:thread viewerPK:owner];
                [RYGReadReceiptStorage applyThreadTitle:gi[@"name"] avatarURL:gi[@"image"] forThreadId:tid ownerPK:owner];
            }
            NSDictionary *parts = [RYGDirectThreadInfo participantsForThread:thread];
            [parts enumerateKeysAndObjectsUsingBlock:^(NSString *pk, NSDictionary *info, BOOL *stop) {
                [RYGReadReceiptStorage applyReaderUsername:info[@"username"] profilePicURL:info[@"profile_pic_url"] forReaderPK:pk ownerPK:owner];
                [RYGActivityLogStore applyUsername:info[@"username"] picURL:info[@"profile_pic_url"] forPK:pk ownerPK:owner];
            }];
        }];
    }
    for (NSString *pk in [RYGActivityLogStore peopleForOwnerPK:owner]) {
        NSString *un = rygDirectUserResolverUsernameForPK(pk);
        NSString *pic = rygDirectUserResolverProfilePicURLStringForPK(pk);
        if (un.length || pic.length) [RYGActivityLogStore applyUsername:un picURL:pic forPK:pk ownerPK:owner];
    }
    RYGNotifyInfo(RYG_NOTIF_GENERIC, RYGLocalized(@"Refreshing…"), RYGLocalized(@"Updating names and photos"));
}
- (void)refreshMenus { self.filterItem.menu = [self filterMenu]; }

- (NSArray<RYGActRow *> *)buildRows {
    NSString *owner = self.ownerPK;
    NSMutableDictionary<NSString *, RYGActRow *> *persons = [NSMutableDictionary dictionary];
    NSMutableArray<RYGActRow *> *groups = [NSMutableArray array];

    for (RYGReadReceiptGroup *g in [RYGReadReceiptStorage groupedByThreadForOwnerPK:owner]) {
        NSMutableArray<RYGActItem *> *reads = [NSMutableArray array];
        for (RYGReadReceipt *r in g.receipts) {
            RYGActItem *it = [RYGActItem new];
            it.kind = RYGActRead; it.date = r.readAt; it.text = r.messagePreview;
            if (g.isGroup) { it.who = r.readerUsername.length ? [@"@" stringByAppendingString:r.readerUsername] : r.readerPk; it.whoPic = r.readerProfilePicURL; }
            [reads addObject:it];
        }
        if (g.isGroup) {
            RYGActRow *row = [RYGActRow new];
            row.isGroup = YES; row.threadId = g.threadId; row.title = g.displayTitle;
            row.avatarURL = g.displayAvatarURL; row.items = reads; row.readCount = g.count;
            [groups addObject:row];
        } else {
            NSString *pk = g.readerPk; if (!pk.length) continue;
            RYGActRow *row = persons[pk] ?: [RYGActRow new];
            row.isGroup = NO; row.pk = pk;
            row.title = g.displayTitle; if (g.displayAvatarURL.length) row.avatarURL = g.displayAvatarURL;
            NSMutableArray *items = [(row.items ?: @[]) mutableCopy]; [items addObjectsFromArray:reads];
            row.items = items; row.readCount += g.count;
            persons[pk] = row;
        }
    }

    for (NSString *pk in [RYGActivityLogStore peopleForOwnerPK:owner]) {
        if (!pk.length) continue;
        RYGActRow *row = persons[pk];
        if (!row) {
            row = [RYGActRow new]; row.isGroup = NO; row.pk = pk;
            NSString *un = [RYGActivityLogStore usernameForPK:pk ownerPK:owner] ?: rygDirectUserResolverUsernameForPK(pk);
            row.title = un.length ? [@"@" stringByAppendingString:un] : pk;
            row.avatarURL = [RYGActivityLogStore picURLForPK:pk ownerPK:owner] ?: rygDirectUserResolverProfilePicURLStringForPK(pk);
        }
        NSMutableArray *items = [(row.items ?: @[]) mutableCopy];
        for (RYGActivityLogEvent *ev in [RYGActivityLogStore eventsForPK:pk ownerPK:owner]) {
            RYGActItem *it = [RYGActItem new];
            it.kind = ev.type == RYGActivityTypeOnline ? RYGActOnline : (ev.type == RYGActivityTypeOffline ? RYGActOffline : RYGActTyping);
            it.date = ev.at;
            [items addObject:it];
        }
        row.items = items;
        persons[pk] = row;
    }

    NSMutableArray<RYGActRow *> *all = [NSMutableArray arrayWithArray:groups];
    [all addObjectsFromArray:persons.allValues];
    for (RYGActRow *r in all)
        r.items = [r.items sortedArrayUsingComparator:^NSComparisonResult(RYGActItem *a, RYGActItem *b) { return [b.date compare:a.date]; }];
    return all;
}

- (void)reload {
    if (self.batching) return;
    self.allRows = [self buildRows];
    [self applyFilter];
}

- (BOOL)rowIgnored:(RYGActRow *)row {
    return row.isGroup ? [RYGReadReceiptStorage isThreadExcluded:row.threadId ownerPK:self.ownerPK]
                       : [RYGReadReceiptStorage isReaderExcluded:row.pk ownerPK:self.ownerPK];
}

- (void)applyFilter {
    NSString *q = self.search.searchBar.text.lowercaseString;
    NSMutableArray *out = [NSMutableArray array];
    for (RYGActRow *row in self.allRows) {
        if (!row.items.count) continue;
        if (q.length) {
            NSString *title = row.title.lowercaseString ?: @"";
            BOOL hit = [title containsString:q] || [(row.pk ?: @"") containsString:q];
            if (!hit && row.isGroup) for (RYGActItem *it in row.items)
                if ([(it.who.lowercaseString ?: @"") containsString:q]) { hit = YES; break; }
            if (!hit) continue;
        }
        if (!rrDateInRange(row.lastDate, self.dateRange)) continue;
        [out addObject:row];
    }
    if (self.sort == RYGRRSortMostReads)
        [out sortUsingComparator:^NSComparisonResult(RYGActRow *a, RYGActRow *b){ return [@(b.readCount) compare:@(a.readCount)]; }];
    else if (self.sort == RYGRRSortName)
        [out sortUsingComparator:^NSComparisonResult(RYGActRow *a, RYGActRow *b){ return [a.title caseInsensitiveCompare:b.title]; }];
    else
        [out sortUsingComparator:^NSComparisonResult(RYGActRow *a, RYGActRow *b){ return [b.lastDate compare:a.lastDate]; }];
    self.visible = out;
    self.emptyLabel.hidden = out.count > 0;
    if (out.count == 0 && self.allRows.count > 0)
        self.emptyLabel.text = RYGLocalized(@"Nothing matches your filters.");
    else
        self.emptyLabel.text = RYGLocalized(@"No activity yet.\nWhen someone reads your message or comes online, it shows up here.");
    [self.tableView reloadData];
    if (self.tableView.isEditing) [self updateEditUI];
}

- (void)updateSearchResultsForSearchController:(UISearchController *)searchController { [self applyFilter]; }

- (void)confirmReset {
    UIAlertController *a = [UIAlertController alertControllerWithTitle:RYGLocalized(@"Clear activity log?") message:RYGLocalized(@"This removes all recorded activity on this device.") preferredStyle:UIAlertControllerStyleAlert];
    [a addAction:[UIAlertAction actionWithTitle:RYGLocalized(@"Cancel") style:UIAlertActionStyleCancel handler:nil]];
    [a addAction:[UIAlertAction actionWithTitle:RYGLocalized(@"Clear") style:UIAlertActionStyleDestructive handler:^(UIAlertAction *x) {
        [RYGReadReceiptStorage resetForOwnerPK:self.ownerPK];
        [RYGActivityLogStore resetForOwnerPK:self.ownerPK];
    }]];
    [self presentViewController:a animated:YES completion:nil];
}

#pragma mark - Multi-select

- (void)deleteRowFully:(RYGActRow *)row {
    NSString *owner = self.ownerPK;
    if (row.isGroup) [RYGReadReceiptStorage deleteReceiptsForThreadId:row.threadId ownerPK:owner];
    else { [RYGReadReceiptStorage deleteReceiptsForReaderPK:row.pk ownerPK:owner]; [RYGActivityLogStore deleteEventsForPK:row.pk ownerPK:owner]; }
}

- (void)beginSelecting { [self setEditing:YES animated:YES]; }
- (void)endSelecting { [self setEditing:NO animated:YES]; }

- (void)setEditing:(BOOL)editing animated:(BOOL)animated {
    [super setEditing:editing animated:animated];
    [self.tableView setEditing:editing animated:animated];
    if (editing) {
        self.navigationItem.rightBarButtonItems = @[[[UIBarButtonItem alloc] initWithBarButtonSystemItem:UIBarButtonSystemItemDone target:self action:@selector(endSelecting)]];
        UIBarButtonItem *flex = [[UIBarButtonItem alloc] initWithBarButtonSystemItem:UIBarButtonSystemItemFlexibleSpace target:nil action:nil];
        self.toolbarItems = @[self.deleteItem, flex, self.selectAllItem];
        self.navigationController.toolbarHidden = NO;
        self.search.searchBar.userInteractionEnabled = NO;
    } else {
        self.navigationItem.rightBarButtonItems = @[self.moreItem, self.filterItem];
        self.navigationController.toolbarHidden = YES;
        self.search.searchBar.userInteractionEnabled = YES;
    }
    [self updateEditUI];
}

- (void)updateEditUI {
    if (!self.tableView.isEditing) { self.title = RYGLocalized(@"Activity log"); return; }
    NSUInteger n = self.tableView.indexPathsForSelectedRows.count;
    self.title = n ? [NSString stringWithFormat:RYGLocalized(@"%lu selected"), (unsigned long)n] : RYGLocalized(@"Select");
    self.deleteItem.enabled = n > 0;
    self.deleteItem.title = n ? [NSString stringWithFormat:RYGLocalized(@"Delete (%lu)"), (unsigned long)n] : RYGLocalized(@"Delete");
    BOOL all = n > 0 && n == self.visible.count;
    self.selectAllItem.title = all ? RYGLocalized(@"Deselect All") : RYGLocalized(@"Select All");
}

- (void)toggleSelectAll {
    BOOL all = self.tableView.indexPathsForSelectedRows.count == self.visible.count;
    if (all) {
        for (NSIndexPath *ip in self.tableView.indexPathsForSelectedRows.copy) [self.tableView deselectRowAtIndexPath:ip animated:NO];
    } else {
        for (NSInteger i = 0; i < (NSInteger)self.visible.count; i++)
            [self.tableView selectRowAtIndexPath:[NSIndexPath indexPathForRow:i inSection:0] animated:NO scrollPosition:UITableViewScrollPositionNone];
    }
    [self updateEditUI];
}

- (void)deleteSelected {
    NSArray<NSIndexPath *> *sel = self.tableView.indexPathsForSelectedRows;
    if (!sel.count) return;
    NSMutableArray<RYGActRow *> *rows = [NSMutableArray array];
    for (NSIndexPath *ip in sel) if (ip.row < (NSInteger)self.visible.count) [rows addObject:self.visible[ip.row]];
    NSString *msg = RYGLocalized(@"Delete all records for the selected chats? This can't be undone.");
    UIAlertController *a = [UIAlertController alertControllerWithTitle:RYGLocalized(@"Delete records") message:msg preferredStyle:UIAlertControllerStyleAlert];
    [a addAction:[UIAlertAction actionWithTitle:RYGLocalized(@"Cancel") style:UIAlertActionStyleCancel handler:nil]];
    [a addAction:[UIAlertAction actionWithTitle:RYGLocalized(@"Delete") style:UIAlertActionStyleDestructive handler:^(UIAlertAction *x) {
        self.batching = YES;
        for (RYGActRow *row in rows) [self deleteRowFully:row];
        self.batching = NO;
        [self endSelecting];
        [self reload];
    }]];
    [self presentViewController:a animated:YES completion:nil];
}

- (NSString *)subtitleForRow:(RYGActRow *)row {
    if (row.isGroup) {
        NSUInteger members = row.distinctReaderCount;
        NSString *fmt = members == 1 ? RYGLocalized(@"%lu reads · %lu reader · %@") : RYGLocalized(@"%lu reads · %lu readers · %@");
        return [NSString stringWithFormat:fmt, (unsigned long)row.readCount, (unsigned long)members, rrRelative(row.lastDate)];
    }
    RYGActItem *l = row.latest;
    if (!l) return @"";
    return [NSString stringWithFormat:@"%@ · %@", kindLabel(l.kind), rrRelative(l.date)];
}

- (NSInteger)tableView:(UITableView *)t numberOfRowsInSection:(NSInteger)s { return self.visible.count; }

- (UITableViewCell *)tableView:(UITableView *)t cellForRowAtIndexPath:(NSIndexPath *)ip {
    RYGRRGroupCell *c = [t dequeueReusableCellWithIdentifier:@"g" forIndexPath:ip];
    RYGActRow *row = self.visible[ip.row];
    BOOL ignored = [self rowIgnored:row];
    c.titleLbl.text = row.title;
    NSString *base = [self subtitleForRow:row];
    c.subLbl.text = ignored ? [RYGLocalized(@"Ignored") stringByAppendingFormat:@" · %@", base] : base;
    NSUInteger unseen = ignored ? 0 : rrUnseenForRow(row, self.ownerPK);
    c.countLabel.text = [NSString stringWithFormat:@"%lu", (unsigned long)unseen];
    c.countBadge.hidden = unseen == 0;
    c.mutedIcon.hidden = !ignored;
    c.contentView.alpha = ignored ? 0.5 : 1.0;
    c.accessoryType = UITableViewCellAccessoryDisclosureIndicator;
    if (row.isGroup && !row.avatarURL.length) { c.avatar.image = [UIImage systemImageNamed:@"person.2.circle.fill"]; c.avatar.tintColor = UIColor.systemGray2Color; c.avatar.accessibilityValue = nil; }
    else rrLoadAvatar(c.avatar, row.avatarURL, row.pk);
    return c;
}

- (void)tableView:(UITableView *)t didSelectRowAtIndexPath:(NSIndexPath *)ip {
    if (t.isEditing) { [self updateEditUI]; return; }
    [t deselectRowAtIndexPath:ip animated:YES];
    RYGActRow *row = self.visible[ip.row];
    rrMarkSeen(self.ownerPK, row.identifier);
    [t reloadRowsAtIndexPaths:@[ip] withRowAnimation:UITableViewRowAnimationNone];
    RYGRRDetailViewController *d = [RYGRRDetailViewController new];
    d.row = row; d.ownerPK = self.ownerPK;
    [self.navigationController pushViewController:d animated:YES];
}

- (void)tableView:(UITableView *)t didDeselectRowAtIndexPath:(NSIndexPath *)ip {
    if (t.isEditing) [self updateEditUI];
}

- (UIContextMenuConfiguration *)tableView:(UITableView *)t contextMenuConfigurationForRowAtIndexPath:(NSIndexPath *)ip point:(CGPoint)point {
    RYGActRow *row = self.visible[ip.row];
    NSString *owner = self.ownerPK;
    NSString *who = row.title;
    BOOL ignored = [self rowIgnored:row];
    __weak typeof(self) ws = self;
    return [UIContextMenuConfiguration configurationWithIdentifier:nil previewProvider:nil actionProvider:^UIMenu *(NSArray *suggested) {
        NSMutableArray *actions = [NSMutableArray array];
        if (!row.isGroup && row.pk.length) {
            NSString *rpk = row.pk, *run = [row.title hasPrefix:@"@"] ? [row.title substringFromIndex:1] : nil;
            UIAction *cfg = [UIAction actionWithTitle:RYGLocalized(@"Customise notifications") image:[UIImage systemImageNamed:@"bell.badge"] identifier:nil handler:^(UIAction *action) {
                [ws.navigationController pushViewController:[[RYGActivityPersonViewController alloc] initWithPK:rpk username:run] animated:YES];
            }];
            [actions addObject:cfg];
        }
        UIAction *excl = [UIAction actionWithTitle:ignored ? RYGLocalized(@"Resume logging") : [NSString stringWithFormat:RYGLocalized(@"Stop logging %@"), who]
            image:[UIImage systemImageNamed:ignored ? @"eye" : @"eye.slash"] identifier:nil handler:^(UIAction *action) {
            if (row.isGroup) [RYGReadReceiptStorage setThread:row.threadId excluded:!ignored ownerPK:owner];
            else [RYGReadReceiptStorage setReader:row.pk excluded:!ignored ownerPK:owner];
        }];
        UIAction *del = [UIAction actionWithTitle:RYGLocalized(@"Delete records") image:[UIImage systemImageNamed:@"trash"] identifier:nil handler:^(UIAction *action) {
            if (row.isGroup) [RYGReadReceiptStorage deleteReceiptsForThreadId:row.threadId ownerPK:owner];
            else { [RYGReadReceiptStorage deleteReceiptsForReaderPK:row.pk ownerPK:owner]; [RYGActivityLogStore deleteEventsForPK:row.pk ownerPK:owner]; }
        }];
        del.attributes = UIMenuElementAttributesDestructive;
        [actions addObject:excl];
        [actions addObject:del];
        return [UIMenu menuWithTitle:who children:actions];
    }];
}

@end
