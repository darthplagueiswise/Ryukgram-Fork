#import "RYGCallRecordingsViewController.h"
#import "../Feed/RYGHomeShortcutBadges.h"
#import "RYGCallRecordingDetailViewController.h"
#import "RYGCallRecordingStorage.h"
#import "RYGCallRecordingModels.h"
#import "RYGCallRecordingGallery.h"
#import "../DeletedMessages/RYGDeletedMessagesDate.h"
#import "../../Lock/RYGLockGate.h"
#import "../../Lock/RYGLockGroups.h"
#import "../../UI/RYGPopupChrome.h"
#import "../../RYGImageCache.h"
#import "../../Utils.h"

#pragma mark - Cell

@interface RYGCallGroupCell : UITableViewCell
@property (nonatomic, strong) UIImageView *avatarView;
@property (nonatomic, strong) UILabel *nameLabel;
@property (nonatomic, strong) UILabel *subtitleLabel;
@property (nonatomic, strong) UILabel *unreadBadge;
@property (nonatomic, strong) NSLayoutConstraint *unreadBadgeWidth;
@property (nonatomic, copy) NSString *avatarURLString;
- (void)applyGroup:(RYGCallRecordingGroup *)group;
@end

@implementation RYGCallGroupCell

- (instancetype)initWithStyle:(UITableViewCellStyle)style reuseIdentifier:(NSString *)reuseIdentifier {
	if ((self = [super initWithStyle:style reuseIdentifier:reuseIdentifier])) {
		self.accessoryType = UITableViewCellAccessoryDisclosureIndicator;
		self.backgroundColor = UIColor.secondarySystemGroupedBackgroundColor;

		_avatarView = [UIImageView new];
		_avatarView.translatesAutoresizingMaskIntoConstraints = NO;
		_avatarView.contentMode = UIViewContentModeScaleAspectFill;
		_avatarView.clipsToBounds = YES;
		_avatarView.layer.cornerRadius = 23;
		_avatarView.backgroundColor = UIColor.tertiarySystemFillColor;
		_avatarView.tintColor = UIColor.secondaryLabelColor;

		_nameLabel = [UILabel new];
		_nameLabel.translatesAutoresizingMaskIntoConstraints = NO;
		_nameLabel.font = [UIFont systemFontOfSize:16 weight:UIFontWeightSemibold];

		_subtitleLabel = [UILabel new];
		_subtitleLabel.translatesAutoresizingMaskIntoConstraints = NO;
		_subtitleLabel.font = [UIFont systemFontOfSize:13];
		_subtitleLabel.textColor = UIColor.secondaryLabelColor;

		_unreadBadge = [UILabel new];
		_unreadBadge.translatesAutoresizingMaskIntoConstraints = NO;
		_unreadBadge.font = [UIFont boldSystemFontOfSize:13];
		_unreadBadge.textColor = UIColor.whiteColor;
		_unreadBadge.textAlignment = NSTextAlignmentCenter;
		_unreadBadge.backgroundColor = UIColor.systemRedColor;
		_unreadBadge.layer.cornerRadius = 10;
		_unreadBadge.clipsToBounds = YES;
		_unreadBadge.hidden = YES;
		_unreadBadgeWidth = [_unreadBadge.widthAnchor constraintEqualToConstant:20];

		[self.contentView addSubview:_avatarView];
		[self.contentView addSubview:_nameLabel];
		[self.contentView addSubview:_subtitleLabel];
		[self.contentView addSubview:_unreadBadge];

		[NSLayoutConstraint activateConstraints:@[
			[_unreadBadge.trailingAnchor constraintEqualToAnchor:self.contentView.trailingAnchor constant:-12],
			[_unreadBadge.centerYAnchor constraintEqualToAnchor:self.contentView.centerYAnchor],
			[_unreadBadge.heightAnchor constraintEqualToConstant:20],
			_unreadBadgeWidth,
			[_avatarView.leadingAnchor constraintEqualToAnchor:self.contentView.leadingAnchor constant:16],
			[_avatarView.centerYAnchor constraintEqualToAnchor:self.contentView.centerYAnchor],
			[_avatarView.widthAnchor constraintEqualToConstant:46],
			[_avatarView.heightAnchor constraintEqualToConstant:46],

			[_nameLabel.leadingAnchor constraintEqualToAnchor:_avatarView.trailingAnchor constant:12],
			[_nameLabel.trailingAnchor constraintLessThanOrEqualToAnchor:_unreadBadge.leadingAnchor constant:-8],
			[_nameLabel.topAnchor constraintEqualToAnchor:_avatarView.topAnchor constant:2],

			[_subtitleLabel.leadingAnchor constraintEqualToAnchor:_nameLabel.leadingAnchor],
			[_subtitleLabel.trailingAnchor constraintLessThanOrEqualToAnchor:_unreadBadge.leadingAnchor constant:-8],
			[_subtitleLabel.topAnchor constraintEqualToAnchor:_nameLabel.bottomAnchor constant:3],
		]];
	}
	return self;
}

