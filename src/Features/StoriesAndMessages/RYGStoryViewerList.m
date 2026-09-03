#import "RYGStoryViewerList.h"
#import "RYGStoryViewerFilter.h"
#import "RYGStoryViewerSortSheet.h"
#import "RYGStoryViewerPins.h"
#import "../../Networking/RYGInstagramAPI.h"
#import "../../RYGProfileOpener.h"
#import "../../Utils.h"
#import "../../UI/RYGPopupChrome.h"
#import "../../UI/RYGAvatarLoader.h"
#import <objc/runtime.h>

@class RYGStoryViewerListView;

#pragma mark - session cache

// Full fetched list per media, reused on reopen while fresh. Short TTL — a story's
// viewer list changes fast. Manual reload always refetches; only rapid spam is
// blocked (or a fetch already in flight).
static const NSTimeInterval kRYGViewerCacheTTL = 45.0;
static const NSTimeInterval kRYGViewerReloadThrottle = 2.0;

static NSMutableDictionary<NSString *, NSMutableDictionary *> *rygViewerCache(void) {
    static NSMutableDictionary *d; static dispatch_once_t o;
    dispatch_once(&o, ^{ d = [NSMutableDictionary dictionary]; });
    return d;
}

#pragma mark - cell

@interface RYGViewerCell : UITableViewCell
@property (nonatomic, strong) UIImageView *avatarView;
@property (nonatomic, strong) UILabel *usernameLabel;
@property (nonatomic, strong) UIImageView *verifiedView;
@property (nonatomic, strong) UILabel *fullNameLabel;
@property (nonatomic, strong) UIView *likedBadge;
@property (nonatomic, strong) UIImageView *likedView;
@property (nonatomic, strong) UILabel *emojiLabel;
@property (nonatomic, strong) UIImageView *pinnedView;
- (void)configureWithViewer:(NSDictionary *)v pinned:(BOOL)pinned;
@end

@implementation RYGViewerCell

