#import "RYGFastRuntimeClassViewController.h"
#import "RYGRuntimeIndex.h"
#import "RYGRuntimeBrowserEngine.h"
#import "RYGRuntimeLiveObserver.h"
#import "../UI/RYGLiquidGlass.h"
#import "../UI/RYGPopupChrome.h"

static NSString *RYGDetailNormalize(NSString *value) {
    if (!value.length) return @"";
    NSString *lower = value.lowercaseString;
    NSMutableString *out = [NSMutableString stringWithCapacity:lower.length];
    BOOL emittedSpace = YES;
    for (NSUInteger index = 0; index < lower.length; index++) {
        unichar c = [lower characterAtIndex:index];
        BOOL alnum = (c >= 'a' && c <= 'z') || (c >= '0' && c <= '9');
        if (alnum) { [out appendFormat:@"%C", c]; emittedSpace = NO; }
        else if (!emittedSpace) { [out appendString:@" "]; emittedSpace = YES; }
    }
    return [out stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceCharacterSet];
}

static NSArray<NSString *> *RYGDetailTokens(NSString *query) {
    NSString *normalized = RYGDetailNormalize(query);
    if (!normalized.length) return @[];
    NSMutableArray<NSString *> *tokens = [NSMutableArray array];
    for (NSString *token in [normalized componentsSeparatedByString:@" "]) if (token.length) [tokens addObject:token];
    return tokens.copy;
}

static BOOL RYGDetailMatches(NSString *text, NSArray<NSString *> *tokens) {
    if (!tokens.count) return YES;
    NSString *normalized = RYGDetailNormalize(text);
    NSString *compact = [normalized stringByReplacingOccurrencesOfString:@" " withString:@""];
    for (NSString *token in tokens) {
        NSString *compactToken = [token stringByReplacingOccurrencesOfString:@" " withString:@""];
        if ([normalized rangeOfString:token].location == NSNotFound && [compact rangeOfString:compactToken].location == NSNotFound) return NO;
    }
    return YES;
}

@interface RYGFastRuntimeClassViewController () <UISearchResultsUpdating>
@property (nonatomic, strong) RYGRuntimeImageIndex *index;
@property (nonatomic, strong) RYGRuntimeClassRow *classRow;
@property (nonatomic, copy) NSArray<RYGRuntimeBoolMethod *> *methods;
@property (nonatomic, copy) NSArray<RYGRuntimeBoolMethod *> *visibleMethods;
@property (nonatomic, strong) UISearchController *searchController;
@end

@implementation RYGFastRuntimeClassViewController

- (instancetype)initWithIndex:(RYGRuntimeImageIndex *)index
                     classRow:(RYGRuntimeClassRow *)row
                 initialQuery:(NSString *)query {
    if ((self = [super initWithStyle:UITableViewStyleInsetGrouped])) {
        _index = index;
        _classRow = row;
        _methods = [index methodsForClassName:row.className];
        _visibleMethods = _methods;
        _searchController = [UISearchController new];
        _searchController.searchBar.text = query ?: @"";
    }
    return self;
}

- (void)viewDidLoad {
    [super viewDidLoad];
    self.title = self.classRow.className ?: @"Class";
    self.navigationItem.titleView = RYGLiquidGlassNavigationTitleView(self.title);
    self.view.backgroundColor = [RYGPopupChrome backgroundColor];
    self.tableView.backgroundColor = [RYGPopupChrome backgroundColor];
    self.tableView.rowHeight = UITableViewAutomaticDimension;
    self.tableView.estimatedRowHeight = 52.0;
    self.searchController.searchResultsUpdater = self;
    self.searchController.obscuresBackgroundDuringPresentation = NO;
    self.searchController.searchBar.placeholder = @"BOOL selector or ABI";
    self.navigationItem.searchController = self.searchController;
    self.navigationItem.hidesSearchBarWhenScrolling = NO;
    [NSNotificationCenter.defaultCenter addObserver:self selector:@selector(nativeChanged:) name:RYGRuntimeNativeValueDidChangeNotification object:nil];
    [self applyFilter];
    RYGLiquidGlassApplyToViewController(self);
}

- (void)dealloc { [NSNotificationCenter.defaultCenter removeObserver:self]; }

- (void)nativeChanged:(NSNotification *)note {
    NSString *key = note.userInfo[RYGRuntimeNativeValueKeyUserInfoKey];
    if (key.length && [key containsString:self.classRow.className ?: @""]) [self.tableView reloadData];
}

- (void)updateSearchResultsForSearchController:(UISearchController *)searchController {
    (void)searchController;
    [self applyFilter];
}

