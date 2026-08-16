#import "RYGStoriesArchiveViewController.h"
#import "RYGStoriesArchiveCell.h"
#import "RYGStoriesArchiveStore.h"
#import "RYGStoriesArchiveManager.h"
#import "RYGArchivedStory.h"
#import "../../UI/RYGPopupChrome.h"
#import "RYGStoryMediaViewer.h"
#import "RYGStoryViewersSheet.h"
#import "../../Utils.h"
#import "../../Settings/RYGSymbol.h"
#import "../../Downloader/Download.h"
#import "../../Gallery/RYGGalleryFile.h"
#import "../../Gallery/RYGGallerySaveMetadata.h"
#import "../../Gallery/RYGMediaChrome.h"
#import "../Feed/RYGHomeShortcutBadges.h"

extern NSString *const RYGStoriesArchiveDidChangeNotification;

static NSString *const kCell = @"RYGStoriesArchiveCell";
static NSString *const kHeader = @"RYGStoriesArchiveHeader";
static NSString *const kFilterHeader = @"RYGStoriesArchiveFilterHeader";

typedef NS_ENUM(NSInteger, RYGArchiveSort) { RYGArchiveSortRecent = 0, RYGArchiveSortOldest, RYGArchiveSortMostViewed, RYGArchiveSortMostReacted };
typedef NS_ENUM(NSInteger, RYGArchiveFilter) { RYGArchiveFilterAll = 0, RYGArchiveFilterPhotos, RYGArchiveFilterVideos };

@interface RYGStoriesArchiveViewController () <UICollectionViewDataSource, UICollectionViewDelegate>
@property (nonatomic, strong) RYGStoriesArchiveStore *store;
@property (nonatomic, strong) NSArray<NSDictionary *> *groups;
@property (nonatomic, strong) UICollectionView *collectionView;
@property (nonatomic, strong) UILabel *emptyLabel;
@property (nonatomic, strong) UIView *selectionBar;
@property (nonatomic, strong) UISegmentedControl *filterSegment;
@property (nonatomic, strong) UIButton *sortButton;
@property (nonatomic, strong) UIView *filterRow;

@property (nonatomic, assign) RYGArchiveSort sort;
@property (nonatomic, assign) RYGArchiveFilter filter;
@property (nonatomic, assign) BOOL reactedOnly;
@property (nonatomic, assign) BOOL selecting;
@property (nonatomic, strong) NSMutableSet<NSString *> *selectedPKs;
@property (nonatomic, strong) NSDate *lastRefreshAt;
@end

@implementation RYGStoriesArchiveViewController

+ (void)presentFrom:(UIViewController *)presenter {
	[RYGPopupChrome presentVC:[RYGStoriesArchiveViewController new] from:presenter];
}

- (void)viewDidLoad {
	[super viewDidLoad];
	self.title = RYGLocalized(@"Stories archive");
	self.view.backgroundColor = [RYGPopupChrome backgroundColor];
	self.store = [RYGStoriesArchiveStore storeForCurrentUser];
	self.selectedPKs = [NSMutableSet set];

	[self setupFilterControls];
	[self setupCollectionView];
	[self setupEmptyLabel];
	[self updateNavItems];

	[NSNotificationCenter.defaultCenter addObserver:self selector:@selector(reload)
	                                           name:RYGStoriesArchiveDidChangeNotification object:nil];
	[self reload];

	// Opening the archive clears the "new stories" badge on the home shortcut / entry.
	[RYGHomeShortcutBadges clearActionID:@"stories_archive"];
}

- (void)dealloc { [NSNotificationCenter.defaultCenter removeObserver:self]; }

#pragma mark - Setup

