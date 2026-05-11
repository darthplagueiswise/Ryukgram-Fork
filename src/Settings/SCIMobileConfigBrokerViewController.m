#import "SCIMobileConfigBrokerViewController.h"
#import "../Features/ExpFlags/SCIMobileConfigBrokerDescriptor.h"
#import "../Features/ExpFlags/SCIMobileConfigBrokerStore.h"
#import "../Features/ExpFlags/SCIDexKitNameResolver.h"
#import "../Features/ExpFlags/SCIMobileConfigIdNameMappingExporter.h"

extern void SCIInstallObjCMobileConfigGetterObserverForBrokerID(NSString *brokerID);
extern BOOL SCIObjCMobileConfigObserverIsInstalledForBrokerID(NSString *brokerID);
extern NSUInteger SCIObjCMobileConfigObserverInstalledCount(void);
extern void SCIObjCMobileConfigObserverInstallEnabled(void);

@interface SCIMCBrokerCell : UITableViewCell
@property (nonatomic, strong) UILabel *titleLabel;
@property (nonatomic, strong) UILabel *detailLabel2;
@property (nonatomic, strong) UISwitch *switchView;
@property (nonatomic, copy) void (^switchChanged)(BOOL on);
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
    _detailLabel2.numberOfLines = 5;
    _detailLabel2.translatesAutoresizingMaskIntoConstraints = NO;
    [self.contentView addSubview:_detailLabel2];
    _switchView = [UISwitch new];
    _switchView.translatesAutoresizingMaskIntoConstraints = NO;
    [_switchView addTarget:self action:@selector(onSwitch:) forControlEvents:UIControlEventValueChanged];
    [self.contentView addSubview:_switchView];
    [NSLayoutConstraint activateConstraints:@[
        [_switchView.centerYAnchor constraintEqualToAnchor:self.contentView.centerYAnchor],
        [_switchView.trailingAnchor constraintEqualToAnchor:self.contentView.trailingAnchor constant:-14],
        [_titleLabel.topAnchor constraintEqualToAnchor:self.contentView.topAnchor constant:10],
        [_titleLabel.leadingAnchor constraintEqualToAnchor:self.contentView.leadingAnchor constant:16],
        [_titleLabel.trailingAnchor constraintEqualToAnchor:_switchView.leadingAnchor constant:-10],
        [_detailLabel2.topAnchor constraintEqualToAnchor:_titleLabel.bottomAnchor constant:4],
        [_detailLabel2.leadingAnchor constraintEqualToAnchor:_titleLabel.leadingAnchor],
        [_detailLabel2.trailingAnchor constraintEqualToAnchor:_titleLabel.trailingAnchor],
        [_detailLabel2.bottomAnchor constraintEqualToAnchor:self.contentView.bottomAnchor constant:-10],
    ]];
    return self;
}
- (void)onSwitch:(UISwitch *)s { if (self.switchChanged) self.switchChanged(s.isOn); }
@end

@interface SCIMCBrokerValueViewController : UITableViewController
@property (nonatomic, strong) SCIMobileConfigBrokerDescriptor *broker;
@property (nonatomic, strong) NSArray<NSString *> *keys;
@property (nonatomic, strong) NSMutableDictionary<NSString *, NSDictionary *> *resolvedCache;
@end

@implementation SCIMCBrokerValueViewController
- (instancetype)initWithBroker:(SCIMobileConfigBrokerDescriptor *)broker {
    self = [super initWithStyle:UITableViewStyleInsetGrouped];
    if (self) { _broker = broker; self.title = broker.brokerID; _resolvedCache = [NSMutableDictionary dictionary]; }
    return self;
}
- (void)viewDidLoad {
    [super viewDidLoad];
    [self.tableView registerClass:SCIMCBrokerCell.class forCellReuseIdentifier:@"value"];
    self.navigationItem.rightBarButtonItems = @[
        [[UIBarButtonItem alloc] initWithTitle:@"Install" style:UIBarButtonItemStylePlain target:self action:@selector(installBroker)],
        [[UIBarButtonItem alloc] initWithTitle:@"Copy" style:UIBarButtonItemStylePlain target:self action:@selector(copySnapshot)]
    ];
    
    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(reloadKeys) name:@"SCIDexKitNameResolverRuntimeFeedDidUpdateNotification" object:nil];
    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(reloadKeys) name:@"SCIDexKitNameResolverDidUpdateNotification" object:nil];
    
    [self reloadKeys];
}

