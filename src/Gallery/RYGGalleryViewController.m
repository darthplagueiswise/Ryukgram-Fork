#import "RYGGalleryViewController.h"
#import "RYGGalleryFile.h"
#import "RYGGalleryGridCell.h"
#import "RYGGalleryListCollectionCell.h"
#import "RYGGalleryFolderCell.h"
#import "RYGGalleryCoreDataStack.h"
#import "RYGGallerySheetViewController.h"
#import "RYGGallerySortViewController.h"
#import "RYGGalleryFilterViewController.h"
#import "RYGGallerySettingsViewController.h"
#import "RYGGalleryImporter.h"
#import "RYGGalleryDeleteViewController.h"
#import "RYGGalleryOriginController.h"
#import "RYGMediaChrome.h"
#import "../UI/RYGScrollToTopButton.h"
#import "../Lock/RYGLockGate.h"
#import "../Lock/RYGLockGroups.h"
#import "../InstagramHeaders.h"
#import "../ActionButton/RYGMediaViewer.h"
#import "../ActionButton/RYGMediaActions.h"
#import "RYGAssetUtils.h"
#import "RYGGalleryPaths.h"
#import "../Utils.h"
#import "RYGGalleryShim.h"
#import "../UI/RYGPopupChrome.h"
#import "../UI/Notification/RYGNotificationCenter.h"
#import "../UI/Notification/RYGNotificationActions.h"
#import <CoreData/CoreData.h>

static NSString * const kGridCellID = @"RYGGalleryGridCell";
static NSString * const kListCellID = @"RYGGalleryListCell";
static NSString * const kFolderCellID = @"RYGGalleryFolderCell";
static NSString * const kUserHeaderID = @"RYGGalleryUserHeader";

static NSString * const kViewModeKey = @"gallery_view_mode";
static NSString * const kGridColumnsKey = @"gallery_grid_columns";
static NSString * const kFavoritesAtTopKey = @"show_favorites_at_top";
static NSString * const kGroupModeKey = @"gallery_group_mode";
static NSString * const kGroupModeOff = @"off";
static NSString * const kGroupModeSections = @"sections";
static NSString * const kGroupModeFolders = @"folders";

static CGFloat const kUserHeaderHeight = 36.0;

@interface RYGGalleryUserHeaderView : UICollectionReusableView
@property (nonatomic, strong) UILabel *titleLabel;
@end

@implementation RYGGalleryUserHeaderView
- (instancetype)initWithFrame:(CGRect)frame {
	if ((self = [super initWithFrame:frame])) {
		self.backgroundColor = [UIColor clearColor];
		_titleLabel = [UILabel new];
		_titleLabel.translatesAutoresizingMaskIntoConstraints = NO;
		_titleLabel.font = [UIFont systemFontOfSize:15 weight:UIFontWeightSemibold];
		_titleLabel.textColor = [UIColor secondaryLabelColor];
		[self addSubview:_titleLabel];
		[NSLayoutConstraint activateConstraints:@[
			[_titleLabel.leadingAnchor constraintEqualToAnchor:self.leadingAnchor constant:16],
			[_titleLabel.trailingAnchor constraintEqualToAnchor:self.trailingAnchor constant:-16],
			[_titleLabel.topAnchor constraintEqualToAnchor:self.topAnchor constant:8],
			[_titleLabel.bottomAnchor constraintEqualToAnchor:self.bottomAnchor constant:-4],
		]];
	}
	return self;
}
@end

static CGFloat const kGridSpacing = 2.0;
static CGFloat const kGalleryBottomBarInsetHeight = 64.0;

static NSString *RYGGalleryFolderDateLabel(NSDate *date) {
	if (!date) return nil;

	NSCalendar *cal = [NSCalendar currentCalendar];
	if ([cal isDateInToday:date])	  return RYGLocalized(@"Today");
	if ([cal isDateInYesterday:date]) return RYGLocalized(@"Yesterday");

	static NSDateFormatter *recent;
	static NSDateFormatter *older;
	static dispatch_once_t once;
	dispatch_once(&once, ^{
		recent = [NSDateFormatter new];
		recent.dateFormat = @"MMM d";
		older = [NSDateFormatter new];
		older.dateFormat = @"MMM d, yyyy";
	});

	NSInteger nowYear   = [cal component:NSCalendarUnitYear fromDate:[NSDate date]];
	NSInteger dateYear  = [cal component:NSCalendarUnitYear fromDate:date];
	return (nowYear == dateYear) ? [recent stringFromDate:date] : [older stringFromDate:date];
}

static NSString *RYGGalleryFolderSubtitle(NSInteger itemCount, long long totalSize, NSDate *lastDate) {
	NSMutableArray<NSString *> *parts = [NSMutableArray array];

	[parts addObject:[NSString stringWithFormat:@"%ld %@",
		(long)itemCount,
		itemCount == 1 ? RYGLocalized(@"item") : RYGLocalized(@"items")]];

	if (totalSize > 0) {
		[parts addObject:[NSByteCountFormatter stringFromByteCount:totalSize countStyle:NSByteCountFormatterCountStyleFile]];
	}

	NSString *dateText = RYGGalleryFolderDateLabel(lastDate);
	if (dateText.length) [parts addObject:dateText];

	return [parts componentsJoinedByString:@" · "];
}

static NSString *RYGGalleryCleanFolderPath(NSString *path) {
	if (![path isKindOfClass:[NSString class]]) return @"";

	NSString *clean = [path stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];

	while ([clean hasPrefix:@"/"]) {
		clean = [clean substringFromIndex:1];
	}

	while ([clean hasSuffix:@"/"]) {
		clean = [clean substringToIndex:clean.length - 1];
	}

	return clean ?: @"";
}

static NSString *RYGGalleryStoredFolderPath(NSString *cleanPath) {
	if (!cleanPath.length) return @"";
	return [@"/" stringByAppendingString:cleanPath];
}

static NSString *RYGGalleryImmediateChildPath(NSString *folderPath, NSString *basePath) {
	NSString *folder = RYGGalleryCleanFolderPath(folderPath);
	NSString *base = RYGGalleryCleanFolderPath(basePath);

	if (!folder.length) return nil;

	if (base.length) {
		if (![folder isEqualToString:base] && ![folder hasPrefix:[base stringByAppendingString:@"/"]]) return nil;
		if ([folder isEqualToString:base]) return nil;

		folder = [folder substringFromIndex:base.length + 1];
	}

	NSString *first = [[folder componentsSeparatedByString:@"/"] firstObject];
	if (!first.length) return nil;

	NSString *child = base.length ? [[base stringByAppendingPathComponent:first] copy] : first;
	return RYGGalleryStoredFolderPath(child);
}

#import "RYGGalleryViewController_Internal.h"

@interface RYGGalleryViewController ()
@property (nonatomic, strong) NSDictionary<NSString *, NSNumber *> *subfolderCounts;
@property (nonatomic, copy) dispatch_block_t searchDebounceBlock;
- (void)finishPickerWithURL:(NSURL *)url file:(RYGGalleryFile *)file;
@end

@implementation RYGGalleryViewController

+ (void)load {
	[[RYGNotificationCenter shared] setDefaultTapProvider:^void (^(void))(void) {
		if (![RYGUtils getBoolPref:@"ryg_gallery_enabled"]) return nil;
		return ^{ [RYGGalleryViewController presentGallery]; };
	} ownerVCClass:[RYGGalleryViewController class]
	  forAction:RYG_NOTIF_GALLERY_SAVE];
}

#pragma mark - Presentation

+ (void)presentGallery {
	[RYGLockGate presentLockedVC:[RYGGalleryViewController new]
	                    forGroup:RYGLockGroupGallery
	                        from:topMostController()];
}

+ (void)presentPickerWithMediaTypes:(NSArray<NSNumber *> *)allowedMediaTypes
							  title:(NSString *)title
							 fromVC:(UIViewController *)fromVC
						 completion:(void (^)(NSURL *, RYGGalleryFile *))completion {
	RYGGalleryViewController *vc = [[RYGGalleryViewController alloc] init];

	vc.pickerMode = YES;
	vc.pickerAllowedMediaTypes = [allowedMediaTypes copy];
	vc.pickerCompletion = [completion copy];
	vc.pickerTitleOverride = [title copy];

	[RYGLockGate presentLockedVC:vc forGroup:RYGLockGroupGallery from:(fromVC ?: topMostController())];
}

#pragma mark - Init

- (instancetype)init {
	return [self initWithFolderPath:nil];
}

- (instancetype)initWithFolderPath:(NSString *)folderPath {
	self = [super init];
	if (!self) return nil;

	_currentFolderPath = [folderPath copy];
	_filterTypes = [NSMutableSet set];
	_filterSources = [NSMutableSet set];
	_filterUsernames = [NSMutableSet set];
	_selectedFileIDs = [NSMutableSet set];
	_subfolders = @[];
	_subfolderCounts = @{};
	_userFolders = @[];
	_userFolderCounts = @{};

	_viewMode = (RYGGalleryViewMode)(NSInteger)[RYGUtils getDoublePref:kViewModeKey];

	return self;
}