- (void)setupCollectionView {
	UICollectionViewCompositionalLayout *layout = [[UICollectionViewCompositionalLayout alloc] initWithSectionProvider:^NSCollectionLayoutSection *(NSInteger section, id<NSCollectionLayoutEnvironment> env) {
		NSCollectionLayoutItem *item = [NSCollectionLayoutItem itemWithLayoutSize:
			[NSCollectionLayoutSize sizeWithWidthDimension:[NSCollectionLayoutDimension fractionalWidthDimension:1.0/3.0]
			                                heightDimension:[NSCollectionLayoutDimension fractionalHeightDimension:1.0]]];
		item.contentInsets = NSDirectionalEdgeInsetsMake(3, 3, 3, 3);
		NSCollectionLayoutGroup *group = [NSCollectionLayoutGroup horizontalGroupWithLayoutSize:
			[NSCollectionLayoutSize sizeWithWidthDimension:[NSCollectionLayoutDimension fractionalWidthDimension:1.0]
			                                heightDimension:[NSCollectionLayoutDimension fractionalWidthDimension:16.0/9.0/3.0]]
			subitem:item count:3];
		NSCollectionLayoutSection *s = [NSCollectionLayoutSection sectionWithGroup:group];
		s.contentInsets = NSDirectionalEdgeInsetsMake(4, 9, 16, 9);
		NSCollectionLayoutBoundarySupplementaryItem *header = [NSCollectionLayoutBoundarySupplementaryItem
			boundarySupplementaryItemWithLayoutSize:[NSCollectionLayoutSize sizeWithWidthDimension:[NSCollectionLayoutDimension fractionalWidthDimension:1.0] heightDimension:[NSCollectionLayoutDimension absoluteDimension:38]]
			elementKind:UICollectionElementKindSectionHeader alignment:NSRectAlignmentTop];
		s.boundarySupplementaryItems = @[header];
		return s;
	}];

	// Filter + sort ride at the very top of the scroll content, so they scroll away.
	UICollectionViewCompositionalLayoutConfiguration *config = [UICollectionViewCompositionalLayoutConfiguration new];
	NSCollectionLayoutBoundarySupplementaryItem *filterHeader = [NSCollectionLayoutBoundarySupplementaryItem
		boundarySupplementaryItemWithLayoutSize:[NSCollectionLayoutSize sizeWithWidthDimension:[NSCollectionLayoutDimension fractionalWidthDimension:1.0] heightDimension:[NSCollectionLayoutDimension absoluteDimension:50]]
		elementKind:kFilterHeader alignment:NSRectAlignmentTop];
	filterHeader.pinToVisibleBounds = NO;
	config.boundarySupplementaryItems = @[filterHeader];
	layout.configuration = config;

	_collectionView = [[UICollectionView alloc] initWithFrame:CGRectZero collectionViewLayout:layout];
	_collectionView.translatesAutoresizingMaskIntoConstraints = NO;
	_collectionView.backgroundColor = UIColor.clearColor;
	_collectionView.alwaysBounceVertical = YES;
	_collectionView.dataSource = self;
	_collectionView.delegate = self;
	[_collectionView registerClass:RYGStoriesArchiveCell.class forCellWithReuseIdentifier:kCell];
	[_collectionView registerClass:UICollectionReusableView.class forSupplementaryViewOfKind:UICollectionElementKindSectionHeader withReuseIdentifier:kHeader];
	[_collectionView registerClass:UICollectionReusableView.class forSupplementaryViewOfKind:kFilterHeader withReuseIdentifier:kFilterHeader];
	UIRefreshControl *rc = [UIRefreshControl new];
	[rc addTarget:self action:@selector(pullToRefresh:) forControlEvents:UIControlEventValueChanged];
	_collectionView.refreshControl = rc;
	[self.view addSubview:_collectionView];
	[NSLayoutConstraint activateConstraints:@[
		[_collectionView.topAnchor constraintEqualToAnchor:self.view.safeAreaLayoutGuide.topAnchor],
		[_collectionView.leadingAnchor constraintEqualToAnchor:self.view.leadingAnchor],
		[_collectionView.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor],
		[_collectionView.bottomAnchor constraintEqualToAnchor:self.view.bottomAnchor],
	]];
}

- (void)setupFilterControls {
	self.filterSegment = [[UISegmentedControl alloc] initWithItems:@[RYGLocalized(@"All"), RYGLocalized(@"Photos"), RYGLocalized(@"Videos"), RYGLocalized(@"Reacted")]];
	self.filterSegment.selectedSegmentIndex = 0;
	[self.filterSegment addTarget:self action:@selector(filterSegmentChanged) forControlEvents:UIControlEventValueChanged];

	UIButtonConfiguration *cfg = [UIButtonConfiguration grayButtonConfiguration];
	cfg.cornerStyle = UIButtonConfigurationCornerStyleCapsule;
	cfg.buttonSize = UIButtonConfigurationSizeMedium;
	cfg.image = [RYGSymbol symbolWithIGName:@"ig_icon_sorting_outline_24" fallback:@"arrow.up.arrow.down" color:UIColor.labelColor size:15].image;
	self.sortButton = [UIButton buttonWithConfiguration:cfg primaryAction:nil];
	self.sortButton.showsMenuAsPrimaryAction = YES;
	[self.sortButton setContentHuggingPriority:UILayoutPriorityRequired forAxis:UILayoutConstraintAxisHorizontal];
	[self updateSortMenu];

	UIStackView *row = [[UIStackView alloc] initWithArrangedSubviews:@[self.filterSegment, self.sortButton]];
	row.axis = UILayoutConstraintAxisHorizontal;
	row.alignment = UIStackViewAlignmentCenter;
	row.spacing = 10;
	row.translatesAutoresizingMaskIntoConstraints = NO;
	self.filterRow = row;
}

