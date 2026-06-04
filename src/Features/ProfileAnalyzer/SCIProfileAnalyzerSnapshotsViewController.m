#import "SCIProfileAnalyzerSnapshotsViewController.h"
#import "SCIProfileAnalyzerStorage.h"
#import "../../UI/SCIPopupChrome.h"
#import "../../Utils.h"
#import "../../Localization/SCILocalization.h"

// Bytes past which we paint the usage line red and nudge a cleanup.
static const unsigned long long kSCISnapWarnBytes = 50ULL * 1024 * 1024;

@interface SCIProfileAnalyzerSnapshotsViewController () <UITableViewDataSource, UITableViewDelegate>
@property (nonatomic, copy) NSString *userPK;
@property (nonatomic, strong) UITableView *tableView;
@property (nonatomic, copy) NSArray<SCIProfileAnalyzerSnapshotMeta *> *snapshots;
@property (nonatomic, copy, nullable) NSString *selection;
@property (nonatomic, assign) unsigned long long totalBytes;
@end

@implementation SCIProfileAnalyzerSnapshotsViewController

- (instancetype)initWithUserPK:(NSString *)userPK {
	if ((self = [super init])) { _userPK = [userPK copy] ?: @""; }
	return self;
}

- (void)viewDidLoad {
	[super viewDidLoad];
	self.title = SCILocalized(@"Snapshots");
	self.view.backgroundColor = [SCIPopupChrome backgroundColor];

	self.tableView = [[UITableView alloc] initWithFrame:self.view.bounds style:UITableViewStyleInsetGrouped];
	self.tableView.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
	self.tableView.dataSource = self;
	self.tableView.delegate = self;
	self.tableView.allowsMultipleSelectionDuringEditing = YES;
	self.tableView.backgroundColor = [SCIPopupChrome backgroundColor];
	[self.view addSubview:self.tableView];

	[self reloadFromStore];
	[self refreshBarButtons];
}

- (void)reloadFromStore {
	self.snapshots = [SCIProfileAnalyzerStorage snapshotHistoryForUserPK:self.userPK];
	self.selection = [SCIProfileAnalyzerStorage compareSelectionForUserPK:self.userPK];
	self.totalBytes = [SCIProfileAnalyzerStorage historyByteSizeForUserPK:self.userPK];
	[self.tableView reloadData];
}

#pragma mark - Nav bar / editing

- (void)refreshBarButtons {
	if (self.tableView.isEditing) {
		UIBarButtonItem *cancel = [[UIBarButtonItem alloc] initWithBarButtonSystemItem:UIBarButtonSystemItemCancel
																			   target:self action:@selector(exitEditing)];
		BOOL allSelected = self.tableView.indexPathsForSelectedRows.count == self.snapshots.count && self.snapshots.count > 0;
		UIBarButtonItem *selectAll = [[UIBarButtonItem alloc] initWithTitle:(allSelected ? SCILocalized(@"Deselect All") : SCILocalized(@"Select All"))
																	  style:UIBarButtonItemStylePlain target:self action:@selector(toggleSelectAll)];
		self.navigationItem.leftItemsSupplementBackButton = NO;
		self.navigationItem.leftBarButtonItems = @[cancel, selectAll];

		NSUInteger n = self.tableView.indexPathsForSelectedRows.count;
		UIBarButtonItem *del = [[UIBarButtonItem alloc] initWithTitle:(n ? [NSString stringWithFormat:SCILocalized(@"Delete (%lu)"), (unsigned long)n] : SCILocalized(@"Delete"))
																style:UIBarButtonItemStylePlain target:self action:@selector(deleteSelected)];
		del.tintColor = [UIColor systemRedColor];
		del.enabled = n > 0;
		self.navigationItem.rightBarButtonItem = del;
	} else {
		self.navigationItem.leftBarButtonItems = nil;
		UIBarButtonItem *select = [[UIBarButtonItem alloc] initWithTitle:SCILocalized(@"Select")
																   style:UIBarButtonItemStylePlain target:self action:@selector(enterEditing)];
		select.enabled = self.snapshots.count > 0;
		self.navigationItem.rightBarButtonItem = select;
	}
}

- (void)enterEditing {
	[self.tableView setEditing:YES animated:YES];
	[self refreshBarButtons];
}

- (void)exitEditing {
	[self.tableView setEditing:NO animated:YES];
	[self refreshBarButtons];
}

