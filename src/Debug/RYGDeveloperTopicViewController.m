#import "RYGDeveloperTopicViewController.h"
#import "RYGRuntimeBrowserEngine.h"
#import "RYGRuntimeLiveObserver.h"
#import "../UI/RYGLiquidGlass.h"
#import "../UI/RYGPopupChrome.h"
#import "../Utils.h"
#import <objc/runtime.h>

static const void *kRYGTopicMethodKey = &kRYGTopicMethodKey;

static NSString *RYGTopicNormalize(NSString *value) {
    if (!value.length) return @"";
    NSMutableString *out = [NSMutableString stringWithCapacity:value.length];
    NSString *lower = value.lowercaseString;
    BOOL lastSpace = YES;
    for (NSUInteger i = 0; i < lower.length; i++) {
        unichar c = [lower characterAtIndex:i];
        BOOL alnum = (c >= 'a' && c <= 'z') || (c >= '0' && c <= '9');
        if (alnum) {
            [out appendFormat:@"%C", c];
            lastSpace = NO;
        } else if (!lastSpace) {
            [out appendString:@" "];
            lastSpace = YES;
        }
    }
    return [out stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceCharacterSet];
}

static BOOL RYGTopicMatchesQuery(RYGRuntimeBoolMethod *method, NSString *query) {
    NSString *needle = RYGTopicNormalize(query);
    if (!needle.length) return YES;
    NSString *hay = RYGTopicNormalize([NSString stringWithFormat:@"%@ %@ %@ %@",
        method.className ?: @"", method.selectorName ?: @"", method.typeEncoding ?: @"",
        method.imagePath.lastPathComponent ?: @""]);
    NSString *compact = [hay stringByReplacingOccurrencesOfString:@" " withString:@""];
    for (NSString *token in [needle componentsSeparatedByString:@" "]) {
        if (!token.length) continue;
        if ([hay rangeOfString:token].location == NSNotFound &&
            [compact rangeOfString:token].location == NSNotFound) return NO;
    }
    return YES;
}

@interface RYGDeveloperTopicViewController () <UISearchResultsUpdating>
@property (nonatomic, assign) RYGDeveloperRuntimeSurface surface;
@property (nonatomic, strong) UISearchController *searchController;
@property (nonatomic, copy) NSArray<RYGRuntimeBoolMethod *> *allRows;
@property (nonatomic, copy) NSArray<NSString *> *classSections;
@property (nonatomic, copy) NSDictionary<NSString *, NSArray<RYGRuntimeBoolMethod *> *> *rowsByClass;
@property (nonatomic, assign) NSUInteger scanGeneration;
@property (nonatomic, strong) UIActivityIndicatorView *spinner;
@end

@implementation RYGDeveloperTopicViewController

- (instancetype)initWithSurface:(RYGDeveloperRuntimeSurface)surface {
    if ((self = [super initWithStyle:UITableViewStyleInsetGrouped])) {
        _surface = surface;
        _allRows = @[];
        _classSections = @[];
        _rowsByClass = @{};
    }
    return self;
}

