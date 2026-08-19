#import "RYGDeveloperExactSurfaceViewController.h"
#import "RYGRuntimeBrowserEngine.h"
#import "RYGRuntimeLiveObserver.h"
#import "../UI/RYGLiquidGlass.h"
#import "../UI/RYGPopupChrome.h"
#import "../Utils.h"
#import <objc/runtime.h>
#import <dlfcn.h>
#include <string.h>

static const void *kRYGExactSurfaceRowKey = &kRYGExactSurfaceRowKey;

@interface RYGDeveloperExactRow : NSObject
@property (nonatomic, copy) NSString *displayTitle;
@property (nonatomic, strong) RYGRuntimeBoolMethod *method;
@end
@implementation RYGDeveloperExactRow @end

static NSString *RYGExactSurfaceTitle(RYGDeveloperExactSurface surface) {
    switch (surface) {
        case RYGDeveloperExactSurfaceStories: return @"Stories · Tray & Grid";
        case RYGDeveloperExactSurfaceBugReport: return @"Bug Report";
        case RYGDeveloperExactSurfaceSettingsVisibility: return @"Settings Rows";
        case RYGDeveloperExactSurfaceDirectDogfood: return @"Direct Dogfooding";
    }
    return @"Developer";
}

// These are not keyword searches. Every selector below was found verbatim in
// the current Instagram/FBShared binaries supplied for this build. At runtime
// we still require an actual loaded Objective-C method and a verified BOOL ABI;
// a stale selector simply produces no row.
static NSArray<NSDictionary<NSString *, NSString *> *> *RYGExactDescriptors(RYGDeveloperExactSurface surface) {
    switch (surface) {
        case RYGDeveloperExactSurfaceStories:
            return @[
                @{@"selector":@"isStoriesTraySkipped", @"title":@"Stories tray skipped"},
                @{@"selector":@"isOverlayStoriesTrayEnabled", @"title":@"Overlay stories tray"},
                @{@"selector":@"isPortableStoryTrayHidden", @"title":@"Portable story tray hidden"},
                @{@"selector":@"isStoriesTrayDecouplingEnabled", @"title":@"Stories tray decoupling"},
                @{@"selector":@"isStoriesTrayTapPrefetchEnabled", @"title":@"Stories tray tap prefetch"},
                @{@"selector":@"isStoryMultiAdsGrid", @"title":@"Story multi-ads grid"},
                @{@"selector":@"isDynamicTabStoryGridEnabled", @"title":@"Dynamic-tab story grid"},
                @{@"selector":@"hideStoriesTrayOnClassicFeed", @"title":@"Hide tray on classic feed"},
                @{@"selector":@"isStoriesTrayOnAllTabsEnabled", @"title":@"Stories tray on all tabs"},
            ];
        case RYGDeveloperExactSurfaceBugReport:
            return @[
                @{@"selector":@"isSandboxCreatorAgentEnabled", @"title":@"Sandbox creator agent"},
                @{@"selector":@"shouldRequestDebugConfig", @"title":@"Request debug config"},
                @{@"selector":@"isDebugModeEnabled", @"title":@"Debug mode"},
                @{@"selector":@"isInternalDebugEnabled:", @"title":@"Internal debug"},
                @{@"selector":@"isAdSpecificDebugInformationEnabled", @"title":@"Ad debug information"},
                @{@"selector":@"isDebugOverlayEnabled", @"title":@"Debug overlay"},
                @{@"selector":@"isJSDebugEnabled", @"title":@"JavaScript debug"},
                @{@"selector":@"isDebugIndicatorAllowed", @"title":@"Debug indicator"},
            ];
        case RYGDeveloperExactSurfaceSettingsVisibility:
            return @[
                @{@"selector":@"isNavigationToSettingDisabled", @"title":@"Navigation-to-setting disabled"},
                @{@"selector":@"isEligibleForCreatorSettingsReview", @"title":@"Creator settings review"},
                @{@"selector":@"shouldShowHighQualityUploadSetting", @"title":@"High-quality upload row"},
                @{@"selector":@"canShowHQUploadSetting", @"title":@"High-quality upload eligibility"},
                @{@"selector":@"shouldShowSettingEntryPointButton", @"title":@"Settings entry-point button"},
                @{@"selector":@"shouldLeftAlignSettingsEntrypointButton", @"title":@"Settings entry-point alignment"},
                @{@"selector":@"shouldShowBirthdayVisibilitySettingsButton", @"title":@"Birthday visibility row"},
                @{@"selector":@"canSeeTranslationSettings", @"title":@"Translation settings"},
                @{@"selector":@"isEligibleForMusicTabSettings", @"title":@"Music-tab settings"},
                @{@"selector":@"isShoppingSettingsEnabled", @"title":@"Shopping settings"},
                @{@"selector":@"isHiddenWordsSettingLinkToIgEnabled", @"title":@"Hidden-words settings link"},
                @{@"selector":@"shouldShowReuseSettingForOwner", @"title":@"Reuse setting"},
                @{@"selector":@"showInSettings", @"title":@"Show in settings"},
            ];
        case RYGDeveloperExactSurfaceDirectDogfood:
            return @[
                @{@"selector":@"is_dogfooding_option_enabled", @"title":@"Dogfooding option"},
                @{@"selector":@"isFbAcquisitionEpDogfoodModeEnabled", @"title":@"Acquisition dogfood mode"},
                @{@"selector":@"isInternalBuild", @"title":@"Internal build"},
                @{@"selector":@"isIGInternal", @"title":@"IG internal"},
                @{@"selector":@"isInternalOnly", @"title":@"Internal only"},
                @{@"selector":@"isInternalToggleOn", @"title":@"Internal toggle"},
            ];
    }
    return @[];
}

