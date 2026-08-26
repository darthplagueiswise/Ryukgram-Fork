#import "RYGFastRuntimeBrowserViewController.h"
#import "RYGRuntimeBrowserEngine.h"
#import "RYGRuntimeIndex.h"
#import "RYGRuntimeLiveObserver.h"
#import "../UI/RYGLiquidGlass.h"
#import "../UI/RYGPopupChrome.h"
#import <UIKit/UIKit.h>
#import <objc/runtime.h>
#import <mach-o/dyld.h>
#include <stdlib.h>

// Private accessors already implemented by RYGFastRuntimeBrowserViewController.
// Declaring methods here avoids duplicating storage or creating a second browser.
@interface RYGFastRuntimeBrowserViewController (RYGNonblockingAccess)
- (UITableView *)tableView;
- (UISegmentedControl *)modeControl;
- (UISearchController *)searchController;
- (UIActivityIndicatorView *)spinner;
- (UILabel *)emptyLabel;
- (NSString *)selectedImagePath;
- (void)setIndex:(RYGRuntimeImageIndex *)index;
- (RYGRuntimeImageIndex *)index;
- (void)setVisibleClasses:(NSArray<RYGRuntimeClassRow *> *)classes;
- (NSArray<RYGRuntimeClassRow *> *)visibleClasses;
- (NSUInteger)generation;
- (void)setGeneration:(NSUInteger)generation;
- (void)loadSelectedImage;
- (void)applyFilter;
@end

static const void *kRYGNBSearchGenerationKey = &kRYGNBSearchGenerationKey;
static const void *kRYGNBLastQueryKey = &kRYGNBLastQueryKey;

static dispatch_queue_t RYGNBWorkerQueue(void) {
    static dispatch_queue_t queue;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        queue = dispatch_queue_create("com.ryukgram.runtime-browser.ondemand", DISPATCH_QUEUE_SERIAL);
        dispatch_set_target_queue(queue, dispatch_get_global_queue(QOS_CLASS_UTILITY, 0));
    });
    return queue;
}

static NSString *RYGNBCanonicalPath(NSString *path) {
    if (!path.length) return @"";
    NSString *standard = path.stringByStandardizingPath;
    NSString *resolved = standard.stringByResolvingSymlinksInPath;
    return resolved.length ? resolved.stringByStandardizingPath : standard;
}

static NSString *RYGNBRuntimePath(NSString *path) {
    NSString *wanted = RYGNBCanonicalPath(path);
    for (uint32_t index = 0; index < _dyld_image_count(); index++) {
        const char *raw = _dyld_get_image_name(index);
        if (!raw) continue;
        NSString *runtime = [NSString stringWithUTF8String:raw] ?: @"";
        if ([RYGNBCanonicalPath(runtime) isEqualToString:wanted]) return runtime;
    }
    return nil;
}

static NSArray<NSString *> *RYGNBTokens(NSString *query) {
    NSMutableArray *tokens = [NSMutableArray array];
    for (NSString *part in [query.lowercaseString componentsSeparatedByCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet]) {
        if (part.length) [tokens addObject:part];
    }
    return tokens.copy;
}

static BOOL RYGNBMatches(NSString *text, NSArray<NSString *> *tokens) {
    if (!tokens.count) return YES;
    NSString *lower = text.lowercaseString ?: @"";
    NSString *compact = [[lower componentsSeparatedByCharactersInSet:NSCharacterSet.alphanumericCharacterSet.invertedSet]
        componentsJoinedByString:@""];
    for (NSString *tokenGroup in tokens) {
        BOOL matched = NO;
        for (NSString *token in [tokenGroup componentsSeparatedByString:@"|"]) {
            if (!token.length) continue;
            NSString *compactToken = [[token componentsSeparatedByCharactersInSet:NSCharacterSet.alphanumericCharacterSet.invertedSet]
                componentsJoinedByString:@""];
            if ([lower rangeOfString:token].location != NSNotFound ||
                (compactToken.length && [compact rangeOfString:compactToken].location != NSNotFound)) {
                matched = YES;
                break;
            }
        }
        if (!matched) return NO;
    }
    return YES;
}

