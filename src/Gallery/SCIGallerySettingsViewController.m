#import "SCIGallerySettingsViewController.h"
#import "SCIGalleryDeleteViewController.h"
#import "SCIGalleryFile.h"
#import "SCIGalleryCoreDataStack.h"
#import "../Utils.h"
#import "SCIGalleryShim.h"
#import "../UI/SCIPopupChrome.h"
#import <CoreData/CoreData.h>

static NSString * const kFavoritesAtTopKey = @"show_favorites_at_top";
static NSString * const kGalleryPrefsChangedNotification = @"SCIGalleryFavoritesSortPreferenceChanged";

typedef NS_ENUM(NSInteger, SCIGalleryStatsRow) {
	SCIGalleryStatsRowTotal = 0,
	SCIGalleryStatsRowImages,
	SCIGalleryStatsRowVideos,
	SCIGalleryStatsRowSize,
	SCIGalleryStatsRowCount
};

typedef NS_ENUM(NSInteger, SCIGallerySettingsSection) {
	SCIGallerySettingsSectionStats = 0,
	SCIGallerySettingsSectionBrowsing,
	SCIGallerySettingsSectionManage,
	SCIGallerySettingsSectionCount
};

@interface SCIGalleryStorageStats : NSObject
@property (nonatomic, assign) NSInteger totalFiles;
@property (nonatomic, assign) NSInteger imageCount;
@property (nonatomic, assign) NSInteger videoCount;
@property (nonatomic, assign) long long totalSize;
@end

@implementation SCIGalleryStorageStats
@end

@interface SCIGallerySettingsViewController ()
@property (nonatomic, strong) SCIGalleryStorageStats *stats;
@end

@implementation SCIGallerySettingsViewController

- (instancetype)init {
	return [super initWithStyle:UITableViewStyleInsetGrouped];
}

- (void)viewDidLoad {
	[super viewDidLoad];

	self.title = SCILocalized(@"Gallery Settings");
	self.view.backgroundColor = [SCIPopupChrome backgroundColor];
	self.tableView.backgroundColor = self.view.backgroundColor;
	self.tableView.contentInset = UIEdgeInsetsMake(-10.0, 0.0, 0.0, 0.0);

	[self reloadStats];
}

- (void)viewWillAppear:(BOOL)animated {
	[super viewWillAppear:animated];

	[self reloadStats];
	[self.tableView reloadData];
}

#pragma mark - Stats

- (void)reloadStats {
	NSManagedObjectContext *context = [SCIGalleryCoreDataStack shared].viewContext;
	NSFetchRequest *request = [[NSFetchRequest alloc] initWithEntityName:@"SCIGalleryFile"];
	request.resultType = NSDictionaryResultType;
	request.propertiesToFetch = @[@"mediaType", @"fileSize"];
	request.includesPendingChanges = YES;

	NSArray<NSDictionary *> *rows = [context executeFetchRequest:request error:nil] ?: @[];

	SCIGalleryStorageStats *stats = [SCIGalleryStorageStats new];

	for (NSDictionary *row in rows) {
		NSInteger mediaType = [row[@"mediaType"] integerValue];

		stats.totalFiles += 1;
		stats.totalSize += [row[@"fileSize"] longLongValue];

		if (mediaType == SCIGalleryMediaTypeVideo) {
			stats.videoCount += 1;
		} else {
			stats.imageCount += 1;
		}
	}

	self.stats = stats;
}

- (NSString *)formattedSize:(long long)bytes {
	return [NSByteCountFormatter stringFromByteCount:bytes countStyle:NSByteCountFormatterCountStyleFile];
}

- (NSString *)statsTitleForRow:(NSInteger)row {
	switch (row) {
		case SCIGalleryStatsRowTotal:	return SCILocalized(@"Total files");
		case SCIGalleryStatsRowImages:	return SCILocalized(@"Images");
		case SCIGalleryStatsRowVideos:	return SCILocalized(@"Videos");
		case SCIGalleryStatsRowSize:	return SCILocalized(@"Total size");
		default:						return @"";
	}
}

- (NSString *)statsValueForRow:(NSInteger)row {
	switch (row) {
		case SCIGalleryStatsRowTotal:
			return [NSString stringWithFormat:@"%ld", (long)self.stats.totalFiles];

		case SCIGalleryStatsRowImages:
			return [NSString stringWithFormat:@"%ld", (long)self.stats.imageCount];

		case SCIGalleryStatsRowVideos:
			return [NSString stringWithFormat:@"%ld", (long)self.stats.videoCount];

		case SCIGalleryStatsRowSize:
			return [self formattedSize:self.stats.totalSize];

		default:
			return @"";
	}
}

#pragma mark - Table