// Throttled so spamming does nothing.
- (void)pullToRefresh:(UIRefreshControl *)rc {
	NSTimeInterval since = self.lastRefreshAt ? -[self.lastRefreshAt timeIntervalSinceNow] : 1e9;
	if (since < 6.0) { [rc endRefreshing]; return; }
	self.lastRefreshAt = [NSDate date];
	[[RYGStoriesArchiveManager shared] recheck];
	dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(1.6 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
		[rc endRefreshing];
		[self reload];
	});
}

- (void)filterSegmentChanged {
	NSInteger i = self.filterSegment.selectedSegmentIndex;
	self.reactedOnly = (i == 3);
	self.filter = (i == 1) ? RYGArchiveFilterPhotos : (i == 2) ? RYGArchiveFilterVideos : RYGArchiveFilterAll;
	[self reload];
}

- (void)updateSortMenu {
	__weak typeof(self) w = self;
	NSArray<NSString *> *titles = @[RYGLocalized(@"Most recent"), RYGLocalized(@"Oldest"), RYGLocalized(@"Most viewed"), RYGLocalized(@"Most reacted")];
	NSMutableArray<UIAction *> *items = [NSMutableArray array];
	for (NSInteger i = 0; i < titles.count; i++) {
		UIAction *a = [UIAction actionWithTitle:titles[i] image:nil identifier:nil handler:^(UIAction *ac) { w.sort = i; [w reload]; [w updateSortMenu]; }];
		a.state = self.sort == i ? UIMenuElementStateOn : UIMenuElementStateOff;
		[items addObject:a];
	}
	self.sortButton.menu = [UIMenu menuWithTitle:RYGLocalized(@"Sort by") children:items];
}

- (void)setupEmptyLabel {
	_emptyLabel = [[UILabel alloc] init];
	_emptyLabel.translatesAutoresizingMaskIntoConstraints = NO;
	_emptyLabel.numberOfLines = 0;
	_emptyLabel.textAlignment = NSTextAlignmentCenter;
	_emptyLabel.font = [UIFont systemFontOfSize:15];
	_emptyLabel.textColor = UIColor.secondaryLabelColor;
	_emptyLabel.hidden = YES;
	[self.view addSubview:_emptyLabel];
	[NSLayoutConstraint activateConstraints:@[
		[_emptyLabel.centerXAnchor constraintEqualToAnchor:self.view.centerXAnchor],
		[_emptyLabel.centerYAnchor constraintEqualToAnchor:self.view.centerYAnchor],
		[_emptyLabel.leadingAnchor constraintEqualToAnchor:self.view.leadingAnchor constant:40],
		[_emptyLabel.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor constant:-40],
	]];
}

#pragma mark - Nav / menu

- (void)close { [self dismissViewControllerAnimated:YES completion:nil]; }

- (void)updateNavItems {
	if (self.selecting) {
		self.navigationItem.leftBarButtonItem = [[UIBarButtonItem alloc] initWithBarButtonSystemItem:UIBarButtonSystemItemCancel target:self action:@selector(exitSelection)];
		self.navigationItem.rightBarButtonItem = [[UIBarButtonItem alloc] initWithTitle:RYGLocalized(@"Select All") style:UIBarButtonItemStylePlain target:self action:@selector(selectAll)];
		self.title = self.selectedPKs.count ? [NSString stringWithFormat:RYGLocalized(@"%lu selected"), (unsigned long)self.selectedPKs.count] : RYGLocalized(@"Select stories");
		return;
	}
	self.navigationItem.leftBarButtonItem = [[UIBarButtonItem alloc] initWithImage:[UIImage systemImageNamed:@"xmark"] style:UIBarButtonItemStylePlain target:self action:@selector(close)];
	self.title = RYGLocalized(@"Stories archive");
	self.navigationItem.rightBarButtonItem = [[UIBarButtonItem alloc] initWithImage:[RYGSymbol symbolWithIGName:@"fb_ic_dots_3_horizontal_filled_24" fallback:@"ellipsis" color:UIColor.labelColor size:22].image menu:[self dotsMenu]];
}

