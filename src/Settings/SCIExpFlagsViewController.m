// Exp flag browser + override editor.
// Tabs: Browser(native) | Meta(override) | MC(view) | Scanned/InternalUse(override) | Overrides

#import "SCIExpFlagsViewController.h"
#import "SCIResolverScanner.h"
#import "SCIResolverSpecifierEntry.h"
#import "../Features/ExpFlags/SCIExpFlags.h"
#import "../Utils.h"
#import <objc/runtime.h>
#import <objc/message.h>

static const void *kSCIInternalUseSwitchSpecifierKey = &kSCIInternalUseSwitchSpecifierKey;

typedef NS_ENUM(NSInteger, SCIExpTab) {
    SCIExpTabBrowser = 0,
    SCIExpTabMeta,
    SCIExpTabMC,
    SCIExpTabScanned,
    SCIExpTabOverrides,
};

typedef NS_ENUM(NSInteger, SCIInternalUseCategory) {
    SCIInternalUseCategoryHot = 0,
    SCIInternalUseCategoryChanged,
    SCIInternalUseCategoryOn,
    SCIInternalUseCategoryOff,
    SCIInternalUseCategoryRecent,
};

@interface SCIExpFlagsViewController () <UITableViewDataSource, UITableViewDelegate, UISearchBarDelegate>
@property (nonatomic, strong) UISegmentedControl *seg;
@property (nonatomic, strong) UISegmentedControl *internalCatSeg;
@property (nonatomic, strong) UISearchBar *searchBar;
@property (nonatomic, strong) UITableView *tableView;
@property (nonatomic, strong) UIActivityIndicatorView *spinner;
@property (nonatomic, strong) UILabel *empty;

@property (nonatomic, assign) SCIExpTab tab;
@property (nonatomic, assign) SCIInternalUseCategory internalCategory;
@property (nonatomic, copy)   NSString *query;

@property (nonatomic, strong) NSArray<SCIExpObservation *>   *metaObs;
@property (nonatomic, strong) NSArray<SCIExpMCObservation *> *mcObs;
@property (nonatomic, strong) NSArray<NSString *>            *scannedNames;
@property (nonatomic, assign) BOOL scannedLoading;
@property (nonatomic, strong) NSArray<NSString *>            *overriddenNames;
@property (nonatomic, strong) NSArray<SCIResolverSpecifierEntry *> *resolverEntries;
@end

@implementation SCIExpFlagsViewController

- (void)viewDidLoad {
    [super viewDidLoad];
    self.title = @"Experimental flags";
    self.view.backgroundColor = UIColor.systemBackgroundColor;
    self.navigationItem.rightBarButtonItem = [[UIBarButtonItem alloc]
        initWithTitle:@"Bulk" style:UIBarButtonItemStylePlain target:self action:@selector(presentBulkActions)];

    self.seg = [[UISegmentedControl alloc] initWithItems:@[@"Browser", @"Meta", @"MC IDs", @"Internal (tap to override)", @"Overrides"]];
    self.seg.selectedSegmentIndex = SCIExpTabMeta;
    self.tab = SCIExpTabMeta;
    [self.seg addTarget:self action:@selector(segChanged) forControlEvents:UIControlEventValueChanged];
    self.seg.translatesAutoresizingMaskIntoConstraints = NO;
    [self.view addSubview:self.seg];

    self.internalCatSeg = [[UISegmentedControl alloc] initWithItems:@[@"Hot", @"Changed", @"On", @"Off", @"Recent"]];
    self.internalCatSeg.selectedSegmentIndex = SCIInternalUseCategoryHot;
    self.internalCategory = SCIInternalUseCategoryHot;
    [self.internalCatSeg addTarget:self action:@selector(internalCategoryChanged) forControlEvents:UIControlEventValueChanged];
    self.internalCatSeg.translatesAutoresizingMaskIntoConstraints = NO;
    self.internalCatSeg.hidden = YES;
    [self.view addSubview:self.internalCatSeg];

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

        [self.internalCatSeg.topAnchor constraintEqualToAnchor:self.seg.bottomAnchor constant:6],
        [self.internalCatSeg.leadingAnchor constraintEqualToAnchor:g.leadingAnchor constant:12],
        [self.internalCatSeg.trailingAnchor constraintEqualToAnchor:g.trailingAnchor constant:-12],

        [self.searchBar.topAnchor constraintEqualToAnchor:self.internalCatSeg.bottomAnchor constant:4],
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
    self.internalCatSeg.hidden = self.tab != SCIExpTabScanned;
    if (self.tab == SCIExpTabScanned && !self.scannedNames && !self.scannedLoading) [self loadScanned];
    [self refresh];
}