- (void)dealloc {
    [[NSNotificationCenter defaultCenter] removeObserver:self];
}
- (void)reloadKeys {
    self.keys = [SCIMobileConfigBrokerStore observedOverrideKeysForBrokerID:self.broker.brokerID];
    [self.resolvedCache removeAllObjects];
    [self.tableView reloadData];
}
- (void)installBroker {
    [SCIMobileConfigBrokerStore setBrokerHookEnabled:YES brokerID:self.broker.brokerID];
    SCIInstallObjCMobileConfigGetterObserverForBrokerID(self.broker.brokerID);
    [self reloadKeys];
}
- (void)copySnapshot {
    dispatch_async(dispatch_get_global_queue(QOS_CLASS_UTILITY, 0), ^{
        NSDictionary *snapshot = [SCIMobileConfigBrokerStore snapshotDictionary];
        NSData *data = [NSJSONSerialization dataWithJSONObject:snapshot options:NSJSONWritingPrettyPrinted error:nil];
        NSString *json = [[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding];
        dispatch_async(dispatch_get_main_queue(), ^{
            UIPasteboard.generalPasteboard.string = json;
        });
    });
}
- (void)applyResolvedMetadata:(NSDictionary *)resolved toCell:(SCIMCBrokerCell *)cell key:(NSString *)key value:(uint64_t)value brokerID:(NSString *)bid {
    NSString *title = [resolved[@"title"] isKindOfClass:NSString.class] ? resolved[@"title"] : @"";
    NSString *source = [resolved[@"source"] isKindOfClass:NSString.class] ? resolved[@"source"] : @"";
    NSString *detail = [resolved[@"resolvedDetail"] isKindOfClass:NSString.class] ? resolved[@"resolvedDetail"] : @"";
    NSString *callerSymbol = [resolved[@"callerSymbol"] isKindOfClass:NSString.class] ? resolved[@"callerSymbol"] : @"";
    BOOL runtimeObserved = [resolved[@"runtimeObserved"] respondsToSelector:@selector(boolValue)] ? [resolved[@"runtimeObserved"] boolValue] : NO;
    if (!title.length || [title hasPrefix:@"0x"]) {
        SCIDexKitResolvedName *r = [SCIDexKitNameResolver resolveBrokerID:bid value:value];
        if (r.title.length && r.confidence >= SCIDexKitNameConfidenceMedium) title = r.title;
    }
    if (!title.length) title = [NSString stringWithFormat:@"0x%016llx", (unsigned long long)value];
    NSMutableArray<NSString *> *detailParts = [NSMutableArray array];
    [detailParts addObject:[NSString stringWithFormat:@"%@ · system %@ · %@", self.broker.kindLabel, [SCIMobileConfigBrokerStore systemLabelForOverrideKey:key], [SCIMobileConfigBrokerStore overrideLabelForOverrideKey:key]]];
    if (source.length) [detailParts addObject:[NSString stringWithFormat:@"source %@%@", source, runtimeObserved ? @" · runtimeObserved" : @""]];
    if (callerSymbol.length) [detailParts addObject:[NSString stringWithFormat:@"caller %@", callerSymbol]];
    if (detail.length) [detailParts addObject:detail];
    cell.titleLabel.text = title;
    cell.detailLabel2.text = [detailParts componentsJoinedByString:@"\n"];
}

- (NSInteger)numberOfSectionsInTableView:(UITableView *)tableView { return 2; }
- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section { return section == 0 ? 1 : self.keys.count; }
- (NSString *)tableView:(UITableView *)tableView titleForHeaderInSection:(NSInteger)section { return section == 0 ? @"Broker" : @"Observed specifiers / gates"; }
- (NSString *)tableView:(UITableView *)tableView titleForFooterInSection:(NSInteger)section {
    if (section == 0) return @"Install enables ObjC pass-through observation. Overrides are only per observed specifier/gate below.";
    if (!self.keys.count) return @"No values observed yet. Tap Install, use the app path that reads this target, then return here.";
    return @"Switch reflects the observed system state until you change it. Changing it writes mcbr:<id>:<hex>; use System to remove the override.";
}
- (UITableViewCell *)basic:(NSString *)title detail:(NSString *)detail {
    UITableViewCell *c = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleSubtitle reuseIdentifier:nil];
    c.textLabel.text = title;
    c.detailTextLabel.text = detail;
    c.detailTextLabel.numberOfLines = 0;
    c.backgroundColor = UIColor.secondarySystemGroupedBackgroundColor;
    return c;
}
- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath {
    if (indexPath.section == 0) {
        BOOL installed = SCIObjCMobileConfigObserverIsInstalledForBrokerID(self.broker.brokerID);
        NSString *detail = [NSString stringWithFormat:@"%@ · %@ · observer %@ · observed %lu · overrides %lu\n%@\nLast status: %@",
                            self.broker.symbol,
                            self.broker.tierLabel,
                            installed ? @"live" : ([SCIMobileConfigBrokerStore isBrokerHookEnabledForID:self.broker.brokerID] ? @"pending" : @"off"),
                            (unsigned long)[SCIMobileConfigBrokerStore observedOverrideKeysForBrokerID:self.broker.brokerID].count,
                            (unsigned long)[SCIMobileConfigBrokerStore activeOverrideKeysForBrokerID:self.broker.brokerID].count,
                            self.broker.details ?: @"",
                            [SCIMobileConfigBrokerStore lastErrorForBrokerID:self.broker.brokerID] ?: @"none"];
        return [self basic:self.broker.displayName detail:detail];
    }
    SCIMCBrokerCell *cell = [tableView dequeueReusableCellWithIdentifier:@"value" forIndexPath:indexPath];
    NSString *key = self.keys[indexPath.row];
    NSString *bid = nil; uint64_t value = 0;
    [SCIMobileConfigBrokerStore parseOverrideKey:key brokerID:&bid value:&value];
    NSNumber *forced = [SCIMobileConfigBrokerStore overrideValueForKey:key];
    SCIMCBrokerBoolState state = [SCIMobileConfigBrokerStore effectiveStateForOverrideKey:key];
    NSDictionary *resolved = self.resolvedCache[key];
    if (resolved) {
        [self applyResolvedMetadata:resolved toCell:cell key:key value:value brokerID:bid];
    } else {
        cell.titleLabel.text = [NSString stringWithFormat:@"0x%016llx", (unsigned long long)value];
        cell.detailLabel2.text = [NSString stringWithFormat:@"%@ · system %@ · %@", self.broker.kindLabel, [SCIMobileConfigBrokerStore systemLabelForOverrideKey:key], [SCIMobileConfigBrokerStore overrideLabelForOverrideKey:key]];
    }
    [cell.switchView setOn:(state == SCIMCBrokerBoolStateOn) animated:NO];
    __weak typeof(self) weakSelf = self;
    cell.switchChanged = ^(BOOL on) {
        [SCIMobileConfigBrokerStore setBrokerHookEnabled:YES brokerID:weakSelf.broker.brokerID];
        [SCIMobileConfigBrokerStore setOverrideValue:@(on) forKey:key];
        SCIInstallObjCMobileConfigGetterObserverForBrokerID(weakSelf.broker.brokerID);
        [weakSelf reloadKeys];
    };
    cell.accessoryType = forced ? UITableViewCellAccessoryCheckmark : UITableViewCellAccessoryDisclosureIndicator;
    return cell;
}
- (void)tableView:(UITableView *)tableView willDisplayCell:(UITableViewCell *)tableViewCell forRowAtIndexPath:(NSIndexPath *)indexPath {
    if (indexPath.section != 1) return;
    NSString *key = self.keys[indexPath.row];
    if (self.resolvedCache[key]) return;
    NSString *bid = nil; uint64_t value = 0;
    [SCIMobileConfigBrokerStore parseOverrideKey:key brokerID:&bid value:&value];
    dispatch_async(dispatch_get_global_queue(QOS_CLASS_UTILITY, 0), ^{
        NSDictionary *resolved = [SCIMobileConfigBrokerStore resolvedMetadataForOverrideKey:key] ?: @{};
        dispatch_async(dispatch_get_main_queue(), ^{
            if (!resolved || self.resolvedCache[key]) return;
            self.resolvedCache[key] = resolved;
            SCIMCBrokerCell *cell = (SCIMCBrokerCell *)[tableView cellForRowAtIndexPath:indexPath];
            if (![cell isKindOfClass:SCIMCBrokerCell.class]) return;
            [self applyResolvedMetadata:resolved toCell:cell key:key value:value brokerID:bid];
        });
    });
}

- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath {
    [tableView deselectRowAtIndexPath:indexPath animated:YES];
    if (indexPath.section != 1) return;
    NSString *key = self.keys[indexPath.row];
    NSString *bid = nil; uint64_t value = 0;
    [SCIMobileConfigBrokerStore parseOverrideKey:key brokerID:&bid value:&value];
    NSDictionary *resolved = [SCIMobileConfigBrokerStore resolvedMetadataForOverrideKey:key];
    NSString *title = [resolved[@"title"] isKindOfClass:NSString.class] && [resolved[@"title"] length] ? resolved[@"title"] : [NSString stringWithFormat:@"0x%016llx", (unsigned long long)value];
    NSString *message = [NSString stringWithFormat:@"%@\nsource=%@\nruntimeObserved=%@\ncaller=%@ %@\n%@",
                         key,
                         [resolved[@"source"] isKindOfClass:NSString.class] ? resolved[@"source"] : @"",
                         [resolved[@"runtimeObserved"] respondsToSelector:@selector(boolValue)] && [resolved[@"runtimeObserved"] boolValue] ? @"YES" : @"NO",
                         [resolved[@"callerSymbol"] isKindOfClass:NSString.class] ? resolved[@"callerSymbol"] : @"",
                         [resolved[@"callerAddress"] isKindOfClass:NSString.class] ? resolved[@"callerAddress"] : @"",
                         [resolved[@"resolvedDetail"] isKindOfClass:NSString.class] ? resolved[@"resolvedDetail"] : @""];
    UIAlertController *a = [UIAlertController alertControllerWithTitle:title message:message preferredStyle:UIAlertControllerStyleActionSheet];
    [a addAction:[UIAlertAction actionWithTitle:@"Force ON" style:UIAlertActionStyleDefault handler:^(__unused UIAlertAction *x){ [SCIMobileConfigBrokerStore setBrokerHookEnabled:YES brokerID:self.broker.brokerID]; [SCIMobileConfigBrokerStore setOverrideValue:@YES forKey:key]; SCIInstallObjCMobileConfigGetterObserverForBrokerID(self.broker.brokerID); [self reloadKeys]; }]];
    [a addAction:[UIAlertAction actionWithTitle:@"Force OFF" style:UIAlertActionStyleDefault handler:^(__unused UIAlertAction *x){ [SCIMobileConfigBrokerStore setBrokerHookEnabled:YES brokerID:self.broker.brokerID]; [SCIMobileConfigBrokerStore setOverrideValue:@NO forKey:key]; SCIInstallObjCMobileConfigGetterObserverForBrokerID(self.broker.brokerID); [self reloadKeys]; }]];
    [a addAction:[UIAlertAction actionWithTitle:@"System" style:UIAlertActionStyleDefault handler:^(__unused UIAlertAction *x){ [SCIMobileConfigBrokerStore setOverrideValue:nil forKey:key]; [self reloadKeys]; }]];
    [a addAction:[UIAlertAction actionWithTitle:@"Copy key" style:UIAlertActionStyleDefault handler:^(__unused UIAlertAction *x){ UIPasteboard.generalPasteboard.string = key; }]];
    [a addAction:[UIAlertAction actionWithTitle:@"Copy resolved JSON" style:UIAlertActionStyleDefault handler:^(__unused UIAlertAction *x){
        NSMutableDictionary *copy = [[SCIMobileConfigBrokerStore resolvedMetadataForOverrideKey:key] mutableCopy];
        copy[@"key"] = key ?: @"";
        NSData *data = [NSJSONSerialization dataWithJSONObject:copy options:NSJSONWritingPrettyPrinted error:nil];
        UIPasteboard.generalPasteboard.string = [[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding];
    }]];
    [a addAction:[UIAlertAction actionWithTitle:@"Cancel" style:UIAlertActionStyleCancel handler:nil]];
    UITableViewCell *cell = [tableView cellForRowAtIndexPath:indexPath];
    if (a.popoverPresentationController) { a.popoverPresentationController.sourceView = cell; a.popoverPresentationController.sourceRect = cell.bounds; }
    [self presentViewController:a animated:YES completion:nil];
}
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
    self.title = @"MC ObjC Observers";
    self.view.backgroundColor = UIColor.systemGroupedBackgroundColor;
    [SCIMobileConfigBrokerStore registerDefaultsAndMigrate];
    self.filter = [[UISegmentedControl alloc] initWithItems:@[@"Core", @"All", @"Observed", @"Forced", @"Live"]];
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
        if (f == 0 && d.kind != SCIMCBrokerKindPrimary && d.kind != SCIMCBrokerKindComplement) continue;
        if (f == 2 && [SCIMobileConfigBrokerStore observedOverrideKeysForBrokerID:d.brokerID].count == 0) continue;
        if (f == 3 && [SCIMobileConfigBrokerStore activeOverrideKeysForBrokerID:d.brokerID].count == 0) continue;
        if (f == 4 && !SCIObjCMobileConfigObserverIsInstalledForBrokerID(d.brokerID)) continue;
        [items addObject:d];
    }
    self.rows = items;
    self.footerLabel.text = [NSString stringWithFormat:@"Namespace: mcbr:<id>:<hex> / mcob:<id>:<hex> · ObjC hooks=%lu · overrides=%lu · observed=%lu", (unsigned long)SCIObjCMobileConfigObserverInstalledCount(), (unsigned long)[SCIMobileConfigBrokerStore activeOverrideKeys].count, (unsigned long)[SCIMobileConfigBrokerStore observedOverrideKeys].count];
    [self.tableView reloadData];
}
- (void)installEnabled { SCIObjCMobileConfigObserverInstallEnabled(); [self reloadRows]; }
- (void)resetOverrides { [SCIMobileConfigBrokerStore resetAllBrokerOverrides]; [self reloadRows]; }

