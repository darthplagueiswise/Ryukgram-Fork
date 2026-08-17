#import "RYGDeveloperGateViewController.h"
#import "RYGRuntimeBrowserEngine.h"
#import "RYGRuntimeLiveObserver.h"
#import "../Settings/RYGSetting.h"
#import "../Settings/RYGSymbol.h"
#import "../UI/RYGIcon.h"
#import "../UI/RYGLiquidGlass.h"
#import "../Utils.h"
#import <QuartzCore/QuartzCore.h>
#import <objc/runtime.h>
#include <stdlib.h>
#include <string.h>

typedef struct {
    __unsafe_unretained NSString *selector;
    __unsafe_unretained NSString *classNeedle;
    __unsafe_unretained NSString *displayTitle;
} RYGDeveloperGateDescriptor;

@interface RYGDeveloperGateViewController ()
@property (nonatomic, assign) RYGDeveloperGateSurface surface;
@property (nonatomic, copy) NSArray<RYGRuntimeBoolMethod *> *gateRows;
@property (nonatomic, assign) BOOL scanning;
@property (nonatomic, assign) NSUInteger scanGeneration;
@end

static NSString *RYGDeveloperSurfaceTitle(RYGDeveloperGateSurface surface) {
    switch (surface) {
        case RYGDeveloperGateSurfaceWordMark: return @"IGWordMark";
        case RYGDeveloperGateSurfaceInternal: return @"Easy Gating Internal";
        case RYGDeveloperGateSurfacePrism: return @"Prism UI";
        case RYGDeveloperGateSurfaceLiquidGlass: return @"Liquid Glass";
    }
    return @"Developer";
}

