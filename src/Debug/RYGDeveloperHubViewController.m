#import "RYGDeveloperHubViewController.h"
#import "RYGWordmarkViewController.h"
#import "RYGPortedRuntimeBrowserViewController.h"
#import "RYGEasyGatingViewController.h"
#import "RYGMetaLocalExperimentBrowser.h"
#import "../Features/ExpFlags/RYGMobileConfigViewController.h"
#import "../UI/RYGLiquidGlass.h"

@implementation RYGDeveloperHubViewController

- (instancetype)init {
    return [super initWithTitle:@"Developer"];
}

- (void)viewDidLoad {
    [super viewDidLoad];
    [self rebuildSections];
    RYGLiquidGlassApplyToViewController(self);
}

- (void)rebuildSections {
    RYGSetting *wordmark = [RYGSetting navigationCellWithTitle:@"IGWordMark"
                                                     subtitle:@"Validated IGDS/BSLDS native WordMark variants"
                                                         icon:[RYGSymbol symbolWithName:@"instagram"]
                                               viewController:[RYGWordmarkViewController new]];

    RYGSetting *easyGating = [RYGSetting navigationCellWithTitle:@"Easy Gating Runtime"
                                                       subtitle:@"Live wrapper mapping and final gate IDs; installation starts only after opening this surface"
                                                           icon:[RYGSymbol symbolWithName:@"key"]
                                                 viewController:[RYGEasyGatingViewController new]];

    RYGSetting *mobileConfig = [RYGSetting navigationCellWithTitle:@"MobileConfig"
                                                         subtitle:@"Current main2 MobileConfig browser; typed-runtime reconciliation remains owned by the MobileConfig layer"
                                                             icon:[RYGSymbol symbolWithName:@"sliders"]
                                                   viewController:[RYGMobileConfigViewController new]];

    RYGSetting *metaLocal = [RYGSetting buttonCellWithTitle:@"Meta / Family Local Experiments"
                                                   subtitle:@"Native local-experiment browser and current family-device identity"
                                                       icon:[RYGSymbol symbolWithName:@"insights"]
                                                     action:^{ [RYGMetaLocalExperimentBrowser presentFromCurrentViewController]; }];

    RYGSetting *runtime = [RYGSetting navigationCellWithTitle:@"Runtime Browser · WAT Port"
                                                     subtitle:@"dogfood runtime owner · live image inventory · typed getters · persist/retry/apply"
                                                         icon:[RYGSymbol symbolWithName:@"search"]
                                               viewController:[RYGPortedRuntimeBrowserViewController new]];

    [self applySettingSections:@[
        [RYGSettingsViewController sectionWithHeader:nil footer:nil rows:@[wordmark, easyGating, mobileConfig]],
        [RYGSettingsViewController sectionWithHeader:@"Runtime"
                                               footer:@"The runtime inventory is on-demand: no runtime scan or generic persisted-hook replay is installed from this Developer entry during app launch."
                                                 rows:@[metaLocal, runtime]],
    ]];
}

@end
