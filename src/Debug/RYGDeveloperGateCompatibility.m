#import "RYGDeveloperGateViewController.h"
#import "RYGRuntimeBrowserEngine.h"
#import <objc/runtime.h>
#import <objc/message.h>
#include <string.h>

static const char *RYGGateSkipQualifiers(const char *type) {
    while (type && strchr("rnNoORV", *type)) type++;
    return type;
}

static RYGRuntimeArgumentKind RYGGateArgumentKind(Method method) {
    if (!method) return -1;
    unsigned int count = method_getNumberOfArguments(method);
    if (count == 2) return RYGRuntimeArgumentNone;
    if (count != 3) return -1;
    char encoded[32] = {0};
    method_getArgumentType(method, 2, encoded, sizeof(encoded));
    const char *arg = RYGGateSkipQualifiers(encoded);
    if (!arg || !*arg) return -1;
    if (*arg == '@' || *arg == '#' || *arg == ':') return RYGRuntimeArgumentObject;
    if (strchr("BcCsSiIlLqQ^*", *arg)) return RYGRuntimeArgumentInteger;
    return -1;
}

static BOOL RYGGateSupportedBool(Method method) {
    if (!method) return NO;
    char encoded[16] = {0};
    method_getReturnType(method, encoded, sizeof(encoded));
    const char *ret = RYGGateSkipQualifiers(encoded);
    return ret && (*ret == 'B' || *ret == 'c' || *ret == 'C') && RYGGateArgumentKind(method) >= 0;
}

static NSArray<NSDictionary<NSString *, NSString *> *> *RYGCompatDescriptors(RYGDeveloperGateSurface surface) {
    switch (surface) {
        case RYGDeveloperGateSurfaceWordMark:
            return @[
                @{@"selector":@"isIGWordmark1aEnabled"},
                @{@"selector":@"isIGWordmark1aAltEnabled"},
                @{@"selector":@"isIGWordmark1bEnabled"},
                @{@"selector":@"isIGWordmark1bAltEnabled"},
            ];
        case RYGDeveloperGateSurfaceInternal:
            return @[
                @{@"selector":@"isEmployee"}, @{@"selector":@"isEmployeeBuild"},
                @{@"selector":@"is_employee"}, @{@"selector":@"is_employee_value_set"},
                @{@"selector":@"isIGInternal"}, @{@"selector":@"isInternal"},
                @{@"selector":@"isInternalBuild"}, @{@"selector":@"isInternalOnly"},
                @{@"selector":@"is_internal_build"}, @{@"selector":@"is_internal_only"},
                @{@"selector":@"is_internal_toggle_on"}, @{@"selector":@"is_dogfooding_option_enabled"},
                @{@"selector":@"shouldSendEmployeeTag"}, @{@"selector":@"shouldShowInternalBadge"},
                @{@"selector":@"shouldShowIgOnlyUserDisclosureIn3dotMenu"},
                @{@"selector":@"shouldShowIgOnlyUserDisclosureThroughCtaClick"},
            ];
        case RYGDeveloperGateSurfacePrism:
            return @[
                @{@"selector":@"isPrismEnabled"}, @{@"selector":@"isIGBPrismEnabled"},
                @{@"selector":@"isPrismAlertDialogEnabled"}, @{@"selector":@"isPrismAllUserAssetsEnabled"},
                @{@"selector":@"isPrismAvatarRingEnabled"}, @{@"selector":@"isPrismBottomSheetEnabled"},
                @{@"selector":@"isPrismButtonEnabled"}, @{@"selector":@"isPrismContextMenuEnabled"},
                @{@"selector":@"isPrismControlsEnabled"}, @{@"selector":@"isPrismCreationIconsEnabled"},
                @{@"selector":@"isPrismDefaultTooltipEnabled"}, @{@"selector":@"isPrismDividersUpdateEnabled"},
                @{@"selector":@"isPrismIndigoButtonEnabled"}, @{@"selector":@"isPrismMediaButtonsEnabled"},
                @{@"selector":@"isPrismOverflowMenuEnabled"}, @{@"selector":@"isPrismSaveIconM4Enabled"},
                @{@"selector":@"isPrismToastsEnabled"}, @{@"selector":@"isRevertedPrismColorEnabled"},
                @{@"selector":@"shouldRenderPrismStyle"}, @{@"selector":@"usePrismColors"},
            ];
        case RYGDeveloperGateSurfaceLiquidGlass:
            return @[
                @{@"selector":@"isLiquidGlassEnabled"}, @{@"selector":@"isLiquidGlassBlurEnabled"},
                @{@"selector":@"isLiquidGlassCGContextBlurEnabled"}, @{@"selector":@"isLiquidGlassEaseInOutBlurEnabled"},
                @{@"selector":@"isLiquidGlassIconBarButtonEnabled"}, @{@"selector":@"isLiquidGlassInAppNotificationEnabled"},
                @{@"selector":@"isLiquidGlassNavigationContentStylePinningEnabled"}, @{@"selector":@"isLiquidGlassToastEnabled"},
                @{@"selector":@"isLiquidGlassToastPeekEnabled"}, @{@"selector":@"isLiquidGlassToggleEnabled"},
                @{@"selector":@"isGlassBackgroundEnabled"}, @{@"selector":@"isGlassEnabled"},
                @{@"selector":@"isGlassRenderingOptimizationEnabled"}, @{@"selector":@"isInlineComposerGlassEnabled"},
                @{@"selector":@"shouldMitigateLiquidGlassYOffset"}, @{@"selector":@"shouldUseGlassEffect"},
                @{@"selector":@"useGlassEffect"},
                @{@"selector":@"isEnabled", @"class":@"IGLiquidGlassNavigationExperimentHelper"},
                @{@"selector":@"isHomeFeedHeaderEnabled", @"class":@"IGLiquidGlassNavigationExperimentHelper"},
                @{@"selector":@"isProfileSegmentedTabsGlassDisabled", @"class":@"IGLiquidGlassNavigationExperimentHelper"},
                @{@"selector":@"isEnabled", @"class":@"IGThrowbackChromeExperimentHelper"},
            ];
    }
    return @[];
}