static NSArray<NSDictionary<NSString *, NSString *> *> *RYGDeveloperDescriptors(RYGDeveloperGateSurface surface) {
    switch (surface) {
        case RYGDeveloperGateSurfaceWordMark:
            return @[
                @{@"selector": @"isIGWordmark1aEnabled", @"title": @"IG WordMark 1A"},
                @{@"selector": @"isIGWordmark1aAltEnabled", @"title": @"IG WordMark 1A Alt"},
                @{@"selector": @"isIGWordmark1bEnabled", @"title": @"IG WordMark 1B"},
                @{@"selector": @"isIGWordmark1bAltEnabled", @"title": @"IG WordMark 1B Alt"},
            ];
        case RYGDeveloperGateSurfaceInternal:
            return @[
                @{@"selector": @"isEmployee", @"title": @"Employee"},
                @{@"selector": @"isEmployeeBuild", @"title": @"Employee build"},
                @{@"selector": @"is_employee", @"title": @"Employee"},
                @{@"selector": @"is_employee_value_set", @"title": @"Employee value set"},
                @{@"selector": @"isIGInternal", @"title": @"IG internal"},
                @{@"selector": @"isInternal", @"title": @"Internal"},
                @{@"selector": @"isInternalBuild", @"title": @"Internal build"},
                @{@"selector": @"isInternalOnly", @"title": @"Internal only"},
                @{@"selector": @"is_internal_build", @"title": @"Internal build"},
                @{@"selector": @"is_internal_only", @"title": @"Internal only"},
                @{@"selector": @"is_internal_toggle_on", @"title": @"Internal toggle"},
                @{@"selector": @"is_dogfooding_option_enabled", @"title": @"Dogfooding option"},
                @{@"selector": @"shouldSendEmployeeTag", @"title": @"Send employee tag"},
                @{@"selector": @"shouldShowInternalBadge", @"title": @"Show internal badge"},
                @{@"selector": @"shouldShowIgOnlyUserDisclosureIn3dotMenu", @"title": @"IG-only disclosure · 3-dot menu"},
                @{@"selector": @"shouldShowIgOnlyUserDisclosureThroughCtaClick", @"title": @"IG-only disclosure · CTA"},
            ];
        case RYGDeveloperGateSurfacePrism:
            return @[
                @{@"selector": @"isPrismEnabled", @"title": @"Prism"},
                @{@"selector": @"isIGBPrismEnabled", @"title": @"IGB Prism"},
                @{@"selector": @"isPrismAlertDialogEnabled", @"title": @"Prism alert dialog"},
                @{@"selector": @"isPrismAllUserAssetsEnabled", @"title": @"Prism all-user assets"},
                @{@"selector": @"isPrismAvatarRingEnabled", @"title": @"Prism avatar ring"},
                @{@"selector": @"isPrismBottomSheetEnabled", @"title": @"Prism bottom sheet"},
                @{@"selector": @"isPrismButtonEnabled", @"title": @"Prism button"},
                @{@"selector": @"isPrismContextMenuEnabled", @"title": @"Prism context menu"},
                @{@"selector": @"isPrismControlsEnabled", @"title": @"Prism controls"},
                @{@"selector": @"isPrismCreationIconsEnabled", @"title": @"Prism creation icons"},
                @{@"selector": @"isPrismDefaultTooltipEnabled", @"title": @"Prism tooltip"},
                @{@"selector": @"isPrismDividersUpdateEnabled", @"title": @"Prism dividers"},
                @{@"selector": @"isPrismIndigoButtonEnabled", @"title": @"Prism indigo button"},
                @{@"selector": @"isPrismMediaButtonsEnabled", @"title": @"Prism media buttons"},
                @{@"selector": @"isPrismOverflowMenuEnabled", @"title": @"Prism overflow menu"},
                @{@"selector": @"isPrismSaveIconM4Enabled", @"title": @"Prism M4 save icon"},
                @{@"selector": @"isPrismToastsEnabled", @"title": @"Prism toasts"},
                @{@"selector": @"isRevertedPrismColorEnabled", @"title": @"Reverted Prism colors"},
                @{@"selector": @"shouldRenderPrismStyle", @"title": @"Render Prism style"},
                @{@"selector": @"usePrismColors", @"title": @"Use Prism colors"},
            ];
        case RYGDeveloperGateSurfaceLiquidGlass:
            return @[
                @{@"selector": @"isLiquidGlassEnabled", @"title": @"Liquid Glass"},
                @{@"selector": @"isLiquidGlassBlurEnabled", @"title": @"Liquid Glass blur"},
                @{@"selector": @"isLiquidGlassCGContextBlurEnabled", @"title": @"CGContext blur"},
                @{@"selector": @"isLiquidGlassEaseInOutBlurEnabled", @"title": @"Ease-in/out blur"},
                @{@"selector": @"isLiquidGlassIconBarButtonEnabled", @"title": @"Icon bar button"},
                @{@"selector": @"isLiquidGlassInAppNotificationEnabled", @"title": @"In-app notification"},
                @{@"selector": @"isLiquidGlassNavigationContentStylePinningEnabled", @"title": @"Navigation content pinning"},
                @{@"selector": @"isLiquidGlassToastEnabled", @"title": @"Liquid Glass toast"},
                @{@"selector": @"isLiquidGlassToastPeekEnabled", @"title": @"Toast peek"},
                @{@"selector": @"isLiquidGlassToggleEnabled", @"title": @"Liquid Glass toggle"},
                @{@"selector": @"isGlassBackgroundEnabled", @"title": @"Glass background"},
                @{@"selector": @"isGlassEnabled", @"title": @"Glass"},
                @{@"selector": @"isGlassRenderingOptimizationEnabled", @"title": @"Glass rendering optimization"},
                @{@"selector": @"isInlineComposerGlassEnabled", @"title": @"Inline composer glass"},
                @{@"selector": @"shouldMitigateLiquidGlassYOffset", @"title": @"Mitigate Y offset"},
                @{@"selector": @"shouldUseGlassEffect", @"title": @"Use Glass effect"},
                @{@"selector": @"useGlassEffect", @"title": @"Use Glass effect"},
                @{@"selector": @"isEnabled", @"class": @"IGLiquidGlassNavigationExperimentHelper", @"title": @"Navigation experiment"},
                @{@"selector": @"isHomeFeedHeaderEnabled", @"class": @"IGLiquidGlassNavigationExperimentHelper", @"title": @"Home feed header"},
                @{@"selector": @"isProfileSegmentedTabsGlassDisabled", @"class": @"IGLiquidGlassNavigationExperimentHelper", @"title": @"Profile segmented tabs glass disabled"},
                // Throwback is deliberately one gate inside Liquid Glass, not a
                // standalone Developer submenu.
                @{@"selector": @"isEnabled", @"class": @"IGThrowbackChromeExperimentHelper", @"title": @"Throwback chrome"},
            ];
    }
    return @[];
}

