#import "SCIGatingCatalogViewController.h"
#import "../Features/Gating/SCIGatingCatalog.h"

#pragma mark - Glass toggle cell

@interface SCIGlassToggleCell : UITableViewCell
@property (nonatomic, strong) SCIAdaptiveGlassPanelView *panel;
@property (nonatomic, strong) UILabel *titleLabel;
@property (nonatomic, strong) UILabel *subtitleLabel;
@property (nonatomic, strong) UISwitch *toggle;
@property (nonatomic, copy) void (^onToggle)(BOOL on);
- (void)configureWithTitle:(NSString *)title subtitle:(NSString *)subtitle on:(BOOL)on overridden:(BOOL)overridden interactive:(BOOL)interactive;
@end

@implementation SCIGlassToggleCell

- (instancetype)initWithStyle:(UITableViewCellStyle)style reuseIdentifier:(NSString *)reuseIdentifier {
    self = [super initWithStyle:style reuseIdentifier:reuseIdentifier];
    if (self) {
        self.backgroundColor = UIColor.clearColor;
        self.selectionStyle = UITableViewCellSelectionStyleNone;

        _panel = [[SCIAdaptiveGlassPanelView alloc] initWithRadius:16.0];
        _panel.sciGlassInteractive = YES;
        _panel.translatesAutoresizingMaskIntoConstraints = NO;
        [self.contentView addSubview:_panel];

        _titleLabel = [UILabel new];
        _titleLabel.font = [UIFont monospacedSystemFontOfSize:11.5 weight:UIFontWeightMedium];
        _titleLabel.textColor = UIColor.labelColor;
        _titleLabel.numberOfLines = 2;
        _titleLabel.translatesAutoresizingMaskIntoConstraints = NO;

        _subtitleLabel = [UILabel new];
        _subtitleLabel.font = [UIFont systemFontOfSize:10.0 weight:UIFontWeightLight];
        _subtitleLabel.textColor = UIColor.secondaryLabelColor;
        _subtitleLabel.numberOfLines = 1;
        _subtitleLabel.translatesAutoresizingMaskIntoConstraints = NO;

        UIStackView *stack = [[UIStackView alloc] initWithArrangedSubviews:@[_titleLabel, _subtitleLabel]];
        stack.axis = UILayoutConstraintAxisVertical;
        stack.spacing = 2.0;
        stack.translatesAutoresizingMaskIntoConstraints = NO;
        [_panel.contentView addSubview:stack];

        _toggle = [UISwitch new];
        _toggle.onTintColor = UIColor.systemBlueColor;
        _toggle.translatesAutoresizingMaskIntoConstraints = NO;
        [_toggle addTarget:self action:@selector(switchChanged) forControlEvents:UIControlEventValueChanged];
        [_panel.contentView addSubview:_toggle];

        [_toggle setContentHuggingPriority:UILayoutPriorityRequired forAxis:UILayoutConstraintAxisHorizontal];
        [_toggle setContentCompressionResistancePriority:UILayoutPriorityRequired forAxis:UILayoutConstraintAxisHorizontal];

        [NSLayoutConstraint activateConstraints:@[
            [_panel.topAnchor constraintEqualToAnchor:self.contentView.topAnchor constant:3.0],
            [_panel.leadingAnchor constraintEqualToAnchor:self.contentView.leadingAnchor constant:16.0],
            [_panel.trailingAnchor constraintEqualToAnchor:self.contentView.trailingAnchor constant:-16.0],
            [_panel.bottomAnchor constraintEqualToAnchor:self.contentView.bottomAnchor constant:-3.0],

            [stack.topAnchor constraintEqualToAnchor:_panel.contentView.topAnchor constant:7.0],
            [stack.leadingAnchor constraintEqualToAnchor:_panel.contentView.leadingAnchor constant:14.0],
            [stack.bottomAnchor constraintEqualToAnchor:_panel.contentView.bottomAnchor constant:-7.0],

            [_toggle.leadingAnchor constraintEqualToAnchor:stack.trailingAnchor constant:12.0],
            [_toggle.trailingAnchor constraintEqualToAnchor:_panel.contentView.trailingAnchor constant:-14.0],
            [_toggle.centerYAnchor constraintEqualToAnchor:_panel.contentView.centerYAnchor],
        ]];
    }
    return self;
}