- (instancetype)initWithUsernameScope:(NSString *)username {
	self = [self initWithFolderPath:nil];
	if (!self) return nil;

	_usernameScope = [username copy];

	return self;
}

#pragma mark - Lifecycle

- (void)viewDidLoad {
	[super viewDidLoad];

	self.view.backgroundColor = [RYGPopupChrome backgroundColor];

	[[NSNotificationCenter defaultCenter] addObserver:self
											 selector:@selector(handleGalleryPreferencesChanged:)
												 name:@"RYGGalleryFavoritesSortPreferenceChanged"
											   object:nil];

	[[NSNotificationCenter defaultCenter] addObserver:self
											 selector:@selector(handleGalleryContextSaved:)
												 name:NSManagedObjectContextDidSaveNotification
											   object:[RYGGalleryCoreDataStack shared].viewContext];

	[self setupCenteredTitle];
	[self setupNavigationItems];
	[self setupSearchController];
	[self setupBottomToolbar];
	[self setupCollectionView];
	[self setupEmptyState];
	[self setupScrollToTopButton];
	[self setupFetchedResultsController];
	[self reloadSubfolders];
	[self updateEmptyState];

	if ([self.navigationController.viewControllers firstObject] == self) {
		self.navigationController.presentationController.delegate = self;
	}
}

- (void)dealloc {
	if (self.searchDebounceBlock) {
		dispatch_block_cancel(self.searchDebounceBlock);
	}

	[[NSNotificationCenter defaultCenter] removeObserver:self];
}

- (void)viewWillAppear:(BOOL)animated {
	[super viewWillAppear:animated];

	[self applyGalleryNavigationChrome];
	[self setupCenteredTitle];
	[self installBottomToolbarIfNeeded];
	[self refreshNavigationItems];
	[self refreshBottomToolbarItems];
	[self updateCollectionInsets];
}

- (void)viewDidAppear:(BOOL)animated {
	[super viewDidAppear:animated];
	[self offerLegacyMigrationIfNeeded];
}

- (void)viewWillDisappear:(BOOL)animated {
	[super viewWillDisappear:animated];

	if (self.bottomBar.superview) {
		[self.bottomBar removeFromSuperview];
	}
}

- (void)viewSafeAreaInsetsDidChange {
	[super viewSafeAreaInsetsDidChange];
	[self updateCollectionInsets];
}

- (void)presentationControllerDidDismiss:(UIPresentationController *)presentationController {
	(void)presentationController;

	if (self.pickerMode && self.pickerCompletion) {
		[self finishPickerWithURL:nil file:nil];
	}
}

#pragma mark - Picker

- (void)finishPickerWithURL:(NSURL *)url file:(RYGGalleryFile *)file {
	void (^callback)(NSURL *, RYGGalleryFile *) = self.pickerCompletion;
	UINavigationController *nav = self.navigationController;

	for (UIViewController *vc in nav.viewControllers) {
		if ([vc isKindOfClass:[RYGGalleryViewController class]]) {
			((RYGGalleryViewController *)vc).pickerCompletion = nil;
		}
	}

	[nav dismissViewControllerAnimated:YES completion:^{
		if (callback) callback(url, file);
	}];
}

- (void)pickerCancelTapped {
	[self finishPickerWithURL:nil file:nil];
}

- (void)dismissSelf {
	[self.navigationController dismissViewControllerAnimated:YES completion:nil];
}

#pragma mark - Navigation & chrome

- (void)applyGalleryNavigationChrome {
}

- (void)setupCenteredTitle {
	if (self.pickerMode && self.pickerTitleOverride.length && !self.currentFolderPath.length) {
		self.title = self.pickerTitleOverride;
	} else if (self.usernameScope.length) {
		self.title = [@"@" stringByAppendingString:self.usernameScope];
	} else {
		self.title = self.currentFolderPath.length ? [self.currentFolderPath lastPathComponent] : RYGLocalized(@"Gallery");
	}

	self.navigationItem.titleView = nil;
}

- (void)setupNavigationItems {
	[self refreshNavigationItems];
}

- (void)refreshNavigationItems {
	if (self.pickerMode) {
		self.navigationItem.rightBarButtonItem = nil;
		self.navigationItem.rightBarButtonItems = nil;
		self.navigationItem.leftBarButtonItem = ([self.navigationController.viewControllers firstObject] == self)
			? [[UIBarButtonItem alloc] initWithTitle:RYGLocalized(@"Cancel")
											   style:UIBarButtonItemStylePlain
											  target:self
											  action:@selector(pickerCancelTapped)]
			: nil;
		return;
	}

	if (self.selectionMode) {
		NSArray<RYGGalleryFile *> *files = [self visibleGalleryFiles];
		BOOL allSelected = files.count > 0 && self.selectedFileIDs.count == files.count;

		self.navigationItem.rightBarButtonItems = nil;
		self.navigationItem.leftBarButtonItem = [[UIBarButtonItem alloc] initWithTitle:RYGLocalized(@"Cancel")
																				 style:UIBarButtonItemStylePlain
																				target:self
																				action:@selector(exitSelectionMode)];
		self.navigationItem.rightBarButtonItem = [[UIBarButtonItem alloc] initWithTitle:(allSelected ? RYGLocalized(@"Deselect All") : RYGLocalized(@"Select All"))
																				  style:UIBarButtonItemStylePlain
																				 target:self
																				 action:@selector(selectAllVisibleFiles)];
		return;
	}

	BOOL root = ([self.navigationController.viewControllers firstObject] == self);

	self.navigationItem.leftBarButtonItems = nil;
	self.navigationItem.leftBarButtonItem = root ? RYGMediaChromeTopBarButtonItem(@"xmark", self, @selector(dismissSelf)) : nil;

	NSMutableArray<UIBarButtonItem *> *items = [NSMutableArray array];

	// ••• overflow (Import + Settings) at the edge, Select as its own icon.
	NSMutableArray<UIAction *> *menuActions = [NSMutableArray array];
	[menuActions addObject:[UIAction actionWithTitle:RYGLocalized(@"Import") image:RYGMediaChromeTopIcon(@"download") identifier:nil handler:^(__unused UIAction *a) { [self presentGalleryImport]; }]];
	if (root) [menuActions addObject:[UIAction actionWithTitle:RYGLocalized(@"Settings") image:RYGMediaChromeTopIcon(@"settings") identifier:nil handler:^(__unused UIAction *a) { [self pushSettings]; }]];

	if (menuActions.count > 1) {
		UIBarButtonItem *overflow = [[UIBarButtonItem alloc] initWithImage:RYGMediaChromeTopIcon(@"more")
																	  menu:[UIMenu menuWithTitle:@"" children:menuActions]];
		overflow.tintColor = [UIColor labelColor];
		[items addObject:overflow];
	} else {
		[items addObject:RYGMediaChromeTopBarButtonItem(@"download", self, @selector(presentGalleryImport))];
	}
	[items addObject:RYGMediaChromeTopBarButtonItem(@"circle_check", self, @selector(enterSelectionMode))];

	self.navigationItem.rightBarButtonItem = nil;
	self.navigationItem.rightBarButtonItems = items;
}

#pragma mark - Search

- (void)setupSearchController {
	UISearchController *controller = [[UISearchController alloc] initWithSearchResultsController:nil];

	controller.obscuresBackgroundDuringPresentation = NO;
	controller.hidesNavigationBarDuringPresentation = NO;
	controller.searchResultsUpdater = self;
	controller.searchBar.placeholder = RYGLocalized(@"Search");

	self.searchController = controller;
	self.navigationItem.searchController = controller;
	self.navigationItem.hidesSearchBarWhenScrolling = YES;
	self.definesPresentationContext = YES;

	if (@available(iOS 26.0, *)) {
		@try {
			[self.navigationItem setValue:@2 forKey:@"preferredSearchBarPlacement"];
		} @catch (NSException *exception) {
			(void)exception;
		}
	}
}

- (void)activateSearch {
	UISearchController *controller = self.searchController;
	if (!controller) return;

	UICollectionView *cv = self.collectionView;
	CGFloat topOffset = -cv.adjustedContentInset.top;

	if (cv.contentOffset.y > topOffset) {
		[cv setContentOffset:CGPointMake(cv.contentOffset.x, topOffset) animated:NO];
	}

	[cv layoutIfNeeded];
	[self.navigationController.navigationBar layoutIfNeeded];
	[self.view layoutIfNeeded];

	controller.active = YES;

	dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.05 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
		if (!controller.active) controller.active = YES;
		[controller.searchBar becomeFirstResponder];
	});
}

- (void)updateSearchResultsForSearchController:(UISearchController *)searchController {
	NSString *nextQuery = searchController.searchBar.text ?: @"";

	if ([(self.searchQuery ?: @"") isEqualToString:nextQuery]) return;

	self.searchQuery = nextQuery;

	if (self.searchDebounceBlock) {
		dispatch_block_cancel(self.searchDebounceBlock);
	}

	__weak typeof(self) weakSelf = self;
	dispatch_block_t block = dispatch_block_create(0, ^{
		[weakSelf refetch];
	});

	self.searchDebounceBlock = block;

	dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.18 * NSEC_PER_SEC)), dispatch_get_main_queue(), block);
}