static NSArray<RYGRuntimeClassRow *> *RYGNBLightweightClasses(NSString *imagePath) {
    NSString *runtimePath = RYGNBRuntimePath(imagePath);
    if (!runtimePath.length) return @[];
    unsigned int count = 0;
    const char **rawNames = objc_copyClassNamesForImage(runtimePath.fileSystemRepresentation, &count);
    if (!rawNames || count == 0 || count > 500000) {
        if (rawNames) free(rawNames);
        return @[];
    }

    NSMutableArray<RYGRuntimeClassRow *> *rows = [NSMutableArray arrayWithCapacity:count];
    for (unsigned int index = 0; index < count; index++) {
        const char *raw = rawNames[index];
        if (!raw || !*raw) continue;
        NSString *name = [NSString stringWithUTF8String:raw];
        if (!name.length) continue;
        RYGRuntimeClassRow *row = [RYGRuntimeClassRow new];
        row.imagePath = imagePath ?: @"";
        row.className = name;
        row.instanceMethodCount = 0;
        row.classMethodCount = 0;
        row.propertyCount = 0;
        [rows addObject:row];
    }
    free(rawNames);
    [rows sortUsingComparator:^NSComparisonResult(RYGRuntimeClassRow *left, RYGRuntimeClassRow *right) {
        return [left.className localizedCaseInsensitiveCompare:right.className];
    }];
    return rows.copy;
}

static NSArray<RYGRuntimeBoolMethod *> *RYGNBBoolMethodsForClass(RYGRuntimeClassRow *row) {
    if (!row.className.length || !row.imagePath.length) return @[];
    NSArray<RYGRuntimeMemberRow *> *members = [RYGRuntimeBrowserEngine membersForClassName:row.className imagePath:row.imagePath] ?: @[];
    NSMutableArray<RYGRuntimeBoolMethod *> *methods = [NSMutableArray array];
    for (RYGRuntimeMemberRow *member in members) {
        if (!member.hookableBool) continue;
        RYGRuntimeBoolMethod *method = [RYGRuntimeBrowserEngine boolMethodForMember:member];
        if (method) [methods addObject:method];
    }
    [methods sortUsingComparator:^NSComparisonResult(RYGRuntimeBoolMethod *left, RYGRuntimeBoolMethod *right) {
        if (left.classMethod != right.classMethod) return left.classMethod ? NSOrderedDescending : NSOrderedAscending;
        return [left.selectorName localizedCaseInsensitiveCompare:right.selectorName];
    }];
    return methods.copy;
}

static RYGRuntimeImageIndex *RYGNBSnapshot(NSString *imagePath,
                                           NSArray<RYGRuntimeClassRow *> *classes,
                                           NSDictionary<NSString *, NSArray<RYGRuntimeBoolMethod *> *> *methods,
                                           NSUInteger scannedClasses,
                                           NSUInteger scannedMethods) {
    RYGRuntimeImageIndex *index = [RYGRuntimeImageIndex new];
    index.imagePath = imagePath ?: @"";
    index.classes = classes ?: @[];
    index.methodsByClass = methods ?: @{};
    index.classesScanned = scannedClasses;
    index.methodsScanned = scannedMethods;
    index.buildDuration = 0;
    return index;
}

#pragma mark - On-demand class detail

@interface RYGOnDemandRuntimeClassViewController : UITableViewController <UISearchResultsUpdating>
@property (nonatomic, strong) RYGRuntimeClassRow *classRow;
@property (nonatomic, copy) NSArray<RYGRuntimeBoolMethod *> *methods;
@property (nonatomic, copy) NSArray<RYGRuntimeBoolMethod *> *visibleMethods;
@property (nonatomic, strong) UISearchController *searchController;
@property (nonatomic, strong) UIActivityIndicatorView *spinner;
@property (nonatomic, assign) NSUInteger generation;
- (instancetype)initWithClassRow:(RYGRuntimeClassRow *)row query:(NSString *)query;
@end

