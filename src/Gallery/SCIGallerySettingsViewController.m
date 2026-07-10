#import "SCIGallerySettingsViewController.h"
#import "SCIGalleryDeleteViewController.h"
#import "SCIGalleryFile.h"
#import "SCIGalleryCoreDataStack.h"
#import "../Utils.h"
#import "../UI/SCIOptionSheet.h"
#import <CoreData/CoreData.h>

static NSString *const kFavoritesAtTopKey = @"show_favorites_at_top";
static NSString *const kGroupModeKey = @"gallery_group_mode";
static NSString *const kGroupModeOff = @"off";
static NSString *const kGroupModeSections = @"sections";
static NSString *const kGroupModeFolders = @"folders";
static NSString *const kPrefsChanged = @"SCIGalleryFavoritesSortPreferenceChanged";

@interface SCIGalleryStorageStats : NSObject
@property (nonatomic) NSInteger totalFiles;
@property (nonatomic) NSInteger imageCount;
@property (nonatomic) NSInteger videoCount;
@property (nonatomic) long long totalSize;
@end

@implementation SCIGalleryStorageStats
@end

@interface SCIGallerySettingsViewController ()
@property (nonatomic, strong) SCIGalleryStorageStats *stats;
@end

@implementation SCIGallerySettingsViewController

- (instancetype)init {
	if ((self = [super initWithTitle:SCILocalized(@"Gallery Settings")])) {
		_stats = [SCIGalleryStorageStats new];
	}
	return self;
}

- (void)viewWillAppear:(BOOL)animated {
	[super viewWillAppear:animated];
	[self reloadStatsAndSections];
}

#pragma mark - Stats

- (void)reloadStatsAndSections {
	[self reloadStats];
	[self rebuildSections];
}

- (void)reloadStats {
	NSManagedObjectContext *ctx = [SCIGalleryCoreDataStack shared].viewContext;
	NSFetchRequest *req = [[NSFetchRequest alloc] initWithEntityName:@"SCIGalleryFile"];
	req.resultType = NSDictionaryResultType;
	req.propertiesToFetch = @[@"mediaType", @"fileSize"];
	req.includesPendingChanges = YES;

	SCIGalleryStorageStats *s = [SCIGalleryStorageStats new];

	for (NSDictionary *row in [ctx executeFetchRequest:req error:nil] ?: @[]) {
		NSInteger type = [row[@"mediaType"] integerValue];
		s.totalFiles++;
		s.totalSize += [row[@"fileSize"] longLongValue];
		type == SCIGalleryMediaTypeVideo ? s.videoCount++ : s.imageCount++;
	}

	self.stats = s;
}

- (NSString *)sizeText {
	return [NSByteCountFormatter stringFromByteCount:self.stats.totalSize countStyle:NSByteCountFormatterCountStyleFile];
}

- (NSString *)groupModeLabel {
	NSString *v = [SCIUtils getStringPref:kGroupModeKey];
	if ([v isEqualToString:kGroupModeSections]) return SCILocalized(@"Sections");
	if ([v isEqualToString:kGroupModeFolders]) return SCILocalized(@"Folders");
	return SCILocalized(@"Off");
}

#pragma mark - Sections

- (void)rebuildSections {
	__weak typeof(self) weak = self;

	SCISetting *total = [SCISetting staticCellWithTitle:SCILocalized(@"Total files") subtitle:@"" icon:nil];
	total.dynamicSubtitle = ^{ return [NSString stringWithFormat:@"%ld", (long)weak.stats.totalFiles]; };

	SCISetting *images = [SCISetting staticCellWithTitle:SCILocalized(@"Images") subtitle:@"" icon:nil];
	images.dynamicSubtitle = ^{ return [NSString stringWithFormat:@"%ld", (long)weak.stats.imageCount]; };

	SCISetting *videos = [SCISetting staticCellWithTitle:SCILocalized(@"Videos") subtitle:@"" icon:nil];
	videos.dynamicSubtitle = ^{ return [NSString stringWithFormat:@"%ld", (long)weak.stats.videoCount]; };

	SCISetting *size = [SCISetting staticCellWithTitle:SCILocalized(@"Total size") subtitle:@"" icon:nil];
	size.dynamicSubtitle = ^{ return [weak sizeText]; };

	SCISetting *favorites = [SCISetting switchCellWithTitle:SCILocalized(@"Show favorites at top")
												   subtitle:nil
													  value:^BOOL{
		return [SCIUtils getBoolPref:kFavoritesAtTopKey];
	} action:^(BOOL on) {
		[SCIUtils setPref:@(on) forKey:kFavoritesAtTopKey];
		[NSNotificationCenter.defaultCenter postNotificationName:kPrefsChanged object:nil];
	}];

	SCISetting *group = [SCISetting buttonCellWithTitle:SCILocalized(@"Group by user") subtitle:@"" icon:nil action:^{
		[weak presentGroupModeSheet];
	}];
	group.dynamicSubtitle = ^{ return [weak groupModeLabel]; };

	SCISetting *delete = [SCISetting buttonCellWithTitle:SCILocalized(@"Delete files") subtitle:@"" icon:nil action:^{
		[weak openDeletePage];
	}];
	delete.titleColor = UIColor.systemRedColor;

	[self applySettingSections:@[
		[SCISettingsViewController sectionWithHeader:SCILocalized(@"Storage") footer:nil rows:@[total, images, videos, size]],
		[SCISettingsViewController sectionWithHeader:SCILocalized(@"Browsing")
											 footer:SCILocalized(@"When enabled, favorites are pinned above other files inside the current sort and folder context.")
											   rows:@[favorites, group]],
		[SCISettingsViewController sectionWithHeader:SCILocalized(@"Manage") footer:nil rows:@[delete]]
	]];
}

#pragma mark - Actions

- (void)presentGroupModeSheet {
	NSArray *options = @[
		@{@"title": SCILocalized(@"Off"), @"value": kGroupModeOff, @"description": SCILocalized(@"Flat list. No grouping.")},
		@{@"title": SCILocalized(@"Sections"), @"value": kGroupModeSections, @"description": SCILocalized(@"Each user gets a labelled section in the grid/list.")},
		@{@"title": SCILocalized(@"Folders"), @"value": kGroupModeFolders, @"description": SCILocalized(@"Each user appears as a folder next to your real folders.")}
	];

	[SCIOptionSheet presentFrom:self title:SCILocalized(@"Group by user") defaultsKey:kGroupModeKey options:options onChange:^(__unused NSString *value) {
		[NSNotificationCenter.defaultCenter postNotificationName:kPrefsChanged object:nil];
		[self rebuildSections];
	}];
}

- (void)openDeletePage {
	SCIGalleryDeleteViewController *vc = [[SCIGalleryDeleteViewController alloc] initWithMode:SCIGalleryDeletePageModeRoot];

	__weak typeof(self) weak = self;
	vc.onDidDelete = ^{
		[weak reloadStatsAndSections];
		[NSNotificationCenter.defaultCenter postNotificationName:kPrefsChanged object:nil];
	};

	[self.navigationController pushViewController:vc animated:YES];
}

@end