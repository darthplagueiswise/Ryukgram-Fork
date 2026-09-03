#import "RYGCallRecordingDetailViewController.h"
#import "RYGCallRecordingStorage.h"
#import "../DeletedMessages/RYGDeletedMessagesDate.h"
#import "../../UI/RYGPopupChrome.h"
#import "../../Utils.h"
#import <AVKit/AVKit.h>
#import <AVFoundation/AVFoundation.h>

static NSString *rygDurationString(double seconds) {
	if (seconds <= 0) return @"0:00";
	NSInteger s = (NSInteger)round(seconds);
	NSInteger h = s / 3600, m = (s % 3600) / 60, sec = s % 60;
	if (h > 0) return [NSString stringWithFormat:@"%ld:%02ld:%02ld", (long)h, (long)m, (long)sec];
	return [NSString stringWithFormat:@"%ld:%02ld", (long)m, (long)sec];
}

static NSString *rygSizeString(unsigned long long bytes) {
	return [NSByteCountFormatter stringFromByteCount:(long long)bytes countStyle:NSByteCountFormatterCountStyleFile];
}

@interface RYGCallRecordingDetailViewController () <UITableViewDataSource, UITableViewDelegate>
@property (nonatomic, strong) UITableView *tableView;
@property (nonatomic, strong) UISegmentedControl *typeControl;
@property (nonatomic, strong) NSArray<RYGCallRecording *> *allRecordings;
@property (nonatomic, strong) NSArray<RYGCallRecording *> *recordings;
@property (nonatomic, strong) RYGCallRecordingGroup *group;
@property (nonatomic, copy) NSString *ownerPK;
@property (nonatomic, assign) NSInteger typeFilter;
@property (nonatomic, assign) BOOL newestFirst;
@end

@implementation RYGCallRecordingDetailViewController

- (instancetype)initWithGroup:(RYGCallRecordingGroup *)group ownerPK:(NSString *)ownerPK {
	if ((self = [super init])) { _group = group; _ownerPK = [ownerPK copy]; _newestFirst = YES; }
	return self;
}

- (void)viewDidLoad {
	[super viewDidLoad];
	self.title = self.group.displayName;
	self.view.backgroundColor = [RYGPopupChrome backgroundColor];

	self.typeControl = [[UISegmentedControl alloc] initWithItems:@[
		RYGLocalized(@"All"), RYGLocalized(@"Video"), RYGLocalized(@"Audio")]];
	self.typeControl.selectedSegmentIndex = 0;
	[self.typeControl addTarget:self action:@selector(typeChanged:) forControlEvents:UIControlEventValueChanged];
	[self updateOverflow];

	self.tableView = [[UITableView alloc] initWithFrame:CGRectZero style:UITableViewStyleInsetGrouped];
	self.tableView.translatesAutoresizingMaskIntoConstraints = NO;
	self.tableView.dataSource = self;
	self.tableView.delegate = self;
	self.tableView.rowHeight = 64;
	self.tableView.backgroundColor = UIColor.clearColor;
	[self.view addSubview:self.tableView];
	[NSLayoutConstraint activateConstraints:@[
		[self.tableView.topAnchor constraintEqualToAnchor:self.view.topAnchor],
		[self.tableView.leadingAnchor constraintEqualToAnchor:self.view.leadingAnchor],
		[self.tableView.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor],
		[self.tableView.bottomAnchor constraintEqualToAnchor:self.view.bottomAnchor],
	]];

	[NSNotificationCenter.defaultCenter addObserver:self selector:@selector(reload)
											   name:RYGCallRecordingsDidChangeNotification object:nil];
	[self reload];
}

- (void)dealloc { [NSNotificationCenter.defaultCenter removeObserver:self]; }

- (void)reload {
	self.allRecordings = [RYGCallRecordingStorage recordingsForIdentifier:self.group.identifier ownerPK:self.ownerPK];
	if (self.allRecordings.count == 0) {
		[self.navigationController popViewControllerAnimated:YES];
		return;
	}
	[self applyFilter];
}