- (void)applyFilter {
    NSArray<NSString *> *tokens = RYGDetailTokens(self.searchController.searchBar.text ?: @"");
    if (!tokens.count) self.visibleMethods = self.methods;
    else {
        self.visibleMethods = [self.methods filteredArrayUsingPredicate:[NSPredicate predicateWithBlock:^BOOL(RYGRuntimeBoolMethod *method, NSDictionary *bindings) {
            (void)bindings;
            NSString *text = [NSString stringWithFormat:@"%@ %@ %@", method.className ?: @"", method.selectorName ?: @"", method.typeEncoding ?: @""];
            return RYGDetailMatches(text, tokens);
        }]];
    }
    [self.tableView reloadData];
}

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section {
    (void)tableView; (void)section;
    return self.visibleMethods.count;
}

- (NSString *)tableView:(UITableView *)tableView titleForHeaderInSection:(NSInteger)section {
    (void)tableView; (void)section;
    return [NSString stringWithFormat:@"%lu ABI-validated BOOL methods", (unsigned long)self.visibleMethods.count];
}

- (UIButton *)buttonForMethod:(RYGRuntimeBoolMethod *)method {
    NSNumber *forced = method.overrideValue;
    NSNumber *native = method.liveValue;
    NSString *title = forced ? (forced.boolValue ? @"Forced On" : @"Forced Off") : native ? (native.boolValue ? @"Native On" : @"Native Off") : @"Native";
    __weak typeof(self) weakSelf = self;

    UIAction *observe = [UIAction actionWithTitle:@"Observe native" image:[UIImage systemImageNamed:@"waveform.path.ecg"] identifier:nil handler:^(__unused UIAction *action) {
        RYGRuntimeBeginLiveObservation(@[method]);
        [weakSelf.tableView reloadData];
    }];
    UIAction *useNative = [UIAction actionWithTitle:@"Use Native" image:nil identifier:nil handler:^(__unused UIAction *action) {
        [RYGRuntimeBrowserEngine setOverride:nil forMethod:method];
        [weakSelf.tableView reloadData];
    }];
    UIAction *on = [UIAction actionWithTitle:@"Force On" image:nil identifier:nil handler:^(__unused UIAction *action) {
        [RYGRuntimeBrowserEngine setOverride:@YES forMethod:method];
        [weakSelf.tableView reloadData];
    }];
    UIAction *off = [UIAction actionWithTitle:@"Force Off" image:nil identifier:nil handler:^(__unused UIAction *action) {
        [RYGRuntimeBrowserEngine setOverride:@NO forMethod:method];
        [weakSelf.tableView reloadData];
    }];
    useNative.state = forced ? UIMenuElementStateOff : UIMenuElementStateOn;
    on.state = forced && forced.boolValue ? UIMenuElementStateOn : UIMenuElementStateOff;
    off.state = forced && !forced.boolValue ? UIMenuElementStateOn : UIMenuElementStateOff;

    UIButton *button = [UIButton buttonWithType:UIButtonTypeSystem];
    UIMenu *output = [UIMenu menuWithTitle:@"Output" image:nil identifier:nil options:UIMenuOptionsSingleSelection children:@[useNative, on, off]];
    button.menu = [UIMenu menuWithTitle:method.selectorName ?: @"Method" image:nil identifier:nil options:0 children:@[observe, output]];
    button.showsMenuAsPrimaryAction = YES;
    RYGLiquidGlassConfigureButton(button, NO);
    UIButtonConfiguration *configuration = button.configuration;
    if (configuration) {
        configuration.title = title;
        configuration.baseForegroundColor = UIColor.labelColor;
        button.configuration = configuration;
    } else {
        [button setTitle:title forState:UIControlStateNormal];
    }
    return button;
}

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath {
    UITableViewCell *cell = [tableView dequeueReusableCellWithIdentifier:@"RYGFastRuntimeMethod"];
    if (!cell) cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleSubtitle reuseIdentifier:@"RYGFastRuntimeMethod"];
    RYGRuntimeBoolMethod *method = self.visibleMethods[(NSUInteger)indexPath.row];
    cell.textLabel.text = [NSString stringWithFormat:@"%@ %@", method.classMethod ? @"+" : @"−", method.selectorName ?: @""];
    cell.textLabel.font = [UIFont monospacedSystemFontOfSize:12.5 weight:UIFontWeightMedium];
    cell.textLabel.numberOfLines = 2;
    cell.detailTextLabel.text = method.typeEncoding ?: @"";
    cell.detailTextLabel.font = [UIFont monospacedSystemFontOfSize:10.5 weight:UIFontWeightRegular];
    cell.detailTextLabel.textColor = UIColor.secondaryLabelColor;
    cell.accessoryView = [self buttonForMethod:method];
    cell.selectionStyle = UITableViewCellSelectionStyleNone;
    return cell;
}

@end
