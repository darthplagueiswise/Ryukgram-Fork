// Exp flag browser + override editor.
// Tabs: Browser(native) | Meta(override) | MC(view) | Scanned(view) | Overrides

#import "SCIExpFlagsViewController.h"
#import "../Features/ExpFlags/SCIExpFlags.h"
#import "../Utils.h"
#import <objc/runtime.h>
#import <objc/message.h>

typedef NS_ENUM(NSInteger, SCIExpTab) {
    SCIExpTabBrowser = 0,
    SCIExpTabMeta,
    SCIExpTabMC,
    SCIExpTabScanned,
    SCIExpTabOverrides,
};

@interface SCIExpFlagsViewController () <UITableViewDataSource, UITableViewDelegate, UISearchBarDelegate>
@property (nonatomic, strong) UISegmentedControl *seg;
@property (nonatomic, strong) UISearchBar *searchBar;
@property (nonatomic, strong) UITableView *tableView;
@property (nonatomic, strong) UIActivityIndicatorView *spinner;
@property (nonatomic, strong) UILabel *empty;

@property (nonatomic, assign) SCIExpTab tab;
@property (nonatomic, copy)   NSString *query;

@property (nonatomic, strong) NSArray<SCIExpObservation *>   *metaObs;
@property (nonatomic, strong) NSArray<SCIExpMCObservation *> *mcObs;
@property (nonatomic, strong) NSArray<NSString *>            *scannedNames;
@property (nonatomic, assign) BOOL scannedLoading;
@property (nonatomic, strong) NSArray<NSString *>            *overriddenNames;
@end

@implementation SCIExpFlagsViewController

- (void)viewDidLoad {
    [super viewDidLoad];
    self.title = @"Experimental flags";
    self.view.backgroundColor = UIColor.systemBackgroundColor;
    self.navigationItem.rightBarButtonItem = [[UIBarButtonItem alloc]
        initWithImage:[UIImage systemImageNamed:@"xmark.circle"]
                style:UIBarButtonItemStylePlain target:self action:@selector(confirmResetAll)];

    self.seg = [[UISegmentedControl alloc] initWithItems:@[@"Browser", @"Meta", @"MC IDs", @"Scanned", @"Overrides"]];
    self.seg.selectedSegmentIndex = SCIExpTabMeta;
    self.tab = SCIExpTabMeta;
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

    self.tableView = [[UITableView alloc] initWithFrame:CGRectZero style:UITableViewStylePlain];
    self.tableView.dataSource = self;
    self.tableView.delegate = self;
    self.tableView.translatesAutoresizingMaskIntoConstraints = NO;
    self.tableView.keyboardDismissMode = UIScrollViewKeyboardDismissModeOnDrag;
    [self.tableView registerClass:[UITableViewCell class] forCellReuseIdentifier:@"cell"];
    [self.view addSubview:self.tableView];

    self.spinner = [[UIActivityIndicatorView alloc] initWithActivityIndicatorStyle:UIActivityIndicatorViewStyleLarge];
    self.spinner.translatesAutoresizingMaskIntoConstraints = NO;
    self.spinner.hidesWhenStopped = YES;
    [self.view addSubview:self.spinner];

    self.empty = [UILabel new];
    self.empty.translatesAutoresizingMaskIntoConstraints = NO;
    self.empty.textColor = UIColor.secondaryLabelColor;
    self.empty.textAlignment = NSTextAlignmentCenter;
    self.empty.numberOfLines = 0;
    self.empty.font = [UIFont systemFontOfSize:14];
    [self.view addSubview:self.empty];

    UILayoutGuide *g = self.view.safeAreaLayoutGuide;
    [NSLayoutConstraint activateConstraints:@[
        [self.seg.topAnchor constraintEqualToAnchor:g.topAnchor constant:8],
        [self.seg.leadingAnchor constraintEqualToAnchor:g.leadingAnchor constant:12],
        [self.seg.trailingAnchor constraintEqualToAnchor:g.trailingAnchor constant:-12],
        [self.searchBar.topAnchor constraintEqualToAnchor:self.seg.bottomAnchor constant:4],
        [self.searchBar.leadingAnchor constraintEqualToAnchor:g.leadingAnchor constant:8],
        [self.searchBar.trailingAnchor constraintEqualToAnchor:g.trailingAnchor constant:-8],
        [self.tableView.topAnchor constraintEqualToAnchor:self.searchBar.bottomAnchor],
        [self.tableView.leadingAnchor constraintEqualToAnchor:g.leadingAnchor],
        [self.tableView.trailingAnchor constraintEqualToAnchor:g.trailingAnchor],
        [self.tableView.bottomAnchor constraintEqualToAnchor:g.bottomAnchor],
        [self.spinner.centerXAnchor constraintEqualToAnchor:self.tableView.centerXAnchor],
        [self.spinner.centerYAnchor constraintEqualToAnchor:self.tableView.centerYAnchor],
        [self.empty.centerXAnchor constraintEqualToAnchor:self.tableView.centerXAnchor],
        [self.empty.centerYAnchor constraintEqualToAnchor:self.tableView.centerYAnchor],
        [self.empty.leadingAnchor constraintEqualToAnchor:g.leadingAnchor constant:24],
        [self.empty.trailingAnchor constraintEqualToAnchor:g.trailingAnchor constant:-24],
    ]];
}

