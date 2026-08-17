#import "RYGDeveloperRuntimeBrowserViewController.h"
#import "RYGRuntimeBrowserEngine.h"
#import "RYGRuntimeLiveObserver.h"
#import "../Utils.h"

@implementation RYGDeveloperRuntimeBrowserViewController

- (void)viewDidLoad {
    [super viewDidLoad];
    [[NSNotificationCenter defaultCenter] addObserver:self
                                             selector:@selector(rygRuntimeNativeValueChanged:)
                                                 name:RYGRuntimeNativeValueDidChangeNotification
                                               object:nil];
}

- (void)dealloc {
    [[NSNotificationCenter defaultCenter] removeObserver:self];
}

- (void)rygRuntimeNativeValueChanged:(NSNotification *)notification {
    UITableView *table = nil;
    @try { table = [self valueForKey:@"tableView"]; } @catch (__unused NSException *exception) {}
    if (table) [table reloadData];
}

- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath {
    [tableView deselectRowAtIndexPath:indexPath animated:YES];

    UISegmentedControl *mode = nil;
    NSArray *visibleRows = nil;
    @try {
        mode = [self valueForKey:@"modeControl"];
        visibleRows = [self valueForKey:@"visibleRows"];
    } @catch (__unused NSException *exception) {}

    if (!mode || indexPath.row < 0 || indexPath.row >= (NSInteger)visibleRows.count) return;
    id item = visibleRows[(NSUInteger)indexPath.row];

    if (mode.selectedSegmentIndex != 0) {
        if ([item isKindOfClass:RYGMachOSymbol.class]) {
            RYGMachOSymbol *symbol = item;
            UIPasteboard.generalPasteboard.string = symbol.name;
            [RYGUtils showToastForDuration:1.2 title:@"Copied" subtitle:symbol.name];
        }
        return;
    }

    if (![item isKindOfClass:RYGRuntimeBoolMethod.class]) return;
    RYGRuntimeBoolMethod *method = item;
    NSNumber *native = method.liveValue;
    NSNumber *forced = method.overrideValue;
    NSString *nativeText = native ? (native.boolValue ? @"true" : @"false") : @"not observed yet";
    NSString *outputText = forced ? (forced.boolValue ? @"forced true" : @"forced false") : @"native";
    NSString *message = [NSString stringWithFormat:@"%@\nOriginal: %@\nOutput: %@",
                         method.className, nativeText, outputText];

    UIAlertController *sheet = [UIAlertController alertControllerWithTitle:method.selectorName
                                                                    message:message
                                                             preferredStyle:UIAlertControllerStyleActionSheet];
    __weak typeof(self) weakSelf = self;

    [sheet addAction:[UIAlertAction actionWithTitle:@"Observe original live value"
                                              style:UIAlertActionStyleDefault
                                            handler:^(__unused UIAlertAction *action) {
        RYGRuntimeBeginLiveObservation(@[method]);
        [RYGUtils showToastForDuration:1.5
                                title:@"Live observer installed"
                             subtitle:@"Waiting for Instagram to call this method"];
    }]];

    [sheet addAction:[UIAlertAction actionWithTitle:@"Force true"
                                              style:UIAlertActionStyleDefault
                                            handler:^(__unused UIAlertAction *action) {
        [RYGRuntimeBrowserEngine setOverride:@YES forMethod:method];
        UITableView *strongTable = nil;
        @try { strongTable = [weakSelf valueForKey:@"tableView"]; } @catch (__unused NSException *exception) {}
        [strongTable reloadData];
    }]];

    [sheet addAction:[UIAlertAction actionWithTitle:@"Force false"
                                              style:UIAlertActionStyleDefault
                                            handler:^(__unused UIAlertAction *action) {
        [RYGRuntimeBrowserEngine setOverride:@NO forMethod:method];
        UITableView *strongTable = nil;
        @try { strongTable = [weakSelf valueForKey:@"tableView"]; } @catch (__unused NSException *exception) {}
        [strongTable reloadData];
    }]];

    if (method.overrideValue) {
        [sheet addAction:[UIAlertAction actionWithTitle:@"Use native value"
                                                  style:UIAlertActionStyleDestructive
                                                handler:^(__unused UIAlertAction *action) {
            [RYGRuntimeBrowserEngine setOverride:nil forMethod:method];
            UITableView *strongTable = nil;
            @try { strongTable = [weakSelf valueForKey:@"tableView"]; } @catch (__unused NSException *exception) {}
            [strongTable reloadData];
        }]];
    }

    [sheet addAction:[UIAlertAction actionWithTitle:@"Copy method details"
                                              style:UIAlertActionStyleDefault
                                            handler:^(__unused UIAlertAction *action) {
        UIPasteboard.generalPasteboard.string = [NSString stringWithFormat:@"%@[%@ %@] %@",
                                                 method.classMethod ? @"+" : @"-",
                                                 method.className,
                                                 method.selectorName,
                                                 method.typeEncoding];
    }]];
    [sheet addAction:[UIAlertAction actionWithTitle:@"Cancel" style:UIAlertActionStyleCancel handler:nil]];

    if (UIDevice.currentDevice.userInterfaceIdiom == UIUserInterfaceIdiomPad) {
        UITableViewCell *cell = [tableView cellForRowAtIndexPath:indexPath];
        sheet.popoverPresentationController.sourceView = cell ?: tableView;
        sheet.popoverPresentationController.sourceRect = cell ? cell.bounds : CGRectMake(CGRectGetMidX(tableView.bounds), 80.0, 1.0, 1.0);
    }
    [self presentViewController:sheet animated:YES completion:nil];
}

@end