- (instancetype)initWithStyle:(UITableViewCellStyle)style reuseIdentifier:(NSString *)rid {
    if (!(self = [super initWithStyle:style reuseIdentifier:rid])) return nil;
    self.backgroundColor = UIColor.clearColor;
    UIView *sel = [UIView new];
    sel.backgroundColor = [UIColor.systemGrayColor colorWithAlphaComponent:0.14];
    self.selectedBackgroundView = sel;

    _avatarView = [UIImageView new];
    _avatarView.contentMode = UIViewContentModeScaleAspectFill;
    _avatarView.clipsToBounds = YES;
    _avatarView.layer.cornerRadius = 24;
    _avatarView.backgroundColor = [UIColor.systemGrayColor colorWithAlphaComponent:0.2];
    _avatarView.translatesAutoresizingMaskIntoConstraints = NO;

    _usernameLabel = [UILabel new];
    _usernameLabel.font = [UIFont systemFontOfSize:15 weight:UIFontWeightSemibold];
    _usernameLabel.textColor = UIColor.labelColor;
    _usernameLabel.lineBreakMode = NSLineBreakByTruncatingTail;
    [_usernameLabel setContentCompressionResistancePriority:UILayoutPriorityDefaultLow - 1 forAxis:UILayoutConstraintAxisHorizontal];
    [_usernameLabel setContentHuggingPriority:UILayoutPriorityDefaultLow forAxis:UILayoutConstraintAxisHorizontal];

    _verifiedView = [[UIImageView alloc] initWithImage:[UIImage systemImageNamed:@"checkmark.seal.fill"]];
    _verifiedView.tintColor = UIColor.systemBlueColor;
    _verifiedView.contentMode = UIViewContentModeScaleAspectFit;
    [_verifiedView setContentHuggingPriority:UILayoutPriorityRequired forAxis:UILayoutConstraintAxisHorizontal];
    [_verifiedView setContentCompressionResistancePriority:UILayoutPriorityRequired forAxis:UILayoutConstraintAxisHorizontal];

    _fullNameLabel = [UILabel new];
    _fullNameLabel.font = [UIFont systemFontOfSize:13];
    _fullNameLabel.textColor = UIColor.secondaryLabelColor;
    _fullNameLabel.lineBreakMode = NSLineBreakByTruncatingTail;

    _likedBadge = [UIView new];
    _likedBadge.backgroundColor = UIColor.systemBackgroundColor;
    _likedBadge.layer.cornerRadius = 10;
    _likedBadge.translatesAutoresizingMaskIntoConstraints = NO;
    _likedView = [[UIImageView alloc] initWithImage:[[UIImage systemImageNamed:@"heart.fill"] imageWithConfiguration:[UIImageSymbolConfiguration configurationWithPointSize:11 weight:UIImageSymbolWeightBold]]];
    _likedView.tintColor = UIColor.systemRedColor;
    _likedView.contentMode = UIViewContentModeScaleAspectFit;
    _likedView.translatesAutoresizingMaskIntoConstraints = NO;
    [_likedBadge addSubview:_likedView];
    _emojiLabel = [UILabel new];
    _emojiLabel.font = [UIFont systemFontOfSize:13];
    _emojiLabel.textAlignment = NSTextAlignmentCenter;
    _emojiLabel.hidden = YES;
    _emojiLabel.translatesAutoresizingMaskIntoConstraints = NO;
    [_likedBadge addSubview:_emojiLabel];

    _pinnedView = [[UIImageView alloc] initWithImage:[UIImage systemImageNamed:@"pin.fill"]];
    _pinnedView.tintColor = UIColor.systemBlueColor;
    _pinnedView.contentMode = UIViewContentModeScaleAspectFit;
    _pinnedView.translatesAutoresizingMaskIntoConstraints = NO;
    [_pinnedView setContentHuggingPriority:UILayoutPriorityRequired forAxis:UILayoutConstraintAxisHorizontal];
    [_pinnedView setContentCompressionResistancePriority:UILayoutPriorityRequired forAxis:UILayoutConstraintAxisHorizontal];

    UIStackView *nameRow = [[UIStackView alloc] initWithArrangedSubviews:@[_usernameLabel, _verifiedView]];
    nameRow.axis = UILayoutConstraintAxisHorizontal;
    nameRow.spacing = 4;
    nameRow.alignment = UIStackViewAlignmentCenter;

    UIStackView *text = [[UIStackView alloc] initWithArrangedSubviews:@[nameRow, _fullNameLabel]];
    text.axis = UILayoutConstraintAxisVertical;
    text.spacing = 2;
    text.alignment = UIStackViewAlignmentLeading;
    text.translatesAutoresizingMaskIntoConstraints = NO;

    [self.contentView addSubview:_avatarView];
    [self.contentView addSubview:_likedBadge];
    [self.contentView addSubview:text];
    [self.contentView addSubview:_pinnedView];

    [NSLayoutConstraint activateConstraints:@[
        [_avatarView.leadingAnchor constraintEqualToAnchor:self.contentView.leadingAnchor constant:16],
        [_avatarView.centerYAnchor constraintEqualToAnchor:self.contentView.centerYAnchor],
        [_avatarView.widthAnchor constraintEqualToConstant:48],
        [_avatarView.heightAnchor constraintEqualToConstant:48],

        [_likedBadge.widthAnchor constraintEqualToConstant:20],
        [_likedBadge.heightAnchor constraintEqualToConstant:20],
        [_likedBadge.centerXAnchor constraintEqualToAnchor:_avatarView.trailingAnchor constant:-3],
        [_likedBadge.centerYAnchor constraintEqualToAnchor:_avatarView.bottomAnchor constant:-3],
        [_likedView.centerXAnchor constraintEqualToAnchor:_likedBadge.centerXAnchor],
        [_likedView.centerYAnchor constraintEqualToAnchor:_likedBadge.centerYAnchor],
        [_emojiLabel.centerXAnchor constraintEqualToAnchor:_likedBadge.centerXAnchor],
        [_emojiLabel.centerYAnchor constraintEqualToAnchor:_likedBadge.centerYAnchor],

        [text.leadingAnchor constraintEqualToAnchor:_avatarView.trailingAnchor constant:12],
        [text.centerYAnchor constraintEqualToAnchor:self.contentView.centerYAnchor],
        [text.trailingAnchor constraintLessThanOrEqualToAnchor:_pinnedView.leadingAnchor constant:-12],

        [_verifiedView.widthAnchor constraintEqualToConstant:13],
        [_verifiedView.heightAnchor constraintEqualToConstant:13],
        [_pinnedView.widthAnchor constraintEqualToConstant:19],
        [_pinnedView.heightAnchor constraintEqualToConstant:19],
        [_pinnedView.trailingAnchor constraintEqualToAnchor:self.contentView.trailingAnchor constant:-18],
        [_pinnedView.centerYAnchor constraintEqualToAnchor:self.contentView.centerYAnchor],

        [self.contentView.heightAnchor constraintGreaterThanOrEqualToConstant:64],
    ]];
    return self;
}

