#import "RYGStoriesArchiveStatsViewController.h"
#import "RYGStoryAudienceStats.h"
#import "RYGStoriesArchiveStore.h"
#import "RYGStoriesArchiveManager.h"
#import "RYGArchivedStory.h"
#import "RYGStoryViewerCell.h"
#import "RYGStoryMediaViewer.h"
#import "RYGStoryViewerHistoryViewController.h"
#import "../StoriesAndMessages/RYGStoryViewerFilter.h"
#import "../StoriesAndMessages/RYGStoryViewerPins.h"
#import "../../UI/Notification/RYGNotificationActions.h"
#import "../../UI/RYGPopupChrome.h"
#import "../../RYGProfileOpener.h"
#import "../../Settings/RYGSymbol.h"
#import "../../Utils.h"

extern NSString *const RYGStoriesArchiveDidChangeNotification;

typedef NS_ENUM(NSInteger, RYGAudienceSort) {
	RYGAudienceSortViews = 0,
	RYGAudienceSortReactions,
	RYGAudienceSortRecent,
	RYGAudienceSortEarly,
	RYGAudienceSortName,
};

// Percent change against the previous window.
static NSString *rygDeltaText(double current, double previous, UIColor **outColor) {
	*outColor = UIColor.tertiaryLabelColor;
	if (previous == 0) return current > 0 ? RYGLocalized(@"NEW") : nil;
	double diff = (current - previous) / previous * 100.0;
	if (fabs(diff) < 0.5) return @"±0%";
	*outColor = diff > 0 ? UIColor.systemGreenColor : UIColor.systemRedColor;
	return [NSString stringWithFormat:@"%@%.0f%%", diff > 0 ? @"+" : @"−", fabs(diff)];
}

static NSString *const kCell = @"RYGStoryViewerCell";
static NSInteger const kChartBars = 20;

@interface RYGStoriesArchiveStatsViewController () <UITableViewDataSource, UITableViewDelegate, UISearchBarDelegate>
@property (nonatomic, strong) RYGStoriesArchiveStore *store;
@property (nonatomic, strong) RYGStoryAudienceStats *stats;
@property (nonatomic, copy) NSArray<RYGStoryStatPoint *> *chartPoints;
@property (nonatomic, copy) NSArray<RYGAudienceMember *> *shown;

@property (nonatomic, strong) UITableView *tableView;
@property (nonatomic, strong) UISegmentedControl *rangeControl;
@property (nonatomic, strong) UIStackView *headerStack;
@property (nonatomic, strong) UIStackView *tilesStack;
@property (nonatomic, strong) UIView *chartCard;
@property (nonatomic, strong) UIStackView *barsStack;
@property (nonatomic, strong) UILabel *chartCaption;
@property (nonatomic, strong) UISearchBar *searchBar;
@property (nonatomic, strong) UIView *listHeaderView;
@property (nonatomic, strong) UIButton *filterButton;
@property (nonatomic, strong) UIButton *sortButton;
@property (nonatomic, strong) UILabel *emptyLabel;
@property (nonatomic, strong) UIActivityIndicatorView *spinner;
@property (nonatomic, strong) UIBarButtonItem *spinnerItem;
@property (nonatomic, strong) UIBarButtonItem *moreItem;

@property (nonatomic, assign) RYGStatsRange range;
@property (nonatomic, assign) RYGSVFilter filterMask;
@property (nonatomic, assign) RYGAudienceSort sort;
@property (nonatomic, copy) NSString *query;
@end

@implementation RYGStoriesArchiveStatsViewController

+ (void)showFrom:(UIViewController *)presenter {
	RYGStoriesArchiveStatsViewController *vc = [RYGStoriesArchiveStatsViewController new];
	if (presenter.navigationController) [presenter.navigationController pushViewController:vc animated:YES];
	else [RYGPopupChrome presentVC:vc from:presenter];
}

