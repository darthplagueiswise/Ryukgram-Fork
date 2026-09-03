#import "RYGStoryViewersSheet.h"
#import "RYGStoryViewerCell.h"
#import "RYGArchivedStory.h"
#import "RYGArchivedStoryViewer.h"
#import "RYGStoriesArchiveManager.h"
#import "RYGStoriesArchiveStore.h"
#import "../StoriesAndMessages/RYGStoryViewerFilter.h"
#import "../StoriesAndMessages/RYGStoryViewerSortSheet.h"
#import "../StoriesAndMessages/RYGStoryViewerPins.h"
#import "../../UI/Notification/RYGNotificationActions.h"
#import "../../Utils.h"
#import "../../UI/RYGPopupChrome.h"
#import "../../RYGProfileOpener.h"
#import "../../Settings/RYGSymbol.h"

extern NSString *const RYGStoriesArchiveDidChangeNotification;

// Quick tabs map onto the shared filter model; the filter button opens the full
// multi-select sheet (RYGStoryViewerSortSheet) for everything else.
static RYGSVFilter const kTabFilters[] = { 0, RYGSVFilterReacted, RYGSVFilterIFollow, RYGSVFilterFollowsMe };

static NSString *const kViewerCell = @"RYGStoryViewerCell";

@interface RYGStoryViewersSheet () <UITableViewDataSource, UITableViewDelegate, UISearchBarDelegate>
@property (nonatomic, strong) RYGArchivedStory *story;
@property (nonatomic, strong) NSArray<RYGArchivedStoryViewer *> *allViewers;
@property (nonatomic, strong) NSArray<RYGArchivedStoryViewer *> *shown;
@property (nonatomic, strong) UISegmentedControl *filter;
@property (nonatomic, strong) UISearchBar *searchBar;
@property (nonatomic, strong) UIButton *sortButton;
@property (nonatomic, strong) UITableView *tableView;
@property (nonatomic, strong) UIView *headerView;
@property (nonatomic, strong) UILabel *titleTop;
@property (nonatomic, strong) UILabel *titleBottom;
@property (nonatomic, strong) UIActivityIndicatorView *spinner;
@property (nonatomic, strong) UIButton *moreButton;
@property (nonatomic, copy) NSString *query;
@end

@implementation RYGStoryViewersSheet

+ (void)presentForStory:(RYGArchivedStory *)story from:(UIViewController *)presenter {
	RYGStoryViewersSheet *vc = [RYGStoryViewersSheet new];
	vc.story = story;
	vc.modalPresentationStyle = UIModalPresentationPageSheet;
	if (@available(iOS 15.0, *)) {
		UISheetPresentationController *sheet = vc.sheetPresentationController;
		sheet.detents = @[UISheetPresentationControllerDetent.mediumDetent, UISheetPresentationControllerDetent.largeDetent];
		sheet.prefersGrabberVisible = YES;
		sheet.preferredCornerRadius = 20;
	}
	UIViewController *host = presenter ?: [RYGPopupChrome topMostController];
	[host presentViewController:vc animated:YES completion:nil];
}

- (void)viewDidLoad {
	[super viewDidLoad];
	self.view.backgroundColor = UIColor.systemBackgroundColor;

	UIView *topBar = [self buildTopBar];

	self.tableView = [[UITableView alloc] initWithFrame:CGRectZero style:UITableViewStylePlain];
	self.tableView.translatesAutoresizingMaskIntoConstraints = NO;
	self.tableView.backgroundColor = UIColor.clearColor;
	self.tableView.dataSource = self;
	self.tableView.delegate = self;
	self.tableView.rowHeight = 64;
	self.tableView.separatorInset = UIEdgeInsetsMake(0, 76, 0, 0);
	self.tableView.keyboardDismissMode = UIScrollViewKeyboardDismissModeOnDrag;
	[self.tableView registerClass:RYGStoryViewerCell.class forCellReuseIdentifier:kViewerCell];
	UILongPressGestureRecognizer *lp = [[UILongPressGestureRecognizer alloc] initWithTarget:self action:@selector(handleLongPress:)];
	[self.tableView addGestureRecognizer:lp];
	[self.view addSubview:self.tableView];
	[NSLayoutConstraint activateConstraints:@[
		[self.tableView.topAnchor constraintEqualToAnchor:topBar.bottomAnchor],
		[self.tableView.leadingAnchor constraintEqualToAnchor:self.view.leadingAnchor],
		[self.tableView.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor],
		[self.tableView.bottomAnchor constraintEqualToAnchor:self.view.bottomAnchor],
	]];

	[self buildHeader];

	[NSNotificationCenter.defaultCenter addObserver:self selector:@selector(onStoreChange)
	                                           name:RYGStoriesArchiveDidChangeNotification object:nil];
	[self rebuildViewers];
	[self refilter];

	[self.spinner startAnimating];
	[[RYGStoriesArchiveManager shared] refreshViewersForMediaID:self.story.mediaID completion:^(NSInteger count) {
		[self.spinner stopAnimating];
	}];
}

