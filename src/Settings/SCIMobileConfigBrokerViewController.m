// MC Broker param browser — lazy name resolution, never resolves all rows upfront.
// Primary display is the resolved feature/class name; hex ID is fallback + detail.

#import "SCIMobileConfigBrokerViewController.h"
#import "../Features/ExpFlags/SCIExpFlags.h"
#import "../Utils.h"

typedef NS_ENUM(NSInteger, SCIMCBrokerTab) {
    SCIMCBrokerTabObserved = 0,
    SCIMCBrokerTabOverrides,
};

// Resolver stub — returns nil until Commits A/B/C wire in SCIDexKitNameResolver +
// SCIMCRuntimeObservationBuffer. The VC's lazy-dispatch pattern stays unchanged.
static NSString *SCIMCBrokerResolveName(__unused unsigned long long paramID) {
    return nil;
}

@interface SCIMobileConfigBrokerViewController () <UITableViewDataSource, UITableViewDelegate, UISearchBarDelegate>
@property (nonatomic, strong) UISegmentedControl *seg;
@property (nonatomic, strong) UISearchBar        *searchBar;
@property (nonatomic, strong) UITableView        *tableView;
@property (nonatomic, strong) UILabel            *empty;

@property (nonatomic, assign) SCIMCBrokerTab tab;
@property (nonatomic, copy)   NSString       *query;

@property (nonatomic, strong) NSArray<SCIExpMCObservation *> *obs;

// key = decimal paramID string, value = resolved name or @"" (already attempted, no result)
@property (nonatomic, strong) NSMutableDictionary<NSString *, NSString *> *nameCache;
@end

@implementation SCIMobileConfigBrokerViewController

- (void)viewDidLoad {
    [super viewDidLoad];
    self.title = @"MC Broker";
    self.view.backgroundColor = UIColor.systemBackgroundColor;
    self.nameCache = [NSMutableDictionary dictionary];

    self.navigationItem.leftBarButtonItem = [[UIBarButtonItem alloc]
        initWithImage:[UIImage systemImageNamed:@"xmark.circle"]
                style:UIBarButtonItemStylePlain
               target:self
               action:@selector(confirmResetOverrides)];

    self.navigationItem.rightBarButtonItem = [[UIBarButtonItem alloc]
        initWithImage:[UIImage systemImageNamed:@"square.and.arrow.up"]
                style:UIBarButtonItemStylePlain
               target:self
               action:@selector(exportJSON)];

    self.seg = [[UISegmentedControl alloc] initWithItems:@[@"Observed", @"Overrides"]];
    self.seg.selectedSegmentIndex = SCIMCBrokerTabObserved;
    self.tab = SCIMCBrokerTabObserved;
    [self.seg addTarget:self action:@selector(segChanged) forControlEvents:UIControlEventValueChanged];
    self.seg.translatesAutoresizingMaskIntoConstraints = NO;
    [self.view addSubview:self.seg];

    self.searchBar = [UISearchBar new];
    self.searchBar.searchBarStyle = UISearchBarStyleMinimal;
    self.searchBar.placeholder = @"Search name or hex ID";
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

        [self.empty.centerXAnchor constraintEqualToAnchor:self.tableView.centerXAnchor],
        [self.empty.centerYAnchor constraintEqualToAnchor:self.tableView.centerYAnchor],
        [self.empty.leadingAnchor constraintEqualToAnchor:g.leadingAnchor constant:24],
        [self.empty.trailingAnchor constraintEqualToAnchor:g.trailingAnchor constant:-24],
    ]];
}

- (void)viewWillAppear:(BOOL)animated { [super viewWillAppear:animated]; [self refresh]; }

// MARK: - State

- (void)segChanged {
    self.tab = (SCIMCBrokerTab)self.seg.selectedSegmentIndex;
    [self refresh];
}

- (void)refresh {
    // allMCObservations returns sorted by hitCount descending.
    self.obs = [SCIExpFlags allMCObservations];
    [self.tableView reloadData];
    [self updateEmpty];
    // nameCache intentionally NOT cleared — resolved names persist across refreshes.
}