- (void)viewDidLoad {
	[super viewDidLoad];
	self.title = RYGLocalized(@"Story stats");
	self.view.backgroundColor = [RYGPopupChrome backgroundColor];
	self.store = [RYGStoriesArchiveStore storeForCurrentUser];
	self.range = RYGStatsRangeAll;
	self.sort = RYGAudienceSortViews;

	[self setupTable];
	[self setupHeader];
	[self setupEmptyLabel];

	self.spinner = [[UIActivityIndicatorView alloc] initWithActivityIndicatorStyle:UIActivityIndicatorViewStyleMedium];
	self.spinner.hidesWhenStopped = YES;
	self.moreItem = [[UIBarButtonItem alloc] initWithImage:[RYGSymbol symbolWithIGName:@"fb_ic_dots_3_horizontal_filled_24" fallback:@"ellipsis" color:UIColor.labelColor size:20].image menu:[self moreMenu]];
	self.spinnerItem = [[UIBarButtonItem alloc] initWithCustomView:self.spinner];
	self.navigationItem.rightBarButtonItem = self.moreItem;

	[NSNotificationCenter.defaultCenter addObserver:self selector:@selector(scheduleRecompute)
	                                           name:RYGStoriesArchiveDidChangeNotification object:nil];
	[self recompute];
}

- (void)viewWillAppear:(BOOL)animated {
	[super viewWillAppear:animated];
	if (self.stats) [self refilter];
}

- (void)dealloc {
	[NSObject cancelPreviousPerformRequestsWithTarget:self];
	[NSNotificationCenter.defaultCenter removeObserver:self];
}

#pragma mark - Setup

- (void)setupTable {
	self.tableView = [[UITableView alloc] initWithFrame:CGRectZero style:UITableViewStylePlain];
	self.tableView.translatesAutoresizingMaskIntoConstraints = NO;
	self.tableView.backgroundColor = UIColor.clearColor;
	self.tableView.dataSource = self;
	self.tableView.delegate = self;
	self.tableView.rowHeight = 64;
	self.tableView.separatorInset = UIEdgeInsetsMake(0, 76, 0, 0);
	self.tableView.keyboardDismissMode = UIScrollViewKeyboardDismissModeOnDrag;
	[self.tableView registerClass:RYGStoryViewerCell.class forCellReuseIdentifier:kCell];
	UIRefreshControl *rc = [UIRefreshControl new];
	[rc addTarget:self action:@selector(recompute) forControlEvents:UIControlEventValueChanged];
	self.tableView.refreshControl = rc;
	[self.view addSubview:self.tableView];
	[NSLayoutConstraint activateConstraints:@[
		[self.tableView.topAnchor constraintEqualToAnchor:self.view.safeAreaLayoutGuide.topAnchor],
		[self.tableView.leadingAnchor constraintEqualToAnchor:self.view.leadingAnchor],
		[self.tableView.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor],
		[self.tableView.bottomAnchor constraintEqualToAnchor:self.view.bottomAnchor],
	]];
}

- (void)setupHeader {
	self.rangeControl = [[UISegmentedControl alloc] initWithItems:@[RYGLocalized(@"7 days"), RYGLocalized(@"30 days"), RYGLocalized(@"All time")]];
	self.rangeControl.selectedSegmentIndex = RYGStatsRangeAll;
	[self.rangeControl addTarget:self action:@selector(rangeChanged) forControlEvents:UIControlEventValueChanged];

	self.tilesStack = [UIStackView new];
	self.tilesStack.axis = UILayoutConstraintAxisVertical;
	self.tilesStack.spacing = 14;

	self.barsStack = [UIStackView new];
	self.barsStack.axis = UILayoutConstraintAxisHorizontal;
	self.barsStack.alignment = UIStackViewAlignmentBottom;
	self.barsStack.distribution = UIStackViewDistributionFillEqually;
	self.barsStack.spacing = 4;
	[self.barsStack.heightAnchor constraintEqualToConstant:74].active = YES;

	UILabel *chartTitle = [UILabel new];
	chartTitle.font = [UIFont systemFontOfSize:13 weight:UIFontWeightSemibold];
	chartTitle.textColor = UIColor.labelColor;
	chartTitle.text = RYGLocalized(@"Views per story");

	self.chartCaption = [UILabel new];
	self.chartCaption.font = [UIFont systemFontOfSize:11];
	self.chartCaption.textColor = UIColor.secondaryLabelColor;

	UIStackView *chartStack = [[UIStackView alloc] initWithArrangedSubviews:@[chartTitle, self.barsStack, self.chartCaption]];
	chartStack.axis = UILayoutConstraintAxisVertical;
	chartStack.spacing = 10;
	self.chartCard = [self cardWrapping:chartStack];

	self.headerStack = [[UIStackView alloc] initWithArrangedSubviews:@[self.rangeControl, [self cardWrapping:self.tilesStack], self.chartCard]];
	self.headerStack.axis = UILayoutConstraintAxisVertical;
	self.headerStack.spacing = 14;
	self.headerStack.layoutMargins = UIEdgeInsetsMake(12, 16, 6, 16);
	self.headerStack.layoutMarginsRelativeArrangement = YES;
	self.headerStack.translatesAutoresizingMaskIntoConstraints = NO;

	UIView *header = [[UIView alloc] initWithFrame:CGRectMake(0, 0, self.view.bounds.size.width, 300)];
	[header addSubview:self.headerStack];
	[NSLayoutConstraint activateConstraints:@[
		[self.headerStack.leadingAnchor constraintEqualToAnchor:header.leadingAnchor],
		[self.headerStack.trailingAnchor constraintEqualToAnchor:header.trailingAnchor],
		[self.headerStack.topAnchor constraintEqualToAnchor:header.topAnchor],
		[self.headerStack.bottomAnchor constraintEqualToAnchor:header.bottomAnchor],
	]];
	self.tableView.tableHeaderView = header;
}