- (void)typeChanged:(UISegmentedControl *)c { self.typeFilter = c.selectedSegmentIndex; [self applyFilter]; }

- (void)updateOverflow {
	__weak typeof(self) weakSelf = self;
	UIAction *sort = [UIAction actionWithTitle:(self.newestFirst ? RYGLocalized(@"Oldest first") : RYGLocalized(@"Newest first"))
										 image:[UIImage systemImageNamed:@"arrow.up.arrow.down"] identifier:nil
									   handler:^(UIAction *a) { weakSelf.newestFirst = !weakSelf.newestFirst; [weakSelf applyFilter]; [weakSelf updateOverflow]; }];
	UIAction *exportAll = [UIAction actionWithTitle:RYGLocalized(@"Export all") image:[UIImage systemImageNamed:@"square.and.arrow.up.on.square"] identifier:nil
										   handler:^(UIAction *a) { [weakSelf exportAll]; }];
	UIAction *rename = [UIAction actionWithTitle:RYGLocalized(@"Rename") image:[UIImage systemImageNamed:@"pencil"] identifier:nil
										handler:^(UIAction *a) { [weakSelf renameGroup]; }];
	UIMenu *menu = [UIMenu menuWithTitle:@"" children:@[sort, exportAll, rename]];
	self.navigationItem.rightBarButtonItem = [[UIBarButtonItem alloc] initWithImage:[UIImage systemImageNamed:@"ellipsis.circle"] menu:menu];
}

- (void)renameGroup {
	UIAlertController *ac = [UIAlertController alertControllerWithTitle:RYGLocalized(@"Rename")
															   message:RYGLocalized(@"Set a custom name for this chat's recordings.")
														preferredStyle:UIAlertControllerStyleAlert];
	[ac addTextFieldWithConfigurationHandler:^(UITextField *tf) { tf.text = self.group.customName ?: self.group.displayName; tf.clearButtonMode = UITextFieldViewModeAlways; }];
	[ac addAction:[UIAlertAction actionWithTitle:RYGLocalized(@"Cancel") style:UIAlertActionStyleCancel handler:nil]];
	[ac addAction:[UIAlertAction actionWithTitle:RYGLocalized(@"Save") style:UIAlertActionStyleDefault handler:^(UIAlertAction *a) {
		NSString *name = ac.textFields.firstObject.text;
		[RYGCallRecordingStorage setCustomName:name forGroupIdentifier:self.group.identifier ownerPK:self.ownerPK];
		self.group.customName = name.length ? name : nil;
		self.title = self.group.displayName;
	}]];
	[self presentViewController:ac animated:YES completion:nil];
}

- (void)renameRecording:(RYGCallRecording *)r {
	UIAlertController *ac = [UIAlertController alertControllerWithTitle:RYGLocalized(@"Rename recording") message:nil preferredStyle:UIAlertControllerStyleAlert];
	[ac addTextFieldWithConfigurationHandler:^(UITextField *tf) { tf.text = r.customName; tf.clearButtonMode = UITextFieldViewModeAlways; tf.placeholder = RYGLocalized(@"Recording name"); }];
	[ac addAction:[UIAlertAction actionWithTitle:RYGLocalized(@"Cancel") style:UIAlertActionStyleCancel handler:nil]];
	[ac addAction:[UIAlertAction actionWithTitle:RYGLocalized(@"Save") style:UIAlertActionStyleDefault handler:^(UIAlertAction *a) {
		[RYGCallRecordingStorage setCustomName:ac.textFields.firstObject.text forRecordingId:r.recordingId ownerPK:self.ownerPK];
	}]];
	[self presentViewController:ac animated:YES completion:nil];
}

- (void)exportAll {
	NSMutableArray<NSURL *> *urls = [NSMutableArray array];
	for (RYGCallRecording *r in self.recordings) {
		NSString *p = [RYGCallRecordingStorage absolutePathForRelativePath:r.mediaPath ownerPK:self.ownerPK];
		if (p.length && [NSFileManager.defaultManager fileExistsAtPath:p]) [urls addObject:[NSURL fileURLWithPath:p]];
	}
	if (!urls.count) return;
	UIActivityViewController *av = [[UIActivityViewController alloc] initWithActivityItems:urls applicationActivities:nil];
	av.popoverPresentationController.barButtonItem = self.navigationItem.rightBarButtonItem;
	[self presentViewController:av animated:YES completion:nil];
}