#pragma mark - Bottom toolbar

- (void)setupBottomToolbar {
	[self installBottomToolbarIfNeeded];
	[self refreshBottomToolbarItems];
}

- (void)installBottomToolbarIfNeeded {
	UIView *host = self.navigationController.view ?: self.view;

	if (self.bottomBar.superview == host) return;

	[self.bottomBar removeFromSuperview];

	self.bottomBar = RYGMediaChromeInstallBottomBar(host);
	self.bottomBarStack = nil;
}

- (UIButton *)galleryBottomBarButtonWithResource:(NSString *)resourceName accessibility:(NSString *)label {
	return RYGMediaChromeBottomButton(resourceName, label);
}

- (void)refreshBottomToolbarItems {
	[self installBottomToolbarIfNeeded];

	[self.bottomBarStack removeFromSuperview];
	self.bottomBarStack = nil;

	UIButton *searchBtn = [self galleryBottomBarButtonWithResource:@"search" accessibility:RYGLocalized(@"Search")];
	[searchBtn addTarget:self action:@selector(activateSearch) forControlEvents:UIControlEventTouchUpInside];

	if (self.selectionMode) {
		UIButton *shareBtn = [self galleryBottomBarButtonWithResource:@"share" accessibility:RYGLocalized(@"Share selected")];
		UIButton *saveBtn = [self galleryBottomBarButtonWithResource:@"download" accessibility:RYGLocalized(@"Save to Photos")];
		UIButton *moveBtn = [self galleryBottomBarButtonWithResource:@"folder_move" accessibility:RYGLocalized(@"Move selected")];
		UIButton *favoriteBtn = [self galleryBottomBarButtonWithResource:@"heart" accessibility:RYGLocalized(@"Favorite selected")];
		UIButton *deleteBtn = [self galleryBottomBarButtonWithResource:@"trash" accessibility:RYGLocalized(@"Delete selected")];

		[shareBtn addTarget:self action:@selector(shareSelectedFiles) forControlEvents:UIControlEventTouchUpInside];
		[saveBtn addTarget:self action:@selector(saveSelectedFilesToPhotos) forControlEvents:UIControlEventTouchUpInside];
		[moveBtn addTarget:self action:@selector(moveSelectedFiles) forControlEvents:UIControlEventTouchUpInside];
		[favoriteBtn addTarget:self action:@selector(toggleFavoriteForSelectedFiles) forControlEvents:UIControlEventTouchUpInside];
		[deleteBtn addTarget:self action:@selector(deleteSelectedFiles) forControlEvents:UIControlEventTouchUpInside];

		deleteBtn.tintColor = [UIColor systemRedColor];

		self.bottomBarStack = RYGMediaChromeInstallBottomRow(self.bottomBar, @[shareBtn, saveBtn, moveBtn, favoriteBtn, deleteBtn]);
		return;
	}

	UIButton *filterBtn = [self galleryBottomBarButtonWithResource:@"filter" accessibility:RYGLocalized(@"Filter")];
	UIButton *sortBtn = [self galleryBottomBarButtonWithResource:@"sort" accessibility:RYGLocalized(@"Sort")];
	UIButton *folderBtn = [self galleryBottomBarButtonWithResource:@"folder" accessibility:RYGLocalized(@"New Folder")];

	NSString *toggleResource = self.viewMode == RYGGalleryViewModeGrid ? @"list" : @"grid";
	NSString *toggleAX = self.viewMode == RYGGalleryViewModeGrid ? RYGLocalized(@"List view") : RYGLocalized(@"Grid view");
	UIButton *toggleBtn = [self galleryBottomBarButtonWithResource:toggleResource accessibility:toggleAX];

	[filterBtn addTarget:self action:@selector(presentFilter) forControlEvents:UIControlEventTouchUpInside];
	[sortBtn addTarget:self action:@selector(presentSort) forControlEvents:UIControlEventTouchUpInside];
	[folderBtn addTarget:self action:@selector(presentCreateFolder) forControlEvents:UIControlEventTouchUpInside];
	[toggleBtn addTarget:self action:@selector(toggleViewMode) forControlEvents:UIControlEventTouchUpInside];

	NSArray<UIView *> *row = self.pickerMode
		? @[toggleBtn, sortBtn, filterBtn, searchBtn]
		: @[toggleBtn, sortBtn, filterBtn, folderBtn, searchBtn];

	self.bottomBarStack = RYGMediaChromeInstallBottomRow(self.bottomBar, row);
}

#pragma mark - Collection View

- (void)setupCollectionView {
	_collectionView = [[UICollectionView alloc] initWithFrame:CGRectZero collectionViewLayout:[self layoutForViewMode:self.viewMode]];
	_collectionView.translatesAutoresizingMaskIntoConstraints = NO;
	_collectionView.backgroundColor = self.view.backgroundColor;
	_collectionView.dataSource = self;
	_collectionView.delegate = self;
	_collectionView.alwaysBounceVertical = YES;
	_collectionView.keyboardDismissMode = UIScrollViewKeyboardDismissModeInteractive;

	[_collectionView registerClass:[RYGGalleryGridCell class] forCellWithReuseIdentifier:kGridCellID];
	[_collectionView registerClass:[RYGGalleryListCollectionCell class] forCellWithReuseIdentifier:kListCellID];
	[_collectionView registerClass:[RYGGalleryFolderCell class] forCellWithReuseIdentifier:kFolderCellID];
	[_collectionView registerClass:[RYGGalleryUserHeaderView class]
		forSupplementaryViewOfKind:UICollectionElementKindSectionHeader
			   withReuseIdentifier:kUserHeaderID];

	[self.view addSubview:_collectionView];

	[NSLayoutConstraint activateConstraints:@[
		[_collectionView.topAnchor constraintEqualToAnchor:self.view.topAnchor],
		[_collectionView.bottomAnchor constraintEqualToAnchor:self.view.bottomAnchor],
		[_collectionView.leadingAnchor constraintEqualToAnchor:self.view.leadingAnchor],
		[_collectionView.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor],
	]];
}

- (void)updateCollectionInsets {
	CGFloat bottomInset = kGalleryBottomBarInsetHeight + self.view.safeAreaInsets.bottom;

	UIEdgeInsets content = self.collectionView.contentInset;
	UIEdgeInsets indicators = self.collectionView.scrollIndicatorInsets;

	content.bottom = bottomInset;
	indicators.bottom = bottomInset;

	self.collectionView.contentInset = content;
	self.collectionView.scrollIndicatorInsets = indicators;
}

- (UICollectionViewLayout *)layoutForViewMode:(RYGGalleryViewMode)mode {
	if (mode == RYGGalleryViewModeGrid) {
		UICollectionViewFlowLayout *layout = [UICollectionViewFlowLayout new];
		layout.minimumInteritemSpacing = kGridSpacing;
		layout.minimumLineSpacing = kGridSpacing;
		return layout;
	}

	__weak typeof(self) weakSelf = self;

	UICollectionViewCompositionalLayoutSectionProvider provider = ^NSCollectionLayoutSection *(NSInteger sectionIndex, id<NSCollectionLayoutEnvironment> env) {
		typeof(self) self = weakSelf;
		if (!self) return nil;

		if ([self showsFolderSection] && sectionIndex == 0) {
			NSCollectionLayoutSize *size = [NSCollectionLayoutSize sizeWithWidthDimension:[NSCollectionLayoutDimension fractionalWidthDimension:1.0]
																		  heightDimension:[NSCollectionLayoutDimension absoluteDimension:88]];
			NSCollectionLayoutItem *item = [NSCollectionLayoutItem itemWithLayoutSize:size];
			NSCollectionLayoutGroup *group = [NSCollectionLayoutGroup horizontalGroupWithLayoutSize:size subitems:@[item]];
			NSCollectionLayoutSection *section = [NSCollectionLayoutSection sectionWithGroup:group];

			section.contentInsets = NSDirectionalEdgeInsetsMake(10, 0, 6, 0);

			return section;
		}

		UICollectionLayoutListConfiguration *config = [[UICollectionLayoutListConfiguration alloc] initWithAppearance:UICollectionLayoutListAppearancePlain];

		config.showsSeparators = NO;
		config.backgroundColor = [UIColor clearColor];
		config.trailingSwipeActionsConfigurationProvider = ^UISwipeActionsConfiguration *(NSIndexPath *idx) {
			typeof(self) self = weakSelf;
			if (!self) return nil;

			RYGGalleryFile *file = [self galleryFileForCollectionIndexPath:idx];
			if (!file) return nil;

			UIContextualAction *deleteAction = [UIContextualAction contextualActionWithStyle:UIContextualActionStyleDestructive
																					   title:RYGLocalized(@"Delete")
																					 handler:^(UIContextualAction *action, UIView *view, void (^completion)(BOOL)) {
				(void)action;
				(void)view;

				[self confirmDeleteFile:file];
				completion(YES);
			}];

			deleteAction.image = [RYGAssetUtils instagramIconNamed:@"trash" pointSize:20.0];

			return [UISwipeActionsConfiguration configurationWithActions:@[deleteAction]];
		};

		NSCollectionLayoutSection *section = [NSCollectionLayoutSection sectionWithListConfiguration:config layoutEnvironment:env];

		if ([self isGroupingByUser]) {
			NSCollectionLayoutSize *headerSize = [NSCollectionLayoutSize sizeWithWidthDimension:[NSCollectionLayoutDimension fractionalWidthDimension:1.0]
																				heightDimension:[NSCollectionLayoutDimension absoluteDimension:kUserHeaderHeight]];
			NSCollectionLayoutBoundarySupplementaryItem *header = [NSCollectionLayoutBoundarySupplementaryItem boundarySupplementaryItemWithLayoutSize:headerSize
																																		 elementKind:UICollectionElementKindSectionHeader
																																		   alignment:NSRectAlignmentTop];
			section.boundarySupplementaryItems = @[header];
		}

		return section;
	};

	return [[UICollectionViewCompositionalLayout alloc] initWithSectionProvider:provider];
}

