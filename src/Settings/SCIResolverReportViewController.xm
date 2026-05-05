#import "SCIResolverReportViewController.h"
#import "SCIResolverScanner.h"
#import "SCIResolverSpecifierEntry.h"
#import "../Features/ExpFlags/SCIExpFlags.h"
#import "../Utils.h"
#import <objc/runtime.h>

static const void *kSCIResolverSwitchSpecifierKey = &kSCIResolverSwitchSpecifierKey;

typedef NS_ENUM(NSInteger, SCIResolverSection) {
    SCIResolverSectionObserved = 0,
    SCIResolverSectionResolved = 1,
    SCIResolverSectionReport = 2,
};

@interface SCIResolverReportViewController () <UITableViewDataSource, UITableViewDelegate, UISearchBarDelegate>
@property (nonatomic, assign) SCIResolverReportKind kind;
@property (nonatomic, copy) NSString *reportTitle;
@property (nonatomic, strong) UITableView *tableView;
@property (nonatomic, strong) UISearchBar *searchBar;
@property (nonatomic, strong) UIActivityIndicatorView *spinner;
@property (nonatomic, strong) NSArray<SCIResolverSpecifierEntry *> *specifiers;
@property (nonatomic, strong) NSArray<SCIExpInternalUseObservation *> *observations;
@property (nonatomic, copy) NSString *fullReport;
@property (nonatomic, copy) NSString *query;
@end

@implementation SCIResolverReportViewController

- (instancetype)initWithNibName:(NSString *)nibNameOrNil bundle:(NSBundle *)nibBundleOrNil {
    self = [super initWithNibName:nibNameOrNil bundle:nibBundleOrNil];
    if (self) {
        _kind = SCIResolverReportKindFull;
        _reportTitle = @"Resolver Report";
    }
    return self;
}

- (instancetype)initWithKind:(SCIResolverReportKind)kind title:(NSString *)title {
    self = [super initWithNibName:nil bundle:nil];
    if (self) {
        _kind = kind;
        _reportTitle = title ?: @"Resolver Report";
    }
    return self;
}

- (void)viewDidLoad {
    [super viewDidLoad];
    self.title = self.reportTitle;
    self.view.backgroundColor = UIColor.systemBackgroundColor;

    self.navigationItem.rightBarButtonItems = @[
        [[UIBarButtonItem alloc] initWithTitle:@"Copy" style:UIBarButtonItemStylePlain target:self action:@selector(copyFullReport)],
        [[UIBarButtonItem alloc] initWithBarButtonSystemItem:UIBarButtonSystemItemRefresh target:self action:@selector(runReport)]
    ];

    self.searchBar = [UISearchBar new];
    self.searchBar.searchBarStyle = UISearchBarStyleMinimal;
    self.searchBar.placeholder = @"Search gates, functions, specifiers";
    self.searchBar.autocapitalizationType = UITextAutocapitalizationTypeNone;
    self.searchBar.autocorrectionType = UITextAutocorrectionTypeNo;
    self.searchBar.delegate = self;
    self.searchBar.translatesAutoresizingMaskIntoConstraints = NO;
    [self.view addSubview:self.searchBar];

    self.tableView = [[UITableView alloc] initWithFrame:CGRectZero style:UITableViewStyleGrouped];
    self.tableView.translatesAutoresizingMaskIntoConstraints = NO;
    self.tableView.dataSource = self;
    self.tableView.delegate = self;
    self.tableView.keyboardDismissMode = UIScrollViewKeyboardDismissModeOnDrag;
    [self.view addSubview:self.tableView];

    self.spinner = [[UIActivityIndicatorView alloc] initWithActivityIndicatorStyle:UIActivityIndicatorViewStyleMedium];
    self.spinner.translatesAutoresizingMaskIntoConstraints = NO;
    self.spinner.hidesWhenStopped = YES;
    [self.view addSubview:self.spinner];

    UILayoutGuide *g = self.view.safeAreaLayoutGuide;
    [NSLayoutConstraint activateConstraints:@[
        [self.searchBar.topAnchor constraintEqualToAnchor:g.topAnchor],
        [self.searchBar.leadingAnchor constraintEqualToAnchor:g.leadingAnchor],
        [self.searchBar.trailingAnchor constraintEqualToAnchor:g.trailingAnchor],
        [self.tableView.topAnchor constraintEqualToAnchor:self.searchBar.bottomAnchor],
        [self.tableView.leadingAnchor constraintEqualToAnchor:g.leadingAnchor],
        [self.tableView.trailingAnchor constraintEqualToAnchor:g.trailingAnchor],
        [self.tableView.bottomAnchor constraintEqualToAnchor:g.bottomAnchor],
        [self.spinner.centerXAnchor constraintEqualToAnchor:self.view.centerXAnchor],
        [self.spinner.centerYAnchor constraintEqualToAnchor:self.view.centerYAnchor]
    ]];

    [self runReport];
}