static BOOL RYGCompatGateMatches(NSString *selector, NSString *className, RYGDeveloperGateSurface surface) {
    for (NSDictionary *descriptor in RYGCompatDescriptors(surface)) {
        if (![descriptor[@"selector"] isEqualToString:selector]) continue;
        NSString *classNeedle = descriptor[@"class"];
        if (classNeedle.length && [className rangeOfString:classNeedle options:NSCaseInsensitiveSearch].location == NSNotFound) continue;
        return YES;
    }
    return NO;
}

static NSArray<NSString *> *RYGCompatPrimaryImages(void) {
    NSString *main = NSBundle.mainBundle.executablePath.stringByStandardizingPath;
    NSMutableOrderedSet<NSString *> *selected = [NSMutableOrderedSet orderedSet];
    for (NSString *path in [RYGRuntimeBrowserEngine runtimeImagePaths]) {
        NSString *standard = path.stringByStandardizingPath;
        if ([standard isEqualToString:main] ||
            [standard.lastPathComponent rangeOfString:@"FBSharedFramework" options:NSCaseInsensitiveSearch].location != NSNotFound) {
            [selected addObject:standard];
        }
    }
    return selected.array;
}

static NSArray<RYGRuntimeBoolMethod *> *RYGCompatScanSurface(RYGDeveloperGateSurface surface) {
    NSMutableArray<RYGRuntimeBoolMethod *> *rows = [NSMutableArray array];
    for (NSString *imagePath in RYGCompatPrimaryImages()) {
        unsigned int count = 0;
        const char **classNames = objc_copyClassNamesForImage(imagePath.fileSystemRepresentation, &count);
        if (!classNames) continue;
        for (unsigned int index = 0; index < count; index++) {
            const char *raw = classNames[index];
            if (!raw || !*raw) continue;
            Class cls = objc_lookUpClass(raw);
            if (!cls) continue;
            NSString *className = [NSString stringWithUTF8String:raw];
            if (!className.length) continue;
            for (NSInteger pass = 0; pass < 2; pass++) {
                BOOL classMethod = pass == 1;
                Class owner = classMethod ? object_getClass(cls) : cls;
                unsigned int methodCount = 0;
                Method *methods = owner ? class_copyMethodList(owner, &methodCount) : NULL;
                for (unsigned int methodIndex = 0; methodIndex < methodCount; methodIndex++) {
                    Method method = methods[methodIndex];
                    if (!RYGGateSupportedBool(method)) continue;
                    SEL sel = method_getName(method);
                    NSString *selector = sel ? NSStringFromSelector(sel) : nil;
                    if (!selector.length || !RYGCompatGateMatches(selector, className, surface)) continue;
                    RYGRuntimeBoolMethod *row = [RYGRuntimeBoolMethod new];
                    row.imagePath = imagePath;
                    row.className = className;
                    row.selectorName = selector;
                    row.classMethod = classMethod;
                    row.argumentKind = RYGGateArgumentKind(method);
                    row.typeEncoding = [NSString stringWithUTF8String:method_getTypeEncoding(method) ?: ""];
                    [rows addObject:row];
                }
                if (methods) free(methods);
            }
        }
        free(classNames);
    }
    [rows sortUsingComparator:^NSComparisonResult(RYGRuntimeBoolMethod *a, RYGRuntimeBoolMethod *b) {
        NSComparisonResult classOrder = [a.className localizedCaseInsensitiveCompare:b.className];
        return classOrder == NSOrderedSame ? [a.selectorName localizedCaseInsensitiveCompare:b.selectorName] : classOrder;
    }];
    return rows.copy;
}