- (void)toggleSelectAll {
	BOOL allSelected = self.tableView.indexPathsForSelectedRows.count == self.snapshots.count && self.snapshots.count > 0;
	for (NSInteger i = 0; i < (NSInteger)self.snapshots.count; i++) {
		NSIndexPath *ip = [NSIndexPath indexPathForRow:i + 1 inSection:1];   // row 0 = "Previous scan"
		if (allSelected) [self.tableView deselectRowAtIndexPath:ip animated:NO];
		else [self.tableView selectRowAtIndexPath:ip animated:NO scrollPosition:UITableViewScrollPositionNone];
	}
	[self refreshBarButtons];
}

- (void)deleteSelected {
	NSArray<NSIndexPath *> *sel = self.tableView.indexPathsForSelectedRows;
	if (!sel.count) return;
	NSMutableArray<NSString *> *ids = [NSMutableArray array];
	for (NSIndexPath *ip in sel) {
		NSInteger idx = ip.row - 1;
		if (idx >= 0 && idx < (NSInteger)self.snapshots.count) [ids addObject:self.snapshots[idx].snapshotID];
	}
	if (!ids.count) return;

	NSString *msg = ids.count == 1
		? SCILocalized(@"Delete this snapshot? This can't be undone.")
		: [NSString stringWithFormat:SCILocalized(@"Delete %lu snapshots? This can't be undone."), (unsigned long)ids.count];
	UIAlertController *a = [UIAlertController alertControllerWithTitle:SCILocalized(@"Delete snapshots") message:msg preferredStyle:UIAlertControllerStyleAlert];
	[a addAction:[UIAlertAction actionWithTitle:SCILocalized(@"Cancel") style:UIAlertActionStyleCancel handler:nil]];
	[a addAction:[UIAlertAction actionWithTitle:SCILocalized(@"Delete") style:UIAlertActionStyleDestructive handler:^(UIAlertAction *_) {
		[SCIProfileAnalyzerStorage deleteHistorySnapshotIDs:ids forUserPK:self.userPK];
		[self exitEditing];
		[self reloadFromStore];
		[self refreshBarButtons];
	}]];
	[self presentViewController:a animated:YES completion:nil];
}

#pragma mark - Table

- (NSInteger)numberOfSectionsInTableView:(UITableView *)tv { return 2; }

- (NSInteger)tableView:(UITableView *)tv numberOfRowsInSection:(NSInteger)section {
	if (section == 0) return 2;                       // record toggle + capacity
	return 1 + (NSInteger)self.snapshots.count;       // "Previous scan" + archive
}

- (NSString *)tableView:(UITableView *)tv titleForHeaderInSection:(NSInteger)section {
	return section == 0 ? SCILocalized(@"Recording") : SCILocalized(@"Compare next scan against");
}

- (NSString *)tableView:(UITableView *)tv titleForFooterInSection:(NSInteger)section {
	if (section == 0) {
		NSString *usage = [NSByteCountFormatter stringFromByteCount:(long long)self.totalBytes countStyle:NSByteCountFormatterCountStyleFile];
		NSString *base = SCILocalized(@"Each scan saves a full copy of your followers and following so you can compare against it later. Everything stays on this device.");
		NSString *stat = [NSString stringWithFormat:SCILocalized(@"Using %@ across %lu snapshots."), usage, (unsigned long)self.snapshots.count];
		NSString *warn = self.totalBytes >= kSCISnapWarnBytes ? [@"\n\n" stringByAppendingString:SCILocalized(@"⚠️ This is getting large — lower the limit or delete older snapshots to free space.")] : @"";
		return [NSString stringWithFormat:@"%@\n\n%@%@", base, stat, warn];
	}
	return SCILocalized(@"“Previous scan” always measures against your last run. Pick a saved snapshot to compare against a fixed point in time instead.");
}

- (UITableViewCell *)tableView:(UITableView *)tv cellForRowAtIndexPath:(NSIndexPath *)ip {
	if (ip.section == 0) return [self recordingCellForRow:ip.row tableView:tv];
	return [self compareCellForRow:ip.row tableView:tv];
}