- (NSInteger)numberOfSectionsInTableView:(UITableView *)tableView { return 2; }
- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section { return section == 0 ? self.rows.count : 3; }
- (NSString *)tableView:(UITableView *)tableView titleForHeaderInSection:(NSInteger)section { return section == 0 ? @"FBSharedFramework ObjC observer targets" : @"Debug"; }
- (NSString *)tableView:(UITableView *)tableView titleForFooterInSection:(NSInteger)section { return section == 0 ? @"Switch enables pass-through observation. Tap row to view observed specifiers/gates and force individual values." : nil; }
- (UITableViewCell *)basicCell:(NSString *)title detail:(NSString *)detail {
    UITableViewCell *cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleSubtitle reuseIdentifier:nil];
    cell.textLabel.text = title;
    cell.detailTextLabel.text = detail;
    cell.detailTextLabel.numberOfLines = 0;
    cell.backgroundColor = UIColor.secondarySystemGroupedBackgroundColor;
    return cell;
}
- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath {
    if (indexPath.section == 1) {
        if (indexPath.row == 0) return [self basicCell:@"Copy resolved snapshot" detail:@"Tap to copy current mcbr/mcob state as JSON enriched by SCIDexKitNameResolver: resolvedName, title, source, runtimeObserved, callerImage, callerSymbol and callerAddress."];
        if (indexPath.row == 1) return [self basicCell:@"Copy MobileConfig asset report" detail:@"Reports packaged Android params_map/params_names experiment files, candidate iOS paths, file sizes, SHA-256 hashes, native symbol probe, and id_name_mapping candidates. No hooks are installed."];
        return [self basicCell:@"Copy assets to runtime paths" detail:@"Manual experiment: copies packaged params_map/params_names files into container/app candidate mobileconfig_res paths, then copies the full JSON report. Does not call C++ or TryUpdate."];
    }
    SCIMCBrokerCell *cell = [tableView dequeueReusableCellWithIdentifier:@"broker" forIndexPath:indexPath];
    SCIMobileConfigBrokerDescriptor *d = self.rows[indexPath.row];
    BOOL installed = SCIObjCMobileConfigObserverIsInstalledForBrokerID(d.brokerID);
    BOOL hookEnabled = [SCIMobileConfigBrokerStore isBrokerHookEnabledForID:d.brokerID];
    NSUInteger observed = [SCIMobileConfigBrokerStore observedOverrideKeysForBrokerID:d.brokerID].count;
    NSUInteger forced = [SCIMobileConfigBrokerStore activeOverrideKeysForBrokerID:d.brokerID].count;
    cell.titleLabel.text = [NSString stringWithFormat:@"%@  [%@]", d.displayName, d.brokerID];
    cell.detailLabel2.text = [NSString stringWithFormat:@"%@ · %@ · observer %@ · observed %lu · forced %lu · hits %lu/%lu", d.tierLabel, d.kindLabel, installed ? @"live" : (hookEnabled ? @"pending" : @"off"), (unsigned long)observed, (unsigned long)forced, (unsigned long)[SCIMobileConfigBrokerStore hitCountForBrokerID:d.brokerID], (unsigned long)[SCIMobileConfigBrokerStore forcedHitCountForBrokerID:d.brokerID]];
    [cell.switchView setOn:hookEnabled animated:NO];
    __weak typeof(self) weakSelf = self;
    cell.switchChanged = ^(BOOL on) {
        [SCIMobileConfigBrokerStore setBrokerHookEnabled:on brokerID:d.brokerID];
        if (on) SCIInstallObjCMobileConfigGetterObserverForBrokerID(d.brokerID);
        [weakSelf reloadRows];
    };
    cell.accessoryType = UITableViewCellAccessoryDisclosureIndicator;
    return cell;
}
- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath {
    [tableView deselectRowAtIndexPath:indexPath animated:YES];
    if (indexPath.section == 1) {
        if (indexPath.row == 1 || indexPath.row == 2) {
            dispatch_async(dispatch_get_global_queue(QOS_CLASS_UTILITY, 0), ^{
                NSDictionary *result = (indexPath.row == 2) ? [SCIMobileConfigIdNameMappingExporter copyMobileConfigAssetExperimentFiles] : [SCIMobileConfigIdNameMappingExporter mobileConfigAssetExperimentReport];
                NSData *data = [NSJSONSerialization dataWithJSONObject:result ?: @{} options:NSJSONWritingPrettyPrinted error:nil];
                NSString *json = [[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding];
                dispatch_async(dispatch_get_main_queue(), ^{
                    UIPasteboard.generalPasteboard.string = json;
                    [self reloadRows];
                });
            });
            return;
        }
        dispatch_async(dispatch_get_global_queue(QOS_CLASS_UTILITY, 0), ^{
            NSDictionary *snapshot = [SCIMobileConfigBrokerStore snapshotDictionary];
            NSData *data = [NSJSONSerialization dataWithJSONObject:snapshot options:NSJSONWritingPrettyPrinted error:nil];
            NSString *json = [[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding];
            dispatch_async(dispatch_get_main_queue(), ^{
                UIPasteboard.generalPasteboard.string = json;
            });
        });
        return;
    }
    SCIMobileConfigBrokerDescriptor *d = self.rows[indexPath.row];
    [self.navigationController pushViewController:[[SCIMCBrokerValueViewController alloc] initWithBroker:d] animated:YES];
}
@end
