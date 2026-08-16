#import "RYGGalleryDeleteViewController.h"
#import "RYGGalleryCoreDataStack.h"
#import "RYGGalleryFile.h"
#import "RYGAssetUtils.h"
#import "../Utils.h"
#import "RYGGalleryShim.h"

typedef NS_ENUM(NSInteger, RYGGalleryDeleteSection) {
	RYGGalleryDeleteSectionGlobal = 0,
	RYGGalleryDeleteSectionType,
	RYGGalleryDeleteSectionSource,
	RYGGalleryDeleteSectionUser,
	RYGGalleryDeleteSectionCount
};

@interface RYGGalleryDeleteAction : NSObject
@property (nonatomic, copy) NSString *title;
@property (nonatomic, copy) NSString *iconName;
@property (nonatomic, strong, nullable) NSPredicate *predicate;
@property (nonatomic, copy, nullable) NSString *successTitle;
@property (nonatomic, assign) BOOL navigatesToUsers;
@end

@implementation RYGGalleryDeleteAction
@end

@interface RYGGalleryDeleteUserItem : NSObject
@property (nonatomic, copy) NSString *displayName;
@property (nonatomic, copy, nullable) NSString *username;
@property (nonatomic, assign) NSInteger count;
@end

@implementation RYGGalleryDeleteUserItem
@end

@interface RYGGalleryDeleteViewController ()
@property (nonatomic, assign) RYGGalleryDeletePageMode mode;
@property (nonatomic, strong) NSArray<NSArray<RYGGalleryDeleteAction *> *> *sections;
@property (nonatomic, strong) NSArray<RYGGalleryDeleteUserItem *> *users;
@property (nonatomic, strong) NSDictionary<NSString *, NSNumber *> *countCache;
@end

@implementation RYGGalleryDeleteViewController

- (instancetype)initWithMode:(RYGGalleryDeletePageMode)mode {
	if ((self = [super initWithStyle:UITableViewStyleInsetGrouped])) {
		_mode = mode;
		_countCache = @{};
		_sections = @[];
		_users = @[];
	}
	return self;
}

- (void)viewDidLoad {
	[super viewDidLoad];
	self.title = self.mode == RYGGalleryDeletePageModeRoot
		? RYGLocalized(@"Delete files")
		: RYGLocalized(@"Delete by user");
	self.view.backgroundColor = [UIColor systemGroupedBackgroundColor];
	self.tableView.backgroundColor = [UIColor systemGroupedBackgroundColor];
	[self reloadDataModel];
}

- (void)viewWillAppear:(BOOL)animated {
	[super viewWillAppear:animated];
	[self reloadDataModel];
	[self.tableView reloadData];
}

- (RYGGalleryDeleteAction *)actionWithTitle:(NSString *)title
								 iconName:(NSString *)iconName
								predicate:(nullable NSPredicate *)predicate
							 successTitle:(nullable NSString *)successTitle {
	RYGGalleryDeleteAction *action = [RYGGalleryDeleteAction new];
	action.title = title;
	action.iconName = iconName;
	action.predicate = predicate;
	action.successTitle = successTitle;
	return action;
}

- (void)reloadDataModel {
	if (self.mode == RYGGalleryDeletePageModeUsers) {
		[self reloadUsers];
		return;
	}

	self.sections = @[
		@[[self actionWithTitle:RYGLocalized(@"Delete all files") iconName:@"trash" predicate:nil successTitle:RYGLocalized(@"All files deleted")]],
		@[
			[self actionWithTitle:RYGLocalized(@"Delete all images") iconName:@"photo" predicate:[NSPredicate predicateWithFormat:@"mediaType == %d", RYGGalleryMediaTypeImage] successTitle:RYGLocalized(@"Images deleted")],
			[self actionWithTitle:RYGLocalized(@"Delete all videos") iconName:@"video" predicate:[NSPredicate predicateWithFormat:@"mediaType == %d", RYGGalleryMediaTypeVideo] successTitle:RYGLocalized(@"Videos deleted")]
		],
		@[
			[self actionWithTitle:RYGLocalized(@"Delete feed posts") iconName:@"feed" predicate:[NSPredicate predicateWithFormat:@"source == %d", RYGGallerySourceFeed] successTitle:RYGLocalized(@"Feed posts deleted")],
			[self actionWithTitle:RYGLocalized(@"Delete stories") iconName:@"story" predicate:[NSPredicate predicateWithFormat:@"source == %d", RYGGallerySourceStories] successTitle:RYGLocalized(@"Stories deleted")],
			[self actionWithTitle:RYGLocalized(@"Delete reels") iconName:@"reels" predicate:[NSPredicate predicateWithFormat:@"source == %d", RYGGallerySourceReels] successTitle:RYGLocalized(@"Reels deleted")],
			[self actionWithTitle:RYGLocalized(@"Delete thumbnails") iconName:@"photo_gallery" predicate:[NSPredicate predicateWithFormat:@"source == %d", RYGGallerySourceThumbnail] successTitle:RYGLocalized(@"Thumbnails deleted")],
			[self actionWithTitle:RYGLocalized(@"Delete DM media") iconName:@"messages" predicate:[NSPredicate predicateWithFormat:@"source == %d", RYGGallerySourceDMs] successTitle:RYGLocalized(@"DM media deleted")],
			[self actionWithTitle:RYGLocalized(@"Delete profile pictures") iconName:@"profile" predicate:[NSPredicate predicateWithFormat:@"source == %d", RYGGallerySourceProfile] successTitle:RYGLocalized(@"Profile pictures deleted")]
		],
		@[]
	];

	RYGGalleryDeleteAction *usersAction = [self actionWithTitle:RYGLocalized(@"Delete by user") iconName:@"users" predicate:nil successTitle:nil];
	usersAction.navigatesToUsers = YES;
	self.sections = @[
		self.sections[0],
		self.sections[1],
		self.sections[2],
		@[usersAction]
	];

	[self rebuildCountCache];
}