static NSDictionary<NSString *, NSString *> *RYGDeveloperDescriptorFor(NSString *selectorName,
                                                                        NSString *className,
                                                                        RYGDeveloperGateSurface surface) {
    for (NSDictionary<NSString *, NSString *> *descriptor in RYGDeveloperDescriptors(surface)) {
        if (![descriptor[@"selector"] isEqualToString:selectorName]) continue;
        NSString *classNeedle = descriptor[@"class"];
        if (classNeedle.length && [className rangeOfString:classNeedle options:NSCaseInsensitiveSearch].location == NSNotFound) continue;
        return descriptor;
    }
    return nil;
}

static const char *RYGDeveloperSkipQualifiers(const char *type) {
    while (type && strchr("rnNoORV", *type)) type++;
    return type;
}

static RYGRuntimeArgumentKind RYGDeveloperArgumentKind(Method method) {
    if (!method) return -1;
    unsigned int count = method_getNumberOfArguments(method);
    if (count == 2) return RYGRuntimeArgumentNone;
    if (count != 3) return -1;
    char encoded[32] = {0};
    method_getArgumentType(method, 2, encoded, sizeof(encoded));
    const char *arg = RYGDeveloperSkipQualifiers(encoded);
    if (!arg || !*arg) return -1;
    if (*arg == '@' || *arg == '#' || *arg == ':') return RYGRuntimeArgumentObject;
    if (strchr("BcCsSiIlLqQ^*", *arg)) return RYGRuntimeArgumentInteger;
    return -1;
}

static BOOL RYGDeveloperMethodIsSupportedBool(Method method) {
    if (!method) return NO;
    char encoded[16] = {0};
    method_getReturnType(method, encoded, sizeof(encoded));
    const char *ret = RYGDeveloperSkipQualifiers(encoded);
    return ret && *ret == 'B' && RYGDeveloperArgumentKind(method) >= 0;
}

static NSArray<NSString *> *RYGDeveloperPrimaryImages(void) {
    NSArray<NSString *> *images = [RYGRuntimeBrowserEngine runtimeImagePaths];
    NSString *main = NSBundle.mainBundle.executablePath.stringByStandardizingPath;
    NSMutableOrderedSet<NSString *> *selected = [NSMutableOrderedSet orderedSet];
    if (main.length && [images containsObject:main]) [selected addObject:main];
    for (NSString *path in images) {
        if ([path.lastPathComponent rangeOfString:@"FBSharedFramework" options:NSCaseInsensitiveSearch].location != NSNotFound) {
            [selected addObject:path];
            break;
        }
    }
    return selected.array;
}