- (void)updateEmpty {
    if ([self filteredRows].count == 0) {
        self.empty.text = self.tab == SCIMCBrokerTabOverrides ? @"No overrides." : @"Browse Instagram to populate.";
        self.empty.hidden = NO;
    } else {
        self.empty.hidden = YES;
    }
}

// MARK: - Filter

- (NSArray<SCIExpMCObservation *> *)filteredRows {
    NSArray<SCIExpMCObservation *> *source = self.obs ?: @[];

    if (self.tab == SCIMCBrokerTabOverrides) {
        NSMutableArray *filtered = [NSMutableArray array];
        for (SCIExpMCObservation *o in source) {
            NSString *key = [NSString stringWithFormat:@"%llu", o.paramID];
            if ([SCIExpFlags overrideForName:key] != SCIExpFlagOverrideOff) [filtered addObject:o];
        }
        source = filtered;
    }

    if (!self.query.length) return source;

    NSString *q = self.query.lowercaseString;
    NSMutableArray *out = [NSMutableArray array];
    for (SCIExpMCObservation *o in source) {
        NSString *key = [NSString stringWithFormat:@"%llu", o.paramID];
        NSString *hex = [NSString stringWithFormat:@"0x%016llx", o.paramID];
        NSString *cached = self.nameCache[key];
        BOOL matchesHex  = [hex containsString:q] || [key containsString:q];
        BOOL matchesName = cached.length && [cached.lowercaseString containsString:q];
        if (matchesHex || matchesName) [out addObject:o];
    }
    return out;
}

// MARK: - Table

- (NSInteger)tableView:(UITableView *)tv numberOfRowsInSection:(NSInteger)section {
    return (NSInteger)[self filteredRows].count;
}

- (UITableViewCell *)tableView:(UITableView *)tv cellForRowAtIndexPath:(NSIndexPath *)ip {
    UITableViewCell *cell = [tv dequeueReusableCellWithIdentifier:@"cell" forIndexPath:ip];
    cell.accessoryType = UITableViewCellAccessoryDisclosureIndicator;
    cell.selectionStyle = UITableViewCellSelectionStyleDefault;
    cell.textLabel.numberOfLines = 1;

    NSArray<SCIExpMCObservation *> *rows = [self filteredRows];
    if ((NSUInteger)ip.row >= rows.count) return cell;
    SCIExpMCObservation *o = rows[(NSUInteger)ip.row];

    NSString *key  = [NSString stringWithFormat:@"%llu", o.paramID];
    NSString *hex  = [NSString stringWithFormat:@"0x%016llx", o.paramID];
    NSString *type = [self typeString:o.type];

    SCIExpFlagOverride ov = [SCIExpFlags overrideForName:key];
    BOOL overridden = (ov != SCIExpFlagOverrideOff);

    NSString *cached = self.nameCache[key]; // nil = not yet attempted, @"" = attempted, no result

    if (cached.length) {
        // Resolution succeeded: name is primary, hex moves to detail.
        NSString *prefix = ov == SCIExpFlagOverrideTrue ? @"● " : ov == SCIExpFlagOverrideFalse ? @"○ " : @"";
        cell.textLabel.text = [prefix stringByAppendingString:cached];
        cell.textLabel.font = [UIFont systemFontOfSize:14 weight:UIFontWeightRegular];
        cell.textLabel.textColor = overridden ? UIColor.systemOrangeColor : UIColor.labelColor;
        cell.detailTextLabel.text = [NSString stringWithFormat:@"%@ · %@ · ×%lu",
                                     hex, type, (unsigned long)o.hitCount];
    } else {
        // Fallback: show hex as primary in monospaced secondary color.
        NSString *prefix = ov == SCIExpFlagOverrideTrue ? @"● " : ov == SCIExpFlagOverrideFalse ? @"○ " : @"";
        cell.textLabel.text = [prefix stringByAppendingString:hex];
        cell.textLabel.font = [UIFont monospacedSystemFontOfSize:13 weight:UIFontWeightRegular];
        cell.textLabel.textColor = overridden ? UIColor.systemOrangeColor : UIColor.secondaryLabelColor;
        cell.detailTextLabel.text = [NSString stringWithFormat:@"%@ · default=%@ · ×%lu",
                                     type, o.lastDefault ?: @"?", (unsigned long)o.hitCount];

        if (cached == nil) {
            // First time seeing this cell — kick off async resolution.
            [self resolveAsyncForParamID:o.paramID key:key indexPath:ip tableView:tv];
        }
    }

    return cell;
}