- (void)configureWithViewer:(NSDictionary *)v pinned:(BOOL)pinned {
    NSString *uname = v[@"username"];
    NSString *full = v[@"full_name"];
    NSString *emoji = v[@"reaction_emoji"];
    BOOL hasU = uname.length > 0;
    self.usernameLabel.text = hasU ? uname : (full.length ? full : RYGLocalized(@"Unavailable"));
    self.fullNameLabel.text = hasU ? full : nil;
    self.fullNameLabel.hidden = !(hasU && full.length);
    self.verifiedView.hidden = ![v[@"is_verified"] boolValue];
    BOOL reacted = emoji.length > 0;
    BOOL liked = [v[@"liked"] boolValue];
    self.emojiLabel.text = reacted ? emoji : nil;
    self.emojiLabel.hidden = !reacted;
    self.likedView.hidden = reacted;
    self.likedBadge.hidden = !(reacted || liked);
    self.pinnedView.hidden = !pinned;
    self.avatarView.image = [RYGAvatarLoader avatarForURLString:v[@"profile_pic_url"] group:NO];
}

- (void)prepareForReuse {
    [super prepareForReuse];
    self.avatarView.image = nil;
}

// A cancelled touch leaves the table's highlighted index path stuck set.
- (void)setHighlighted:(BOOL)highlighted animated:(BOOL)animated {}

@end

#pragma mark - list view

@interface RYGStoryViewerListView () <UITableViewDataSource, UITableViewDelegate, UISearchBarDelegate>
@property (nonatomic, copy) NSString *searchQuery;
@property (nonatomic, copy) NSString *mediaID;
@property (nonatomic, strong) UISearchBar *searchBar;
@property (nonatomic, strong) UIButton *filterButton;
@property (nonatomic, strong) UITableView *tableView;
@property (nonatomic, strong) NSMutableArray<NSDictionary *> *all;   // server order = recent-viewer-first
@property (nonatomic, strong) NSArray<NSDictionary *> *rows;
@property (nonatomic, copy) NSString *cursor;
@property (nonatomic, assign) BOOL loading;
@property (nonatomic, assign) BOOL reachedEnd;
@property (nonatomic, assign) BOOL didStart;
@property (nonatomic, assign) NSInteger total;
@property (nonatomic, strong) UIActivityIndicatorView *spinner;
@property (nonatomic, strong) UIActivityIndicatorView *bigSpinner;
@property (nonatomic, strong) UILabel *emptyLabel;
@property (nonatomic, assign) BOOL firstPageLoaded;
@end

@implementation RYGStoryViewerListView

