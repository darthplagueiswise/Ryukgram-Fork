#import "SCIMobileConfigBrokerViewController.h"
#import "../Features/ExpFlags/SCIMobileConfigBrokerDescriptor.h"
#import "../Features/ExpFlags/SCIMobileConfigBrokerStore.h"
#import "../Features/ExpFlags/SCIMobileConfigBrokerRouter.h"

@interface SCIMCBrokerCell : UITableViewCell
@property UILabel *titleLabel;
@property UILabel *detailLabel2;
@property UISwitch *toggle;
@property UIButton *systemButton;
@property (copy) void (^changed)(BOOL on);
@property (copy) void (^systemPressed)(void);
@end

@implementation SCIMCBrokerCell
- (instancetype)initWithStyle:(UITableViewCellStyle)style reuseIdentifier:(NSString *)reuseIdentifier {
    self = [super initWithStyle:style reuseIdentifier:reuseIdentifier];
    if (!self) return nil;
    self.backgroundColor = UIColor.secondarySystemGroupedBackgroundColor;
    self.contentView.backgroundColor = self.backgroundColor;
    _titleLabel = [UILabel new];
    _titleLabel.font = [UIFont monospacedSystemFontOfSize:12 weight:UIFontWeightRegular];
    _titleLabel.numberOfLines = 2;
    _titleLabel.translatesAutoresizingMaskIntoConstraints = NO;
    [self.contentView addSubview:_titleLabel];
    _detailLabel2 = [UILabel new];
    _detailLabel2.font = [UIFont systemFontOfSize:11];
    _detailLabel2.textColor = UIColor.secondaryLabelColor;
    _detailLabel2.numberOfLines = 2;
    _detailLabel2.translatesAutoresizingMaskIntoConstraints = NO;
    [self.contentView addSubview:_detailLabel2];
    _toggle = [UISwitch new];
    _toggle.translatesAutoresizingMaskIntoConstraints = NO;
    [_toggle addTarget:self action:@selector(onSwitch) forControlEvents:UIControlEventValueChanged];
    [self.contentView addSubview:_toggle];
    _systemButton = [UIButton buttonWithType:UIButtonTypeSystem];
    [_systemButton setTitle:@"System" forState:UIControlStateNormal];
    _systemButton.titleLabel.font = [UIFont systemFontOfSize:12 weight:UIFontWeightSemibold];
    _systemButton.translatesAutoresizingMaskIntoConstraints = NO;
    [_systemButton addTarget:self action:@selector(onSystem) forControlEvents:UIControlEventTouchUpInside];
    [self.contentView addSubview:_systemButton];
    [NSLayoutConstraint activateConstraints:@[
        [_toggle.centerYAnchor constraintEqualToAnchor:self.contentView.centerYAnchor],
        [_toggle.trailingAnchor constraintEqualToAnchor:self.contentView.trailingAnchor constant:-12],
        [_systemButton.centerYAnchor constraintEqualToAnchor:_toggle.centerYAnchor],
        [_systemButton.trailingAnchor constraintEqualToAnchor:_toggle.leadingAnchor constant:-10],
        [_titleLabel.topAnchor constraintEqualToAnchor:self.contentView.topAnchor constant:10],
        [_titleLabel.leadingAnchor constraintEqualToAnchor:self.contentView.leadingAnchor constant:16],
        [_titleLabel.trailingAnchor constraintEqualToAnchor:_systemButton.leadingAnchor constant:-8],
        [_detailLabel2.topAnchor constraintEqualToAnchor:_titleLabel.bottomAnchor constant:4],
        [_detailLabel2.leadingAnchor constraintEqualToAnchor:_titleLabel.leadingAnchor],
        [_detailLabel2.trailingAnchor constraintEqualToAnchor:_titleLabel.trailingAnchor],
        [_detailLabel2.bottomAnchor constraintEqualToAnchor:self.contentView.bottomAnchor constant:-10]
    ]];
    return self;
}
- (void)onSwitch { if (self.changed) self.changed(self.toggle.isOn); }
- (void)onSystem { if (self.systemPressed) self.systemPressed(); }
@end

@interface SCIMobileConfigBrokerViewController () <UITableViewDataSource, UITableViewDelegate, UISearchBarDelegate>
@property UITableView *tableView;
@property UISegmentedControl *mode;
@property UISearchBar *search;
@property UILabel *footer;
@property NSArray *rows;
@property NSString *query;
@end

