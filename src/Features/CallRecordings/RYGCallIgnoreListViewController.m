#import "RYGCallIgnoreListViewController.h"
#import "RYGCallRecordingStorage.h"
#import "../../UI/RYGPopupChrome.h"
#import "../../Utils.h"

@interface RYGCallIgnoreListViewController () <UITableViewDataSource, UITableViewDelegate>
@property (nonatomic, strong) UITableView *tableView;
@property (nonatomic, strong) UILabel *emptyLabel;
@property (nonatomic, strong) NSArray<NSDictionary *> *entries;
@property (nonatomic, copy) NSString *ownerPK;
@end

@implementation RYGCallIgnoreListViewController

- (void)viewDidLoad {
	[super viewDidLoad];
	self.title = RYGLocalized(@"Auto-record ignore list");
	self.view.backgroundColor = [RYGPopupChrome backgroundColor];
	self.ownerPK = [RYGUtils currentUserPK] ?: @"anon";

	self.tableView = [[UITableView alloc] initWithFrame:CGRectZero style:UITableViewStyleInsetGrouped];
	self.tableView.translatesAutoresizingMaskIntoConstraints = NO;
	self.tableView.dataSource = self;
	self.tableView.delegate = self;
	self.tableView.backgroundColor = UIColor.clearColor;
	[self.view addSubview:self.tableView];

	self.emptyLabel = [UILabel new];
	self.emptyLabel.translatesAutoresizingMaskIntoConstraints = NO;
	self.emptyLabel.text = RYGLocalized(@"No ignored chats. Long-press the record button in a call to ignore it.");
	self.emptyLabel.textColor = UIColor.tertiaryLabelColor;
	self.emptyLabel.font = [UIFont systemFontOfSize:15];
	self.emptyLabel.textAlignment = NSTextAlignmentCenter;
	self.emptyLabel.numberOfLines = 0;
	[self.view addSubview:self.emptyLabel];

	[NSLayoutConstraint activateConstraints:@[
		[self.tableView.topAnchor constraintEqualToAnchor:self.view.topAnchor],
		[self.tableView.leadingAnchor constraintEqualToAnchor:self.view.leadingAnchor],
		[self.tableView.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor],
		[self.tableView.bottomAnchor constraintEqualToAnchor:self.view.bottomAnchor],
		[self.emptyLabel.centerXAnchor constraintEqualToAnchor:self.view.centerXAnchor],
		[self.emptyLabel.centerYAnchor constraintEqualToAnchor:self.view.centerYAnchor],
		[self.emptyLabel.leadingAnchor constraintEqualToAnchor:self.view.leadingAnchor constant:32],
		[self.emptyLabel.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor constant:-32],
	]];
}

- (void)viewWillAppear:(BOOL)animated {
	[super viewWillAppear:animated];
	[self reload];
}

- (void)reload {
	self.entries = [RYGCallRecordingStorage ignoredCallsForOwnerPK:self.ownerPK];
	self.emptyLabel.hidden = self.entries.count > 0;
	[self.tableView reloadData];
}

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section { return self.entries.count; }

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath {
	static NSString *rid = @"ig";
	UITableViewCell *cell = [tableView dequeueReusableCellWithIdentifier:rid];
	if (!cell) {
		cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleDefault reuseIdentifier:rid];
		cell.backgroundColor = UIColor.secondarySystemGroupedBackgroundColor;
	}
	cell.textLabel.text = self.entries[indexPath.row][@"name"];
	cell.imageView.image = [UIImage systemImageNamed:@"mic.slash.circle.fill"];
	cell.imageView.tintColor = UIColor.secondaryLabelColor;
	return cell;
}

- (UISwipeActionsConfiguration *)tableView:(UITableView *)tableView trailingSwipeActionsConfigurationForRowAtIndexPath:(NSIndexPath *)indexPath {
	NSDictionary *e = self.entries[indexPath.row];
	UIContextualAction *del = [UIContextualAction contextualActionWithStyle:UIContextualActionStyleDestructive
																	 title:RYGLocalized(@"Remove")
																   handler:^(UIContextualAction *a, UIView *v, void (^done)(BOOL)) {
		[RYGCallRecordingStorage setCall:e[@"id"] ignored:NO name:nil ownerPK:self.ownerPK];
		[self reload];
		done(YES);
	}];
	del.image = [UIImage systemImageNamed:@"trash"];
	return [UISwipeActionsConfiguration configurationWithActions:@[del]];
}

@end
