#import "RYGGallerySettingsViewController.h"
#import "RYGGalleryDeleteViewController.h"
#import "RYGGalleryFile.h"
#import "RYGGalleryCoreDataStack.h"
#import "../Utils.h"
#import "../UI/RYGOptionSheet.h"
#import <CoreData/CoreData.h>

static NSString *const kFavoritesAtTopKey = @"show_favorites_at_top";
static NSString *const kGridColumnsKey = @"gallery_grid_columns";
static NSString *const kGroupModeKey = @"gallery_group_mode";
static NSString *const kGroupModeOff = @"off";
static NSString *const kGroupModeSections = @"sections";
static NSString *const kGroupModeFolders = @"folders";
static NSString *const kPrefsChanged = @"RYGGalleryFavoritesSortPreferenceChanged";

@interface RYGGalleryStorageStats : NSObject
@property (nonatomic) NSInteger totalFiles;
@property (nonatomic) NSInteger imageCount;
@property (nonatomic) NSInteger videoCount;
@property (nonatomic) NSInteger callsCount;
@property (nonatomic) long long totalSize;
@property (nonatomic) long long callsSize;
@end

@implementation RYGGalleryStorageStats
@end

@interface RYGGallerySettingsViewController ()
@property (nonatomic, strong) RYGGalleryStorageStats *stats;
@end

@implementation RYGGallerySettingsViewController