- (void)applyFilter {
	NSArray<RYGCallRecording *> *r = self.allRecordings;
	if (self.typeFilter == 1) r = [r filteredArrayUsingPredicate:[NSPredicate predicateWithFormat:@"isVideo == YES"]];
	else if (self.typeFilter == 2) r = [r filteredArrayUsingPredicate:[NSPredicate predicateWithFormat:@"isVideo == NO"]];
	r = [r sortedArrayUsingComparator:^NSComparisonResult(RYGCallRecording *a, RYGCallRecording *b) {
		NSComparisonResult c = [(a.startedAt ?: NSDate.distantPast) compare:(b.startedAt ?: NSDate.distantPast)];
		return self.newestFirst ? (c == NSOrderedAscending ? NSOrderedDescending : (c == NSOrderedDescending ? NSOrderedAscending : NSOrderedSame)) : c;
	}];
	self.recordings = r;
	[self.tableView reloadData];
}

#pragma mark - Table

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section { return self.recordings.count; }

- (CGFloat)tableView:(UITableView *)tableView heightForHeaderInSection:(NSInteger)section { return 48; }

- (UIView *)tableView:(UITableView *)tableView viewForHeaderInSection:(NSInteger)section {
	UIView *container = [UIView new];
	self.typeControl.translatesAutoresizingMaskIntoConstraints = NO;
	[container addSubview:self.typeControl];
	[NSLayoutConstraint activateConstraints:@[
		[self.typeControl.leadingAnchor constraintEqualToAnchor:container.leadingAnchor constant:16],
		[self.typeControl.trailingAnchor constraintEqualToAnchor:container.trailingAnchor constant:-16],
		[self.typeControl.centerYAnchor constraintEqualToAnchor:container.centerYAnchor],
	]];
	return container;
}

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath {
	static NSString *rid = @"rec";
	UITableViewCell *cell = [tableView dequeueReusableCellWithIdentifier:rid];
	if (!cell) {
		cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleSubtitle reuseIdentifier:rid];
		cell.backgroundColor = UIColor.secondarySystemGroupedBackgroundColor;
	}
	RYGCallRecording *r = self.recordings[indexPath.row];
	NSString *icon = r.isVideo ? @"video.circle.fill" : @"waveform.circle.fill";
	cell.imageView.image = [UIImage systemImageNamed:icon];
	cell.imageView.tintColor = UIColor.systemBlueColor;
	cell.textLabel.text = r.customName.length ? r.customName : ([RYGDeletedMessagesDate stringForDate:r.startedAt] ?: RYGLocalized(@"Call"));
	cell.textLabel.font = [UIFont systemFontOfSize:16 weight:UIFontWeightMedium];
	cell.detailTextLabel.text = [NSString stringWithFormat:@"%@ · %@ · %@ · %@",
		r.isVideo ? RYGLocalized(@"Video") : RYGLocalized(@"Audio"),
		rygDurationString(r.durationSeconds), rygSizeString(r.fileSizeBytes),
		r.startedAutomatically ? RYGLocalized(@"Auto") : RYGLocalized(@"Manual")];
	cell.detailTextLabel.textColor = UIColor.secondaryLabelColor;
	cell.accessoryView = [[UIImageView alloc] initWithImage:[UIImage systemImageNamed:@"play.circle"]];
	cell.accessoryView.tintColor = UIColor.systemBlueColor;
	return cell;
}

- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath {
	[tableView deselectRowAtIndexPath:indexPath animated:YES];
	[self playRecording:self.recordings[indexPath.row]];
}