- (UIView *)cardWrapping:(UIView *)content {
	UIView *card = [UIView new];
	card.backgroundColor = UIColor.secondarySystemBackgroundColor;
	card.layer.cornerRadius = 18;
	content.translatesAutoresizingMaskIntoConstraints = NO;
	[card addSubview:content];
	[NSLayoutConstraint activateConstraints:@[
		[content.leadingAnchor constraintEqualToAnchor:card.leadingAnchor constant:14],
		[content.trailingAnchor constraintEqualToAnchor:card.trailingAnchor constant:-14],
		[content.topAnchor constraintEqualToAnchor:card.topAnchor constant:14],
		[content.bottomAnchor constraintEqualToAnchor:card.bottomAnchor constant:-14],
	]];
	return card;
}

- (void)setupEmptyLabel {
	self.emptyLabel = [UILabel new];
	self.emptyLabel.translatesAutoresizingMaskIntoConstraints = NO;
	self.emptyLabel.numberOfLines = 0;
	self.emptyLabel.textAlignment = NSTextAlignmentCenter;
	self.emptyLabel.font = [UIFont systemFontOfSize:14];
	self.emptyLabel.textColor = UIColor.secondaryLabelColor;
	self.emptyLabel.hidden = YES;
	[self.view addSubview:self.emptyLabel];
	[NSLayoutConstraint activateConstraints:@[
		[self.emptyLabel.centerXAnchor constraintEqualToAnchor:self.view.centerXAnchor],
		[self.emptyLabel.bottomAnchor constraintEqualToAnchor:self.view.bottomAnchor constant:-90],
		[self.emptyLabel.leadingAnchor constraintEqualToAnchor:self.view.leadingAnchor constant:40],
		[self.emptyLabel.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor constant:-40],
	]];
}

- (void)viewDidLayoutSubviews {
	[super viewDidLayoutSubviews];
	[self sizeHeaderToFit];
}

// A table never re-measures its header, and this one grows once stats land.
- (void)sizeHeaderToFit {
	UIView *header = self.tableView.tableHeaderView;
	CGFloat width = self.tableView.bounds.size.width;
	if (!header || width <= 0) return;
	if (header.frame.size.width != width) {
		CGRect f = header.frame;
		f.size.width = width;
		header.frame = f;
	}
	[header layoutIfNeeded];
	CGFloat height = [header systemLayoutSizeFittingSize:CGSizeMake(width, 0)
	                      withHorizontalFittingPriority:UILayoutPriorityRequired
	                            verticalFittingPriority:UILayoutPriorityFittingSizeLevel].height;
	if (fabs(header.frame.size.height - height) < 0.5) return;
	CGRect f = header.frame;
	f.size.height = height;
	header.frame = f;
	self.tableView.tableHeaderView = header;
}