- (void)viewWillAppear:(BOOL)animated {
    [super viewWillAppear:animated];
    [self refreshRuntimeOnly];
}

- (void)refreshRuntimeOnly {
    self.observations = [SCIExpFlags allInternalUseObservations];
    self.specifiers = [SCIResolverScanner allKnownSpecifierEntries];
    [self.tableView reloadData];
}

- (void)runReport {
    [self.spinner startAnimating];
    dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
        NSString *report = @"";
        switch (self.kind) {
            case SCIResolverReportKindDogfoodDeveloper:
                report = [SCIResolverScanner runDogfoodDeveloperReport];
                break;
            case SCIResolverReportKindMobileConfigSymbols:
                report = [SCIResolverScanner runMobileConfigSymbolReport];
                break;
            case SCIResolverReportKindFull:
                report = [SCIResolverScanner runFullResolverReport];
                break;
        }

        NSArray *specs = [SCIResolverScanner allKnownSpecifierEntries];
        NSArray *obs = [SCIExpFlags allInternalUseObservations];

        dispatch_async(dispatch_get_main_queue(), ^{
            self.fullReport = report;
            self.specifiers = specs;
            self.observations = obs;
            [self.spinner stopAnimating];
            [self.tableView reloadData];
        });
    });
}

- (void)copyFullReport {
    if (!self.fullReport.length) return;
    UIPasteboard.generalPasteboard.string = self.fullReport;
    [SCIUtils showSuccessHUDWithDescription:@"Report copied"];
}

#pragma mark - Filtering

- (BOOL)stringMatchesQuery:(NSString *)s {
    if (!self.query.length) return YES;
    return [[s ?: @"" lowercaseString] containsString:self.query.lowercaseString];
}

- (NSArray<SCIExpInternalUseObservation *> *)filteredObservations {
    if (!self.query.length) return self.observations ?: @[];
    NSMutableArray *out = [NSMutableArray array];
    for (SCIExpInternalUseObservation *o in self.observations ?: @[]) {
        NSString *joined = [NSString stringWithFormat:@"%@ %@ %@ 0x%016llx %@",
                            o.functionName ?: @"",
                            o.specifierName ?: @"",
                            o.callerDescription ?: @"",
                            o.specifier,
                            o.forcedValue ? @"forced" : @"normal"];
        if ([self stringMatchesQuery:joined]) [out addObject:o];
    }
    return out;
}

- (NSArray<SCIResolverSpecifierEntry *> *)filteredSpecifiers {
    if (!self.query.length) return self.specifiers ?: @[];
    NSMutableArray *out = [NSMutableArray array];
    for (SCIResolverSpecifierEntry *e in self.specifiers ?: @[]) {
        NSString *joined = [NSString stringWithFormat:@"%@ %@ 0x%016llx %@",
                            e.name ?: @"",
                            e.source ?: @"",
                            e.specifier,
                            e.suggestedValue ? @"yes on true" : @"no off false"];
        if ([self stringMatchesQuery:joined]) [out addObject:e];
    }
    return out;
}

#pragma mark - UISearchBarDelegate

- (void)searchBar:(UISearchBar *)searchBar textDidChange:(NSString *)searchText {
    self.query = searchText ?: @"";
    [self.tableView reloadData];
}

- (void)searchBarSearchButtonClicked:(UISearchBar *)searchBar {
    [searchBar resignFirstResponder];
}

#pragma mark - UITableViewDataSource

- (NSInteger)numberOfSectionsInTableView:(UITableView *)tableView {
    return 3;
}

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section {
    if (section == SCIResolverSectionObserved) return MAX(1, (NSInteger)[self filteredObservations].count);
    if (section == SCIResolverSectionResolved) return [self filteredSpecifiers].count;
    return 1;
}

- (NSString *)tableView:(UITableView *)tableView titleForHeaderInSection:(NSInteger)section {
    if (section == SCIResolverSectionObserved) return @"Live observed gates";
    if (section == SCIResolverSectionResolved) return @"Resolved specifiers / named gates";
    return @"Coverage report";
}

- (NSString *)tableView:(UITableView *)tableView titleForFooterInSection:(NSInteger)section {
    if (section == SCIResolverSectionObserved) return @"Merged from SCIExpFlags runtime observations. Browse Instagram with Flags Browser/Verbose Gate Logging enabled, then refresh.";
    if (section == SCIResolverSectionResolved) return @"Includes dlsym data symbols, hardcoded fallbacks, runtime observations and manual overrides.";
    return @"Copy this report when validating coverage or debugging missing functions.";
}

