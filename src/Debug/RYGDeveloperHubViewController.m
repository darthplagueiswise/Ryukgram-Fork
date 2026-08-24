#import "RYGDeveloperHubViewController.h"
#import "RYGDeveloperTopicViewController.h"
#import "RYGDeveloperFeatureCatalog.h"
#import "RYGDeveloperFeatureCatalogViewController.h"
#import "RYGDeveloperHookRegistry.h"
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

    // No cold-start runtime walk. Developer itself owns this prewarm and only
    // resolves the tiny known-owner lists asynchronously after the hub opens.
    [[RYGDeveloperFeatureCatalog sharedCatalog] startIfNeeded];
    [[RYGDeveloperFeatureCatalog sharedCatalog] prewarmKnownOwners];
    [[RYGDeveloperHookRegistry sharedRegistry] startIfNeeded];

    [self rebuildSections];
    RYGLiquidGlassApplyToViewController(self);
}

- (void)rebuildSections {
    RYGSetting *wordmark = [RYGSetting navigationCellWithTitle:@"IGWordMark" subtitle:@"Native Wordmark families with typed persisted overrides" icon:[RYGSymbol symbolWithName:@"instagram"] viewController:[RYGWordmarkViewController new]];
    RYGSetting *easyGating = [RYGSetting navigationCellWithTitle:@"Easy Gating Internal" subtitle:@"Validated internal gate resolution" icon:[RYGSymbol symbolWithName:@"key"] viewController:[RYGEasyGatingViewController new]];
    RYGSetting *mobileConfig = [RYGSetting navigationCellWithTitle:@"MobileConfig" subtitle:@"id_name_mapping + mc_overrides + native active-session path" icon:[RYGSymbol symbolWithName:@"sliders"] viewController:[RYGMobileConfigToolsViewController new]];

    RYGSetting *liveCatalog = [RYGSetting navigationCellWithTitle:@"Live Feature Catalog" subtitle:@"Prism, Aura/IGPlus, Stories, Glass and internal domains · no Runtime Browser required" icon:[RYGSymbol symbolWithName:@"list"] viewController:[RYGDeveloperFeatureCatalogViewController new]];
    RYGSetting *prism = [RYGSetting navigationCellWithTitle:@"Prism UI" subtitle:@"IGDS / BSLDS design gates and live-discovered BOOL features" icon:[RYGSymbol symbolWithName:@"layout"] viewController:[[RYGDeveloperTopicViewController alloc] initWithSurface:RYGDeveloperRuntimeSurfacePrism]];
    RYGSetting *aura = [RYGSetting navigationCellWithTitle:@"Aura / IGPlus" subtitle:@"Consumer subscription benefits and Plus/Aura gates discovered from loaded owners" icon:[RYGSymbol symbolWithName:@"sparkles"] viewController:[[RYGDeveloperTopicViewController alloc] initWithSurface:RYGDeveloperRuntimeSurfaceConsumerSubs]];
    RYGSetting *stories = [RYGSetting navigationCellWithTitle:@"Story Tray / Story Grid" subtitle:@"Persistent Story Tray, Story Grid and Homecoming gates" icon:[RYGSymbol symbolWithName:@"rectangle.stack"] viewController:[[RYGDeveloperTopicViewController alloc] initWithSurface:RYGDeveloperRuntimeSurfaceStories]];
    RYGSetting *glass = [RYGSetting navigationCellWithTitle:@"Liquid Glass / Throwback" subtitle:@"Swizzle, Throwback Chrome and navigation experiment helpers" icon:[RYGSymbol symbolWithName:@"interface"] viewController:[[RYGDeveloperTopicViewController alloc] initWithSurface:RYGDeveloperRuntimeSurfaceLiquidGlass]];
    RYGSetting *internalOnly = [RYGSetting navigationCellWithTitle:@"IG-only / Internal-only" subtitle:@"Internal visibility owners and loaded classes" icon:[RYGSymbol symbolWithName:@"eye"] viewController:[[RYGDeveloperTopicViewController alloc] initWithSurface:RYGDeveloperRuntimeSurfaceInternalOnly]];
    RYGSetting *bugReport = [RYGSetting navigationCellWithTitle:@"Bug Report / Sandbox" subtitle:@"Logged-out, assistant, internal-settings and sandbox gates" icon:[RYGSymbol symbolWithName:@"bug"] viewController:[[RYGDeveloperTopicViewController alloc] initWithSurface:RYGDeveloperRuntimeSurfaceBugReport]];
    RYGSetting *settingsRows = [RYGSetting navigationCellWithTitle:@"Hidden Settings Rows" subtitle:@"Visibility gates discovered from loaded settings owners" icon:[RYGSymbol symbolWithName:@"list"] viewController:[[RYGDeveloperTopicViewController alloc] initWithSurface:RYGDeveloperRuntimeSurfaceSettingsRows]];
    RYGSetting *dogfood = [RYGSetting navigationCellWithTitle:@"Direct / Dogfooding Settings" subtitle:@"Dogfood owners and internal launch/settings gates" icon:[RYGSymbol symbolWithName:@"paw"] viewController:[[RYGDeveloperTopicViewController alloc] initWithSurface:RYGDeveloperRuntimeSurfaceDirectDogfood]];

    RYGSetting *metaLocal = [RYGSetting buttonCellWithTitle:@"MetaLocalExperiment" subtitle:nil icon:[RYGSymbol symbolWithName:@"insights"] action:^{ [RYGMetaLocalExperimentBrowser presentFromCurrentViewController]; }];
    RYGSetting *runtime = [RYGSetting navigationCellWithTitle:@"Runtime Browser · Live" subtitle:@"Images → classes/subclasses → Objective-C methods and C imports on demand" icon:[RYGSymbol symbolWithName:@"search"] viewController:[RYGFastRuntimeBrowserViewController new]];

    [self applySettingSections:@[
        [RYGSettingsViewController sectionWithHeader:nil footer:nil rows:@[wordmark, easyGating, mobileConfig]],
        [RYGSettingsViewController sectionWithHeader:@"Native / live surfaces" footer:@"Developer hooks are independent from Runtime Browser. Known owners prewarm only after this hub opens; scoped class discovery runs only for the domain you enter." rows:@[liveCatalog, prism, aura, stories, glass, internalOnly, bugReport, settingsRows, dogfood]],
        [RYGSettingsViewController sectionWithHeader:nil footer:nil rows:@[metaLocal, runtime]],
    ]];
}

@end
