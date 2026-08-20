// Vanilla-derived experimental flag browser.
// Tabs: Browser(native) | Meta(override) | MC(view) | Scanned(view) | Overrides

#import "RYGExpFlagsViewController.h"
#import "../Features/ExpFlags/RYGExpFlags.h"
#import "../UI/RYGLiquidGlass.h"
#import "../UI/RYGPopupChrome.h"
#import "../Utils.h"
#import <objc/runtime.h>
#import <objc/message.h>

typedef NS_ENUM(NSInteger, RYGExpTab) {
    RYGExpTabBrowser = 0,
    RYGExpTabMeta,
    RYGExpTabMC,
    RYGExpTabScanned,
    RYGExpTabOverrides,
};

@interface RYGExpFlagsViewController () <UITableViewDataSource, UITableViewDelegate, UISearchBarDelegate>
@property (nonatomic, strong) UISegmentedControl *seg;
@property (nonatomic, strong) UISearchBar *searchBar;
@property (nonatomic, strong) UITableView *tableView;
@property (nonatomic, strong) UIActivityIndicatorView *spinner;
@property (nonatomic, strong) UILabel *empty;
@property (nonatomic, assign) RYGExpTab tab;
@property (nonatomic, copy) NSString *query;
@property (nonatomic, strong) NSArray<RYGExpObservation *> *metaObs;
@property (nonatomic, strong) NSArray<RYGExpMCObservation *> *mcObs;
@property (nonatomic, strong) NSArray<NSString *> *scannedNames;
@property (nonatomic, strong) NSArray *visibleRows;
@property (nonatomic, assign) BOOL scannedLoading;
@end

@implementation RYGExpFlagsViewController

- (void)viewDidLoad {
    [super viewDidLoad];
    self.title = @"Experimental flags";
    self.view.backgroundColor = [RYGPopupChrome backgroundColor];
    self.tab = RYGExpTabMeta;

    self.navigationItem.rightBarButtonItem = [[UIBarButtonItem alloc]
        initWithImage:[UIImage systemImageNamed:@"xmark.circle"]
                style:UIBarButtonItemStylePlain
               target:self
               action:@selector(confirmResetAll)];

    self.seg = [[UISegmentedControl alloc] initWithItems:@[@"Browser", @"Meta", @"MC IDs", @"Scanned", @"Overrides"]];
    self.seg.selectedSegmentIndex = self.tab;
    [self.seg addTarget:self action:@selector(segChanged) forControlEvents:UIControlEventValueChanged];
    self.seg.translatesAutoresizingMaskIntoConstraints = NO;
    [self.view addSubview:self.seg];

    self.searchBar = [UISearchBar new];
    self.searchBar.searchBarStyle = UISearchBarStyleMinimal;
    self.searchBar.placeholder = @"Search";
    self.searchBar.autocapitalizationType = UITextAutocapitalizationTypeNone;
    self.searchBar.autocorrectionType = UITextAutocorrectionTypeNo;
    self.searchBar.delegate = self;
    self.searchBar.translatesAutoresizingMaskIntoConstraints = NO;
    [self.view addSubview:self.searchBar];

    self.tableView = [[UITableView alloc] initWithFrame:CGRectZero style:UITableViewStyleInsetGrouped];
    self.tableView.dataSource = self;
    self.tableView.delegate = self;
    self.tableView.translatesAutoresizingMaskIntoConstraints = NO;
    self.tableView.backgroundColor = self.view.backgroundColor;
    self.tableView.keyboardDismissMode = UIScrollViewKeyboardDismissModeOnDrag;
    [self.tableView registerClass:UITableViewCell.class forCellReuseIdentifier:@"cell"];
    [self.view addSubview:self.tableView];

    self.spinner = [[UIActivityIndicatorView alloc] initWithActivityIndicatorStyle:UIActivityIndicatorViewStyleMedium];
    self.spinner.translatesAutoresizingMaskIntoConstraints = NO;
    self.spinner.hidesWhenStopped = YES;
    [self.view addSubview:self.spinner];

    self.empty = [UILabel new];
    self.empty.translatesAutoresizingMaskIntoConstraints = NO;
    self.empty.textColor = UIColor.secondaryLabelColor;
    self.empty.textAlignment = NSTextAlignmentCenter;
    self.empty.numberOfLines = 0;
    self.empty.font = [UIFont systemFontOfSize:13.0];
    [self.view addSubview:self.empty];

    UILayoutGuide *g = self.view.safeAreaLayoutGuide;
    [NSLayoutConstraint activateConstraints:@[
        [self.seg.topAnchor constraintEqualToAnchor:g.topAnchor constant:8.0],
        [self.seg.leadingAnchor constraintEqualToAnchor:g.leadingAnchor constant:12.0],
        [self.seg.trailingAnchor constraintEqualToAnchor:g.trailingAnchor constant:-12.0],
        [self.searchBar.topAnchor constraintEqualToAnchor:self.seg.bottomAnchor constant:4.0],
        [self.searchBar.leadingAnchor constraintEqualToAnchor:g.leadingAnchor constant:8.0],
        [self.searchBar.trailingAnchor constraintEqualToAnchor:g.trailingAnchor constant:-8.0],
        [self.tableView.topAnchor constraintEqualToAnchor:self.searchBar.bottomAnchor],
        [self.tableView.leadingAnchor constraintEqualToAnchor:self.view.leadingAnchor],
        [self.tableView.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor],
        [self.tableView.bottomAnchor constraintEqualToAnchor:self.view.bottomAnchor],
        [self.spinner.centerXAnchor constraintEqualToAnchor:self.tableView.centerXAnchor],
        [self.spinner.centerYAnchor constraintEqualToAnchor:self.tableView.centerYAnchor],
        [self.empty.centerXAnchor constraintEqualToAnchor:self.tableView.centerXAnchor],
        [self.empty.centerYAnchor constraintEqualToAnchor:self.tableView.centerYAnchor],
        [self.empty.leadingAnchor constraintEqualToAnchor:g.leadingAnchor constant:24.0],
        [self.empty.trailingAnchor constraintEqualToAnchor:g.trailingAnchor constant:-24.0],
    ]];

    [self refreshSnapshot];
    RYGLiquidGlassApplyToViewController(self);
}

