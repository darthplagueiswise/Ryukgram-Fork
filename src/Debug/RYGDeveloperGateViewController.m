#import "RYGDeveloperGateViewController.h"
#import "RYGRuntimeBrowserEngine.h"
#import "../Settings/RYGSetting.h"
#import "../Settings/RYGSymbol.h"
#import "../UI/RYGLiquidGlass.h"
#import <objc/runtime.h>
#include <string.h>

@interface RYGDeveloperGateViewController ()
@property (nonatomic, assign) RYGDeveloperGateSurface surface;
@property (nonatomic, copy) NSArray<RYGRuntimeBoolMethod *> *gateRows;
@property (nonatomic, assign) NSUInteger scanGeneration;
@end

static NSString *RYGDeveloperSurfaceTitle(RYGDeveloperGateSurface surface) {
    switch (surface) {
        case RYGDeveloperGateSurfaceWordMark: return @"IGWordMark";
        case RYGDeveloperGateSurfaceInternal: return @"IG-only / Internal-only";
        case RYGDeveloperGateSurfacePrism: return @"Prism UI";
        case RYGDeveloperGateSurfaceLiquidGlass: return @"Liquid Glass";
    }
    return @"Developer";
}

static const char *RYGDeveloperSkipQualifiers(const char *type) {
    while (type && strchr("rnNoORV", *type)) type++;
    return type;
}

static RYGRuntimeArgumentKind RYGDeveloperArgumentKind(Method method) {
    if (!method) return (RYGRuntimeArgumentKind)-1;
    unsigned int count = method_getNumberOfArguments(method);
    if (count == 2) return RYGRuntimeArgumentNone;
    if (count != 3) return (RYGRuntimeArgumentKind)-1;

    char encoded[64] = {0};
    method_getArgumentType(method, 2, encoded, sizeof(encoded));
    const char *argument = RYGDeveloperSkipQualifiers(encoded);
    if (!argument || !*argument) return (RYGRuntimeArgumentKind)-1;
    if (*argument == '@' || *argument == '#' || *argument == ':') return RYGRuntimeArgumentObject;
    if (strchr("BcCsSiIlLqQ", *argument)) return RYGRuntimeArgumentInteger;
    return (RYGRuntimeArgumentKind)-1;
}

static BOOL RYGDeveloperSupportedBOOL(Method method) {
    if (!method) return NO;
    char encoded[32] = {0};
    method_getReturnType(method, encoded, sizeof(encoded));
    const char *result = RYGDeveloperSkipQualifiers(encoded);
    RYGRuntimeArgumentKind argument = RYGDeveloperArgumentKind(method);
    return result && *result == 'B'
        && argument >= RYGRuntimeArgumentNone
        && argument <= RYGRuntimeArgumentInteger;
}

static BOOL RYGDeveloperContains(NSString *value, NSString *needle) {
    return value.length && needle.length &&
        [value rangeOfString:needle options:NSCaseInsensitiveSearch].location != NSNotFound;
}

static BOOL RYGDeveloperMethodBelongsToSurface(RYGDeveloperGateSurface surface,
                                                NSString *className,
                                                NSString *selectorName) {
    if (surface == RYGDeveloperGateSurfaceWordMark) {
        static NSSet<NSString *> *selectors;
        static dispatch_once_t once;
        dispatch_once(&once, ^{
            selectors = [NSSet setWithArray:@[
                @"isIGWordmark1aEnabled",
                @"isIGWordmark1aAltEnabled",
                @"isIGWordmark1bEnabled",
                @"isIGWordmark1bAltEnabled",
            ]];
        });
        return [selectors containsObject:selectorName];
    }

    if (surface == RYGDeveloperGateSurfacePrism) {
        return RYGDeveloperContains(className, @"Prism") || RYGDeveloperContains(selectorName, @"Prism");
    }

    if (surface == RYGDeveloperGateSurfaceLiquidGlass) {
        return RYGDeveloperContains(className, @"LiquidGlass")
            || RYGDeveloperContains(selectorName, @"LiquidGlass")
            || RYGDeveloperContains(className, @"ThrowbackChrome")
            || [selectorName hasPrefix:@"isGlass"]
            || [selectorName hasPrefix:@"useGlass"]
            || [selectorName hasPrefix:@"shouldUseGlass"];
    }

    return RYGDeveloperContains(className, @"Internal")
        || RYGDeveloperContains(selectorName, @"InternalOnly")
        || RYGDeveloperContains(selectorName, @"InternalBuild")
        || RYGDeveloperContains(selectorName, @"IGInternal")
        || RYGDeveloperContains(selectorName, @"IGOnly")
        || RYGDeveloperContains(selectorName, @"ig_only")
        || RYGDeveloperContains(selectorName, @"internal_only")
        || RYGDeveloperContains(selectorName, @"dogfooding_option");
}