- (UIMenu *)moreMenu {
	__weak typeof(self) w = self;
	UIAction *refresh = [UIAction actionWithTitle:RYGLocalized(@"Refresh names & photos")
	                                        image:[RYGSymbol symbolWithIGName:@"ig_icon_refresh_outline_24" fallback:@"arrow.clockwise"].image
	                                   identifier:nil handler:^(UIAction *a) {
		NSMutableArray<NSString *> *pks = [NSMutableArray array];
		for (RYGAudienceMember *m in w.stats.members) if (m.pk.length) [pks addObject:m.pk];
		[[RYGStoriesArchiveManager shared] refreshIdentitiesForPKs:pks force:YES];
	}];
	return [UIMenu menuWithTitle:@"" children:@[refresh]];
}

#pragma mark - Compute

- (void)rangeChanged {
	self.range = self.rangeControl.selectedSegmentIndex;
	[self recompute];
}

- (void)scheduleRecompute {
	[NSObject cancelPreviousPerformRequestsWithTarget:self selector:@selector(recompute) object:nil];
	[self performSelector:@selector(recompute) withObject:nil afterDelay:1.0];
}

- (void)setBusy:(BOOL)busy {
	busy ? [self.spinner startAnimating] : [self.spinner stopAnimating];
	self.navigationItem.rightBarButtonItems = busy ? @[self.moreItem, self.spinnerItem] : @[self.moreItem];
}

- (void)recompute {
	[self setBusy:YES];
	__weak typeof(self) w = self;
	[RYGStoryAudienceStats computeForStore:self.store range:self.range completion:^(RYGStoryAudienceStats *stats) {
		[w setBusy:NO];
		[w.tableView.refreshControl endRefreshing];
		w.stats = stats;
		[w renderOverview];
		[w renderChart];
		[w refilter];
		[w sizeHeaderToFit];
	}];
}

#pragma mark - Overview

- (void)renderOverview {
	RYGStoryAudienceStats *s = self.stats, *prev = self.stats.previous;
	NSString *peak = s.peakHour < 0 ? @"—" : [NSString stringWithFormat:@"%02ld:00", (long)s.peakHour];
	NSArray<NSDictionary *> *tiles = @[
		@{@"v": RYGStatShortNumber(s.storyCount),    @"c": RYGLocalized(@"Stories"),        @"n": @(s.storyCount),     @"p": @(prev.storyCount)},
		@{@"v": RYGStatShortNumber(s.totalViews),    @"c": RYGLocalized(@"Views"),          @"n": @(s.totalViews),     @"p": @(prev.totalViews)},
		@{@"v": [NSString stringWithFormat:@"%.0f", s.avgViews], @"c": RYGLocalized(@"Avg / story"), @"n": @(s.avgViews), @"p": @(prev.avgViews)},
		@{@"v": RYGStatShortNumber(s.uniqueViewers), @"c": RYGLocalized(@"Unique viewers"), @"n": @(s.uniqueViewers),  @"p": @(prev.uniqueViewers)},
		@{@"v": RYGStatShortNumber(s.totalReactions),@"c": RYGLocalized(@"Reactions"),      @"n": @(s.totalReactions), @"p": @(prev.totalReactions)},
		@{@"v": [NSString stringWithFormat:@"%.1f%%", s.engagement], @"c": RYGLocalized(@"Engagement"), @"n": @(s.engagement), @"p": @(prev.engagement)},
		@{@"v": RYGStatShortNumber(s.loyalViewers),  @"c": RYGLocalized(@"Loyal fans"),     @"n": @(s.loyalViewers),   @"p": @(prev.loyalViewers)},
		@{@"v": RYGStatShortNumber(s.earlyViewers),  @"c": RYGLocalized(@"Early birds"),    @"n": @(s.earlyViewers),   @"p": @(prev.earlyViewers)},
		@{@"v": peak, @"c": RYGLocalized(@"Peak hour")},
	];

	for (UIView *v in self.tilesStack.arrangedSubviews) [v removeFromSuperview];
	UIStackView *row = nil;
	for (NSDictionary *t in tiles) {
		if (!row || row.arrangedSubviews.count == 3) {
			row = [UIStackView new];
			row.axis = UILayoutConstraintAxisHorizontal;
			row.distribution = UIStackViewDistributionFillEqually;
			row.spacing = 6;
			[self.tilesStack addArrangedSubview:row];
		}
		UIColor *color = UIColor.tertiaryLabelColor;
		NSString *delta = (prev && t[@"n"]) ? rygDeltaText([t[@"n"] doubleValue], [t[@"p"] doubleValue], &color) : nil;
		[row addArrangedSubview:[self tileWithValue:t[@"v"] caption:t[@"c"] delta:delta deltaColor:color]];
	}
}