- (void)resolveAsyncForParamID:(unsigned long long)paramID
                           key:(NSString *)key
                     indexPath:(NSIndexPath *)ip
                     tableView:(UITableView *)tv {
    // Mark as in-flight immediately to prevent duplicate dispatches on reuse.
    self.nameCache[key] = @"";

    dispatch_async(dispatch_get_global_queue(QOS_CLASS_UTILITY, 0), ^{
        NSString *name = SCIMCBrokerResolveName(paramID);
        dispatch_async(dispatch_get_main_queue(), ^{
            self.nameCache[key] = name ?: @"";
            if (name.length && [tv.indexPathsForVisibleRows containsObject:ip]) {
                [tv reloadRowsAtIndexPaths:@[ip] withRowAnimation:UITableViewRowAnimationNone];
            }
        });
    });
}

- (void)tableView:(UITableView *)tv didSelectRowAtIndexPath:(NSIndexPath *)ip {
    [tv deselectRowAtIndexPath:ip animated:YES];
    NSArray<SCIExpMCObservation *> *rows = [self filteredRows];
    if ((NSUInteger)ip.row >= rows.count) return;
    SCIExpMCObservation *o = rows[(NSUInteger)ip.row];
    UITableViewCell *cell = [tv cellForRowAtIndexPath:ip];
    [self presentActionSheetForObservation:o fromCell:cell];
}

// MARK: - Action sheet

- (void)presentActionSheetForObservation:(SCIExpMCObservation *)o fromCell:(UITableViewCell *)cell {
    NSString *key      = [NSString stringWithFormat:@"%llu", o.paramID];
    NSString *hex      = [NSString stringWithFormat:@"0x%016llx", o.paramID];
    NSString *cached   = self.nameCache[key];
    NSString *title    = cached.length ? cached : hex;
    NSString *message  = cached.length ? hex : nil;

    SCIExpFlagOverride cur = [SCIExpFlags overrideForName:key];

    UIAlertController *sheet = [UIAlertController alertControllerWithTitle:title
                                                                   message:message
                                                            preferredStyle:UIAlertControllerStyleActionSheet];

    if (cached.length) {
        [sheet addAction:[UIAlertAction actionWithTitle:@"Copy name" style:UIAlertActionStyleDefault handler:^(UIAlertAction *_) {
            [UIPasteboard generalPasteboard].string = cached;
        }]];
    }

    [sheet addAction:[UIAlertAction actionWithTitle:@"Copy hex" style:UIAlertActionStyleDefault handler:^(UIAlertAction *_) {
        [UIPasteboard generalPasteboard].string = hex;
    }]];

    [sheet addAction:[UIAlertAction actionWithTitle:@"Copy decimal" style:UIAlertActionStyleDefault handler:^(UIAlertAction *_) {
        [UIPasteboard generalPasteboard].string = key;
    }]];

    NSArray *overrideOpts = @[
        @{@"t": @"No override", @"v": @(SCIExpFlagOverrideOff)},
        @{@"t": @"Force ON",    @"v": @(SCIExpFlagOverrideTrue)},
        @{@"t": @"Force OFF",   @"v": @(SCIExpFlagOverrideFalse)},
    ];
    for (NSDictionary *opt in overrideOpts) {
        NSInteger val = ((NSNumber *)opt[@"v"]).integerValue;
        NSString *label = opt[@"t"];
        if (val == cur) label = [label stringByAppendingString:@"  ✓"];
        [sheet addAction:[UIAlertAction actionWithTitle:label style:UIAlertActionStyleDefault handler:^(UIAlertAction *_) {
            [SCIExpFlags setOverride:(SCIExpFlagOverride)val forName:key];
            [self refresh];
        }]];
    }

    [sheet addAction:[UIAlertAction actionWithTitle:@"Cancel" style:UIAlertActionStyleCancel handler:nil]];

    if (sheet.popoverPresentationController) {
        sheet.popoverPresentationController.sourceView = cell;
        sheet.popoverPresentationController.sourceRect = cell.bounds;
    }
    [self presentViewController:sheet animated:YES completion:nil];
}