- (void)switchChanged {
    if (self.onToggle) self.onToggle(self.toggle.isOn);
}

- (void)prepareForReuse {
    [super prepareForReuse];
    self.onToggle = nil;
}

- (void)configureWithTitle:(NSString *)title subtitle:(NSString *)subtitle on:(BOOL)on overridden:(BOOL)overridden interactive:(BOOL)interactive {
    self.titleLabel.text = title;
    self.subtitleLabel.text = subtitle;
    self.subtitleLabel.textColor = overridden ? UIColor.systemBlueColor : UIColor.secondaryLabelColor;
    self.panel.sciGlassInteractive = interactive;
    self.panel.sciGlassTintColor = nil;
    self.panel.contentView.alpha = interactive ? 1.0 : 0.55;
    [self.toggle setOn:on animated:NO];
    self.toggle.enabled = interactive;
    self.toggle.alpha = interactive ? 1.0 : 0.4;
}

@end

#pragma mark - row model

typedef NS_ENUM(NSInteger, SCIGatingLiveState) {
    SCIGatingLiveStateUnknown = 0,
    SCIGatingLiveStateUnavailable = 1,
    SCIGatingLiveStateReady = 2,
    SCIGatingLiveStateLoaded = 3,
};

@interface SCIGatingRow : NSObject
@property (nonatomic, copy) NSString *displayClass;
@property (nonatomic, copy) NSString *rawClass;
@property (nonatomic, copy) NSString *selector;
@property (nonatomic, copy) NSString *canonical;
@property (nonatomic, strong, nullable) NSNumber *value;
@property (nonatomic, assign) BOOL blacklisted;
@property (nonatomic, assign) BOOL classMethod;
@property (nonatomic, assign) SCIGatingLiveState liveState;
@end
@implementation SCIGatingRow
@end

#pragma mark - view controller

@interface SCIGatingCatalogViewController () <UITableViewDataSource, UITableViewDelegate, UISearchBarDelegate>
@property (nonatomic, strong) SCIGlassSearchBar *glassSearchBar;
@property (nonatomic, strong) UISearchBar *searchBar;
@property (nonatomic, strong) SCIAdaptiveGlassPanelView *scopePanel;
@property (nonatomic, strong) UISegmentedControl *scopeControl;
@property (nonatomic, strong) UITableView *tableView;
@property (nonatomic, copy) NSArray<NSDictionary *> *allSections;
@property (nonatomic, copy) NSArray<NSDictionary *> *sections;
@property (nonatomic, copy) NSString *query;
@property (nonatomic, assign) BOOL onlyOverridden;
@property (nonatomic, assign) BOOL scopeSelected;
@property (nonatomic, assign) SCIGatingRuntimeScope runtimeScope;
@end

@implementation SCIGatingCatalogViewController

- (void)configureScopeControlAppearance {
    if (!self.scopeControl) return;
    self.scopeControl.backgroundColor = UIColor.clearColor;
    self.scopeControl.selectedSegmentTintColor = SCIIsIOS26OrNewer() ? nil : [UIColor.labelColor colorWithAlphaComponent:0.12];
    NSDictionary *normal = @{ NSForegroundColorAttributeName: UIColor.secondaryLabelColor };
    NSDictionary *selected = @{ NSForegroundColorAttributeName: UIColor.labelColor, NSFontAttributeName: [UIFont systemFontOfSize:13.0 weight:UIFontWeightSemibold] };
    [self.scopeControl setTitleTextAttributes:normal forState:UIControlStateNormal];
    [self.scopeControl setTitleTextAttributes:selected forState:UIControlStateSelected];
}

- (NSString *)subtitleForRow:(SCIGatingRow *)r override:(NSNumber *)ov {
    if (ov != nil) return ov.boolValue ? @"forced ON via getter hook" : @"forced OFF via getter hook";
    if (r.classMethod) return @"class getter · ready to force";
    if (r.blacklisted) return @"live read blocked after prior crash";
    switch (r.liveState) {
        case SCIGatingLiveStateLoaded: return r.value.boolValue ? @"live value: ON" : @"live value: OFF";
        case SCIGatingLiveStateReady: return @"live source available · tap to read";
        case SCIGatingLiveStateUnavailable: return @"catalog only · no live receiver";
        default: return @"catalog entry";
    }
}