- (void)viewWillAppear:(BOOL)animated { [super viewWillAppear:animated]; [self refresh]; }

- (void)segChanged {
    self.tab = (SCIExpTab)self.seg.selectedSegmentIndex;
    if (self.tab == SCIExpTabScanned && !self.scannedNames && !self.scannedLoading) [self loadScanned];
    [self refresh];
}

- (void)loadScanned {
    self.scannedLoading = YES;
    [self.spinner startAnimating];
    [self updateEmpty];
    [SCIExpFlags scanExecutableNamesWithCompletion:^(NSArray<NSString *> *names) {
        self.scannedNames = names;
        self.scannedLoading = NO;
        [self.spinner stopAnimating];
        [self refresh];
    }];
}

- (void)refresh {
    self.metaObs = [SCIExpFlags allObservations];
    self.mcObs = [SCIExpFlags allMCObservations];
    self.overriddenNames = [[SCIExpFlags allOverriddenNames] sortedArrayUsingSelector:@selector(compare:)];
    [self.tableView reloadData];
    [self updateEmpty];
}

- (void)updateEmpty {
    NSInteger rows = [self tableView:self.tableView numberOfRowsInSection:0];
    if (self.tab == SCIExpTabScanned && self.scannedLoading) {
        self.empty.text = @"Scanning…";
        self.empty.hidden = NO;
        return;
    }
    if (rows == 0) {
        switch (self.tab) {
            case SCIExpTabBrowser:   self.empty.text = @""; break;
            case SCIExpTabMeta:      self.empty.text = @"Browse IG to populate."; break;
            case SCIExpTabMC:        self.empty.text = @"Browse IG to populate."; break;
            case SCIExpTabScanned:   self.empty.text = self.query.length ? @"No match" : @"Empty."; break;
            case SCIExpTabOverrides: self.empty.text = @"None."; break;
        }
        self.empty.hidden = NO;
        return;
    }
    self.empty.hidden = YES;
}

- (NSArray *)filteredRows {
    switch (self.tab) {
        case SCIExpTabBrowser:   return @[@"Open native list", @"Add override"];
        case SCIExpTabMeta:      return [self filtered:self.metaObs keyPath:@"experimentName"];
        case SCIExpTabMC:        return [self filterMC:self.mcObs];
        case SCIExpTabScanned:   return [self filterStrings:self.scannedNames];
        case SCIExpTabOverrides: return [self filterStrings:[self overrideRows]];
    }
}

- (NSArray *)filtered:(NSArray *)items keyPath:(NSString *)kp {
    if (!self.query.length) return items ?: @[];
    NSString *q = self.query.lowercaseString;
    NSMutableArray *out = [NSMutableArray array];
    for (id o in items) {
        NSString *s = [[o valueForKey:kp] lowercaseString];
        if ([s containsString:q]) [out addObject:o];
    }
    return out;
}

- (NSArray *)filterMC:(NSArray<SCIExpMCObservation *> *)items {
    if (!self.query.length) return items ?: @[];
    NSString *q = self.query.lowercaseString;
    NSMutableArray *out = [NSMutableArray array];
    for (SCIExpMCObservation *o in items) {
        NSString *s = [NSString stringWithFormat:@"%llu", o.paramID];
        if ([s containsString:q]) [out addObject:o];
    }
    return out;
}

