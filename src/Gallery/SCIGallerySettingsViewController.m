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

	SCIBaseSettingsRow *total = [SCIBaseSettingsRow rowWithTitle:SCILocalized(@"Total files") subtitle:nil action:nil];
	total.dynamicSubtitle = ^{ return [NSString stringWithFormat:@"%ld", (long)weak.stats.totalFiles]; };

	SCIBaseSettingsRow *images = [SCIBaseSettingsRow rowWithTitle:SCILocalized(@"Images") subtitle:nil action:nil];
	images.dynamicSubtitle = ^{ return [NSString stringWithFormat:@"%ld", (long)weak.stats.imageCount]; };

	SCIBaseSettingsRow *videos = [SCIBaseSettingsRow rowWithTitle:SCILocalized(@"Videos") subtitle:nil action:nil];
	videos.dynamicSubtitle = ^{ return [NSString stringWithFormat:@"%ld", (long)weak.stats.videoCount]; };

	SCIBaseSettingsRow *size = [SCIBaseSettingsRow rowWithTitle:SCILocalized(@"Total size") subtitle:nil action:nil];
	size.dynamicSubtitle = ^{ return [weak sizeText]; };

	SCIBaseSettingsRow *favorites = [SCIBaseSettingsRow switchRowWithTitle:SCILocalized(@"Show favorites at top")
																   subtitle:nil
																	  value:^BOOL{
		return [SCIUtils getBoolPref:kFavoritesAtTopKey];
	} action:^(BOOL on, __unused UIViewController *vc) {
		[SCIUtils setPref:@(on) forKey:kFavoritesAtTopKey];
		[NSNotificationCenter.defaultCenter postNotificationName:kPrefsChanged object:nil];
	}];

	SCIBaseSettingsRow *group = [SCIBaseSettingsRow rowWithTitle:SCILocalized(@"Group by user")
														subtitle:nil
														  action:^(UIViewController *vc) {
		[(SCIGallerySettingsViewController *)vc presentGroupModeSheet];
	}];
	group.dynamicSubtitle = ^{ return [weak groupModeLabel]; };

	SCIBaseSettingsRow *delete = [SCIBaseSettingsRow destructiveRowWithTitle:SCILocalized(@"Delete files")
																	subtitle:nil
																	  action:^(UIViewController *vc) {
		[(SCIGallerySettingsViewController *)vc openDeletePage];
	}];
	delete.accessoryType = UITableViewCellAccessoryDisclosureIndicator;

	self.sections = @[
		[SCIBaseSettingsSection sectionWithHeader:SCILocalized(@"Storage") footer:nil rows:@[total, images, videos, size]],
		[SCIBaseSettingsSection sectionWithHeader:SCILocalized(@"Browsing")
										   footer:SCILocalized(@"When enabled, favorites are pinned above other files inside the current sort and folder context.")
											 rows:@[favorites, group]],
		[SCIBaseSettingsSection sectionWithHeader:SCILocalized(@"Manage") footer:nil rows:@[delete]]
	];

	[self reloadSettings];
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