- (void)refreshLiveStateForRow:(SCIGatingRow *)r {
    if (!r || r.blacklisted) return;
    if (r.classMethod) { r.liveState = SCIGatingLiveStateUnavailable; return; }
    if (r.liveState == SCIGatingLiveStateLoaded) return;
    r.liveState = [SCIGatingCatalog hasLiveReceiverForClass:r.rawClass] ? SCIGatingLiveStateReady : SCIGatingLiveStateUnavailable;
}

- (void)readLiveValueForRow:(SCIGatingRow *)r completion:(void (^ __nullable)(void))completion {
    if (!r || r.blacklisted) { if (completion) completion(); return; }
    [self refreshLiveStateForRow:r];
    if (r.liveState != SCIGatingLiveStateReady) { if (completion) completion(); return; }
    r.value = [SCIGatingCatalog evaluateClass:r.rawClass selector:r.selector];
    r.blacklisted = [SCIGatingCatalog isBlacklistedClass:r.rawClass selector:r.selector];
    r.liveState = r.blacklisted ? SCIGatingLiveStateUnavailable : (r.value ? SCIGatingLiveStateLoaded : SCIGatingLiveStateReady);
    if (completion) completion();
}

- (void)viewDidLoad {
    [super viewDidLoad];
    self.title = @"Feature Gatings";
    SCIApplyGlassBackdropToViewController(self);

    UIBarButtonItem *reset = [[UIBarButtonItem alloc] initWithBarButtonSystemItem:UIBarButtonSystemItemTrash
                                                                           target:self action:@selector(confirmReset)];
    self.navigationItem.rightBarButtonItems = @[reset];

    self.glassSearchBar = [[SCIGlassSearchBar alloc] initWithRadius:22.0];
    self.glassSearchBar.translatesAutoresizingMaskIntoConstraints = NO;
    self.searchBar = self.glassSearchBar.searchBar;
    self.searchBar.placeholder = @"Filter class or flag name";
    self.searchBar.autocapitalizationType = UITextAutocapitalizationTypeNone;
    self.searchBar.autocorrectionType = UITextAutocorrectionTypeNo;
    self.searchBar.delegate = self;
    [self.view addSubview:self.glassSearchBar];

    self.scopePanel = [[SCIAdaptiveGlassPanelView alloc] initWithRadius:18.0];
    self.scopePanel.sciGlassInteractive = YES;
    self.scopePanel.translatesAutoresizingMaskIntoConstraints = NO;
    [self.view addSubview:self.scopePanel];

    self.scopeControl = [[UISegmentedControl alloc] initWithItems:@[@"Instagram", @"FBShared"]];
    self.scopeControl.selectedSegmentIndex = UISegmentedControlNoSegment;
    self.scopeControl.translatesAutoresizingMaskIntoConstraints = NO;
    [self.scopeControl addTarget:self action:@selector(scopeChanged:) forControlEvents:UIControlEventValueChanged];
    [self.scopePanel.contentView addSubview:self.scopeControl];
    SCIStyleSegmentedControlForGlass(self.scopeControl);

    self.tableView = [[UITableView alloc] initWithFrame:CGRectZero style:UITableViewStyleGrouped];
    self.tableView.dataSource = self;
    self.tableView.delegate = self;
    SCIStyleTableViewForGlass(self.tableView);
    self.tableView.separatorStyle = UITableViewCellSeparatorStyleNone;
    self.tableView.translatesAutoresizingMaskIntoConstraints = NO;
    self.tableView.estimatedRowHeight = 48.0;
    self.tableView.rowHeight = UITableViewAutomaticDimension;
    self.tableView.contentInset = UIEdgeInsetsMake(126.0, 0.0, 24.0, 0.0);
    self.tableView.scrollIndicatorInsets = self.tableView.contentInset;
    [self.tableView registerClass:SCIGlassToggleCell.class forCellReuseIdentifier:@"gate"];
    [self.tableView registerClass:SCIGlassParamCell.class forCellReuseIdentifier:@"status"];
    [self.tableView registerClass:SCIGlassSectionHeaderView.class forHeaderFooterViewReuseIdentifier:@"hdr"];
    [self.view addSubview:self.tableView];
    [self.view sendSubviewToBack:self.tableView];

    UILayoutGuide *g = self.view.safeAreaLayoutGuide;
    [NSLayoutConstraint activateConstraints:@[
        [self.glassSearchBar.topAnchor constraintEqualToAnchor:g.topAnchor constant:8],
        [self.glassSearchBar.leadingAnchor constraintEqualToAnchor:g.leadingAnchor constant:12],
        [self.glassSearchBar.trailingAnchor constraintEqualToAnchor:g.trailingAnchor constant:-12],
        [self.scopePanel.topAnchor constraintEqualToAnchor:self.glassSearchBar.bottomAnchor constant:8],
        [self.scopePanel.leadingAnchor constraintEqualToAnchor:g.leadingAnchor constant:12],
        [self.scopePanel.trailingAnchor constraintEqualToAnchor:g.trailingAnchor constant:-12],
        [self.scopeControl.topAnchor constraintEqualToAnchor:self.scopePanel.contentView.topAnchor constant:8],
        [self.scopeControl.leadingAnchor constraintEqualToAnchor:self.scopePanel.contentView.leadingAnchor constant:10],
        [self.scopeControl.trailingAnchor constraintEqualToAnchor:self.scopePanel.contentView.trailingAnchor constant:-10],
        [self.scopeControl.bottomAnchor constraintEqualToAnchor:self.scopePanel.contentView.bottomAnchor constant:-8],
        [self.tableView.topAnchor constraintEqualToAnchor:self.view.topAnchor],
        [self.tableView.leadingAnchor constraintEqualToAnchor:self.view.leadingAnchor],
        [self.tableView.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor],
        [self.tableView.bottomAnchor constraintEqualToAnchor:self.view.bottomAnchor],
    ]];
    SCIApplyLiquidGlassToViewTree(self.view);

    self.allSections = @[];
    self.sections = @[];
    [self applyFilter];
}