- (void)toggleViewMode {
	if (self.selectionMode) {
		[self exitSelectionMode];
	}

	self.viewMode = self.viewMode == RYGGalleryViewModeGrid ? RYGGalleryViewModeList : RYGGalleryViewModeGrid;

	[RYGUtils setPref:@(self.viewMode) forKey:kViewModeKey];

	[self.collectionView setCollectionViewLayout:[self layoutForViewMode:self.viewMode] animated:NO];
	[self.collectionView reloadData];
	[self updateEmptyState];
	[self refreshBottomToolbarItems];
}

#pragma mark - Empty State

- (void)setupScrollToTopButton {
	RYGScrollToTopButton *btn = [RYGScrollToTopButton new];

	[btn attachToScrollView:self.collectionView inView:self.view bottomInset:(RYGMediaChromeBottomBarHeight + 16)];

	self.scrollToTopButton = btn;
}

- (void)setupEmptyState {
	_emptyStateView = [UIView new];
	_emptyStateView.translatesAutoresizingMaskIntoConstraints = NO;
	_emptyStateView.hidden = YES;

	[self.view addSubview:_emptyStateView];

	UIImageView *icon = [[UIImageView alloc] initWithImage:[RYGAssetUtils instagramIconNamed:@"media_empty" pointSize:96.0]];
	icon.translatesAutoresizingMaskIntoConstraints = NO;
	icon.contentMode = UIViewContentModeScaleAspectFit;
	icon.tintColor = [UIColor tertiaryLabelColor];

	[_emptyStateView addSubview:icon];

	_emptyStateLabel = [UILabel new];
	_emptyStateLabel.translatesAutoresizingMaskIntoConstraints = NO;
	_emptyStateLabel.text = RYGLocalized(@"No files in Gallery");
	_emptyStateLabel.textColor = [UIColor secondaryLabelColor];
	_emptyStateLabel.font = [UIFont systemFontOfSize:17 weight:UIFontWeightMedium];
	_emptyStateLabel.textAlignment = NSTextAlignmentCenter;

	[_emptyStateView addSubview:_emptyStateLabel];

	UILabel *subtitle = [UILabel new];
	subtitle.translatesAutoresizingMaskIntoConstraints = NO;
	subtitle.text = RYGLocalized(@"Save media from the preview screen\nto see it here.");
	subtitle.textColor = [UIColor tertiaryLabelColor];
	subtitle.font = [UIFont systemFontOfSize:14];
	subtitle.textAlignment = NSTextAlignmentCenter;
	subtitle.numberOfLines = 0;

	[_emptyStateView addSubview:subtitle];

	[NSLayoutConstraint activateConstraints:@[
		[_emptyStateView.centerXAnchor constraintEqualToAnchor:self.view.centerXAnchor],
		[_emptyStateView.centerYAnchor constraintEqualToAnchor:self.view.centerYAnchor constant:-40],
		[_emptyStateView.leadingAnchor constraintGreaterThanOrEqualToAnchor:self.view.leadingAnchor constant:40],
		[_emptyStateView.trailingAnchor constraintLessThanOrEqualToAnchor:self.view.trailingAnchor constant:-40],

		[icon.topAnchor constraintEqualToAnchor:_emptyStateView.topAnchor],
		[icon.centerXAnchor constraintEqualToAnchor:_emptyStateView.centerXAnchor],
		[icon.widthAnchor constraintEqualToConstant:64],
		[icon.heightAnchor constraintEqualToConstant:64],

		[_emptyStateLabel.topAnchor constraintEqualToAnchor:icon.bottomAnchor constant:20],
		[_emptyStateLabel.leadingAnchor constraintEqualToAnchor:_emptyStateView.leadingAnchor],
		[_emptyStateLabel.trailingAnchor constraintEqualToAnchor:_emptyStateView.trailingAnchor],

		[subtitle.topAnchor constraintEqualToAnchor:_emptyStateLabel.bottomAnchor constant:8],
		[subtitle.leadingAnchor constraintEqualToAnchor:_emptyStateView.leadingAnchor],
		[subtitle.trailingAnchor constraintEqualToAnchor:_emptyStateView.trailingAnchor],
		[subtitle.bottomAnchor constraintEqualToAnchor:_emptyStateView.bottomAnchor],
	]];
}

- (void)updateEmptyState {
	NSInteger files = self.fetchedResultsController.fetchedObjects.count;
	NSInteger folders = [self showsFolderSection] ? [self folderSectionItemCount] : 0;
	BOOL hasFilters = [self hasActiveFilters];
	BOOL empty = files == 0 && folders == 0;

	self.emptyStateView.hidden = !empty;
	self.collectionView.hidden = NO;
	self.emptyStateLabel.text = empty && hasFilters ? RYGLocalized(@"No matching files") : RYGLocalized(@"No files in Gallery");
}

#pragma mark - Fetched Results Controller

- (NSString *)groupMode {
	if (self.usernameScope.length) return kGroupModeOff;

	NSString *mode = [RYGUtils getStringPref:kGroupModeKey];
	// Picker can't navigate sub-folders — fall back to Sections so files stay visible.
	if (self.pickerMode && [mode isEqualToString:kGroupModeFolders]) return kGroupModeSections;
	if ([mode isEqualToString:kGroupModeSections]) return kGroupModeSections;
	if ([mode isEqualToString:kGroupModeFolders])  return kGroupModeFolders;
	return kGroupModeOff;
}

- (BOOL)isGroupingByUser {
	return [[self groupMode] isEqualToString:kGroupModeSections];
}

- (BOOL)hasActiveFilters {
	return self.filterTypes.count || self.filterSources.count || self.filterUsernames.count || self.filterFavoritesOnly || self.filterDateFrom != nil;
}

// Filters don't hide the buckets — folder fetches apply them, so only folders with matches show.
- (BOOL)isShowingUserFolders {
	if (![[self groupMode] isEqualToString:kGroupModeFolders]) return NO;
	if (self.currentFolderPath.length) return NO;
	if (self.searchQuery.length) return NO;
	return YES;
}

- (nullable NSPredicate *)activeFilterPredicate {
	return [RYGGalleryFilterViewController filterPredicateForTypes:self.filterTypes
														   sources:self.filterSources
														 usernames:self.filterUsernames
													 favoritesOnly:self.filterFavoritesOnly
														  dateFrom:self.filterDateFrom
															dateTo:self.filterDateTo];
}

// Inline folders into the file section so flow layout fills the row.
- (BOOL)mergesFolderIntoGridSection {
	if (self.viewMode != RYGGalleryViewModeGrid) return NO;
	if (![[self groupMode] isEqualToString:kGroupModeFolders]) return NO;
	return [self showsFolderSection];
}

- (NSInteger)folderSectionOffset {
	if ([self mergesFolderIntoGridSection]) return 0;
	return [self showsFolderSection] ? 1 : 0;
}

- (void)setupFetchedResultsController {
	NSFetchRequest *request = [self currentFetchRequest];
	NSManagedObjectContext *context = [RYGGalleryCoreDataStack shared].viewContext;
	NSString *sectionKey = [self isGroupingByUser] ? @"sourceUsername" : nil;

	_fetchedResultsController = [[NSFetchedResultsController alloc] initWithFetchRequest:request
																	managedObjectContext:context
																	  sectionNameKeyPath:sectionKey
																			   cacheName:nil];
	_fetchedResultsController.delegate = self;

	NSError *error = nil;

	if (![_fetchedResultsController performFetch:&error]) {
		NSLog(@"[RyukGram Gallery] Fetch failed: %@", error);
	}
}