- (void)applyGroup:(RYGCallRecordingGroup *)group {
	self.nameLabel.text = group.displayName;
	NSUInteger unread = group.unreadCount;
	self.unreadBadge.hidden = unread == 0;
	if (unread > 0) {
		NSString *txt = unread > 99 ? @"99+" : [@(unread) stringValue];
		self.unreadBadge.text = txt;
		CGFloat w = ceil([txt sizeWithAttributes:@{ NSFontAttributeName: self.unreadBadge.font }].width);
		self.unreadBadgeWidth.constant = MAX(20.0, w + 14.0);
	} else {
		self.unreadBadgeWidth.constant = 0;
	}
	self.nameLabel.font = [UIFont systemFontOfSize:16 weight:(unread > 0 ? UIFontWeightBold : UIFontWeightSemibold)];

	NSString *count = group.count == 1 ? RYGLocalized(@"1 recording")
		: [NSString stringWithFormat:RYGLocalized(@"%lu recordings"), (unsigned long)group.count];
	NSString *size = [NSByteCountFormatter stringFromByteCount:(long long)group.totalBytes countStyle:NSByteCountFormatterCountStyleFile];
	NSString *when = [RYGDeletedMessagesDate stringForDate:group.lastRecordedAt];
	NSMutableArray *parts = [NSMutableArray arrayWithObject:count];
	if (size.length) [parts addObject:size];
	if (when.length) [parts addObject:when];
	self.subtitleLabel.text = [parts componentsJoinedByString:@" · "];

	UIImage *placeholder = [UIImage systemImageNamed:group.isGroup ? @"person.2.circle.fill" : @"person.circle.fill"];
	self.avatarView.image = placeholder;

	NSString *urlStr = group.avatarURL;
	self.avatarURLString = urlStr;
	if (urlStr.length) {
		NSURL *url = [NSURL URLWithString:urlStr];
		[RYGImageCache loadImageFromURL:url completion:^(UIImage *image) {
			if (image && [self.avatarURLString isEqualToString:urlStr]) self.avatarView.image = image;
		}];
	}
}

@end

#pragma mark - Empty view

@interface RYGCallEmptyView : UIView
- (void)applyTitle:(NSString *)title message:(NSString *)message;
@end

@implementation RYGCallEmptyView {
	UIImageView *_icon; UILabel *_title; UILabel *_message;
}
- (instancetype)initWithFrame:(CGRect)frame {
	if ((self = [super initWithFrame:frame])) {
		_icon = [[UIImageView alloc] initWithImage:[UIImage systemImageNamed:@"phone.badge.waveform"]];
		_icon.tintColor = UIColor.tertiaryLabelColor;
		_icon.contentMode = UIViewContentModeScaleAspectFit;
		_icon.translatesAutoresizingMaskIntoConstraints = NO;

		_title = [UILabel new];
		_title.font = [UIFont systemFontOfSize:18 weight:UIFontWeightSemibold];
		_title.textColor = UIColor.secondaryLabelColor;
		_title.textAlignment = NSTextAlignmentCenter;
		_title.translatesAutoresizingMaskIntoConstraints = NO;

		_message = [UILabel new];
		_message.font = [UIFont systemFontOfSize:14];
		_message.textColor = UIColor.tertiaryLabelColor;
		_message.textAlignment = NSTextAlignmentCenter;
		_message.numberOfLines = 0;
		_message.translatesAutoresizingMaskIntoConstraints = NO;

		[self addSubview:_icon]; [self addSubview:_title]; [self addSubview:_message];
		[NSLayoutConstraint activateConstraints:@[
			[_icon.centerXAnchor constraintEqualToAnchor:self.centerXAnchor],
			[_icon.centerYAnchor constraintEqualToAnchor:self.centerYAnchor constant:-60],
			[_icon.widthAnchor constraintEqualToConstant:64],
			[_icon.heightAnchor constraintEqualToConstant:64],
			[_title.topAnchor constraintEqualToAnchor:_icon.bottomAnchor constant:16],
			[_title.centerXAnchor constraintEqualToAnchor:self.centerXAnchor],
			[_title.leadingAnchor constraintEqualToAnchor:self.leadingAnchor constant:32],
			[_title.trailingAnchor constraintEqualToAnchor:self.trailingAnchor constant:-32],
			[_message.topAnchor constraintEqualToAnchor:_title.bottomAnchor constant:8],
			[_message.leadingAnchor constraintEqualToAnchor:_title.leadingAnchor],
			[_message.trailingAnchor constraintEqualToAnchor:_title.trailingAnchor],
		]];
	}
	return self;
}
- (void)applyTitle:(NSString *)title message:(NSString *)message { _title.text = title; _message.text = message; }
@end