- (void)viewWillAppear:(BOOL)animated {
    [super viewWillAppear:animated];
    SCIApplyGlassBackdropToViewController(self);
    SCIApplyLiquidGlassToViewTree(self.view);
    [SCIGatingCatalog installPersistedDirectOverrideHooks];
}

- (void)buildModel {
    if (!self.scopeSelected) {
        self.allSections = @[];
        [self applyFilter];
        return;
    }
    NSMutableArray<NSDictionary *> *secs = [NSMutableArray array];
    for (NSDictionary *entry in [SCIGatingCatalog catalogForScope:self.runtimeScope]) {
        NSString *disp = entry[@"class"];
        NSString *raw = entry[@"raw"];
        NSMutableArray<SCIGatingRow *> *rows = [NSMutableArray array];
        for (NSDictionary *getter in entry[@"getters"]) {
            NSString *sel = getter[@"selector"];
            if (!sel.length) continue;
            SCIGatingRow *r = [SCIGatingRow new];
            r.displayClass = disp; r.rawClass = raw; r.selector = sel;
            r.classMethod = [getter[@"classMethod"] boolValue];
            r.canonical = [SCIGatingCatalog canonicalNameForClass:raw selector:sel];
            r.blacklisted = [SCIGatingCatalog isBlacklistedClass:raw selector:sel];
            r.liveState = r.blacklisted ? SCIGatingLiveStateUnavailable : SCIGatingLiveStateUnknown;
            [rows addObject:r];
        }
        if (rows.count) [secs addObject:@{ @"class": disp, @"rows": rows }];
    }
    self.allSections = secs;
    [self applyFilter];
}