- (NSFetchRequest *)currentFetchRequest {
	NSFetchRequest *request = [[NSFetchRequest alloc] initWithEntityName:@"RYGGalleryFile"];
	NSMutableArray<NSSortDescriptor *> *sorts = [[RYGGallerySortViewController fileSortDescriptors] mutableCopy];

	// FRC needs the section key to lead; recomputeSectionOrder reorders sections after.
	if ([self isGroupingByUser]) {
		[sorts insertObject:[NSSortDescriptor sortDescriptorWithKey:@"sourceUsername"
														  ascending:YES
														   selector:@selector(localizedCaseInsensitiveCompare:)]
					atIndex:0];
	}

	NSMutableArray<NSPredicate *> *predicates = [NSMutableArray array];

	NSPredicate *base = [RYGGalleryFilterViewController predicateForTypes:self.filterTypes
																  sources:self.filterSources
																usernames:self.filterUsernames
															favoritesOnly:self.filterFavoritesOnly
																 dateFrom:self.filterDateFrom
																   dateTo:self.filterDateTo
															   folderPath:self.currentFolderPath];

	if (base) {
		[predicates addObject:base];
	}

	if (self.usernameScope.length) {
		[predicates addObject:[NSPredicate predicateWithFormat:@"sourceUsername == %@", self.usernameScope]];
	}

	// Folders mode: exclude bucketed files from the flat list.
	if ([self isShowingUserFolders]) {
		[predicates addObject:[NSPredicate predicateWithFormat:@"sourceUsername == nil OR sourceUsername == %@", @""]];
	}

	if (self.pickerMode && self.pickerAllowedMediaTypes.count) {
		[predicates addObject:[NSPredicate predicateWithFormat:@"mediaType IN %@", self.pickerAllowedMediaTypes]];
	}

	NSString *query = [self.searchQuery stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];

	if (query.length) {
		[predicates addObject:[NSPredicate predicateWithFormat:@"sourceUsername CONTAINS[cd] %@ OR customName CONTAINS[cd] %@ OR relativePath CONTAINS[cd] %@", query, query, query]];
	}

	request.sortDescriptors = sorts;
	request.predicate = predicates.count ? [NSCompoundPredicate andPredicateWithSubpredicates:predicates] : nil;
	request.fetchBatchSize = 60;

	return request;
}

- (void)refetch {
	if (self.selectionMode) {
		[self.selectedFileIDs removeAllObjects];
	}

	NSFetchRequest *request = [self currentFetchRequest];

	self.fetchedResultsController.fetchRequest.sortDescriptors = request.sortDescriptors;
	self.fetchedResultsController.fetchRequest.predicate = request.predicate;

	NSError *error = nil;

	if (![self.fetchedResultsController performFetch:&error]) {
		NSLog(@"[RyukGram Gallery] Refetch failed: %@", error);
	}

	[self reloadSubfolders];
	[self.collectionView reloadData];
	[self updateEmptyState];
	[self refreshNavigationItems];
}

#pragma mark - Subfolders

- (void)reloadUserFolders {
	if (![self isShowingUserFolders]) {
		self.userFolders = @[];
		self.userFolderCounts = @{};
		self.userFolderThumbnailPaths = @{};
		self.userFolderLastDates = @{};
		return;
	}

	NSManagedObjectContext *context = [RYGGalleryCoreDataStack shared].viewContext;
	NSFetchRequest *request = [[NSFetchRequest alloc] initWithEntityName:@"RYGGalleryFile"];

	NSMutableArray<NSPredicate *> *parts = [NSMutableArray arrayWithObject:
		[NSPredicate predicateWithFormat:@"sourceUsername != nil AND sourceUsername != %@", @""]];
	NSPredicate *filters = [self activeFilterPredicate];
	if (filters) [parts addObject:filters];

	request.resultType = NSDictionaryResultType;
	request.propertiesToFetch = @[@"sourceUsername", @"identifier", @"dateAdded", @"fileSize"];
	request.predicate = [NSCompoundPredicate andPredicateWithSubpredicates:parts];
	request.sortDescriptors = @[[NSSortDescriptor sortDescriptorWithKey:@"dateAdded" ascending:NO]];

	NSArray<NSDictionary *> *rows = [context executeFetchRequest:request error:nil];
	NSMutableDictionary<NSString *, NSNumber *> *counts = [NSMutableDictionary dictionary];
	NSMutableDictionary<NSString *, NSNumber *> *sizes = [NSMutableDictionary dictionary];
	NSMutableDictionary<NSString *, NSMutableArray<NSString *> *> *thumbs = [NSMutableDictionary dictionary];
	NSMutableDictionary<NSString *, NSDate *> *dates = [NSMutableDictionary dictionary];
	NSString *thumbDir = [RYGGalleryPaths galleryThumbnailsDirectory];
	NSFileManager *fm = [NSFileManager defaultManager];

	for (NSDictionary *row in rows) {
		NSString *name = row[@"sourceUsername"];
		if (!name.length) continue;

		counts[name] = @([counts[name] integerValue] + 1);
		sizes[name] = @([sizes[name] longLongValue] + [row[@"fileSize"] longLongValue]);

		NSDate *date = row[@"dateAdded"];
		if (date && !dates[name]) dates[name] = date;

		NSMutableArray *list = thumbs[name];
		if (!list) {
			list = [NSMutableArray array];
			thumbs[name] = list;
		}

		if (list.count < 4) {
			NSString *identifier = row[@"identifier"];
			if (identifier.length) {
				NSString *path = [thumbDir stringByAppendingPathComponent:[NSString stringWithFormat:@"%@.jpg", identifier]];
				if ([fm fileExistsAtPath:path]) [list addObject:path];
			}
		}
	}

	self.userFolders = [self orderFolderKeys:[counts allKeys] usingDates:dates sizes:sizes displayName:^NSString *(NSString *key) { return key; }];
	self.userFolderCounts = [counts copy];
	self.userFolderSizes = [sizes copy];
	self.userFolderThumbnailPaths = [thumbs copy];
	self.userFolderLastDates = [dates copy];
}

- (void)reloadSubfolderThumbnails {
	if (!self.subfolders.count) {
		self.subfolderThumbnailPaths = @{};
		self.subfolderLastDates = @{};
		return;
	}

	NSManagedObjectContext *context = [RYGGalleryCoreDataStack shared].viewContext;
	NSFetchRequest *request = [[NSFetchRequest alloc] initWithEntityName:@"RYGGalleryFile"];

	NSMutableArray<NSPredicate *> *parts = [NSMutableArray arrayWithObject:
		[NSPredicate predicateWithFormat:@"folderPath != nil AND folderPath != %@", @""]];
	NSPredicate *filters = [self activeFilterPredicate];
	if (filters) [parts addObject:filters];

	request.resultType = NSDictionaryResultType;
	request.propertiesToFetch = @[@"folderPath", @"identifier", @"dateAdded"];
	request.predicate = [NSCompoundPredicate andPredicateWithSubpredicates:parts];
	request.sortDescriptors = @[[NSSortDescriptor sortDescriptorWithKey:@"dateAdded" ascending:NO]];

	NSArray<NSDictionary *> *rows = [context executeFetchRequest:request error:nil];
	NSMutableDictionary<NSString *, NSMutableArray<NSString *> *> *thumbs = [NSMutableDictionary dictionary];
	NSMutableDictionary<NSString *, NSDate *> *dates = [NSMutableDictionary dictionary];
	NSString *thumbDir = [RYGGalleryPaths galleryThumbnailsDirectory];
	NSFileManager *fm = [NSFileManager defaultManager];
	NSSet<NSString *> *visibleFolders = [NSSet setWithArray:self.subfolders];

	for (NSDictionary *row in rows) {
		NSString *folder = row[@"folderPath"];
		if (!folder.length) continue;

		NSString *child = RYGGalleryImmediateChildPath(folder, self.currentFolderPath);
		if (!child.length || ![visibleFolders containsObject:child]) continue;

		NSDate *date = row[@"dateAdded"];
		if (date && !dates[child]) dates[child] = date;

		NSMutableArray *list = thumbs[child];
		if (!list) {
			list = [NSMutableArray array];
			thumbs[child] = list;
		}

		if (list.count >= 4) continue;

		NSString *identifier = row[@"identifier"];
		if (!identifier.length) continue;

		NSString *path = [thumbDir stringByAppendingPathComponent:[NSString stringWithFormat:@"%@.jpg", identifier]];
		if ([fm fileExistsAtPath:path]) [list addObject:path];
	}

	self.subfolderThumbnailPaths = [thumbs copy];
	self.subfolderLastDates = [dates copy];
}

