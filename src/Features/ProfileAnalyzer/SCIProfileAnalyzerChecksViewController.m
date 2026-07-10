#import "SCIProfileAnalyzerChecksViewController.h"
#import "SCIProfileAnalyzerChecks.h"
#import "../../UI/SCIPopupChrome.h"
#import "../../Utils.h"
#import "../../Localization/SCILocalization.h"

@interface SCIProfileAnalyzerChecksViewController () <UITableViewDataSource, UITableViewDelegate>
@property (nonatomic, strong) UITableView *tableView;
@property (nonatomic, copy) NSArray<SCIPACheckDescriptor *> *checks;
@end

@implementation SCIProfileAnalyzerChecksViewController

- (void)viewDidLoad {
	[super viewDidLoad];
	self.title = SCILocalized(@"Checks");
	self.view.backgroundColor = [SCIPopupChrome backgroundColor];
	self.checks = [SCIProfileAnalyzerChecks allChecks];

	self.tableView = [[UITableView alloc] initWithFrame:self.view.bounds style:UITableViewStyleInsetGrouped];
	self.tableView.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
	self.tableView.dataSource = self;
	self.tableView.delegate = self;
	self.tableView.backgroundColor = [SCIPopupChrome backgroundColor];
	[self.view addSubview:self.tableView];
}

#pragma mark - Table

- (NSInteger)tableView:(UITableView *)tv numberOfRowsInSection:(NSInteger)section {
	return (NSInteger)self.checks.count;
}

- (NSString *)tableView:(UITableView *)tv titleForFooterInSection:(NSInteger)section {
	return SCILocalized(@"Pick which categories each scan computes. A disabled check is greyed out and skipped — it won't be calculated or shown.");
}

- (UITableViewCell *)tableView:(UITableView *)tv cellForRowAtIndexPath:(NSIndexPath *)ip {
	static NSString *rid = @"chk";
	UITableViewCell *cell = [tv dequeueReusableCellWithIdentifier:rid];
	if (!cell) cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleSubtitle reuseIdentifier:rid];
	cell.detailTextLabel.numberOfLines = 0;
	cell.detailTextLabel.textColor = [UIColor secondaryLabelColor];
	cell.selectionStyle = UITableViewCellSelectionStyleNone;

	SCIPACheckDescriptor *c = self.checks[ip.row];
	cell.textLabel.text = SCILocalized(c.title);
	cell.detailTextLabel.text = SCILocalized(c.subtitle);
	cell.imageView.image = [UIImage systemImageNamed:c.symbol];
	cell.imageView.tintColor = c.color;

	UISwitch *sw = [UISwitch new];
	sw.onTintColor = [SCIUtils SCIColor_Primary];
	sw.tag = ip.row;
	sw.on = [SCIProfileAnalyzerChecks isCheckEnabledForKey:c.prefKey];
	[sw addTarget:self action:@selector(checkToggled:) forControlEvents:UIControlEventValueChanged];
	cell.accessoryView = sw;
	return cell;
}

- (void)checkToggled:(UISwitch *)sw {
	if (sw.tag < 0 || sw.tag >= (NSInteger)self.checks.count) return;
	SCIPACheckDescriptor *c = self.checks[sw.tag];
	[SCIUtils setPref:@(sw.isOn) forKey:c.prefKey];
}

@end
