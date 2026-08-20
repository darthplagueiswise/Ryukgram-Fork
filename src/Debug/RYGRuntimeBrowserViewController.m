#import "RYGRuntimeBrowserViewController.h"
#import "RYGRuntimeBrowserEngine.h"
#import "RYGRuntimeLiveObserver.h"
#import "../UI/RYGLiquidGlass.h"
#import "../UI/RYGPopupChrome.h"
#import "../Utils.h"

static NSString *const kRYGRuntimeSelectedImageKey = @"ryg_runtime_browser_selected_image";

static NSString *RYGRuntimeImagePersistenceID(NSString *path) {
    NSString *standard = path.stringByStandardizingPath;
    NSString *root = NSBundle.mainBundle.bundlePath.stringByStandardizingPath;
    NSString *prefix = [root stringByAppendingString:@"/"];
    if ([standard hasPrefix:prefix]) return [standard substringFromIndex:prefix.length];
    return standard.lastPathComponent ?: @"";
}

static NSString *RYGRuntimeNormalizedSearch(NSString *value) {
    if (!value.length) return @"";
    NSMutableString *result = [NSMutableString stringWithCapacity:value.length];
    NSString *lower = value.lowercaseString;
    BOOL previousSpace = YES;
    for (NSUInteger index = 0; index < lower.length; index++) {
        unichar character = [lower characterAtIndex:index];
        BOOL alphaNumeric = (character >= 'a' && character <= 'z') ||
                            (character >= '0' && character <= '9');
        if (alphaNumeric) {
            [result appendFormat:@"%C", character];
            previousSpace = NO;
        } else if (!previousSpace) {
            [result appendString:@" "];
            previousSpace = YES;
        }
    }
    return [result stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceCharacterSet];
}

static BOOL RYGRuntimeMethodMatchesQuery(RYGRuntimeBoolMethod *method, NSString *query) {
    NSString *needle = RYGRuntimeNormalizedSearch(query);
    if (!needle.length) return YES;

    NSString *haystack = RYGRuntimeNormalizedSearch([NSString stringWithFormat:@"%@ %@ %@ %@",
        method.className ?: @"",
        method.selectorName ?: @"",
        method.typeEncoding ?: @"",
        method.imagePath.lastPathComponent ?: @""]);
    NSString *compact = [haystack stringByReplacingOccurrencesOfString:@" " withString:@""];

    for (NSString *token in [needle componentsSeparatedByString:@" "]) {
        if (!token.length) continue;
        if ([haystack rangeOfString:token].location == NSNotFound &&
            [compact rangeOfString:token].location == NSNotFound) return NO;
    }
    return YES;
}

@interface RYGRuntimeBrowserViewController () <UITableViewDataSource, UITableViewDelegate, UISearchResultsUpdating>
@property (nonatomic, strong) UITableView *tableView;
@property (nonatomic, strong) UIButton *imageButton;
@property (nonatomic, strong) UISearchController *searchController;
@property (nonatomic, strong) UIActivityIndicatorView *spinner;
@property (nonatomic, strong) UILabel *emptyLabel;
@property (nonatomic, copy) NSArray<NSString *> *images;
@property (nonatomic, copy) NSString *selectedImagePath;
@property (nonatomic, copy) NSArray<RYGRuntimeBoolMethod *> *allRows;
@property (nonatomic, copy) NSArray<RYGRuntimeBoolMethod *> *visibleRows;
@property (nonatomic, assign) NSUInteger scanGeneration;
@property (nonatomic, assign, getter=isScanning) BOOL scanning;
@end

@implementation RYGRuntimeBrowserViewController