- (UIView *)tileWithValue:(NSString *)value caption:(NSString *)caption delta:(NSString *)delta deltaColor:(UIColor *)deltaColor {
	UILabel *v = [UILabel new];
	v.font = [UIFont systemFontOfSize:19 weight:UIFontWeightSemibold];
	v.textColor = UIColor.labelColor;
	v.textAlignment = NSTextAlignmentCenter;
	v.adjustsFontSizeToFitWidth = YES;
	v.minimumScaleFactor = 0.7;
	v.text = value;

	UILabel *c = [UILabel new];
	c.font = [UIFont systemFontOfSize:11];
	c.textColor = UIColor.secondaryLabelColor;
	c.textAlignment = NSTextAlignmentCenter;
	c.numberOfLines = 2;
	c.text = caption;

	UILabel *d = [UILabel new];
	d.font = [UIFont systemFontOfSize:10.5 weight:UIFontWeightSemibold];
	d.textColor = deltaColor;
	d.textAlignment = NSTextAlignmentCenter;
	d.text = delta;
	d.hidden = !delta.length;

	UIStackView *st = [[UIStackView alloc] initWithArrangedSubviews:@[v, c, d]];
	st.axis = UILayoutConstraintAxisVertical;
	st.spacing = 1;
	return st;
}

#pragma mark - Chart

- (void)renderChart {
	NSArray<RYGStoryStatPoint *> *points = self.stats.points;
	if (points.count > kChartBars) points = [points subarrayWithRange:NSMakeRange(points.count - kChartBars, kChartBars)];
	self.chartPoints = points;

	for (UIView *v in self.barsStack.arrangedSubviews) [v removeFromSuperview];
	self.chartCard.hidden = points.count < 2;
	if (self.chartCard.hidden) return;

	NSInteger peak = 0;
	for (RYGStoryStatPoint *p in points) peak = MAX(peak, p.views);
	UIColor *tint = [RYGUtils RYGColor_Primary] ?: UIColor.systemBlueColor;

	for (NSInteger i = 0; i < (NSInteger)points.count; i++) {
		RYGStoryStatPoint *p = points[i];
		UIButton *bar = [UIButton buttonWithType:UIButtonTypeCustom];
		bar.tag = i;
		bar.backgroundColor = [tint colorWithAlphaComponent:p.reactions ? 1.0 : 0.55];
		bar.layer.cornerRadius = 3;
		bar.layer.maskedCorners = kCALayerMinXMinYCorner | kCALayerMaxXMinYCorner;
		[bar addTarget:self action:@selector(barTapped:) forControlEvents:UIControlEventTouchUpInside];
		CGFloat fraction = peak ? MAX(0.06, (CGFloat)p.views / peak) : 0.06;
		[bar.heightAnchor constraintEqualToConstant:round(74 * fraction)].active = YES;
		[self.barsStack addArrangedSubview:bar];
	}

	static NSDateFormatter *fmt;
	static dispatch_once_t once;
	dispatch_once(&once, ^{ fmt = [NSDateFormatter new]; fmt.dateFormat = @"MMM d"; });
	NSDate *first = points.firstObject.takenAt, *last = points.lastObject.takenAt;
	NSString *span = (first && last) ? [NSString stringWithFormat:@"%@ – %@", [fmt stringFromDate:first], [fmt stringFromDate:last]] : @"";
	self.chartCaption.text = [NSString stringWithFormat:RYGLocalized(@"%@ · peak %@ views"), span, RYGStatShortNumber(peak)];
}

- (void)barTapped:(UIButton *)bar {
	NSMutableArray<RYGArchivedStory *> *stories = [NSMutableArray array];
	NSInteger start = 0;
	for (NSInteger i = 0; i < (NSInteger)self.chartPoints.count; i++) {
		RYGArchivedStory *story = [self.store storyWithPK:self.chartPoints[i].pk inContext:self.store.viewContext];
		if (!story) continue;
		if (i == bar.tag) start = stories.count;
		[stories addObject:story];
	}
	if (stories.count) [RYGStoryMediaViewer presentStories:stories store:self.store startIndex:start from:self];
}

#pragma mark - Audience list