- (UIMenu *)dotsMenu {
	__weak typeof(self) w = self;
	UIAction *select = [UIAction actionWithTitle:RYGLocalized(@"Select") image:[RYGSymbol symbolWithIGName:@"selected-state-checkmark" fallback:@"checkmark.circle"].image identifier:nil handler:^(UIAction *ac) { [w enterSelection]; }];
	UIAction *settings = [UIAction actionWithTitle:RYGLocalized(@"Archive settings") image:[RYGSymbol symbolWithIGName:@"ig_icon_settings_outline_24" fallback:@"gearshape"].image identifier:nil handler:^(UIAction *ac) { [w openArchiveSettings]; }];
	UIAction *deleteAll = [UIAction actionWithTitle:RYGLocalized(@"Delete all") image:[RYGSymbol symbolWithIGName:@"ig_icon_delete_outline_24" fallback:@"trash"].image identifier:nil handler:^(UIAction *ac) { [w confirmDeleteAll]; }];
	deleteAll.attributes = UIMenuElementAttributesDestructive;
	UIMenu *tools = [UIMenu menuWithTitle:@"" image:nil identifier:nil options:UIMenuOptionsDisplayInline children:@[select, settings]];
	return [UIMenu menuWithTitle:@"" children:@[tools, deleteAll]];
}

- (void)openArchiveSettings {
	UIWindow *win = nil;
	for (UIWindow *ww in UIApplication.sharedApplication.windows) if (ww.isKeyWindow) { win = ww; break; }
	if (win) [RYGUtils showSettingsVC:win atTopLevelEntry:RYGLocalized(@"Stories archive")];
}

#pragma mark - Data build

- (void)reload {
	NSArray<RYGArchivedStory *> *all = self.store ? [self.store allStoriesSortedByDateDescending] : @[];

	NSMutableArray<RYGArchivedStory *> *filtered = [NSMutableArray array];
	for (RYGArchivedStory *s in all) {
		if (self.filter == RYGArchiveFilterPhotos && s.mediaType == 2) continue;
		if (self.filter == RYGArchiveFilterVideos && s.mediaType != 2) continue;
		if (self.reactedOnly && (s.likesCount + s.reactionsCount) == 0) continue;
		[filtered addObject:s];
	}

	if (self.sort == RYGArchiveSortOldest)
		filtered = [[[filtered reverseObjectEnumerator] allObjects] mutableCopy];
	else if (self.sort == RYGArchiveSortMostViewed)
		[filtered sortUsingComparator:^NSComparisonResult(RYGArchivedStory *a, RYGArchivedStory *b) { return a.viewersCount < b.viewersCount ? NSOrderedDescending : (a.viewersCount > b.viewersCount ? NSOrderedAscending : NSOrderedSame); }];
	else if (self.sort == RYGArchiveSortMostReacted)
		[filtered sortUsingComparator:^NSComparisonResult(RYGArchivedStory *a, RYGArchivedStory *b) { int64_t ra = a.likesCount + a.reactionsCount, rb = b.likesCount + b.reactionsCount; return ra < rb ? NSOrderedDescending : (ra > rb ? NSOrderedAscending : NSOrderedSame); }];

	self.groups = [self groupStories:filtered];
	self.emptyLabel.hidden = self.groups.count > 0;
	if (self.groups.count == 0)
		self.emptyLabel.text = [RYGUtils getBoolPref:@"ryg_stories_archive"]
			? RYGLocalized(@"No archived stories yet. Post a story and it appears here.")
			: RYGLocalized(@"Archiving is off. Enable it in the archive settings, then post a story.");
	[self.collectionView reloadData];
}