@implementation RYGDeveloperGateViewController (RYGCurrentABIFix)

- (void)ryg_currentABI_refreshGates {
    NSNumber *generationValue = objc_getAssociatedObject(self, @selector(ryg_currentABI_refreshGates));
    NSUInteger generation = generationValue.unsignedIntegerValue + 1;
    objc_setAssociatedObject(self, @selector(ryg_currentABI_refreshGates), @(generation), OBJC_ASSOCIATION_RETAIN_NONATOMIC);

    RYGDeveloperGateSurface surface = [[self valueForKey:@"surface"] integerValue];
    [self setValue:@YES forKey:@"scanning"];
    ((void (*)(id, SEL))objc_msgSend)(self, NSSelectorFromString(@"rebuildSections"));

    dispatch_async(dispatch_get_global_queue(QOS_CLASS_USER_INITIATED, 0), ^{
        NSArray *rows = RYGCompatScanSurface(surface);
        dispatch_async(dispatch_get_main_queue(), ^{
            NSNumber *latest = objc_getAssociatedObject(self, @selector(ryg_currentABI_refreshGates));
            if (latest.unsignedIntegerValue != generation) return;
            [self setValue:rows ?: @[] forKey:@"gateRows"];
            [self setValue:@NO forKey:@"scanning"];
            ((void (*)(id, SEL))objc_msgSend)(self, NSSelectorFromString(@"rebuildSections"));
        });
    });
}

@end

__attribute__((constructor(120))) static void RYGInstallDeveloperGateCurrentABIFix(void) {
    Class cls = RYGDeveloperGateViewController.class;
    Method original = class_getInstanceMethod(cls, NSSelectorFromString(@"refreshGates"));
    Method replacement = class_getInstanceMethod(cls, @selector(ryg_currentABI_refreshGates));
    if (original && replacement) method_exchangeImplementations(original, replacement);
}