- (void)viewDidLoad {
    [super viewDidLoad];
    self.title = @"Runtime Browser";
    self.view.backgroundColor = [RYGPopupChrome backgroundColor];
    self.allRows = @[];
    self.visibleRows = @[];

    self.imageButton = [UIButton buttonWithType:UIButtonTypeSystem];
    self.imageButton.translatesAutoresizingMaskIntoConstraints = NO;
    self.imageButton.showsMenuAsPrimaryAction = YES;
    self.imageButton.changesSelectionAsPrimaryAction = NO;
    self.imageButton.contentHorizontalAlignment = UIControlContentHorizontalAlignmentLeading;
    self.imageButton.titleLabel.lineBreakMode = NSLineBreakByTruncatingMiddle;
    [self.view addSubview:self.imageButton];

    self.tableView = [[UITableView alloc] initWithFrame:CGRectZero style:UITableViewStyleInsetGrouped];
    self.tableView.translatesAutoresizingMaskIntoConstraints = NO;
    self.tableView.backgroundColor = [RYGPopupChrome backgroundColor];
    self.tableView.dataSource = self;
    self.tableView.delegate = self;
    self.tableView.keyboardDismissMode = UIScrollViewKeyboardDismissModeOnDrag;
    self.tableView.rowHeight = UITableViewAutomaticDimension;
    self.tableView.estimatedRowHeight = 52.0;
    [self.view addSubview:self.tableView];

    UILayoutGuide *guide = self.view.safeAreaLayoutGuide;
    [NSLayoutConstraint activateConstraints:@[
        [self.imageButton.topAnchor constraintEqualToAnchor:guide.topAnchor constant:8.0],
        [self.imageButton.leadingAnchor constraintEqualToAnchor:guide.leadingAnchor constant:16.0],
        [self.imageButton.trailingAnchor constraintEqualToAnchor:guide.trailingAnchor constant:-16.0],
        [self.imageButton.heightAnchor constraintGreaterThanOrEqualToConstant:44.0],
        [self.tableView.topAnchor constraintEqualToAnchor:self.imageButton.bottomAnchor constant:4.0],
        [self.tableView.leadingAnchor constraintEqualToAnchor:self.view.leadingAnchor],
        [self.tableView.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor],
        [self.tableView.bottomAnchor constraintEqualToAnchor:self.view.bottomAnchor],
    ]];

    self.searchController = [[UISearchController alloc] initWithSearchResultsController:nil];
    self.searchController.searchResultsUpdater = self;
    self.searchController.obscuresBackgroundDuringPresentation = NO;
    self.searchController.searchBar.placeholder = @"Class, BOOL or ABI";
    self.navigationItem.searchController = self.searchController;
    self.navigationItem.hidesSearchBarWhenScrolling = NO;

    self.spinner = [[UIActivityIndicatorView alloc] initWithActivityIndicatorStyle:UIActivityIndicatorViewStyleMedium];
    self.emptyLabel = [UILabel new];
    self.emptyLabel.textAlignment = NSTextAlignmentCenter;
    self.emptyLabel.numberOfLines = 0;
    self.emptyLabel.textColor = UIColor.secondaryLabelColor;
    self.emptyLabel.font = [UIFont systemFontOfSize:14.0 weight:UIFontWeightRegular];

    __weak typeof(self) weakSelf = self;
    UIAction *observe = [UIAction actionWithTitle:@"Observe visible original values"
                                            image:[UIImage systemImageNamed:@"waveform.path.ecg"]
                                       identifier:nil
                                          handler:^(__unused UIAction *action) {
        [weakSelf observeVisibleRows];
    }];
    UIAction *refresh = [UIAction actionWithTitle:@"Refresh selected image"
                                            image:[UIImage systemImageNamed:@"arrow.clockwise"]
                                       identifier:nil
                                          handler:^(__unused UIAction *action) {
        [weakSelf refreshAndScan];
    }];
    self.navigationItem.rightBarButtonItem = [[UIBarButtonItem alloc]
        initWithImage:[UIImage systemImageNamed:@"ellipsis.circle"]
                 menu:[UIMenu menuWithTitle:@"Runtime" children:@[observe, refresh]]];

    [NSNotificationCenter.defaultCenter addObserver:self
                                           selector:@selector(nativeValueChanged:)
                                               name:RYGRuntimeNativeValueDidChangeNotification
                                             object:nil];

    [self refreshRuntimeImages];
    [self rebuildImageMenu];
    RYGLiquidGlassApplyToViewController(self);
    [self scanSelectedImage];
}

- (void)dealloc {
    [NSNotificationCenter.defaultCenter removeObserver:self];
}

- (void)refreshRuntimeImages {
    self.images = [RYGRuntimeBrowserEngine runtimeImagePaths] ?: @[];
    NSString *stored = [NSUserDefaults.standardUserDefaults stringForKey:kRYGRuntimeSelectedImageKey];
    NSString *main = NSBundle.mainBundle.executablePath.stringByStandardizingPath;

    if (!self.selectedImagePath.length || ![self.images containsObject:self.selectedImagePath]) {
        self.selectedImagePath = nil;
        for (NSString *path in self.images) {
            if (stored.length && [RYGRuntimeImagePersistenceID(path) isEqualToString:stored]) {
                self.selectedImagePath = path;
                break;
            }
        }
        if (!self.selectedImagePath.length) {
            for (NSString *path in self.images) {
                if ([path.stringByStandardizingPath isEqualToString:main]) {
                    self.selectedImagePath = path;
                    break;
                }
            }
        }
        if (!self.selectedImagePath.length) self.selectedImagePath = self.images.firstObject;
    }
}