// Recent/Oldest → month sections; stat sorts → one flat section.
- (NSArray<NSDictionary *> *)groupStories:(NSArray<RYGArchivedStory *> *)stories {
	if (!stories.count) return @[];
	if (self.sort == RYGArchiveSortMostViewed) return @[@{ @"title": RYGLocalized(@"Most viewed"), @"stories": stories }];
	if (self.sort == RYGArchiveSortMostReacted) return @[@{ @"title": RYGLocalized(@"Most reacted"), @"stories": stories }];

	static NSDateFormatter *fmt;
	static dispatch_once_t once;
	dispatch_once(&once, ^{ fmt = [NSDateFormatter new]; fmt.dateFormat = @"LLLL yyyy"; });
	NSMutableArray *groups = [NSMutableArray array];
	NSMutableDictionary<NSString *, NSMutableArray *> *byMonth = [NSMutableDictionary dictionary];
	for (RYGArchivedStory *s in stories) {
		NSString *key = s.sectionID.length ? s.sectionID : @"0000-00";
		NSMutableArray *arr = byMonth[key];
		if (!arr) {
			arr = [NSMutableArray array];
			byMonth[key] = arr;
			[groups addObject:@{ @"title": s.takenAt ? [fmt stringFromDate:s.takenAt] : key, @"stories": arr }];
		}
		[arr addObject:s];
	}
	return groups;
}

- (RYGArchivedStory *)storyAt:(NSIndexPath *)ip {
	NSArray *stories = self.groups[ip.section][@"stories"];
	return ip.item < stories.count ? stories[ip.item] : nil;
}

#pragma mark - Selection

- (void)enterSelection {
	self.selecting = YES;
	[self.selectedPKs removeAllObjects];

	self.selectionBar = RYGMediaChromeInstallBottomBar(self.view);
	UIButton *save = RYGMediaChromeBottomButton(@"download", RYGLocalized(@"Save to Photos"));
	UIButton *share = RYGMediaChromeBottomButton(@"share", RYGLocalized(@"Share"));
	UIButton *trash = RYGMediaChromeBottomButton(@"trash", RYGLocalized(@"Delete"));
	trash.tintColor = UIColor.systemRedColor;
	[save addTarget:self action:@selector(saveSelected) forControlEvents:UIControlEventTouchUpInside];
	[share addTarget:self action:@selector(shareSelected) forControlEvents:UIControlEventTouchUpInside];
	[trash addTarget:self action:@selector(deleteSelected) forControlEvents:UIControlEventTouchUpInside];
	RYGMediaChromeInstallBottomRow(self.selectionBar, @[save, share, trash]);

	UIEdgeInsets inset = self.collectionView.contentInset;
	inset.bottom = RYGMediaChromeBottomBarHeight + self.view.safeAreaInsets.bottom;
	self.collectionView.contentInset = inset;
	self.collectionView.verticalScrollIndicatorInsets = inset;

	[self updateNavItems];
	[self.collectionView reloadData];
}

- (void)exitSelection {
	self.selecting = NO;
	[self.selectedPKs removeAllObjects];
	[self.selectionBar removeFromSuperview];
	self.selectionBar = nil;
	UIEdgeInsets inset = self.collectionView.contentInset;
	inset.bottom = 0;
	self.collectionView.contentInset = inset;
	self.collectionView.verticalScrollIndicatorInsets = inset;
	[self updateNavItems];
	[self.collectionView reloadData];
}

- (void)selectAll {
	for (NSDictionary *g in self.groups) for (RYGArchivedStory *s in g[@"stories"]) if (s.pk) [self.selectedPKs addObject:s.pk];
	[self updateNavItems];
	[self.collectionView reloadData];
}

- (NSArray<RYGArchivedStory *> *)selectedStories {
	NSMutableArray *out = [NSMutableArray array];
	for (NSDictionary *g in self.groups) for (RYGArchivedStory *s in g[@"stories"]) if ([self.selectedPKs containsObject:s.pk]) [out addObject:s];
	return out;
}