- (instancetype)initWithMediaID:(NSString *)mediaID {
    if (!(self = [super initWithFrame:CGRectZero])) return nil;
    _mediaID = [mediaID copy];
    _all = [NSMutableArray array];
    _rows = @[];
    _searchQuery = @"";

    _searchBar = [UISearchBar new];
    _searchBar.placeholder = RYGLocalized(@"Search viewers");
    _searchBar.delegate = self;
    _searchBar.searchBarStyle = UISearchBarStyleMinimal;
    _searchBar.autocapitalizationType = UITextAutocapitalizationTypeNone;
    _searchBar.autocorrectionType = UITextAutocorrectionTypeNo;
    _searchBar.backgroundColor = UIColor.clearColor;
    _searchBar.translatesAutoresizingMaskIntoConstraints = NO;
    [self addSubview:_searchBar];

    UIImageSymbolConfiguration *cfg = [UIImageSymbolConfiguration configurationWithPointSize:21 weight:UIImageSymbolWeightRegular];

    _filterButton = [UIButton buttonWithType:UIButtonTypeSystem];
    [_filterButton setImage:[[UIImage systemImageNamed:@"line.3.horizontal.decrease.circle"] imageWithConfiguration:cfg] forState:UIControlStateNormal];
    _filterButton.tintColor = UIColor.labelColor;
    [_filterButton addTarget:self action:@selector(openFilters) forControlEvents:UIControlEventTouchUpInside];
    _filterButton.translatesAutoresizingMaskIntoConstraints = NO;
    [self addSubview:_filterButton];

    _tableView = [[UITableView alloc] initWithFrame:CGRectZero style:UITableViewStylePlain];
    _tableView.dataSource = self;
    _tableView.delegate = self;
    _tableView.backgroundColor = UIColor.clearColor;
    _tableView.separatorStyle = UITableViewCellSeparatorStyleNone;
    _tableView.rowHeight = 60;
    _tableView.keyboardDismissMode = UIScrollViewKeyboardDismissModeOnDrag;
    [_tableView registerClass:RYGViewerCell.class forCellReuseIdentifier:@"v"];
    _tableView.translatesAutoresizingMaskIntoConstraints = NO;
    [self addSubview:_tableView];

    _emptyLabel = [UILabel new];
    _emptyLabel.font = [UIFont systemFontOfSize:15];
    _emptyLabel.textColor = UIColor.secondaryLabelColor;
    _emptyLabel.textAlignment = NSTextAlignmentCenter;
    _emptyLabel.numberOfLines = 0;
    _emptyLabel.hidden = YES;
    _emptyLabel.translatesAutoresizingMaskIntoConstraints = NO;
    [self addSubview:_emptyLabel];

    [NSLayoutConstraint activateConstraints:@[
        [_searchBar.topAnchor constraintEqualToAnchor:self.topAnchor constant:4],
        [_searchBar.leadingAnchor constraintEqualToAnchor:self.leadingAnchor constant:4],
        [_searchBar.trailingAnchor constraintEqualToAnchor:_filterButton.leadingAnchor constant:-2],
        [_filterButton.centerYAnchor constraintEqualToAnchor:_searchBar.centerYAnchor],
        [_filterButton.trailingAnchor constraintEqualToAnchor:self.trailingAnchor constant:-14],
        [_filterButton.widthAnchor constraintEqualToConstant:32],

        [_tableView.topAnchor constraintEqualToAnchor:_searchBar.bottomAnchor constant:2],
        [_tableView.leadingAnchor constraintEqualToAnchor:self.leadingAnchor],
        [_tableView.trailingAnchor constraintEqualToAnchor:self.trailingAnchor],
        [_tableView.bottomAnchor constraintEqualToAnchor:self.bottomAnchor],
        [_emptyLabel.centerXAnchor constraintEqualToAnchor:self.centerXAnchor],
        [_emptyLabel.centerYAnchor constraintEqualToAnchor:self.centerYAnchor constant:-40],
        [_emptyLabel.widthAnchor constraintLessThanOrEqualToAnchor:self.widthAnchor constant:-64],
    ]];

    _spinner = [[UIActivityIndicatorView alloc] initWithActivityIndicatorStyle:UIActivityIndicatorViewStyleMedium];
    _spinner.hidesWhenStopped = YES;
    _tableView.tableFooterView = _spinner;

    _bigSpinner = [[UIActivityIndicatorView alloc] initWithActivityIndicatorStyle:UIActivityIndicatorViewStyleLarge];
    _bigSpinner.hidesWhenStopped = YES;
    _bigSpinner.translatesAutoresizingMaskIntoConstraints = NO;
    [self addSubview:_bigSpinner];
    [_bigSpinner startAnimating];
    [NSLayoutConstraint activateConstraints:@[
        [_bigSpinner.centerXAnchor constraintEqualToAnchor:self.centerXAnchor],
        [_bigSpinner.centerYAnchor constraintEqualToAnchor:self.centerYAnchor constant:-30],
    ]];

    UILongPressGestureRecognizer *lp = [[UILongPressGestureRecognizer alloc] initWithTarget:self action:@selector(handleLongPress:)];
    lp.minimumPressDuration = 0.35;
    [_tableView addGestureRecognizer:lp];

    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(avatarLoaded) name:RYGAvatarLoadedNotification object:nil];

    NSMutableDictionary *c = rygViewerCache()[_mediaID];
    NSDate *ts = c[@"ts"];
    if (c && ts && [[NSDate date] timeIntervalSinceDate:ts] < kRYGViewerCacheTTL) {
        [_all addObjectsFromArray:c[@"viewers"]];
        _cursor = [c[@"cursor"] length] ? c[@"cursor"] : nil;
        _reachedEnd = [c[@"end"] boolValue];
        _total = [c[@"total"] integerValue];
        _firstPageLoaded = YES;
        [_bigSpinner stopAnimating];
    }
    return self;
}

