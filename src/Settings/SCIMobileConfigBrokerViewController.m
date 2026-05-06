#import "SCIMobileConfigBrokerViewController.h"
#import "../Features/ExpFlags/SCIMobileConfigBrokerDescriptor.h"
#import "../Features/ExpFlags/SCIMobileConfigBrokerStore.h"
#import "../Features/ExpFlags/SCIMobileConfigBrokerRouter.h"
#import "../Features/ExpFlags/SCIMobileConfigIDResolver.h"

@interface SCIMCBrokerValueViewController : UITableViewController
@property (nonatomic, strong) SCIMobileConfigBrokerDescriptor *broker;
@property (nonatomic, strong) NSArray<NSString *> *rows;
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
    self.tableView.estimatedRowHeight = 74;
    [self.tableView registerClass:UITableViewCell.class forCellReuseIdentifier:@"broker"];
    self.tableView.translatesAutoresizingMaskIntoConstraints = NO;
    [self.view addSubview:self.tableView];

    self.navigationItem.rightBarButtonItems = @[
        [[UIBarButtonItem alloc] initWithTitle:@"Copy" style:UIBarButtonItemStylePlain target:self action:@selector(copySnapshot)],
        [[UIBarButtonItem alloc] initWithTitle:@"Install" style:UIBarButtonItemStylePlain target:self action:@selector(installEnabled)]
    ];
    self.navigationItem.leftBarButtonItem = [[UIBarButtonItem alloc] initWithTitle:@"Reset" style:UIBarButtonItemStylePlain target:self action:@selector(resetOverrides)];

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

    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(reloadRows) name:SCIMCBrokerStoreDidChangeNotification object:nil];
    [self reloadRows];
}

- (void)dealloc { [[NSNotificationCenter defaultCenter] removeObserver:self]; }

- (void)reloadRows {
    NSMutableArray *items = [NSMutableArray array];
    for (SCIMobileConfigBrokerDescriptor *d in [SCIMobileConfigBrokerDescriptor allDescriptors]) {
        NSInteger f = self.filter.selectedSegmentIndex;
        if (f == 0 && d.kind == SCIMCBrokerKindCompat) continue;
        if (f == 2 && [SCIMobileConfigBrokerStore activeOverrideKeysForBrokerID:d.brokerID].count == 0) continue;
        if (f == 3 && [SCIMobileConfigBrokerStore observedOverrideKeysForBrokerID:d.brokerID].count == 0) continue;
        [items addObject:d];
    }
    self.rows = items;
    self.footerLabel.text = [NSString stringWithFormat:@"%@\nNamespace: mcbr:<brokerID>:<hex64> override · mcob:<brokerID>:<hex64> observed · hook toggle mcbr.hook:<brokerID>", [SCIMobileConfigIDResolver mappingStatusLine]];
    [self.tableView reloadData];
}

- (void)installEnabled {
    [SCIMobileConfigBrokerRouter installEnabledBrokers];
    [self reloadRows];
}

- (void)resetOverrides {
    UIAlertController *a = [UIAlertController alertControllerWithTitle:@"Reset MC Broker overrides" message:@"Remove all per-value overrides under mcbr:<brokerID>:<hex64>. Observed mcob values are kept." preferredStyle:UIAlertControllerStyleAlert];
    [a addAction:[UIAlertAction actionWithTitle:@"Cancel" style:UIAlertActionStyleCancel handler:nil]];
    [a addAction:[UIAlertAction actionWithTitle:@"Reset" style:UIAlertActionStyleDestructive handler:^(__unused UIAlertAction *action) {
        [SCIMobileConfigBrokerStore resetAllBrokerOverrides];
        [self reloadRows];
    }]];
    [self presentViewController:a animated:YES completion:nil];
}

