#import "RYGDeletedMessagesStorageViewController.h"
#import "../../UI/RYGPopupChrome.h"
#import "RYGDeletedMessagesStorage.h"
#import "RYGDeletedMessagesModels.h"
#import "../../Utils.h"
#import "../../Localization/RYGLocalization.h"

@interface RYGDeletedMessagesStorageViewController () <UITableViewDataSource, UITableViewDelegate>
@property (nonatomic, strong) UITableView *tableView;
@property (nonatomic, copy) NSString *ownerPK;
@property (nonatomic) NSUInteger messageCount;
@property (nonatomic) unsigned long long mediaBytes;
@end

@implementation RYGDeletedMessagesStorageViewController

- (void)viewDidLoad {
	[super viewDidLoad];

	self.title = RYGLocalized(@"Storage");
	self.view.backgroundColor = [RYGPopupChrome backgroundColor];

	self.tableView = [[UITableView alloc] initWithFrame:self.view.bounds style:UITableViewStyleInsetGrouped];
	self.tableView.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
	self.tableView.dataSource = self;
	self.tableView.delegate = self;
	self.tableView.backgroundColor = self.view.backgroundColor;
	[self.view addSubview:self.tableView];

	[NSNotificationCenter.defaultCenter addObserver:self
										   selector:@selector(reload)
											   name:RYGDeletedMessagesDidChangeNotification
											 object:nil];

	[self reload];
}

- (void)dealloc {
	[NSNotificationCenter.defaultCenter removeObserver:self];
}

- (void)reload {
	self.ownerPK = [RYGUtils currentUserPK];
	self.messageCount = [RYGDeletedMessagesStorage allMessagesForOwnerPK:self.ownerPK].count;
	self.mediaBytes = [RYGDeletedMessagesStorage mediaSizeBytesForOwnerPK:self.ownerPK];
	[self.tableView reloadData];
}

#pragma mark - Helpers

+ (NSString *)formatBytes:(unsigned long long)b {
	return b ? [NSByteCountFormatter stringFromByteCount:(long long)b
											  countStyle:NSByteCountFormatterCountStyleFile]
			 : RYGLocalized(@"Empty");
}

- (UIColor *)primaryColor {
	return [RYGUtils RYGColor_Primary] ?: UIColor.systemBlueColor;
}

- (void)configureCell:(UITableViewCell *)cell
				title:(NSString *)title
			   detail:(NSString *)detail
			   symbol:(NSString *)symbol
				color:(UIColor *)color
		   selectable:(BOOL)selectable {
	cell.textLabel.text = title;
	cell.textLabel.textColor = selectable ? color ?: UIColor.labelColor : UIColor.labelColor;
	cell.detailTextLabel.text = detail;
	cell.imageView.image = [UIImage systemImageNamed:symbol];
	cell.imageView.tintColor = color ?: self.primaryColor;
	cell.accessoryType = UITableViewCellAccessoryNone;
	cell.selectionStyle = selectable ? UITableViewCellSelectionStyleDefault : UITableViewCellSelectionStyleNone;
}

- (void)confirmTitle:(NSString *)title message:(NSString *)message action:(dispatch_block_t)action {
	UIAlertController *a = [UIAlertController alertControllerWithTitle:[NSString stringWithFormat:@"%@?", title]
															  message:message
													   preferredStyle:UIAlertControllerStyleAlert];

	[a addAction:[UIAlertAction actionWithTitle:RYGLocalized(@"Cancel")
										  style:UIAlertActionStyleCancel
										handler:nil]];

	[a addAction:[UIAlertAction actionWithTitle:RYGLocalized(@"Clear")
										  style:UIAlertActionStyleDestructive
										handler:^(__unused UIAlertAction *_) {
		if (action) action();
	}]];

	[self presentViewController:a animated:YES completion:nil];
}

#pragma mark - Table

- (NSInteger)numberOfSectionsInTableView:(UITableView *)tv {
	return 2;
}

- (NSInteger)tableView:(UITableView *)tv numberOfRowsInSection:(NSInteger)section {
	return 2;
}

- (NSString *)tableView:(UITableView *)tv titleForHeaderInSection:(NSInteger)section {
	return section == 0 ? RYGLocalized(@"This account") : RYGLocalized(@"Manage");
}