- (void)viewDidLoad {
    [super viewDidLoad];
    self.title = [RYGDeveloperRuntimeScanner titleForSurface:self.surface];
    self.view.backgroundColor = [RYGPopupChrome backgroundColor];
    self.tableView.backgroundColor = [RYGPopupChrome backgroundColor];
    self.tableView.keyboardDismissMode = UIScrollViewKeyboardDismissModeOnDrag;
    self.tableView.rowHeight = UITableViewAutomaticDimension;
    self.tableView.estimatedRowHeight = 48.0;

    self.searchController = [[UISearchController alloc] initWithSearchResultsController:nil];
    self.searchController.searchResultsUpdater = self;
    self.searchController.obscuresBackgroundDuringPresentation = NO;
    self.searchController.searchBar.placeholder = @"Class or BOOL";
    self.navigationItem.searchController = self.searchController;
    self.navigationItem.hidesSearchBarWhenScrolling = NO;

    self.spinner = [[UIActivityIndicatorView alloc] initWithActivityIndicatorStyle:UIActivityIndicatorViewStyleMedium];
    __weak typeof(self) weakSelf = self;
    UIAction *observeVisible = [UIAction actionWithTitle:@"Observe visible native values"
                                                  image:[UIImage systemImageNamed:@"waveform.path.ecg"]
                                             identifier:nil
                                                handler:^(__kindof UIAction *action) {
        (void)action;
        [weakSelf observeVisibleRows];
    }];
    UIAction *refresh = [UIAction actionWithTitle:@"Refresh live runtime"
                                           image:[UIImage systemImageNamed:@"arrow.clockwise"]
                                      identifier:nil
                                         handler:^(__kindof UIAction *action) {
        (void)action;
        [weakSelf refreshRows];
    }];
    self.navigationItem.rightBarButtonItem = [[UIBarButtonItem alloc]
        initWithImage:[UIImage systemImageNamed:@"ellipsis.circle"]
                 menu:[UIMenu menuWithTitle:@"Live runtime" children:@[observeVisible, refresh]]];

    [NSNotificationCenter.defaultCenter addObserver:self
                                           selector:@selector(nativeValueChanged:)
                                               name:RYGRuntimeNativeValueDidChangeNotification
                                             object:nil];
    RYGLiquidGlassApplyToViewController(self);
    [self refreshRows];
}

- (void)dealloc {
    [NSNotificationCenter.defaultCenter removeObserver:self];
}

- (void)refreshRows {
    NSUInteger generation = ++self.scanGeneration;
    [self.spinner startAnimating];
    self.tableView.backgroundView = self.spinner;
    RYGDeveloperRuntimeSurface surface = self.surface;
    __weak typeof(self) weakSelf = self;
    dispatch_async(dispatch_get_global_queue(QOS_CLASS_USER_INITIATED, 0), ^{
        NSArray<RYGRuntimeBoolMethod *> *rows = [RYGDeveloperRuntimeScanner boolMethodsForSurface:surface];
        dispatch_async(dispatch_get_main_queue(), ^{
            __strong typeof(weakSelf) self = weakSelf;
            if (!self || generation != self.scanGeneration) return;
            self.allRows = rows ?: @[];
            [self.spinner stopAnimating];
            [self rebuildFilteredModel];
        });
    });
}

- (void)updateSearchResultsForSearchController:(UISearchController *)searchController {
    (void)searchController;
    [self rebuildFilteredModel];
}

- (void)rebuildFilteredModel {
    NSString *query = self.searchController.searchBar.text ?: @"";
    NSMutableDictionary<NSString *, NSMutableArray<RYGRuntimeBoolMethod *> *> *mutable = [NSMutableDictionary dictionary];
    for (RYGRuntimeBoolMethod *method in self.allRows) {
        if (!RYGTopicMatchesQuery(method, query)) continue;
        NSString *className = method.className.length ? method.className : @"Runtime";
        if (!mutable[className]) mutable[className] = [NSMutableArray array];
        [mutable[className] addObject:method];
    }

    NSArray<NSString *> *classes = [mutable.allKeys sortedArrayUsingSelector:@selector(localizedCaseInsensitiveCompare:)];
    NSMutableDictionary *frozen = [NSMutableDictionary dictionaryWithCapacity:classes.count];
    for (NSString *className in classes) {
        frozen[className] = [mutable[className] sortedArrayUsingComparator:^NSComparisonResult(RYGRuntimeBoolMethod *a, RYGRuntimeBoolMethod *b) {
            return [a.selectorName localizedCaseInsensitiveCompare:b.selectorName];
        }];
    }
    self.classSections = classes;
    self.rowsByClass = frozen.copy;

    if (!classes.count && !self.spinner.isAnimating) {
        UILabel *empty = [UILabel new];
        empty.text = query.length ? @"No matching live BOOL" : @"No live BOOL from this surface is loaded";
        empty.textAlignment = NSTextAlignmentCenter;
        empty.numberOfLines = 0;
        empty.textColor = UIColor.secondaryLabelColor;
        empty.font = [UIFont systemFontOfSize:14.0 weight:UIFontWeightRegular];
        self.tableView.backgroundView = empty;
    } else if (!self.spinner.isAnimating) {
        self.tableView.backgroundView = nil;
    }
    [self.tableView reloadData];
}

