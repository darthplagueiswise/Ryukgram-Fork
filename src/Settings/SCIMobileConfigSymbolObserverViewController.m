#import "SCIMobileConfigSymbolObserverViewController.h"
#import "../Features/ExpFlags/SCIExpFlags.h"
#import <objc/runtime.h>

static NSString *const kSCIMCSymbolAll = @"All";

@interface SCIMobileConfigSymbolObserverViewController () <UITableViewDataSource, UITableViewDelegate, UISearchBarDelegate>
@property (nonatomic, strong) UISegmentedControl *sourceSeg;
@property (nonatomic, strong) UISearchBar *searchBar;
@property (nonatomic, strong) UITableView *tableView;
@property (nonatomic, strong) UILabel *emptyLabel;
@property (nonatomic, copy) NSString *query;
@property (nonatomic, strong) NSArray<NSString *> *sources;
@property (nonatomic, strong) NSArray<SCIExpMCObservation *> *rows;
@end

@implementation SCIMobileConfigSymbolObserverViewController

- (void)viewDidLoad {
    [super viewDidLoad];
    self.title = @"MC Symbol Observer";
    self.view.backgroundColor = UIColor.systemBackgroundColor;
    self.sources = @[
        kSCIMCSymbolAll,
        @"MCI",
        @"METAExtensions",
        @"MCQMEM",
        @"MEM Capability",
        @"MEM DevConfig",
        @"MEM Platform",
        @"MEM Protocol"
    ];

    self.sourceSeg = [[UISegmentedControl alloc] initWithItems:self.sources];
    self.sourceSeg.selectedSegmentIndex = 0;
    self.sourceSeg.translatesAutoresizingMaskIntoConstraints = NO;
    [self.sourceSeg addTarget:self action:@selector(filterChanged) forControlEvents:UIControlEventValueChanged];
    [self.view addSubview:self.sourceSeg];

    self.searchBar = [UISearchBar new];
    self.searchBar.searchBarStyle = UISearchBarStyleMinimal;
    self.searchBar.placeholder = @"Search symbol / args / candidate";
    self.searchBar.autocapitalizationType = UITextAutocapitalizationTypeNone;
    self.searchBar.autocorrectionType = UITextAutocorrectionTypeNo;
    self.searchBar.delegate = self;
    self.searchBar.translatesAutoresizingMaskIntoConstraints = NO;
    [self.view addSubview:self.searchBar];

    self.tableView = [[UITableView alloc] initWithFrame:CGRectZero style:UITableViewStylePlain];
    self.tableView.dataSource = self;
    self.tableView.delegate = self;
    self.tableView.keyboardDismissMode = UIScrollViewKeyboardDismissModeOnDrag;
    self.tableView.translatesAutoresizingMaskIntoConstraints = NO;
    [self.view addSubview:self.tableView];

    self.emptyLabel = [UILabel new];
    self.emptyLabel.translatesAutoresizingMaskIntoConstraints = NO;
    self.emptyLabel.textColor = UIColor.secondaryLabelColor;
    self.emptyLabel.font = [UIFont systemFontOfSize:14];
    self.emptyLabel.textAlignment = NSTextAlignmentCenter;
    self.emptyLabel.numberOfLines = 0;
    [self.view addSubview:self.emptyLabel];

    UILayoutGuide *g = self.view.safeAreaLayoutGuide;
    [NSLayoutConstraint activateConstraints:@[
        [self.sourceSeg.topAnchor constraintEqualToAnchor:g.topAnchor constant:8],
        [self.sourceSeg.leadingAnchor constraintEqualToAnchor:g.leadingAnchor constant:12],
        [self.sourceSeg.trailingAnchor constraintEqualToAnchor:g.trailingAnchor constant:-12],

        [self.searchBar.topAnchor constraintEqualToAnchor:self.sourceSeg.bottomAnchor constant:4],
        [self.searchBar.leadingAnchor constraintEqualToAnchor:g.leadingAnchor constant:8],
        [self.searchBar.trailingAnchor constraintEqualToAnchor:g.trailingAnchor constant:-8],

        [self.tableView.topAnchor constraintEqualToAnchor:self.searchBar.bottomAnchor],
        [self.tableView.leadingAnchor constraintEqualToAnchor:g.leadingAnchor],
        [self.tableView.trailingAnchor constraintEqualToAnchor:g.trailingAnchor],
        [self.tableView.bottomAnchor constraintEqualToAnchor:g.bottomAnchor],

        [self.emptyLabel.centerXAnchor constraintEqualToAnchor:self.tableView.centerXAnchor],
        [self.emptyLabel.centerYAnchor constraintEqualToAnchor:self.tableView.centerYAnchor],
        [self.emptyLabel.leadingAnchor constraintEqualToAnchor:g.leadingAnchor constant:24],
        [self.emptyLabel.trailingAnchor constraintEqualToAnchor:g.trailingAnchor constant:-24],
    ]];
}