@implementation SCIMobileConfigBrokerViewController

- (void)viewDidLoad {
    [super viewDidLoad];
    self.title = @"MC Brokers v2";
    self.view.backgroundColor = UIColor.systemGroupedBackgroundColor;
    [SCIMobileConfigBrokerStore registerDefaults];

    self.mode = [[UISegmentedControl alloc] initWithItems:@[@"Brokers", @"Observed", @"Forced"]];
    self.mode.selectedSegmentIndex = 0;
    [self.mode addTarget:self action:@selector(reload) forControlEvents:UIControlEventValueChanged];
    self.mode.translatesAutoresizingMaskIntoConstraints = NO;
    [self.view addSubview:self.mode];

    self.search = [UISearchBar new];
    self.search.searchBarStyle = UISearchBarStyleMinimal;
    self.search.placeholder = @"Search broker/symbol/key";
    self.search.autocapitalizationType = UITextAutocapitalizationTypeNone;
    self.search.autocorrectionType = UITextAutocorrectionTypeNo;
    self.search.delegate = self;
    self.search.translatesAutoresizingMaskIntoConstraints = NO;
    [self.view addSubview:self.search];

    self.footer = [UILabel new];
    self.footer.font = [UIFont systemFontOfSize:11];
    self.footer.textColor = UIColor.secondaryLabelColor;
    self.footer.numberOfLines = 0;
    self.footer.translatesAutoresizingMaskIntoConstraints = NO;
    [self.view addSubview:self.footer];

    self.tableView = [[UITableView alloc] initWithFrame:CGRectZero style:UITableViewStyleInsetGrouped];
    self.tableView.backgroundColor = UIColor.systemGroupedBackgroundColor;
    self.tableView.dataSource = self;
    self.tableView.delegate = self;
    self.tableView.rowHeight = UITableViewAutomaticDimension;
    self.tableView.estimatedRowHeight = 72;
    [self.tableView registerClass:SCIMCBrokerCell.class forCellReuseIdentifier:@"cell"];
    self.tableView.translatesAutoresizingMaskIntoConstraints = NO;
    [self.view addSubview:self.tableView];

    self.navigationItem.rightBarButtonItem = [[UIBarButtonItem alloc] initWithTitle:@"Refresh" style:UIBarButtonItemStylePlain target:self action:@selector(reload)];

    UILayoutGuide *g = self.view.safeAreaLayoutGuide;
    [NSLayoutConstraint activateConstraints:@[
        [self.mode.topAnchor constraintEqualToAnchor:g.topAnchor constant:8],
        [self.mode.leadingAnchor constraintEqualToAnchor:g.leadingAnchor constant:12],
        [self.mode.trailingAnchor constraintEqualToAnchor:g.trailingAnchor constant:-12],
        [self.search.topAnchor constraintEqualToAnchor:self.mode.bottomAnchor constant:4],
        [self.search.leadingAnchor constraintEqualToAnchor:g.leadingAnchor constant:8],
        [self.search.trailingAnchor constraintEqualToAnchor:g.trailingAnchor constant:-8],
        [self.footer.topAnchor constraintEqualToAnchor:self.search.bottomAnchor constant:2],
        [self.footer.leadingAnchor constraintEqualToAnchor:g.leadingAnchor constant:14],
        [self.footer.trailingAnchor constraintEqualToAnchor:g.trailingAnchor constant:-14],
        [self.tableView.topAnchor constraintEqualToAnchor:self.footer.bottomAnchor constant:4],
        [self.tableView.leadingAnchor constraintEqualToAnchor:g.leadingAnchor],
        [self.tableView.trailingAnchor constraintEqualToAnchor:g.trailingAnchor],
        [self.tableView.bottomAnchor constraintEqualToAnchor:g.bottomAnchor]
    ]];
    [self reload];
}

- (NSString *)haystackForRow:(id)row {
    if ([row isKindOfClass:SCIMobileConfigBrokerDescriptor.class]) {
        SCIMobileConfigBrokerDescriptor *d = row;
        return [NSString stringWithFormat:@"%@ %@ %@ %@ %@", d.brokerID, d.symbol, d.displayName, d.details, [d tierLabel]].lowercaseString;
    }
    return [row description].lowercaseString;
}