- (UITableViewCell *)recordingCellForRow:(NSInteger)row tableView:(UITableView *)tv {
	NSString *rid = row == 0 ? @"rec" : @"cap";
	UITableViewCell *cell = [tv dequeueReusableCellWithIdentifier:rid];
	if (!cell) cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleSubtitle reuseIdentifier:rid];
	cell.detailTextLabel.numberOfLines = 0;
	cell.detailTextLabel.textColor = [UIColor secondaryLabelColor];
	cell.accessoryView = nil;
	cell.accessoryType = UITableViewCellAccessoryNone;

	if (row == 0) {
		cell.textLabel.text = SCILocalized(@"Record snapshots");
		cell.detailTextLabel.text = SCILocalized(@"Save a dated entry on every scan");
		cell.imageView.image = [UIImage systemImageNamed:@"camera.aperture"];
		cell.imageView.tintColor = [UIColor systemIndigoColor];
		cell.selectionStyle = UITableViewCellSelectionStyleNone;
		UISwitch *sw = [UISwitch new];
		sw.onTintColor = [SCIUtils SCIColor_Primary];
		sw.on = [SCIUtils getBoolPref:@"profile_analyzer_record_snapshots"];
		[sw addTarget:self action:@selector(recordToggled:) forControlEvents:UIControlEventValueChanged];
		cell.accessoryView = sw;
	} else {
		NSInteger cap = (NSInteger)[SCIUtils getDoublePref:@"profile_analyzer_snapshot_cap"];
		cell.textLabel.text = SCILocalized(@"Keep newest");
		cell.detailTextLabel.text = SCILocalized(@"Older snapshots beyond the limit are removed automatically");
		cell.imageView.image = [UIImage systemImageNamed:@"externaldrive.badge.timemachine"];
		cell.imageView.tintColor = [UIColor systemTealColor];
		cell.selectionStyle = UITableViewCellSelectionStyleDefault;
		UILabel *val = [UILabel new];
		val.textColor = [UIColor secondaryLabelColor];
		val.font = [UIFont systemFontOfSize:16];
		val.text = cap > 0 ? [NSString stringWithFormat:@"%ld", (long)cap] : SCILocalized(@"Unlimited");
		[val sizeToFit];
		cell.accessoryView = val;
	}
	return cell;
}

- (UITableViewCell *)compareCellForRow:(NSInteger)row tableView:(UITableView *)tv {
	static NSString *rid = @"cmp";
	UITableViewCell *cell = [tv dequeueReusableCellWithIdentifier:rid];
	if (!cell) cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleSubtitle reuseIdentifier:rid];
	cell.detailTextLabel.textColor = [UIColor secondaryLabelColor];
	cell.imageView.image = nil;

	BOOL isPrevious = (row == 0);
	BOOL selected;
	if (isPrevious) {
		cell.textLabel.text = SCILocalized(@"Previous scan");
		cell.detailTextLabel.text = SCILocalized(@"Rolling — always your last run");
		// nil selection (legacy / never chosen) defaults to the rolling diff.
		selected = !self.selection.length || [self.selection isEqualToString:SCIProfileAnalyzerCompareSelectionPrevious];
	} else {
		SCIProfileAnalyzerSnapshotMeta *m = self.snapshots[row - 1];
		cell.textLabel.text = [self dateLabelForMeta:m];
		cell.detailTextLabel.text = [NSString stringWithFormat:SCILocalized(@"%@ followers · %@ following"),
									 [SCIUtils shortCount:m.followerCount], [SCIUtils shortCount:m.followingCount]];
		selected = [self.selection isEqualToString:m.snapshotID];
	}
	cell.accessoryType = (selected && !tv.isEditing) ? UITableViewCellAccessoryCheckmark : UITableViewCellAccessoryNone;
	cell.selectionStyle = UITableViewCellSelectionStyleDefault;
	return cell;
}

- (NSString *)dateLabelForMeta:(SCIProfileAnalyzerSnapshotMeta *)m {
	static NSDateFormatter *fmt;
	static dispatch_once_t once;
	dispatch_once(&once, ^{
		fmt = [NSDateFormatter new];
		fmt.dateStyle = NSDateFormatterMediumStyle;
		fmt.timeStyle = NSDateFormatterShortStyle;
	});
	return m.scanDate ? [fmt stringFromDate:m.scanDate] : SCILocalized(@"Snapshot");
}

#pragma mark - Selection

- (BOOL)tableView:(UITableView *)tv canEditRowAtIndexPath:(NSIndexPath *)ip {
	return ip.section == 1 && ip.row >= 1;
}