- (void)saveSelected {
	NSArray<RYGArchivedStory *> *stories = [self selectedStories];
	if (!stories.count) return;

	void (^saveAll)(BOOL) = ^(BOOL toGallery) {
		for (RYGArchivedStory *s in stories) [self saveStory:s toGallery:toGallery];
		[self exitSelection];
	};

	if (![RYGUtils getBoolPref:@"ryg_gallery_enabled"]) { saveAll(NO); return; }

	UIAlertController *sheet = [UIAlertController alertControllerWithTitle:nil message:nil preferredStyle:UIAlertControllerStyleActionSheet];
	[sheet addAction:[UIAlertAction actionWithTitle:RYGLocalized(@"Save to Photos") style:UIAlertActionStyleDefault handler:^(UIAlertAction *a) { saveAll(NO); }]];
	[sheet addAction:[UIAlertAction actionWithTitle:RYGLocalized(@"Save to Gallery") style:UIAlertActionStyleDefault handler:^(UIAlertAction *a) { saveAll(YES); }]];
	[sheet addAction:[UIAlertAction actionWithTitle:RYGLocalized(@"Cancel") style:UIAlertActionStyleCancel handler:nil]];
	sheet.popoverPresentationController.sourceView = self.selectionBar;
	[self presentViewController:sheet animated:YES completion:nil];
}

- (void)shareSelected {
	NSArray<RYGArchivedStory *> *stories = [self selectedStories];
	NSMutableArray *urls = [NSMutableArray array];
	for (RYGArchivedStory *s in stories) {
		NSString *p = [self.store absoluteMediaPathForStory:s];
		if (p) [urls addObject:[NSURL fileURLWithPath:p]];
	}
	if (!urls.count) return;
	UIActivityViewController *av = [[UIActivityViewController alloc] initWithActivityItems:urls applicationActivities:nil];
	av.popoverPresentationController.sourceView = self.selectionBar;
	[self presentViewController:av animated:YES completion:nil];
}

- (void)deleteSelected {
	NSArray<RYGArchivedStory *> *stories = [self selectedStories];
	if (!stories.count) return;
	NSString *msg = [NSString stringWithFormat:RYGLocalized(@"Delete %lu archived stories and their viewers?"), (unsigned long)stories.count];
	UIAlertController *alert = [UIAlertController alertControllerWithTitle:nil message:msg preferredStyle:UIAlertControllerStyleActionSheet];
	[alert addAction:[UIAlertAction actionWithTitle:RYGLocalized(@"Delete") style:UIAlertActionStyleDestructive handler:^(UIAlertAction *a) {
		for (RYGArchivedStory *s in stories) [self.store deleteStory:s];
		[self exitSelection];
		[self reload];
	}]];
	[alert addAction:[UIAlertAction actionWithTitle:RYGLocalized(@"Cancel") style:UIAlertActionStyleCancel handler:nil]];
	alert.popoverPresentationController.sourceView = self.selectionBar;
	[self presentViewController:alert animated:YES completion:nil];
}

- (void)confirmDeleteAll {
	UIAlertController *alert = [UIAlertController alertControllerWithTitle:RYGLocalized(@"Delete all stories?")
																   message:RYGLocalized(@"Removes every archived story and its viewers for this account. This cannot be undone.")
															preferredStyle:UIAlertControllerStyleAlert];
	[alert addAction:[UIAlertAction actionWithTitle:RYGLocalized(@"Cancel") style:UIAlertActionStyleCancel handler:nil]];
	[alert addAction:[UIAlertAction actionWithTitle:RYGLocalized(@"Delete all") style:UIAlertActionStyleDestructive handler:^(UIAlertAction *a) {
		[self.store deleteAllStories];
		[self reload];
	}]];
	[self presentViewController:alert animated:YES completion:nil];
}

#pragma mark - Data source

- (NSInteger)numberOfSectionsInCollectionView:(UICollectionView *)cv { return self.groups.count; }
- (NSInteger)collectionView:(UICollectionView *)cv numberOfItemsInSection:(NSInteger)section { return [self.groups[section][@"stories"] count]; }

- (UICollectionViewCell *)collectionView:(UICollectionView *)cv cellForItemAtIndexPath:(NSIndexPath *)ip {
	RYGStoriesArchiveCell *cell = [cv dequeueReusableCellWithReuseIdentifier:kCell forIndexPath:ip];
	RYGArchivedStory *s = [self storyAt:ip];
	NSString *thumb = [self.store absoluteThumbPathForStory:s] ?: [self.store absoluteMediaPathForStory:s];
	[cell configureWithThumbnailPath:thumb isVideo:s.mediaType == 2 viewerCount:s.viewersCount likeCount:s.likesCount];
	[cell configureDate:s.takenAt];
	[cell setChecked:self.selecting && [self.selectedPKs containsObject:s.pk]];
	return cell;
}