- (void)reload {
    NSMutableArray *out = [NSMutableArray array];
    if (self.mode.selectedSegmentIndex == 0) {
        [out addObjectsFromArray:[SCIMobileConfigBrokerDescriptor allDescriptors]];
    } else if (self.mode.selectedSegmentIndex == 1) {
        [out addObjectsFromArray:[SCIMobileConfigBrokerStore observedOverrideKeys]];
    } else {
        [out addObjectsFromArray:[SCIMobileConfigBrokerStore activeOverrideKeys]];
    }
    NSString *q = self.query.lowercaseString ?: @"";
    if (q.length) {
        NSMutableArray *filtered = [NSMutableArray array];
        for (id row in out) if ([[self haystackForRow:row] containsString:q]) [filtered addObject:row];
        out = filtered;
    }
    self.rows = out;
    self.footer.text = [NSString stringWithFormat:@"%@ · %@ · rows=%lu", SCIMCBrokerRuntimeSummary(), self.mode.selectedSegmentIndex == 0 ? @"hook enable per broker" : @"per specifier/gate override", (unsigned long)out.count];
    [self.tableView reloadData];
}

- (NSInteger)numberOfSectionsInTableView:(UITableView *)tableView { return 1; }
- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section { return self.rows.count; }

- (void)configureBrokerCell:(SCIMCBrokerCell *)cell descriptor:(SCIMobileConfigBrokerDescriptor *)d {
    cell.titleLabel.text = [NSString stringWithFormat:@"%@ · %@", d.brokerID, d.displayName];
    NSString *err = [SCIMobileConfigBrokerStore lastErrorForBrokerID:d.brokerID];
    cell.detailLabel2.text = [NSString stringWithFormat:@"%@ · %@ · hook=%@ · installed=%@ · xrefs=%lu%@%@", d.symbol, [d tierLabel], [SCIMobileConfigBrokerStore hookEnabledForBrokerID:d.brokerID] ? @"ON" : @"OFF", SCIMCBrokerIsInstalled(d.brokerID) ? @"YES" : @"NO", (unsigned long)d.xrefCount, err.length ? @" · err=" : @"", err ?: @""];
    [cell.toggle setOn:[SCIMobileConfigBrokerStore hookEnabledForBrokerID:d.brokerID] animated:NO];
    cell.systemButton.hidden = YES;
    __weak typeof(self) weakSelf = self;
    cell.changed = ^(BOOL on) {
        [SCIMobileConfigBrokerStore setHookEnabled:on forBrokerID:d.brokerID];
        if (on) SCIMCBrokerInstall(d, nil);
        [weakSelf reload];
    };
    cell.systemPressed = nil;
}

- (void)configureKeyCell:(SCIMCBrokerCell *)cell key:(NSString *)key {
    NSNumber *forced = [SCIMobileConfigBrokerStore overrideValueForKey:key];
    NSNumber *observed = [SCIMobileConfigBrokerStore observedValueForOverrideKey:key];
    NSString *bid = nil, *image = nil, *symbol = nil, *kind = nil;
    uint64_t value = 0;
    [SCIMobileConfigBrokerStore parseOverrideKey:key brokerID:&bid image:&image symbol:&symbol kind:&kind value:&value];
    cell.titleLabel.text = [NSString stringWithFormat:@"%@:%@:%016llx", bid.length ? bid : symbol, kind ?: @"?", (unsigned long long)value];
    cell.detailLabel2.text = [NSString stringWithFormat:@"%@ · observed=%@ · override=%@", key, observed ? (observed.boolValue ? @"ON" : @"OFF") : @"unknown", forced ? (forced.boolValue ? @"ON" : @"OFF") : @"System"];
    [cell.toggle setOn:forced ? forced.boolValue : (observed ? observed.boolValue : NO) animated:NO];
    cell.systemButton.hidden = NO;
    cell.systemButton.enabled = forced != nil;
    cell.systemButton.alpha = forced ? 1.0 : 0.35;
    __weak typeof(self) weakSelf = self;
    cell.changed = ^(BOOL on) { [SCIMobileConfigBrokerStore setOverrideValue:@(on) forKey:key]; [weakSelf reload]; };
    cell.systemPressed = ^{ [SCIMobileConfigBrokerStore setOverrideValue:nil forKey:key]; [weakSelf reload]; };
}

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath {
    SCIMCBrokerCell *cell = [tableView dequeueReusableCellWithIdentifier:@"cell" forIndexPath:indexPath];
    id row = self.rows[indexPath.row];
    if ([row isKindOfClass:SCIMobileConfigBrokerDescriptor.class]) [self configureBrokerCell:cell descriptor:row];
    else [self configureKeyCell:cell key:row];
    return cell;
}

- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath {
    [tableView deselectRowAtIndexPath:indexPath animated:YES];
    id row = self.rows[indexPath.row];
    if ([row isKindOfClass:SCIMobileConfigBrokerDescriptor.class]) {
        SCIMobileConfigBrokerDescriptor *d = row;
        NSString *msg = [NSString stringWithFormat:@"%@\n\nSymbol: %@\nImage: %@\nVM: 0x%lx\nXrefs: %lu\nKind: %@\nTier: %@\n\n%@", d.displayName, d.symbol, d.imageName, (unsigned long)d.vmAddress, (unsigned long)d.xrefCount, [d kindLabel], [d tierLabel], d.details];
        UIAlertController *a = [UIAlertController alertControllerWithTitle:d.brokerID message:msg preferredStyle:UIAlertControllerStyleActionSheet];
        [a addAction:[UIAlertAction actionWithTitle:@"Enable hook/observe" style:UIAlertActionStyleDefault handler:^(__unused UIAlertAction *x){ [SCIMobileConfigBrokerStore setHookEnabled:YES forBrokerID:d.brokerID]; SCIMCBrokerInstall(d, nil); [self reload]; }]];
        [a addAction:[UIAlertAction actionWithTitle:@"Disable hook on next launch" style:UIAlertActionStyleDefault handler:^(__unused UIAlertAction *x){ [SCIMobileConfigBrokerStore setHookEnabled:NO forBrokerID:d.brokerID]; [self reload]; }]];
        [a addAction:[UIAlertAction actionWithTitle:@"Copy symbol" style:UIAlertActionStyleDefault handler:^(__unused UIAlertAction *x){ UIPasteboard.generalPasteboard.string = d.symbol; }]];
        [a addAction:[UIAlertAction actionWithTitle:@"Cancel" style:UIAlertActionStyleCancel handler:nil]];
        UITableViewCell *cell = [tableView cellForRowAtIndexPath:indexPath];
        if (a.popoverPresentationController) { a.popoverPresentationController.sourceView = cell; a.popoverPresentationController.sourceRect = cell.bounds; }
        [self presentViewController:a animated:YES completion:nil];
    } else {
        NSString *key = row;
        UIAlertController *a = [UIAlertController alertControllerWithTitle:@"C bool override" message:key preferredStyle:UIAlertControllerStyleActionSheet];
        [a addAction:[UIAlertAction actionWithTitle:@"Force ON" style:UIAlertActionStyleDefault handler:^(__unused UIAlertAction *x){ [SCIMobileConfigBrokerStore setOverrideValue:@YES forKey:key]; [self reload]; }]];
        [a addAction:[UIAlertAction actionWithTitle:@"Force OFF" style:UIAlertActionStyleDefault handler:^(__unused UIAlertAction *x){ [SCIMobileConfigBrokerStore setOverrideValue:@NO forKey:key]; [self reload]; }]];
        [a addAction:[UIAlertAction actionWithTitle:@"System" style:UIAlertActionStyleDefault handler:^(__unused UIAlertAction *x){ [SCIMobileConfigBrokerStore setOverrideValue:nil forKey:key]; [self reload]; }]];
        [a addAction:[UIAlertAction actionWithTitle:@"Copy key" style:UIAlertActionStyleDefault handler:^(__unused UIAlertAction *x){ UIPasteboard.generalPasteboard.string = key; }]];
        [a addAction:[UIAlertAction actionWithTitle:@"Cancel" style:UIAlertActionStyleCancel handler:nil]];
        UITableViewCell *cell = [tableView cellForRowAtIndexPath:indexPath];
        if (a.popoverPresentationController) { a.popoverPresentationController.sourceView = cell; a.popoverPresentationController.sourceRect = cell.bounds; }
        [self presentViewController:a animated:YES completion:nil];
    }
}

- (void)searchBar:(UISearchBar *)searchBar textDidChange:(NSString *)searchText { self.query = searchText ?: @""; [self reload]; }
- (void)searchBarSearchButtonClicked:(UISearchBar *)searchBar { [searchBar resignFirstResponder]; }
@end