- (void)dealloc { [[NSNotificationCenter defaultCenter] removeObserver:self]; }

- (void)avatarLoaded {
    for (RYGViewerCell *cell in self.tableView.visibleCells) {
        NSIndexPath *ip = [self.tableView indexPathForCell:cell];
        NSDictionary *v = ip ? [self viewerAt:ip] : nil;
        if (v) cell.avatarView.image = [RYGAvatarLoader avatarForURLString:v[@"profile_pic_url"] group:NO];
    }
}

- (void)handleLongPress:(UILongPressGestureRecognizer *)gr {
    if (gr.state != UIGestureRecognizerStateBegan) return;
    NSIndexPath *ip = [self.tableView indexPathForRowAtPoint:[gr locationInView:self.tableView]];
    NSDictionary *v = ip ? [self viewerAt:ip] : nil;
    NSString *pk = v[@"pk"];
    if (!pk.length) return;
    BOOL nowPinned = [RYGStoryViewerPins togglePK:pk entry:@{
        @"pk": pk, @"username": v[@"username"] ?: @"", @"fullName": v[@"full_name"] ?: @"", @"avatarURL": v[@"profile_pic_url"] ?: @""
    }];
    [[[UIImpactFeedbackGenerator alloc] initWithStyle:UIImpactFeedbackStyleMedium] impactOccurred];
    NSString *uname = v[@"username"];
    RYGNotifySuccess(RYG_NOTIF_PIN_STORY_VIEWER,
        nowPinned ? RYGLocalized(@"Viewer pinned") : RYGLocalized(@"Viewer unpinned"),
        uname.length ? [@"@" stringByAppendingString:uname] : nil);
    [self applyFilters];
}

- (void)didMoveToWindow {
    [super didMoveToWindow];
    if (!self.window || self.didStart) return;
    self.didStart = YES;
    if (self.firstPageLoaded) [self applyFilters];   // served from cache
    else [self loadNextPage];
}

#pragma mark data

- (void)loadNextPage {
    if (self.loading || self.reachedEnd) return;
    self.loading = YES;
    if (self.all.count) [self.spinner startAnimating];   // footer spinner for pages; the big spinner covers the first load
    __weak typeof(self) w = self;
    [RYGInstagramAPI fetchStoryViewersPageForMediaID:self.mediaID cursor:self.cursor completion:^(NSArray<NSDictionary *> *viewers, NSString *nextCursor, NSInteger total, NSError *error) {
        typeof(self) s = w; if (!s) return;
        s.loading = NO;
        s.firstPageLoaded = YES;
        [s.bigSpinner stopAnimating];
        if (total > s.total) s.total = total;
        [s.all addObjectsFromArray:viewers];
        s.cursor = nextCursor;
        if (!nextCursor.length) { s.reachedEnd = YES; [s.spinner stopAnimating]; }
        [s writeCache];
        // While searching we page to full coverage; defer the re-filter to the last page.
        if (s.searchQuery.length && !s.reachedEnd) [s loadNextPage];
        else [s applyFilters];
    }];
}

- (void)writeCache {
    if (!self.mediaID.length) return;
    rygViewerCache()[self.mediaID] = [@{
        @"viewers": [self.all copy],
        @"cursor": self.cursor ?: @"",
        @"end": @(self.reachedEnd),
        @"total": @(self.total),
        @"ts": [NSDate date],
    } mutableCopy];
}