- (void)viewWillAppear:(BOOL)animated {
    [super viewWillAppear:animated];
    [self refreshSnapshot];
}

- (void)segChanged {
    self.tab = (RYGExpTab)self.seg.selectedSegmentIndex;
    if (self.tab == RYGExpTabScanned && !self.scannedNames && !self.scannedLoading) [self loadScanned];
    [self rebuildVisibleRows];
}

- (void)loadScanned {
    self.scannedLoading = YES;
    [self.spinner startAnimating];
    [self updateEmpty];
    __weak typeof(self) weakSelf = self;
    [RYGExpFlags scanExecutableNamesWithCompletion:^(NSArray<NSString *> *names) {
        __strong typeof(weakSelf) self = weakSelf;
        if (!self) return;
        self.scannedNames = names ?: @[];
        self.scannedLoading = NO;
        [self.spinner stopAnimating];
        [self rebuildVisibleRows];
    }];
}

- (void)refreshSnapshot {
    self.metaObs = [RYGExpFlags allObservations] ?: @[];
    self.mcObs = [RYGExpFlags allMCObservations] ?: @[];
    [self rebuildVisibleRows];
}

- (BOOL)text:(NSString *)text matchesQuery:(NSString *)query {
    if (!query.length) return YES;
    NSArray<NSString *> *tokens = [query.lowercaseString componentsSeparatedByCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet];
    NSString *hay = text.lowercaseString ?: @"";
    for (NSString *token in tokens) if (token.length && [hay rangeOfString:token].location == NSNotFound) return NO;
    return YES;
}

- (void)rebuildVisibleRows {
    NSString *q = [self.query stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet] ?: @"";
    NSMutableArray *out = [NSMutableArray array];
    switch (self.tab) {
        case RYGExpTabBrowser:
            [out addObjectsFromArray:@[@"Open native list", @"Add override"]];
            break;
        case RYGExpTabMeta:
            for (RYGExpObservation *o in self.metaObs) if ([self text:o.experimentName matchesQuery:q]) [out addObject:o];
            break;
        case RYGExpTabMC:
            for (RYGExpMCObservation *o in self.mcObs) {
                NSString *s = [NSString stringWithFormat:@"%llu %@", o.paramID, o.lastDefault ?: @""];
                if ([self text:s matchesQuery:q]) [out addObject:o];
            }
            break;
        case RYGExpTabScanned:
            for (NSString *name in self.scannedNames ?: @[]) if ([self text:name matchesQuery:q]) [out addObject:name];
            break;
        case RYGExpTabOverrides:
            for (NSString *name in [[RYGExpFlags allOverriddenNames] sortedArrayUsingSelector:@selector(compare:)])
                if ([self text:name matchesQuery:q]) [out addObject:name];
            break;
    }
    self.visibleRows = out.copy;
    [self.tableView reloadData];
    [self updateEmpty];
}