// Pinning lives in the custom viewer-list feature; if it's off, no pin UI.
- (BOOL)pinsEnabled { return [RYGUtils getBoolPref:@"ryg_story_viewer_sort_enabled"]; }

- (BOOL)isPinned:(RYGAudienceMember *)m { return [self pinsEnabled] && m.pk.length && [RYGStoryViewerPins isPinned:m.pk]; }

- (void)refilter {
	NSString *q = self.query.lowercaseString;
	NSMutableArray<RYGAudienceMember *> *pinned = [NSMutableArray array];
	NSMutableArray<RYGAudienceMember *> *out = [NSMutableArray array];
	for (RYGAudienceMember *m in self.stats.members) {
		RYGSVAttr a = { m.following, m.followedBy, m.isVerified, m.reactions > 0 };
		BOOL isPinned = [self isPinned:m];
		BOOL pass = (self.filterMask & RYGSVFilterPinned) ? (isPinned && rygSVPassesNonPinned(self.filterMask, a))
		                                                  : (isPinned || rygSVPassesNonPinned(self.filterMask, a));
		if (!pass) continue;
		if (q.length && !([m.username.lowercaseString containsString:q] || [m.fullName.lowercaseString containsString:q])) continue;
		[(isPinned ? pinned : out) addObject:m];
	}
	[pinned sortUsingComparator:^NSComparisonResult(RYGAudienceMember *a, RYGAudienceMember *b) {
		return [@([RYGStoryViewerPins rankOfPK:a.pk]) compare:@([RYGStoryViewerPins rankOfPK:b.pk])];
	}];

	NSComparator cmp = nil;
	switch (self.sort) {
		case RYGAudienceSortReactions:
			cmp = ^NSComparisonResult(RYGAudienceMember *a, RYGAudienceMember *b) { return a.reactions == b.reactions ? NSOrderedSame : (a.reactions > b.reactions ? NSOrderedAscending : NSOrderedDescending); };
			break;
		case RYGAudienceSortRecent:
			cmp = ^NSComparisonResult(RYGAudienceMember *a, RYGAudienceMember *b) { return [(b.lastSeenAt ?: NSDate.distantPast) compare:(a.lastSeenAt ?: NSDate.distantPast)]; };
			break;
		case RYGAudienceSortEarly:
			cmp = ^NSComparisonResult(RYGAudienceMember *a, RYGAudienceMember *b) { return a.earliness == b.earliness ? NSOrderedSame : (a.earliness > b.earliness ? NSOrderedAscending : NSOrderedDescending); };
			break;
		case RYGAudienceSortName:
			cmp = ^NSComparisonResult(RYGAudienceMember *a, RYGAudienceMember *b) { return [(a.username ?: @"") caseInsensitiveCompare:(b.username ?: @"")]; };
			break;
		default: break;
	}
	if (cmp) [out sortWithOptions:NSSortStable usingComparator:cmp];

	[pinned addObjectsFromArray:out];
	out = pinned;
	self.shown = out;
	self.emptyLabel.hidden = out.count > 0;
	if (!out.count)
		self.emptyLabel.text = self.stats.storyCount ? RYGLocalized(@"No viewers match these filters")
		                                             : RYGLocalized(@"No archived stories in this range yet.");
	[self.tableView reloadData];
	[self updateMenus];
}

- (UIView *)tableView:(UITableView *)tv viewForHeaderInSection:(NSInteger)section {
	if (!self.listHeaderView) [self buildListControls];
	return self.listHeaderView;
}

- (CGFloat)tableView:(UITableView *)tv heightForHeaderInSection:(NSInteger)section { return 52; }

