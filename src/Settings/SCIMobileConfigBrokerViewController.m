#import "SCIMobileConfigBrokerViewController.h"
#import "../Features/ExpFlags/SCIMobileConfigBrokerDescriptor.h"
#import "../Features/ExpFlags/SCIMobileConfigBrokerStore.h"
#import "../Features/ExpFlags/SCIMobileConfigBrokerRouter.h"

@interface SCIMCBrokerCell : UITableViewCell
@property (nonatomic, strong) UILabel *titleLabel;
@property (nonatomic, strong) UILabel *detailLabel2;
@property (nonatomic, strong) UISwitch *overrideSwitch;
@property (nonatomic, strong) UIButton *systemButton;
@property (nonatomic, copy) void (^toggleChanged)(BOOL on);
@property (nonatomic, copy) void (^systemTapped)(void);
@end

@implementation SCIMCBrokerCell
- (instancetype)initWithStyle:(UITableViewCellStyle)style reuseIdentifier:(NSString *)reuseIdentifier {
    self = [super initWithStyle:style reuseIdentifier:reuseIdentifier];
    if (!self) return nil;
    self.backgroundColor = UIColor.secondarySystemGroupedBackgroundColor;
    self.contentView.backgroundColor = UIColor.secondarySystemGroupedBackgroundColor;

    _titleLabel = [UILabel new];
    _titleLabel.font = [UIFont systemFontOfSize:15 weight:UIFontWeightSemibold];
    _titleLabel.numberOfLines = 2;
    _titleLabel.translatesAutoresizingMaskIntoConstraints = NO;
    [self.contentView addSubview:_titleLabel];

    _detailLabel2 = [UILabel new];
    _detailLabel2.font = [UIFont systemFontOfSize:11];
    _detailLabel2.textColor = UIColor.secondaryLabelColor;
    _detailLabel2.numberOfLines = 2;
    _detailLabel2.translatesAutoresizingMaskIntoConstraints = NO;
    [self.contentView addSubview:_detailLabel2];

    _overrideSwitch = [UISwitch new];
    _overrideSwitch.translatesAutoresizingMaskIntoConstraints = NO;
    [_overrideSwitch addTarget:self action:@selector(switchChanged) forControlEvents:UIControlEventValueChanged];
    [self.contentView addSubview:_overrideSwitch];

    _systemButton = [UIButton buttonWithType:UIButtonTypeSystem];
    [_systemButton setTitle:@"System" forState:UIControlStateNormal];
    _systemButton.titleLabel.font = [UIFont systemFontOfSize:12 weight:UIFontWeightSemibold];
    _systemButton.translatesAutoresizingMaskIntoConstraints = NO;
    [_systemButton addTarget:self action:@selector(systemPressed) forControlEvents:UIControlEventTouchUpInside];
    [self.contentView addSubview:_systemButton];

    [NSLayoutConstraint activateConstraints:@[
        [_overrideSwitch.centerYAnchor constraintEqualToAnchor:self.contentView.centerYAnchor],
        [_overrideSwitch.trailingAnchor constraintEqualToAnchor:self.contentView.trailingAnchor constant:-14],
        [_systemButton.centerYAnchor constraintEqualToAnchor:_overrideSwitch.centerYAnchor],
        [_systemButton.trailingAnchor constraintEqualToAnchor:_overrideSwitch.leadingAnchor constant:-12],
        [_titleLabel.topAnchor constraintEqualToAnchor:self.contentView.topAnchor constant:10],
        [_titleLabel.leadingAnchor constraintEqualToAnchor:self.contentView.leadingAnchor constant:16],
        [_titleLabel.trailingAnchor constraintEqualToAnchor:_systemButton.leadingAnchor constant:-10],
        [_detailLabel2.topAnchor constraintEqualToAnchor:_titleLabel.bottomAnchor constant:4],
        [_detailLabel2.leadingAnchor constraintEqualToAnchor:_titleLabel.leadingAnchor],
        [_detailLabel2.trailingAnchor constraintEqualToAnchor:_titleLabel.trailingAnchor],
        [_detailLabel2.bottomAnchor constraintEqualToAnchor:self.contentView.bottomAnchor constant:-10],
    ]];
    return self;
}
- (void)switchChanged { if (self.toggleChanged) self.toggleChanged(self.overrideSwitch.isOn); }
- (void)systemPressed { if (self.systemTapped) self.systemTapped(); }
@end

