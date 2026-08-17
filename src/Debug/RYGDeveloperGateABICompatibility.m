#import "RYGDeveloperGateViewController.h"
#import "RYGRuntimeBrowserEngine.h"
#import <Foundation/Foundation.h>
#import <objc/runtime.h>

static const void *kRYGDeveloperGateScanGenerationKey = &kRYGDeveloperGateScanGenerationKey;

static NSArray<NSDictionary<NSString *, NSString *> *> *RYGCompatGateDescriptors(RYGDeveloperGateSurface surface) {
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

static BOOL RYGCompatGateMatches(RYGRuntimeBoolMethod *row, RYGDeveloperGateSurface surface) {
    if (!row.selectorName.length) return NO;
    for (NSDictionary<NSString *, NSString *> *descriptor in RYGCompatGateDescriptors(surface)) {
        if (![descriptor[@"selector"] isEqualToString:row.selectorName]) continue;
        NSString *needle = descriptor[@"class"];
        if (needle.length && [row.className rangeOfString:needle options:NSCaseInsensitiveSearch].location == NSNotFound) continue;
        return YES;
    }
    return NO;
}

static NSArray<NSString *> *RYGCompatDeveloperImages(void) {
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

@implementation RYGDeveloperGateViewController (RYGABICompatibility)

- (void)ryg_abi_refreshGates {
    NSInteger surfaceValue = 0;
    @try { surfaceValue = [[self valueForKey:@"surface"] integerValue]; } @catch (__unused id exception) {}
    RYGDeveloperGateSurface surface = (RYGDeveloperGateSurface)surfaceValue;
    NSUInteger generation = [objc_getAssociatedObject(self, kRYGDeveloperGateScanGenerationKey) unsignedIntegerValue] + 1;
    objc_setAssociatedObject(self, kRYGDeveloperGateScanGenerationKey, @(generation), OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    @try { [self setValue:@YES forKey:@"scanning"]; } @catch (__unused id exception) {}
    [self rebuildSections];

    dispatch_async(dispatch_get_global_queue(QOS_CLASS_USER_INITIATED, 0), ^{
        NSMutableArray<RYGRuntimeBoolMethod *> *matches = [NSMutableArray array];
        NSMutableSet<NSString *> *dedupe = [NSMutableSet set];
        for (NSString *path in RYGCompatDeveloperImages()) {
            NSArray<RYGRuntimeBoolMethod *> *rows = [RYGRuntimeBrowserEngine boolMethodsForImagePath:path scope:RYGRuntimeBrowserScopeAll];
            for (RYGRuntimeBoolMethod *row in rows) {
                if (!RYGCompatGateMatches(row, surface)) continue;
                if ([dedupe containsObject:row.overrideKey]) continue;
                [dedupe addObject:row.overrideKey];
                [matches addObject:row];
            }
        }
        [matches sortUsingComparator:^NSComparisonResult(RYGRuntimeBoolMethod *a, RYGRuntimeBoolMethod *b) {
            NSComparisonResult selectorOrder = [a.selectorName localizedCaseInsensitiveCompare:b.selectorName];
            if (selectorOrder != NSOrderedSame) return selectorOrder;
            return [a.className localizedCaseInsensitiveCompare:b.className];
        }];

        dispatch_async(dispatch_get_main_queue(), ^{
            NSUInteger current = [objc_getAssociatedObject(self, kRYGDeveloperGateScanGenerationKey) unsignedIntegerValue];
            if (current != generation) return;
            @try {
                [self setValue:matches.copy forKey:@"gateRows"];
                [self setValue:@NO forKey:@"scanning"];
            } @catch (__unused id exception) {}
            [self rebuildSections];
        });
    });
}

@end

__attribute__((constructor(145))) static void RYGInstallDeveloperGateABICompatibility(void) {
    Class cls = RYGDeveloperGateViewController.class;
    Method original = class_getInstanceMethod(cls, NSSelectorFromString(@"refreshGates"));
    Method replacement = class_getInstanceMethod(cls, @selector(ryg_abi_refreshGates));
    if (original && replacement) method_exchangeImplementations(original, replacement);
}
