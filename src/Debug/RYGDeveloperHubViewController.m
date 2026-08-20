#import "RYGDeveloperHubViewController.h"
#import "RYGDeveloperTopicViewController.h"
#import "RYGWordmarkViewController.h"
#import "RYGRuntimeBrowserViewController.h"
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
    RYGSetting *prism = [RYGSetting navigationCellWithTitle:@"Prism / Redesign" subtitle:@"Validated runtime owners" icon:[RYGSymbol symbolWithName:@"layout"] viewController:[[RYGDeveloperTopicViewController alloc] initWithSurface:RYGDeveloperRuntimeSurfacePrism]];
    RYGSetting *glass = [RYGSetting navigationCellWithTitle:@"Liquid Glass" subtitle:@"Navigation, Throwback Chrome and Throwback Feed" icon:[RYGSymbol symbolWithName:@"interface"] viewController:[[RYGDeveloperTopicViewController alloc] initWithSurface:RYGDeveloperRuntimeSurfaceLiquidGlass]];
    RYGSetting *stories = [RYGSetting navigationCellWithTitle:@"Stories / Story Tray" subtitle:@"Native Story Tray debug + redesign gates" icon:[RYGSymbol symbolWithName:@"stories"] viewController:[[RYGDeveloperTopicViewController alloc] initWithSurface:RYGDeveloperRuntimeSurfaceStories]];
    RYGSetting *subs = [RYGSetting navigationCellWithTitle:@"SubsConsumer / IGPlus / Aura" subtitle:@"IGConsumerSubsService owner" icon:[RYGSymbol symbolWithName:@"heart"] viewController:[[RYGDeveloperTopicViewController alloc] initWithSurface:RYGDeveloperRuntimeSurfaceConsumerSubs]];
    RYGSetting *internalOnly = [RYGSetting navigationCellWithTitle:@"IG-only / Internal-only" subtitle:@"Exact Bug Reporter menu visibility ABI" icon:[RYGSymbol symbolWithName:@"eye"] viewController:[[RYGDeveloperTopicViewController alloc] initWithSurface:RYGDeveloperRuntimeSurfaceInternalOnly]];
    RYGSetting *dogfood = [RYGSetting navigationCellWithTitle:@"Dogfooding Mode" subtitle:@"Native menu + resolved MobileConfig + EasyGating" icon:[RYGSymbol symbolWithName:@"paw"] viewController:[[RYGDeveloperTopicViewController alloc] initWithSurface:RYGDeveloperRuntimeSurfaceDirectDogfood]];
    RYGSetting *metaLocal = [RYGSetting buttonCellWithTitle:@"MetaLocalExperiment" subtitle:nil icon:[RYGSymbol symbolWithName:@"insights"] action:^{ [RYGMetaLocalExperimentBrowser presentFromCurrentViewController]; }];
    RYGSetting *runtime = [RYGSetting navigationCellWithTitle:@"Runtime Browser · Live" subtitle:@"Image → ABI-validated BOOL methods · native value + explicit override" icon:[RYGSymbol symbolWithName:@"search"] viewController:[RYGRuntimeBrowserViewController new]];

    [self applySettingSections:@[
        [RYGSettingsViewController sectionWithHeader:nil footer:nil rows:@[wordmark, easyGating, mobileConfig]],
        [RYGSettingsViewController sectionWithHeader:@"Validated surfaces" footer:nil rows:@[prism, glass, stories, subs, internalOnly, dogfood]],
        [RYGSettingsViewController sectionWithHeader:nil footer:nil rows:@[metaLocal, runtime]],
    ]];
}

@end