- (void)reloadSubfolders {
	[self reloadUserFolders];

	if (self.searchQuery.length) {
		self.subfolders = @[];
		self.subfolderCounts = @{};
		return;
	}

	NSManagedObjectContext *context = [RYGGalleryCoreDataStack shared].viewContext;
	NSFetchRequest *request = [[NSFetchRequest alloc] initWithEntityName:@"RYGGalleryFile"];

	NSMutableArray<NSPredicate *> *parts = [NSMutableArray arrayWithObject:
		[NSPredicate predicateWithFormat:@"folderPath != nil AND folderPath != ''"]];
	NSPredicate *filters = [self activeFilterPredicate];
	if (filters) [parts addObject:filters];

	request.resultType = NSDictionaryResultType;
	request.propertiesToFetch = @[@"folderPath", @"dateAdded", @"fileSize"];
	request.predicate = [NSCompoundPredicate andPredicateWithSubpredicates:parts];

	NSArray<NSDictionary *> *rows = [context executeFetchRequest:request error:nil];
	NSMutableDictionary<NSString *, NSNumber *> *counts = [NSMutableDictionary dictionary];
	NSMutableDictionary<NSString *, NSNumber *> *sizes = [NSMutableDictionary dictionary];
	NSMutableDictionary<NSString *, NSDate *> *dates = [NSMutableDictionary dictionary];
	NSMutableSet<NSString *> *folders = [NSMutableSet set];

	for (NSDictionary *row in rows) {
		NSString *child = RYGGalleryImmediateChildPath(row[@"folderPath"], self.currentFolderPath);
		if (!child.length) continue;

		[folders addObject:child];
		counts[child] = @([counts[child] integerValue] + 1);
		sizes[child] = @([sizes[child] longLongValue] + [row[@"fileSize"] longLongValue]);

		NSDate *date = row[@"dateAdded"];
		if (date && (!dates[child] || [date compare:dates[child]] == NSOrderedDescending)) dates[child] = date;
	}

	self.subfolderCounts = [counts copy];
	self.subfolderSizes = [sizes copy];
	self.subfolderLastDates = [dates copy];
	self.subfolders = [self orderFolderKeys:[folders allObjects] usingDates:dates sizes:sizes displayName:^NSString *(NSString *key) { return key.lastPathComponent; }];

	// Empty placeholder folders can't contain filter matches.
	if (![self hasActiveFilters]) {
		[self mergePlaceholderSubfolders];
		self.subfolders = [self orderFolderKeys:self.subfolders usingDates:dates sizes:sizes displayName:^NSString *(NSString *key) { return key.lastPathComponent; }];
	}

	[self reloadSubfolderThumbnails];
	[self recomputeSectionOrder];
}

#pragma mark - Group ordering

// Orders folder/user buckets by the active sort axis, matching the flat list.
- (NSArray<NSString *> *)orderFolderKeys:(NSArray<NSString *> *)keys
							  usingDates:(NSDictionary<NSString *, NSDate *> *)dates
								   sizes:(NSDictionary<NSString *, NSNumber *> *)sizes
							 displayName:(NSString *(^)(NSString *))displayName {
	RYGGallerySortOrder order = RYGGallerySortViewController.currentOrder;
	BOOL asc = RYGGallerySortViewController.currentAscending;

	return [keys sortedArrayUsingComparator:^NSComparisonResult(NSString *a, NSString *b) {
		NSComparisonResult r;

		if (order == RYGGallerySortOrderSize) {
			long long sa = [sizes[a] longLongValue], sb = [sizes[b] longLongValue];
			r = (sa < sb) ? NSOrderedAscending : (sa > sb ? NSOrderedDescending : NSOrderedSame);
		} else if (order == RYGGallerySortOrderDate) {
			NSDate *da = dates[a] ?: NSDate.distantPast, *db = dates[b] ?: NSDate.distantPast;
			r = [da compare:db];
		} else {
			r = [displayName(a) localizedStandardCompare:displayName(b)];
		}

		if (r == NSOrderedSame) r = [displayName(a) localizedStandardCompare:displayName(b)];
		return asc ? r : (NSComparisonResult)(0 - r);
	}];
}

- (NSInteger)realSectionForOrderedIndex:(NSInteger)orderedIndex {
	NSArray<NSNumber *> *order = self.orderedSectionIndices;
	if (orderedIndex < 0 || !order || orderedIndex >= (NSInteger)order.count) return orderedIndex;
	return order[orderedIndex].integerValue;
}

// Reorders user sections by the active sort axis instead of FRC's alphabetical key.
- (void)recomputeSectionOrder {
	if (![self isGroupingByUser]) {
		self.orderedSectionIndices = nil;
		return;
	}

	NSArray<id<NSFetchedResultsSectionInfo>> *sections = self.fetchedResultsController.sections;
	NSInteger count = (NSInteger)sections.count;
	if (count <= 1) {
		self.orderedSectionIndices = nil;
		return;
	}

	RYGGallerySortOrder order = RYGGallerySortViewController.currentOrder;
	BOOL asc = RYGGallerySortViewController.currentAscending;

	NSMutableArray<NSNumber *> *indices = [NSMutableArray arrayWithCapacity:count];
	for (NSInteger i = 0; i < count; i++) [indices addObject:@(i)];

	NSDictionary<NSString *, NSDictionary *> *agg = (order == RYGGallerySortOrderName) ? nil : [self sectionAggregates];

	[indices sortUsingComparator:^NSComparisonResult(NSNumber *a, NSNumber *b) {
		NSString *na = sections[a.integerValue].name ?: @"";
		NSString *nb = sections[b.integerValue].name ?: @"";
		NSComparisonResult r;

		if (order == RYGGallerySortOrderSize) {
			long long sa = [agg[na][@"size"] longLongValue];
			long long sb = [agg[nb][@"size"] longLongValue];
			r = (sa < sb) ? NSOrderedAscending : (sa > sb ? NSOrderedDescending : NSOrderedSame);
		} else if (order == RYGGallerySortOrderDate) {
			NSDate *da = agg[na][@"date"] ?: NSDate.distantPast;
			NSDate *db = agg[nb][@"date"] ?: NSDate.distantPast;
			r = [da compare:db];
		} else {
			r = [na localizedCaseInsensitiveCompare:nb];
		}

		if (r == NSOrderedSame) r = [na localizedCaseInsensitiveCompare:nb];
		return asc ? r : (NSComparisonResult)(0 - r);
	}];

	self.orderedSectionIndices = [indices copy];
}

- (NSDictionary<NSString *, NSDictionary *> *)sectionAggregates {
	NSManagedObjectContext *context = [RYGGalleryCoreDataStack shared].viewContext;
	NSFetchRequest *request = [[NSFetchRequest alloc] initWithEntityName:@"RYGGalleryFile"];
	request.resultType = NSDictionaryResultType;
	request.propertiesToFetch = @[@"sourceUsername", @"dateAdded", @"fileSize"];
	request.predicate = self.fetchedResultsController.fetchRequest.predicate;

	NSArray<NSDictionary *> *rows = [context executeFetchRequest:request error:nil] ?: @[];
	NSMutableDictionary<NSString *, NSMutableDictionary *> *agg = [NSMutableDictionary dictionary];

	for (NSDictionary *row in rows) {
		NSString *name = row[@"sourceUsername"];
		if (![name isKindOfClass:NSString.class]) name = @"";

		NSMutableDictionary *entry = agg[name];
		if (!entry) {
			entry = [NSMutableDictionary dictionary];
			agg[name] = entry;
		}

		entry[@"size"] = @([entry[@"size"] longLongValue] + [row[@"fileSize"] longLongValue]);

		NSDate *date = row[@"dateAdded"];
		NSDate *current = entry[@"date"];
		if (date && (!current || [date compare:current] == NSOrderedDescending)) entry[@"date"] = date;
	}

	return agg;
}

#pragma mark - NSFetchedResultsControllerDelegate

- (void)controllerDidChangeContent:(NSFetchedResultsController *)controller {
	(void)controller;

	[self reloadSubfolders];
	[self.collectionView reloadData];
	[self updateEmptyState];
	[self refreshNavigationItems];
}

#pragma mark - UICollectionViewDataSource

- (BOOL)showsFolderSection {
	if (self.searchQuery.length) return NO;
	return self.subfolders.count > 0 || self.userFolders.count > 0;
}

- (BOOL)isFolderIndexPath:(NSIndexPath *)indexPath {
	if (![self showsFolderSection]) return NO;
	if (indexPath.section != 0) return NO;
	if ([self mergesFolderIntoGridSection]) {
		return indexPath.item < [self folderSectionItemCount];
	}
	return YES;
}

- (NSInteger)folderSectionItemCount {
	return (NSInteger)(self.subfolders.count + self.userFolders.count);
}

- (BOOL)folderIndexPathIsUserFolder:(NSIndexPath *)indexPath {
	if (![self isFolderIndexPath:indexPath]) return NO;
	return indexPath.item >= (NSInteger)self.subfolders.count;
}

- (NSString *)userFolderNameAtFolderIndex:(NSInteger)item {
	NSInteger offset = item - (NSInteger)self.subfolders.count;
	if (offset < 0 || offset >= (NSInteger)self.userFolders.count) return nil;
	return self.userFolders[offset];
}

- (NSInteger)numberOfSectionsInCollectionView:(UICollectionView *)collectionView {
	NSInteger folder = [self mergesFolderIntoGridSection] ? 0 : [self folderSectionOffset];
	NSInteger frcCount = (NSInteger)self.fetchedResultsController.sections.count;

	if (![self isGroupingByUser]) {
		return folder + 1;
	}

	return folder + MAX(frcCount, 1);
}

- (NSInteger)collectionView:(UICollectionView *)collectionView numberOfItemsInSection:(NSInteger)section {
	NSArray *sections = self.fetchedResultsController.sections;

	if ([self mergesFolderIntoGridSection] && section == 0) {
		NSInteger folderCount = [self folderSectionItemCount];
		NSInteger fileCount = sections.count
			? (NSInteger)((id<NSFetchedResultsSectionInfo>)sections[0]).numberOfObjects
			: 0;
		return folderCount + fileCount;
	}

	if ([self showsFolderSection] && section == 0) {
		return [self folderSectionItemCount];
	}

	NSInteger frcIdx = [self realSectionForOrderedIndex:(section - [self folderSectionOffset])];

	if (frcIdx < 0 || frcIdx >= (NSInteger)sections.count) return 0;

	return ((id<NSFetchedResultsSectionInfo>)sections[frcIdx]).numberOfObjects;
}