- (void)copySnapshot {
    NSDictionary *snap = [SCIMobileConfigBrokerStore snapshotDictionary];
    NSData *data = [NSJSONSerialization dataWithJSONObject:snap options:NSJSONWritingPrettyPrinted error:nil];
    NSString *json = [[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding] ?: @"{}";
    UIPasteboard.generalPasteboard.string = json;
}

- (NSInteger)numberOfSectionsInTableView:(UITableView *)tableView { return 2; }
- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section { return section == 0 ? self.rows.count : 1; }
- (NSString *)tableView:(UITableView *)tableView titleForHeaderInSection:(NSInteger)section { return section == 0 ? @"Broker" : @"Actions"; }
- (NSString *)tableView:(UITableView *)tableView titleForFooterInSection:(NSInteger)section {
    if (section == 0) return @"Install enables pass-through observation. Overrides are per observed specifier/gate inside each broker screen, not global.";
    return nil;
}

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath {
    UITableViewCell *cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleSubtitle reuseIdentifier:nil];
    cell.backgroundColor = UIColor.secondarySystemGroupedBackgroundColor;
    cell.textLabel.numberOfLines = 2;
    cell.detailTextLabel.numberOfLines = 4;
    cell.accessoryType = UITableViewCellAccessoryNone;

    if (indexPath.section == 1) {
        cell.textLabel.text = @"Copy resolved snapshot JSON";
        cell.detailTextLabel.text = @"Copies broker values enriched with resolvedName/resolvedDetail/source/family/param.";
        cell.accessoryType = UITableViewCellAccessoryDisclosureIndicator;
        return cell;
    }

    SCIMobileConfigBrokerDescriptor *d = self.rows[indexPath.row];
    NSArray *observed = [SCIMobileConfigBrokerStore observedOverrideKeysForBrokerID:d.brokerID];
    NSArray *forced = [SCIMobileConfigBrokerStore activeOverrideKeysForBrokerID:d.brokerID];
    UISwitch *sw = [UISwitch new];
    sw.on = [SCIMobileConfigBrokerStore isBrokerHookEnabledForID:d.brokerID];
    sw.tag = indexPath.row;
    [sw addTarget:self action:@selector(hookSwitchChanged:) forControlEvents:UIControlEventValueChanged];
    cell.accessoryView = sw;
    cell.textLabel.text = d.displayName ?: d.symbol;
    NSString *error = [SCIMobileConfigBrokerStore lastErrorForBrokerID:d.brokerID];
    NSMutableString *detail = [NSMutableString stringWithFormat:@"%@ · observed %lu · overrides %lu · hits %lu forced %lu", d.symbol ?: @"", (unsigned long)observed.count, (unsigned long)forced.count, (unsigned long)[SCIMobileConfigBrokerStore hitCountForBrokerID:d.brokerID], (unsigned long)[SCIMobileConfigBrokerStore forcedHitCountForBrokerID:d.brokerID]];
    if (d.details.length) [detail appendFormat:@"\n%@", d.details];
    if (error.length) [detail appendFormat:@"\nLast error: %@", error];
    cell.detailTextLabel.text = detail;
    cell.accessoryType = UITableViewCellAccessoryDisclosureIndicator;
    return cell;
}

- (void)hookSwitchChanged:(UISwitch *)sender {
    if (sender.tag < 0 || sender.tag >= self.rows.count) return;
    SCIMobileConfigBrokerDescriptor *d = self.rows[sender.tag];
    [SCIMobileConfigBrokerStore setBrokerHookEnabled:sender.isOn brokerID:d.brokerID];
    [self reloadRows];
}

- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath {
    [tableView deselectRowAtIndexPath:indexPath animated:YES];
    if (indexPath.section == 1) { [self copySnapshot]; return; }
    SCIMobileConfigBrokerDescriptor *d = self.rows[indexPath.row];
    SCIMCBrokerValueViewController *vc = [SCIMCBrokerValueViewController new];
    vc.broker = d;
    [self.navigationController pushViewController:vc animated:YES];
}

@end

@implementation SCIMCBrokerValueViewController