- (UICollectionReusableView *)collectionView:(UICollectionView *)cv viewForSupplementaryElementOfKind:(NSString *)kind atIndexPath:(NSIndexPath *)ip {
	if ([kind isEqualToString:kFilterHeader]) {
		UICollectionReusableView *v = [cv dequeueReusableSupplementaryViewOfKind:kind withReuseIdentifier:kFilterHeader forIndexPath:ip];
		if (self.filterRow.superview != v) {
			[self.filterRow removeFromSuperview];
			[v addSubview:self.filterRow];
			[NSLayoutConstraint activateConstraints:@[
				[self.filterRow.leadingAnchor constraintEqualToAnchor:v.leadingAnchor constant:14],
				[self.filterRow.trailingAnchor constraintEqualToAnchor:v.trailingAnchor constant:-14],
				[self.filterRow.centerYAnchor constraintEqualToAnchor:v.centerYAnchor],
			]];
		}
		return v;
	}
	UICollectionReusableView *header = [cv dequeueReusableSupplementaryViewOfKind:kind withReuseIdentifier:kHeader forIndexPath:ip];
	UILabel *label = [header viewWithTag:99];
	if (!label) {
		label = [[UILabel alloc] initWithFrame:header.bounds];
		label.tag = 99;
		label.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
		label.font = [UIFont systemFontOfSize:17 weight:UIFontWeightBold];
		label.textColor = UIColor.labelColor;
		[header addSubview:label];
		UILongPressGestureRecognizer *lp = [[UILongPressGestureRecognizer alloc] initWithTarget:self action:@selector(headerLongPress:)];
		[header addGestureRecognizer:lp];
	}
	header.tag = 1000 + ip.section;
	NSDictionary *g = self.groups[ip.section];
	label.text = [NSString stringWithFormat:@"%@  ·  %lu", g[@"title"], (unsigned long)[g[@"stories"] count]];
	return header;
}

// Long-press a month header to select every story in that month.
- (void)headerLongPress:(UILongPressGestureRecognizer *)gr {
	if (gr.state != UIGestureRecognizerStateBegan) return;
	NSInteger section = gr.view.tag - 1000;
	if (section < 0 || section >= (NSInteger)self.groups.count) return;
	if (!self.selecting) [self enterSelection];
	for (RYGArchivedStory *s in self.groups[section][@"stories"]) if (s.pk) [self.selectedPKs addObject:s.pk];
	[[[UIImpactFeedbackGenerator alloc] initWithStyle:UIImpactFeedbackStyleMedium] impactOccurred];
	[self updateNavItems];
	[self.collectionView reloadData];
}

#pragma mark - Delegate

- (void)collectionView:(UICollectionView *)cv didSelectItemAtIndexPath:(NSIndexPath *)ip {
	[cv deselectItemAtIndexPath:ip animated:NO];
	RYGArchivedStory *s = [self storyAt:ip];
	if (self.selecting) {
		if ([self.selectedPKs containsObject:s.pk]) [self.selectedPKs removeObject:s.pk]; else [self.selectedPKs addObject:s.pk];
		[(RYGStoriesArchiveCell *)[cv cellForItemAtIndexPath:ip] setChecked:[self.selectedPKs containsObject:s.pk]];
		[self updateNavItems];
		return;
	}
	NSInteger start = 0;
	NSArray *flat = [self flatStoriesWithTapped:s outIndex:&start];
	[RYGStoryMediaViewer presentStories:flat store:self.store startIndex:start from:self];
}

- (NSArray<RYGArchivedStory *> *)flatStoriesWithTapped:(RYGArchivedStory *)tapped outIndex:(NSInteger *)outIndex {
	NSMutableArray *flat = [NSMutableArray array];
	NSInteger idx = 0;
	for (NSDictionary *g in self.groups) for (RYGArchivedStory *s in g[@"stories"]) {
		if (s == tapped && outIndex) *outIndex = idx;
		[flat addObject:s];
		idx++;
	}
	return flat;
}