- (void)reload {
    NSDate *ts = rygViewerCache()[self.mediaID][@"ts"];
    if (self.loading || (ts && [[NSDate date] timeIntervalSinceDate:ts] < kRYGViewerReloadThrottle)) {
        [[[UIImpactFeedbackGenerator alloc] initWithStyle:UIImpactFeedbackStyleRigid] impactOccurred];
        return;   // throttled — recently refreshed
    }
    [rygViewerCache() removeObjectForKey:self.mediaID];
    [self.all removeAllObjects];
    self.rows = @[];
    self.cursor = nil;
    self.reachedEnd = NO;
    self.firstPageLoaded = NO;
    self.total = 0;
    [self.tableView reloadData];
    [self.bigSpinner startAnimating];
    [self loadNextPage];
}

- (void)applyFilters {
    RYGSVFilter filter = rygSVFilter();
    RYGSVSort sortKey = rygSVSort();
    BOOL reverse = rygSVReverse();
    NSString *q = self.searchQuery ?: @"";

    NSMutableArray *pinned = [NSMutableArray array];
    NSMutableArray *rest = [NSMutableArray array];
    NSInteger idx = 0;
    for (NSDictionary *v in self.all) {
        NSString *pk = v[@"pk"];
        BOOL isPinned = pk.length && [RYGStoryViewerPins isPinned:pk];
        RYGSVAttr a = (RYGSVAttr){ [v[@"following"] boolValue], [v[@"followed_by"] boolValue], [v[@"is_verified"] boolValue], ([v[@"liked"] boolValue] || [v[@"reaction_emoji"] length] > 0) };

        BOOL pass = (filter & RYGSVFilterPinned) ? (isPinned && rygSVPassesNonPinned(filter, a)) : (isPinned || rygSVPassesNonPinned(filter, a));
        if (!pass) { idx++; continue; }
        if (q.length) {
            NSString *uname = v[@"username"] ?: @"", *full = v[@"full_name"] ?: @"";
            if ([uname rangeOfString:q options:NSCaseInsensitiveSearch].location == NSNotFound &&
                [full rangeOfString:q options:NSCaseInsensitiveSearch].location == NSNotFound) { idx++; continue; }
        }
        NSMutableDictionary *d = [v mutableCopy];
        d[@"_i"] = @(idx++);
        d[@"_rank"] = isPinned ? @([RYGStoryViewerPins rankOfPK:pk]) : @(NSNotFound);
        [(isPinned ? pinned : rest) addObject:d];
    }

    [pinned sortUsingComparator:^NSComparisonResult(NSDictionary *x, NSDictionary *y) { return [x[@"_rank"] compare:y[@"_rank"]]; }];

    NSString *boolKey = nil;
    switch (sortKey) {
        case RYGSVSortVerified:  boolKey = @"is_verified"; break;
        case RYGSVSortMutual:    boolKey = @"_mutual";     break;
        case RYGSVSortFollowsMe: boolKey = @"followed_by"; break;
        case RYGSVSortFollowing: boolKey = @"following";   break;
        case RYGSVSortReacted:   boolKey = @"_reacted";    break;
        default: break;
    }
    if (sortKey == RYGSVSortMutual) for (NSMutableDictionary *d in rest) d[@"_mutual"] = @([d[@"following"] boolValue] && [d[@"followed_by"] boolValue]);
    if (sortKey == RYGSVSortReacted) for (NSMutableDictionary *d in rest) d[@"_reacted"] = @([d[@"liked"] boolValue] || [d[@"reaction_emoji"] length] > 0);

    if (sortKey == RYGSVSortName) {
        [rest sortUsingComparator:^NSComparisonResult(NSDictionary *x, NSDictionary *y) {
            NSComparisonResult c = [(x[@"username"] ?: @"") caseInsensitiveCompare:(y[@"username"] ?: @"")];
            if (c == NSOrderedSame) return [x[@"_i"] compare:y[@"_i"]];
            return reverse ? (NSComparisonResult)(-c) : c;
        }];
    } else if (sortKey != RYGSVSortDefault) {
        [rest sortUsingComparator:^NSComparisonResult(NSDictionary *x, NSDictionary *y) {
            BOOL bx = [x[boolKey] boolValue], by = [y[boolKey] boolValue];
            NSComparisonResult c = (bx == by) ? NSOrderedSame : (bx ? NSOrderedAscending : NSOrderedDescending);
            if (c == NSOrderedSame) return [x[@"_i"] compare:y[@"_i"]];
            return reverse ? (NSComparisonResult)(-c) : c;
        }];
    } else if (reverse) {
        rest = [[[rest reverseObjectEnumerator] allObjects] mutableCopy];
    }

    NSMutableArray *out = [NSMutableArray arrayWithCapacity:pinned.count + rest.count];
    [out addObjectsFromArray:pinned];
    [out addObjectsFromArray:rest];
    self.rows = out;

    [self.tableView reloadData];
    [self updateEmptyState];
    [self updateFilterButtonState];
}