- (void)applyFilter {
    NSString *q = self.query.lowercaseString;
    NSMutableArray<NSDictionary *> *out = [NSMutableArray array];
    for (NSDictionary *sec in self.allSections) {
        BOOL classMatch = (q.length == 0) || [[sec[@"class"] lowercaseString] containsString:q];
        NSMutableArray<SCIGatingRow *> *kept = [NSMutableArray array];
        for (SCIGatingRow *r in sec[@"rows"]) {
            if (self.onlyOverridden && [SCIGatingCatalog runtimeBoolOverrideStateForClass:r.rawClass selector:r.selector classMethod:r.classMethod] == nil) continue;
            BOOL selMatch = (q.length == 0) || classMatch || [r.selector.lowercaseString containsString:q];
            if (selMatch) [kept addObject:r];
        }
        if (kept.count) [out addObject:@{ @"class": sec[@"class"], @"rows": kept }];
    }
    self.sections = out;
    [self.tableView reloadData];
}

- (void)scopeChanged:(UISegmentedControl *)c {
    if (c.selectedSegmentIndex == UISegmentedControlNoSegment) return;
    self.scopeSelected = YES;
    self.runtimeScope = c.selectedSegmentIndex == 0 ? SCIGatingRuntimeScopeInstagramMain : SCIGatingRuntimeScopeFBSharedFramework;
    self.title = [NSString stringWithFormat:@"Feature Gatings · %@", c.selectedSegmentIndex == 0 ? @"Instagram" : @"FBShared"];
    [self.searchBar resignFirstResponder];
    [self buildModel];
}

- (void)confirmReset {
    UIAlertController *a = [UIAlertController alertControllerWithTitle:@"Reset gating overrides?"
                                                              message:@"Clears every forced value and the evaluation blacklist."
                                                       preferredStyle:UIAlertControllerStyleAlert];
    [a addAction:[UIAlertAction actionWithTitle:@"Cancel" style:UIAlertActionStyleCancel handler:nil]];
    [a addAction:[UIAlertAction actionWithTitle:@"Reset" style:UIAlertActionStyleDestructive handler:^(__unused UIAlertAction *x) {
        [SCIGatingCatalog clearDirectOverrides];
        [SCIGatingCatalog clearBlacklist];
        [self buildModel];
    }]];
    [self presentViewController:a animated:YES completion:nil];
}

#pragma mark search

- (void)searchBar:(UISearchBar *)searchBar textDidChange:(NSString *)searchText {
    self.query = searchText;
    [self applyFilter];
}
- (void)searchBarSearchButtonClicked:(UISearchBar *)searchBar { [searchBar resignFirstResponder]; }

- (void)scrollViewWillBeginDragging:(UIScrollView *)scrollView {
    [self.searchBar resignFirstResponder];
    [self.view endEditing:YES];
}

#pragma mark helpers

- (SCIGatingRow *)rowAt:(NSIndexPath *)ip {
    if (self.sections.count == 0) return nil;
    if (ip.section >= (NSInteger)self.sections.count) return nil;
    NSArray *rows = self.sections[ip.section][@"rows"];
    if (ip.row >= (NSInteger)rows.count) return nil;
    return rows[ip.row];
}

- (void)toggleRow:(NSIndexPath *)ip to:(BOOL)on {
    SCIGatingRow *r = [self rowAt:ip];
    if (!r) return;
    [SCIGatingCatalog setRuntimeBoolOverride:on class:r.rawClass selector:r.selector classMethod:r.classMethod];
    r.value = @(on);
    [self.tableView reloadData];
}

#pragma mark table

- (NSInteger)numberOfSectionsInTableView:(UITableView *)tableView {
    return self.sections.count ?: 1;
}

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section {
    if (self.sections.count == 0) return 1;
    return [self.sections[section][@"rows"] count];
}

