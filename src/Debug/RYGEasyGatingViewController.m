#import "RYGEasyGatingViewController.h"
#import "RYGEasyGatingRuntime.h"
#import "../Settings/RYGSetting.h"
#import "../Settings/RYGSymbol.h"
#import "../UI/RYGLiquidGlass.h"
#import "../Utils.h"

@implementation RYGEasyGatingViewController

- (instancetype)init {
    return [super initWithTitle:@"Easy Gating Internal"];
}

- (void)viewDidLoad {
    [super viewDidLoad];
    self.tableView.keyboardDismissMode = UIScrollViewKeyboardDismissModeOnDrag;
    [[RYGEasyGatingRuntime shared] installIfNeeded];
    [NSNotificationCenter.defaultCenter addObserver:self
                                           selector:@selector(easyGatingChanged:)
                                               name:RYGEasyGatingDidObserveNotification
                                             object:nil];

    __weak typeof(self) weakSelf = self;
    UIAction *clear = [UIAction actionWithTitle:@"Clear live observations"
                                         image:[[RYGSymbol symbolWithName:@"history"] image]
                                    identifier:nil
                                       handler:^(__unused UIAction *action) {
        [[RYGEasyGatingRuntime shared] clearObservations];
        [weakSelf rebuildSections];
    }];
    self.navigationItem.rightBarButtonItem = [[UIBarButtonItem alloc]
        initWithImage:[[RYGSymbol symbolWithName:@"ellipsis_circle"] image]
                menu:[UIMenu menuWithTitle:@"Easy Gating" children:@[clear]]];

    [self rebuildSections];
    RYGLiquidGlassApplyToViewController(self);
}

- (void)dealloc {
    [NSNotificationCenter.defaultCenter removeObserver:self];
}

- (void)easyGatingChanged:(NSNotification *)notification {
    (void)notification;
    if (!NSThread.isMainThread) {
        dispatch_async(dispatch_get_main_queue(), ^{ [self rebuildSections]; });
        return;
    }
    [self rebuildSections];
}

- (RYGSetting *)settingForObservation:(RYGEasyGatingObservation *)row {
    NSNumber *forced = row.overrideValue;
    NSString *title = [NSString stringWithFormat:@"Gate %u · 0x%X", row.gateID, row.gateID];
    NSString *native = row.nativeValue ? @"true" : @"false";
    NSString *output = forced ? (forced.boolValue ? @"forced true" : @"forced false") : @"native";
    NSString *subtitle = [NSString stringWithFormat:@"variant %u · original %@ · output %@\n%lu live call%@",
                          row.variant,
                          native,
                          output,
                          (unsigned long)row.callCount,
                          row.callCount == 1 ? @"" : @"s"];
    RYGSymbol *icon = forced
        ? [RYGSymbol symbolWithName:(forced.boolValue ? @"circle_check_filled" : @"xmark")]
        : [RYGSymbol symbolWithName:@"function" color:UIColor.secondaryLabelColor];
    __weak typeof(self) weakSelf = self;
    return [RYGSetting buttonCellWithTitle:title subtitle:subtitle icon:icon action:^{
        [weakSelf presentActionsForObservation:row];
    }];
}

- (void)rebuildSections {
    NSArray<RYGEasyGatingObservation *> *observations = [[RYGEasyGatingRuntime shared] observations];
    NSMutableArray<RYGSetting *> *rows = [NSMutableArray arrayWithCapacity:observations.count];
    for (RYGEasyGatingObservation *observation in observations) {
        [rows addObject:[self settingForObservation:observation]];
    }
    if (!rows.count) {
        [rows addObject:[RYGSetting staticCellWithTitle:@"Waiting for a live Easy Gating query"
                                               subtitle:@"The supplied Instagram executable imports EasyGatingGetBoolean_Internal_DoNotUseOrMock. This page lists gate IDs only after that exact API is called; no guessed Objective-C employee getter is substituted."
                                                   icon:[RYGSymbol symbolWithName:@"info"]]];
    }

    NSString *footer = [NSString stringWithFormat:@"%lu gate ID%@ observed through the real Easy Gating Boolean C entry point. Context pointers are never persisted. Overrides are per numeric gate ID and native pass-through is the default.",
                        (unsigned long)observations.count,
                        observations.count == 1 ? @"" : @"s"];
    [self applySettingSections:@[[RYGSettingsViewController sectionWithHeader:@"Live Boolean gates"
                                                                           footer:footer
                                                                             rows:rows]]];
}

- (void)presentActionsForObservation:(RYGEasyGatingObservation *)row {
    NSNumber *forced = row.overrideValue;
    NSString *message = [NSString stringWithFormat:@"Gate ID %u (0x%X)\nVariant %u\nOriginal: %@\nOutput: %@\nCalls: %lu",
                         row.gateID,
                         row.gateID,
                         row.variant,
                         row.nativeValue ? @"true" : @"false",
                         forced ? (forced.boolValue ? @"forced true" : @"forced false") : @"native",
                         (unsigned long)row.callCount];
    UIAlertController *sheet = [UIAlertController alertControllerWithTitle:@"Easy Gating Boolean"
                                                                    message:message
                                                             preferredStyle:UIAlertControllerStyleActionSheet];
    __weak typeof(self) weakSelf = self;
    [sheet addAction:[UIAlertAction actionWithTitle:@"Force true" style:UIAlertActionStyleDefault handler:^(__unused UIAlertAction *action) {
        [[RYGEasyGatingRuntime shared] setOverride:@YES forGateID:row.gateID];
        [weakSelf rebuildSections];
    }]];
    [sheet addAction:[UIAlertAction actionWithTitle:@"Force false" style:UIAlertActionStyleDefault handler:^(__unused UIAlertAction *action) {
        [[RYGEasyGatingRuntime shared] setOverride:@NO forGateID:row.gateID];
        [weakSelf rebuildSections];
    }]];
    if (forced) {
        [sheet addAction:[UIAlertAction actionWithTitle:@"Use native value" style:UIAlertActionStyleDestructive handler:^(__unused UIAlertAction *action) {
            [[RYGEasyGatingRuntime shared] setOverride:nil forGateID:row.gateID];
            [weakSelf rebuildSections];
        }]];
    }
    [sheet addAction:[UIAlertAction actionWithTitle:@"Copy gate ID" style:UIAlertActionStyleDefault handler:^(__unused UIAlertAction *action) {
        UIPasteboard.generalPasteboard.string = [NSString stringWithFormat:@"%u", row.gateID];
    }]];
    [sheet addAction:[UIAlertAction actionWithTitle:@"Cancel" style:UIAlertActionStyleCancel handler:nil]];
    if (UIDevice.currentDevice.userInterfaceIdiom == UIUserInterfaceIdiomPad) {
        sheet.popoverPresentationController.sourceView = self.view;
        sheet.popoverPresentationController.sourceRect = CGRectMake(CGRectGetMidX(self.view.bounds), 90.0, 1.0, 1.0);
    }
    [self presentViewController:sheet animated:YES completion:nil];
}

@end