- (void)setSearchQuery:(NSString *)searchQuery {
    _searchQuery = [searchQuery copy] ?: @"";
    [self applyFilters];
    if (_searchQuery.length && !self.reachedEnd && !self.loading) [self loadNextPage];
}

- (void)updateEmptyState {
    BOOL empty = self.rows.count == 0 && self.firstPageLoaded && !self.loading;
    self.emptyLabel.hidden = !empty;
    if (empty) self.emptyLabel.text = self.searchQuery.length ? RYGLocalized(@"No matching viewers") : RYGLocalized(@"No viewers match these filters");
}

#pragma mark table

- (NSDictionary *)viewerAt:(NSIndexPath *)ip {
    return ip.row < (NSInteger)self.rows.count ? self.rows[ip.row] : nil;
}

- (NSInteger)tableView:(UITableView *)tv numberOfRowsInSection:(NSInteger)s { return self.rows.count; }

- (UITableViewCell *)tableView:(UITableView *)tv cellForRowAtIndexPath:(NSIndexPath *)ip {
    RYGViewerCell *cell = [tv dequeueReusableCellWithIdentifier:@"v" forIndexPath:ip];
    NSDictionary *v = [self viewerAt:ip];
    NSString *pk = v[@"pk"];
    [cell configureWithViewer:v pinned:(pk.length && [RYGStoryViewerPins isPinned:pk])];
    return cell;
}

- (void)tableView:(UITableView *)tv didSelectRowAtIndexPath:(NSIndexPath *)ip {
    [tv deselectRowAtIndexPath:ip animated:YES];
    NSDictionary *v = [self viewerAt:ip];
    NSString *uname = v[@"username"];
    NSString *pk = v[@"pk"];
    if (!uname.length && !pk.length) return;
    [RYGProfileOpener openProfileForPK:pk username:uname from:[self ryg_hostVC]];
}

- (void)scrollViewDidScroll:(UIScrollView *)sv {
    if (self.reachedEnd || self.loading || self.searchQuery.length) return;
    CGFloat dist = sv.contentSize.height - (sv.contentOffset.y + sv.bounds.size.height);
    if (dist < 400) [self loadNextPage];
}

- (void)tableView:(UITableView *)tv willDisplayCell:(UITableViewCell *)cell forRowAtIndexPath:(NSIndexPath *)ip {
    if (!self.searchQuery.length && !self.reachedEnd && !self.loading && ip.row >= (NSInteger)self.rows.count - 8) [self loadNextPage];
}

#pragma mark search + filter

- (void)searchBar:(UISearchBar *)sb textDidChange:(NSString *)text { self.searchQuery = text ?: @""; }
- (void)searchBarSearchButtonClicked:(UISearchBar *)sb { [sb resignFirstResponder]; }
- (void)searchBarTextDidBeginEditing:(UISearchBar *)sb { [sb setShowsCancelButton:YES animated:YES]; }
- (void)searchBarTextDidEndEditing:(UISearchBar *)sb { [sb setShowsCancelButton:NO animated:YES]; }
- (void)searchBarCancelButtonClicked:(UISearchBar *)sb { sb.text = @""; self.searchQuery = @""; [sb resignFirstResponder]; }

- (void)updateFilterButtonState {
    self.filterButton.tintColor = (rygSVActive() || self.searchQuery.length) ? UIColor.systemBlueColor : UIColor.labelColor;
}

- (void)openFilters {
    __weak typeof(self) w = self;
    [RYGStoryViewerSortSheet presentFrom:[self ryg_hostVC] hidePinned:NO onChange:^{ [w applyFilters]; }];
}

- (UIViewController *)ryg_hostVC {
    UIResponder *r = self;
    while ((r = r.nextResponder)) if ([r isKindOfClass:UIViewController.class]) return (UIViewController *)r;
    return nil;
}

@end