static NSArray<NSString *> *RYGDeveloperPrimaryImages(void) {
    NSArray<NSString *> *images = RYGRuntimeBrowserEngine.runtimeImagePaths;
    NSString *main = NSBundle.mainBundle.executablePath;
    NSMutableOrderedSet<NSString *> *selected = [NSMutableOrderedSet orderedSet];
    if (main.length) {
        for (NSString *path in images) {
            if ([path isEqualToString:main] ||
                [path.stringByResolvingSymlinksInPath isEqualToString:main.stringByResolvingSymlinksInPath]) {
                [selected addObject:path];
                break;
            }
        }
    }
    for (NSString *path in images) {
        if (RYGDeveloperContains(path.lastPathComponent, @"FBShared")) [selected addObject:path];
    }
    return selected.array;
}

static const char **RYGDeveloperCopyClassNamesForImage(NSString *imagePath, unsigned int *count) {
    if (count) *count = 0;
    if (!imagePath.length) return NULL;
    const char **names = objc_copyClassNamesForImage(imagePath.fileSystemRepresentation, count);
    if (names) return names;
    NSString *resolved = imagePath.stringByResolvingSymlinksInPath;
    if (![resolved isEqualToString:imagePath]) return objc_copyClassNamesForImage(resolved.fileSystemRepresentation, count);
    return NULL;
}

static NSArray<RYGRuntimeBoolMethod *> *RYGDeveloperScanSurface(RYGDeveloperGateSurface surface) {
    NSMutableArray<RYGRuntimeBoolMethod *> *rows = [NSMutableArray array];
    NSMutableSet<NSString *> *dedupe = [NSMutableSet set];

    for (NSString *imagePath in RYGDeveloperPrimaryImages()) {
        unsigned int classCount = 0;
        const char **classNames = RYGDeveloperCopyClassNamesForImage(imagePath, &classCount);
        if (!classNames) continue;

        for (unsigned int classIndex = 0; classIndex < classCount; classIndex++) {
            const char *rawClassName = classNames[classIndex];
            if (!rawClassName || !*rawClassName) continue;
            Class cls = objc_lookUpClass(rawClassName);
            if (!cls) continue;
            NSString *className = [NSString stringWithUTF8String:rawClassName];

            for (NSUInteger pass = 0; pass < 2; pass++) {
                BOOL classMethod = pass == 1;
                Class owner = classMethod ? object_getClass(cls) : cls;
                unsigned int methodCount = 0;
                Method *methods = owner ? class_copyMethodList(owner, &methodCount) : NULL;
                for (unsigned int methodIndex = 0; methodIndex < methodCount; methodIndex++) {
                    Method method = methods[methodIndex];
                    if (!RYGDeveloperSupportedBOOL(method)) continue;
                    SEL selector = method_getName(method);
                    if (!selector) continue;
                    NSString *selectorName = NSStringFromSelector(selector);
                    if (!RYGDeveloperMethodBelongsToSurface(surface, className, selectorName)) continue;

                    RYGRuntimeBoolMethod *row = [RYGRuntimeBoolMethod new];
                    row.imagePath = imagePath;
                    row.className = className ?: @"";
                    row.selectorName = selectorName ?: @"";
                    row.classMethod = classMethod;
                    row.argumentKind = RYGDeveloperArgumentKind(method);
                    const char *types = method_getTypeEncoding(method);
                    row.typeEncoding = types ? [NSString stringWithUTF8String:types] : @"";
                    if (!row.overrideKey.length || [dedupe containsObject:row.overrideKey]) continue;
                    [dedupe addObject:row.overrideKey];
                    [rows addObject:row];
                }
                if (methods) free(methods);
            }
        }
        free(classNames);
    }

    [rows sortUsingComparator:^NSComparisonResult(RYGRuntimeBoolMethod *left, RYGRuntimeBoolMethod *right) {
        NSComparisonResult selector = [left.selectorName localizedCaseInsensitiveCompare:right.selectorName];
        if (selector != NSOrderedSame) return selector;
        return [left.className localizedCaseInsensitiveCompare:right.className];
    }];
    return rows.copy;
}

static NSString *RYGDeveloperPrettySelector(NSString *selector) {
    if (!selector.length) return @"Gate";
    NSMutableString *result = [NSMutableString string];
    for (NSUInteger index = 0; index < selector.length; index++) {
        unichar character = [selector characterAtIndex:index];
        if (character == ':' || character == '_') {
            if (result.length && ![[result substringFromIndex:result.length - 1] isEqualToString:@" "]) [result appendString:@" "];
            continue;
        }
        if (index > 0 && [[NSCharacterSet uppercaseLetterCharacterSet] characterIsMember:character]) [result appendString:@" "];
        [result appendFormat:@"%C", character];
    }
    return [result stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceCharacterSet];
}