static const char *RYGExactSkipQualifiers(const char *type) {
    while (type && strchr("rnNoORV", *type)) type++;
    return type;
}

static RYGRuntimeArgumentKind RYGExactArgumentKind(Method method) {
    if (!method) return (RYGRuntimeArgumentKind)-1;
    unsigned int count = method_getNumberOfArguments(method);
    if (count == 2) return RYGRuntimeArgumentNone;
    if (count != 3) return (RYGRuntimeArgumentKind)-1;
    char encoded[64] = {0};
    method_getArgumentType(method, 2, encoded, sizeof(encoded));
    const char *type = RYGExactSkipQualifiers(encoded);
    if (!type || !*type) return (RYGRuntimeArgumentKind)-1;
    if (*type == '@' || *type == '#' || *type == ':') return RYGRuntimeArgumentObject;
    if (strchr("BcCsSiIlLqQ", *type)) return RYGRuntimeArgumentInteger;
    return (RYGRuntimeArgumentKind)-1;
}

static BOOL RYGExactSupportedBool(Method method) {
    if (!method) return NO;
    char encoded[32] = {0};
    method_getReturnType(method, encoded, sizeof(encoded));
    const char *ret = RYGExactSkipQualifiers(encoded);
    return ret && *ret == 'B' && RYGExactArgumentKind(method) >= 0;
}

static NSDictionary<NSString *, NSString *> *RYGExactDescriptorForSelector(NSString *selector,
                                                                            RYGDeveloperExactSurface surface) {
    for (NSDictionary *descriptor in RYGExactDescriptors(surface)) {
        if ([descriptor[@"selector"] isEqualToString:selector]) return descriptor;
    }
    return nil;
}

static BOOL RYGExactClassBelongsToAppImage(Class cls, NSSet<NSString *> *imagePaths) {
    if (!cls) return NO;
    const char *raw = class_getImageName(cls);
    if (!raw) return NO;
    NSString *path = [[NSString stringWithUTF8String:raw] stringByStandardizingPath];
    if ([imagePaths containsObject:path]) return YES;
    NSString *name = path.lastPathComponent;
    for (NSString *candidate in imagePaths) {
        if (name.length && [candidate.lastPathComponent isEqualToString:name]) return YES;
    }
    return NO;
}