- (UITableViewCell *)newSubtitleCellWithTableView:(UITableView *)tableView identifier:(NSString *)identifier {
    UITableViewCell *cell = [tableView dequeueReusableCellWithIdentifier:identifier];
    if (!cell) cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleSubtitle reuseIdentifier:identifier];
    cell.textLabel.numberOfLines = 0;
    cell.detailTextLabel.numberOfLines = 0;
    cell.textLabel.textColor = UIColor.labelColor;
    cell.detailTextLabel.textColor = UIColor.secondaryLabelColor;
    cell.accessoryView = nil;
    cell.accessoryType = UITableViewCellAccessoryNone;
    cell.selectionStyle = UITableViewCellSelectionStyleDefault;
    return cell;
}

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath {
    if (indexPath.section == SCIResolverSectionObserved) {
        NSArray *rows = [self filteredObservations];
        UITableViewCell *cell = [self newSubtitleCellWithTableView:tableView identifier:@"ObservedCell"];
        if (!rows.count) {
            cell.textLabel.text = @"No runtime gates observed yet";
            cell.detailTextLabel.text = @"Enable Flags Browser or Verbose Gate Logging, browse Instagram, then tap Refresh.";
            cell.selectionStyle = UITableViewCellSelectionStyleNone;
            return cell;
        }

        SCIExpInternalUseObservation *o = rows[indexPath.row];
        SCIExpFlagOverride ov = [SCIExpFlags internalUseOverrideForSpecifier:o.specifier];
        NSString *ovStr = ov == SCIExpFlagOverrideTrue ? @"FORCED ON" : ov == SCIExpFlagOverrideFalse ? @"FORCED OFF" : @"Override: none";
        NSString *forceMark = o.forcedValue ? @" · forced" : @"";

        cell.textLabel.text = [NSString stringWithFormat:@"%@  0x%016llx", o.specifierName ?: @"unknown", o.specifier];
        cell.textLabel.font = [UIFont monospacedSystemFontOfSize:12 weight:UIFontWeightRegular];
        cell.detailTextLabel.text = [NSString stringWithFormat:@"%@ · default=%d result=%d%@ · hits=%lu · %@\n%@",
                                     o.functionName ?: @"Gate",
                                     o.defaultValue,
                                     o.resultValue,
                                     forceMark,
                                     (unsigned long)o.hitCount,
                                     ovStr,
                                     o.callerDescription ?: @""];

        UISwitch *sw = [UISwitch new];
        sw.on = (ov == SCIExpFlagOverrideTrue) || (ov == SCIExpFlagOverrideOff && o.resultValue);
        objc_setAssociatedObject(sw, kSCIResolverSwitchSpecifierKey, @(o.specifier), OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        [sw addTarget:self action:@selector(specifierSwitchChanged:) forControlEvents:UIControlEventValueChanged];
        cell.accessoryView = sw;
        return cell;
    }

    if (indexPath.section == SCIResolverSectionResolved) {
        UITableViewCell *cell = [self newSubtitleCellWithTableView:tableView identifier:@"SpecifierCell"];
        SCIResolverSpecifierEntry *e = [self filteredSpecifiers][indexPath.row];
        SCIExpFlagOverride ov = [SCIExpFlags internalUseOverrideForSpecifier:e.specifier];
        NSString *ovStr = (ov == SCIExpFlagOverrideTrue) ? @"FORCED ON" : (ov == SCIExpFlagOverrideFalse) ? @"FORCED OFF" : @"Override: none";

        cell.textLabel.text = [NSString stringWithFormat:@"%@  0x%016llx", e.name ?: @"unknown", e.specifier];
        cell.textLabel.font = [UIFont monospacedSystemFontOfSize:12 weight:UIFontWeightRegular];
        cell.detailTextLabel.text = [NSString stringWithFormat:@"Source: %@ · Suggested: %@ · %@", e.source ?: @"resolver", e.suggestedValue ? @"YES" : @"NO", ovStr];
        cell.detailTextLabel.textColor = [UIColor secondaryLabelColor];

        UISwitch *sw = [UISwitch new];
        sw.on = (ov == SCIExpFlagOverrideTrue) || (ov == SCIExpFlagOverrideOff && e.suggestedValue);
        objc_setAssociatedObject(sw, kSCIResolverSwitchSpecifierKey, @(e.specifier), OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        [sw addTarget:self action:@selector(specifierSwitchChanged:) forControlEvents:UIControlEventValueChanged];
        cell.accessoryView = sw;
        return cell;
    }

    UITableViewCell *cell = [self newSubtitleCellWithTableView:tableView identifier:@"ReportCell"];
    cell.textLabel.text = @"Copy full coverage report";
    cell.detailTextLabel.text = self.fullReport.length ? @"Includes function coverage, dlsym availability, runtime observations and class candidates." : @"Report is still loading.";
    cell.textLabel.textColor = UIColor.systemBlueColor;
    cell.accessoryType = UITableViewCellAccessoryDisclosureIndicator;
    return cell;
}

#pragma mark - UITableViewDelegate

- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath {
    [tableView deselectRowAtIndexPath:indexPath animated:YES];

    if (indexPath.section == SCIResolverSectionReport) {
        [self copyFullReport];
        return;
    }

    if (indexPath.section == SCIResolverSectionObserved) {
        NSArray *rows = [self filteredObservations];
        if (!rows.count) return;
        SCIExpInternalUseObservation *o = rows[indexPath.row];
        [self presentOverrideSheetForSpecifier:o.specifier
                                          name:o.specifierName ?: @"unknown"
                                        source:o.functionName ?: @"runtime"
                                      subtitle:o.callerDescription
                                      fromCell:[tableView cellForRowAtIndexPath:indexPath]];
        return;
    }

    if (indexPath.section == SCIResolverSectionResolved) {
        SCIResolverSpecifierEntry *e = [self filteredSpecifiers][indexPath.row];
        [self presentOverrideSheetForSpecifier:e.specifier
                                          name:e.name ?: @"unknown"
                                        source:e.source ?: @"resolver"
                                      subtitle:[NSString stringWithFormat:@"Suggested: %@", e.suggestedValue ? @"YES" : @"NO"]
                                      fromCell:[tableView cellForRowAtIndexPath:indexPath]];
    }
}

- (void)specifierSwitchChanged:(UISwitch *)sender {
    NSNumber *n = objc_getAssociatedObject(sender, kSCIResolverSwitchSpecifierKey);
    if (!n) return;
    unsigned long long spec = n.unsignedLongLongValue;
    [SCIExpFlags setInternalUseOverride:(sender.on ? SCIExpFlagOverrideTrue : SCIExpFlagOverrideFalse) forSpecifier:spec];
    [self refreshRuntimeOnly];
}

- (void)presentOverrideSheetForSpecifier:(unsigned long long)specifier
                                    name:(NSString *)name
                                  source:(NSString *)source
                                subtitle:(NSString *)subtitle
                                fromCell:(UITableViewCell *)cell {
    SCIExpFlagOverride cur = [SCIExpFlags internalUseOverrideForSpecifier:specifier];
    NSString *title = [NSString stringWithFormat:@"0x%016llx", specifier];
    NSString *msg = [NSString stringWithFormat:@"%@\nSource: %@%@%@",
                     name ?: @"unknown",
                     source ?: @"resolver",
                     subtitle.length ? @"\n" : @"",
                     subtitle ?: @""];

    UIAlertController *sheet = [UIAlertController alertControllerWithTitle:title message:msg preferredStyle:UIAlertControllerStyleActionSheet];

    void (^add)(NSString *, SCIExpFlagOverride) = ^(NSString *t, SCIExpFlagOverride v) {
        NSString *shown = (v == cur) ? [t stringByAppendingString:@"  ✓"] : t;
        [sheet addAction:[UIAlertAction actionWithTitle:shown style:UIAlertActionStyleDefault handler:^(__unused UIAlertAction *_) {
            [SCIExpFlags setInternalUseOverride:v forSpecifier:specifier];
            [self refreshRuntimeOnly];
        }]];
    };

    add(@"No override", SCIExpFlagOverrideOff);
    add(@"Force ON", SCIExpFlagOverrideTrue);
    add(@"Force OFF", SCIExpFlagOverrideFalse);

    [sheet addAction:[UIAlertAction actionWithTitle:@"Copy Hex" style:UIAlertActionStyleDefault handler:^(__unused UIAlertAction *_) {
        UIPasteboard.generalPasteboard.string = [NSString stringWithFormat:@"0x%016llx", specifier];
    }]];
    [sheet addAction:[UIAlertAction actionWithTitle:@"Copy Name" style:UIAlertActionStyleDefault handler:^(__unused UIAlertAction *_) {
        UIPasteboard.generalPasteboard.string = name ?: @"unknown";
    }]];
    [sheet addAction:[UIAlertAction actionWithTitle:@"Cancel" style:UIAlertActionStyleCancel handler:nil]];

    if (sheet.popoverPresentationController) {
        sheet.popoverPresentationController.sourceView = cell ?: self.view;
        sheet.popoverPresentationController.sourceRect = cell ? cell.bounds : self.view.bounds;
    }
    [self presentViewController:sheet animated:YES completion:nil];
}

@end