- (NSString *)tableView:(UITableView *)tv titleForFooterInSection:(NSInteger)section {
	return section == 1
		? RYGLocalized(@"Clearing media keeps the records (text, sender, timestamp). Clearing the log removes everything for this account.")
		: nil;
}

- (UITableViewCell *)tableView:(UITableView *)tv cellForRowAtIndexPath:(NSIndexPath *)ip {
	static NSString *rid = @"ryg_dm_storage";
	UITableViewCell *cell = [tv dequeueReusableCellWithIdentifier:rid];
	if (!cell) cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleValue1 reuseIdentifier:rid];

	cell.detailTextLabel.text = nil;
	cell.imageView.image = nil;
	cell.userInteractionEnabled = YES;
	cell.textLabel.enabled = YES;
	cell.detailTextLabel.enabled = YES;

	if (ip.section == 0 && ip.row == 0) {
		[self configureCell:cell
					  title:RYGLocalized(@"Messages")
					 detail:[NSString stringWithFormat:@"%lu", (unsigned long)self.messageCount]
					 symbol:@"tray.full"
					  color:self.primaryColor
				 selectable:NO];
	} else if (ip.section == 0) {
		[self configureCell:cell
					  title:RYGLocalized(@"Media on disk")
					 detail:[self.class formatBytes:self.mediaBytes]
					 symbol:@"externaldrive"
					  color:UIColor.systemTealColor
				 selectable:NO];
	} else if (ip.row == 0) {
		BOOL enabled = self.mediaBytes > 0;
		[self configureCell:cell
					  title:RYGLocalized(@"Clear media files")
					 detail:[self.class formatBytes:self.mediaBytes]
					 symbol:@"externaldrive.badge.minus"
					  color:UIColor.systemOrangeColor
				 selectable:enabled];
		cell.userInteractionEnabled = enabled;
		cell.textLabel.enabled = enabled;
		cell.detailTextLabel.enabled = enabled;
	} else {
		BOOL enabled = self.messageCount > 0;
		[self configureCell:cell
					  title:RYGLocalized(@"Clear log for this account")
					 detail:nil
					 symbol:@"trash"
					  color:UIColor.systemRedColor
				 selectable:enabled];
		cell.userInteractionEnabled = enabled;
		cell.textLabel.enabled = enabled;
		cell.detailTextLabel.enabled = enabled;
	}

	return cell;
}

- (void)tableView:(UITableView *)tv didSelectRowAtIndexPath:(NSIndexPath *)ip {
	[tv deselectRowAtIndexPath:ip animated:YES];
	if (ip.section != 1) return;

	if (ip.row == 0) [self confirmClearMedia];
	else [self confirmClearAll];
}

#pragma mark - Actions

- (void)confirmClearMedia {
	if (!self.mediaBytes) return;

	__weak typeof(self) ws = self;
	[self confirmTitle:RYGLocalized(@"Clear media files")
			   message:RYGLocalized(@"Removes every saved photo, video and voice clip. Records keep their text and sender info.")
				action:^{
		[ws clearMediaFiles];
	}];
}

- (void)confirmClearAll {
	if (!self.messageCount) return;

	__weak typeof(self) ws = self;
	[self confirmTitle:RYGLocalized(@"Clear log for this account")
			   message:RYGLocalized(@"Removes every preserved deleted message and its captured media for the current account. This cannot be undone.")
				action:^{
		[RYGDeletedMessagesStorage resetForOwnerPK:ws.ownerPK];
	}];
}

- (void)clearMediaFiles {
	NSArray<RYGDeletedMessage *> *all = [RYGDeletedMessagesStorage allMessagesForOwnerPK:self.ownerPK];
	if (!all.count) return;

	BOOL changed = NO;

	for (RYGDeletedMessage *m in all) {
		for (NSString *rel in @[m.mediaPath ?: @"", m.thumbnailPath ?: @""]) {
			NSString *abs = [RYGDeletedMessagesStorage absolutePathForRelativePath:rel ownerPK:self.ownerPK];
			if (abs.length) [NSFileManager.defaultManager removeItemAtPath:abs error:nil];
		}

		if (m.mediaPath.length || m.thumbnailPath.length) {
			m.mediaPath = nil;
			m.thumbnailPath = nil;
			changed = YES;
		}
	}

	if (!changed) return;

	[RYGDeletedMessagesStorage saveMessages:all forOwnerPK:self.ownerPK];
	[self reload];
}

@end