#pragma mark - VC

@interface RYGCallRecordingsViewController () <UITableViewDataSource, UITableViewDelegate, UISearchResultsUpdating>
@property (nonatomic, strong) UITableView *tableView;
@property (nonatomic, strong) RYGCallEmptyView *emptyView;
@property (nonatomic, strong) NSArray<RYGCallRecordingGroup *> *allGroups;
@property (nonatomic, strong) NSArray<RYGCallRecordingGroup *> *groups;
@property (nonatomic, strong) UISearchController *searchController;
@property (nonatomic, copy) NSString *ownerPK;
@property (nonatomic, copy) NSString *sortMode;
@end

@implementation RYGCallRecordingsViewController

+ (void)presentFromViewController:(UIViewController *)presenter {
	[RYGLockGate presentLockedVC:[RYGCallRecordingsViewController new]
						forGroup:RYGLockGroupCallRecordings
							from:presenter];
}

- (void)viewDidLoad {
	[super viewDidLoad];
	[RYGHomeShortcutBadges clearActionID:@"call_recordings"];
	self.title = RYGLocalized(@"Call recordings");
	self.view.backgroundColor = [RYGPopupChrome backgroundColor];
	self.ownerPK = [RYGUtils currentUserPK] ?: @"anon";
	self.sortMode = @"recent";

	self.searchController = [[UISearchController alloc] initWithSearchResultsController:nil];
	self.searchController.searchResultsUpdater = self;
	self.searchController.obscuresBackgroundDuringPresentation = NO;
	self.searchController.searchBar.placeholder = RYGLocalized(@"Search calls");
	self.navigationItem.searchController = self.searchController;
	self.navigationItem.hidesSearchBarWhenScrolling = NO;
	self.definesPresentationContext = YES;

	self.tableView = [[UITableView alloc] initWithFrame:CGRectZero style:UITableViewStyleInsetGrouped];
	self.tableView.translatesAutoresizingMaskIntoConstraints = NO;
	self.tableView.dataSource = self;
	self.tableView.delegate = self;
	self.tableView.rowHeight = 72;
	self.tableView.backgroundColor = UIColor.clearColor;
	self.tableView.allowsMultipleSelectionDuringEditing = YES;
	[self.tableView registerClass:RYGCallGroupCell.class forCellReuseIdentifier:@"group"];
	[self.view addSubview:self.tableView];

	self.emptyView = [[RYGCallEmptyView alloc] initWithFrame:CGRectZero];
	self.emptyView.translatesAutoresizingMaskIntoConstraints = NO;
	[self.view addSubview:self.emptyView];

	[NSLayoutConstraint activateConstraints:@[
		[self.tableView.topAnchor constraintEqualToAnchor:self.view.topAnchor],
		[self.tableView.leadingAnchor constraintEqualToAnchor:self.view.leadingAnchor],
		[self.tableView.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor],
		[self.tableView.bottomAnchor constraintEqualToAnchor:self.view.bottomAnchor],
		[self.emptyView.centerXAnchor constraintEqualToAnchor:self.view.centerXAnchor],
		[self.emptyView.centerYAnchor constraintEqualToAnchor:self.view.centerYAnchor],
		[self.emptyView.widthAnchor constraintEqualToAnchor:self.view.widthAnchor],
		[self.emptyView.heightAnchor constraintEqualToAnchor:self.view.heightAnchor],
	]];

	[NSNotificationCenter.defaultCenter addObserver:self selector:@selector(reload)
											   name:RYGCallRecordingsDidChangeNotification object:nil];
	NSInteger retention = [RYGUtils getStringPref:@"call_recordings_retention"].integerValue;
	if (retention > 0) [RYGCallRecordingStorage pruneOlderThanDays:retention forOwnerPK:self.ownerPK];
	if ([RYGUtils getBoolPref:@"call_recordings_sync_gallery"]) [RYGCallRecordingGallery syncAllForOwnerPK:self.ownerPK];
	[self reload];
}