- (UISwipeActionsConfiguration *)tableView:(UITableView *)tv trailingSwipeActionsConfigurationForRowAtIndexPath:(NSIndexPath *)ip {
	if (ip.section != 1 || ip.row < 1) return nil;
	NSString *sid = self.snapshots[ip.row - 1].snapshotID;
	UIContextualAction *del = [UIContextualAction contextualActionWithStyle:UIContextualActionStyleDestructive
																	  title:SCILocalized(@"Delete")
																	handler:^(UIContextualAction *a, UIView *v, void (^done)(BOOL)) {
		[SCIProfileAnalyzerStorage deleteHistorySnapshotIDs:@[sid] forUserPK:self.userPK];
		[self reloadFromStore];
		[self refreshBarButtons];
		done(YES);
	}];
	return [UISwipeActionsConfiguration configurationWithActions:@[del]];
}

- (BOOL)tableView:(UITableView *)tv shouldHighlightRowAtIndexPath:(NSIndexPath *)ip {
	if (tv.isEditing) return ip.section == 1 && ip.row >= 1;
	return YES;
}

- (void)tableView:(UITableView *)tv didSelectRowAtIndexPath:(NSIndexPath *)ip {
	if (tv.isEditing) {
		if (ip.section != 1 || ip.row < 1) { [tv deselectRowAtIndexPath:ip animated:NO]; return; }
		[self refreshBarButtons];
		return;
	}
	[tv deselectRowAtIndexPath:ip animated:YES];

	if (ip.section == 0) {
		if (ip.row == 1) [self promptCapacity];
		return;
	}
	NSString *newSel = (ip.row == 0)
		? SCIProfileAnalyzerCompareSelectionPrevious
		: self.snapshots[ip.row - 1].snapshotID;
	if ([newSel isEqualToString:self.selection]) return;
	[SCIProfileAnalyzerStorage setCompareSelection:newSel forUserPK:self.userPK];
	self.selection = newSel;
	[tv reloadSections:[NSIndexSet indexSetWithIndex:1] withRowAnimation:UITableViewRowAnimationNone];
}

- (void)tableView:(UITableView *)tv didDeselectRowAtIndexPath:(NSIndexPath *)ip {
	if (tv.isEditing) [self refreshBarButtons];
}

#pragma mark - Actions

- (void)recordToggled:(UISwitch *)sw {
	[[NSUserDefaults standardUserDefaults] setBool:sw.isOn forKey:@"profile_analyzer_record_snapshots"];
}

- (void)promptCapacity {
	NSArray<NSNumber *> *opts = @[@10, @20, @50, @100, @0];
	NSInteger cap = (NSInteger)[SCIUtils getDoublePref:@"profile_analyzer_snapshot_cap"];
	UIAlertController *a = [UIAlertController alertControllerWithTitle:SCILocalized(@"Keep newest snapshots")
															  message:SCILocalized(@"Older snapshots beyond this limit are deleted on the next scan.")
													   preferredStyle:UIAlertControllerStyleActionSheet];
	for (NSNumber *n in opts) {
		NSInteger v = n.integerValue;
		NSString *title = v > 0 ? [NSString stringWithFormat:@"%ld", (long)v] : SCILocalized(@"Unlimited");
		if (v == cap) title = [@"✓ " stringByAppendingString:title];
		[a addAction:[UIAlertAction actionWithTitle:title style:UIAlertActionStyleDefault handler:^(UIAlertAction *_) {
			[[NSUserDefaults standardUserDefaults] setDouble:(double)v forKey:@"profile_analyzer_snapshot_cap"];
			[self.tableView reloadRowsAtIndexPaths:@[[NSIndexPath indexPathForRow:1 inSection:0]] withRowAnimation:UITableViewRowAnimationNone];
		}]];
	}
	[a addAction:[UIAlertAction actionWithTitle:SCILocalized(@"Cancel") style:UIAlertActionStyleCancel handler:nil]];
	if (a.popoverPresentationController) {
		UITableViewCell *cell = [self.tableView cellForRowAtIndexPath:[NSIndexPath indexPathForRow:1 inSection:0]];
		a.popoverPresentationController.sourceView = cell ?: self.view;
		a.popoverPresentationController.sourceRect = (cell ?: self.view).bounds;
	}
	[self presentViewController:a animated:YES completion:nil];
}

@end