@interface SCIMobileConfigBrokerViewController () <UITableViewDelegate, UITableViewDataSource>
@property (nonatomic, strong) UITableView *tableView;
@property (nonatomic, strong) UISegmentedControl *filter;
@property (nonatomic, strong) UILabel *footerLabel;
@property (nonatomic, strong) NSArray<SCIMobileConfigBrokerDescriptor *> *rows;
@end

@implementation SCIMobileConfigBrokerViewController

- (void)viewDidLoad {
    [super viewDidLoad];
    self.title = @"MC Brokers";
    self.view.backgroundColor = UIColor.systemGroupedBackgroundColor;
    [SCIMobileConfigBrokerStore registerDefaultsAndMigrate];

    self.filter = [[UISegmentedControl alloc] initWithItems:@[@"Core", @"All", @"Forced", @"Live"]];
    self.filter.selectedSegmentIndex = 0;
    [self.filter addTarget:self action:@selector(reloadRows) forControlEvents:UIControlEventValueChanged];
    self.filter.translatesAutoresizingMaskIntoConstraints = NO;
    [self.view addSubview:self.filter];

    self.footerLabel = [UILabel new];
    self.footerLabel.font = [UIFont systemFontOfSize:11];
    self.footerLabel.textColor = UIColor.secondaryLabelColor;
    self.footerLabel.numberOfLines = 0;
    self.footerLabel.translatesAutoresizingMaskIntoConstraints = NO;
    [self.view addSubview:self.footerLabel];

    self.tableView = [[UITableView alloc] initWithFrame:CGRectZero style:UITableViewStyleInsetGrouped];
    self.tableView.delegate = self;
    self.tableView.dataSource = self;
    self.tableView.backgroundColor = UIColor.systemGroupedBackgroundColor;
    self.tableView.rowHeight = UITableViewAutomaticDimension;
    self.tableView.estimatedRowHeight = 72;
    [self.tableView registerClass:SCIMCBrokerCell.class forCellReuseIdentifier:@"broker"];
    self.tableView.translatesAutoresizingMaskIntoConstraints = NO;
    [self.view addSubview:self.tableView];

    self.navigationItem.rightBarButtonItems = @[
        [[UIBarButtonItem alloc] initWithTitle:@"Install" style:UIBarButtonItemStylePlain target:self action:@selector(installEnabled)],
        [[UIBarButtonItem alloc] initWithTitle:@"Reset" style:UIBarButtonItemStylePlain target:self action:@selector(resetOverrides)]
    ];

    UILayoutGuide *g = self.view.safeAreaLayoutGuide;
    [NSLayoutConstraint activateConstraints:@[
        [self.filter.topAnchor constraintEqualToAnchor:g.topAnchor constant:8],
        [self.filter.leadingAnchor constraintEqualToAnchor:g.leadingAnchor constant:12],
        [self.filter.trailingAnchor constraintEqualToAnchor:g.trailingAnchor constant:-12],
        [self.footerLabel.topAnchor constraintEqualToAnchor:self.filter.bottomAnchor constant:8],
        [self.footerLabel.leadingAnchor constraintEqualToAnchor:g.leadingAnchor constant:16],
        [self.footerLabel.trailingAnchor constraintEqualToAnchor:g.trailingAnchor constant:-16],
        [self.tableView.topAnchor constraintEqualToAnchor:self.footerLabel.bottomAnchor constant:4],
        [self.tableView.leadingAnchor constraintEqualToAnchor:g.leadingAnchor],
        [self.tableView.trailingAnchor constraintEqualToAnchor:g.trailingAnchor],
        [self.tableView.bottomAnchor constraintEqualToAnchor:g.bottomAnchor],
    ]];

    [self reloadRows];
}

- (void)reloadRows {
    NSMutableArray *items = [NSMutableArray array];
    for (SCIMobileConfigBrokerDescriptor *d in [SCIMobileConfigBrokerDescriptor allDescriptors]) {
        NSInteger f = self.filter.selectedSegmentIndex;
        if (f == 0 && d.kind == SCIMCBrokerKindCompat) continue;
        if (f == 2 && [SCIMobileConfigBrokerStore overrideValueForBrokerID:d.brokerID] == nil) continue;
        if (f == 3 && ![SCIMobileConfigBrokerRouter isInstalled:d.brokerID]) continue;
        [items addObject:d];
    }
    self.rows = items;
    self.footerLabel.text = [NSString stringWithFormat:@"Namespace: mcbr:<id> / mcob:<id> · installed=%lu · overrides=%lu · zero hook when no saved override/hook toggle", (unsigned long)[SCIMobileConfigBrokerRouter installedCount], (unsigned long)[SCIMobileConfigBrokerStore activeOverrideBrokerIDs].count];
    [self.tableView reloadData];
}