static NSArray<RYGDeveloperExactRow *> *RYGExactScanSurface(RYGDeveloperExactSurface surface) {
    NSArray<NSDictionary<NSString *, NSString *> *> *descriptors = RYGExactDescriptors(surface);
    NSMutableSet<NSString *> *wantedSelectors = [NSMutableSet setWithCapacity:descriptors.count];
    for (NSDictionary *descriptor in descriptors) [wantedSelectors addObject:descriptor[@"selector"]];

    NSMutableSet<NSString *> *images = [NSMutableSet set];
    for (NSString *path in [RYGRuntimeBrowserEngine runtimeImagePaths]) {
        if (path.length) [images addObject:path.stringByStandardizingPath];
    }

    unsigned int classCount = 0;
    Class *classes = objc_copyClassList(&classCount);
    if (!classes) return @[];
    NSMutableArray<RYGDeveloperExactRow *> *rows = [NSMutableArray array];
    NSMutableSet<NSString *> *dedupe = [NSMutableSet set];

    for (unsigned int classIndex = 0; classIndex < classCount; classIndex++) {
        Class cls = classes[classIndex];
        if (!RYGExactClassBelongsToAppImage(cls, images)) continue;
        NSString *className = NSStringFromClass(cls);
        if (!className.length) continue;

        for (NSInteger pass = 0; pass < 2; pass++) {
            BOOL classMethod = pass == 1;
            Class owner = classMethod ? object_getClass(cls) : cls;
            if (!owner) continue;
            unsigned int methodCount = 0;
            Method *methods = class_copyMethodList(owner, &methodCount);
            for (unsigned int methodIndex = 0; methodIndex < methodCount; methodIndex++) {
                Method method = methods[methodIndex];
                SEL selector = method_getName(method);
                if (!selector) continue;
                NSString *selectorName = NSStringFromSelector(selector);
                if (![wantedSelectors containsObject:selectorName] || !RYGExactSupportedBool(method)) continue;

                RYGRuntimeBoolMethod *runtimeMethod = [RYGRuntimeBoolMethod new];
                runtimeMethod.className = className;
                runtimeMethod.selectorName = selectorName;
                runtimeMethod.classMethod = classMethod;
                runtimeMethod.argumentKind = RYGExactArgumentKind(method);
                const char *types = method_getTypeEncoding(method);
                runtimeMethod.typeEncoding = types ? [NSString stringWithUTF8String:types] : @"";
                const char *rawImage = class_getImageName(cls);
                runtimeMethod.imagePath = rawImage ? [NSString stringWithUTF8String:rawImage] : @"";
                if (!runtimeMethod.overrideKey.length || [dedupe containsObject:runtimeMethod.overrideKey]) continue;
                [dedupe addObject:runtimeMethod.overrideKey];

                NSDictionary *descriptor = RYGExactDescriptorForSelector(selectorName, surface);
                RYGDeveloperExactRow *row = [RYGDeveloperExactRow new];
                row.displayTitle = descriptor[@"title"] ?: selectorName;
                row.method = runtimeMethod;
                [rows addObject:row];
            }
            if (methods) free(methods);
        }
    }
    free(classes);

    [rows sortUsingComparator:^NSComparisonResult(RYGDeveloperExactRow *left, RYGDeveloperExactRow *right) {
        NSComparisonResult title = [left.displayTitle localizedCaseInsensitiveCompare:right.displayTitle];
        if (title != NSOrderedSame) return title;
        return [left.method.className localizedCaseInsensitiveCompare:right.method.className];
    }];
    return rows.copy;
}

@interface RYGDeveloperExactSurfaceViewController ()
@property (nonatomic, assign) RYGDeveloperExactSurface surface;
@property (nonatomic, copy) NSArray<RYGDeveloperExactRow *> *rows;
@property (nonatomic, assign) NSUInteger scanGeneration;
@property (nonatomic, strong) UIActivityIndicatorView *spinner;
@end