@implementation RYGOnDemandRuntimeClassViewController

- (instancetype)initWithClassRow:(RYGRuntimeClassRow *)row query:(NSString *)query {
    if ((self = [super initWithStyle:UITableViewStyleInsetGrouped])) {
        _classRow = row;
        _methods = @[];
        _visibleMethods = @[];
        _searchController = [[UISearchController alloc] initWithSearchResultsController:nil];
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
    self.tableView.estimatedRowHeight = 52.0;
    self.tableView.rowHeight = UITableViewAutomaticDimension;
    self.searchController.searchResultsUpdater = self;
    self.searchController.obscuresBackgroundDuringPresentation = NO;
    self.searchController.searchBar.placeholder = @"BOOL selector or ABI";
    self.navigationItem.searchController = self.searchController;
    self.navigationItem.hidesSearchBarWhenScrolling = NO;
    self.spinner = [[UIActivityIndicatorView alloc] initWithActivityIndicatorStyle:UIActivityIndicatorViewStyleMedium];
    [self.spinner startAnimating];
    self.tableView.backgroundView = self.spinner;
    [NSNotificationCenter.defaultCenter addObserver:self selector:@selector(ryg_nativeChanged:) name:RYGRuntimeNativeValueDidChangeNotification object:nil];
    RYGLiquidGlassApplyToViewController(self);

    NSUInteger generation = ++self.generation;
    RYGRuntimeClassRow *row = self.classRow;
    __weak typeof(self) weakSelf = self;
    dispatch_async(RYGNBWorkerQueue(), ^{
        NSArray *methods = RYGNBBoolMethodsForClass(row);
        dispatch_async(dispatch_get_main_queue(), ^{
            __strong typeof(weakSelf) self = weakSelf;
            if (!self || generation != self.generation) return;
            self.methods = methods;
            [self.spinner stopAnimating];
            [self ryg_applyFilter];
        });
    });
}

- (void)dealloc { [NSNotificationCenter.defaultCenter removeObserver:self]; }

- (void)ryg_nativeChanged:(NSNotification *)note {
    NSString *key = note.userInfo[RYGRuntimeNativeValueKeyUserInfoKey];
    if (key.length && [key containsString:self.classRow.className ?: @""]) [self.tableView reloadData];
}

- (void)updateSearchResultsForSearchController:(UISearchController *)searchController {
    (void)searchController;
    [self ryg_applyFilter];
}

- (void)ryg_applyFilter {
    NSArray *tokens = RYGNBTokens(self.searchController.searchBar.text ?: @"");
    if (!tokens.count) self.visibleMethods = self.methods;
    else self.visibleMethods = [self.methods filteredArrayUsingPredicate:[NSPredicate predicateWithBlock:^BOOL(RYGRuntimeBoolMethod *method, NSDictionary *bindings) {
        (void)bindings;
        NSString *text = [NSString stringWithFormat:@"%@ %@ %@", method.className ?: @"", method.selectorName ?: @"", method.typeEncoding ?: @""];
        return RYGNBMatches(text, tokens);
    }]];
    if (self.spinner.isAnimating) self.tableView.backgroundView = self.spinner;
    else if (!self.visibleMethods.count) {
        UILabel *empty = [UILabel new];
        empty.text = @"No ABI-validated BOOL method in this class.";
        empty.textAlignment = NSTextAlignmentCenter;
        empty.textColor = UIColor.secondaryLabelColor;
        empty.numberOfLines = 0;
        self.tableView.backgroundView = empty;
    } else self.tableView.backgroundView = nil;
    [self.tableView reloadData];
}

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section {
    (void)tableView; (void)section;
    return self.visibleMethods.count;
}

- (NSString *)tableView:(UITableView *)tableView titleForHeaderInSection:(NSInteger)section {
    (void)tableView; (void)section;
    return self.spinner.isAnimating ? @"Scanning this class…" : [NSString stringWithFormat:@"%lu ABI-validated BOOL methods", (unsigned long)self.visibleMethods.count];
}

- (UIButton *)ryg_buttonForMethod:(RYGRuntimeBoolMethod *)method {
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
    button.showsMenuAsPrimaryAction = YES;
    UIMenu *output = [UIMenu menuWithTitle:@"Output" image:nil identifier:nil options:UIMenuOptionsSingleSelection children:@[useNative, on, off]];
    button.menu = [UIMenu menuWithTitle:method.selectorName ?: @"Method" image:nil identifier:nil options:0 children:@[observe, output]];
    RYGLiquidGlassConfigureButton(button, NO);
    UIButtonConfiguration *configuration = button.configuration;
    if (configuration) {
        configuration.title = title;
        configuration.baseForegroundColor = UIColor.labelColor;
        button.configuration = configuration;
    } else [button setTitle:title forState:UIControlStateNormal];
    return button;
}

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath {
    UITableViewCell *cell = [tableView dequeueReusableCellWithIdentifier:@"RYGOnDemandRuntimeMethod"];
    if (!cell) cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleSubtitle reuseIdentifier:@"RYGOnDemandRuntimeMethod"];
    RYGRuntimeBoolMethod *method = self.visibleMethods[(NSUInteger)indexPath.row];
    cell.textLabel.text = [NSString stringWithFormat:@"%@ %@", method.classMethod ? @"+" : @"−", method.selectorName ?: @""];
    cell.textLabel.font = [UIFont monospacedSystemFontOfSize:12.5 weight:UIFontWeightMedium];
    cell.textLabel.numberOfLines = 2;
    cell.detailTextLabel.text = method.typeEncoding ?: @"";
    cell.detailTextLabel.font = [UIFont monospacedSystemFontOfSize:10.5 weight:UIFontWeightRegular];
    cell.detailTextLabel.textColor = UIColor.secondaryLabelColor;
    cell.accessoryView = [self ryg_buttonForMethod:method];
    cell.selectionStyle = UITableViewCellSelectionStyleNone;
    return cell;
}