- (UIView *)buildTopBar {
	UIView *bar = [UIView new];
	bar.translatesAutoresizingMaskIntoConstraints = NO;

	UIButton *close = [UIButton buttonWithType:UIButtonTypeSystem];
	[close setImage:[UIImage systemImageNamed:@"xmark"] forState:UIControlStateNormal];
	close.tintColor = UIColor.labelColor;
	close.translatesAutoresizingMaskIntoConstraints = NO;
	[close addTarget:self action:@selector(close) forControlEvents:UIControlEventTouchUpInside];

	self.titleTop = [UILabel new];
	self.titleTop.font = [UIFont systemFontOfSize:15 weight:UIFontWeightSemibold];
	self.titleTop.textColor = UIColor.labelColor;
	self.titleBottom = [UILabel new];
	self.titleBottom.font = [UIFont systemFontOfSize:12];
	self.titleBottom.textColor = UIColor.secondaryLabelColor;
	UIStackView *titleStack = [[UIStackView alloc] initWithArrangedSubviews:@[self.titleTop, self.titleBottom]];
	titleStack.axis = UILayoutConstraintAxisVertical;
	titleStack.alignment = UIStackViewAlignmentCenter;
	titleStack.translatesAutoresizingMaskIntoConstraints = NO;

	self.spinner = [[UIActivityIndicatorView alloc] initWithActivityIndicatorStyle:UIActivityIndicatorViewStyleMedium];
	self.spinner.translatesAutoresizingMaskIntoConstraints = NO;
	self.spinner.hidesWhenStopped = YES;

	self.moreButton = [UIButton buttonWithType:UIButtonTypeSystem];
	[self.moreButton setImage:[RYGSymbol symbolWithIGName:@"fb_ic_dots_3_horizontal_filled_24" fallback:@"ellipsis" color:UIColor.labelColor size:20].image forState:UIControlStateNormal];
	self.moreButton.tintColor = UIColor.labelColor;
	self.moreButton.showsMenuAsPrimaryAction = YES;
	self.moreButton.translatesAutoresizingMaskIntoConstraints = NO;
	[self updateMoreMenu];

	[bar addSubview:close];
	[bar addSubview:titleStack];
	[bar addSubview:self.spinner];
	[bar addSubview:self.moreButton];
	[self.view addSubview:bar];
	[NSLayoutConstraint activateConstraints:@[
		[bar.topAnchor constraintEqualToAnchor:self.view.topAnchor constant:20],
		[bar.leadingAnchor constraintEqualToAnchor:self.view.leadingAnchor],
		[bar.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor],
		[bar.heightAnchor constraintEqualToConstant:48],
		[close.leadingAnchor constraintEqualToAnchor:bar.leadingAnchor constant:16],
		[close.centerYAnchor constraintEqualToAnchor:bar.centerYAnchor],
		[titleStack.centerXAnchor constraintEqualToAnchor:bar.centerXAnchor],
		[titleStack.centerYAnchor constraintEqualToAnchor:bar.centerYAnchor],
		[self.moreButton.trailingAnchor constraintEqualToAnchor:bar.trailingAnchor constant:-16],
		[self.moreButton.centerYAnchor constraintEqualToAnchor:bar.centerYAnchor],
		[self.spinner.trailingAnchor constraintEqualToAnchor:self.moreButton.leadingAnchor constant:-10],
		[self.spinner.centerYAnchor constraintEqualToAnchor:bar.centerYAnchor],
	]];
	return bar;
}