- (NSArray *)filterStrings:(NSArray<NSString *> *)items {
    if (!self.query.length) return items ?: @[];
    NSString *q = self.query.lowercaseString;
    NSMutableArray *out = [NSMutableArray array];
    for (NSString *s in items) if ([s.lowercaseString containsString:q]) [out addObject:s];
    return out;
}

- (NSArray<NSString *> *)overrideRows {
    NSMutableArray<NSString *> *rows = [NSMutableArray array];
    for (NSString *name in self.overriddenNames ?: @[]) [rows addObject:name];

    NSArray<SCIExpInternalUseObservation *> *obs = [SCIExpFlags allInternalUseObservations];
    for (NSNumber *n in [SCIExpFlags allOverriddenInternalUseSpecifiers]) {
        unsigned long long spec = n.unsignedLongLongValue;
        SCIExpFlagOverride ov = [SCIExpFlags internalUseOverrideForSpecifier:spec];
        NSString *state = ov == SCIExpFlagOverrideTrue ? @"FORCED ON" : ov == SCIExpFlagOverrideFalse ? @"FORCED OFF" : @"NO OVERRIDE";
        NSString *fn = @"InternalUse";
        NSString *name = @"unknown";
        for (SCIExpInternalUseObservation *o in obs) {
            if (o.specifier == spec) {
                if (o.functionName.length) fn = o.functionName;
                if (o.specifierName.length) name = o.specifierName;
                break;
            }
        }
        [rows addObject:[NSString stringWithFormat:@"[InternalUse Override] %@ %@ spec=0x%016llx %@", fn, name, spec, state]];
    }
    return rows;
}

- (unsigned long long)internalUseSpecifierFromLine:(NSString *)line {
    if (![line hasPrefix:@"[InternalUse"]) return 0;
    NSRange r = [line rangeOfString:@"spec=0x"];
    if (r.location == NSNotFound) return 0;
    NSUInteger start = r.location + r.length;
    if (start >= line.length) return 0;
    NSString *tail = [line substringFromIndex:start];
    NSMutableString *hex = [NSMutableString string];
    for (NSUInteger i = 0; i < tail.length; i++) {
        unichar c = [tail characterAtIndex:i];
        BOOL ok = (c >= '0' && c <= '9') || (c >= 'a' && c <= 'f') || (c >= 'A' && c <= 'F');
        if (!ok) break;
        [hex appendFormat:@"%C", c];
    }
    if (!hex.length) return 0;
    return strtoull(hex.UTF8String, NULL, 16);
}

- (NSInteger)tableView:(UITableView *)tv numberOfRowsInSection:(NSInteger)section { return [self filteredRows].count; }

- (UITableViewCell *)tableView:(UITableView *)tv cellForRowAtIndexPath:(NSIndexPath *)ip {
    UITableViewCell *cell = [tv dequeueReusableCellWithIdentifier:@"cell" forIndexPath:ip];
    cell.accessoryType = UITableViewCellAccessoryNone;
    cell.selectionStyle = UITableViewCellSelectionStyleDefault;
    cell.textLabel.textColor = UIColor.labelColor;
    cell.textLabel.font = [UIFont systemFontOfSize:15];
    cell.textLabel.numberOfLines = 0;
    cell.detailTextLabel.text = nil;

    id row = [self filteredRows][ip.row];

    switch (self.tab) {
        case SCIExpTabBrowser: {
            cell.textLabel.text = (NSString *)row;
            cell.accessoryType = UITableViewCellAccessoryDisclosureIndicator;
            break;
        }
        case SCIExpTabMeta: {
            SCIExpObservation *o = row;
            [self fillCell:cell withName:o.experimentName subtitle:[NSString stringWithFormat:@"group=%@ · ×%lu", o.lastGroup ?: @"nil", (unsigned long)o.hitCount]];
            break;
        }
        case SCIExpTabMC: {
            SCIExpMCObservation *o = row;
            NSString *tname = @"?";
            switch (o.type) {
                case SCIExpMCTypeBool:   tname = @"bool";   break;
                case SCIExpMCTypeInt:    tname = @"int64";  break;
                case SCIExpMCTypeDouble: tname = @"double"; break;
                case SCIExpMCTypeString: tname = @"string"; break;
            }
            cell.textLabel.text = [NSString stringWithFormat:@"%llu", o.paramID];
            cell.textLabel.font = [UIFont monospacedSystemFontOfSize:13 weight:UIFontWeightRegular];
            cell.detailTextLabel.text = [NSString stringWithFormat:@"%@ · default=%@ · ×%lu", tname, o.lastDefault ?: @"?", (unsigned long)o.hitCount];
            cell.accessoryType = UITableViewCellAccessoryDisclosureIndicator;
            break;
        }
        case SCIExpTabScanned:
        case SCIExpTabOverrides: {
            NSString *line = (NSString *)row;
            unsigned long long spec = [self internalUseSpecifierFromLine:line];
            SCIExpFlagOverride o = spec ? [SCIExpFlags internalUseOverrideForSpecifier:spec] : SCIExpFlagOverrideOff;
            if (self.tab == SCIExpTabOverrides && !spec) {
                [self fillCell:cell withName:line subtitle:nil];
                break;
            }
            NSString *prefix = o == SCIExpFlagOverrideTrue ? @"● " : o == SCIExpFlagOverrideFalse ? @"○ " : @"";
            cell.textLabel.text = [prefix stringByAppendingString:line];
            cell.textLabel.font = [UIFont monospacedSystemFontOfSize:12 weight:UIFontWeightRegular];
            cell.textLabel.textColor = o == SCIExpFlagOverrideOff ? UIColor.labelColor : UIColor.systemOrangeColor;
            cell.accessoryType = UITableViewCellAccessoryDisclosureIndicator;
            break;
        }
    }
    return cell;
}