@end

#pragma mark - Root browser owner

@implementation RYGFastRuntimeBrowserViewController (RYGRuntimeBrowserNonblockingOwner)

+ (void)load {
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        Method load = class_getInstanceMethod(self, NSSelectorFromString(@"loadSelectedImage"));
        Method nbLoad = class_getInstanceMethod(self, @selector(ryg_nb_loadSelectedImage));
        if (load && nbLoad) method_exchangeImplementations(load, nbLoad);

        Method filter = class_getInstanceMethod(self, NSSelectorFromString(@"applyFilter"));
        Method nbFilter = class_getInstanceMethod(self, @selector(ryg_nb_applyFilter));
        if (filter && nbFilter) method_exchangeImplementations(filter, nbFilter);

        Method select = class_getInstanceMethod(self, @selector(tableView:didSelectRowAtIndexPath:));
        Method nbSelect = class_getInstanceMethod(self, @selector(ryg_nb_tableView:didSelectRowAtIndexPath:));
        if (select && nbSelect) method_exchangeImplementations(select, nbSelect);
    });
}

- (void)ryg_nb_loadSelectedImage {
    // C-symbol mode keeps the existing Mach-O parser. Objective-C mode never
    // waits for a global method index anymore.
    if ([self modeControl].selectedSegmentIndex != 0) {
        [self ryg_nb_loadSelectedImage];
        return;
    }

    NSString *path = [self selectedImagePath].copy;
    NSUInteger generation = [self generation] + 1;
    [self setGeneration:generation];
    [[self spinner] stopAnimating];
    [self tableView].backgroundView = nil;

    RYGRuntimeImageIndex *bootstrap = RYGNBSnapshot(path, @[], @{}, 0, 0);
    [self setIndex:bootstrap];
    [self setVisibleClasses:@[]];
    [[self tableView] reloadData];
    if (!path.length) {
        [self emptyLabel].text = @"No loaded image.";
        [self tableView].backgroundView = [self emptyLabel];
        return;
    }

    __weak typeof(self) weakSelf = self;
    dispatch_async(RYGNBWorkerQueue(), ^{
        NSArray<RYGRuntimeClassRow *> *classes = RYGNBLightweightClasses(path);
        dispatch_async(dispatch_get_main_queue(), ^{
            __strong typeof(weakSelf) self = weakSelf;
            if (!self || generation != [self generation] || ![[self selectedImagePath] isEqualToString:path]) return;
            [self setIndex:RYGNBSnapshot(path, classes, @{}, classes.count, 0)];
            [self applyFilter];
        });
    });
}