@implementation RYGDeveloperExactSurfaceViewController

- (instancetype)initWithSurface:(RYGDeveloperExactSurface)surface {
    self = [super initWithStyle:UITableViewStyleInsetGrouped];
    if (self) {
        _surface = surface;
        _rows = @[];
    }
    return self;
}

- (void)viewDidLoad {
    [super viewDidLoad];
    self.title = RYGExactSurfaceTitle(self.surface);
    self.view.backgroundColor = [RYGPopupChrome backgroundColor];
    self.tableView.backgroundColor = [RYGPopupChrome backgroundColor];
    self.tableView.rowHeight = UITableViewAutomaticDimension;
    self.tableView.estimatedRowHeight = 54.0;
    self.navigationItem.rightBarButtonItem = [[UIBarButtonItem alloc]
        initWithImage:[UIImage systemImageNamed:@"arrow.clockwise"]
                style:UIBarButtonItemStylePlain
               target:self
               action:@selector(refreshSurface)];
    self.spinner = [[UIActivityIndicatorView alloc] initWithActivityIndicatorStyle:UIActivityIndicatorViewStyleMedium];
    [NSNotificationCenter.defaultCenter addObserver:self
                                           selector:@selector(runtimeValueChanged:)
                                               name:RYGRuntimeNativeValueDidChangeNotification
                                             object:nil];
    RYGLiquidGlassApplyToViewController(self);
    [self refreshSurface];
}

- (void)dealloc {
    [NSNotificationCenter.defaultCenter removeObserver:self];
}

- (void)refreshSurface {
    NSUInteger generation = ++self.scanGeneration;
    [self.spinner startAnimating];
    self.tableView.backgroundView = self.spinner;
    RYGDeveloperExactSurface surface = self.surface;
    __weak typeof(self) weakSelf = self;
    dispatch_async(dispatch_get_global_queue(QOS_CLASS_USER_INITIATED, 0), ^{
        NSArray *rows = RYGExactScanSurface(surface);
        dispatch_async(dispatch_get_main_queue(), ^{
            __strong typeof(weakSelf) self = weakSelf;
            if (!self || generation != self.scanGeneration) return;
            self.rows = rows;
            [self.spinner stopAnimating];
            if (!rows.count) {
                UILabel *empty = [UILabel new];
                empty.text = @"No verified runtime gate from this surface is loaded.";
                empty.textAlignment = NSTextAlignmentCenter;
                empty.numberOfLines = 0;
                empty.textColor = UIColor.secondaryLabelColor;
                self.tableView.backgroundView = empty;
            } else {
                self.tableView.backgroundView = nil;
            }
            [self.tableView reloadData];
        });
    });
}

- (void)runtimeValueChanged:(NSNotification *)notification {
    NSString *key = notification.userInfo[RYGRuntimeNativeValueKeyUserInfoKey];
    if (!key.length) return;
    for (RYGDeveloperExactRow *row in self.rows) {
        if ([row.method.overrideKey isEqualToString:key]) {
            [self.tableView reloadData];
            break;
        }
    }
}

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section {
    (void)tableView; (void)section;
    return self.rows.count;
}

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath {
    (void)tableView;
    RYGDeveloperExactRow *row = self.rows[(NSUInteger)indexPath.row];
    RYGRuntimeBoolMethod *method = row.method;
    UITableViewCell *cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleSubtitle reuseIdentifier:nil];
    cell.textLabel.text = row.displayTitle;
    cell.textLabel.font = [UIFont systemFontOfSize:15.0 weight:UIFontWeightMedium];
    cell.detailTextLabel.text = [NSString stringWithFormat:@"%@ %@", method.classMethod ? @"+" : @"-", method.selectorName];
    cell.detailTextLabel.font = [UIFont systemFontOfSize:11.0 weight:UIFontWeightRegular];
    cell.detailTextLabel.textColor = UIColor.secondaryLabelColor;
    cell.detailTextLabel.numberOfLines = 1;

    NSNumber *forced = method.overrideValue;
    NSNumber *native = method.liveValue;
    UISwitch *toggle = [UISwitch new];
    toggle.on = forced ? forced.boolValue : (native ? native.boolValue : NO);
    objc_setAssociatedObject(toggle, kRYGExactSurfaceRowKey, row, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    [toggle addTarget:self action:@selector(toggleChanged:) forControlEvents:UIControlEventValueChanged];
    cell.accessoryView = toggle;
    cell.imageView.image = [UIImage systemImageNamed:forced ? @"slider.horizontal.3" : @"switch.2"];
    cell.imageView.tintColor = forced ? [RYGUtils RYGColor_Primary] : UIColor.secondaryLabelColor;
    return cell;
}