- (NSArray<RYGRuntimeBoolMethod *> *)visibleRows {
    NSMutableArray *rows = [NSMutableArray array];
    for (NSString *className in self.classSections) [rows addObjectsFromArray:self.rowsByClass[className] ?: @[]];
    return rows.copy;
}

- (void)observeVisibleRows {
    NSArray *rows = [self visibleRows];
    if (!rows.count) return;
    RYGRuntimeBeginLiveObservation(rows);
    [RYGUtils showToastForDuration:1.4
                            title:@"Live observation"
                         subtitle:[NSString stringWithFormat:@"Observing up to %lu visible BOOLs", (unsigned long)MIN(rows.count, (NSUInteger)64)]];
}

- (void)nativeValueChanged:(NSNotification *)notification {
    NSString *key = notification.userInfo[RYGRuntimeNativeValueKeyUserInfoKey];
    if (!key.length) return;
    for (RYGRuntimeBoolMethod *method in self.allRows) {
        if ([method.overrideKey isEqualToString:key]) {
            [self.tableView reloadData];
            break;
        }
    }
}

- (NSInteger)numberOfSectionsInTableView:(UITableView *)tableView {
    (void)tableView;
    return self.classSections.count;
}

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section {
    (void)tableView;
    if (section < 0 || section >= (NSInteger)self.classSections.count) return 0;
    return [self.rowsByClass[self.classSections[(NSUInteger)section]] count];
}

- (NSString *)tableView:(UITableView *)tableView titleForHeaderInSection:(NSInteger)section {
    (void)tableView;
    if (section < 0 || section >= (NSInteger)self.classSections.count) return nil;
    return self.classSections[(NSUInteger)section];
}

- (RYGRuntimeBoolMethod *)methodAtIndexPath:(NSIndexPath *)indexPath {
    if (indexPath.section < 0 || indexPath.section >= (NSInteger)self.classSections.count) return nil;
    NSArray *rows = self.rowsByClass[self.classSections[(NSUInteger)indexPath.section]];
    if (indexPath.row < 0 || indexPath.row >= (NSInteger)rows.count) return nil;
    return rows[(NSUInteger)indexPath.row];
}

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath {
    static NSString *identifier = @"RYGDeveloperTopicBool";
    UITableViewCell *cell = [tableView dequeueReusableCellWithIdentifier:identifier];
    if (!cell) cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleSubtitle reuseIdentifier:identifier];
    RYGRuntimeBoolMethod *method = [self methodAtIndexPath:indexPath];

    cell.textLabel.text = [NSString stringWithFormat:@"%@ %@", method.classMethod ? @"+" : @"−", method.selectorName ?: @""];
    cell.textLabel.font = [UIFont monospacedSystemFontOfSize:13.0 weight:UIFontWeightMedium];
    cell.textLabel.numberOfLines = 1;

    NSNumber *native = method.liveValue;
    NSNumber *forced = method.overrideValue;
    NSString *nativeText = native ? (native.boolValue ? @"original true" : @"original false") : @"original not observed";
    NSString *outputText = forced ? (forced.boolValue ? @"forced true" : @"forced false") : @"native output";
    cell.detailTextLabel.text = [NSString stringWithFormat:@"%@ · %@", nativeText, outputText];
    cell.detailTextLabel.font = [UIFont systemFontOfSize:10.5 weight:UIFontWeightRegular];
    cell.detailTextLabel.textColor = UIColor.secondaryLabelColor;
    cell.detailTextLabel.numberOfLines = 1;

    UISwitch *toggle = [UISwitch new];
    toggle.on = forced ? forced.boolValue : (native ? native.boolValue : NO);
    toggle.onTintColor = [RYGUtils RYGColor_Primary];
    objc_setAssociatedObject(toggle, kRYGTopicMethodKey, method, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    [toggle addTarget:self action:@selector(toggleChanged:) forControlEvents:UIControlEventValueChanged];
    cell.accessoryView = toggle;
    cell.selectionStyle = UITableViewCellSelectionStyleDefault;
    return cell;
}