- (void)dealloc { [NSNotificationCenter.defaultCenter removeObserver:self]; }

- (void)reload {
	self.allGroups = [RYGCallRecordingStorage groupedForOwnerPK:self.ownerPK];
	[self applyFilter];
}

- (void)applyFilter {
	NSString *q = self.searchController.searchBar.text;
	NSArray<RYGCallRecordingGroup *> *g = self.allGroups;
	if (q.length) {
		NSPredicate *p = [NSPredicate predicateWithBlock:^BOOL(RYGCallRecordingGroup *grp, NSDictionary *b) {
			return [grp.displayName localizedCaseInsensitiveContainsString:q];
		}];
		g = [g filteredArrayUsingPredicate:p];
	}
	if ([self.sortMode isEqualToString:@"name"]) {
		g = [g sortedArrayUsingComparator:^NSComparisonResult(RYGCallRecordingGroup *a, RYGCallRecordingGroup *b) {
			return [a.displayName localizedCaseInsensitiveCompare:b.displayName];
		}];
	} else if ([self.sortMode isEqualToString:@"count"]) {
		g = [g sortedArrayUsingComparator:^NSComparisonResult(RYGCallRecordingGroup *a, RYGCallRecordingGroup *b) {
			return a.count < b.count ? NSOrderedDescending : (a.count > b.count ? NSOrderedAscending : NSOrderedSame);
		}];
	}
	self.groups = g;

	BOOL noneAtAll = self.allGroups.count == 0;
	self.tableView.hidden = noneAtAll;
	self.emptyView.hidden = !noneAtAll;
	if (noneAtAll) {
		[self.emptyView applyTitle:RYGLocalized(@"No recordings")
						   message:RYGLocalized(@"Recorded calls will appear here.")];
	}
	[self updateOverflow];
	[self.tableView reloadData];
}

- (void)updateSearchResultsForSearchController:(UISearchController *)searchController { [self applyFilter]; }

- (void)updateOverflow {
	if (self.tableView.isEditing) {
		NSUInteger n = self.tableView.indexPathsForSelectedRows.count;
		UIBarButtonItem *del = [[UIBarButtonItem alloc] initWithTitle:(n ? [NSString stringWithFormat:RYGLocalized(@"Delete (%lu)"), (unsigned long)n] : RYGLocalized(@"Delete"))
																style:UIBarButtonItemStyleDone target:self action:@selector(deleteSelected)];
		del.tintColor = UIColor.systemRedColor;
		del.enabled = n > 0;
		UIBarButtonItem *done = [[UIBarButtonItem alloc] initWithBarButtonSystemItem:UIBarButtonSystemItemDone target:self action:@selector(exitSelect)];
		self.navigationItem.rightBarButtonItems = @[done, del];
		return;
	}
	if (self.allGroups.count == 0) { self.navigationItem.rightBarButtonItems = nil; return; }
	__weak typeof(self) weakSelf = self;
	UIAction *select = [UIAction actionWithTitle:RYGLocalized(@"Select") image:[UIImage systemImageNamed:@"checkmark.circle"] identifier:nil
										 handler:^(UIAction *a) { [weakSelf enterSelect]; }];
	UIAction *(^sortAction)(NSString *, NSString *) = ^UIAction *(NSString *title, NSString *mode) {
		UIAction *a = [UIAction actionWithTitle:title image:nil identifier:nil handler:^(UIAction *x) {
			weakSelf.sortMode = mode; [weakSelf applyFilter];
		}];
		a.state = [weakSelf.sortMode isEqualToString:mode] ? UIMenuElementStateOn : UIMenuElementStateOff;
		return a;
	};
	UIMenu *sort = [UIMenu menuWithTitle:RYGLocalized(@"Sort by") image:[UIImage systemImageNamed:@"arrow.up.arrow.down"] identifier:nil options:0 children:@[
		sortAction(RYGLocalized(@"Most recent"), @"recent"),
		sortAction(RYGLocalized(@"Name"), @"name"),
		sortAction(RYGLocalized(@"Recording count"), @"count"),
	]];
	UIAction *markRead = [UIAction actionWithTitle:RYGLocalized(@"Mark all as read")
											 image:[UIImage systemImageNamed:@"checkmark.circle"]
										identifier:nil
										   handler:^(UIAction *a) {
		[RYGCallRecordingStorage markAllSeenForOwnerPK:weakSelf.ownerPK];
		[NSNotificationCenter.defaultCenter postNotificationName:@"RYGSettingsShouldReload" object:nil];
	}];
	UIAction *clear = [UIAction actionWithTitle:RYGLocalized(@"Delete all recordings")
										  image:[UIImage systemImageNamed:@"trash"]
									 identifier:nil
										handler:^(UIAction *a) { [weakSelf confirmClearAll]; }];
	clear.attributes = UIMenuElementAttributesDestructive;
	UIMenu *menu = [UIMenu menuWithTitle:@"" children:@[select, sort, markRead, clear]];
	self.navigationItem.rightBarButtonItems = @[[[UIBarButtonItem alloc] initWithImage:[UIImage systemImageNamed:@"ellipsis.circle"] menu:menu]];
}

