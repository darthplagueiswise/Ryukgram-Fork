#import "RYGDeveloperHubViewController.h"
#import "RYGDeveloperTopicViewController.h"
#import "RYGWordmarkViewController.h"
#import "RYGFastRuntimeBrowserViewController.h"
#import "RYGEasyGatingViewController.h"
#import "RYGMetaLocalExperimentBrowser.h"
#import "../Features/ExpFlags/RYGMobileConfigToolsViewController.h"
#import "../UI/RYGLiquidGlass.h"

@implementation RYGDeveloperHubViewController

- (instancetype)init { return [super initWithTitle:@"Developer"]; }

- (void)viewDidLoad {
    [super viewDidLoad];
    [RYGDeveloperTopicViewController activatePersistedNativeFeatures];
    [self rebuildSections];
    RYGLiquidGlassApplyToViewController(self);
}

- (void)rebuildSections {
    RYGSetting *wordmark = [RYGSetting navigationCellWithTitle:@"IGWordMark" subtitle:nil icon:[RYGSymbol symbolWithName:@"instagram"] viewController:[RYGWordmarkViewController new]];
    RYGSetting *easyGating = [RYGSetting navigationCellWithTitle:@"Easy Gating Internal" subtitle:@"Final mapped IDs observed live" icon:[RYGSymbol symbolWithName:@"key"] viewController:[RYGEasyGatingViewController new]];
    RYGSetting *mobileConfig = [RYGSetting navigationCellWithTitle:@"MobileConfig" subtitle:@"Live table + id_name_mapping + native overrides" icon:[RYGSymbol symbolWithName:@"sliders"] viewController:[RYGMobileConfigToolsViewController new]];
    RYGSetting *prism = [RYGSetting navigationCellWithTitle:@"Prism UI" subtitle:@"Live customizations across the selected executable or framework" icon:[RYGSymbol symbolWithName:@"layout"] viewController:[[RYGDeveloperTopicViewController alloc] initWithSurface:RYGDeveloperRuntimeSurfacePrism]];
    RYGSetting *stories = [RYGSetting navigationCellWithTitle:@"Story Tray / Story Grid" subtitle:@"Native tray debug + dynamic Story Grid gate" icon:[RYGSymbol symbolWithName:@"rectangle.stack"] viewController:[[RYGDeveloperTopicViewController alloc] initWithSurface:RYGDeveloperRuntimeSurfaceStories]];
    RYGSetting *glass = [RYGSetting navigationCellWithTitle:@"Liquid Glass Throwback" subtitle:@"Throwback Chrome blue header + navigation/feed helpers" icon:[RYGSymbol symbolWithName:@"interface"] viewController:[[RYGDeveloperTopicViewController alloc] initWithSurface:RYGDeveloperRuntimeSurfaceLiquidGlass]];
    RYGSetting *internalOnly = [RYGSetting navigationCellWithTitle:@"IG-only / Internal-only" subtitle:@"Live ABI-safe gates across the selected image" icon:[RYGSymbol symbolWithName:@"eye"] viewController:[[RYGDeveloperTopicViewController alloc] initWithSurface:RYGDeveloperRuntimeSurfaceInternalOnly]];
    RYGSetting *bugReport = [RYGSetting navigationCellWithTitle:@"Bug Report Menu" subtitle:@"Logged out, assistant, internal settings, shake and sandbox" icon:[RYGSymbol symbolWithName:@"bug"] viewController:[[RYGDeveloperTopicViewController alloc] initWithSurface:RYGDeveloperRuntimeSurfaceBugReport]];
    RYGSetting *settingsRows = [RYGSetting navigationCellWithTitle:@"Hidden Settings Rows" subtitle:@"Real-time visibility gates; no preloaded row table" icon:[RYGSymbol symbolWithName:@"list"] viewController:[[RYGDeveloperTopicViewController alloc] initWithSurface:RYGDeveloperRuntimeSurfaceSettingsRows]];
    RYGSetting *dogfood = [RYGSetting navigationCellWithTitle:@"Direct / Dogfooding Settings" subtitle:@"Native menus + live employee/dogfood MobileConfig resolution" icon:[RYGSymbol symbolWithName:@"paw"] viewController:[[RYGDeveloperTopicViewController alloc] initWithSurface:RYGDeveloperRuntimeSurfaceDirectDogfood]];
    // Keep the proven native MetaLocalExperiment presentation path unchanged.
    RYGSetting *metaLocal = [RYGSetting buttonCellWithTitle:@"MetaLocalExperiment" subtitle:nil icon:[RYGSymbol symbolWithName:@"insights"] action:^{ [RYGMetaLocalExperimentBrowser presentFromCurrentViewController]; }];
    RYGSetting *runtime = [RYGSetting navigationCellWithTitle:@"Runtime Browser · Live" subtitle:@"In-memory image snapshot · explicit refresh · ABI-validated BOOL methods" icon:[RYGSymbol symbolWithName:@"search"] viewController:[RYGFastRuntimeBrowserViewController new]];

    [self applySettingSections:@[
        [RYGSettingsViewController sectionWithHeader:nil footer:nil rows:@[wordmark, easyGating, mobileConfig]],
        [RYGSettingsViewController sectionWithHeader:@"Live native surfaces" footer:@"Rows are derived from currently loaded Objective-C/Mach-O images or the active MobileConfig runtime. Nothing is shipped as a preloaded gate table." rows:@[prism, stories, glass, internalOnly, bugReport, settingsRows, dogfood]],
        [RYGSettingsViewController sectionWithHeader:nil footer:nil rows:@[metaLocal, runtime]],
    ]];
}

@end
