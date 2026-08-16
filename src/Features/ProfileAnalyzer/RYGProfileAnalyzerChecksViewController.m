#import "RYGProfileAnalyzerChecksViewController.h"
#import "RYGProfileAnalyzerChecks.h"
#import "../../UI/RYGPopupChrome.h"
#import "../../Utils.h"
#import "../../Localization/RYGLocalization.h"

@interface RYGProfileAnalyzerChecksViewController () <UITableViewDataSource, UITableViewDelegate>
@property (nonatomic, strong) UITableView *tableView;
@property (nonatomic, copy) NSArray<RYGPACheckDescriptor *> *checks;
@end

@implementation RYGProfileAnalyzerChecksViewController

- (void)viewDidLoad {
	[super viewDidLoad];
	self.title = RYGLocalized(@"Checks");
	self.view.backgroundColor = [RYGPopupChrome backgroundColor];
	self.checks = [RYGProfileAnalyzerChecks allChecks];

	self.tableView = [[UITableView alloc] initWithFrame:self.view.bounds style:UITableViewStyleInsetGrouped];
	self.tableView.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
	self.tableView.dataSource = self;
	self.tableView.delegate = self;
	self.tableView.backgroundColor = [RYGPopupChrome backgroundColor];
	[self.view addSubview:self.tableView];
}

#pragma mark - Table

- (NSInteger)tableView:(UITableView *)tv numberOfRowsInSection:(NSInteger)section {
	return (NSInteger)self.checks.count;
}

- (NSString *)tableView:(UITableView *)tv titleForFooterInSection:(NSInteger)section {
	return RYGLocalized(@"Pick which categories each scan computes. A disabled check is greyed out and skipped — it won't be calculated or shown.");
}

- (UITableViewCell *)tableView:(UITableView *)tv cellForRowAtIndexPath:(NSIndexPath *)ip {
	static NSString *rid = @"chk";
	UITableViewCell *cell = [tv dequeueReusableCellWithIdentifier:rid];
	if (!cell) cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleSubtitle reuseIdentifier:rid];
	cell.detailTextLabel.numberOfLines = 0;
	cell.detailTextLabel.textColor = [UIColor secondaryLabelColor];
	cell.selectionStyle = UITableViewCellSelectionStyleNone;

	RYGPACheckDescriptor *c = self.checks[ip.row];
	cell.textLabel.text = RYGLocalized(c.title);
	cell.detailTextLabel.text = RYGLocalized(c.subtitle);
	cell.imageView.image = [UIImage systemImageNamed:c.symbol];
	cell.imageView.tintColor = c.color;

	UISwitch *sw = [UISwitch new];
	sw.onTintColor = [RYGUtils RYGColor_Primary];
	sw.tag = ip.row;
	sw.on = [RYGProfileAnalyzerChecks isCheckEnabledForKey:c.prefKey];
	[sw addTarget:self action:@selector(checkToggled:) forControlEvents:UIControlEventValueChanged];
	cell.accessoryView = sw;
	return cell;
}

- (void)checkToggled:(UISwitch *)sw {
	if (sw.tag < 0 || sw.tag >= (NSInteger)self.checks.count) return;
	RYGPACheckDescriptor *c = self.checks[sw.tag];
	[RYGUtils setPref:@(sw.isOn) forKey:c.prefKey];
}

@end
