#import "RYGDeveloperHubViewController.h"
#import "../Settings/RYGExpFlagsViewController.h"
#import "../UI/RYGLiquidGlass.h"
#import "../Utils.h"

@implementation RYGDeveloperHubViewController

- (instancetype)init { return [super initWithTitle:@"Developer"]; }

- (void)viewDidLoad {
    [super viewDidLoad];
    // Vanilla is authoritative here. Do not bootstrap the newer hard-coded
    // Runtime/Developer surfaces when the menu opens.
    [self rebuildSections];
    RYGLiquidGlassApplyToViewController(self);
}

- (void)rebuildSections {
    RYGSetting *enableHooks = [RYGSetting switchCellWithTitle:@"Enable hooks"
                                                     subtitle:@"Vanilla MetaLocalExperiment + live MobileConfig observers. Restart required."
                                                        value:^BOOL{
        return [RYGUtils getBoolPref:@"ryg_exp_flags_enabled"];
    } action:^(BOOL on) {
        [RYGUtils setPref:@(on) forKey:@"ryg_exp_flags_enabled"];
        if (on) {
            // The old mapped MobileConfig engine hooks the same getter family.
            // Vanilla mode owns that chain, so turn the heavyweight engine off
            // before the requested restart instead of stacking two hook owners.
            [RYGUtils setPref:@NO forKey:@"ryg_metaconfig_enabled"];
        }
    }];
    enableHooks.requiresRestart = YES;

    RYGSetting *browser = [RYGSetting navigationCellWithTitle:@"Experimental flags"
                                                     subtitle:@"Meta experiments, live MC IDs, scanned names and overrides"
                                                         icon:[RYGSymbol symbolWithName:@"flag.2.crossed"]
                                               viewController:[RYGExpFlagsViewController new]];

    [self applySettingSections:@[
        [RYGSettingsViewController sectionWithHeader:@"Vanilla developer engine"
                                               footer:@"The Developer menu now follows the vanilla architecture: explicit MetaLocalExperiment hooks, observed MobileConfig getter calls, and a lazy mmap string scan. Enabling it disables the old heavyweight mapped MobileConfig hook owner for the next launch."
                                                 rows:@[enableHooks, browser]],
    ]];
}

@end