- (void)enterSelect {
	[self.tableView setEditing:YES animated:YES];
	[self updateOverflow];
}

- (void)exitSelect {
	[self.tableView setEditing:NO animated:YES];
	[self updateOverflow];
}

- (void)deleteSelected {
	NSArray<NSIndexPath *> *sel = self.tableView.indexPathsForSelectedRows;
	if (!sel.count) return;
	NSMutableArray<NSString *> *ids = [NSMutableArray array];
	for (NSIndexPath *ip in sel) if (ip.row < (NSInteger)self.groups.count) [ids addObject:self.groups[ip.row].identifier];
	UIAlertController *ac = [UIAlertController alertControllerWithTitle:[NSString stringWithFormat:RYGLocalized(@"Delete %lu chats?"), (unsigned long)ids.count]
															   message:RYGLocalized(@"This permanently removes their recordings.")
														preferredStyle:UIAlertControllerStyleAlert];
	[ac addAction:[UIAlertAction actionWithTitle:RYGLocalized(@"Cancel") style:UIAlertActionStyleCancel handler:nil]];
	[ac addAction:[UIAlertAction actionWithTitle:RYGLocalized(@"Delete") style:UIAlertActionStyleDestructive handler:^(UIAlertAction *a) {
		for (NSString *identifier in ids) [RYGCallRecordingStorage deleteRecordingsForIdentifier:identifier ownerPK:self.ownerPK];
		[self exitSelect];
	}]];
	[self presentViewController:ac animated:YES completion:nil];
}

- (void)confirmClearAll {
	UIAlertController *ac = [UIAlertController alertControllerWithTitle:RYGLocalized(@"Delete all recordings?")
															   message:RYGLocalized(@"This permanently removes every saved call recording for this account.")
														preferredStyle:UIAlertControllerStyleAlert];
	[ac addAction:[UIAlertAction actionWithTitle:RYGLocalized(@"Cancel") style:UIAlertActionStyleCancel handler:nil]];
	[ac addAction:[UIAlertAction actionWithTitle:RYGLocalized(@"Delete all") style:UIAlertActionStyleDestructive handler:^(UIAlertAction *a) {
		[RYGCallRecordingStorage resetForOwnerPK:self.ownerPK];
	}]];
	[self presentViewController:ac animated:YES completion:nil];
}

#pragma mark - Table

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section { return self.groups.count; }

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath {
	RYGCallGroupCell *cell = [tableView dequeueReusableCellWithIdentifier:@"group" forIndexPath:indexPath];
	[cell applyGroup:self.groups[indexPath.row]];
	return cell;
}

- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath {
	if (tableView.isEditing) { [self updateOverflow]; return; }
	[tableView deselectRowAtIndexPath:indexPath animated:YES];
	RYGCallRecordingGroup *g = self.groups[indexPath.row];
	[RYGCallRecordingStorage markGroupSeen:g.identifier ownerPK:self.ownerPK];
	[NSNotificationCenter.defaultCenter postNotificationName:@"RYGSettingsShouldReload" object:nil];
	RYGCallRecordingDetailViewController *vc = [[RYGCallRecordingDetailViewController alloc] initWithGroup:g ownerPK:self.ownerPK];
	[self.navigationController pushViewController:vc animated:YES];
}