- (void)buildHeader {
	self.searchBar = [UISearchBar new];
	self.searchBar.placeholder = RYGLocalized(@"Search viewers");
	self.searchBar.delegate = self;
	self.searchBar.searchBarStyle = UISearchBarStyleMinimal;
	self.searchBar.backgroundImage = [UIImage new];

	self.sortButton = [UIButton buttonWithType:UIButtonTypeSystem];
	[self.sortButton setImage:[RYGSymbol symbolWithIGName:@"ig_icon_sorting_outline_24" fallback:@"line.3.horizontal.decrease.circle" color:UIColor.labelColor size:22].image forState:UIControlStateNormal];
	self.sortButton.tintColor = UIColor.labelColor;
	[self.sortButton setContentHuggingPriority:UILayoutPriorityRequired forAxis:UILayoutConstraintAxisHorizontal];
	[self.sortButton addTarget:self action:@selector(openFilterSheet) forControlEvents:UIControlEventTouchUpInside];

	UIStackView *searchRow = [[UIStackView alloc] initWithArrangedSubviews:@[self.searchBar, self.sortButton]];
	searchRow.axis = UILayoutConstraintAxisHorizontal;
	searchRow.alignment = UIStackViewAlignmentCenter;
	searchRow.spacing = 4;

	self.filter = [[UISegmentedControl alloc] initWithItems:@[RYGLocalized(@"All"), RYGLocalized(@"Reacted"), RYGLocalized(@"Following"), RYGLocalized(@"Followers")]];
	[self.filter addTarget:self action:@selector(tabChanged) forControlEvents:UIControlEventValueChanged];
	[self syncTabToFilter];

	UIStackView *stack = [[UIStackView alloc] initWithArrangedSubviews:@[searchRow, self.filter]];
	stack.axis = UILayoutConstraintAxisVertical;
	stack.spacing = 8;
	stack.layoutMargins = UIEdgeInsetsMake(6, 12, 10, 12);
	stack.layoutMarginsRelativeArrangement = YES;
	stack.translatesAutoresizingMaskIntoConstraints = NO;

	UIView *header = [[UIView alloc] initWithFrame:CGRectMake(0, 0, self.view.bounds.size.width, 100)];
	header.backgroundColor = UIColor.clearColor;
	[header addSubview:stack];
	[NSLayoutConstraint activateConstraints:@[
		[stack.leadingAnchor constraintEqualToAnchor:header.leadingAnchor],
		[stack.trailingAnchor constraintEqualToAnchor:header.trailingAnchor],
		[stack.topAnchor constraintEqualToAnchor:header.topAnchor],
		[stack.bottomAnchor constraintEqualToAnchor:header.bottomAnchor],
	]];
	self.headerView = header;
	self.tableView.tableHeaderView = header;
}

- (void)viewDidLayoutSubviews {
	[super viewDidLayoutSubviews];
	UIView *header = self.tableView.tableHeaderView;
	if (!header) return;
	CGFloat h = [header systemLayoutSizeFittingSize:CGSizeMake(self.tableView.bounds.size.width, 0)
	                     withHorizontalFittingPriority:UILayoutPriorityRequired verticalFittingPriority:UILayoutPriorityFittingSizeLevel].height;
	if (fabs(header.frame.size.height - h) > 0.5 || header.frame.size.width != self.tableView.bounds.size.width) {
		CGRect f = header.frame;
		f.size = CGSizeMake(self.tableView.bounds.size.width, h);
		header.frame = f;
		self.tableView.tableHeaderView = header;
	}
}

- (void)dealloc { [NSNotificationCenter.defaultCenter removeObserver:self]; }

- (void)close { [self dismissViewControllerAnimated:YES completion:nil]; }

- (void)updateMoreMenu {
	__weak typeof(self) w = self;
	UIAction *refresh = [UIAction actionWithTitle:RYGLocalized(@"Refresh names & photos")
	                                        image:[RYGSymbol symbolWithIGName:@"ig_icon_refresh_outline_24" fallback:@"arrow.clockwise"].image
	                                   identifier:nil handler:^(UIAction *a) { [w refreshIdentities]; }];
	if (!self.allViewers.count) refresh.attributes = UIMenuElementAttributesDisabled;
	self.moreButton.menu = [UIMenu menuWithTitle:@"" children:@[refresh]];
}

- (void)refreshIdentities {
	NSMutableArray<NSString *> *pks = [NSMutableArray array];
	for (RYGArchivedStoryViewer *v in self.allViewers) if (v.pk.length) [pks addObject:v.pk];
	[[RYGStoriesArchiveManager shared] refreshIdentitiesForPKs:pks force:YES];
}

- (void)onStoreChange { [self rebuildViewers]; [self refilter]; [self updateMoreMenu]; }

