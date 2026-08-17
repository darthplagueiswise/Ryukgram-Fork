#import "RYGDeveloperGateViewController.h"
#import "RYGDeveloperRuntimeScanner.h"
#import <objc/runtime.h>

static const void *kRYGDeveloperGateScanGenerationKey = &kRYGDeveloperGateScanGenerationKey;

static NSArray<NSString *> *RYGVerifiedKeywordsForGateSurface(RYGDeveloperGateSurface surface) {
    switch (surface) {
        case RYGDeveloperGateSurfaceWordMark: return @[@"wordmark"];
        case RYGDeveloperGateSurfacePrism: return @[@"prism"];
        case RYGDeveloperGateSurfaceLiquidGlass: return @[@"liquidglass"];
        case RYGDeveloperGateSurfaceInternal:
            // Internal/Easy Gating is no longer inferred from arbitrary ObjC
            // selectors containing employee/internal. The supplied executable
            // imports the real EasyGating Boolean C dispatcher, which is handled
            // by RYGEasyGatingRuntime / RYGEasyGatingViewController per gate ID.
            return nil;
    }
    return nil;
}

@implementation RYGDeveloperGateViewController (RYGABICompatibility)

- (void)ryg_abi_refreshGates {
    NSInteger surfaceValue = 0;
    @try { surfaceValue = [[self valueForKey:@"surface"] integerValue]; } @catch (__unused id exception) {}
    RYGDeveloperGateSurface surface = (RYGDeveloperGateSurface)surfaceValue;
    NSArray<NSString *> *keywords = RYGVerifiedKeywordsForGateSurface(surface);

    NSUInteger generation = [objc_getAssociatedObject(self, kRYGDeveloperGateScanGenerationKey) unsignedIntegerValue] + 1;
    objc_setAssociatedObject(self, kRYGDeveloperGateScanGenerationKey, @(generation), OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    @try { [self setValue:@YES forKey:@"scanning"]; } @catch (__unused id exception) {}
    [self rebuildSections];

    if (!keywords.count) {
        @try {
            [self setValue:@[] forKey:@"gateRows"];
            [self setValue:@NO forKey:@"scanning"];
        } @catch (__unused id exception) {}
        [self rebuildSections];
        return;
    }

    NSArray<NSString *> *images = [RYGDeveloperRuntimeScanner primaryDeveloperImagePaths];
    dispatch_async(dispatch_get_global_queue(QOS_CLASS_USER_INITIATED, 0), ^{
        NSArray *matches = [RYGDeveloperRuntimeScanner boolMethodsForImagePaths:images keywords:keywords];
        dispatch_async(dispatch_get_main_queue(), ^{
            NSUInteger current = [objc_getAssociatedObject(self, kRYGDeveloperGateScanGenerationKey) unsignedIntegerValue];
            if (current != generation) return;
            @try {
                [self setValue:matches ?: @[] forKey:@"gateRows"];
                [self setValue:@NO forKey:@"scanning"];
            } @catch (__unused id exception) {}
            [self rebuildSections];
        });
    });
}

@end

// One compatibility shim remains only because older navigation paths can still
// instantiate RYGDeveloperGateViewController directly. It delegates to the same
// authoritative scanner used by the current Developer hub; it does not perform
// a second runtime enumeration or maintain a separate selector table.
__attribute__((constructor(145))) static void RYGInstallDeveloperGateABICompatibility(void) {
    Class cls = RYGDeveloperGateViewController.class;
    Method original = class_getInstanceMethod(cls, NSSelectorFromString(@"refreshGates"));
    Method replacement = class_getInstanceMethod(cls, @selector(ryg_abi_refreshGates));
    if (original && replacement) method_exchangeImplementations(original, replacement);
}
