#import "RYGDeveloperHubViewController.h"
#import "../Settings/RYGExpFlagsViewController.h"
#import "../UI/RYGLiquidGlass.h"

@implementation RYGDeveloperHubViewController

- (instancetype)init { return [super initWithTitle:@"Developer"]; }

- (void)viewDidLoad {
    [super viewDidLoad];
    // Deliberately do not bootstrap the newer hard-coded Developer surfaces here.
    // The vanilla architecture installs only its explicit hooks from %ctor when
    // ryg_exp_flags_enabled is set, after a user-requested restart.
    [self rebuildSections];
    RYGLiquidGlassApplyToViewController(self);
}

- (void)rebuildSections {
    RYGSetting *enableHooks = [RYGSetting switchCellWithTitle:@"Enable hooks"
                                                     subtitle:@"Vanilla MetaLocalExperiment + MobileConfig observers. Restart required."
                                                  defaultsKey:@"ryg_exp_flags_enabled"
                                              requiresRestart:YES];

    RYGSetting *browser = [RYGSetting navigationCellWithTitle:@"Experimental flags"
                                                     subtitle:@"Meta experiments, live MC IDs, scanned names and overrides"
                                                         icon:[RYGSymbol symbolWithName:@"flag.2.crossed"]
                                               viewController:[RYGExpFlagsViewController new]];

    [self applySettingSections:@[
        [RYGSettingsViewController sectionWithHeader:@"Vanilla developer engine"
                                               footer:@"This is the lightweight developer path used by the vanilla branch: explicit MetaLocalExperiment hooks, live MobileConfig observations, and a lazy mmap string scan. The previous Runtime Browser and hard-coded Developer surfaces are not started from this menu."
                                                 rows:@[enableHooks, browser]],
    ]];
}

@end