- (void)rebuildViewers {
	NSArray *v = [[RYGStoriesArchiveStore storeForCurrentUser] sortedViewersForStoryPK:self.story.pk];
	self.allViewers = v;

	NSInteger likes = 0;
	for (RYGArchivedStoryViewer *x in v) if (x.liked) likes++;

	static NSDateFormatter *fmt;
	static dispatch_once_t once;
	dispatch_once(&once, ^{ fmt = [NSDateFormatter new]; fmt.dateFormat = @"MMM d, yyyy · HH:mm"; });
	self.titleTop.text = self.story.takenAt ? [fmt stringFromDate:self.story.takenAt] : @"";
	NSString *viewsStr = v.count == 1 ? RYGLocalized(@"1 viewer") : [NSString stringWithFormat:RYGLocalized(@"%lu viewers"), (unsigned long)v.count];
	NSString *likesStr = likes == 1 ? RYGLocalized(@"1 like") : [NSString stringWithFormat:RYGLocalized(@"%ld likes"), (long)likes];
	self.titleBottom.text = [NSString stringWithFormat:@"%@ · %@", viewsStr, likesStr];
}

// Pinning lives in the custom viewer-list feature; if it's off, no pin UI.
- (BOOL)pinsEnabled { return [RYGUtils getBoolPref:@"ryg_story_viewer_sort_enabled"]; }

- (void)openFilterSheet {
	__weak typeof(self) w = self;
	[RYGStoryViewerSortSheet presentFrom:self hidePinned:![self pinsEnabled] onChange:^{ [w syncTabToFilter]; [w refilter]; }];
}

- (void)handleLongPress:(UILongPressGestureRecognizer *)gr {
	if (gr.state != UIGestureRecognizerStateBegan || ![self pinsEnabled]) return;
	NSIndexPath *ip = [self.tableView indexPathForRowAtPoint:[gr locationInView:self.tableView]];
	RYGArchivedStoryViewer *v = ip ? [self viewerAt:ip] : nil;
	if (!v.pk.length) return;
	BOOL nowPinned = [RYGStoryViewerPins togglePK:v.pk entry:@{
		@"pk": v.pk, @"username": v.username ?: @"", @"fullName": v.fullName ?: @"", @"avatarURL": v.profilePicURL ?: @""
	}];
	[[[UIImpactFeedbackGenerator alloc] initWithStyle:UIImpactFeedbackStyleMedium] impactOccurred];
	RYGNotifySuccess(RYG_NOTIF_PIN_STORY_VIEWER,
		nowPinned ? RYGLocalized(@"Viewer pinned") : RYGLocalized(@"Viewer unpinned"),
		v.username.length ? [@"@" stringByAppendingString:v.username] : nil);
	[self refilter];
}

// One quick tab = one preset filter bit; a multi-bit / advanced filter shows no tab.
- (void)tabChanged {
	NSInteger i = self.filter.selectedSegmentIndex;
	if (i >= 0 && i < (NSInteger)(sizeof(kTabFilters) / sizeof(kTabFilters[0]))) rygSVSetFilter(kTabFilters[i]);
	[self refilter];
}

- (void)syncTabToFilter {
	RYGSVFilter f = rygSVFilter();
	NSInteger match = UISegmentedControlNoSegment;
	for (NSInteger i = 0; i < (NSInteger)(sizeof(kTabFilters) / sizeof(kTabFilters[0])); i++)
		if (kTabFilters[i] == f) { match = i; break; }
	self.filter.selectedSegmentIndex = match;
}

- (void)refilter {
	RYGSVFilter f = rygSVFilter();
	NSString *q = self.query.lowercaseString;
	BOOL pins = [self pinsEnabled];
	NSMutableArray *pinned = [NSMutableArray array];
	NSMutableArray *rest = [NSMutableArray array];
	for (RYGArchivedStoryViewer *v in self.allViewers) {
		BOOL isPinned = pins && v.pk.length && [RYGStoryViewerPins isPinned:v.pk];
		RYGSVAttr a = { v.following, v.followedBy, v.isVerified, (v.liked || v.reactionEmoji.length > 0) };
		BOOL pass = (f & RYGSVFilterPinned) ? (isPinned && rygSVPassesNonPinned(f, a)) : (isPinned || rygSVPassesNonPinned(f, a));
		if (!pass) continue;
		if (q.length && !([v.username.lowercaseString containsString:q] || [v.fullName.lowercaseString containsString:q])) continue;
		[(isPinned ? pinned : rest) addObject:v];
	}
	[pinned sortUsingComparator:^NSComparisonResult(RYGArchivedStoryViewer *x, RYGArchivedStoryViewer *y) {
		return [@([RYGStoryViewerPins rankOfPK:x.pk]) compare:@([RYGStoryViewerPins rankOfPK:y.pk])];
	}];
	[self applySort:rest];

	NSMutableArray *out = [pinned mutableCopy];
	[out addObjectsFromArray:rest];
	self.shown = out;
	[self.tableView reloadData];
}

