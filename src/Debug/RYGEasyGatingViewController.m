#import "RYGEasyGatingViewController.h"
#import "RYGEasyGatingRuntime.h"
#import "../Settings/RYGSetting.h"
#import "../Settings/RYGSymbol.h"
#import "../UI/RYGLiquidGlass.h"
#import "../Utils.h"

@implementation RYGEasyGatingViewController

- (instancetype)init { return [super initWithTitle:@"Easy Gating Internal"]; }

- (void)viewDidLoad {
    [super viewDidLoad];
    self.tableView.keyboardDismissMode = UIScrollViewKeyboardDismissModeOnDrag;
    [[RYGEasyGatingRuntime shared] installIfNeeded];
    [NSNotificationCenter.defaultCenter addObserver:self
                                           selector:@selector(easyGatingChanged:)
                                               name:RYGEasyGatingDidObserveNotification
                                             object:nil];

    __weak typeof(self) weakSelf = self;
    UIAction *clear = [UIAction actionWithTitle:@"Clear observations"
                                         image:[[RYGSymbol symbolWithName:@"history"] image]
                                    identifier:nil
                                       handler:^(__unused UIAction *action) {
        [[RYGEasyGatingRuntime shared] clearObservations];
        [weakSelf rebuildSections];
    }];
    self.navigationItem.rightBarButtonItem = [[UIBarButtonItem alloc]
        initWithImage:[[RYGSymbol symbolWithName:@"ellipsis_circle"] image]
                menu:[UIMenu menuWithChildren:@[clear]]];

    [self rebuildSections];
    RYGLiquidGlassApplyToViewController(self);
}

- (void)dealloc { [NSNotificationCenter.defaultCenter removeObserver:self]; }

- (void)easyGatingChanged:(NSNotification *)notification {
    (void)notification;
    if (NSThread.isMainThread) [self rebuildSections];
    else dispatch_async(dispatch_get_main_queue(), ^{ [self rebuildSections]; });
}

- (RYGSetting *)settingForObservation:(RYGEasyGatingObservation *)observation {
    NSNumber *forced = observation.overrideValue;
    NSString *title = [NSString stringWithFormat:@"Gate %u", observation.gateID];
    NSString *subtitle = forced
        ? [NSString stringWithFormat:@"original %@ · forced %@ · default %@ · exposure %@",
            observation.nativeValue ? @"true" : @"false",
            forced.boolValue ? @"true" : @"false",
            observation.defaultValue ? @"true" : @"false",
            observation.exposureEnabled ? @"on" : @"off"]
        : [NSString stringWithFormat:@"original %@ · default %@ · exposure %@",
            observation.nativeValue ? @"true" : @"false",
            observation.defaultValue ? @"true" : @"false",
            observation.exposureEnabled ? @"on" : @"off"];
    __weak typeof(self) weakSelf = self;
    return [RYGSetting buttonCellWithTitle:title
                                  subtitle:subtitle
                                      icon:[RYGSymbol symbolWithName:forced ? @"slider_horizontal_3" : @"function"]
                                    action:^{ [weakSelf presentActionsForObservation:observation]; }];
}

- (void)rebuildSections {
    NSArray<RYGEasyGatingObservation *> *observations = RYGEasyGatingRuntime.shared.observations;
    NSMutableArray<RYGSetting *> *rows = [NSMutableArray arrayWithCapacity:observations.count];
    for (RYGEasyGatingObservation *observation in observations) [rows addObject:[self settingForObservation:observation]];
    if (!rows.count) {
        [rows addObject:[RYGSetting staticCellWithTitle:@"Waiting for live mapped gates" subtitle:nil icon:[RYGSymbol symbolWithName:@"function"]]];
    }
    [self applySettingSections:@[[RYGSettingsViewController sectionWithHeader:nil
                                                                       footer:@"IDs shown here are the final mapped IDs received by EasyGatingPlatformGetBoolean, not the pre-map selector/index passed to the public wrapper."
                                                                         rows:rows]]];
}

- (void)presentActionsForObservation:(RYGEasyGatingObservation *)observation {
    NSNumber *forced = observation.overrideValue;
    NSString *message = [NSString stringWithFormat:@"Mapped ID %u · default %@ · exposure %@ · original %@ · %lu call%@",
        observation.gateID,
        observation.defaultValue ? @"true" : @"false",
        observation.exposureEnabled ? @"on" : @"off",
        observation.nativeValue ? @"true" : @"false",
        (unsigned long)observation.callCount,
        observation.callCount == 1 ? @"" : @"s"];
    UIAlertController *sheet = [UIAlertController alertControllerWithTitle:@"Easy Gating"
                                                                    message:message
                                                             preferredStyle:UIAlertControllerStyleActionSheet];
    __weak typeof(self) weakSelf = self;
    [sheet addAction:[UIAlertAction actionWithTitle:@"Force True" style:UIAlertActionStyleDefault handler:^(__unused UIAlertAction *action) {
        [RYGEasyGatingRuntime.shared setOverride:@YES forGateID:observation.gateID]; [weakSelf rebuildSections];
    }]];
    [sheet addAction:[UIAlertAction actionWithTitle:@"Force False" style:UIAlertActionStyleDefault handler:^(__unused UIAlertAction *action) {
        [RYGEasyGatingRuntime.shared setOverride:@NO forGateID:observation.gateID]; [weakSelf rebuildSections];
    }]];
    if (forced) {
        [sheet addAction:[UIAlertAction actionWithTitle:@"Use Native" style:UIAlertActionStyleDestructive handler:^(__unused UIAlertAction *action) {
            [RYGEasyGatingRuntime.shared setOverride:nil forGateID:observation.gateID]; [weakSelf rebuildSections];
        }]];
    }
    [sheet addAction:[UIAlertAction actionWithTitle:@"Copy mapped ID" style:UIAlertActionStyleDefault handler:^(__unused UIAlertAction *action) {
        UIPasteboard.generalPasteboard.string = [NSString stringWithFormat:@"%u", observation.gateID];
    }]];
    [sheet addAction:[UIAlertAction actionWithTitle:@"Cancel" style:UIAlertActionStyleCancel handler:nil]];
    if (UIDevice.currentDevice.userInterfaceIdiom == UIUserInterfaceIdiomPad) {
        sheet.popoverPresentationController.sourceView = self.view;
        sheet.popoverPresentationController.sourceRect = CGRectMake(CGRectGetMidX(self.view.bounds), 90.0, 1.0, 1.0);
    }
    [self presentViewController:sheet animated:YES completion:nil];
}

@end