- (void)installEnabled {
    [SCIMobileConfigBrokerRouter installEnabledBrokers];
    [self reloadRows];
}

- (void)resetOverrides {
    [SCIMobileConfigBrokerStore resetAllBrokerOverrides];
    [self reloadRows];
}

- (NSInteger)numberOfSectionsInTableView:(UITableView *)tableView { return 3; }
- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section {
    if (section == 0) return self.rows.count;
    if (section == 1) return 1;
    return 1;
}
- (NSString *)tableView:(UITableView *)tableView titleForHeaderInSection:(NSInteger)section {
    if (section == 0) return @"FBSharedFramework C brokers";
    if (section == 1) return @"Install behavior";
    return @"Debug snapshot";
}
- (NSString *)tableView:(UITableView *)tableView titleForFooterInSection:(NSInteger)section {
    if (section == 0) return @"Switch ON/OFF writes override. System removes override. Install toggle in details controls pass-through observation without forcing.";
    return nil;
}

- (UITableViewCell *)basicCell:(NSString *)title detail:(NSString *)detail {
    UITableViewCell *cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleSubtitle reuseIdentifier:nil];
    cell.textLabel.text = title;
    cell.detailTextLabel.text = detail;
    cell.detailTextLabel.numberOfLines = 0;
    cell.backgroundColor = UIColor.secondarySystemGroupedBackgroundColor;
    return cell;
}

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath {
    if (indexPath.section == 1) return [self basicCell:@"Startup" detail:@"Only brokers with mcbr:<id> override or mcbr.hook:<id> enabled are installed on launch. No global sweep."];
    if (indexPath.section == 2) return [self basicCell:@"Copy snapshot" detail:@"Tap to copy current mcbr/mcob state as JSON."];

    SCIMCBrokerCell *cell = [tableView dequeueReusableCellWithIdentifier:@"broker" forIndexPath:indexPath];
    SCIMobileConfigBrokerDescriptor *d = self.rows[indexPath.row];
    BOOL installed = [SCIMobileConfigBrokerRouter isInstalled:d.brokerID];
    NSNumber *forced = [SCIMobileConfigBrokerStore overrideValueForBrokerID:d.brokerID];
    NSString *system = [SCIMobileConfigBrokerStore systemLabelForBrokerID:d.brokerID];
    NSString *override = [SCIMobileConfigBrokerStore overrideLabelForBrokerID:d.brokerID];
    NSString *kind = d.kind == SCIMCBrokerKindPrimary ? @"core" : (d.kind == SCIMCBrokerKindComplement ? @"extra" : @"compat");
    cell.titleLabel.text = [NSString stringWithFormat:@"%@  [%@]", d.displayName, d.brokerID];
    cell.detailLabel2.text = [NSString stringWithFormat:@"%@ · system %@ · %@ · %@ · hits %lu/%lu", kind, system, override, installed ? @"live" : @"off", (unsigned long)[SCIMobileConfigBrokerStore hitCountForBrokerID:d.brokerID], (unsigned long)[SCIMobileConfigBrokerStore forcedHitCountForBrokerID:d.brokerID]];
    [cell.overrideSwitch setOn:([SCIMobileConfigBrokerStore effectiveStateForBrokerID:d.brokerID] == SCIMCBrokerBoolStateOn) animated:NO];
    cell.systemButton.enabled = forced != nil;
    cell.systemButton.alpha = forced ? 1.0 : 0.35;
    __weak typeof(self) weakSelf = self;
    cell.toggleChanged = ^(BOOL on) {
        [SCIMobileConfigBrokerStore setOverrideValue:@(on) forBrokerID:d.brokerID];
        NSError *err = nil;
        [SCIMobileConfigBrokerRouter installBroker:d error:&err];
        [weakSelf reloadRows];
    };
    cell.systemTapped = ^{
        [SCIMobileConfigBrokerStore setOverrideValue:nil forBrokerID:d.brokerID];
        [weakSelf reloadRows];
    };
    return cell;
}

- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath {
    [tableView deselectRowAtIndexPath:indexPath animated:YES];
    if (indexPath.section == 2) {
        NSData *data = [NSJSONSerialization dataWithJSONObject:[SCIMobileConfigBrokerStore snapshotDictionary] options:NSJSONWritingPrettyPrinted error:nil];
        UIPasteboard.generalPasteboard.string = [[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding];
        return;
    }
    if (indexPath.section != 0) return;

    SCIMobileConfigBrokerDescriptor *d = self.rows[indexPath.row];
    NSString *msg = [NSString stringWithFormat:@"%@\n\nSymbol: %@\nImage: %@\nVM: 0x%lx\nXrefs: %lu\nExpected8: 0x%016llx\nKey: %@\nObserved: %@\nOverride: %@\nHook: %@\nLast error: %@",
                     d.details,
                     d.symbol,
                     d.imageName,
                     (unsigned long)d.vmAddress,
                     (unsigned long)d.xrefCount,
                     (unsigned long long)d.expectedOrig8,
                     [SCIMobileConfigBrokerStore overrideKeyForBrokerID:d.brokerID],
                     [SCIMobileConfigBrokerStore systemLabelForBrokerID:d.brokerID],
                     [SCIMobileConfigBrokerStore overrideLabelForBrokerID:d.brokerID],
                     [SCIMobileConfigBrokerRouter isInstalled:d.brokerID] ? @"installed" : @"not installed",
                     [SCIMobileConfigBrokerStore lastErrorForBrokerID:d.brokerID] ?: @"none"];

    UIAlertController *a = [UIAlertController alertControllerWithTitle:d.displayName message:msg preferredStyle:UIAlertControllerStyleActionSheet];
    [a addAction:[UIAlertAction actionWithTitle:@"Force ON" style:UIAlertActionStyleDefault handler:^(__unused UIAlertAction *x){ [SCIMobileConfigBrokerStore setOverrideValue:@YES forBrokerID:d.brokerID]; [SCIMobileConfigBrokerRouter installBroker:d error:nil]; [self reloadRows]; }]];
    [a addAction:[UIAlertAction actionWithTitle:@"Force OFF" style:UIAlertActionStyleDefault handler:^(__unused UIAlertAction *x){ [SCIMobileConfigBrokerStore setOverrideValue:@NO forBrokerID:d.brokerID]; [SCIMobileConfigBrokerRouter installBroker:d error:nil]; [self reloadRows]; }]];
    [a addAction:[UIAlertAction actionWithTitle:@"System" style:UIAlertActionStyleDefault handler:^(__unused UIAlertAction *x){ [SCIMobileConfigBrokerStore setOverrideValue:nil forBrokerID:d.brokerID]; [self reloadRows]; }]];
    [a addAction:[UIAlertAction actionWithTitle:@"Install pass-through observer" style:UIAlertActionStyleDefault handler:^(__unused UIAlertAction *x){ [SCIMobileConfigBrokerStore setBrokerHookEnabled:YES brokerID:d.brokerID]; [SCIMobileConfigBrokerRouter installBroker:d error:nil]; [self reloadRows]; }]];
    [a addAction:[UIAlertAction actionWithTitle:@"Disable startup observer" style:UIAlertActionStyleDefault handler:^(__unused UIAlertAction *x){ [SCIMobileConfigBrokerStore setBrokerHookEnabled:NO brokerID:d.brokerID]; [self reloadRows]; }]];
    [a addAction:[UIAlertAction actionWithTitle:@"Copy key" style:UIAlertActionStyleDefault handler:^(__unused UIAlertAction *x){ UIPasteboard.generalPasteboard.string = [SCIMobileConfigBrokerStore overrideKeyForBrokerID:d.brokerID]; }]];
    [a addAction:[UIAlertAction actionWithTitle:@"Cancel" style:UIAlertActionStyleCancel handler:nil]];
    UITableViewCell *cell = [tableView cellForRowAtIndexPath:indexPath];
    if (a.popoverPresentationController) { a.popoverPresentationController.sourceView = cell; a.popoverPresentationController.sourceRect = cell.bounds; }
    [self presentViewController:a animated:YES completion:nil];
}
@end
