#import "SCIGalleryViewController.h"
#import "SCIGalleryFile.h"
#import "SCIGalleryGridCell.h"
#import "SCIGalleryListCollectionCell.h"
#import "SCIGalleryFolderCell.h"
#import "SCIGalleryCoreDataStack.h"
#import "SCIGallerySheetViewController.h"
#import "SCIGallerySortViewController.h"
#import "SCIGalleryFilterViewController.h"
#import "SCIGallerySettingsViewController.h"
#import "SCIGalleryDeleteViewController.h"
#import "SCIGalleryOriginController.h"
#import "SCIMediaChrome.h"
#import "../UI/SCIScrollToTopButton.h"
#import "../Lock/SCILockGate.h"
#import "../Lock/SCILockGroups.h"
#import "../InstagramHeaders.h"
#import "../ActionButton/SCIMediaViewer.h"
#import "../ActionButton/SCIMediaActions.h"
#import "SCIAssetUtils.h"
#import "SCIGalleryPaths.h"
#import "../Utils.h"
#import "SCIGalleryShim.h"
#import "../UI/SCIPopupChrome.h"
#import <CoreData/CoreData.h>

static NSString * const kGridCellID = @"SCIGalleryGridCell";
static NSString * const kListCellID = @"SCIGalleryListCell";
static NSString * const kFolderCellID = @"SCIGalleryFolderCell";
static NSString * const kUserHeaderID = @"SCIGalleryUserHeader";

static NSString * const kSortModeKey = @"gallery_sort_mode";
static NSString * const kViewModeKey = @"gallery_view_mode";
static NSString * const kFavoritesAtTopKey = @"show_favorites_at_top";
static NSString * const kGroupModeKey = @"gallery_group_mode";
static NSString * const kGroupModeOff = @"off";
static NSString * const kGroupModeSections = @"sections";
static NSString * const kGroupModeFolders = @"folders";

static CGFloat const kUserHeaderHeight = 36.0;

@interface SCIGalleryUserHeaderView : UICollectionReusableView
@property (nonatomic, strong) UILabel *titleLabel;
@end

@implementation SCIGalleryUserHeaderView
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
static NSInteger const kGridColumns = 3;
static CGFloat const kGalleryBottomBarInsetHeight = 64.0;