- (nullable UIContextMenuConfiguration *)collectionView:(UICollectionView *)cv contextMenuConfigurationForItemAtIndexPath:(NSIndexPath *)ip point:(CGPoint)point {
	if (self.selecting) return nil;
	RYGArchivedStory *s = [self storyAt:ip];
	if (!s) return nil;
	__weak typeof(self) w = self;
	return [UIContextMenuConfiguration configurationWithIdentifier:nil previewProvider:nil actionProvider:^UIMenu *(NSArray<UIMenuElement *> *elements) {
		NSMutableArray<UIMenuElement *> *actions = [NSMutableArray array];
		if (s.viewersCount) {
			[actions addObject:[UIAction actionWithTitle:RYGLocalized(@"View viewers")
												   image:[RYGSymbol symbolWithIGName:@"ig_icon_eye_outline_24" fallback:@"eye"].image
											  identifier:nil handler:^(UIAction *a) { [RYGStoryViewersSheet presentForStory:s from:w]; }]];
		}
		[actions addObject:[UIAction actionWithTitle:RYGLocalized(@"Save to Photos")
											   image:[RYGSymbol symbolWithIGName:@"download_filled" fallback:@"square.and.arrow.down"].image
										  identifier:nil handler:^(UIAction *a) { [w saveStory:s toGallery:NO]; }]];
		if ([RYGUtils getBoolPref:@"ryg_gallery_enabled"]) {
			[actions addObject:[UIAction actionWithTitle:RYGLocalized(@"Save to Gallery")
												   image:[RYGSymbol symbolWithIGName:@"ig_icon_photo_gallery_prism_outline_24" fallback:@"square.grid.2x2"].image
											  identifier:nil handler:^(UIAction *a) { [w saveStory:s toGallery:YES]; }]];
		}
		[actions addObject:[UIAction actionWithTitle:RYGLocalized(@"Share")
											   image:[RYGSymbol symbolWithIGName:@"ig_icon_direct_share_outline_24" fallback:@"square.and.arrow.up"].image
										  identifier:nil handler:^(UIAction *a) { [w exportStory:s]; }]];
		UIAction *del = [UIAction actionWithTitle:RYGLocalized(@"Delete")
											image:[RYGSymbol symbolWithIGName:@"ig_icon_delete_outline_24" fallback:@"trash"].image
									   identifier:nil handler:^(UIAction *a) { [w confirmDeleteStory:s]; }];
		del.attributes = UIMenuElementAttributesDestructive;
		[actions addObject:del];
		return [UIMenu menuWithTitle:@"" children:actions];
	}];
}

#pragma mark - Single actions

- (void)exportStory:(RYGArchivedStory *)s {
	NSString *path = [self.store absoluteMediaPathForStory:s];
	if (!path) return;
	UIActivityViewController *av = [[UIActivityViewController alloc] initWithActivityItems:@[[NSURL fileURLWithPath:path]] applicationActivities:nil];
	av.popoverPresentationController.sourceView = self.view;
	av.popoverPresentationController.sourceRect = CGRectMake(CGRectGetMidX(self.view.bounds), CGRectGetMidY(self.view.bounds), 1, 1);
	[self presentViewController:av animated:YES completion:nil];
}

- (void)saveStory:(RYGArchivedStory *)s toGallery:(BOOL)toGallery {
	NSString *path = [self.store absoluteMediaPathForStory:s];
	if (!path) return;
	RYGDownloadDelegate *dl = [[RYGDownloadDelegate alloc] initWithAction:(toGallery ? saveToGallery : saveToPhotos) showProgress:YES];
	if (toGallery) {
		RYGGallerySaveMetadata *meta = [RYGGallerySaveMetadata new];
		meta.source = RYGGallerySourceStories;
		meta.sourceUserPK = self.store.accountPK;
		dl.pendingGallerySaveMetadata = meta;
	}
	NSString *ext = s.mediaType == 2 ? @"mp4" : @"jpg";
	[dl saveLocalFileURL:[NSURL fileURLWithPath:path] hudLabel:[NSString stringWithFormat:@"story.%@", ext]];
}

- (void)confirmDeleteStory:(RYGArchivedStory *)s {
	UIAlertController *alert = [UIAlertController alertControllerWithTitle:RYGLocalized(@"Delete story?")
																   message:RYGLocalized(@"This removes the archived photo or video and its viewers.")
															preferredStyle:UIAlertControllerStyleAlert];
	[alert addAction:[UIAlertAction actionWithTitle:RYGLocalized(@"Cancel") style:UIAlertActionStyleCancel handler:nil]];
	[alert addAction:[UIAlertAction actionWithTitle:RYGLocalized(@"Delete") style:UIAlertActionStyleDestructive handler:^(UIAlertAction *a) {
		[self.store deleteStory:s];
		[self reload];
	}]];
	[self presentViewController:alert animated:YES completion:nil];
}

@end