- (void)fillCell:(UITableViewCell *)cell withName:(NSString *)name subtitle:(NSString *)sub {
    SCIExpFlagOverride o = [SCIExpFlags overrideForName:name];
    NSString *prefix = o == SCIExpFlagOverrideTrue ? @"● " : o == SCIExpFlagOverrideFalse ? @"○ " : @"";
    cell.textLabel.text = [prefix stringByAppendingString:name];
    cell.textLabel.font = [UIFont monospacedSystemFontOfSize:13 weight:UIFontWeightRegular];
    cell.textLabel.textColor = o == SCIExpFlagOverrideOff ? UIColor.labelColor : UIColor.systemOrangeColor;

    NSMutableArray *parts = [NSMutableArray array];
    if (sub.length) [parts addObject:sub];
    if (o == SCIExpFlagOverrideTrue)  [parts addObject:@"FORCED ON"];
    if (o == SCIExpFlagOverrideFalse) [parts addObject:@"FORCED OFF"];
    cell.detailTextLabel.text = [parts componentsJoinedByString:@" · "];
    cell.accessoryType = UITableViewCellAccessoryDisclosureIndicator;
}

- (void)tableView:(UITableView *)tv didSelectRowAtIndexPath:(NSIndexPath *)ip {
    [tv deselectRowAtIndexPath:ip animated:YES];
    UITableViewCell *cell = [tv cellForRowAtIndexPath:ip];
    id row = [self filteredRows][ip.row];
    switch (self.tab) {
        case SCIExpTabBrowser:
            if (ip.row == 0) [self openNativeBrowser];
            else [self promptAddByName];
            break;
        case SCIExpTabMeta:
            [self presentOverrideSheetForName:((SCIExpObservation *)row).experimentName fromCell:cell];
            break;
        case SCIExpTabMC: {
            SCIExpMCObservation *o = row;
            [self presentCopySheetWithText:[NSString stringWithFormat:@"%llu", o.paramID] title:@"MobileConfig param" fromCell:cell];
            break;
        }
        case SCIExpTabScanned: {
            NSString *line = (NSString *)row;
            unsigned long long spec = [self internalUseSpecifierFromLine:line];
            if (spec) [self presentInternalUseOverrideSheetForSpecifier:spec line:line fromCell:cell];
            else [self presentCopySheetWithText:line title:@"Scanned name" fromCell:cell];
            break;
        }
        case SCIExpTabOverrides: {
            NSString *line = (NSString *)row;
            unsigned long long spec = [self internalUseSpecifierFromLine:line];
            if (spec) [self presentInternalUseOverrideSheetForSpecifier:spec line:line fromCell:cell];
            else [self presentOverrideSheetForName:line fromCell:cell];
            break;
        }
    }
}