- (void)updateEmpty {
    if (self.tab == RYGExpTabScanned && self.scannedLoading) {
        self.empty.text = @"Scanning executable…";
        self.empty.hidden = NO;
        return;
    }
    if (self.visibleRows.count) { self.empty.hidden = YES; return; }
    switch (self.tab) {
        case RYGExpTabBrowser: self.empty.text = @""; break;
        case RYGExpTabMeta: self.empty.text = @"Browse Instagram to populate live experiments."; break;
        case RYGExpTabMC: self.empty.text = @"Browse Instagram to populate MobileConfig calls."; break;
        case RYGExpTabScanned: self.empty.text = self.query.length ? @"No match" : @"Open this tab to scan flag-name strings."; break;
        case RYGExpTabOverrides: self.empty.text = @"No experiment overrides."; break;
    }
    self.empty.hidden = NO;
}

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section {
    (void)tableView; (void)section; return (NSInteger)self.visibleRows.count;
}

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath {
    UITableViewCell *cell = [tableView dequeueReusableCellWithIdentifier:@"cell" forIndexPath:indexPath];
    cell.accessoryType = UITableViewCellAccessoryNone;
    cell.selectionStyle = UITableViewCellSelectionStyleDefault;
    cell.textLabel.textColor = UIColor.labelColor;
    cell.textLabel.numberOfLines = 2;
    cell.detailTextLabel.text = nil;
    id row = self.visibleRows[(NSUInteger)indexPath.row];

    switch (self.tab) {
        case RYGExpTabBrowser:
            cell.textLabel.text = row;
            cell.textLabel.font = [UIFont systemFontOfSize:15.0];
            cell.accessoryType = UITableViewCellAccessoryDisclosureIndicator;
            break;
        case RYGExpTabMeta: {
            RYGExpObservation *o = row;
            [self fillCell:cell withName:o.experimentName subtitle:[NSString stringWithFormat:@"group=%@ · ×%lu", o.lastGroup ?: @"nil", (unsigned long)o.hitCount]];
            break;
        }
        case RYGExpTabMC: {
            RYGExpMCObservation *o = row;
            NSString *type = @"?";
            switch (o.type) {
                case RYGExpMCTypeBool: type = @"bool"; break;
                case RYGExpMCTypeInt: type = @"int64"; break;
                case RYGExpMCTypeDouble: type = @"double"; break;
                case RYGExpMCTypeString: type = @"string"; break;
            }
            cell.textLabel.text = [NSString stringWithFormat:@"%llu", o.paramID];
            cell.textLabel.font = [UIFont monospacedSystemFontOfSize:12.0 weight:UIFontWeightRegular];
            cell.detailTextLabel.text = [NSString stringWithFormat:@"%@ · default=%@ · ×%lu", type, o.lastDefault ?: @"?", (unsigned long)o.hitCount];
            cell.accessoryType = UITableViewCellAccessoryDisclosureIndicator;
            break;
        }
        case RYGExpTabScanned:
            cell.textLabel.text = row;
            cell.textLabel.font = [UIFont monospacedSystemFontOfSize:11.5 weight:UIFontWeightRegular];
            cell.accessoryType = UITableViewCellAccessoryDisclosureIndicator;
            break;
        case RYGExpTabOverrides:
            [self fillCell:cell withName:row subtitle:nil];
            break;
    }
    return cell;
}

- (void)fillCell:(UITableViewCell *)cell withName:(NSString *)name subtitle:(NSString *)subtitle {
    RYGExpFlagOverride value = [RYGExpFlags overrideForName:name];
    NSString *prefix = value == RYGExpFlagOverrideTrue ? @"● " : value == RYGExpFlagOverrideFalse ? @"○ " : @"";
    cell.textLabel.text = [prefix stringByAppendingString:name ?: @""];
    cell.textLabel.font = [UIFont monospacedSystemFontOfSize:12.0 weight:UIFontWeightRegular];
    cell.textLabel.textColor = value == RYGExpFlagOverrideOff ? UIColor.labelColor : UIColor.systemOrangeColor;
    NSMutableArray *parts = [NSMutableArray array];
    if (subtitle.length) [parts addObject:subtitle];
    if (value == RYGExpFlagOverrideTrue) [parts addObject:@"FORCED ON"];
    if (value == RYGExpFlagOverrideFalse) [parts addObject:@"FORCED OFF"];
    cell.detailTextLabel.text = [parts componentsJoinedByString:@" · "];
    cell.accessoryType = UITableViewCellAccessoryDisclosureIndicator;
}

- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath {
    [tableView deselectRowAtIndexPath:indexPath animated:YES];
    UITableViewCell *cell = [tableView cellForRowAtIndexPath:indexPath];
    id row = self.visibleRows[(NSUInteger)indexPath.row];
    switch (self.tab) {
        case RYGExpTabBrowser:
            if (indexPath.row == 0) [self openNativeBrowser]; else [self promptAddByName];
            break;
        case RYGExpTabMeta:
            [self presentOverrideSheetForName:((RYGExpObservation *)row).experimentName fromCell:cell];
            break;
        case RYGExpTabMC:
            [self presentCopySheetWithText:[NSString stringWithFormat:@"%llu", ((RYGExpMCObservation *)row).paramID] title:@"MobileConfig param" fromCell:cell];
            break;
        case RYGExpTabScanned:
            [self presentCopySheetWithText:row title:@"Scanned name" fromCell:cell];
            break;
        case RYGExpTabOverrides:
            [self presentOverrideSheetForName:row fromCell:cell];
            break;
    }
}

- (void)openNativeBrowser {
    Class cls = NSClassFromString(@"MetaLocalExperimentListViewController");
    if (!cls) { [RYGUtils showErrorHUDWithDescription:@"Native browser missing"]; return; }
    SEL initSel = NSSelectorFromString(@"initWithExperimentConfigs:experimentGenerator:");
    UIViewController *vc = nil;
    @try {
        if ([cls instancesRespondToSelector:initSel]) {
            vc = ((id (*)(id, SEL, id, id))objc_msgSend)([cls alloc], initSel, [self nativeBrowserConfigs], [self nativeBrowserGenerator]);
        } else vc = [[cls alloc] init];
    } @catch (__unused id e) {}
    if (!vc) { [RYGUtils showErrorHUDWithDescription:@"Native MetaLocalExperiment init failed"]; return; }
    UINavigationController *nav = [[UINavigationController alloc] initWithRootViewController:vc];
    nav.modalPresentationStyle = UIModalPresentationFullScreen;
    [self presentViewController:nav animated:YES completion:nil];
}

- (NSArray *)nativeBrowserConfigs {
    Protocol *p = objc_getProtocol("MetaLocalExperimentConfigProtocol");
    if (!p) return @[];
    unsigned int count = 0;
    Class *classes = objc_copyClassList(&count);
    NSMutableArray *out = [NSMutableArray array];
    for (unsigned int i = 0; classes && i < count; i++) {
        if (!class_conformsToProtocol(classes[i], p)) continue;
        @try { id value = [[classes[i] alloc] init]; if (value) [out addObject:value]; } @catch (__unused id e) {}
    }
    if (classes) free(classes);
    return out.copy;
}

- (id)nativeBrowserGenerator {
    Class cls = NSClassFromString(@"LIDExperimentGenerator");
    SEL sel = NSSelectorFromString(@"initWithDeviceID:logger:");
    if (!cls || ![cls instancesRespondToSelector:sel]) return nil;
    @try { return ((id (*)(id, SEL, id, id))objc_msgSend)([cls alloc], sel, nil, nil); }
    @catch (__unused id e) { return nil; }
}

- (void)promptAddByName {
    UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"Add override" message:@"Substring match, case-insensitive." preferredStyle:UIAlertControllerStyleAlert];
    [alert addTextFieldWithConfigurationHandler:^(UITextField *field) {
        field.placeholder = @"name (e.g. liquidglass)";
        field.autocapitalizationType = UITextAutocapitalizationTypeNone;
        field.autocorrectionType = UITextAutocorrectionTypeNo;
    }];
    [alert addAction:[UIAlertAction actionWithTitle:@"Cancel" style:UIAlertActionStyleCancel handler:nil]];
    __weak typeof(self) weakSelf = self;
    [alert addAction:[UIAlertAction actionWithTitle:@"Force ON" style:UIAlertActionStyleDefault handler:^(__unused UIAlertAction *action) {
        NSString *name = [alert.textFields.firstObject.text stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet];
        if (name.length) [RYGExpFlags setOverride:RYGExpFlagOverrideTrue forName:name];
        [weakSelf refreshSnapshot];
    }]];
    [alert addAction:[UIAlertAction actionWithTitle:@"Force OFF" style:UIAlertActionStyleDefault handler:^(__unused UIAlertAction *action) {
        NSString *name = [alert.textFields.firstObject.text stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet];
        if (name.length) [RYGExpFlags setOverride:RYGExpFlagOverrideFalse forName:name];
        [weakSelf refreshSnapshot];
    }]];
    [self presentViewController:alert animated:YES completion:nil];
}