static NSArray<RYGRuntimeBoolMethod *> *RYGDeveloperScanExactSurface(RYGDeveloperGateSurface surface) {
    NSMutableArray<RYGRuntimeBoolMethod *> *rows = [NSMutableArray array];
    for (NSString *imagePath in RYGDeveloperPrimaryImages()) {
        NSString *wanted = imagePath.stringByStandardizingPath;
        unsigned int classCount = 0;
        const char **classNames = objc_copyClassNamesForImage(wanted.fileSystemRepresentation, &classCount);
        if (!classNames) continue;

        for (unsigned int classIndex = 0; classIndex < classCount; classIndex++) {
            const char *rawClassName = classNames[classIndex];
            if (!rawClassName || !*rawClassName) continue;
            Class cls = objc_lookUpClass(rawClassName);
            if (!cls) continue;
            NSString *className = [NSString stringWithUTF8String:rawClassName];
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
                    if (!selector || !RYGDeveloperMethodIsSupportedBool(method)) continue;
                    NSString *selectorName = NSStringFromSelector(selector);
                    NSDictionary *descriptor = RYGDeveloperDescriptorFor(selectorName, className, surface);
                    if (!descriptor) continue;

                    RYGRuntimeBoolMethod *row = [RYGRuntimeBoolMethod new];
                    row.imagePath = wanted;
                    row.className = className;
                    row.selectorName = selectorName;
                    row.classMethod = classMethod;
                    row.argumentKind = RYGDeveloperArgumentKind(method);
                    const char *types = method_getTypeEncoding(method);
                    row.typeEncoding = types ? [NSString stringWithUTF8String:types] : @"";
                    [rows addObject:row];
                }
                if (methods) free(methods);
            }
        }
        free(classNames);
    }

    [rows sortUsingComparator:^NSComparisonResult(RYGRuntimeBoolMethod *left, RYGRuntimeBoolMethod *right) {
        NSDictionary *ld = RYGDeveloperDescriptorFor(left.selectorName, left.className, surface);
        NSDictionary *rd = RYGDeveloperDescriptorFor(right.selectorName, right.className, surface);
        NSString *lt = ld[@"title"] ?: left.selectorName;
        NSString *rt = rd[@"title"] ?: right.selectorName;
        NSComparisonResult titleOrder = [lt localizedCaseInsensitiveCompare:rt];
        if (titleOrder != NSOrderedSame) return titleOrder;
        NSComparisonResult classOrder = [left.className localizedCaseInsensitiveCompare:right.className];
        return classOrder == NSOrderedSame
            ? [left.selectorName localizedCaseInsensitiveCompare:right.selectorName]
            : classOrder;
    }];
    return rows.copy;
}

@implementation RYGDeveloperGateViewController

- (instancetype)initWithSurface:(RYGDeveloperGateSurface)surface {
    if ((self = [super initWithTitle:RYGDeveloperSurfaceTitle(surface)])) {
        _surface = surface;
        _gateRows = @[];
    }
    return self;
}

- (void)viewDidLoad {
    [super viewDidLoad];
    self.tableView.keyboardDismissMode = UIScrollViewKeyboardDismissModeOnDrag;
    self.navigationItem.rightBarButtonItem = [[UIBarButtonItem alloc]
        initWithImage:[[RYGSymbol symbolWithName:@"arrow_cw"] image]
                style:UIBarButtonItemStylePlain
               target:self
               action:@selector(refreshGates)];
    [NSNotificationCenter.defaultCenter addObserver:self
                                           selector:@selector(runtimeValueChanged:)
                                               name:RYGRuntimeNativeValueDidChangeNotification
                                             object:nil];
    [self rebuildSections];
    [self refreshGates];
}

- (void)dealloc {
    [NSNotificationCenter.defaultCenter removeObserver:self];
}

- (void)runtimeValueChanged:(NSNotification *)notification {
    NSString *key = notification.userInfo[RYGRuntimeNativeValueKeyUserInfoKey];
    if (!key.length) return;
    for (RYGRuntimeBoolMethod *row in self.gateRows) {
        if ([row.overrideKey isEqualToString:key]) {
            [self rebuildSections];
            return;
        }
    }
}

- (void)refreshGates {
    NSUInteger generation = ++self.scanGeneration;
    self.scanning = YES;
    [self rebuildSections];
    RYGDeveloperGateSurface surface = self.surface;
    dispatch_async(dispatch_get_global_queue(QOS_CLASS_USER_INITIATED, 0), ^{
        NSArray<RYGRuntimeBoolMethod *> *rows = RYGDeveloperScanExactSurface(surface);
        dispatch_async(dispatch_get_main_queue(), ^{
            if (generation != self.scanGeneration) return;
            self.gateRows = rows ?: @[];
            self.scanning = NO;
            [self rebuildSections];
        });
    });
}