- (instancetype)init {
	if ((self = [super initWithTitle:RYGLocalized(@"Gallery Settings")])) {
		_stats = [RYGGalleryStorageStats new];
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
	NSManagedObjectContext *ctx = [RYGGalleryCoreDataStack shared].viewContext;
	NSFetchRequest *req = [[NSFetchRequest alloc] initWithEntityName:@"RYGGalleryFile"];
	req.resultType = NSDictionaryResultType;
	req.propertiesToFetch = @[@"mediaType", @"fileSize", @"source"];
	req.includesPendingChanges = YES;

	RYGGalleryStorageStats *s = [RYGGalleryStorageStats new];

	for (NSDictionary *row in [ctx executeFetchRequest:req error:nil] ?: @[]) {
		NSInteger type = [row[@"mediaType"] integerValue];
		long long sz = [row[@"fileSize"] longLongValue];
		s.totalFiles++;
		s.totalSize += sz;
		type == RYGGalleryMediaTypeVideo ? s.videoCount++ : s.imageCount++;
		if ([row[@"source"] integerValue] == RYGGallerySourceCalls) { s.callsCount++; s.callsSize += sz; }
	}

	self.stats = s;
}

- (NSString *)sizeText {
	return [NSByteCountFormatter stringFromByteCount:self.stats.totalSize countStyle:NSByteCountFormatterCountStyleFile];
}

- (NSString *)groupModeLabel {
	NSString *v = [RYGUtils getStringPref:kGroupModeKey];
	if ([v isEqualToString:kGroupModeSections]) return RYGLocalized(@"Sections");
	if ([v isEqualToString:kGroupModeFolders]) return RYGLocalized(@"Folders");
	return RYGLocalized(@"Off");
}

- (NSString *)gridColumnsLabel {
	NSInteger cols = (NSInteger)[RYGUtils getDoublePref:kGridColumnsKey];
	if (cols < 2 || cols > 5) cols = 3;
	return [NSString stringWithFormat:RYGLocalized(@"%ld columns"), (long)cols];
}

#pragma mark - Sections

- (void)rebuildSections {
	__weak typeof(self) weak = self;

	RYGSetting *total = [RYGSetting staticCellWithTitle:RYGLocalized(@"Total files") subtitle:@"" icon:nil];
	total.dynamicSubtitle = ^{ return [NSString stringWithFormat:@"%ld", (long)weak.stats.totalFiles]; };

	RYGSetting *images = [RYGSetting staticCellWithTitle:RYGLocalized(@"Images") subtitle:@"" icon:nil];
	images.dynamicSubtitle = ^{ return [NSString stringWithFormat:@"%ld", (long)weak.stats.imageCount]; };

	RYGSetting *videos = [RYGSetting staticCellWithTitle:RYGLocalized(@"Videos") subtitle:@"" icon:nil];
	videos.dynamicSubtitle = ^{ return [NSString stringWithFormat:@"%ld", (long)weak.stats.videoCount]; };

	RYGSetting *size = [RYGSetting staticCellWithTitle:RYGLocalized(@"Total size") subtitle:@"" icon:nil];
	size.dynamicSubtitle = ^{ return [weak sizeText]; };

	NSMutableArray *storageRows = [NSMutableArray arrayWithObjects:total, images, videos, size, nil];
	if ([RYGUtils getBoolPref:@"call_recordings_sync_gallery"]) {
		RYGSetting *calls = [RYGSetting staticCellWithTitle:RYGLocalized(@"Calls") subtitle:@"" icon:nil];
		calls.dynamicSubtitle = ^{
			return [NSString stringWithFormat:@"%ld · %@", (long)weak.stats.callsCount,
					[NSByteCountFormatter stringFromByteCount:weak.stats.callsSize countStyle:NSByteCountFormatterCountStyleFile]];
		};
		[storageRows addObject:calls];
	}

	RYGSetting *favorites = [RYGSetting switchCellWithTitle:RYGLocalized(@"Show favorites at top")
												   subtitle:nil
													  value:^BOOL{
		return [RYGUtils getBoolPref:kFavoritesAtTopKey];
	} action:^(BOOL on) {
		[RYGUtils setPref:@(on) forKey:kFavoritesAtTopKey];
		[NSNotificationCenter.defaultCenter postNotificationName:kPrefsChanged object:nil];
	}];

	RYGSetting *group = [RYGSetting buttonCellWithTitle:RYGLocalized(@"Group by user") subtitle:@"" icon:nil action:^{
		[weak presentGroupModeSheet];
	}];
	group.dynamicSubtitle = ^{ return [weak groupModeLabel]; };

	RYGSetting *gridColumns = [RYGSetting buttonCellWithTitle:RYGLocalized(@"Grid columns") subtitle:@"" icon:nil action:^{
		[weak presentGridColumnsSheet];
	}];
	gridColumns.dynamicSubtitle = ^{ return [weak gridColumnsLabel]; };
	gridColumns.whatsNewID = @"gallery_grid_columns";

	RYGSetting *delete = [RYGSetting buttonCellWithTitle:RYGLocalized(@"Delete files") subtitle:@"" icon:nil action:^{
		[weak openDeletePage];
	}];
	delete.titleColor = UIColor.systemRedColor;

	[self applySettingSections:@[
		[RYGSettingsViewController sectionWithHeader:RYGLocalized(@"Storage") footer:nil rows:storageRows],
		[RYGSettingsViewController sectionWithHeader:RYGLocalized(@"Browsing")
											 footer:RYGLocalized(@"When enabled, favorites are pinned above other files inside the current sort and folder context.")
											   rows:@[favorites, group, gridColumns]],
		[RYGSettingsViewController sectionWithHeader:RYGLocalized(@"Manage") footer:nil rows:@[delete]]
	]];
}

#pragma mark - Actions

- (void)presentGroupModeSheet {
	NSArray *options = @[
		@{@"title": RYGLocalized(@"Off"), @"value": kGroupModeOff, @"description": RYGLocalized(@"Flat list. No grouping.")},
		@{@"title": RYGLocalized(@"Sections"), @"value": kGroupModeSections, @"description": RYGLocalized(@"Each user gets a labelled section in the grid/list.")},
		@{@"title": RYGLocalized(@"Folders"), @"value": kGroupModeFolders, @"description": RYGLocalized(@"Each user appears as a folder next to your real folders.")}
	];

	[RYGOptionSheet presentFrom:self title:RYGLocalized(@"Group by user") defaultsKey:kGroupModeKey options:options onChange:^(__unused NSString *value) {
		[NSNotificationCenter.defaultCenter postNotificationName:kPrefsChanged object:nil];
		[self rebuildSections];
	}];
}

- (void)presentGridColumnsSheet {
	NSMutableArray *options = [NSMutableArray array];
	for (NSInteger cols = 2; cols <= 5; cols++) {
		[options addObject:@{
			@"title": [NSString stringWithFormat:RYGLocalized(@"%ld columns"), (long)cols],
			@"value": [NSString stringWithFormat:@"%ld", (long)cols],
		}];
	}

	[RYGOptionSheet presentFrom:self title:RYGLocalized(@"Grid columns") defaultsKey:kGridColumnsKey options:options onChange:^(__unused NSString *value) {
		[NSNotificationCenter.defaultCenter postNotificationName:kPrefsChanged object:nil];
		[self rebuildSections];
	}];
}

- (void)openDeletePage {
	RYGGalleryDeleteViewController *vc = [[RYGGalleryDeleteViewController alloc] initWithMode:RYGGalleryDeletePageModeRoot];

	__weak typeof(self) weak = self;
	vc.onDidDelete = ^{
		[weak reloadStatsAndSections];
		[NSNotificationCenter.defaultCenter postNotificationName:kPrefsChanged object:nil];
	};

	[self.navigationController pushViewController:vc animated:YES];
}

@end