- (void)presentOverrideSheetForName:(NSString *)name fromCell:(UITableViewCell *)cell {
    RYGExpFlagOverride current = [RYGExpFlags overrideForName:name];
    UIAlertController *sheet = [UIAlertController alertControllerWithTitle:name message:nil preferredStyle:UIAlertControllerStyleActionSheet];
    NSArray *options = @[
        @{@"title": @"No override", @"value": @(RYGExpFlagOverrideOff)},
        @{@"title": @"Force ON", @"value": @(RYGExpFlagOverrideTrue)},
        @{@"title": @"Force OFF", @"value": @(RYGExpFlagOverrideFalse)},
    ];
    __weak typeof(self) weakSelf = self;
    for (NSDictionary *option in options) {
        NSInteger value = [option[@"value"] integerValue];
        NSString *title = option[@"title"];
        if (value == current) title = [title stringByAppendingString:@"  ✓"];
        [sheet addAction:[UIAlertAction actionWithTitle:title style:UIAlertActionStyleDefault handler:^(__unused UIAlertAction *action) {
            [RYGExpFlags setOverride:(RYGExpFlagOverride)value forName:name];
            [weakSelf refreshSnapshot];
        }]];
    }
    [sheet addAction:[UIAlertAction actionWithTitle:@"Copy name" style:UIAlertActionStyleDefault handler:^(__unused UIAlertAction *action) {
        UIPasteboard.generalPasteboard.string = name;
    }]];
    [sheet addAction:[UIAlertAction actionWithTitle:@"Cancel" style:UIAlertActionStyleCancel handler:nil]];
    if (sheet.popoverPresentationController) {
        sheet.popoverPresentationController.sourceView = cell;
        sheet.popoverPresentationController.sourceRect = cell.bounds;
    }
    [self presentViewController:sheet animated:YES completion:nil];
}

- (void)presentCopySheetWithText:(NSString *)text title:(NSString *)title fromCell:(UITableViewCell *)cell {
    UIAlertController *sheet = [UIAlertController alertControllerWithTitle:title message:text preferredStyle:UIAlertControllerStyleActionSheet];
    [sheet addAction:[UIAlertAction actionWithTitle:@"Copy" style:UIAlertActionStyleDefault handler:^(__unused UIAlertAction *action) {
        UIPasteboard.generalPasteboard.string = text;
    }]];
    [sheet addAction:[UIAlertAction actionWithTitle:@"Cancel" style:UIAlertActionStyleCancel handler:nil]];
    if (sheet.popoverPresentationController) {
        sheet.popoverPresentationController.sourceView = cell;
        sheet.popoverPresentationController.sourceRect = cell.bounds;
    }
    [self presentViewController:sheet animated:YES completion:nil];
}

- (void)confirmResetAll {
    UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"Reset all?" message:nil preferredStyle:UIAlertControllerStyleAlert];
    [alert addAction:[UIAlertAction actionWithTitle:@"Cancel" style:UIAlertActionStyleCancel handler:nil]];
    __weak typeof(self) weakSelf = self;
    [alert addAction:[UIAlertAction actionWithTitle:@"Reset" style:UIAlertActionStyleDestructive handler:^(__unused UIAlertAction *action) {
        [RYGExpFlags resetAllOverrides];
        [weakSelf refreshSnapshot];
    }]];
    [self presentViewController:alert animated:YES completion:nil];
}

- (void)searchBar:(UISearchBar *)searchBar textDidChange:(NSString *)searchText {
    (void)searchBar;
    self.query = searchText ?: @"";
    [self rebuildVisibleRows];
}

- (void)searchBarSearchButtonClicked:(UISearchBar *)searchBar { [searchBar resignFirstResponder]; }

@end