- (void)viewWillAppear:(BOOL)animated {
    [super viewWillAppear:animated];
    [self refresh];
}

- (void)filterChanged { [self refresh]; }

- (void)refresh {
    self.rows = [self filteredRows];
    [self.tableView reloadData];
    self.emptyLabel.hidden = self.rows.count > 0;
    self.emptyLabel.text = self.query.length ? @"No matching MobileConfig symbol observations yet." : @"Browse Instagram to populate observed MobileConfig C boolean symbols.";
}

- (NSArray<SCIExpMCObservation *> *)filteredRows {
    NSArray<SCIExpMCObservation *> *all = [SCIExpFlags allMCObservations];
    NSMutableArray<SCIExpMCObservation *> *out = [NSMutableArray array];
    NSString *selected = self.sources[(NSUInteger)MAX(0, self.sourceSeg.selectedSegmentIndex)];
    NSString *q = self.query.lowercaseString ?: @"";

    for (SCIExpMCObservation *o in all) {
        NSString *detail = o.lastDefault ?: @"";
        if (![self isRuntimeSymbolObservation:detail]) continue;
        NSString *symbol = [self symbolNameFromDetail:detail];
        if (![self symbol:symbol matchesSource:selected]) continue;
        NSString *haystack = [NSString stringWithFormat:@"%@ %@ 0x%016llx %llu", symbol ?: @"", detail, o.paramID, o.paramID].lowercaseString;
        if (q.length && ![haystack containsString:q]) continue;
        [out addObject:o];
    }

    return [out sortedArrayUsingComparator:^NSComparisonResult(SCIExpMCObservation *a, SCIExpMCObservation *b) {
        if (a.hitCount != b.hitCount) return a.hitCount > b.hitCount ? NSOrderedAscending : NSOrderedDescending;
        NSString *as = [self symbolNameFromDetail:a.lastDefault ?: @""] ?: @"";
        NSString *bs = [self symbolNameFromDetail:b.lastDefault ?: @""] ?: @"";
        NSComparisonResult r = [as compare:bs];
        if (r != NSOrderedSame) return r;
        if (a.paramID < b.paramID) return NSOrderedAscending;
        if (a.paramID > b.paramID) return NSOrderedDescending;
        return NSOrderedSame;
    }];
}

- (BOOL)isRuntimeSymbolObservation:(NSString *)detail {
    return [detail containsString:@"_MCIMobileConfigGetBoolean"] ||
           [detail containsString:@"_METAExtensionsExperimentGetBoolean"] ||
           [detail containsString:@"_MCQMEMMobileConfigCqlGetBooleanInternalDoNotUseOrMock"] ||
           [detail containsString:@"_MEMMobileConfigFeatureCapabilityGetBoolean_Internal_DoNotUseOrMock"] ||
           [detail containsString:@"_MEMMobileConfigFeatureDevConfigGetBoolean_Internal_DoNotUseOrMock"] ||
           [detail containsString:@"_MEMMobileConfigPlatformGetBoolean"] ||
           [detail containsString:@"_MEMMobileConfigProtocolExperimentGetBoolean_Internal_DoNotUseOrMock"];
}

- (NSString *)symbolNameFromDetail:(NSString *)detail {
    NSArray<NSString *> *symbols = @[
        @"_MCIMobileConfigGetBoolean",
        @"_METAExtensionsExperimentGetBooleanWithoutExposure",
        @"_METAExtensionsExperimentGetBoolean",
        @"_MCQMEMMobileConfigCqlGetBooleanInternalDoNotUseOrMock",
        @"_MEMMobileConfigFeatureCapabilityGetBoolean_Internal_DoNotUseOrMock",
        @"_MEMMobileConfigFeatureDevConfigGetBoolean_Internal_DoNotUseOrMock",
        @"_MEMMobileConfigPlatformGetBoolean",
        @"_MEMMobileConfigProtocolExperimentGetBoolean_Internal_DoNotUseOrMock"
    ];
    for (NSString *s in symbols) if ([detail containsString:s]) return s;
    return @"Unknown MC symbol";
}