- (UIView *)tableView:(UITableView *)tableView viewForHeaderInSection:(NSInteger)section {
    if (self.sections.count == 0) return nil;
    SCIGlassSectionHeaderView *h = [tableView dequeueReusableHeaderFooterViewWithIdentifier:@"hdr"];
    NSDictionary *sec = self.sections[section];
    [h configureWithTitle:sec[@"class"] subtitle:[NSString stringWithFormat:@"%lu flags", (unsigned long)[sec[@"rows"] count]]];
    return h;
}

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath {
    if (self.sections.count == 0) {
        SCIGlassParamCell *cell = [tableView dequeueReusableCellWithIdentifier:@"status" forIndexPath:indexPath];
        NSString *title = self.scopeSelected ? @"No gating accessors found" : @"Choose a runtime scope";
        NSString *subtitle = self.scopeSelected ? @"Try another search or switch runtime scope." : @"Pick Instagram executable or FBSharedFramework above. The catalog is built only after choosing.";
        [cell configureWithTitle:title
                        subtitle:subtitle
                           badge:nil emphasized:NO];
        return cell;
    }
    SCIGlassToggleCell *cell = [tableView dequeueReusableCellWithIdentifier:@"gate" forIndexPath:indexPath];
    SCIGatingRow *r = self.sections[indexPath.section][@"rows"][indexPath.row];
    NSNumber *ov = [SCIGatingCatalog runtimeBoolOverrideStateForClass:r.rawClass selector:r.selector classMethod:r.classMethod];
    [self refreshLiveStateForRow:r];

    BOOL on = ov ? ov.boolValue : (r.value ? r.value.boolValue : NO);
    NSString *sub = [self subtitleForRow:r override:ov];
    BOOL interactive = !r.blacklisted;
    NSString *title = [NSString stringWithFormat:@"%@ %@", r.classMethod ? @"+" : @"-", r.selector ?: @""];
    [cell configureWithTitle:title subtitle:sub on:on overridden:(ov != nil) interactive:interactive];

    __weak typeof(self) ws = self;
    NSIndexPath *ip = indexPath;
    cell.onToggle = ^(BOOL v) { [ws toggleRow:ip to:v]; };
    return cell;
}

- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath {
    [tableView deselectRowAtIndexPath:indexPath animated:YES];
    if (self.sections.count == 0) return;
    SCIGatingRow *r = [self rowAt:indexPath];
    if (!r) return;
    [self refreshLiveStateForRow:r];
    NSNumber *ov = [SCIGatingCatalog runtimeBoolOverrideStateForClass:r.rawClass selector:r.selector classMethod:r.classMethod];
    NSString *liveStr = r.value == nil ? @"not read" : (r.value.boolValue ? @"ON" : @"OFF");
    NSString *forced = ov ? (ov.boolValue ? @"ON" : @"OFF") : @"none";
    NSString *liveMode = r.classMethod ? @"class method" : ((r.liveState == SCIGatingLiveStateReady || r.liveState == SCIGatingLiveStateLoaded) ? @"available" : @"unavailable");
    NSString *msg = [NSString stringWithFormat:@"%@\nLive source: %@\nLive value: %@\nDirect override: %@", r.displayClass, liveMode, liveStr, forced];
    UIAlertController *a = [UIAlertController alertControllerWithTitle:r.selector message:msg preferredStyle:UIAlertControllerStyleActionSheet];

    if (!r.blacklisted && r.liveState == SCIGatingLiveStateReady) {
        [a addAction:[UIAlertAction actionWithTitle:@"Read live value" style:UIAlertActionStyleDefault handler:^(__unused UIAlertAction *act) {
            [self readLiveValueForRow:r completion:^{ [self.tableView reloadData]; }];
        }]];
    }
    [a addAction:[UIAlertAction actionWithTitle:@"Force ON" style:UIAlertActionStyleDefault handler:^(__unused UIAlertAction *act) {
        [self toggleRow:indexPath to:YES];
    }]];
    [a addAction:[UIAlertAction actionWithTitle:@"Force OFF" style:UIAlertActionStyleDefault handler:^(__unused UIAlertAction *act) {
        [self toggleRow:indexPath to:NO];
    }]];
    if (ov != nil) {
        [a addAction:[UIAlertAction actionWithTitle:@"Clear override" style:UIAlertActionStyleDestructive handler:^(__unused UIAlertAction *act) {
            [SCIGatingCatalog clearRuntimeBoolOverrideForClass:r.rawClass selector:r.selector classMethod:r.classMethod];
            [self.tableView reloadData];
        }]];
    }
    [a addAction:[UIAlertAction actionWithTitle:@"Cancel" style:UIAlertActionStyleCancel handler:nil]];
    UIPopoverPresentationController *pop = a.popoverPresentationController;
    if (pop) {
        pop.sourceView = tableView;
        CGRect rect = [tableView rectForRowAtIndexPath:indexPath];
        pop.sourceRect = rect;
    }
    [self presentViewController:a animated:YES completion:nil];
}

@end