- (void)rebuildImageMenu {
    NSMutableArray<UIMenuElement *> *actions = [NSMutableArray arrayWithCapacity:self.images.count];
    __weak typeof(self) weakSelf = self;
    NSString *main = NSBundle.mainBundle.executablePath.stringByStandardizingPath;

    for (NSString *path in self.images) {
        NSString *title = [RYGRuntimeBrowserEngine shortNameForImagePath:path];
        UIAction *action = [UIAction actionWithTitle:title
                                              image:[UIImage systemImageNamed:[path.stringByStandardizingPath isEqualToString:main] ? @"app" : @"shippingbox"]
                                         identifier:nil
                                            handler:^(__unused UIAction *item) {
            __strong typeof(weakSelf) self = weakSelf;
            if (!self) return;
            self.selectedImagePath = path;
            [NSUserDefaults.standardUserDefaults setObject:RYGRuntimeImagePersistenceID(path)
                                                    forKey:kRYGRuntimeSelectedImageKey];
            [self rebuildImageMenu];
            [self scanSelectedImage];
        }];
        action.state = [path isEqualToString:self.selectedImagePath] ? UIMenuElementStateOn : UIMenuElementStateOff;
        [actions addObject:action];
    }

    NSString *shortName = self.selectedImagePath.length
        ? [RYGRuntimeBrowserEngine shortNameForImagePath:self.selectedImagePath]
        : @"No loaded image";
    NSString *title = [NSString stringWithFormat:@"Image: %@", shortName];
    self.imageButton.menu = [UIMenu menuWithTitle:@"Loaded executable and frameworks"
                                            image:nil
                                       identifier:nil
                                          options:UIMenuOptionsSingleSelection
                                         children:actions];

    // Configure Glass after the menu exists so UIKit keeps the native menu-source
    // metrics and closed-to-expanded morphing behavior.
    RYGLiquidGlassConfigureButton(self.imageButton, NO);
    UIButtonConfiguration *configuration = self.imageButton.configuration;
    if (configuration) {
        configuration.title = title;
        if (@available(iOS 26.0, *)) [configuration setDefaultContentInsets];
        self.imageButton.configuration = configuration;
    } else {
        [self.imageButton setTitle:title forState:UIControlStateNormal];
    }
}

- (void)setScanning:(BOOL)scanning {
    _scanning = scanning;
    if (scanning) {
        [self.spinner startAnimating];
        self.tableView.backgroundView = self.spinner;
    } else {
        [self.spinner stopAnimating];
        self.tableView.backgroundView = self.visibleRows.count ? nil : self.emptyLabel;
    }
}

- (void)refreshAndScan {
    [self refreshRuntimeImages];
    [self rebuildImageMenu];
    [self scanSelectedImage];
}

- (void)scanSelectedImage {
    NSString *imagePath = self.selectedImagePath.copy;
    NSUInteger generation = ++self.scanGeneration;
    if (!imagePath.length) {
        self.allRows = @[];
        self.visibleRows = @[];
        self.emptyLabel.text = @"No loaded app image";
        self.scanning = NO;
        [self.tableView reloadData];
        return;
    }

    self.scanning = YES;
    __weak typeof(self) weakSelf = self;
    dispatch_async(dispatch_get_global_queue(QOS_CLASS_USER_INITIATED, 0), ^{
        NSArray<RYGRuntimeBoolMethod *> *rows =
            [RYGRuntimeBrowserEngine boolMethodsForImagePath:imagePath scope:RYGRuntimeBrowserScopeAll];
        dispatch_async(dispatch_get_main_queue(), ^{
            __strong typeof(weakSelf) self = weakSelf;
            if (!self || generation != self.scanGeneration || ![self.selectedImagePath isEqualToString:imagePath]) return;
            self.allRows = rows ?: @[];
            self.scanning = NO;
            [self applySearchFilter];
        });
    });
}

- (void)updateSearchResultsForSearchController:(UISearchController *)searchController {
    (void)searchController;
    [self applySearchFilter];
}