- (RYGSetting *)wordmarkPreviewSetting {
    static NSArray<NSDictionary<NSString *, NSString *> *> *variants;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        variants = @[
            @{@"label": @"1A", @"asset": @"instagram-wordmark-1a"},
            @{@"label": @"1A Alt", @"asset": @"instagram-wordmark-1a-alt"},
            @{@"label": @"1B", @"asset": @"instagram-wordmark-1b"},
            @{@"label": @"1B Alt", @"asset": @"instagram-wordmark-1b-alt"},
        ];
    });

    return [RYGSetting customCellWithHeight:244.0 provider:^UITableViewCell *(UITableView *tableView, NSIndexPath *indexPath) {
        UITableViewCell *cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleDefault reuseIdentifier:nil];
        cell.selectionStyle = UITableViewCellSelectionStyleNone;
        cell.backgroundColor = UIColor.clearColor;

        UIVisualEffectView *glass = RYGLiquidGlassView(NO, NO, nil);
        glass.translatesAutoresizingMaskIntoConstraints = NO;
        glass.layer.cornerCurve = kCACornerCurveContinuous;
        glass.layer.cornerRadius = 22.0;
        glass.clipsToBounds = YES;
        [cell.contentView addSubview:glass];

        UIStackView *vertical = [[UIStackView alloc] init];
        vertical.translatesAutoresizingMaskIntoConstraints = NO;
        vertical.axis = UILayoutConstraintAxisVertical;
        vertical.spacing = 8.0;
        vertical.distribution = UIStackViewDistributionFillEqually;
        [glass.contentView addSubview:vertical];

        for (NSInteger rowIndex = 0; rowIndex < 2; rowIndex++) {
            UIStackView *horizontal = [[UIStackView alloc] init];
            horizontal.axis = UILayoutConstraintAxisHorizontal;
            horizontal.spacing = 8.0;
            horizontal.distribution = UIStackViewDistributionFillEqually;
            [vertical addArrangedSubview:horizontal];

            for (NSInteger column = 0; column < 2; column++) {
                NSDictionary *variant = variants[(NSUInteger)(rowIndex * 2 + column)];
                UIView *tile = [UIView new];
                tile.backgroundColor = [UIColor.secondarySystemFillColor colorWithAlphaComponent:0.22];
                tile.layer.cornerCurve = kCACornerCurveContinuous;
                tile.layer.cornerRadius = 15.0;

                UIImageView *imageView = [UIImageView new];
                imageView.translatesAutoresizingMaskIntoConstraints = NO;
                imageView.contentMode = UIViewContentModeScaleAspectFit;
                imageView.tintColor = UIColor.labelColor;
                UIImage *asset = [RYGIcon fbImageNamed:variant[@"asset"]];
                imageView.image = asset;
                [tile addSubview:imageView];

                UILabel *label = [UILabel new];
                label.translatesAutoresizingMaskIntoConstraints = NO;
                label.text = variant[@"label"];
                label.textAlignment = NSTextAlignmentCenter;
                label.font = [UIFont systemFontOfSize:12.0 weight:UIFontWeightSemibold];
                label.textColor = UIColor.secondaryLabelColor;
                [tile addSubview:label];

                if (!asset) {
                    UILabel *missing = [UILabel new];
                    missing.translatesAutoresizingMaskIntoConstraints = NO;
                    missing.text = @"asset unavailable";
                    missing.font = [UIFont systemFontOfSize:10.0];
                    missing.textColor = UIColor.tertiaryLabelColor;
                    missing.textAlignment = NSTextAlignmentCenter;
                    [tile addSubview:missing];
                    [NSLayoutConstraint activateConstraints:@[
                        [missing.centerXAnchor constraintEqualToAnchor:tile.centerXAnchor],
                        [missing.centerYAnchor constraintEqualToAnchor:tile.centerYAnchor constant:-5.0],
                    ]];
                }

                [NSLayoutConstraint activateConstraints:@[
                    [imageView.leadingAnchor constraintEqualToAnchor:tile.leadingAnchor constant:10.0],
                    [imageView.trailingAnchor constraintEqualToAnchor:tile.trailingAnchor constant:-10.0],
                    [imageView.topAnchor constraintEqualToAnchor:tile.topAnchor constant:10.0],
                    [imageView.bottomAnchor constraintEqualToAnchor:label.topAnchor constant:-5.0],
                    [label.leadingAnchor constraintEqualToAnchor:tile.leadingAnchor constant:6.0],
                    [label.trailingAnchor constraintEqualToAnchor:tile.trailingAnchor constant:-6.0],
                    [label.bottomAnchor constraintEqualToAnchor:tile.bottomAnchor constant:-7.0],
                    [label.heightAnchor constraintEqualToConstant:17.0],
                ]];
                [horizontal addArrangedSubview:tile];
            }
        }

        [NSLayoutConstraint activateConstraints:@[
            [glass.leadingAnchor constraintEqualToAnchor:cell.contentView.leadingAnchor constant:8.0],
            [glass.trailingAnchor constraintEqualToAnchor:cell.contentView.trailingAnchor constant:-8.0],
            [glass.topAnchor constraintEqualToAnchor:cell.contentView.topAnchor constant:6.0],
            [glass.bottomAnchor constraintEqualToAnchor:cell.contentView.bottomAnchor constant:-6.0],
            [vertical.leadingAnchor constraintEqualToAnchor:glass.contentView.leadingAnchor constant:10.0],
            [vertical.trailingAnchor constraintEqualToAnchor:glass.contentView.trailingAnchor constant:-10.0],
            [vertical.topAnchor constraintEqualToAnchor:glass.contentView.topAnchor constant:10.0],
            [vertical.bottomAnchor constraintEqualToAnchor:glass.contentView.bottomAnchor constant:-10.0],
        ]];
        return cell;
    }];
}