- (void)tableView:(UITableView *)tableView didDeselectRowAtIndexPath:(NSIndexPath *)indexPath {
	if (tableView.isEditing) [self updateOverflow];
}

- (UISwipeActionsConfiguration *)tableView:(UITableView *)tableView trailingSwipeActionsConfigurationForRowAtIndexPath:(NSIndexPath *)indexPath {
	RYGCallRecordingGroup *g = self.groups[indexPath.row];
	UIContextualAction *del = [UIContextualAction contextualActionWithStyle:UIContextualActionStyleDestructive
																	 title:RYGLocalized(@"Delete")
																   handler:^(UIContextualAction *a, UIView *v, void (^done)(BOOL)) {
		[RYGCallRecordingStorage deleteRecordingsForIdentifier:g.identifier ownerPK:self.ownerPK];
		done(YES);
	}];
	del.image = [UIImage systemImageNamed:@"trash"];
	UIContextualAction *rename = [UIContextualAction contextualActionWithStyle:UIContextualActionStyleNormal
																	 title:RYGLocalized(@"Rename")
																   handler:^(UIContextualAction *a, UIView *v, void (^done)(BOOL)) {
		[self renameGroup:g]; done(YES);
	}];
	rename.image = [UIImage systemImageNamed:@"pencil"];
	rename.backgroundColor = UIColor.systemBlueColor;
	return [UISwipeActionsConfiguration configurationWithActions:@[del, rename]];
}

- (void)renameGroup:(RYGCallRecordingGroup *)g {
	UIAlertController *ac = [UIAlertController alertControllerWithTitle:RYGLocalized(@"Rename")
															   message:RYGLocalized(@"Set a custom name for this chat's recordings.")
														preferredStyle:UIAlertControllerStyleAlert];
	[ac addTextFieldWithConfigurationHandler:^(UITextField *tf) { tf.text = g.customName ?: g.displayName; tf.clearButtonMode = UITextFieldViewModeAlways; }];
	[ac addAction:[UIAlertAction actionWithTitle:RYGLocalized(@"Cancel") style:UIAlertActionStyleCancel handler:nil]];
	if (g.customName.length)
		[ac addAction:[UIAlertAction actionWithTitle:RYGLocalized(@"Reset") style:UIAlertActionStyleDestructive handler:^(UIAlertAction *a) {
			[RYGCallRecordingStorage setCustomName:nil forGroupIdentifier:g.identifier ownerPK:self.ownerPK];
		}]];
	[ac addAction:[UIAlertAction actionWithTitle:RYGLocalized(@"Save") style:UIAlertActionStyleDefault handler:^(UIAlertAction *a) {
		[RYGCallRecordingStorage setCustomName:ac.textFields.firstObject.text forGroupIdentifier:g.identifier ownerPK:self.ownerPK];
	}]];
	[self presentViewController:ac animated:YES completion:nil];
}

- (UIContextMenuConfiguration *)tableView:(UITableView *)tableView contextMenuConfigurationForRowAtIndexPath:(NSIndexPath *)indexPath point:(CGPoint)point {
	RYGCallRecordingGroup *g = self.groups[indexPath.row];
	__weak typeof(self) weakSelf = self;
	return [UIContextMenuConfiguration configurationWithIdentifier:nil previewProvider:nil actionProvider:^UIMenu *(NSArray *sug) {
		UIAction *rename = [UIAction actionWithTitle:RYGLocalized(@"Rename") image:[UIImage systemImageNamed:@"pencil"] identifier:nil
											 handler:^(UIAction *a) { [weakSelf renameGroup:g]; }];
		UIAction *del = [UIAction actionWithTitle:RYGLocalized(@"Delete") image:[UIImage systemImageNamed:@"trash"] identifier:nil
										  handler:^(UIAction *a) { [RYGCallRecordingStorage deleteRecordingsForIdentifier:g.identifier ownerPK:weakSelf.ownerPK]; }];
		del.attributes = UIMenuElementAttributesDestructive;
		return [UIMenu menuWithTitle:@"" children:@[rename, del]];
	}];
}

@end