- (void)ryg_nb_applyFilter {
    if ([self modeControl].selectedSegmentIndex != 0) {
        [self ryg_nb_applyFilter];
        return;
    }

    RYGRuntimeImageIndex *index = [self index];
    NSArray<RYGRuntimeClassRow *> *classes = index.classes ?: @[];
    NSString *query = [self searchController].searchBar.text ?: @"";
    NSArray<NSString *> *tokens = RYGNBTokens(query);

    if (!tokens.count) {
        NSNumber *generation = objc_getAssociatedObject(self, kRYGNBSearchGenerationKey) ?: @0;
        objc_setAssociatedObject(self, kRYGNBSearchGenerationKey, @(generation.unsignedIntegerValue + 1), OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        objc_setAssociatedObject(self, kRYGNBLastQueryKey, @"", OBJC_ASSOCIATION_COPY_NONATOMIC);
        [self setVisibleClasses:classes];
        [self emptyLabel].text = @"No Objective-C classes in this loaded image.";
        [self tableView].backgroundView = classes.count ? nil : [self emptyLabel];
        [[self tableView] reloadData];
        return;
    }

    NSMutableArray<RYGRuntimeClassRow *> *visible = [NSMutableArray array];
    for (RYGRuntimeClassRow *row in classes) {
        if (RYGNBMatches(row.className ?: @"", tokens)) {
            [visible addObject:row];
            continue;
        }
        for (RYGRuntimeBoolMethod *method in [index methodsForClassName:row.className]) {
            NSString *text = [NSString stringWithFormat:@"%@ %@ %@", row.className ?: @"", method.selectorName ?: @"", method.typeEncoding ?: @""];
            if (RYGNBMatches(text, tokens)) { [visible addObject:row]; break; }
        }
    }
    [self setVisibleClasses:visible.copy];
    [self emptyLabel].text = @"No ABI-validated BOOL method or class matched this loaded image.";
    [self tableView].backgroundView = visible.count ? nil : [self emptyLabel];
    [[self tableView] reloadData];

    NSString *last = objc_getAssociatedObject(self, kRYGNBLastQueryKey);
    if ([last isEqualToString:query]) return;
    objc_setAssociatedObject(self, kRYGNBLastQueryKey, query.copy, OBJC_ASSOCIATION_COPY_NONATOMIC);
    NSNumber *oldGeneration = objc_getAssociatedObject(self, kRYGNBSearchGenerationKey) ?: @0;
    NSUInteger searchGeneration = oldGeneration.unsignedIntegerValue + 1;
    objc_setAssociatedObject(self, kRYGNBSearchGenerationKey, @(searchGeneration), OBJC_ASSOCIATION_RETAIN_NONATOMIC);

    NSString *path = [self selectedImagePath].copy;
    NSUInteger browserGeneration = [self generation];
    __weak typeof(self) weakSelf = self;
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(250 * NSEC_PER_MSEC)), RYGNBWorkerQueue(), ^{
        __strong typeof(weakSelf) strongSelf = weakSelf;
        if (!strongSelf) return;
        NSNumber *currentGeneration = objc_getAssociatedObject(strongSelf, kRYGNBSearchGenerationKey);
        if (currentGeneration.unsignedIntegerValue != searchGeneration) return;

        NSMutableDictionary<NSString *, NSArray<RYGRuntimeBoolMethod *> *> *matches = [NSMutableDictionary dictionary];
        NSUInteger scannedMethods = 0;
        NSUInteger scannedClasses = 0;
        for (RYGRuntimeClassRow *row in classes) {
            currentGeneration = objc_getAssociatedObject(strongSelf, kRYGNBSearchGenerationKey);
            if (currentGeneration.unsignedIntegerValue != searchGeneration) return;
            NSArray<RYGRuntimeBoolMethod *> *allMethods = RYGNBBoolMethodsForClass(row);
            scannedMethods += allMethods.count;
            NSMutableArray *methodHits = nil;
            for (RYGRuntimeBoolMethod *method in allMethods) {
                NSString *text = [NSString stringWithFormat:@"%@ %@ %@", row.className ?: @"", method.selectorName ?: @"", method.typeEncoding ?: @""];
                if (!RYGNBMatches(text, tokens)) continue;
                if (!methodHits) methodHits = [NSMutableArray array];
                [methodHits addObject:method];
            }
            if (methodHits.count) matches[row.className] = methodHits.copy;
            scannedClasses++;

            if ((scannedClasses % 96) == 0) {
                NSDictionary *partial = matches.copy;
                NSUInteger partialClasses = scannedClasses;
                NSUInteger partialMethods = scannedMethods;
                dispatch_async(dispatch_get_main_queue(), ^{
                    __strong typeof(weakSelf) self = weakSelf;
                    NSNumber *generationNow = self ? objc_getAssociatedObject(self, kRYGNBSearchGenerationKey) : nil;
                    if (!self || generationNow.unsignedIntegerValue != searchGeneration || browserGeneration != [self generation] || ![[self selectedImagePath] isEqualToString:path]) return;
                    [self setIndex:RYGNBSnapshot(path, classes, partial, partialClasses, partialMethods)];
                    [self applyFilter];
                });
            }
        }

        NSDictionary *finalMatches = matches.copy;
        dispatch_async(dispatch_get_main_queue(), ^{
            __strong typeof(weakSelf) self = weakSelf;
            NSNumber *generationNow = self ? objc_getAssociatedObject(self, kRYGNBSearchGenerationKey) : nil;
            if (!self || generationNow.unsignedIntegerValue != searchGeneration || browserGeneration != [self generation] || ![[self selectedImagePath] isEqualToString:path]) return;
            [self setIndex:RYGNBSnapshot(path, classes, finalMatches, scannedClasses, scannedMethods)];
            [self applyFilter];
        });
    });
}

- (void)ryg_nb_tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath {
    if ([self modeControl].selectedSegmentIndex != 0) {
        [self ryg_nb_tableView:tableView didSelectRowAtIndexPath:indexPath];
        return;
    }
    [tableView deselectRowAtIndexPath:indexPath animated:YES];
    NSArray<RYGRuntimeClassRow *> *visible = [self visibleClasses];
    if ((NSUInteger)indexPath.row >= visible.count) return;
    RYGRuntimeClassRow *row = visible[(NSUInteger)indexPath.row];
    RYGOnDemandRuntimeClassViewController *detail = [[RYGOnDemandRuntimeClassViewController alloc]
        initWithClassRow:row query:[self searchController].searchBar.text ?: @""];
    [self.navigationController pushViewController:detail animated:YES];
}

@end