- (RYGSetting *)settingForGate:(RYGRuntimeBoolMethod *)row {
    NSDictionary *descriptor = RYGDeveloperDescriptorFor(row.selectorName, row.className, self.surface);
    NSString *title = descriptor[@"title"] ?: row.selectorName;
    NSNumber *native = row.liveValue;
    NSNumber *forced = row.overrideValue;
    NSString *nativeText = native ? (native.boolValue ? @"true" : @"false") : @"not observed";
    NSString *outputText = forced ? (forced.boolValue ? @"forced true" : @"forced false") : @"native";
    NSString *subtitle = [NSString stringWithFormat:@"%@ · %@\noriginal %@ · output %@",
                          row.className, row.imagePath.lastPathComponent, nativeText, outputText];
    RYGSymbol *icon = forced
        ? [RYGSymbol symbolWithName:(forced.boolValue ? @"circle_check_filled" : @"xmark")]
        : [RYGSymbol symbolWithName:@"interface" color:UIColor.secondaryLabelColor];
    __weak typeof(self) weakSelf = self;
    return [RYGSetting buttonCellWithTitle:title subtitle:subtitle icon:icon action:^{
        [weakSelf presentActionsForGate:row displayTitle:title];
    }];
}

- (void)rebuildSections {
    NSMutableArray<NSDictionary *> *sections = [NSMutableArray array];
    if (self.surface == RYGDeveloperGateSurfaceWordMark) {
        [sections addObject:[RYGSettingsViewController sectionWithHeader:@"WordMark assets"
                                                                  footer:@"The four previews are loaded directly from FBSharedFramework's current asset catalog."
                                                                    rows:@[[self wordmarkPreviewSetting]]]];
    }

    if (self.scanning) {
        RYGSetting *status = [RYGSetting staticCellWithTitle:@"Scanning loaded Instagram images…"
                                                   subtitle:@"Exact selectors only; no MobileConfig lookup and no hook is installed while this page opens."
                                                       icon:[RYGSymbol symbolWithName:@"search"]];
        [sections addObject:[RYGSettingsViewController sectionWithHeader:@"Live BOOL gates" footer:nil rows:@[status]]];
    } else {
        NSMutableArray<RYGSetting *> *rows = [NSMutableArray arrayWithCapacity:self.gateRows.count];
        for (RYGRuntimeBoolMethod *gate in self.gateRows) [rows addObject:[self settingForGate:gate]];
        if (!rows.count) {
            [rows addObject:[RYGSetting staticCellWithTitle:@"No matching live gate loaded"
                                                   subtitle:@"This page only lists exact selectors verified for this surface; it does not invent a MobileConfig fallback."
                                                       icon:[RYGSymbol symbolWithName:@"info"]]];
        }
        NSString *footer = [NSString stringWithFormat:@"%lu live match%@ in the Instagram executable / FBSharedFramework. Tap a gate to observe its original value or explicitly override it.",
                            (unsigned long)self.gateRows.count, self.gateRows.count == 1 ? @"" : @"es"];
        [sections addObject:[RYGSettingsViewController sectionWithHeader:@"Live BOOL gates" footer:footer rows:rows]];
    }
    [self applySettingSections:sections];
}