static inline BOOL rygViewerReacted(RYGArchivedStoryViewer *v) { return v.liked || v.reactionEmoji.length > 0; }

- (void)applySort:(NSMutableArray<RYGArchivedStoryViewer *> *)arr {
	NSComparator cmp = nil;
	switch (rygSVSort()) {
		case RYGSVSortName:      cmp = ^NSComparisonResult(RYGArchivedStoryViewer *a, RYGArchivedStoryViewer *b) { return [(a.username ?: @"") caseInsensitiveCompare:(b.username ?: @"")]; }; break;
		case RYGSVSortVerified:  cmp = ^NSComparisonResult(RYGArchivedStoryViewer *a, RYGArchivedStoryViewer *b) { return a.isVerified == b.isVerified ? NSOrderedSame : (a.isVerified ? NSOrderedAscending : NSOrderedDescending); }; break;
		case RYGSVSortFollowing: cmp = ^NSComparisonResult(RYGArchivedStoryViewer *a, RYGArchivedStoryViewer *b) { return a.following == b.following ? NSOrderedSame : (a.following ? NSOrderedAscending : NSOrderedDescending); }; break;
		case RYGSVSortFollowsMe: cmp = ^NSComparisonResult(RYGArchivedStoryViewer *a, RYGArchivedStoryViewer *b) { return a.followedBy == b.followedBy ? NSOrderedSame : (a.followedBy ? NSOrderedAscending : NSOrderedDescending); }; break;
		case RYGSVSortMutual:    cmp = ^NSComparisonResult(RYGArchivedStoryViewer *a, RYGArchivedStoryViewer *b) { BOOL ma = a.following && a.followedBy, mb = b.following && b.followedBy; return ma == mb ? NSOrderedSame : (ma ? NSOrderedAscending : NSOrderedDescending); }; break;
		case RYGSVSortReacted:   cmp = ^NSComparisonResult(RYGArchivedStoryViewer *a, RYGArchivedStoryViewer *b) { BOOL ra = rygViewerReacted(a), rb = rygViewerReacted(b); return ra == rb ? NSOrderedSame : (ra ? NSOrderedAscending : NSOrderedDescending); }; break;
		default: break;
	}
	// Stable sort keeps view order (sortIndex) as the tiebreak for equal keys.
	if (cmp) [arr sortWithOptions:NSSortStable usingComparator:cmp];
	if (rygSVReverse()) {
		NSArray *rev = [[arr reverseObjectEnumerator] allObjects];
		[arr setArray:rev];
	}
}

#pragma mark - Table

- (RYGArchivedStoryViewer *)viewerAt:(NSIndexPath *)ip {
	return ip.row < (NSInteger)self.shown.count ? self.shown[ip.row] : nil;
}

- (NSInteger)tableView:(UITableView *)tv numberOfRowsInSection:(NSInteger)section { return self.shown.count; }

- (UITableViewCell *)tableView:(UITableView *)tv cellForRowAtIndexPath:(NSIndexPath *)ip {
	RYGStoryViewerCell *cell = [tv dequeueReusableCellWithIdentifier:kViewerCell forIndexPath:ip];
	RYGArchivedStoryViewer *v = [self viewerAt:ip];
	[cell configureWithViewer:v pinned:([self pinsEnabled] && v.pk.length && [RYGStoryViewerPins isPinned:v.pk])];
	return cell;
}

- (void)tableView:(UITableView *)tv didSelectRowAtIndexPath:(NSIndexPath *)ip {
	[tv deselectRowAtIndexPath:ip animated:YES];
	RYGArchivedStoryViewer *v = [self viewerAt:ip];
	if (v) [RYGProfileOpener openProfileForPK:v.pk username:v.username from:self];
}

#pragma mark - Search

- (void)searchBar:(UISearchBar *)searchBar textDidChange:(NSString *)searchText { self.query = searchText; [self refilter]; }
- (void)searchBarSearchButtonClicked:(UISearchBar *)searchBar { [searchBar resignFirstResponder]; }

@end