- (void)openNativeBrowser {
    Class cls = NSClassFromString(@"MetaLocalExperimentListViewController");
    if (!cls) { [SCIUtils showErrorHUDWithDescription:@"Native browser missing"]; return; }
    SEL initSel = NSSelectorFromString(@"initWithExperimentConfigs:experimentGenerator:");
    UIViewController *vc = nil;
    @try {
        if ([cls instancesRespondToSelector:initSel]) {
            id (*send)(id, SEL, id, id) = (id (*)(id, SEL, id, id))objc_msgSend;
            vc = send([cls alloc], initSel, [self nativeBrowserConfigs], [self nativeBrowserGenerator]);
        } else {
            vc = [[cls alloc] init];
        }
    } @catch (__unused id e) {}
    if (!vc) { [SCIUtils showErrorHUDWithDescription:@"Init failed"]; return; }
    UINavigationController *nav = [[UINavigationController alloc] initWithRootViewController:vc];
    nav.modalPresentationStyle = UIModalPresentationFullScreen;
    [self presentViewController:nav animated:YES completion:nil];
}

- (NSArray *)nativeBrowserConfigs {
    Protocol *p = objc_getProtocol("MetaLocalExperimentConfigProtocol");
    if (!p) return @[];
    unsigned int n = 0;
    Class *all = objc_copyClassList(&n);
    NSMutableArray *out = [NSMutableArray array];
    for (unsigned int i = 0; i < n; i++) {
        if (class_conformsToProtocol(all[i], p)) {
            @try { id x = [[all[i] alloc] init]; if (x) [out addObject:x]; } @catch (__unused id e) {}
        }
    }
    if (all) free(all);
    return out;
}

- (id)nativeBrowserGenerator {
    Class c = NSClassFromString(@"LIDExperimentGenerator");
    if (!c) return nil;
    SEL s = NSSelectorFromString(@"initWithDeviceID:logger:");
    if (![c instancesRespondToSelector:s]) return nil;
    id (*send)(id, SEL, id, id) = (id (*)(id, SEL, id, id))objc_msgSend;
    return send([c alloc], s, nil, nil);
}

- (void)promptAddByName {
    UIAlertController *a = [UIAlertController alertControllerWithTitle:@"Add override" message:@"Substring match, case-insensitive." preferredStyle:UIAlertControllerStyleAlert];
    [a addTextFieldWithConfigurationHandler:^(UITextField *tf) {
        tf.placeholder = @"name (e.g. liquidglass)";
        tf.autocapitalizationType = UITextAutocapitalizationTypeNone;
        tf.autocorrectionType = UITextAutocorrectionTypeNo;
    }];
    [a addAction:[UIAlertAction actionWithTitle:@"Cancel" style:UIAlertActionStyleCancel handler:nil]];
    [a addAction:[UIAlertAction actionWithTitle:@"Force ON" style:UIAlertActionStyleDefault handler:^(UIAlertAction *_) {
        NSString *n = [a.textFields.firstObject.text stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceCharacterSet]];
        if (n.length) { [SCIExpFlags setOverride:SCIExpFlagOverrideTrue forName:n]; [self refresh]; }
    }]];
    [a addAction:[UIAlertAction actionWithTitle:@"Force OFF" style:UIAlertActionStyleDefault handler:^(UIAlertAction *_) {
        NSString *n = [a.textFields.firstObject.text stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceCharacterSet]];
        if (n.length) { [SCIExpFlags setOverride:SCIExpFlagOverrideFalse forName:n]; [self refresh]; }
    }]];
    [self presentViewController:a animated:YES completion:nil];
}

- (void)presentOverrideSheetForName:(NSString *)name fromCell:(UITableViewCell *)cell {
    SCIExpFlagOverride cur = [SCIExpFlags overrideForName:name];
    UIAlertController *sheet = [UIAlertController alertControllerWithTitle:name message:nil preferredStyle:UIAlertControllerStyleActionSheet];
    NSArray *opts = @[@{@"t": @"No override", @"v": @(SCIExpFlagOverrideOff)},
                      @{@"t": @"Force ON",    @"v": @(SCIExpFlagOverrideTrue)},
                      @{@"t": @"Force OFF",   @"v": @(SCIExpFlagOverrideFalse)}];
    for (NSDictionary *o in opts) {
        NSString *t = o[@"t"];
        if (((NSNumber *)o[@"v"]).integerValue == cur) t = [t stringByAppendingString:@"  ✓"];
        [sheet addAction:[UIAlertAction actionWithTitle:t style:UIAlertActionStyleDefault handler:^(UIAlertAction *_) {
            [SCIExpFlags setOverride:((NSNumber *)o[@"v"]).integerValue forName:name];
            [self refresh];
        }]];
    }
    [sheet addAction:[UIAlertAction actionWithTitle:@"Copy name" style:UIAlertActionStyleDefault handler:^(UIAlertAction *_) {
        [UIPasteboard generalPasteboard].string = name;
    }]];
    [sheet addAction:[UIAlertAction actionWithTitle:@"Cancel" style:UIAlertActionStyleCancel handler:nil]];
    if (sheet.popoverPresentationController) {
        sheet.popoverPresentationController.sourceView = cell;
        sheet.popoverPresentationController.sourceRect = cell.bounds;
    }
    [self presentViewController:sheet animated:YES completion:nil];
}