- (void)viewDidLoad {
    [super viewDidLoad];
    self.title = self.broker.brokerID ?: @"broker";
    self.tableView.backgroundColor = UIColor.systemGroupedBackgroundColor;
    self.tableView.rowHeight = UITableViewAutomaticDimension;
    self.tableView.estimatedRowHeight = 80;
    self.navigationItem.rightBarButtonItems = @[
        [[UIBarButtonItem alloc] initWithTitle:@"Copy" style:UIBarButtonItemStylePlain target:self action:@selector(copyBrokerSnapshot)],
        [[UIBarButtonItem alloc] initWithTitle:@"Refresh" style:UIBarButtonItemStylePlain target:self action:@selector(reloadRows)]
    ];
    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(reloadRows) name:SCIMCBrokerStoreDidChangeNotification object:nil];
    [self reloadRows];
}

- (void)dealloc { [[NSNotificationCenter defaultCenter] removeObserver:self]; }

- (void)reloadRows {
    NSMutableOrderedSet *set = [NSMutableOrderedSet orderedSetWithArray:[SCIMobileConfigBrokerStore observedOverrideKeysForBrokerID:self.broker.brokerID]];
    for (NSString *k in [SCIMobileConfigBrokerStore activeOverrideKeysForBrokerID:self.broker.brokerID]) [set addObject:k];
    self.rows = set.array;
    [self.tableView reloadData];
}

- (void)copyBrokerSnapshot {
    NSDictionary *snap = [SCIMobileConfigBrokerStore snapshotDictionary][self.broker.brokerID ?: @""] ?: @{};
    NSData *data = [NSJSONSerialization dataWithJSONObject:snap options:NSJSONWritingPrettyPrinted error:nil];
    UIPasteboard.generalPasteboard.string = [[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding] ?: @"{}";
}

- (NSInteger)numberOfSectionsInTableView:(UITableView *)tableView { return 1; }
- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section { return self.rows.count ?: 1; }
- (NSString *)tableView:(UITableView *)tableView titleForHeaderInSection:(NSInteger)section { return @"Observed specifiers / gates"; }
- (NSString *)tableView:(UITableView *)tableView titleForFooterInSection:(NSInteger)section { return @"Per-row switch writes mcbr:<brokerID>:<hex64>. OFF means System unless a forced OFF is explicitly chosen from row actions."; }

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath {
    UITableViewCell *cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleSubtitle reuseIdentifier:nil];
    cell.backgroundColor = UIColor.secondarySystemGroupedBackgroundColor;
    cell.textLabel.numberOfLines = 2;
    cell.detailTextLabel.numberOfLines = 4;
    if (!self.rows.count) {
        cell.textLabel.text = @"No observed values yet";
        cell.detailTextLabel.text = @"Enable Install/pass-through observation and exercise the app path that reads this broker.";
        return cell;
    }

    NSString *key = self.rows[indexPath.row];
    NSString *bid = nil; uint64_t value = 0;
    [SCIMobileConfigBrokerStore parseOverrideKey:key brokerID:&bid value:&value];
    SCIMobileConfigIDResolution *r = [SCIMobileConfigIDResolver resolutionForBrokerID:bid value:value];
    cell.textLabel.text = r.title ?: key;
    cell.detailTextLabel.text = [NSString stringWithFormat:@"%@ · %@ · system %@ · %@", self.broker.displayName ?: bid ?: @"broker", r.source ?: @"unknown", [SCIMobileConfigBrokerStore systemLabelForOverrideKey:key], [SCIMobileConfigBrokerStore overrideLabelForOverrideKey:key]];
    UISwitch *sw = [UISwitch new];
    sw.on = ([SCIMobileConfigBrokerStore overrideValueForKey:key] ?: [SCIMobileConfigBrokerStore observedValueForOverrideKey:key]).boolValue;
    sw.tag = indexPath.row;
    [sw addTarget:self action:@selector(valueSwitchChanged:) forControlEvents:UIControlEventValueChanged];
    cell.accessoryView = sw;
    return cell;
}

- (void)valueSwitchChanged:(UISwitch *)sender {
    if (sender.tag < 0 || sender.tag >= self.rows.count) return;
    NSString *key = self.rows[sender.tag];
    [SCIMobileConfigBrokerStore setOverrideValue:@(sender.isOn) forKey:key];
    [self reloadRows];
}

- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath {
    [tableView deselectRowAtIndexPath:indexPath animated:YES];
    if (!self.rows.count) return;
    NSString *key = self.rows[indexPath.row];
    NSString *bid = nil; uint64_t value = 0;
    [SCIMobileConfigBrokerStore parseOverrideKey:key brokerID:&bid value:&value];
    SCIMobileConfigIDResolution *r = [SCIMobileConfigIDResolver resolutionForBrokerID:bid value:value];

    UIAlertController *a = [UIAlertController alertControllerWithTitle:r.title ?: key message:r.resolvedDetail ?: key preferredStyle:UIAlertControllerStyleActionSheet];
    [a addAction:[UIAlertAction actionWithTitle:@"Force ON" style:UIAlertActionStyleDefault handler:^(__unused UIAlertAction *action) { [SCIMobileConfigBrokerStore setOverrideValue:@YES forKey:key]; [self reloadRows]; }]];
    [a addAction:[UIAlertAction actionWithTitle:@"Force OFF" style:UIAlertActionStyleDefault handler:^(__unused UIAlertAction *action) { [SCIMobileConfigBrokerStore setOverrideValue:@NO forKey:key]; [self reloadRows]; }]];
    [a addAction:[UIAlertAction actionWithTitle:@"System" style:UIAlertActionStyleDefault handler:^(__unused UIAlertAction *action) { [SCIMobileConfigBrokerStore setOverrideValue:nil forKey:key]; [self reloadRows]; }]];
    [a addAction:[UIAlertAction actionWithTitle:@"Set manual label" style:UIAlertActionStyleDefault handler:^(__unused UIAlertAction *action) { [self promptManualLabelForBrokerID:bid value:value]; }]];
    [a addAction:[UIAlertAction actionWithTitle:@"Copy resolved JSON" style:UIAlertActionStyleDefault handler:^(__unused UIAlertAction *action) {
        NSMutableDictionary *d = [[SCIMobileConfigBrokerStore resolvedDictionaryForOverrideKey:key] mutableCopy] ?: [NSMutableDictionary dictionary];
        d[@"key"] = key ?: @"";
        d[@"override"] = [SCIMobileConfigBrokerStore overrideValueForKey:key] ?: [NSNull null];
        d[@"observed"] = [SCIMobileConfigBrokerStore observedValueForOverrideKey:key] ?: [NSNull null];
        NSData *data = [NSJSONSerialization dataWithJSONObject:d options:NSJSONWritingPrettyPrinted error:nil];
        UIPasteboard.generalPasteboard.string = [[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding] ?: @"{}";
    }]];
    [a addAction:[UIAlertAction actionWithTitle:@"Cancel" style:UIAlertActionStyleCancel handler:nil]];
    [self presentViewController:a animated:YES completion:nil];
}

- (void)promptManualLabelForBrokerID:(NSString *)brokerID value:(uint64_t)value {
    NSString *current = [SCIMobileConfigIDResolver manualLabelForBrokerID:brokerID value:value] ?: @"";
    UIAlertController *a = [UIAlertController alertControllerWithTitle:@"Manual label" message:[NSString stringWithFormat:@"0x%016llx", (unsigned long long)value] preferredStyle:UIAlertControllerStyleAlert];
    [a addTextFieldWithConfigurationHandler:^(UITextField *tf) { tf.placeholder = @"feature_name"; tf.text = current; }];
    [a addAction:[UIAlertAction actionWithTitle:@"Clear" style:UIAlertActionStyleDestructive handler:^(__unused UIAlertAction *action) { [SCIMobileConfigIDResolver setManualLabel:nil brokerID:brokerID value:value]; [self reloadRows]; }]];
    [a addAction:[UIAlertAction actionWithTitle:@"Cancel" style:UIAlertActionStyleCancel handler:nil]];
    [a addAction:[UIAlertAction actionWithTitle:@"Save" style:UIAlertActionStyleDefault handler:^(__unused UIAlertAction *action) { [SCIMobileConfigIDResolver setManualLabel:a.textFields.firstObject.text brokerID:brokerID value:value]; [self reloadRows]; }]];
    [self presentViewController:a animated:YES completion:nil];
}

@end