- (void)buildListControls {
	self.searchBar = [UISearchBar new];
	self.searchBar.placeholder = RYGLocalized(@"Search viewers");
	self.searchBar.delegate = self;
	self.searchBar.searchBarStyle = UISearchBarStyleMinimal;
	self.searchBar.backgroundImage = [UIImage new];

	self.filterButton = [self capsuleButtonWithIGName:@"ig_icon_filter_outline_24" fallback:@"line.3.horizontal.decrease"];
	self.sortButton = [self capsuleButtonWithIGName:@"ig_icon_sorting_outline_24" fallback:@"arrow.up.arrow.down"];
	[self updateMenus];

	UIStackView *row = [[UIStackView alloc] initWithArrangedSubviews:@[self.searchBar, self.filterButton, self.sortButton]];
	row.axis = UILayoutConstraintAxisHorizontal;
	row.alignment = UIStackViewAlignmentCenter;
	row.spacing = 6;
	row.translatesAutoresizingMaskIntoConstraints = NO;

	UIView *host = [UIView new];
	host.backgroundColor = [RYGPopupChrome backgroundColor];
	self.listHeaderView = host;
	[host addSubview:row];
	[NSLayoutConstraint activateConstraints:@[
		[row.leadingAnchor constraintEqualToAnchor:host.leadingAnchor constant:10],
		[row.trailingAnchor constraintEqualToAnchor:host.trailingAnchor constant:-12],
		[row.centerYAnchor constraintEqualToAnchor:host.centerYAnchor],
	]];
}

- (UIButton *)capsuleButtonWithIGName:(NSString *)igName fallback:(NSString *)fallback {
	UIButtonConfiguration *cfg = [UIButtonConfiguration grayButtonConfiguration];
	cfg.cornerStyle = UIButtonConfigurationCornerStyleCapsule;
	cfg.buttonSize = UIButtonConfigurationSizeSmall;
	cfg.image = [RYGSymbol symbolWithIGName:igName fallback:fallback color:UIColor.labelColor size:15].image;
	UIButton *b = [UIButton buttonWithConfiguration:cfg primaryAction:nil];
	b.showsMenuAsPrimaryAction = YES;
	[b setContentHuggingPriority:UILayoutPriorityRequired forAxis:UILayoutConstraintAxisHorizontal];
	return b;
}

- (void)updateMenus {
	if (!self.filterButton) return;
	__weak typeof(self) w = self;

	NSMutableArray<UIAction *> *filters = [NSMutableArray array];
	BOOL pins = [self pinsEnabled];
	for (NSDictionary *r in rygSVFilterRows()) {
		RYGSVFilter bit = (RYGSVFilter)[r[@"v"] unsignedIntegerValue];
		if (bit == RYGSVFilterPinned && !pins) continue;
		UIAction *a = [UIAction actionWithTitle:r[@"t"] image:[UIImage systemImageNamed:r[@"i"]] identifier:nil handler:^(UIAction *ac) {
			w.filterMask ^= bit;
			[w refilter];
		}];
		a.state = (self.filterMask & bit) ? UIMenuElementStateOn : UIMenuElementStateOff;
		if (@available(iOS 16.0, *)) a.attributes = UIMenuElementAttributesKeepsMenuPresented;
		[filters addObject:a];
	}
	UIMenu *filterMenu = [UIMenu menuWithTitle:@"" image:nil identifier:nil options:UIMenuOptionsDisplayInline children:filters];
	if (self.filterMask) {
		UIAction *clear = [UIAction actionWithTitle:RYGLocalized(@"Clear filters") image:[UIImage systemImageNamed:@"xmark.circle"] identifier:nil handler:^(UIAction *ac) {
			w.filterMask = 0;
			[w refilter];
		}];
		self.filterButton.menu = [UIMenu menuWithTitle:@"" children:@[filterMenu, clear]];
	} else {
		self.filterButton.menu = [UIMenu menuWithTitle:@"" children:@[filterMenu]];
	}
	UIButtonConfiguration *cfg = self.filterButton.configuration;
	cfg.baseForegroundColor = self.filterMask ? ([RYGUtils RYGColor_Primary] ?: UIColor.systemBlueColor) : UIColor.labelColor;
	self.filterButton.configuration = cfg;

	NSArray<NSString *> *sortTitles = @[RYGLocalized(@"Most viewed"), RYGLocalized(@"Most reacted"), RYGLocalized(@"Recently viewed"), RYGLocalized(@"Opens first"), RYGLocalized(@"Name (A–Z)")];
	NSMutableArray<UIAction *> *sorts = [NSMutableArray array];
	for (NSInteger i = 0; i < (NSInteger)sortTitles.count; i++) {
		UIAction *a = [UIAction actionWithTitle:sortTitles[i] image:nil identifier:nil handler:^(UIAction *ac) {
			w.sort = i;
			[w refilter];
		}];
		a.state = self.sort == i ? UIMenuElementStateOn : UIMenuElementStateOff;
		[sorts addObject:a];
	}
	self.sortButton.menu = [UIMenu menuWithTitle:RYGLocalized(@"Sort by") children:sorts];
}