- (BOOL)symbol:(NSString *)symbol matchesSource:(NSString *)source {
    if (!source.length || [source isEqualToString:kSCIMCSymbolAll]) return YES;
    if ([source isEqualToString:@"MCI"]) return [symbol containsString:@"MCIMobileConfigGetBoolean"];
    if ([source isEqualToString:@"METAExtensions"]) return [symbol containsString:@"METAExtensionsExperimentGetBoolean"];
    if ([source isEqualToString:@"MCQMEM"]) return [symbol containsString:@"MCQMEMMobileConfigCqlGetBoolean"];
    if ([source isEqualToString:@"MEM Capability"]) return [symbol containsString:@"FeatureCapability"];
    if ([source isEqualToString:@"MEM DevConfig"]) return [symbol containsString:@"FeatureDevConfig"];
    if ([source isEqualToString:@"MEM Platform"]) return [symbol containsString:@"PlatformGetBoolean"];
    if ([source isEqualToString:@"MEM Protocol"]) return [symbol containsString:@"ProtocolExperiment"];
    return YES;
}

- (NSString *)cleanDetail:(NSString *)detail {
    NSString *symbol = [self symbolNameFromDetail:detail] ?: @"";
    NSString *clean = detail;
    if (symbol.length) clean = [clean stringByReplacingOccurrencesOfString:symbol withString:@""];
    clean = [clean stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
    return clean.length ? clean : detail;
}

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section { return self.rows.count; }

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath {
    UITableViewCell *cell = [tableView dequeueReusableCellWithIdentifier:@"mc-symbol"];
    if (!cell) cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleSubtitle reuseIdentifier:@"mc-symbol"];
    SCIExpMCObservation *o = self.rows[(NSUInteger)indexPath.row];
    NSString *symbol = [self symbolNameFromDetail:o.lastDefault ?: @""];
    NSString *candidate = o.paramID ? [NSString stringWithFormat:@"0x%016llx", o.paramID] : @"candidate=none";
    cell.textLabel.text = [NSString stringWithFormat:@"%@  %@", symbol, candidate];
    cell.textLabel.font = [UIFont monospacedSystemFontOfSize:12 weight:UIFontWeightRegular];
    cell.textLabel.numberOfLines = 0;
    cell.detailTextLabel.text = [NSString stringWithFormat:@"%@ · ×%lu", [self cleanDetail:o.lastDefault ?: @""], (unsigned long)o.hitCount];
    cell.detailTextLabel.font = [UIFont monospacedSystemFontOfSize:11 weight:UIFontWeightRegular];
    cell.detailTextLabel.textColor = UIColor.secondaryLabelColor;
    cell.detailTextLabel.numberOfLines = 0;
    cell.accessoryType = UITableViewCellAccessoryDisclosureIndicator;
    return cell;
}

- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath {
    [tableView deselectRowAtIndexPath:indexPath animated:YES];
    SCIExpMCObservation *o = self.rows[(NSUInteger)indexPath.row];
    NSString *symbol = [self symbolNameFromDetail:o.lastDefault ?: @""];
    NSString *row = [NSString stringWithFormat:@"%@\ncandidate=0x%016llx\nhits=%lu\n%@", symbol, o.paramID, (unsigned long)o.hitCount, o.lastDefault ?: @""];
    UIAlertController *sheet = [UIAlertController alertControllerWithTitle:symbol message:row preferredStyle:UIAlertControllerStyleActionSheet];
    [sheet addAction:[UIAlertAction actionWithTitle:@"Copy row" style:UIAlertActionStyleDefault handler:^(__unused UIAlertAction *action) {
        UIPasteboard.generalPasteboard.string = row;
    }]];
    [sheet addAction:[UIAlertAction actionWithTitle:@"Copy symbol" style:UIAlertActionStyleDefault handler:^(__unused UIAlertAction *action) {
        UIPasteboard.generalPasteboard.string = symbol;
    }]];
    [sheet addAction:[UIAlertAction actionWithTitle:@"Cancel" style:UIAlertActionStyleCancel handler:nil]];
    UITableViewCell *cell = [tableView cellForRowAtIndexPath:indexPath];
    if (sheet.popoverPresentationController) {
        sheet.popoverPresentationController.sourceView = cell;
        sheet.popoverPresentationController.sourceRect = cell.bounds;
    }
    [self presentViewController:sheet animated:YES completion:nil];
}

- (void)searchBar:(UISearchBar *)searchBar textDidChange:(NSString *)searchText {
    self.query = searchText ?: @"";
    [self refresh];
}

- (void)searchBarSearchButtonClicked:(UISearchBar *)searchBar { [searchBar resignFirstResponder]; }

@end