- (void)presentActionsForGate:(RYGRuntimeBoolMethod *)row displayTitle:(NSString *)displayTitle {
    NSNumber *native = row.liveValue;
    NSNumber *forced = row.overrideValue;
    NSString *message = [NSString stringWithFormat:@"%@\n%@\nselector %@\nOriginal: %@\nOutput: %@",
                         row.className,
                         row.imagePath.lastPathComponent,
                         row.selectorName,
                         native ? (native.boolValue ? @"true" : @"false") : @"not observed yet",
                         forced ? (forced.boolValue ? @"forced true" : @"forced false") : @"native"];
    UIAlertController *sheet = [UIAlertController alertControllerWithTitle:displayTitle
                                                                    message:message
                                                             preferredStyle:UIAlertControllerStyleActionSheet];
    __weak typeof(self) weakSelf = self;
    [sheet addAction:[UIAlertAction actionWithTitle:@"Observe original live value" style:UIAlertActionStyleDefault handler:^(__unused UIAlertAction *action) {
        RYGRuntimeBeginLiveObservation(@[row]);
        [RYGUtils showToastForDuration:1.4 title:@"Observing" subtitle:@"Waiting for Instagram to call this gate"];
    }]];
    [sheet addAction:[UIAlertAction actionWithTitle:@"Force true" style:UIAlertActionStyleDefault handler:^(__unused UIAlertAction *action) {
        [RYGRuntimeBrowserEngine setOverride:@YES forMethod:row];
        [weakSelf rebuildSections];
    }]];
    [sheet addAction:[UIAlertAction actionWithTitle:@"Force false" style:UIAlertActionStyleDefault handler:^(__unused UIAlertAction *action) {
        [RYGRuntimeBrowserEngine setOverride:@NO forMethod:row];
        [weakSelf rebuildSections];
    }]];
    if (forced) {
        [sheet addAction:[UIAlertAction actionWithTitle:@"Use native value" style:UIAlertActionStyleDestructive handler:^(__unused UIAlertAction *action) {
            [RYGRuntimeBrowserEngine setOverride:nil forMethod:row];
            [weakSelf rebuildSections];
        }]];
    }
    [sheet addAction:[UIAlertAction actionWithTitle:@"Copy method details" style:UIAlertActionStyleDefault handler:^(__unused UIAlertAction *action) {
        UIPasteboard.generalPasteboard.string = [NSString stringWithFormat:@"%@[%@ %@] %@",
                                                 row.classMethod ? @"+" : @"-", row.className, row.selectorName, row.typeEncoding];
    }]];
    [sheet addAction:[UIAlertAction actionWithTitle:@"Cancel" style:UIAlertActionStyleCancel handler:nil]];

    if (UIDevice.currentDevice.userInterfaceIdiom == UIUserInterfaceIdiomPad) {
        sheet.popoverPresentationController.sourceView = self.view;
        sheet.popoverPresentationController.sourceRect = CGRectMake(CGRectGetMidX(self.view.bounds), 90.0, 1.0, 1.0);
    }
    [self presentViewController:sheet animated:YES completion:nil];
}

@end