- (void)toggleChanged:(UISwitch *)toggle {
    RYGRuntimeBoolMethod *method = objc_getAssociatedObject(toggle, kRYGTopicMethodKey);
    if (!method) return;
    [RYGRuntimeBrowserEngine setOverride:@(toggle.isOn) forMethod:method];
    [self.tableView reloadData];
}

- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath {
    UITableViewCell *cell = [tableView cellForRowAtIndexPath:indexPath];
    [tableView deselectRowAtIndexPath:indexPath animated:YES];
    RYGRuntimeBoolMethod *method = [self methodAtIndexPath:indexPath];
    if (!method) return;
    [self presentActionsForMethod:method source:cell];
}

- (void)presentActionsForMethod:(RYGRuntimeBoolMethod *)method source:(UIView *)source {
    NSNumber *native = method.liveValue;
    NSNumber *forced = method.overrideValue;
    NSString *message = [NSString stringWithFormat:@"%@\n%@\nOriginal: %@\nOutput: %@",
        method.imagePath.lastPathComponent ?: @"",
        method.typeEncoding ?: @"",
        native ? (native.boolValue ? @"true" : @"false") : @"not observed yet",
        forced ? (forced.boolValue ? @"forced true" : @"forced false") : @"native"];

    UIAlertController *sheet = [UIAlertController alertControllerWithTitle:method.selectorName
                                                                    message:message
                                                             preferredStyle:UIAlertControllerStyleActionSheet];
    __weak typeof(self) weakSelf = self;
    [sheet addAction:[UIAlertAction actionWithTitle:@"Observe original live value" style:UIAlertActionStyleDefault handler:^(__unused UIAlertAction *action) {
        RYGRuntimeBeginLiveObservation(@[method]);
    }]];
    [sheet addAction:[UIAlertAction actionWithTitle:@"Force true" style:UIAlertActionStyleDefault handler:^(__unused UIAlertAction *action) {
        [RYGRuntimeBrowserEngine setOverride:@YES forMethod:method]; [weakSelf.tableView reloadData];
    }]];
    [sheet addAction:[UIAlertAction actionWithTitle:@"Force false" style:UIAlertActionStyleDefault handler:^(__unused UIAlertAction *action) {
        [RYGRuntimeBrowserEngine setOverride:@NO forMethod:method]; [weakSelf.tableView reloadData];
    }]];
    if (forced) {
        [sheet addAction:[UIAlertAction actionWithTitle:@"Use native value" style:UIAlertActionStyleDestructive handler:^(__unused UIAlertAction *action) {
            [RYGRuntimeBrowserEngine setOverride:nil forMethod:method]; [weakSelf.tableView reloadData];
        }]];
    }
    [sheet addAction:[UIAlertAction actionWithTitle:@"Copy method details" style:UIAlertActionStyleDefault handler:^(__unused UIAlertAction *action) {
        UIPasteboard.generalPasteboard.string = [NSString stringWithFormat:@"%@[%@ %@] %@",
            method.classMethod ? @"+" : @"−", method.className ?: @"", method.selectorName ?: @"", method.typeEncoding ?: @""];
    }]];
    [sheet addAction:[UIAlertAction actionWithTitle:@"Cancel" style:UIAlertActionStyleCancel handler:nil]];
    if (UIDevice.currentDevice.userInterfaceIdiom == UIUserInterfaceIdiomPad) {
        sheet.popoverPresentationController.sourceView = source ?: self.view;
        sheet.popoverPresentationController.sourceRect = source ? source.bounds : self.view.bounds;
    }
    [self presentViewController:sheet animated:YES completion:nil];
}

@end
