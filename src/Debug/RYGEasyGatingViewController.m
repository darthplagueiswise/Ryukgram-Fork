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

- (UIMenu *)menuForObservation:(RYGEasyGatingObservation *)observation {
    NSNumber *forced = observation.overrideValue;
    __weak typeof(self) weakSelf = self;

    UIAction *nativeAction = [UIAction actionWithTitle:@"Native"
                                                image:nil
                                           identifier:nil
                                              handler:^(__unused UIAction *action) {
        [RYGEasyGatingRuntime.shared setOverride:nil forGateID:observation.gateID];
        [weakSelf rebuildSections];
    }];
    nativeAction.state = forced ? UIMenuElementStateOff : UIMenuElementStateOn;

    UIAction *forceTrue = [UIAction actionWithTitle:@"Force True"
                                             image:nil
                                        identifier:nil
                                           handler:^(__unused UIAction *action) {
        [RYGEasyGatingRuntime.shared setOverride:@YES forGateID:observation.gateID];
        [weakSelf rebuildSections];
    }];
    forceTrue.state = forced && forced.boolValue ? UIMenuElementStateOn : UIMenuElementStateOff;

    UIAction *forceFalse = [UIAction actionWithTitle:@"Force False"
                                              image:nil
                                         identifier:nil
                                            handler:^(__unused UIAction *action) {
        [RYGEasyGatingRuntime.shared setOverride:@NO forGateID:observation.gateID];
        [weakSelf rebuildSections];
    }];
    forceFalse.state = forced && !forced.boolValue ? UIMenuElementStateOn : UIMenuElementStateOff;

    return [UIMenu menuWithTitle:@"Output"
                           image:nil
                      identifier:nil
                         options:UIMenuOptionsSingleSelection
                        children:@[nativeAction, forceTrue, forceFalse]];
}

- (RYGSetting *)settingForObservation:(RYGEasyGatingObservation *)observation {
    NSNumber *forced = observation.overrideValue;
    NSString *title = [NSString stringWithFormat:@"Gate %u", observation.gateID];
    NSString *subtitle = forced
        ? [NSString stringWithFormat:@"original %@ · forced %@ · default %@ · exposure %@ · %lu calls",
            observation.nativeValue ? @"true" : @"false",
            forced.boolValue ? @"true" : @"false",
            observation.defaultValue ? @"true" : @"false",
            observation.exposureEnabled ? @"on" : @"off",
            (unsigned long)observation.callCount]
        : [NSString stringWithFormat:@"original %@ · default %@ · exposure %@ · %lu calls",
            observation.nativeValue ? @"true" : @"false",
            observation.defaultValue ? @"true" : @"false",
            observation.exposureEnabled ? @"on" : @"off",
            (unsigned long)observation.callCount];

    return [RYGSetting menuCellWithTitle:title
                                subtitle:subtitle
                                    menu:[self menuForObservation:observation]];
}

- (void)rebuildSections {
    NSArray<RYGEasyGatingObservation *> *observations = RYGEasyGatingRuntime.shared.observations;
    NSMutableArray<RYGSetting *> *rows = [NSMutableArray arrayWithCapacity:observations.count];
    for (RYGEasyGatingObservation *observation in observations) {
        [rows addObject:[self settingForObservation:observation]];
    }
    if (!rows.count) {
        [rows addObject:[RYGSetting staticCellWithTitle:@"Waiting for live mapped gates"
                                              subtitle:nil
                                                  icon:[RYGSymbol symbolWithName:@"function"]]];
    }
    [self applySettingSections:@[[RYGSettingsViewController sectionWithHeader:nil
                                                                       footer:@"IDs shown here are the final mapped IDs received by EasyGatingPlatformGetBoolean. Each selector changes only that exact mapped gate; the public pre-map wrapper is not hooked."
                                                                         rows:rows]]];
}

@end