- (void)presentInternalUseOverrideSheetForSpecifier:(unsigned long long)specifier line:(NSString *)line fromCell:(UITableViewCell *)cell {
    SCIExpFlagOverride cur = [SCIExpFlags internalUseOverrideForSpecifier:specifier];
    NSString *title = [NSString stringWithFormat:@"InternalUse 0x%016llx", specifier];
    UIAlertController *sheet = [UIAlertController alertControllerWithTitle:title message:line preferredStyle:UIAlertControllerStyleActionSheet];
    NSArray *opts = @[@{@"t": @"No override", @"v": @(SCIExpFlagOverrideOff)},
                      @{@"t": @"Force ON",    @"v": @(SCIExpFlagOverrideTrue)},
                      @{@"t": @"Force OFF",   @"v": @(SCIExpFlagOverrideFalse)}];
    for (NSDictionary *o in opts) {
        NSString *t = o[@"t"];
        if (((NSNumber *)o[@"v"]).integerValue == cur) t = [t stringByAppendingString:@"  ✓"];
        [sheet addAction:[UIAlertAction actionWithTitle:t style:UIAlertActionStyleDefault handler:^(UIAlertAction *_) {
            [SCIExpFlags setInternalUseOverride:((NSNumber *)o[@"v"]).integerValue forSpecifier:specifier];
            [self refresh];
        }]];
    }
    [sheet addAction:[UIAlertAction actionWithTitle:@"Copy specifier" style:UIAlertActionStyleDefault handler:^(UIAlertAction *_) {
        [UIPasteboard generalPasteboard].string = [NSString stringWithFormat:@"0x%016llx", specifier];
    }]];
    [sheet addAction:[UIAlertAction actionWithTitle:@"Copy row" style:UIAlertActionStyleDefault handler:^(UIAlertAction *_) {
        [UIPasteboard generalPasteboard].string = line;
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
    [sheet addAction:[UIAlertAction actionWithTitle:@"Copy" style:UIAlertActionStyleDefault handler:^(UIAlertAction *_) {
        [UIPasteboard generalPasteboard].string = text;
    }]];
    [sheet addAction:[UIAlertAction actionWithTitle:@"Cancel" style:UIAlertActionStyleCancel handler:nil]];
    if (sheet.popoverPresentationController) {
        sheet.popoverPresentationController.sourceView = cell;
        sheet.popoverPresentationController.sourceRect = cell.bounds;
    }
    [self presentViewController:sheet animated:YES completion:nil];
}

- (void)confirmResetAll {
    UIAlertController *a = [UIAlertController alertControllerWithTitle:@"Reset all?" message:nil preferredStyle:UIAlertControllerStyleAlert];
    [a addAction:[UIAlertAction actionWithTitle:@"Cancel" style:UIAlertActionStyleCancel handler:nil]];
    [a addAction:[UIAlertAction actionWithTitle:@"Reset" style:UIAlertActionStyleDestructive handler:^(UIAlertAction *_) {
        [SCIExpFlags resetAllOverrides];
        [SCIExpFlags resetAllInternalUseOverrides];
        [self refresh];
    }]];
    [self presentViewController:a animated:YES completion:nil];
}

- (void)searchBar:(UISearchBar *)searchBar textDidChange:(NSString *)text {
    self.query = text;
    [self.tableView reloadData];
    [self updateEmpty];
}
- (void)searchBarSearchButtonClicked:(UISearchBar *)searchBar { [searchBar resignFirstResponder]; }

@end