- (void)playRecording:(RYGCallRecording *)r {
	NSString *path = [RYGCallRecordingStorage absolutePathForRelativePath:r.mediaPath ownerPK:self.ownerPK];
	if (!path.length || ![NSFileManager.defaultManager fileExistsAtPath:path]) {
		RYGNotifyError(RYG_NOTIF_CALL_RECORDING, RYGLocalized(@"Can't play"), RYGLocalized(@"The recording file is missing."));
		return;
	}
	[[AVAudioSession sharedInstance] setCategory:AVAudioSessionCategoryPlayback error:nil];
	[[AVAudioSession sharedInstance] setActive:YES error:nil];

	AVPlayer *player = [AVPlayer playerWithURL:[NSURL fileURLWithPath:path]];
	AVPlayerViewController *pvc = [AVPlayerViewController new];
	pvc.player = player;
	[self presentViewController:pvc animated:YES completion:^{ [player play]; }];
}

- (void)shareRecording:(RYGCallRecording *)r {
	NSString *path = [RYGCallRecordingStorage absolutePathForRelativePath:r.mediaPath ownerPK:self.ownerPK];
	if (!path.length || ![NSFileManager.defaultManager fileExistsAtPath:path]) return;
	UIActivityViewController *av = [[UIActivityViewController alloc] initWithActivityItems:@[[NSURL fileURLWithPath:path]] applicationActivities:nil];
	av.popoverPresentationController.sourceView = self.view;
	av.popoverPresentationController.sourceRect = CGRectMake(CGRectGetMidX(self.view.bounds), CGRectGetMidY(self.view.bounds), 1, 1);
	[self presentViewController:av animated:YES completion:nil];
}

- (UISwipeActionsConfiguration *)tableView:(UITableView *)tableView trailingSwipeActionsConfigurationForRowAtIndexPath:(NSIndexPath *)indexPath {
	RYGCallRecording *r = self.recordings[indexPath.row];
	UIContextualAction *del = [UIContextualAction contextualActionWithStyle:UIContextualActionStyleDestructive
																	 title:RYGLocalized(@"Delete")
																   handler:^(UIContextualAction *a, UIView *v, void (^done)(BOOL)) {
		[RYGCallRecordingStorage deleteRecordingId:r.recordingId forOwnerPK:self.ownerPK];
		done(YES);
	}];
	del.image = [UIImage systemImageNamed:@"trash"];
	return [UISwipeActionsConfiguration configurationWithActions:@[del]];
}

- (UIContextMenuConfiguration *)tableView:(UITableView *)tableView contextMenuConfigurationForRowAtIndexPath:(NSIndexPath *)indexPath point:(CGPoint)point {
	RYGCallRecording *r = self.recordings[indexPath.row];
	__weak typeof(self) weakSelf = self;
	return [UIContextMenuConfiguration configurationWithIdentifier:nil previewProvider:nil actionProvider:^UIMenu *(NSArray *sug) {
		UIAction *play = [UIAction actionWithTitle:RYGLocalized(@"Play") image:[UIImage systemImageNamed:@"play.fill"] identifier:nil
										   handler:^(UIAction *a) { [weakSelf playRecording:r]; }];
		UIAction *share = [UIAction actionWithTitle:RYGLocalized(@"Share") image:[UIImage systemImageNamed:@"square.and.arrow.up"] identifier:nil
											handler:^(UIAction *a) { [weakSelf shareRecording:r]; }];
		UIAction *rename = [UIAction actionWithTitle:RYGLocalized(@"Rename") image:[UIImage systemImageNamed:@"pencil"] identifier:nil
											handler:^(UIAction *a) { [weakSelf renameRecording:r]; }];
		UIAction *del = [UIAction actionWithTitle:RYGLocalized(@"Delete") image:[UIImage systemImageNamed:@"trash"] identifier:nil
										  handler:^(UIAction *a) { [RYGCallRecordingStorage deleteRecordingId:r.recordingId forOwnerPK:weakSelf.ownerPK]; }];
		del.attributes = UIMenuElementAttributesDestructive;
		return [UIMenu menuWithTitle:@"" children:@[play, share, rename, del]];
	}];
}

@end