- (void)rebuildCountCache {
	NSManagedObjectContext *ctx = [RYGGalleryCoreDataStack shared].viewContext;
	NSMutableDictionary<NSString *, NSNumber *> *counts = [NSMutableDictionary dictionary];
	for (NSArray<RYGGalleryDeleteAction *> *section in self.sections) {
		for (RYGGalleryDeleteAction *action in section) {
			if (action.navigatesToUsers) {
				continue;
			}
			NSFetchRequest *req = [[NSFetchRequest alloc] initWithEntityName:@"RYGGalleryFile"];
			req.predicate = action.predicate;
			NSInteger count = [ctx countForFetchRequest:req error:nil];
			counts[action.title] = @(MAX(count, 0));
		}
	}

	NSFetchRequest *distinctReq = [[NSFetchRequest alloc] initWithEntityName:@"RYGGalleryFile"];
	distinctReq.resultType = NSDictionaryResultType;
	distinctReq.propertiesToFetch = @[@"sourceUsername"];
	distinctReq.returnsDistinctResults = YES;
	NSArray<NSDictionary *> *rows = [ctx executeFetchRequest:distinctReq error:nil] ?: @[];
	counts[RYGLocalized(@"Delete by user")] = @(rows.count);
	self.countCache = counts;
}

- (void)reloadUsers {
	NSManagedObjectContext *ctx = [RYGGalleryCoreDataStack shared].viewContext;
	NSFetchRequest *req = [[NSFetchRequest alloc] initWithEntityName:@"RYGGalleryFile"];
	NSArray<RYGGalleryFile *> *files = [ctx executeFetchRequest:req error:nil] ?: @[];

	NSMutableDictionary<NSString *, RYGGalleryDeleteUserItem *> *items = [NSMutableDictionary dictionary];
	for (RYGGalleryFile *file in files) {
		NSString *username = [file.sourceUsername stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
		NSString *key = username.length > 0 ? username : @"__unknown__";
		RYGGalleryDeleteUserItem *item = items[key];
		if (!item) {
			item = [RYGGalleryDeleteUserItem new];
			item.username = username.length > 0 ? username : nil;
			item.displayName = username.length > 0 ? username : RYGLocalized(@"Unknown user");
			items[key] = item;
		}
		item.count += 1;
	}

	self.users = [[items allValues] sortedArrayUsingComparator:^NSComparisonResult(RYGGalleryDeleteUserItem *lhs, RYGGalleryDeleteUserItem *rhs) {
		return [lhs.displayName localizedCaseInsensitiveCompare:rhs.displayName];
	}];
}

- (NSString *)tableView:(UITableView *)tableView titleForHeaderInSection:(NSInteger)section {
	if (self.mode == RYGGalleryDeletePageModeUsers) {
		return nil;
	}
	switch (section) {
		case RYGGalleryDeleteSectionGlobal: return nil;
		case RYGGalleryDeleteSectionType:   return RYGLocalized(@"By type");
		case RYGGalleryDeleteSectionSource: return RYGLocalized(@"By source");
		case RYGGalleryDeleteSectionUser:   return RYGLocalized(@"By user");
	}
	return nil;
}

- (NSInteger)numberOfSectionsInTableView:(UITableView *)tableView {
	return self.mode == RYGGalleryDeletePageModeUsers ? 1 : self.sections.count;
}

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section {
	if (self.mode == RYGGalleryDeletePageModeUsers) {
		return self.users.count;
	}
	return self.sections[section].count;
}

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath {
	UITableViewCell *cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleValue1 reuseIdentifier:@"cell"];

	if (self.mode == RYGGalleryDeletePageModeUsers) {
		RYGGalleryDeleteUserItem *item = self.users[indexPath.row];
		cell.textLabel.text = item.displayName;
		cell.detailTextLabel.text = [NSString stringWithFormat:@"%ld", (long)item.count];
		cell.textLabel.textColor = [UIColor systemRedColor];
		cell.imageView.image = [RYGAssetUtils instagramIconNamed:@"profile" pointSize:18.0];
		cell.imageView.tintColor = [UIColor systemRedColor];
		return cell;
	}

	RYGGalleryDeleteAction *action = self.sections[indexPath.section][indexPath.row];
	cell.textLabel.text = action.title;
	NSNumber *count = self.countCache[action.title];
	if (count) {
		cell.detailTextLabel.text = count.integerValue > 0 ? [NSString stringWithFormat:@"%ld", (long)count.integerValue] : nil;
	}
	cell.imageView.image = [RYGAssetUtils instagramIconNamed:action.iconName pointSize:18.0];

	if (action.navigatesToUsers) {
		cell.textLabel.textColor = [UIColor labelColor];
		cell.imageView.tintColor = [UIColor secondaryLabelColor];
		cell.accessoryType = UITableViewCellAccessoryDisclosureIndicator;
	} else {
		cell.textLabel.textColor = [UIColor systemRedColor];
		cell.imageView.tintColor = [UIColor systemRedColor];
		cell.accessoryType = UITableViewCellAccessoryNone;
	}
	return cell;
}

- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath {
	[tableView deselectRowAtIndexPath:indexPath animated:YES];

	if (self.mode == RYGGalleryDeletePageModeUsers) {
		RYGGalleryDeleteUserItem *item = self.users[indexPath.row];
		NSPredicate *predicate = item.username.length > 0
			? [NSPredicate predicateWithFormat:@"sourceUsername == %@", item.username]
			: [NSPredicate predicateWithFormat:@"sourceUsername == nil OR sourceUsername == ''"];
		NSString *title = [NSString stringWithFormat:RYGLocalized(@"Delete %@?"), item.displayName];
		[self confirmDeleteWithTitle:title predicate:predicate successTitle:RYGLocalized(@"User files deleted")];
		return;
	}

	RYGGalleryDeleteAction *action = self.sections[indexPath.section][indexPath.row];
	if (action.navigatesToUsers) {
		RYGGalleryDeleteViewController *vc = [[RYGGalleryDeleteViewController alloc] initWithMode:RYGGalleryDeletePageModeUsers];
		vc.onDidDelete = self.onDidDelete;
		[self.navigationController pushViewController:vc animated:YES];
		return;
	}

	[self confirmDeleteWithTitle:action.title predicate:action.predicate successTitle:action.successTitle ?: RYGLocalized(@"Files deleted")];
}

- (void)confirmDeleteWithTitle:(NSString *)title predicate:(nullable NSPredicate *)predicate successTitle:(NSString *)successTitle {
	NSManagedObjectContext *ctx = [RYGGalleryCoreDataStack shared].viewContext;
	NSFetchRequest *req = [[NSFetchRequest alloc] initWithEntityName:@"RYGGalleryFile"];
	req.predicate = predicate;
	NSArray<RYGGalleryFile *> *files = [ctx executeFetchRequest:req error:nil] ?: @[];
	if (files.count == 0) {
		[RYGUtils showToastForActionIdentifier:kRYGFeedbackActionGalleryBulkDelete duration:2.0
								 title:RYGLocalized(@"No files to delete")
							  subtitle:nil
						  iconResource:@"info"
								  tone:RYGFeedbackPillToneInfo];
		return;
	}

	NSString *message = [NSString stringWithFormat:RYGLocalized(@"This will permanently remove %ld file(s)."), (long)files.count];
	UIAlertController *alert = [UIAlertController alertControllerWithTitle:title
																  message:message
														   preferredStyle:UIAlertControllerStyleAlert];
	[alert addAction:[UIAlertAction actionWithTitle:RYGLocalized(@"Cancel") style:UIAlertActionStyleCancel handler:nil]];
	[alert addAction:[UIAlertAction actionWithTitle:RYGLocalized(@"Delete")
											  style:UIAlertActionStyleDestructive
											handler:^(__unused UIAlertAction *action) {
		NSFileManager *fm = [NSFileManager defaultManager];
		for (RYGGalleryFile *file in files) {
			NSString *filePath = file.filePath;
			if ([fm fileExistsAtPath:filePath]) {
				[fm removeItemAtPath:filePath error:nil];
			}
			NSString *thumbPath = file.thumbnailPath;
			if ([fm fileExistsAtPath:thumbPath]) {
				[fm removeItemAtPath:thumbPath error:nil];
			}
			[ctx deleteObject:file];
		}
		[ctx save:nil];
		[self reloadDataModel];
		[self.tableView reloadData];
		if (self.onDidDelete) {
			self.onDidDelete();
		}
		[RYGUtils showToastForActionIdentifier:kRYGFeedbackActionGalleryBulkDelete duration:2.0
								 title:successTitle
							  subtitle:nil
						  iconResource:@"circle_check_filled"
								  tone:RYGFeedbackPillToneSuccess];
	}]];
	[self presentViewController:alert animated:YES completion:nil];
}

@end
