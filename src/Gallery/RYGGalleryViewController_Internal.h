// Private continuation header — exposes RYGGalleryViewController's ivars +
// helper methods to the main implementation file and its category files.
//
// Treat this as internal: do NOT import from outside src/Gallery/.

#import "RYGGalleryViewController.h"
#import "RYGGalleryFilterViewController.h"
#import "RYGGallerySortViewController.h"
#import <CoreData/CoreData.h>

@class RYGGalleryFile;

NS_ASSUME_NONNULL_BEGIN

typedef NS_ENUM(NSInteger, RYGGalleryViewMode) {
	RYGGalleryViewModeGrid = 0,
	RYGGalleryViewModeList = 1,
};

@interface RYGGalleryViewController () <UICollectionViewDataSource,
										UICollectionViewDelegate,
										UICollectionViewDelegateFlowLayout,
										NSFetchedResultsControllerDelegate,
										RYGGallerySortViewControllerDelegate,
										RYGGalleryFilterViewControllerDelegate,
										UIAdaptivePresentationControllerDelegate,
										UISearchResultsUpdating>

@property (nonatomic, strong) UICollectionView *collectionView;
@property (nonatomic, strong) NSFetchedResultsController *fetchedResultsController;
@property (nonatomic, strong) UIView *emptyStateView;
@property (nonatomic, strong) UILabel *emptyStateLabel;
@property (nonatomic, strong, nullable) UIView *bottomBar;
@property (nonatomic, strong, nullable) UIStackView *bottomBarStack;
@property (nonatomic, strong, nullable) id scrollToTopButton;

@property (nonatomic, copy, nullable) NSString *currentFolderPath;
@property (nonatomic, copy, nullable) NSString *usernameScope;
@property (nonatomic, strong) NSArray<NSString *> *subfolders;
@property (nonatomic, strong) NSArray<NSString *> *userFolders;
@property (nonatomic, strong) NSDictionary<NSString *, NSNumber *> *userFolderCounts;
@property (nonatomic, strong) NSDictionary<NSString *, NSNumber *> *userFolderSizes;
@property (nonatomic, strong) NSDictionary<NSString *, NSNumber *> *subfolderSizes;
@property (nonatomic, strong) NSDictionary<NSString *, NSArray<NSString *> *> *subfolderThumbnailPaths;
@property (nonatomic, strong) NSDictionary<NSString *, NSArray<NSString *> *> *userFolderThumbnailPaths;
@property (nonatomic, strong) NSDictionary<NSString *, NSDate *> *subfolderLastDates;
@property (nonatomic, strong) NSDictionary<NSString *, NSDate *> *userFolderLastDates;

@property (nonatomic, assign) RYGGalleryViewMode viewMode;

@property (nonatomic, strong) NSMutableSet<NSNumber *> *filterTypes;
@property (nonatomic, strong) NSMutableSet<NSNumber *> *filterSources;
@property (nonatomic, strong) NSMutableSet<NSString *> *filterUsernames;
@property (nonatomic, assign) BOOL filterFavoritesOnly;
@property (nonatomic, strong, nullable) NSDate *filterDateFrom;
@property (nonatomic, strong, nullable) NSDate *filterDateTo;

// Display order of FRC sections when grouping by user; nil = identity mapping.
@property (nonatomic, strong, nullable) NSArray<NSNumber *> *orderedSectionIndices;

@property (nonatomic, assign) BOOL didOfferLegacyMigration;

@property (nonatomic, assign) BOOL selectionMode;
@property (nonatomic, strong) NSMutableSet<NSString *> *selectedFileIDs;

@property (nonatomic, strong) UISearchController *searchController;
@property (nonatomic, copy) NSString *searchQuery;

// Picker mode — selecting a file fires `pickerCompletion` and dismisses.
// Folder navigation still works; multi-select / settings chrome is hidden.
@property (nonatomic, assign) BOOL pickerMode;
@property (nonatomic, copy, nullable) NSArray<NSNumber *> *pickerAllowedMediaTypes;
@property (nonatomic, copy, nullable) void (^pickerCompletion)(NSURL * _Nullable url, RYGGalleryFile * _Nullable file);
@property (nonatomic, copy, nullable) NSString *pickerTitleOverride;

// Methods that live in the main implementation. The (Actions) category
// declares its own additions below.
- (void)refetch;
- (void)reloadSubfolders;
- (void)refreshNavigationItems;
- (void)refreshBottomToolbarItems;
- (void)updateEmptyState;
- (NSArray<RYGGalleryFile *> *)visibleGalleryFiles;
- (RYGGalleryFile *)galleryFileForCollectionIndexPath:(NSIndexPath *)indexPath;
- (BOOL)isFolderIndexPath:(NSIndexPath *)indexPath;
- (NSInteger)gridColumns;
- (NSInteger)realSectionForOrderedIndex:(NSInteger)orderedIndex;
- (NSInteger)folderSectionOffset;

@end

@interface RYGGalleryViewController (Actions)
- (UIMenu *)fileActionsMenuForFile:(RYGGalleryFile *)file;
- (UIContextMenuConfiguration *)contextMenuForFile:(RYGGalleryFile *)file;
- (UIContextMenuConfiguration *)contextMenuForFolder:(NSString *)folderPath;
- (UIContextMenuConfiguration *)contextMenuForUserFolder:(NSString *)username;
- (void)confirmDeleteUserFolder:(NSString *)username;
- (void)confirmDeleteFile:(RYGGalleryFile *)file;
- (void)openOriginalPostForFile:(RYGGalleryFile *)file;
- (void)openProfileForFile:(RYGGalleryFile *)file;
- (void)renameFile:(RYGGalleryFile *)file;
- (void)moveFile:(RYGGalleryFile *)file;
- (void)assignFolderPath:(nullable NSString *)folderPath toFiles:(NSArray<RYGGalleryFile *> *)files;
- (void)presentMoveSheetForFiles:(NSArray<RYGGalleryFile *> *)files;

- (void)enterSelectionMode;
- (void)exitSelectionMode;
- (void)toggleSelectionForFile:(RYGGalleryFile *)file;
- (void)selectAllVisibleFiles;
- (void)selectAllFilesInDisplaySection:(NSInteger)displaySection;
- (void)shareSelectedFiles;
- (void)saveSelectedFilesToPhotos;
- (void)rygSaveGalleryFilesToPhotos:(NSArray<RYGGalleryFile *> *)files;
- (void)moveSelectedFiles;
- (void)toggleFavoriteForSelectedFiles;
- (void)deleteSelectedFiles;
- (NSArray<RYGGalleryFile *> *)selectedGalleryFiles;
- (void)animateSelectionModeTransition;

- (void)presentCreateFolder;
- (void)createFolderNamed:(NSString *)name;
- (void)renameFolder:(NSString *)folderPath;
- (void)performRenameOfFolder:(NSString *)oldPath toName:(NSString *)newName;
- (void)deleteFolder:(NSString *)folderPath;
- (void)performDeleteFolder:(NSString *)folderPath;
- (NSString *)folderPathByAppendingComponent:(NSString *)component toBase:(nullable NSString *)base;
- (NSArray<NSString *> *)allFolderPaths;
- (void)mergePlaceholderSubfolders;

- (void)showGalleryOpenFailureMessage:(NSString *)title actionIdentifier:(NSString *)actionIdentifier;
- (void)dismissGalleryForOriginOpenWithCompletion:(void (^_Nullable)(void))completion;
@end

NS_ASSUME_NONNULL_END