static NSString *RYGWordMarkTitleForSelector(NSString *selector) {
    if ([selector isEqualToString:@"isIGWordmark1aEnabled"]) return @"Instagram WordMark 1A";
    if ([selector isEqualToString:@"isIGWordmark1aAltEnabled"]) return @"Instagram WordMark 1A Alt";
    if ([selector isEqualToString:@"isIGWordmark1bEnabled"]) return @"Instagram WordMark 1B";
    if ([selector isEqualToString:@"isIGWordmark1bAltEnabled"]) return @"Instagram WordMark 1B Alt";
    return selector;
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
    [self rebuildSections];
    [self refreshGates];
    RYGLiquidGlassApplyToViewController(self);
}

- (void)refreshGates {
    NSUInteger generation = ++self.scanGeneration;
    RYGDeveloperGateSurface surface = self.surface;
    __weak typeof(self) weakSelf = self;
    dispatch_async(dispatch_get_global_queue(QOS_CLASS_USER_INITIATED, 0), ^{
        NSArray<RYGRuntimeBoolMethod *> *rows = RYGDeveloperScanSurface(surface);
        dispatch_async(dispatch_get_main_queue(), ^{
            __strong typeof(weakSelf) self = weakSelf;
            if (!self || generation != self.scanGeneration) return;
            self.gateRows = rows;
            [self rebuildSections];
        });
    });
}

- (void)resetAllToNative {
    for (RYGRuntimeBoolMethod *method in self.gateRows) [RYGRuntimeBrowserEngine setOverride:nil forMethod:method];
    [self rebuildSections];
}

- (void)selectWordMarkSelector:(NSString *)selector {
    for (RYGRuntimeBoolMethod *method in self.gateRows) {
        [RYGRuntimeBrowserEngine setOverride:@([method.selectorName isEqualToString:selector]) forMethod:method];
    }
    [self rebuildSections];
}

- (RYGSetting *)settingForGate:(RYGRuntimeBoolMethod *)method {
    __weak typeof(self) weakSelf = self;
    NSString *title = RYGDeveloperPrettySelector(method.selectorName);
    return [RYGSetting switchCellWithTitle:title
                                  subtitle:nil
                                     value:^BOOL{
        NSNumber *forced = method.overrideValue;
        if (forced) return forced.boolValue;
        NSNumber *live = method.liveValue;
        return live ? live.boolValue : NO;
    } action:^(BOOL on) {
        [RYGRuntimeBrowserEngine setOverride:@(on) forMethod:method];
        [weakSelf rebuildSections];
    }];
}

- (void)rebuildSections {
    NSMutableArray *sections = [NSMutableArray array];
    __weak typeof(self) weakSelf = self;

    if (self.surface == RYGDeveloperGateSurfaceWordMark) {
        NSArray<NSString *> *selectors = @[
            @"isIGWordmark1aEnabled", @"isIGWordmark1aAltEnabled",
            @"isIGWordmark1bEnabled", @"isIGWordmark1bAltEnabled"
        ];
        NSMutableArray<RYGSetting *> *rows = [NSMutableArray array];
        for (NSString *selector in selectors) {
            BOOL found = NO;
            BOOL selected = NO;
            for (RYGRuntimeBoolMethod *method in self.gateRows) {
                if (![method.selectorName isEqualToString:selector]) continue;
                found = YES;
                if (method.overrideValue.boolValue) selected = YES;
            }
            if (!found) continue;
            RYGSetting *row = [RYGSetting buttonCellWithTitle:RYGWordMarkTitleForSelector(selector)
                                                     subtitle:nil
                                                         icon:[RYGSymbol symbolWithName:selected ? @"circle_check_filled" : @"circle"]
                                                       action:^{ [weakSelf selectWordMarkSelector:selector]; }];
            [rows addObject:row];
        }
        if (!rows.count) [rows addObject:[RYGSetting staticCellWithTitle:@"No WordMark gate loaded" subtitle:nil icon:nil]];
        [sections addObject:[RYGSettingsViewController sectionWithHeader:nil footer:nil rows:rows]];
    } else {
        NSMutableArray<RYGSetting *> *rows = [NSMutableArray arrayWithCapacity:self.gateRows.count];
        for (RYGRuntimeBoolMethod *method in self.gateRows) [rows addObject:[self settingForGate:method]];
        if (!rows.count) [rows addObject:[RYGSetting staticCellWithTitle:@"No live option loaded" subtitle:nil icon:nil]];
        [sections addObject:[RYGSettingsViewController sectionWithHeader:nil footer:nil rows:rows]];
    }

    if (self.gateRows.count) {
        RYGSetting *reset = [RYGSetting actionCellWithTitle:@"Use Native Values" color:UIColor.systemRedColor action:^{ [weakSelf resetAllToNative]; }];
        [sections addObject:[RYGSettingsViewController sectionWithHeader:nil footer:nil rows:@[reset]]];
    }
    [self applySettingSections:sections];
}

@end
