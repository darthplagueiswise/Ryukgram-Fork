#import "RYGDeveloperGateViewController.h"
#import "RYGCFunctionOverrideEngine.h"
#import "../Settings/RYGSetting.h"
#import "../Settings/RYGSymbol.h"
#import "../Utils.h"
#import <objc/runtime.h>

static NSArray<NSString *> *RYGEasyGatingBoolSymbols(void) {
    return @[
        @"EasyGatingGetBoolean_Internal_DoNotUseOrMock",
        @"EasyGatingGetBooleanUsingAuthDataContext_Internal_DoNotUseOrMock",
    ];
}

@implementation RYGDeveloperGateViewController (RYGEasyGatingControls)

- (void)ryg_easyGating_rebuildSections {
    [self ryg_easyGating_rebuildSections];
    NSInteger surface = -1;
    NSArray *existing = nil;
    @try {
        surface = [[self valueForKey:@"surface"] integerValue];
        existing = [self valueForKey:@"sections"];
    } @catch (__unused id exception) {}
    if (surface != RYGDeveloperGateSurfaceInternal || !existing) return;

    NSMutableArray<RYGSetting *> *rows = [NSMutableArray array];
    __weak typeof(self) weakSelf = self;
    for (NSString *symbol in RYGEasyGatingBoolSymbols()) {
        NSNumber *forced = [RYGCFunctionOverrideEngine forceForSymbol:symbol];
        NSNumber *observed = [RYGCFunctionOverrideEngine observedValueForSymbol:symbol];
        NSUInteger hits = [RYGCFunctionOverrideEngine callCountForSymbol:symbol];
        NSString *subtitle = [NSString stringWithFormat:@"C BOOL · original %@ · output %@ · %lu call%@",
                              observed ? (observed.boolValue ? @"true" : @"false") : @"not observed",
                              forced ? (forced.boolValue ? @"forced true" : @"forced false") : @"native",
                              (unsigned long)hits, hits == 1 ? @"" : @"s"];
        NSString *title = [symbol hasPrefix:@"EasyGatingGetBooleanUsingAuthDataContext"]
            ? @"Easy Gating · Auth context" : @"Easy Gating · Internal";
        RYGSetting *row = [RYGSetting buttonCellWithTitle:title
                                                 subtitle:subtitle
                                                     icon:[RYGSymbol symbolWithName:@"switch"]
                                                   action:^{ [weakSelf ryg_presentEasyGatingActionsForSymbol:symbol title:title]; }];
        [rows addObject:row];
    }

    NSDictionary *section = [RYGSettingsViewController sectionWithHeader:@"Easy Gating C runtime"
                                                                   footer:@"These are exact ABI profiles carried forward from experimental4. Opening this page does not hook them; choosing Force installs the fishhook and preserves the original arguments."
                                                                     rows:rows];
    NSMutableArray *sections = [NSMutableArray arrayWithObject:section];
    [sections addObjectsFromArray:existing];
    [self applySettingSections:sections.copy];
}

- (void)ryg_presentEasyGatingActionsForSymbol:(NSString *)symbol title:(NSString *)title {
    NSNumber *forced = [RYGCFunctionOverrideEngine forceForSymbol:symbol];
    NSNumber *observed = [RYGCFunctionOverrideEngine observedValueForSymbol:symbol];
    NSString *message = [NSString stringWithFormat:@"%@\nOriginal: %@\nOutput: %@",
                         symbol,
                         observed ? (observed.boolValue ? @"true" : @"false") : @"not observed yet",
                         forced ? (forced.boolValue ? @"forced true" : @"forced false") : @"native"];
    UIAlertController *sheet = [UIAlertController alertControllerWithTitle:title message:message preferredStyle:UIAlertControllerStyleActionSheet];
    __weak typeof(self) weakSelf = self;
    void (^apply)(NSNumber *) = ^(NSNumber *value) {
        if (![RYGCFunctionOverrideEngine setForce:value forSymbol:symbol]) {
            [RYGUtils showErrorHUDWithDescription:@"The validated EasyGating function is not rebindable in the currently loaded images."];
            return;
        }
        [weakSelf rebuildSections];
    };
    [sheet addAction:[UIAlertAction actionWithTitle:@"Force true" style:UIAlertActionStyleDefault handler:^(__unused UIAlertAction *action) { apply(@YES); }]];
    [sheet addAction:[UIAlertAction actionWithTitle:@"Force false" style:UIAlertActionStyleDefault handler:^(__unused UIAlertAction *action) { apply(@NO); }]];
    if (forced) [sheet addAction:[UIAlertAction actionWithTitle:@"Use native value" style:UIAlertActionStyleDestructive handler:^(__unused UIAlertAction *action) { apply(nil); }]];
    [sheet addAction:[UIAlertAction actionWithTitle:@"Cancel" style:UIAlertActionStyleCancel handler:nil]];
    [self presentViewController:sheet animated:YES completion:nil];
}

@end

__attribute__((constructor(165))) static void RYGInstallEasyGatingDeveloperControls(void) {
    Class cls = RYGDeveloperGateViewController.class;
    Method original = class_getInstanceMethod(cls, @selector(rebuildSections));
    Method replacement = class_getInstanceMethod(cls, @selector(ryg_easyGating_rebuildSections));
    if (original && replacement) method_exchangeImplementations(original, replacement);
}