- (void)toggleChanged:(UISwitch *)toggle {
    RYGDeveloperExactRow *row = objc_getAssociatedObject(toggle, kRYGExactSurfaceRowKey);
    if (!row.method) return;
    [RYGRuntimeBrowserEngine setOverride:@(toggle.isOn) forMethod:row.method];
    [self.tableView reloadData];
}

- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath {
    UITableViewCell *cell = [tableView cellForRowAtIndexPath:indexPath];
    [tableView deselectRowAtIndexPath:indexPath animated:YES];
    RYGDeveloperExactRow *row = self.rows[(NSUInteger)indexPath.row];
    RYGRuntimeBoolMethod *method = row.method;
    NSNumber *native = method.liveValue;
    NSNumber *forced = method.overrideValue;
    NSString *message = [NSString stringWithFormat:@"%@\n%@\nNative: %@\nOverride: %@",
                         method.className ?: @"",
                         method.typeEncoding ?: @"",
                         native ? (native.boolValue ? @"true" : @"false") : @"not observed",
                         forced ? (forced.boolValue ? @"true" : @"false") : @"native"];
    UIAlertController *sheet = [UIAlertController alertControllerWithTitle:row.displayTitle
                                                                    message:message
                                                             preferredStyle:UIAlertControllerStyleActionSheet];
    __weak typeof(self) weakSelf = self;
    [sheet addAction:[UIAlertAction actionWithTitle:@"Observe Native" style:UIAlertActionStyleDefault handler:^(__unused UIAlertAction *action) {
        RYGRuntimeBeginLiveObservation(@[method]);
    }]];
    [sheet addAction:[UIAlertAction actionWithTitle:@"Force On" style:UIAlertActionStyleDefault handler:^(__unused UIAlertAction *action) {
        [RYGRuntimeBrowserEngine setOverride:@YES forMethod:method]; [weakSelf.tableView reloadData];
    }]];
    [sheet addAction:[UIAlertAction actionWithTitle:@"Force Off" style:UIAlertActionStyleDefault handler:^(__unused UIAlertAction *action) {
        [RYGRuntimeBrowserEngine setOverride:@NO forMethod:method]; [weakSelf.tableView reloadData];
    }]];
    if (forced) {
        [sheet addAction:[UIAlertAction actionWithTitle:@"Use Native" style:UIAlertActionStyleDestructive handler:^(__unused UIAlertAction *action) {
            [RYGRuntimeBrowserEngine setOverride:nil forMethod:method]; [weakSelf.tableView reloadData];
        }]];
    }
    [sheet addAction:[UIAlertAction actionWithTitle:@"Cancel" style:UIAlertActionStyleCancel handler:nil]];
    if (UIDevice.currentDevice.userInterfaceIdiom == UIUserInterfaceIdiomPad) {
        sheet.popoverPresentationController.sourceView = cell ?: self.view;
        sheet.popoverPresentationController.sourceRect = cell ? cell.bounds : self.view.bounds;
    }
    [self presentViewController:sheet animated:YES completion:nil];
}

@end