// MARK: - Export

- (void)exportJSON {
    dispatch_async(dispatch_get_global_queue(QOS_CLASS_UTILITY, 0), ^{
        NSArray<SCIExpMCObservation *> *all = [SCIExpFlags allMCObservations];
        NSMutableArray *rows = [NSMutableArray arrayWithCapacity:all.count];
        for (SCIExpMCObservation *o in all) {
            NSString *key  = [NSString stringWithFormat:@"%llu", o.paramID];
            NSString *hex  = [NSString stringWithFormat:@"0x%016llx", o.paramID];
            NSString *name = self.nameCache[key] ?: @"";
            [rows addObject:@{
                @"id":      key,
                @"hex":     hex,
                @"name":    name,
                @"type":    [self typeString:o.type],
                @"hits":    @(o.hitCount),
                @"default": o.lastDefault ?: @"",
            }];
        }
        NSError *err = nil;
        NSData *json = [NSJSONSerialization dataWithJSONObject:rows
                                                       options:NSJSONWritingPrettyPrinted
                                                         error:&err];
        dispatch_async(dispatch_get_main_queue(), ^{
            if (!json) {
                [SCIUtils showErrorHUDWithDescription:@"Export failed"];
                return;
            }
            NSURL *tmp = [NSURL fileURLWithPath:[NSTemporaryDirectory() stringByAppendingPathComponent:@"mcbroker.json"]];
            [json writeToURL:tmp atomically:YES];
            UIActivityViewController *av = [[UIActivityViewController alloc] initWithActivityItems:@[tmp] applicationActivities:nil];
            if (av.popoverPresentationController) {
                av.popoverPresentationController.barButtonItem = self.navigationItem.rightBarButtonItem;
            }
            [self presentViewController:av animated:YES completion:nil];
        });
    });
}

// MARK: - Reset

- (void)confirmResetOverrides {
    UIAlertController *a = [UIAlertController alertControllerWithTitle:@"Reset all MC overrides?"
                                                               message:nil
                                                        preferredStyle:UIAlertControllerStyleAlert];
    [a addAction:[UIAlertAction actionWithTitle:@"Cancel" style:UIAlertActionStyleCancel handler:nil]];
    [a addAction:[UIAlertAction actionWithTitle:@"Reset" style:UIAlertActionStyleDestructive handler:^(UIAlertAction *_) {
        // Remove only overrides whose keys are decimal paramIDs.
        for (SCIExpMCObservation *o in self.obs) {
            NSString *key = [NSString stringWithFormat:@"%llu", o.paramID];
            if ([SCIExpFlags overrideForName:key] != SCIExpFlagOverrideOff) {
                [SCIExpFlags setOverride:SCIExpFlagOverrideOff forName:key];
            }
        }
        [self refresh];
    }]];
    [self presentViewController:a animated:YES completion:nil];
}

// MARK: - Search

- (void)searchBar:(UISearchBar *)searchBar textDidChange:(NSString *)text {
    self.query = text;
    [self.tableView reloadData];
    [self updateEmpty];
}
- (void)searchBarSearchButtonClicked:(UISearchBar *)searchBar { [searchBar resignFirstResponder]; }

// MARK: - Helpers

- (NSString *)typeString:(SCIExpMCType)type {
    switch (type) {
        case SCIExpMCTypeBool:   return @"bool";
        case SCIExpMCTypeInt:    return @"int64";
        case SCIExpMCTypeDouble: return @"double";
        case SCIExpMCTypeString: return @"string";
    }
    return @"?";
}

@end
