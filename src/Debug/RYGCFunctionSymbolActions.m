#import "RYGDeveloperRuntimeBrowserViewController.h"
#import "RYGRuntimeBrowserEngine.h"
#import "RYGCFunctionOverrideEngine.h"
#import "../Utils.h"
#import <UIKit/UIKit.h>
#import <objc/runtime.h>

@implementation RYGDeveloperRuntimeBrowserViewController (RYGCFunctionSymbolActions)

- (void)ryg_csymbol_tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath {
    UISegmentedControl *mode = nil;
    NSArray *visibleRows = nil;
    @try {
        mode = [self valueForKey:@"modeControl"];
        visibleRows = [self valueForKey:@"visibleRows"];
    } @catch (__unused id exception) {}

    if (!mode || mode.selectedSegmentIndex != 1 || indexPath.row < 0 || indexPath.row >= (NSInteger)visibleRows.count) {
        [self ryg_csymbol_tableView:tableView didSelectRowAtIndexPath:indexPath];
        return;
    }

    RYGMachOSymbol *symbol = [visibleRows[indexPath.row] isKindOfClass:RYGMachOSymbol.class] ? visibleRows[indexPath.row] : nil;
    if (!symbol || ![symbol.kind isEqualToString:@"Function"] || ![RYGCFunctionOverrideEngine isKnownBoolFunctionSymbol:symbol.name]) {
        [self ryg_csymbol_tableView:tableView didSelectRowAtIndexPath:indexPath];
        return;
    }

    [tableView deselectRowAtIndexPath:indexPath animated:YES];
    NSNumber *forced = [RYGCFunctionOverrideEngine forceForSymbol:symbol.name];
    NSNumber *observed = [RYGCFunctionOverrideEngine observedValueForSymbol:symbol.name];
    NSUInteger hits = [RYGCFunctionOverrideEngine callCountForSymbol:symbol.name];
    NSString *message = [NSString stringWithFormat:@"Validated C BOOL profile\nNative: %@ · calls: %lu\nOutput: %@\n\nThe hook preserves the known function ABI and overrides only the BOOL return.",
                         observed ? (observed.boolValue ? @"true" : @"false") : @"not observed",
                         (unsigned long)hits,
                         forced ? (forced.boolValue ? @"forced true" : @"forced false") : @"native"];
    UIAlertController *sheet = [UIAlertController alertControllerWithTitle:symbol.name
                                                                    message:message
                                                             preferredStyle:UIAlertControllerStyleActionSheet];
    __weak typeof(self) weakSelf = self;
    void (^apply)(NSNumber *) = ^(NSNumber *value) {
        if (![RYGCFunctionOverrideEngine setForce:value forSymbol:symbol.name]) {
            [RYGUtils showErrorHUDWithDescription:@"The validated C function could not be rebound in this loaded image."];
            return;
        }
        [RYGUtils showToastForDuration:1.3 title:@"C runtime override"
                             subtitle:value ? (value.boolValue ? @"Forced true" : @"Forced false") : @"Native value restored"];
        UITableView *strongTable = nil;
        @try { strongTable = [weakSelf valueForKey:@"tableView"]; } @catch (__unused id exception) {}
        [strongTable reloadData];
    };
    [sheet addAction:[UIAlertAction actionWithTitle:@"Force true" style:UIAlertActionStyleDefault handler:^(__unused UIAlertAction *action) { apply(@YES); }]];
    [sheet addAction:[UIAlertAction actionWithTitle:@"Force false" style:UIAlertActionStyleDefault handler:^(__unused UIAlertAction *action) { apply(@NO); }]];
    if (forced) [sheet addAction:[UIAlertAction actionWithTitle:@"Use native value" style:UIAlertActionStyleDestructive handler:^(__unused UIAlertAction *action) { apply(nil); }]];
    [sheet addAction:[UIAlertAction actionWithTitle:@"Copy symbol" style:UIAlertActionStyleDefault handler:^(__unused UIAlertAction *action) { UIPasteboard.generalPasteboard.string = symbol.name; }]];
    [sheet addAction:[UIAlertAction actionWithTitle:@"Cancel" style:UIAlertActionStyleCancel handler:nil]];
    [self presentViewController:sheet animated:YES completion:nil];
}

@end

__attribute__((constructor(155))) static void RYGInstallCFunctionSymbolActions(void) {
    Class cls = RYGDeveloperRuntimeBrowserViewController.class;
    Method original = class_getInstanceMethod(cls, @selector(tableView:didSelectRowAtIndexPath:));
    Method replacement = class_getInstanceMethod(cls, @selector(ryg_csymbol_tableView:didSelectRowAtIndexPath:));
    if (original && replacement) method_exchangeImplementations(original, replacement);
}