- (__kindof UICollectionViewCell *)collectionView:(UICollectionView *)collectionView cellForItemAtIndexPath:(NSIndexPath *)indexPath {
	if ([self isFolderIndexPath:indexPath]) {
		RYGGalleryFolderCell *cell = [collectionView dequeueReusableCellWithReuseIdentifier:kFolderCellID forIndexPath:indexPath];
		RYGGalleryFolderCellLayout layout = (self.viewMode == RYGGalleryViewModeGrid)
			? RYGGalleryFolderCellLayoutGrid
			: RYGGalleryFolderCellLayoutList;

		if ([self folderIndexPathIsUserFolder:indexPath]) {
			NSString *username = [self userFolderNameAtFolderIndex:indexPath.item];
			NSInteger count = [self.userFolderCounts[username] integerValue];
			NSString *subtitle = RYGGalleryFolderSubtitle(count, [self.userFolderSizes[username ?: @""] longLongValue], self.userFolderLastDates[username ?: @""]);
			[cell configureWithFolderName:[@"@" stringByAppendingString:(username ?: @"")]
								 subtitle:subtitle
						   thumbnailPaths:self.userFolderThumbnailPaths[username ?: @""]
							   layoutMode:layout
							 isUserFolder:YES];
		} else {
			NSString *path = self.subfolders[indexPath.item];
			NSInteger count = [self.subfolderCounts[path] integerValue];
			NSString *subtitle = RYGGalleryFolderSubtitle(count, [self.subfolderSizes[path] longLongValue], self.subfolderLastDates[path]);
			[cell configureWithFolderName:[path lastPathComponent]
								 subtitle:subtitle
						   thumbnailPaths:self.subfolderThumbnailPaths[path]
							   layoutMode:layout
							 isUserFolder:NO];
		}

		return cell;
	}

	RYGGalleryFile *file = [self galleryFileForCollectionIndexPath:indexPath];

	if (self.viewMode == RYGGalleryViewModeGrid) {
		RYGGalleryGridCell *cell = [collectionView dequeueReusableCellWithReuseIdentifier:kGridCellID forIndexPath:indexPath];

		[cell configureWithGalleryFile:file
						 selectionMode:self.selectionMode
							  selected:[self.selectedFileIDs containsObject:file.identifier]];

		return cell;
	}

	RYGGalleryListCollectionCell *cell = [collectionView dequeueReusableCellWithReuseIdentifier:kListCellID forIndexPath:indexPath];

	[cell configureWithGalleryFile:file
					 selectionMode:self.selectionMode
						  selected:[self.selectedFileIDs containsObject:file.identifier]];
	[cell setMoreActionsMenu:self.selectionMode ? nil : [self fileActionsMenuForFile:file]];

	return cell;
}

- (UICollectionReusableView *)collectionView:(UICollectionView *)collectionView
		   viewForSupplementaryElementOfKind:(NSString *)kind
								 atIndexPath:(NSIndexPath *)indexPath {
	if (![kind isEqualToString:UICollectionElementKindSectionHeader]) {
		return [UICollectionReusableView new];
	}

	RYGGalleryUserHeaderView *header = [collectionView dequeueReusableSupplementaryViewOfKind:kind
																		 withReuseIdentifier:kUserHeaderID
																				forIndexPath:indexPath];

	NSInteger frcSection = [self realSectionForOrderedIndex:(indexPath.section - [self folderSectionOffset])];
	NSArray *sections = self.fetchedResultsController.sections;
	NSString *name = (frcSection >= 0 && frcSection < (NSInteger)sections.count)
		? ((id<NSFetchedResultsSectionInfo>)sections[frcSection]).name
		: nil;

	header.titleLabel.text = name.length ? name : RYGLocalized(@"Unknown");

	[self attachSectionSelectGestureToHeader:header displaySection:indexPath.section];

	return header;
}

- (void)attachSectionSelectGestureToHeader:(RYGGalleryUserHeaderView *)header displaySection:(NSInteger)displaySection {
	header.tag = displaySection;

	for (UIGestureRecognizer *gesture in header.gestureRecognizers) {
		if ([gesture isKindOfClass:UILongPressGestureRecognizer.class]) return;
	}

	if (self.pickerMode) return;

	UILongPressGestureRecognizer *longPress = [[UILongPressGestureRecognizer alloc] initWithTarget:self action:@selector(handleSectionHeaderLongPress:)];
	[header addGestureRecognizer:longPress];
}

- (void)handleSectionHeaderLongPress:(UILongPressGestureRecognizer *)gesture {
	if (gesture.state != UIGestureRecognizerStateBegan || self.pickerMode) return;

	[[[UIImpactFeedbackGenerator alloc] initWithStyle:UIImpactFeedbackStyleMedium] impactOccurred];
	[self selectAllFilesInDisplaySection:gesture.view.tag];
}

#pragma mark - UICollectionViewDelegateFlowLayout

- (NSInteger)gridColumns {
	NSInteger cols = (NSInteger)[RYGUtils getDoublePref:kGridColumnsKey];
	return (cols >= 2 && cols <= 5) ? cols : 3;
}

- (CGSize)collectionView:(UICollectionView *)collectionView layout:(UICollectionViewLayout *)layout sizeForItemAtIndexPath:(NSIndexPath *)indexPath {
	CGFloat width = collectionView.bounds.size.width;

	if (self.viewMode == RYGGalleryViewModeGrid) {
		NSInteger cols = [self gridColumns];
		CGFloat side = floor((width - (kGridSpacing * (cols - 1))) / cols);
		return CGSizeMake(side, side);
	}

	return CGSizeMake(width, 88);
}

- (UIEdgeInsets)collectionView:(UICollectionView *)collectionView layout:(UICollectionViewLayout *)layout insetForSectionAtIndex:(NSInteger)section {
	if (!([self showsFolderSection] && section == 0)) return UIEdgeInsetsZero;

	return (self.viewMode == RYGGalleryViewModeGrid)
		? UIEdgeInsetsZero
		: UIEdgeInsetsMake(10, 0, 6, 0);
}

- (CGFloat)collectionView:(UICollectionView *)collectionView layout:(UICollectionViewLayout *)layout minimumInteritemSpacingForSectionAtIndex:(NSInteger)section {
	BOOL folderSec = [self showsFolderSection] && section == 0;
	if (folderSec && self.viewMode != RYGGalleryViewModeGrid) return 0;
	return self.viewMode == RYGGalleryViewModeGrid ? kGridSpacing : 0;
}

- (CGFloat)collectionView:(UICollectionView *)collectionView layout:(UICollectionViewLayout *)layout minimumLineSpacingForSectionAtIndex:(NSInteger)section {
	BOOL folderSec = [self showsFolderSection] && section == 0;
	if (folderSec && self.viewMode != RYGGalleryViewModeGrid) return 0;
	return self.viewMode == RYGGalleryViewModeGrid ? kGridSpacing : 0;
}

- (CGSize)collectionView:(UICollectionView *)collectionView
				  layout:(UICollectionViewLayout *)layout
referenceSizeForHeaderInSection:(NSInteger)section {
	if (![self isGroupingByUser]) return CGSizeZero;
	if ([self showsFolderSection] && section == 0) return CGSizeZero;

	return CGSizeMake(collectionView.bounds.size.width, kUserHeaderHeight);
}

#pragma mark - UICollectionViewDelegate