- (void)internalCategoryChanged {
    self.internalCategory = (SCIInternalUseCategory)self.internalCatSeg.selectedSegmentIndex;
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
    self.resolverEntries = [SCIResolverScanner allKnownSpecifierEntries];
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
            case SCIExpTabScanned:   self.empty.text = self.query.length ? @"No match" : @"Browse IG to populate InternalUse calls.\nTap cell to override (Off/True/False)."; break;
            case SCIExpTabOverrides: self.empty.text = @"None."; break;
        }
        self.empty.hidden = NO;
        return;
    }
    self.empty.hidden = YES;
}

// Data

- (NSArray *)filteredRows {
    switch (self.tab) {
        case SCIExpTabBrowser:   return @[@"Open native LocalExperiment list", @"LID / Family diagnostics", @"Add MetaLocal override"];
        case SCIExpTabMeta:      return [self filtered:self.metaObs keyPath:@"experimentName"];
        case SCIExpTabMC:        return [self filterMC:self.mcObs];
        case SCIExpTabScanned:   return [self filteredInternalRows];
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
        NSString *s = [NSString stringWithFormat:@"%llu %@ %@", o.paramID, [self mcTypeName:o.type], o.lastDefault ?: @""];
        if ([s.lowercaseString containsString:q]) [out addObject:o];
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

- (NSArray *)filteredInternalRows {
    NSArray<SCIExpInternalUseObservation *> *obs = [SCIExpFlags allInternalUseObservations] ?: @[];
    NSMutableArray *rows = [obs mutableCopy];
    
    NSMutableSet<NSNumber *> *observedSpecs = [NSMutableSet set];
    for (SCIExpInternalUseObservation *o in obs) {
        [observedSpecs addObject:@(o.specifier)];
    }
    
    for (SCIResolverSpecifierEntry *e in self.resolverEntries) {
        if (![observedSpecs containsObject:@(e.specifier)]) {
            [rows addObject:e];
        }
    }

    NSIndexSet *remove = [rows indexesOfObjectsPassingTest:^BOOL(id o, NSUInteger idx, BOOL *stop) {
        BOOL effective = NO;
        BOOL isChanged = NO;
        if ([o isKindOfClass:[SCIExpInternalUseObservation class]]) {
            effective = [self effectiveInternalValue:o];
            SCIExpInternalUseObservation *io = (SCIExpInternalUseObservation *)o;
            isChanged = (io.defaultValue != io.resultValue);
        } else if ([o isKindOfClass:[SCIResolverSpecifierEntry class]]) {
            SCIResolverSpecifierEntry *e = (SCIResolverSpecifierEntry *)o;
            SCIExpFlagOverride ov = [SCIExpFlags internalUseOverrideForSpecifier:e.specifier];
            effective = (ov == SCIExpFlagOverrideTrue);
            isChanged = (ov != SCIExpFlagOverrideOff);
        }
        
        switch (self.internalCategory) {
            case SCIInternalUseCategoryHot:     return NO;
            case SCIInternalUseCategoryChanged: return !isChanged;
            case SCIInternalUseCategoryOn:      return !effective;
            case SCIInternalUseCategoryOff:     return effective;
            case SCIInternalUseCategoryRecent:  return NO;
        }
        return NO;
    }];
    [rows removeObjectsAtIndexes:remove];

    if (self.internalCategory == SCIInternalUseCategoryRecent) {
        [rows sortUsingComparator:^NSComparisonResult(id a, id b) {
            NSUInteger orderA = [a isKindOfClass:[SCIExpInternalUseObservation class]] ? ((SCIExpInternalUseObservation *)a).lastSeenOrder : 0;
            NSUInteger orderB = [b isKindOfClass:[SCIExpInternalUseObservation class]] ? ((SCIExpInternalUseObservation *)b).lastSeenOrder : 0;
            if (orderA != orderB) return orderA > orderB ? NSOrderedAscending : NSOrderedDescending;
            return NSOrderedSame;
        }];
    }

    if (self.query.length) {
        NSString *q = self.query.lowercaseString;
        NSIndexSet *qRemove = [rows indexesOfObjectsPassingTest:^BOOL(id o, NSUInteger idx, BOOL *stop) {
            NSString *s = @"";
            if ([o isKindOfClass:[SCIExpInternalUseObservation class]]) {
                s = [self searchableInternalString:o];
            } else if ([o isKindOfClass:[SCIResolverSpecifierEntry class]]) {
                SCIResolverSpecifierEntry *e = (SCIResolverSpecifierEntry *)o;
                s = [NSString stringWithFormat:@"%@ %@ resolver %@", e.name, [self specifierHex:e.specifier], e.source];
            }
            return ![s.lowercaseString containsString:q];
        }];
        [rows removeObjectsAtIndexes:qRemove];
    }
    return rows;
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

// Internal helpers

- (BOOL)effectiveInternalValue:(SCIExpInternalUseObservation *)o {
    SCIExpFlagOverride ov = [SCIExpFlags internalUseOverrideForSpecifier:o.specifier];
    if (ov == SCIExpFlagOverrideTrue) return YES;
    if (ov == SCIExpFlagOverrideFalse) return NO;
    return o.resultValue;
}

- (NSString *)specifierHex:(unsigned long long)specifier { return [NSString stringWithFormat:@"0x%016llx", specifier]; }

- (NSString *)shortFunctionName:(NSString *)fn {
    if ([fn containsString:@"Sessionless"]) return @"SessionlessBoolean";
    if ([fn containsString:@"BooleanValueForInternalUse"]) return @"Boolean";
    return fn.length ? fn : @"InternalUse";
}

- (NSString *)internalTitle:(SCIExpInternalUseObservation *)o {
    NSString *name = o.specifierName.length ? o.specifierName : @"unknown";
    return [NSString stringWithFormat:@"%@  %@", name, [self specifierHex:o.specifier]];
}

- (NSString *)internalSubtitle:(SCIExpInternalUseObservation *)o {
    NSMutableArray<NSString *> *parts = [NSMutableArray array];
    [parts addObject:[self shortFunctionName:o.functionName]];
    [parts addObject:[NSString stringWithFormat:@"default=%d", o.defaultValue]];
    [parts addObject:[NSString stringWithFormat:@"result=%d", o.resultValue]];
    if (o.defaultValue != o.resultValue) [parts addObject:@"changed"];
    SCIExpFlagOverride ov = [SCIExpFlags internalUseOverrideForSpecifier:o.specifier];
    if (ov == SCIExpFlagOverrideTrue) [parts addObject:@"FORCED ON"];
    if (ov == SCIExpFlagOverrideFalse) [parts addObject:@"FORCED OFF"];
    [parts addObject:[NSString stringWithFormat:@"×%lu", (unsigned long)o.hitCount]];
    [parts addObject:[NSString stringWithFormat:@"recent=%lu", (unsigned long)o.lastSeenOrder]];
    return [parts componentsJoinedByString:@" · "];
}

- (NSString *)searchableInternalString:(SCIExpInternalUseObservation *)o {
    return [NSString stringWithFormat:@"%@ %@ %@ %@ default=%d result=%d x%lu recent=%lu",
            o.functionName ?: @"",
            o.specifierName ?: @"unknown",
            [self specifierHex:o.specifier],
            o.defaultValue != o.resultValue ? @"changed" : @"same",
            o.defaultValue,
            o.resultValue,
            (unsigned long)o.hitCount,
            (unsigned long)o.lastSeenOrder];
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

- (NSString *)mcTypeName:(SCIExpMCType)t {
    switch (t) {
        case SCIExpMCTypeBool:   return @"bool";
        case SCIExpMCTypeInt:    return @"int64";
        case SCIExpMCTypeDouble: return @"double";
        case SCIExpMCTypeString: return @"string";
    }
}

// Table

- (NSInteger)tableView:(UITableView *)tv numberOfRowsInSection:(NSInteger)section { return [self filteredRows].count; }

- (UITableViewCell *)newSubtitleCellWithTableView:(UITableView *)tv identifier:(NSString *)identifier {
    UITableViewCell *cell = [tv dequeueReusableCellWithIdentifier:identifier];
    if (!cell) cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleSubtitle reuseIdentifier:identifier];
    cell.accessoryType = UITableViewCellAccessoryNone;
    cell.accessoryView = nil;
    cell.selectionStyle = UITableViewCellSelectionStyleDefault;
    cell.textLabel.textColor = UIColor.labelColor;
    cell.textLabel.numberOfLines = 0;
    cell.detailTextLabel.textColor = UIColor.secondaryLabelColor;
    cell.detailTextLabel.numberOfLines = 0;
    return cell;
}

- (UITableViewCell *)tableView:(UITableView *)tv cellForRowAtIndexPath:(NSIndexPath *)ip {
    id row = [self filteredRows][ip.row];
    UITableViewCell *cell = [self newSubtitleCellWithTableView:tv identifier:@"subtitle"];

    switch (self.tab) {
        case SCIExpTabBrowser: {
            cell.textLabel.text = (NSString *)row;
            cell.detailTextLabel.text = nil;
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
            cell.textLabel.text = [NSString stringWithFormat:@"%llu", o.paramID];
            cell.textLabel.font = [UIFont monospacedSystemFontOfSize:13 weight:UIFontWeightRegular];
            cell.detailTextLabel.text = [NSString stringWithFormat:@"%@ · default=%@ · ×%lu", [self mcTypeName:o.type], o.lastDefault ?: @"?", (unsigned long)o.hitCount];
            cell.accessoryType = UITableViewCellAccessoryDisclosureIndicator;
            break;
        }
        case SCIExpTabScanned: {
            unsigned long long spec = 0;
            BOOL effective = NO;
            if ([row isKindOfClass:[SCIExpInternalUseObservation class]]) {
                SCIExpInternalUseObservation *o = row;
                spec = o.specifier;
                effective = [self effectiveInternalValue:o];
                cell.textLabel.text = [self internalTitle:o];
                cell.detailTextLabel.text = [self internalSubtitle:o];
            } else if ([row isKindOfClass:[SCIResolverSpecifierEntry class]]) {
                SCIResolverSpecifierEntry *e = row;
                spec = e.specifier;
                SCIExpFlagOverride ov = [SCIExpFlags internalUseOverrideForSpecifier:spec];
                effective = (ov == SCIExpFlagOverrideTrue);
                cell.textLabel.text = [NSString stringWithFormat:@"%@  %@", e.name, [self specifierHex:e.specifier]];
                cell.detailTextLabel.text = [NSString stringWithFormat:@"Resolver: %@ · suggested=%@ · override=%@", e.source, e.suggestedValue ? @"YES" : @"NO", ov == SCIExpFlagOverrideTrue ? @"True" : (ov == SCIExpFlagOverrideFalse ? @"False" : @"None")];
            }
            cell.textLabel.font = [UIFont monospacedSystemFontOfSize:12 weight:UIFontWeightRegular];
            UISwitch *sw = [UISwitch new];
            sw.on = effective;
            objc_setAssociatedObject(sw, kSCIInternalUseSwitchSpecifierKey, @(spec), OBJC_ASSOCIATION_RETAIN_NONATOMIC);
            [sw addTarget:self action:@selector(internalSwitchChanged:) forControlEvents:UIControlEventValueChanged];
            cell.accessoryView = sw;
            break;
        }
        case SCIExpTabOverrides: {
            NSString *line = (NSString *)row;
            unsigned long long spec = [self internalUseSpecifierFromLine:line];
            SCIExpFlagOverride o = spec ? [SCIExpFlags internalUseOverrideForSpecifier:spec] : SCIExpFlagOverrideOff;
            if (!spec) {
                [self fillCell:cell withName:line subtitle:nil];
                break;
            }
            NSString *prefix = o == SCIExpFlagOverrideTrue ? @"● " : o == SCIExpFlagOverrideFalse ? @"○ " : @"";
            cell.textLabel.text = [prefix stringByAppendingString:line];
            cell.textLabel.font = [UIFont monospacedSystemFontOfSize:12 weight:UIFontWeightRegular];
            cell.textLabel.textColor = o == SCIExpFlagOverrideOff ? UIColor.labelColor : UIColor.systemOrangeColor;
            cell.detailTextLabel.text = nil;
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

- (void)internalSwitchChanged:(UISwitch *)sender {
    NSNumber *n = objc_getAssociatedObject(sender, kSCIInternalUseSwitchSpecifierKey);
    if (!n) return;
    [SCIExpFlags setInternalUseOverride:(sender.on ? SCIExpFlagOverrideTrue : SCIExpFlagOverrideFalse)
                            forSpecifier:n.unsignedLongLongValue];
    [self refresh];
}

- (void)tableView:(UITableView *)tv didSelectRowAtIndexPath:(NSIndexPath *)ip {
    [tv deselectRowAtIndexPath:ip animated:YES];
    UITableViewCell *cell = [tv cellForRowAtIndexPath:ip];
    id row = [self filteredRows][ip.row];
    switch (self.tab) {
        case SCIExpTabBrowser:
            if (ip.row == 0) [self openNativeBrowser];
            else if (ip.row == 1) [self openNativeBrowser];
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
            if ([row isKindOfClass:[SCIExpInternalUseObservation class]]) {
                [self presentInternalUseOverrideSheetForObservation:row fromCell:cell];
            } else if ([row isKindOfClass:[SCIResolverSpecifierEntry class]]) {
                SCIResolverSpecifierEntry *e = row;
                NSString *line = [NSString stringWithFormat:@"%@\nResolver: %@ · suggested=%@", e.name, e.source, e.suggestedValue ? @"YES" : @"NO"];
                [self presentInternalUseOverrideSheetForSpecifier:e.specifier line:line fromCell:cell];
            }
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

// Actions

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
    SEL internalSel = NSSelectorFromString(@"setIsSessionlessCaaInternal:");
    if ([vc respondsToSelector:internalSel]) {
        ((void (*)(id, SEL, BOOL))objc_msgSend)(vc, internalSel, YES);
    }
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
    if (!c) c = objc_getClass("LIDExperimentGenerator");
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

- (void)presentInternalUseOverrideSheetForObservation:(SCIExpInternalUseObservation *)o fromCell:(UITableViewCell *)cell {
    [self presentInternalUseOverrideSheetForSpecifier:o.specifier line:[NSString stringWithFormat:@"%@\n%@", [self internalTitle:o], [self internalSubtitle:o]] fromCell:cell];
}

- (void)presentInternalUseOverrideSheetForSpecifier:(unsigned long long)specifier line:(NSString *)line fromCell:(UITableViewCell *)cell {
    SCIExpFlagOverride cur = [SCIExpFlags internalUseOverrideForSpecifier:specifier];
    NSString *title = [NSString stringWithFormat:@"InternalUse %@", [self specifierHex:specifier]];
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
        [UIPasteboard generalPasteboard].string = [self specifierHex:specifier];
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

- (void)presentBulkActions {
    UIAlertController *sheet = [UIAlertController alertControllerWithTitle:@"Bulk actions" message:nil preferredStyle:UIAlertControllerStyleActionSheet];

    if (self.tab == SCIExpTabScanned) {
        NSArray<SCIExpInternalUseObservation *> *visible = [self filteredInternalRows];
        NSString *msg = [NSString stringWithFormat:@"%lu visible InternalUse items", (unsigned long)visible.count];
        sheet.message = msg;
        [sheet addAction:[UIAlertAction actionWithTitle:@"Force visible ON" style:UIAlertActionStyleDefault handler:^(UIAlertAction *_) {
            for (SCIExpInternalUseObservation *o in visible) [SCIExpFlags setInternalUseOverride:SCIExpFlagOverrideTrue forSpecifier:o.specifier];
            [self refresh];
        }]];
        [sheet addAction:[UIAlertAction actionWithTitle:@"Force visible OFF" style:UIAlertActionStyleDefault handler:^(UIAlertAction *_) {
            for (SCIExpInternalUseObservation *o in visible) [SCIExpFlags setInternalUseOverride:SCIExpFlagOverrideFalse forSpecifier:o.specifier];
            [self refresh];
        }]];
        [sheet addAction:[UIAlertAction actionWithTitle:@"Invert visible" style:UIAlertActionStyleDefault handler:^(UIAlertAction *_) {
            for (SCIExpInternalUseObservation *o in visible) {
                BOOL effective = [self effectiveInternalValue:o];
                [SCIExpFlags setInternalUseOverride:(effective ? SCIExpFlagOverrideFalse : SCIExpFlagOverrideTrue) forSpecifier:o.specifier];
            }
            [self refresh];
        }]];
        [sheet addAction:[UIAlertAction actionWithTitle:@"Clear visible overrides" style:UIAlertActionStyleDefault handler:^(UIAlertAction *_) {
            for (SCIExpInternalUseObservation *o in visible) [SCIExpFlags setInternalUseOverride:SCIExpFlagOverrideOff forSpecifier:o.specifier];
            [self refresh];
        }]];
    }

    [sheet addAction:[UIAlertAction actionWithTitle:@"Reset all overrides" style:UIAlertActionStyleDestructive handler:^(UIAlertAction *_) {
        [SCIExpFlags resetAllOverrides];
        [SCIExpFlags resetAllInternalUseOverrides];
        [self refresh];
    }]];
    [sheet addAction:[UIAlertAction actionWithTitle:@"Cancel" style:UIAlertActionStyleCancel handler:nil]];
    if (sheet.popoverPresentationController) {
        sheet.popoverPresentationController.barButtonItem = self.navigationItem.rightBarButtonItem;
    }
    [self presentViewController:sheet animated:YES completion:nil];
}

- (void)searchBar:(UISearchBar *)searchBar textDidChange:(NSString *)text {
    self.query = text;
    [self.tableView reloadData];
    [self updateEmpty];
}
- (void)searchBarSearchButtonClicked:(UISearchBar *)searchBar { [searchBar resignFirstResponder]; }

@end