- (NSInteger)numberOfSectionsInTableView:(UITableView *)tableView {
	return SCIGallerySettingsSectionCount;
}

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section {
	switch (section) {
		case SCIGallerySettingsSectionStats:		return SCIGalleryStatsRowCount;
		case SCIGallerySettingsSectionBrowsing:	return 1;
		case SCIGallerySettingsSectionManage:	return 1;
		default:								return 0;
	}
}

- (NSString *)tableView:(UITableView *)tableView titleForHeaderInSection:(NSInteger)section {
	switch (section) {
		case SCIGallerySettingsSectionStats:		return SCILocalized(@"Storage");
		case SCIGallerySettingsSectionBrowsing:	return SCILocalized(@"Browsing");
		case SCIGallerySettingsSectionManage:	return SCILocalized(@"Manage");
		default:								return nil;
	}
}

- (NSString *)tableView:(UITableView *)tableView titleForFooterInSection:(NSInteger)section {
	if (section == SCIGallerySettingsSectionBrowsing) {
		return SCILocalized(@"When enabled, favorites are pinned above other files inside the current sort and folder context.");
	}

	return nil;
}

- (UITableViewCell *)baseCell {
	UITableViewCell *cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleDefault reuseIdentifier:nil];
	cell.accessoryView = nil;
	cell.accessoryType = UITableViewCellAccessoryNone;
	cell.selectionStyle = UITableViewCellSelectionStyleDefault;
	cell.contentView.alpha = 1.0;
	return cell;
}

- (UILabel *)valueLabelWithText:(NSString *)text {
	UILabel *label = UILabel.new;
	label.text = text ?: @"";
	label.font = [UIFont systemFontOfSize:16.0];
	label.textColor = UIColor.secondaryLabelColor;
	[label sizeToFit];
	return label;
}

- (UITableViewCell *)statsCellForRow:(NSInteger)row {
	UITableViewCell *cell = [self baseCell];
	UIListContentConfiguration *config = cell.defaultContentConfiguration;

	config.text = [self statsTitleForRow:row];
	config.textProperties.color = UIColor.labelColor;

	cell.contentConfiguration = config;
	cell.selectionStyle = UITableViewCellSelectionStyleNone;
	cell.accessoryView = [self valueLabelWithText:[self statsValueForRow:row]];

	return cell;
}

- (UITableViewCell *)favoritesCell {
	UITableViewCell *cell = [self baseCell];
	UIListContentConfiguration *config = cell.defaultContentConfiguration;

	config.text = SCILocalized(@"Show favorites at top");
	config.textProperties.color = UIColor.labelColor;

	UISwitch *toggle = UISwitch.new;
	toggle.on = [NSUserDefaults.standardUserDefaults boolForKey:kFavoritesAtTopKey];
	toggle.onTintColor = [SCIUtils SCIColor_Primary];
	[toggle addTarget:self action:@selector(favoritesAtTopSwitchChanged:) forControlEvents:UIControlEventValueChanged];

	cell.contentConfiguration = config;
	cell.accessoryView = toggle;
	cell.selectionStyle = UITableViewCellSelectionStyleNone;

	return cell;
}

- (UITableViewCell *)deleteCell {
	UITableViewCell *cell = [self baseCell];
	UIListContentConfiguration *config = cell.defaultContentConfiguration;

	config.text = SCILocalized(@"Delete files");
	config.textProperties.color = UIColor.systemRedColor;

	cell.contentConfiguration = config;
	cell.accessoryType = UITableViewCellAccessoryDisclosureIndicator;

	return cell;
}

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath {
	switch (indexPath.section) {
		case SCIGallerySettingsSectionStats:
			return [self statsCellForRow:indexPath.row];

		case SCIGallerySettingsSectionBrowsing:
			return [self favoritesCell];

		case SCIGallerySettingsSectionManage:
			return [self deleteCell];

		default:
			return [self baseCell];
	}
}

#pragma mark - Actions

- (void)favoritesAtTopSwitchChanged:(UISwitch *)sender {
	[NSUserDefaults.standardUserDefaults setBool:sender.isOn forKey:kFavoritesAtTopKey];
	[NSNotificationCenter.defaultCenter postNotificationName:kGalleryPrefsChangedNotification object:nil];
}

- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath {
	[tableView deselectRowAtIndexPath:indexPath animated:YES];

	if (indexPath.section != SCIGallerySettingsSectionManage) return;

	SCIGalleryDeleteViewController *vc = [[SCIGalleryDeleteViewController alloc] initWithMode:SCIGalleryDeletePageModeRoot];

	__weak typeof(self) weakSelf = self;
	vc.onDidDelete = ^{
		__strong typeof(weakSelf) self = weakSelf;
		if (!self) return;

		[self reloadStats];
		[self.tableView reloadData];
		[NSNotificationCenter.defaultCenter postNotificationName:kGalleryPrefsChangedNotification object:nil];
	};

	[self.navigationController pushViewController:vc animated:YES];
}

@end