static NSString *SCIGalleryFolderDateLabel(NSDate *date) {
	if (!date) return nil;

	NSCalendar *cal = [NSCalendar currentCalendar];
	if ([cal isDateInToday:date])	  return SCILocalized(@"Today");
	if ([cal isDateInYesterday:date]) return SCILocalized(@"Yesterday");

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

static NSString *SCIGalleryFolderSubtitle(NSInteger itemCount, NSDate *lastDate) {
	NSString *countText = [NSString stringWithFormat:@"%ld %@",
		(long)itemCount,
		itemCount == 1 ? SCILocalized(@"item") : SCILocalized(@"items")];

	NSString *dateText = SCIGalleryFolderDateLabel(lastDate);
	if (!dateText.length) return countText;

	return [NSString stringWithFormat:@"%@ · %@", countText, dateText];
}

static NSString *SCIGalleryCleanFolderPath(NSString *path) {
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

static NSString *SCIGalleryStoredFolderPath(NSString *cleanPath) {
	if (!cleanPath.length) return @"";
	return [@"/" stringByAppendingString:cleanPath];
}

static NSString *SCIGalleryImmediateChildPath(NSString *folderPath, NSString *basePath) {
	NSString *folder = SCIGalleryCleanFolderPath(folderPath);
	NSString *base = SCIGalleryCleanFolderPath(basePath);

	if (!folder.length) return nil;

	if (base.length) {
		if (![folder isEqualToString:base] && ![folder hasPrefix:[base stringByAppendingString:@"/"]]) return nil;
		if ([folder isEqualToString:base]) return nil;

		folder = [folder substringFromIndex:base.length + 1];
	}

	NSString *first = [[folder componentsSeparatedByString:@"/"] firstObject];
	if (!first.length) return nil;

	NSString *child = base.length ? [[base stringByAppendingPathComponent:first] copy] : first;
	return SCIGalleryStoredFolderPath(child);
}

#import "SCIGalleryViewController_Internal.h"

@interface SCIGalleryViewController ()
@property (nonatomic, strong) NSDictionary<NSString *, NSNumber *> *subfolderCounts;
@property (nonatomic, copy) dispatch_block_t searchDebounceBlock;
- (void)finishPickerWithURL:(NSURL *)url file:(SCIGalleryFile *)file;
@end

@implementation SCIGalleryViewController

+ (void)load {
	[[SCINotificationCenter shared] setDefaultTapProvider:^void (^(void))(void) {
		if (![SCIUtils getBoolPref:@"sci_gallery_enabled"]) return nil;
		return ^{ [SCIGalleryViewController presentGallery]; };
	} ownerVCClass:[SCIGalleryViewController class]
	  forAction:SCI_NOTIF_GALLERY_SAVE];
}

#pragma mark - Presentation

+ (void)presentGallery {
	[SCILockGate presentLockedVC:[SCIGalleryViewController new]
	                    forGroup:SCILockGroupGallery
	                        from:topMostController()];
}

+ (void)presentPickerWithMediaTypes:(NSArray<NSNumber *> *)allowedMediaTypes
							  title:(NSString *)title
							 fromVC:(UIViewController *)fromVC
						 completion:(void (^)(NSURL *, SCIGalleryFile *))completion {
	SCIGalleryViewController *vc = [[SCIGalleryViewController alloc] init];

	vc.pickerMode = YES;
	vc.pickerAllowedMediaTypes = [allowedMediaTypes copy];
	vc.pickerCompletion = [completion copy];
	vc.pickerTitleOverride = [title copy];

	[SCILockGate presentLockedVC:vc forGroup:SCILockGroupGallery from:(fromVC ?: topMostController())];
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

	_sortMode = (SCIGallerySortMode)(NSInteger)[SCIUtils getDoublePref:kSortModeKey];
	_viewMode = (SCIGalleryViewMode)(NSInteger)[SCIUtils getDoublePref:kViewModeKey];

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

	self.view.backgroundColor = [SCIPopupChrome backgroundColor];

	[[NSNotificationCenter defaultCenter] addObserver:self
											 selector:@selector(handleGalleryPreferencesChanged:)
												 name:@"SCIGalleryFavoritesSortPreferenceChanged"
											   object:nil];

	[[NSNotificationCenter defaultCenter] addObserver:self
											 selector:@selector(handleGalleryContextSaved:)
												 name:NSManagedObjectContextDidSaveNotification
											   object:[SCIGalleryCoreDataStack shared].viewContext];

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

- (void)finishPickerWithURL:(NSURL *)url file:(SCIGalleryFile *)file {
	void (^callback)(NSURL *, SCIGalleryFile *) = self.pickerCompletion;
	UINavigationController *nav = self.navigationController;

	for (UIViewController *vc in nav.viewControllers) {
		if ([vc isKindOfClass:[SCIGalleryViewController class]]) {
			((SCIGalleryViewController *)vc).pickerCompletion = nil;
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
		self.title = self.currentFolderPath.length ? [self.currentFolderPath lastPathComponent] : SCILocalized(@"Gallery");
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
			? [[UIBarButtonItem alloc] initWithTitle:SCILocalized(@"Cancel")
											   style:UIBarButtonItemStylePlain
											  target:self
											  action:@selector(pickerCancelTapped)]
			: nil;
		return;
	}

	if (self.selectionMode) {
		NSArray<SCIGalleryFile *> *files = [self visibleGalleryFiles];
		BOOL allSelected = files.count > 0 && self.selectedFileIDs.count == files.count;

		self.navigationItem.rightBarButtonItems = nil;
		self.navigationItem.leftBarButtonItem = [[UIBarButtonItem alloc] initWithTitle:SCILocalized(@"Cancel")
																				 style:UIBarButtonItemStylePlain
																				target:self
																				action:@selector(exitSelectionMode)];
		self.navigationItem.rightBarButtonItem = [[UIBarButtonItem alloc] initWithTitle:(allSelected ? SCILocalized(@"Deselect All") : SCILocalized(@"Select All"))
																				  style:UIBarButtonItemStylePlain
																				 target:self
																				 action:@selector(selectAllVisibleFiles)];
		return;
	}

	self.navigationItem.leftBarButtonItem = ([self.navigationController.viewControllers firstObject] == self)
		? SCIMediaChromeTopBarButtonItem(@"xmark", self, @selector(dismissSelf))
		: nil;

	NSMutableArray<UIBarButtonItem *> *items = [NSMutableArray array];

	if ([self.navigationController.viewControllers firstObject] == self) {
		[items addObject:SCIMediaChromeTopBarButtonItem(@"settings", self, @selector(pushSettings))];
	}

	[items addObject:SCIMediaChromeTopBarButtonItem(@"circle_check", self, @selector(enterSelectionMode))];

	self.navigationItem.rightBarButtonItem = nil;
	self.navigationItem.rightBarButtonItems = items;
}

#pragma mark - Search

- (void)setupSearchController {
	UISearchController *controller = [[UISearchController alloc] initWithSearchResultsController:nil];

	controller.obscuresBackgroundDuringPresentation = NO;
	controller.hidesNavigationBarDuringPresentation = NO;
	controller.searchResultsUpdater = self;
	controller.searchBar.placeholder = SCILocalized(@"Search");

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

	self.bottomBar = SCIMediaChromeInstallBottomBar(host);
	self.bottomBarStack = nil;
}

- (UIButton *)galleryBottomBarButtonWithResource:(NSString *)resourceName accessibility:(NSString *)label {
	return SCIMediaChromeBottomButton(resourceName, label);
}

- (void)refreshBottomToolbarItems {
	[self installBottomToolbarIfNeeded];

	[self.bottomBarStack removeFromSuperview];
	self.bottomBarStack = nil;

	UIButton *searchBtn = [self galleryBottomBarButtonWithResource:@"search" accessibility:SCILocalized(@"Search")];
	[searchBtn addTarget:self action:@selector(activateSearch) forControlEvents:UIControlEventTouchUpInside];

	if (self.selectionMode) {
		UIButton *shareBtn = [self galleryBottomBarButtonWithResource:@"share" accessibility:SCILocalized(@"Share selected")];
		UIButton *saveBtn = [self galleryBottomBarButtonWithResource:@"download" accessibility:SCILocalized(@"Save to Photos")];
		UIButton *moveBtn = [self galleryBottomBarButtonWithResource:@"folder_move" accessibility:SCILocalized(@"Move selected")];
		UIButton *favoriteBtn = [self galleryBottomBarButtonWithResource:@"heart" accessibility:SCILocalized(@"Favorite selected")];
		UIButton *deleteBtn = [self galleryBottomBarButtonWithResource:@"trash" accessibility:SCILocalized(@"Delete selected")];

		[shareBtn addTarget:self action:@selector(shareSelectedFiles) forControlEvents:UIControlEventTouchUpInside];
		[saveBtn addTarget:self action:@selector(saveSelectedFilesToPhotos) forControlEvents:UIControlEventTouchUpInside];
		[moveBtn addTarget:self action:@selector(moveSelectedFiles) forControlEvents:UIControlEventTouchUpInside];
		[favoriteBtn addTarget:self action:@selector(toggleFavoriteForSelectedFiles) forControlEvents:UIControlEventTouchUpInside];
		[deleteBtn addTarget:self action:@selector(deleteSelectedFiles) forControlEvents:UIControlEventTouchUpInside];

		deleteBtn.tintColor = [UIColor systemRedColor];

		self.bottomBarStack = SCIMediaChromeInstallBottomRow(self.bottomBar, @[shareBtn, saveBtn, moveBtn, favoriteBtn, deleteBtn]);
		return;
	}

	UIButton *filterBtn = [self galleryBottomBarButtonWithResource:@"filter" accessibility:SCILocalized(@"Filter")];
	UIButton *sortBtn = [self galleryBottomBarButtonWithResource:@"sort" accessibility:SCILocalized(@"Sort")];
	UIButton *folderBtn = [self galleryBottomBarButtonWithResource:@"folder" accessibility:SCILocalized(@"New Folder")];

	NSString *toggleResource = self.viewMode == SCIGalleryViewModeGrid ? @"list" : @"grid";
	NSString *toggleAX = self.viewMode == SCIGalleryViewModeGrid ? SCILocalized(@"List view") : SCILocalized(@"Grid view");
	UIButton *toggleBtn = [self galleryBottomBarButtonWithResource:toggleResource accessibility:toggleAX];

	[filterBtn addTarget:self action:@selector(presentFilter) forControlEvents:UIControlEventTouchUpInside];
	[sortBtn addTarget:self action:@selector(presentSort) forControlEvents:UIControlEventTouchUpInside];
	[folderBtn addTarget:self action:@selector(presentCreateFolder) forControlEvents:UIControlEventTouchUpInside];
	[toggleBtn addTarget:self action:@selector(toggleViewMode) forControlEvents:UIControlEventTouchUpInside];

	NSArray<UIView *> *row = self.pickerMode
		? @[toggleBtn, sortBtn, filterBtn, searchBtn]
		: @[toggleBtn, sortBtn, filterBtn, folderBtn, searchBtn];

	self.bottomBarStack = SCIMediaChromeInstallBottomRow(self.bottomBar, row);
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

	[_collectionView registerClass:[SCIGalleryGridCell class] forCellWithReuseIdentifier:kGridCellID];
	[_collectionView registerClass:[SCIGalleryListCollectionCell class] forCellWithReuseIdentifier:kListCellID];
	[_collectionView registerClass:[SCIGalleryFolderCell class] forCellWithReuseIdentifier:kFolderCellID];
	[_collectionView registerClass:[SCIGalleryUserHeaderView class]
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

- (UICollectionViewLayout *)layoutForViewMode:(SCIGalleryViewMode)mode {
	if (mode == SCIGalleryViewModeGrid) {
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

			SCIGalleryFile *file = [self galleryFileForCollectionIndexPath:idx];
			if (!file) return nil;

			UIContextualAction *deleteAction = [UIContextualAction contextualActionWithStyle:UIContextualActionStyleDestructive
																					   title:SCILocalized(@"Delete")
																					 handler:^(UIContextualAction *action, UIView *view, void (^completion)(BOOL)) {
				(void)action;
				(void)view;

				[self confirmDeleteFile:file];
				completion(YES);
			}];

			deleteAction.image = [UIImage systemImageNamed:@"trash.fill"];

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

	self.viewMode = self.viewMode == SCIGalleryViewModeGrid ? SCIGalleryViewModeList : SCIGalleryViewModeGrid;

	[SCIUtils setPref:@(self.viewMode) forKey:kViewModeKey];

	[self.collectionView setCollectionViewLayout:[self layoutForViewMode:self.viewMode] animated:NO];
	[self.collectionView reloadData];
	[self updateEmptyState];
	[self refreshBottomToolbarItems];
}

#pragma mark - Empty State

- (void)setupScrollToTopButton {
	SCIScrollToTopButton *btn = [SCIScrollToTopButton new];

	[btn attachToScrollView:self.collectionView inView:self.view bottomInset:(SCIMediaChromeBottomBarHeight + 16)];

	self.scrollToTopButton = btn;
}

- (void)setupEmptyState {
	_emptyStateView = [UIView new];
	_emptyStateView.translatesAutoresizingMaskIntoConstraints = NO;
	_emptyStateView.hidden = YES;

	[self.view addSubview:_emptyStateView];

	UIImageView *icon = [[UIImageView alloc] initWithImage:[SCIAssetUtils instagramIconNamed:@"media_empty" pointSize:96.0]];
	icon.translatesAutoresizingMaskIntoConstraints = NO;
	icon.contentMode = UIViewContentModeScaleAspectFit;
	icon.tintColor = [UIColor tertiaryLabelColor];

	[_emptyStateView addSubview:icon];

	_emptyStateLabel = [UILabel new];
	_emptyStateLabel.translatesAutoresizingMaskIntoConstraints = NO;
	_emptyStateLabel.text = SCILocalized(@"No files in Gallery");
	_emptyStateLabel.textColor = [UIColor secondaryLabelColor];
	_emptyStateLabel.font = [UIFont systemFontOfSize:17 weight:UIFontWeightMedium];
	_emptyStateLabel.textAlignment = NSTextAlignmentCenter;

	[_emptyStateView addSubview:_emptyStateLabel];

	UILabel *subtitle = [UILabel new];
	subtitle.translatesAutoresizingMaskIntoConstraints = NO;
	subtitle.text = SCILocalized(@"Save media from the preview screen\nto see it here.");
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
	NSInteger folders = [self showsFolderSection] ? self.subfolders.count : 0;
	BOOL hasFilters = self.filterTypes.count || self.filterSources.count || self.filterUsernames.count || self.filterFavoritesOnly;
	BOOL empty = files == 0 && folders == 0;

	self.emptyStateView.hidden = !empty;
	self.collectionView.hidden = NO;
	self.emptyStateLabel.text = empty && hasFilters ? SCILocalized(@"No matching files") : SCILocalized(@"No files in Gallery");
}

#pragma mark - Fetched Results Controller

- (NSString *)groupMode {
	if (self.usernameScope.length) return kGroupModeOff;

	NSString *mode = [SCIUtils getStringPref:kGroupModeKey];
	// Picker can't navigate sub-folders — fall back to Sections so files stay visible.
	if (self.pickerMode && [mode isEqualToString:kGroupModeFolders]) return kGroupModeSections;
	if ([mode isEqualToString:kGroupModeSections]) return kGroupModeSections;
	if ([mode isEqualToString:kGroupModeFolders])  return kGroupModeFolders;
	return kGroupModeOff;
}

- (BOOL)isGroupingByUser {
	return [[self groupMode] isEqualToString:kGroupModeSections];
}

- (BOOL)isShowingUserFolders {
	if (![[self groupMode] isEqualToString:kGroupModeFolders]) return NO;
	if (self.currentFolderPath.length) return NO;
	if (self.searchQuery.length) return NO;
	if (self.filterUsernames.count) return NO;
	return YES;
}

// Inline folders into the file section so flow layout fills the row.
- (BOOL)mergesFolderIntoGridSection {
	if (self.viewMode != SCIGalleryViewModeGrid) return NO;
	if (![[self groupMode] isEqualToString:kGroupModeFolders]) return NO;
	return [self showsFolderSection];
}

- (NSInteger)folderSectionOffset {
	if ([self mergesFolderIntoGridSection]) return 0;
	return [self showsFolderSection] ? 1 : 0;
}

- (void)setupFetchedResultsController {
	NSFetchRequest *request = [self currentFetchRequest];
	NSManagedObjectContext *context = [SCIGalleryCoreDataStack shared].viewContext;
	NSString *sectionKey = [self isGroupingByUser] ? @"sourceUsername" : nil;

	_fetchedResultsController = [[NSFetchedResultsController alloc] initWithFetchRequest:request
																	managedObjectContext:context
																	  sectionNameKeyPath:sectionKey
																			   cacheName:nil];
	_fetchedResultsController.delegate = self;

	NSError *error = nil;

	if (![_fetchedResultsController performFetch:&error]) {
		NSLog(@"[SCInsta Gallery] Fetch failed: %@", error);
	}
}

- (NSFetchRequest *)currentFetchRequest {
	NSFetchRequest *request = [[NSFetchRequest alloc] initWithEntityName:@"SCIGalleryFile"];
	NSMutableArray<NSSortDescriptor *> *sorts = [[SCIGallerySortViewController sortDescriptorsForMode:self.sortMode] mutableCopy];

	if ([SCIUtils getBoolPref:kFavoritesAtTopKey] && !self.filterFavoritesOnly) {
		[sorts insertObject:[NSSortDescriptor sortDescriptorWithKey:@"isFavorite" ascending:NO] atIndex:0];
	}

	// Primary sort must match FRC sectionNameKeyPath.
	if ([self isGroupingByUser]) {
		[sorts insertObject:[NSSortDescriptor sortDescriptorWithKey:@"sourceUsername"
														  ascending:YES
														   selector:@selector(localizedCaseInsensitiveCompare:)]
					atIndex:0];
	}

	NSMutableArray<NSPredicate *> *predicates = [NSMutableArray array];

	NSPredicate *base = [SCIGalleryFilterViewController predicateForTypes:self.filterTypes
																  sources:self.filterSources
																usernames:self.filterUsernames
															favoritesOnly:self.filterFavoritesOnly
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
		NSLog(@"[SCInsta Gallery] Refetch failed: %@", error);
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

	NSManagedObjectContext *context = [SCIGalleryCoreDataStack shared].viewContext;
	NSFetchRequest *request = [[NSFetchRequest alloc] initWithEntityName:@"SCIGalleryFile"];

	request.resultType = NSDictionaryResultType;
	request.propertiesToFetch = @[@"sourceUsername", @"identifier", @"dateAdded"];
	request.predicate = [NSPredicate predicateWithFormat:@"sourceUsername != nil AND sourceUsername != %@", @""];
	request.sortDescriptors = @[[NSSortDescriptor sortDescriptorWithKey:@"dateAdded" ascending:NO]];

	NSArray<NSDictionary *> *rows = [context executeFetchRequest:request error:nil];
	NSMutableDictionary<NSString *, NSNumber *> *counts = [NSMutableDictionary dictionary];
	NSMutableDictionary<NSString *, NSMutableArray<NSString *> *> *thumbs = [NSMutableDictionary dictionary];
	NSMutableDictionary<NSString *, NSDate *> *dates = [NSMutableDictionary dictionary];
	NSString *thumbDir = [SCIGalleryPaths galleryThumbnailsDirectory];
	NSFileManager *fm = [NSFileManager defaultManager];

	for (NSDictionary *row in rows) {
		NSString *name = row[@"sourceUsername"];
		if (!name.length) continue;

		counts[name] = @([counts[name] integerValue] + 1);

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

	self.userFolders = [[counts allKeys] sortedArrayUsingSelector:@selector(localizedCaseInsensitiveCompare:)];
	self.userFolderCounts = [counts copy];
	self.userFolderThumbnailPaths = [thumbs copy];
	self.userFolderLastDates = [dates copy];
}

- (void)reloadSubfolderThumbnails {
	if (!self.subfolders.count) {
		self.subfolderThumbnailPaths = @{};
		self.subfolderLastDates = @{};
		return;
	}

	NSManagedObjectContext *context = [SCIGalleryCoreDataStack shared].viewContext;
	NSFetchRequest *request = [[NSFetchRequest alloc] initWithEntityName:@"SCIGalleryFile"];

	request.resultType = NSDictionaryResultType;
	request.propertiesToFetch = @[@"folderPath", @"identifier", @"dateAdded"];
	request.predicate = [NSPredicate predicateWithFormat:@"folderPath != nil AND folderPath != %@", @""];
	request.sortDescriptors = @[[NSSortDescriptor sortDescriptorWithKey:@"dateAdded" ascending:NO]];

	NSArray<NSDictionary *> *rows = [context executeFetchRequest:request error:nil];
	NSMutableDictionary<NSString *, NSMutableArray<NSString *> *> *thumbs = [NSMutableDictionary dictionary];
	NSMutableDictionary<NSString *, NSDate *> *dates = [NSMutableDictionary dictionary];
	NSString *thumbDir = [SCIGalleryPaths galleryThumbnailsDirectory];
	NSFileManager *fm = [NSFileManager defaultManager];
	NSSet<NSString *> *visibleFolders = [NSSet setWithArray:self.subfolders];

	for (NSDictionary *row in rows) {
		NSString *folder = row[@"folderPath"];
		if (!folder.length) continue;

		NSString *child = SCIGalleryImmediateChildPath(folder, self.currentFolderPath);
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

	NSManagedObjectContext *context = [SCIGalleryCoreDataStack shared].viewContext;
	NSFetchRequest *request = [[NSFetchRequest alloc] initWithEntityName:@"SCIGalleryFile"];

	request.resultType = NSDictionaryResultType;
	request.propertiesToFetch = @[@"folderPath"];
	request.predicate = [NSPredicate predicateWithFormat:@"folderPath != nil AND folderPath != ''"];

	NSArray<NSDictionary *> *rows = [context executeFetchRequest:request error:nil];
	NSMutableDictionary<NSString *, NSNumber *> *counts = [NSMutableDictionary dictionary];
	NSMutableSet<NSString *> *folders = [NSMutableSet set];

	for (NSDictionary *row in rows) {
		NSString *child = SCIGalleryImmediateChildPath(row[@"folderPath"], self.currentFolderPath);
		if (!child.length) continue;

		[folders addObject:child];

		counts[child] = @([counts[child] integerValue] + 1);
	}

	self.subfolders = [[folders allObjects] sortedArrayUsingSelector:@selector(localizedStandardCompare:)];
	self.subfolderCounts = [counts copy];

	[self mergePlaceholderSubfolders];
	[self reloadSubfolderThumbnails];
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

	NSInteger frcIdx = section - [self folderSectionOffset];

	if (frcIdx < 0 || frcIdx >= (NSInteger)sections.count) return 0;

	return ((id<NSFetchedResultsSectionInfo>)sections[frcIdx]).numberOfObjects;
}

- (__kindof UICollectionViewCell *)collectionView:(UICollectionView *)collectionView cellForItemAtIndexPath:(NSIndexPath *)indexPath {
	if ([self isFolderIndexPath:indexPath]) {
		SCIGalleryFolderCell *cell = [collectionView dequeueReusableCellWithReuseIdentifier:kFolderCellID forIndexPath:indexPath];
		SCIGalleryFolderCellLayout layout = (self.viewMode == SCIGalleryViewModeGrid)
			? SCIGalleryFolderCellLayoutGrid
			: SCIGalleryFolderCellLayoutList;

		if ([self folderIndexPathIsUserFolder:indexPath]) {
			NSString *username = [self userFolderNameAtFolderIndex:indexPath.item];
			NSInteger count = [self.userFolderCounts[username] integerValue];
			NSString *subtitle = SCIGalleryFolderSubtitle(count, self.userFolderLastDates[username ?: @""]);
			[cell configureWithFolderName:[@"@" stringByAppendingString:(username ?: @"")]
								 subtitle:subtitle
						   thumbnailPaths:self.userFolderThumbnailPaths[username ?: @""]
							   layoutMode:layout
							 isUserFolder:YES];
		} else {
			NSString *path = self.subfolders[indexPath.item];
			NSInteger count = [self.subfolderCounts[path] integerValue];
			NSString *subtitle = SCIGalleryFolderSubtitle(count, self.subfolderLastDates[path]);
			[cell configureWithFolderName:[path lastPathComponent]
								 subtitle:subtitle
						   thumbnailPaths:self.subfolderThumbnailPaths[path]
							   layoutMode:layout
							 isUserFolder:NO];
		}

		return cell;
	}

	SCIGalleryFile *file = [self galleryFileForCollectionIndexPath:indexPath];

	if (self.viewMode == SCIGalleryViewModeGrid) {
		SCIGalleryGridCell *cell = [collectionView dequeueReusableCellWithReuseIdentifier:kGridCellID forIndexPath:indexPath];

		[cell configureWithGalleryFile:file
						 selectionMode:self.selectionMode
							  selected:[self.selectedFileIDs containsObject:file.identifier]];

		return cell;
	}

	SCIGalleryListCollectionCell *cell = [collectionView dequeueReusableCellWithReuseIdentifier:kListCellID forIndexPath:indexPath];

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

	SCIGalleryUserHeaderView *header = [collectionView dequeueReusableSupplementaryViewOfKind:kind
																		 withReuseIdentifier:kUserHeaderID
																				forIndexPath:indexPath];

	NSInteger frcSection = indexPath.section - [self folderSectionOffset];
	NSArray *sections = self.fetchedResultsController.sections;
	NSString *name = (frcSection >= 0 && frcSection < (NSInteger)sections.count)
		? ((id<NSFetchedResultsSectionInfo>)sections[frcSection]).name
		: nil;

	header.titleLabel.text = name.length ? name : SCILocalized(@"Unknown");

	return header;
}

#pragma mark - UICollectionViewDelegateFlowLayout

- (CGSize)collectionView:(UICollectionView *)collectionView layout:(UICollectionViewLayout *)layout sizeForItemAtIndexPath:(NSIndexPath *)indexPath {
	CGFloat width = collectionView.bounds.size.width;

	if ([self isFolderIndexPath:indexPath]) {
		if (self.viewMode == SCIGalleryViewModeGrid) {
			CGFloat side = floor((width - (kGridSpacing * (kGridColumns - 1))) / kGridColumns);
			return CGSizeMake(side, side);
		}
		return CGSizeMake(width, 88);
	}

	if (self.viewMode == SCIGalleryViewModeGrid) {
		CGFloat side = floor((width - (kGridSpacing * (kGridColumns - 1))) / kGridColumns);
		return CGSizeMake(side, side);
	}

	return CGSizeMake(width, 88);
}

- (UIEdgeInsets)collectionView:(UICollectionView *)collectionView layout:(UICollectionViewLayout *)layout insetForSectionAtIndex:(NSInteger)section {
	if (!([self showsFolderSection] && section == 0)) return UIEdgeInsetsZero;

	return (self.viewMode == SCIGalleryViewModeGrid)
		? UIEdgeInsetsZero
		: UIEdgeInsetsMake(10, 0, 6, 0);
}

- (CGFloat)collectionView:(UICollectionView *)collectionView layout:(UICollectionViewLayout *)layout minimumInteritemSpacingForSectionAtIndex:(NSInteger)section {
	BOOL folderSec = [self showsFolderSection] && section == 0;
	if (folderSec && self.viewMode != SCIGalleryViewModeGrid) return 0;
	return self.viewMode == SCIGalleryViewModeGrid ? kGridSpacing : 0;
}

- (CGFloat)collectionView:(UICollectionView *)collectionView layout:(UICollectionViewLayout *)layout minimumLineSpacingForSectionAtIndex:(NSInteger)section {
	BOOL folderSec = [self showsFolderSection] && section == 0;
	if (folderSec && self.viewMode != SCIGalleryViewModeGrid) return 0;
	return self.viewMode == SCIGalleryViewModeGrid ? kGridSpacing : 0;
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

		SCIGalleryViewController *child;

		if ([self folderIndexPathIsUserFolder:indexPath]) {
			NSString *username = [self userFolderNameAtFolderIndex:indexPath.item];
			if (!username.length) return;
			child = [[SCIGalleryViewController alloc] initWithUsernameScope:username];
		} else {
			child = [[SCIGalleryViewController alloc] initWithFolderPath:self.subfolders[indexPath.item]];
		}

		child.pickerMode = self.pickerMode;
		child.pickerAllowedMediaTypes = self.pickerAllowedMediaTypes;
		child.pickerCompletion = self.pickerCompletion;
		child.pickerTitleOverride = self.pickerTitleOverride;

		[self.navigationController pushViewController:child animated:YES];

		return;
	}

	SCIGalleryFile *file = [self galleryFileForCollectionIndexPath:indexPath];
	if (!file) return;

	if (self.pickerMode) {
		[self finishPickerWithURL:[file fileURL] file:file];
		return;
	}

	if (self.selectionMode) {
		[self toggleSelectionForFile:file];
		return;
	}

	NSArray<SCIGalleryFile *> *files = self.fetchedResultsController.fetchedObjects ?: @[];
	NSUInteger startIndex = [files indexOfObject:file];

	if (startIndex == NSNotFound) {
		startIndex = 0;
	}

	NSMutableArray<SCIMediaViewerItem *> *items = [NSMutableArray arrayWithCapacity:files.count];

	for (SCIGalleryFile *item in files) {
		NSURL *url = [item fileURL];
		SCIMediaViewerItem *viewerItem = nil;

		switch (item.mediaType) {
			case SCIGalleryMediaTypeVideo:
				viewerItem = [SCIMediaViewerItem itemWithVideoURL:url photoURL:nil caption:nil];
				break;
			case SCIGalleryMediaTypeAudio:
				viewerItem = [SCIMediaViewerItem itemWithAudioURL:url caption:nil];
				break;
			case SCIGalleryMediaTypeGIF:
				viewerItem = [SCIMediaViewerItem itemWithAnimatedImageURL:url caption:nil];
				break;
			case SCIGalleryMediaTypeImage:
			default:
				viewerItem = [SCIMediaViewerItem itemWithVideoURL:nil photoURL:url caption:nil];
				break;
		}

		if (viewerItem) {
			[items addObject:viewerItem];
		}
	}

	if (items.count) {
		[SCIMediaViewer showItems:items startIndex:MIN(startIndex, items.count - 1) shareSheetOnly:YES];
	}
}

- (NSArray<SCIGalleryFile *> *)visibleGalleryFiles {
	return self.fetchedResultsController.fetchedObjects ?: @[];
}

- (SCIGalleryFile *)galleryFileForCollectionIndexPath:(NSIndexPath *)indexPath {
	if ([self isFolderIndexPath:indexPath]) return nil;

	NSArray *sections = self.fetchedResultsController.sections;
	NSInteger frcSection = indexPath.section - [self folderSectionOffset];
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

	SCIGalleryFile *file = [self galleryFileForCollectionIndexPath:indexPath];

	return file ? [self contextMenuForFile:file] : nil;
}

#pragma mark - Sort / Filter

- (void)presentGallerySheet:(SCIGallerySheetViewController *)contentVC {
	[self presentViewController:contentVC animated:NO completion:nil];
}

- (void)presentSort {
	SCIGallerySortViewController *vc = [SCIGallerySortViewController new];

	vc.delegate = self;
	vc.currentSortMode = self.sortMode;

	[self presentGallerySheet:vc];
}

- (void)presentFilter {
	SCIGalleryFilterViewController *vc = [SCIGalleryFilterViewController new];

	vc.delegate = self;
	vc.filterTypes = self.filterTypes;
	vc.filterSources = self.filterSources;
	vc.filterUsernames = self.filterUsernames;
	vc.filterFavoritesOnly = self.filterFavoritesOnly;

	[self presentGallerySheet:vc];
}

- (void)sortController:(SCIGallerySortViewController *)controller didSelectSortMode:(SCIGallerySortMode)mode {
	(void)controller;

	self.sortMode = mode;

	[SCIUtils setPref:@(mode) forKey:kSortModeKey];

	[self refetch];
}

- (void)filterController:(SCIGalleryFilterViewController *)controller
		   didApplyTypes:(NSSet<NSNumber *> *)types
				 sources:(NSSet<NSNumber *> *)sources
			   usernames:(NSSet<NSString *> *)usernames
		   favoritesOnly:(BOOL)favoritesOnly {
	(void)controller;

	self.filterTypes = [types mutableCopy];
	self.filterSources = [sources mutableCopy];
	self.filterUsernames = [usernames mutableCopy];
	self.filterFavoritesOnly = favoritesOnly;

	[self refetch];
}

- (void)filterControllerDidClear:(SCIGalleryFilterViewController *)controller {
	(void)controller;

	[self.filterTypes removeAllObjects];
	[self.filterSources removeAllObjects];
	[self.filterUsernames removeAllObjects];

	self.filterFavoritesOnly = NO;

	[self refetch];
}

- (void)handleGalleryPreferencesChanged:(NSNotification *)note {
	(void)note;

	// sectionNameKeyPath is immutable on FRC — rebuild when group mode flips.
	[self setupFetchedResultsController];

	if (self.viewMode == SCIGalleryViewModeList) {
		[self.collectionView setCollectionViewLayout:[self layoutForViewMode:self.viewMode] animated:NO];
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

#pragma mark - Settings

- (void)pushSettings {
	[self.navigationController pushViewController:[SCIGallerySettingsViewController new] animated:YES];
}

@end