#pragma mark - Table

- (NSInteger)tableView:(UITableView *)tv numberOfRowsInSection:(NSInteger)section { return self.shown.count; }

- (UITableViewCell *)tableView:(UITableView *)tv cellForRowAtIndexPath:(NSIndexPath *)ip {
	RYGStoryViewerCell *cell = [tv dequeueReusableCellWithIdentifier:kCell forIndexPath:ip];
	RYGAudienceMember *m = self.shown[ip.row];
	[cell configureWithViewer:m pinned:[self isPinned:m] detail:[self detailForMember:m]];
	return cell;
}

- (NSString *)detailForMember:(RYGAudienceMember *)m {
	if (self.sort == RYGAudienceSortEarly && m.earliness >= 0) {
		NSInteger top = MAX(1, (NSInteger)round((1.0 - m.earliness) * 100));
		return [NSString stringWithFormat:RYGLocalized(@"top %ld%%"), (long)top];
	}
	if (self.sort == RYGAudienceSortReactions)
		return m.reactions == 1 ? RYGLocalized(@"1 reaction") : [NSString stringWithFormat:RYGLocalized(@"%ld reactions"), (long)m.reactions];
	return m.views == 1 ? RYGLocalized(@"1 view") : [NSString stringWithFormat:RYGLocalized(@"%lu views"), (unsigned long)m.views];
}

- (void)tableView:(UITableView *)tv didSelectRowAtIndexPath:(NSIndexPath *)ip {
	[tv deselectRowAtIndexPath:ip animated:YES];
	[RYGStoryViewerHistoryViewController showMember:self.shown[ip.row] from:self];
}

- (UIContextMenuConfiguration *)tableView:(UITableView *)tv contextMenuConfigurationForRowAtIndexPath:(NSIndexPath *)ip point:(CGPoint)point {
	if (ip.row >= (NSInteger)self.shown.count) return nil;
	RYGAudienceMember *m = self.shown[ip.row];
	__weak typeof(self) w = self;
	return [UIContextMenuConfiguration configurationWithIdentifier:nil previewProvider:nil actionProvider:^UIMenu *(NSArray<UIMenuElement *> *elements) {
		UIAction *profile = [UIAction actionWithTitle:RYGLocalized(@"Open profile")
		                                        image:[RYGSymbol symbolWithIGName:@"ig_icon_user_follow_outline_24" fallback:@"person.crop.circle"].image
		                                   identifier:nil handler:^(UIAction *a) { [RYGProfileOpener openProfileForPK:m.pk username:m.username from:w]; }];
		if (![w pinsEnabled]) return [UIMenu menuWithTitle:@"" children:@[profile]];
		BOOL isPinned = [w isPinned:m];
		UIAction *pin = [UIAction actionWithTitle:isPinned ? RYGLocalized(@"Unpin") : RYGLocalized(@"Pin")
		                                    image:[UIImage systemImageNamed:isPinned ? @"pin.slash" : @"pin"]
		                               identifier:nil handler:^(UIAction *a) { [w togglePinForMember:m]; }];
		return [UIMenu menuWithTitle:@"" children:@[pin, profile]];
	}];
}

- (void)togglePinForMember:(RYGAudienceMember *)m {
	if (!m.pk.length) return;
	BOOL nowPinned = [RYGStoryViewerPins togglePK:m.pk entry:@{
		@"pk": m.pk, @"username": m.username ?: @"", @"fullName": m.fullName ?: @"", @"avatarURL": m.profilePicURL ?: @""
	}];
	[[[UIImpactFeedbackGenerator alloc] initWithStyle:UIImpactFeedbackStyleMedium] impactOccurred];
	RYGNotifySuccess(RYG_NOTIF_PIN_STORY_VIEWER,
		nowPinned ? RYGLocalized(@"Viewer pinned") : RYGLocalized(@"Viewer unpinned"),
		m.username.length ? [@"@" stringByAppendingString:m.username] : nil);
	[self refilter];
}

#pragma mark - Search

- (void)searchBar:(UISearchBar *)searchBar textDidChange:(NSString *)text { self.query = text; [self refilter]; }
- (void)searchBarSearchButtonClicked:(UISearchBar *)searchBar { [searchBar resignFirstResponder]; }

@end