- (void)collectionView:(UICollectionView *)collectionView didSelectItemAtIndexPath:(NSIndexPath *)indexPath {
	[collectionView deselectItemAtIndexPath:indexPath animated:YES];

	if ([self isFolderIndexPath:indexPath]) {
		if (self.selectionMode) return;

		RYGGalleryViewController *child;

		if ([self folderIndexPathIsUserFolder:indexPath]) {
			NSString *username = [self userFolderNameAtFolderIndex:indexPath.item];
			if (!username.length) return;
			child = [[RYGGalleryViewController alloc] initWithUsernameScope:username];
		} else {
			child = [[RYGGalleryViewController alloc] initWithFolderPath:self.subfolders[indexPath.item]];
			child.filterUsernames = [self.filterUsernames mutableCopy];
		}

		// Carry filters so folder contents match the badge count (username scope pins its own user).
		child.filterTypes = [self.filterTypes mutableCopy];
		child.filterSources = [self.filterSources mutableCopy];
		child.filterFavoritesOnly = self.filterFavoritesOnly;
		child.filterDateFrom = self.filterDateFrom;
		child.filterDateTo = self.filterDateTo;

		child.pickerMode = self.pickerMode;
		child.pickerAllowedMediaTypes = self.pickerAllowedMediaTypes;
		child.pickerCompletion = self.pickerCompletion;
		child.pickerTitleOverride = self.pickerTitleOverride;

		[self.navigationController pushViewController:child animated:YES];

		return;
	}

	RYGGalleryFile *file = [self galleryFileForCollectionIndexPath:indexPath];
	if (!file) return;

	if (self.pickerMode) {
		[self finishPickerWithURL:[file fileURL] file:file];
		return;
	}

	if (self.selectionMode) {
		[self toggleSelectionForFile:file];
		return;
	}

	NSArray<RYGGalleryFile *> *files = self.fetchedResultsController.fetchedObjects ?: @[];
	NSUInteger startIndex = [files indexOfObject:file];

	if (startIndex == NSNotFound) {
		startIndex = 0;
	}

	NSMutableArray<RYGMediaViewerItem *> *items = [NSMutableArray arrayWithCapacity:files.count];

	for (RYGGalleryFile *item in files) {
		NSURL *url = [item fileURL];
		RYGMediaViewerItem *viewerItem = nil;

		switch (item.mediaType) {
			case RYGGalleryMediaTypeVideo:
				viewerItem = [RYGMediaViewerItem itemWithVideoURL:url photoURL:nil caption:nil];
				break;
			case RYGGalleryMediaTypeAudio:
				viewerItem = [RYGMediaViewerItem itemWithAudioURL:url caption:nil];
				break;
			case RYGGalleryMediaTypeGIF:
				viewerItem = [RYGMediaViewerItem itemWithAnimatedImageURL:url caption:nil];
				break;
			case RYGGalleryMediaTypeImage:
			default:
				viewerItem = [RYGMediaViewerItem itemWithVideoURL:nil photoURL:url caption:nil];
				break;
		}

		if (viewerItem) {
			[items addObject:viewerItem];
		}
	}

	if (items.count) {
		[RYGMediaViewer showItems:items startIndex:MIN(startIndex, items.count - 1) shareSheetOnly:YES];
	}
}

- (NSArray<RYGGalleryFile *> *)visibleGalleryFiles {
	return self.fetchedResultsController.fetchedObjects ?: @[];
}

- (RYGGalleryFile *)galleryFileForCollectionIndexPath:(NSIndexPath *)indexPath {
	if ([self isFolderIndexPath:indexPath]) return nil;

	NSArray *sections = self.fetchedResultsController.sections;
	NSInteger frcSection = [self realSectionForOrderedIndex:(indexPath.section - [self folderSectionOffset])];
	NSInteger frcItem = indexPath.item;

	if ([self mergesFolderIntoGridSection] && indexPath.section == 0) {
		frcSection = 0;
		frcItem = indexPath.item - [self folderSectionItemCount];
	}

	if (frcSection < 0 || frcSection >= (NSInteger)sections.count) return nil;

	id<NSFetchedResultsSectionInfo> info = sections[frcSection];

	if (frcItem < 0 || frcItem >= (NSInteger)info.numberOfObjects) return nil;

	return [self.fetchedResultsController objectAtIndexPath:[NSIndexPath indexPathForItem:frcItem inSection:frcSection]];
}

- (UIContextMenuConfiguration *)collectionView:(UICollectionView *)collectionView contextMenuConfigurationForItemAtIndexPath:(NSIndexPath *)indexPath point:(CGPoint)point {
	(void)collectionView;
	(void)point;

	if (self.selectionMode) return nil;

	if ([self isFolderIndexPath:indexPath]) {
		if ([self folderIndexPathIsUserFolder:indexPath]) {
			NSString *username = [self userFolderNameAtFolderIndex:indexPath.item];
			return username.length ? [self contextMenuForUserFolder:username] : nil;
		}
		return [self contextMenuForFolder:self.subfolders[indexPath.item]];
	}

	RYGGalleryFile *file = [self galleryFileForCollectionIndexPath:indexPath];

	return file ? [self contextMenuForFile:file] : nil;
}

#pragma mark - Sort / Filter

- (void)presentGallerySheet:(RYGGallerySheetViewController *)contentVC {
	[self presentViewController:contentVC animated:NO completion:nil];
}

- (void)presentSort {
	RYGGallerySortViewController *vc = [RYGGallerySortViewController new];

	vc.delegate = self;

	[self presentGallerySheet:vc];
}

- (void)presentFilter {
	RYGGalleryFilterViewController *vc = [RYGGalleryFilterViewController new];

	vc.delegate = self;
	vc.filterTypes = self.filterTypes;
	vc.filterSources = self.filterSources;
	vc.filterUsernames = self.filterUsernames;
	vc.filterFavoritesOnly = self.filterFavoritesOnly;
	vc.filterDateFrom = self.filterDateFrom;
	vc.filterDateTo = self.filterDateTo;

	[self presentGallerySheet:vc];
}

- (void)sortControllerDidChange:(RYGGallerySortViewController *)controller {
	(void)controller;
	[self refetch];
}

- (void)filterController:(RYGGalleryFilterViewController *)controller
		   didApplyTypes:(NSSet<NSNumber *> *)types
				 sources:(NSSet<NSNumber *> *)sources
			   usernames:(NSSet<NSString *> *)usernames
		   favoritesOnly:(BOOL)favoritesOnly
				dateFrom:(NSDate *)dateFrom
				  dateTo:(NSDate *)dateTo {
	(void)controller;

	self.filterTypes = [types mutableCopy];
	self.filterSources = [sources mutableCopy];
	self.filterUsernames = [usernames mutableCopy];
	self.filterFavoritesOnly = favoritesOnly;
	self.filterDateFrom = dateFrom;
	self.filterDateTo = dateTo;

	[self refetch];
}

- (void)filterControllerDidClear:(RYGGalleryFilterViewController *)controller {
	(void)controller;

	[self.filterTypes removeAllObjects];
	[self.filterSources removeAllObjects];
	[self.filterUsernames removeAllObjects];

	self.filterFavoritesOnly = NO;
	self.filterDateFrom = nil;
	self.filterDateTo = nil;

	[self refetch];
}

- (void)handleGalleryPreferencesChanged:(NSNotification *)note {
	(void)note;

	// sectionNameKeyPath is immutable on FRC — rebuild when group mode flips.
	[self setupFetchedResultsController];

	if (self.viewMode == RYGGalleryViewModeList) {
		[self.collectionView setCollectionViewLayout:[self layoutForViewMode:self.viewMode] animated:NO];
	} else {
		[self.collectionView.collectionViewLayout invalidateLayout];
	}

	[self reloadSubfolders];
	[self.collectionView reloadData];
	[self updateEmptyState];
	[self refreshNavigationItems];
}

- (void)handleGalleryContextSaved:(NSNotification *)note {
	(void)note;

	dispatch_async(dispatch_get_main_queue(), ^{
		[self reloadSubfolders];
		[self.collectionView reloadData];
		[self updateEmptyState];
	});
}

#pragma mark - Legacy migration

- (void)offerLegacyMigrationIfNeeded {
	if (self.pickerMode || self.didOfferLegacyMigration) return;

	RYGGalleryCoreDataStack *stack = [RYGGalleryCoreDataStack shared];
	if (!stack.pendingLegacyMigration) return;
	self.didOfferLegacyMigration = YES;

	NSUInteger count = [stack legacyMigrationItemCount];
	NSString *msg = count > 0
		? [NSString stringWithFormat:RYGLocalized(@"Found %lu items saved by a previous version. Restore them into your gallery now?"), (unsigned long)count]
		: RYGLocalized(@"Gallery data from a previous version was found. Restore it now?");

	UIAlertController *alert = [UIAlertController alertControllerWithTitle:RYGLocalized(@"Restore Gallery")
																  message:msg
														   preferredStyle:UIAlertControllerStyleAlert];
	[alert addAction:[UIAlertAction actionWithTitle:RYGLocalized(@"Restore") style:UIAlertActionStyleDefault handler:^(__unused UIAlertAction *a) {
		[self runLegacyMigration];
	}]];
	[alert addAction:[UIAlertAction actionWithTitle:RYGLocalized(@"Not Now") style:UIAlertActionStyleCancel handler:^(__unused UIAlertAction *a) {
		self.didOfferLegacyMigration = NO; // ask again next time the gallery opens
	}]];
	[self presentViewController:alert animated:YES completion:nil];
}

- (void)runLegacyMigration {
	RYGNotificationHandle *handle = RYGNotifyProgress(RYG_NOTIF_GALLERY_SAVE, RYGLocalized(@"Restoring gallery…"), nil);
	dispatch_async(dispatch_get_global_queue(QOS_CLASS_USER_INITIATED, 0), ^{
		BOOL ok = [[RYGGalleryCoreDataStack shared] performLegacyMigrationLogged];
		dispatch_async(dispatch_get_main_queue(), ^{
			[self refetch];
			[self reloadSubfolders];
			[self.collectionView reloadData];
			[self updateEmptyState];
			if (ok) [handle success:RYGLocalized(@"Gallery restored")];
			else [handle error:RYGLocalized(@"Restore failed")];
		});
	});
}

#pragma mark - Settings

- (void)pushSettings {
	[self.navigationController pushViewController:[RYGGallerySettingsViewController new] animated:YES];
}

- (void)presentGalleryImport {
	[RYGGalleryImporter presentImportFrom:self folderPath:self.currentFolderPath completion:nil];
}

@end