- (void)applySearchFilter {
    NSString *query = self.searchController.searchBar.text ?: @"";
    if (!query.length) {
        self.visibleRows = self.allRows ?: @[];
    } else {
        NSMutableArray<RYGRuntimeBoolMethod *> *matches = [NSMutableArray array];
        for (RYGRuntimeBoolMethod *method in self.allRows) {
            if (RYGRuntimeMethodMatchesQuery(method, query)) [matches addObject:method];
        }
        self.visibleRows = matches.copy;
    }

    self.emptyLabel.text = query.length
        ? @"No ABI-supported BOOL matched this search"
        : @"No ABI-supported BOOL is declared in this loaded image";
    if (!self.isScanning) self.tableView.backgroundView = self.visibleRows.count ? nil : self.emptyLabel;
    [self.tableView reloadData];
}

- (void)observeVisibleRows {
    if (!self.visibleRows.count) return;
    RYGRuntimeBeginLiveObservation(self.visibleRows);
    [RYGUtils showToastForDuration:1.4
                            title:@"Live observation"
                         subtitle:[NSString stringWithFormat:@"Observing up to %lu visible BOOLs",
                                   (unsigned long)MIN(self.visibleRows.count, (NSUInteger)64)]];
}

- (void)nativeValueChanged:(NSNotification *)notification {
    NSString *key = notification.userInfo[RYGRuntimeNativeValueKeyUserInfoKey];
    if (!key.length) return;
    for (RYGRuntimeBoolMethod *method in self.visibleRows) {
        if ([method.overrideKey isEqualToString:key]) {
            [self.tableView reloadData];
            break;
        }
    }
}

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section {
    (void)tableView;
    (void)section;
    return self.visibleRows.count;
}

- (NSString *)tableView:(UITableView *)tableView titleForHeaderInSection:(NSInteger)section {
    (void)tableView;
    (void)section;
    if (!self.visibleRows.count) return nil;
    return [NSString stringWithFormat:@"%lu hookable BOOL%@",
            (unsigned long)self.visibleRows.count,
            self.visibleRows.count == 1 ? @"" : @"s"];
}

- (UIButton *)outputButtonForMethod:(RYGRuntimeBoolMethod *)method {
    NSNumber *forced = method.overrideValue;
    NSNumber *native = method.liveValue;
    NSString *closedTitle = forced
        ? (forced.boolValue ? @"On" : @"Off")
        : (native ? (native.boolValue ? @"Native On" : @"Native Off") : @"Native");

    __weak typeof(self) weakSelf = self;
    UIAction *nativeAction = [UIAction actionWithTitle:@"Native"
                                                image:nil
                                           identifier:nil
                                              handler:^(__unused UIAction *action) {
        [RYGRuntimeBrowserEngine setOverride:nil forMethod:method];
        [weakSelf.tableView reloadData];
    }];
    nativeAction.state = forced ? UIMenuElementStateOff : UIMenuElementStateOn;

    UIAction *forceOn = [UIAction actionWithTitle:@"Force On"
                                           image:nil
                                      identifier:nil
                                         handler:^(__unused UIAction *action) {
        [RYGRuntimeBrowserEngine setOverride:@YES forMethod:method];
        [weakSelf.tableView reloadData];
    }];
    forceOn.state = forced && forced.boolValue ? UIMenuElementStateOn : UIMenuElementStateOff;

    UIAction *forceOff = [UIAction actionWithTitle:@"Force Off"
                                            image:nil
                                       identifier:nil
                                          handler:^(__unused UIAction *action) {
        [RYGRuntimeBrowserEngine setOverride:@NO forMethod:method];
        [weakSelf.tableView reloadData];
    }];
    forceOff.state = forced && !forced.boolValue ? UIMenuElementStateOn : UIMenuElementStateOff;

    UIButton *button = [UIButton buttonWithType:UIButtonTypeSystem];
    button.menu = [UIMenu menuWithTitle:@"Output"
                                  image:nil
                             identifier:nil
                                options:UIMenuOptionsSingleSelection
                               children:@[nativeAction, forceOn, forceOff]];
    button.showsMenuAsPrimaryAction = YES;
    button.changesSelectionAsPrimaryAction = YES;
    RYGLiquidGlassConfigureButton(button, NO);
    UIButtonConfiguration *configuration = button.configuration;
    if (configuration) {
        configuration.title = closedTitle;
        if (@available(iOS 26.0, *)) [configuration setDefaultContentInsets];
        button.configuration = configuration;
    } else {
        [button setTitle:closedTitle forState:UIControlStateNormal];
    }
    return button;
}

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath {
    static NSString *identifier = @"RYGRuntimeDirectBool";
    UITableViewCell *cell = [tableView dequeueReusableCellWithIdentifier:identifier];
    if (!cell) cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleSubtitle reuseIdentifier:identifier];
    if ((NSUInteger)indexPath.row >= self.visibleRows.count) return cell;

    RYGRuntimeBoolMethod *method = self.visibleRows[(NSUInteger)indexPath.row];
    cell.textLabel.text = [NSString stringWithFormat:@"%@[%@ %@]",
                           method.classMethod ? @"+" : @"−",
                           method.className ?: @"",
                           method.selectorName ?: @""];
    cell.textLabel.font = [UIFont monospacedSystemFontOfSize:12.0 weight:UIFontWeightMedium];
    cell.textLabel.numberOfLines = 0;
    cell.textLabel.lineBreakMode = NSLineBreakByCharWrapping;

    NSNumber *native = method.liveValue;
    NSNumber *forced = method.overrideValue;
    NSString *nativeText = native
        ? (native.boolValue ? @"original true" : @"original false")
        : @"original not observed";
    NSString *outputText = forced
        ? (forced.boolValue ? @"forced true" : @"forced false")
        : @"native output";
    cell.detailTextLabel.text = [NSString stringWithFormat:@"%@ · %@ · %@",
                                 method.typeEncoding ?: @"",
                                 nativeText,
                                 outputText];
    cell.detailTextLabel.font = [UIFont monospacedSystemFontOfSize:10.0 weight:UIFontWeightRegular];
    cell.detailTextLabel.textColor = UIColor.secondaryLabelColor;
    cell.detailTextLabel.numberOfLines = 0;
    cell.accessoryView = [self outputButtonForMethod:method];
    cell.selectionStyle = UITableViewCellSelectionStyleDefault;
    return cell;
}

- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath {
    UITableViewCell *cell = [tableView cellForRowAtIndexPath:indexPath];
    [tableView deselectRowAtIndexPath:indexPath animated:YES];
    if ((NSUInteger)indexPath.row >= self.visibleRows.count) return;
    [self presentActionsForMethod:self.visibleRows[(NSUInteger)indexPath.row] source:cell];
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
    [sheet addAction:[UIAlertAction actionWithTitle:@"Observe original live value"
                                             style:UIAlertActionStyleDefault
                                           handler:^(__unused UIAlertAction *action) {
        RYGRuntimeBeginLiveObservation(@[method]);
    }]];
    [sheet addAction:[UIAlertAction actionWithTitle:@"Force true"
                                             style:UIAlertActionStyleDefault
                                           handler:^(__unused UIAlertAction *action) {
        [RYGRuntimeBrowserEngine setOverride:@YES forMethod:method];
        [weakSelf.tableView reloadData];
    }]];
    [sheet addAction:[UIAlertAction actionWithTitle:@"Force false"
                                             style:UIAlertActionStyleDefault
                                           handler:^(__unused UIAlertAction *action) {
        [RYGRuntimeBrowserEngine setOverride:@NO forMethod:method];
        [weakSelf.tableView reloadData];
    }]];
    if (forced) {
        [sheet addAction:[UIAlertAction actionWithTitle:@"Use native value"
                                                 style:UIAlertActionStyleDestructive
                                               handler:^(__unused UIAlertAction *action) {
            [RYGRuntimeBrowserEngine setOverride:nil forMethod:method];
            [weakSelf.tableView reloadData];
        }]];
    }
    [sheet addAction:[UIAlertAction actionWithTitle:@"Copy method details"
                                             style:UIAlertActionStyleDefault
                                           handler:^(__unused UIAlertAction *action) {
        UIPasteboard.generalPasteboard.string = [NSString stringWithFormat:@"%@[%@ %@] %@",
            method.classMethod ? @"+" : @"−",
            method.className ?: @"",
            method.selectorName ?: @"",
            method.typeEncoding ?: @""];
    }]];
    [sheet addAction:[UIAlertAction actionWithTitle:@"Cancel" style:UIAlertActionStyleCancel handler:nil]];

    if (UIDevice.currentDevice.userInterfaceIdiom == UIUserInterfaceIdiomPad) {
        sheet.popoverPresentationController.sourceView = source ?: self.view;
        sheet.popoverPresentationController.sourceRect = source ? source.bounds : self.view.bounds;
    }
    [self presentViewController:sheet animated:YES completion:nil];
}

@end
