#import "RYGDeveloperHubViewController.h"
#import "RYGDeveloperTopicViewController.h"
#import "RYGDeveloperFeatureCatalog.h"
#import "RYGDeveloperFeatureCatalogViewController.h"
#import "RYGDeveloperHookRegistry.h"
#import "RYGWordmarkViewController.h"
#import "RYGFastRuntimeBrowserViewController.h"
#import "RYGCFunctionsViewController.h"
#import "RYGEasyGatingViewController.h"
#import "RYGMetaLocalExperimentBrowser.h"
#import "../Features/ExpFlags/RYGMobileConfigToolsViewController.h"
#import "../UI/RYGLiquidGlass.h"

@implementation RYGDeveloperHubViewController

- (instancetype)init { return [super initWithTitle:@"Developer"]; }

- (void)viewDidLoad {
    [super viewDidLoad];

    // Cold launch is intentionally untouched. The hub prewarms only a tiny set
    // of known owners after the user explicitly enters Developer; scoped class
    // discovery remains asynchronous and domain-local.
    [[RYGDeveloperFeatureCatalog sharedCatalog] startIfNeeded];
    [[RYGDeveloperFeatureCatalog sharedCatalog] prewarmKnownOwners];
    [[RYGDeveloperHookRegistry sharedRegistry] startIfNeeded];

    [self rebuildSections];
    RYGLiquidGlassApplyToViewController(self);
}

- (RYGDeveloperFeatureCatalogViewController *)catalogForSurface:(RYGDeveloperRuntimeSurface)surface {
    return [[RYGDeveloperFeatureCatalogViewController alloc] initWithSurface:surface];
}

- (void)rebuildSections {
    RYGSetting *wordmark = [RYGSetting navigationCellWithTitle:@"IGWordMark"
                                                     subtitle:@"Native Wordmark families with typed persisted overrides"
                                                         icon:[RYGSymbol symbolWithName:@"instagram"]
                                               viewController:[RYGWordmarkViewController new]];
    RYGSetting *easyGating = [RYGSetting navigationCellWithTitle:@"Easy Gating Internal"
                                                       subtitle:@"Validated internal gate resolution"
                                                           icon:[RYGSymbol symbolWithName:@"key"]
                                                 viewController:[RYGEasyGatingViewController new]];
    RYGSetting *mobileConfig = [RYGSetting navigationCellWithTitle:@"MobileConfig"
                                                         subtitle:@"id_name_mapping + mc_overrides + native active-session path"
                                                             icon:[RYGSymbol symbolWithName:@"sliders"]
                                                   viewController:[RYGMobileConfigToolsViewController new]];

    RYGSetting *liveCatalog = [RYGSetting navigationCellWithTitle:@"Live Feature Catalog"
                                                        subtitle:@"Prism, Aura/IGPlus, Stories, Glass and internal domains · no Runtime Browser required"
                                                            icon:[RYGSymbol symbolWithName:@"list"]
                                                  viewController:[RYGDeveloperFeatureCatalogViewController new]];
    RYGSetting *prism = [RYGSetting navigationCellWithTitle:@"Prism UI"
                                                   subtitle:@"IGDS / BSLDS design gates and live BOOL features"
                                                       icon:[RYGSymbol symbolWithName:@"layout"]
                                             viewController:[self catalogForSurface:RYGDeveloperRuntimeSurfacePrism]];
    RYGSetting *aura = [RYGSetting navigationCellWithTitle:@"Aura / IGPlus"
                                                  subtitle:@"Consumer subscription benefits and Plus/Aura gates"
                                                      icon:[RYGSymbol symbolWithName:@"sparkles"]
                                            viewController:[self catalogForSurface:RYGDeveloperRuntimeSurfaceConsumerSubs]];
    RYGSetting *stories = [RYGSetting navigationCellWithTitle:@"Story Tray / Story Grid"
                                                     subtitle:@"Persistent Story Tray, Story Grid, Homecoming and redesign gates"
                                                         icon:[RYGSymbol symbolWithName:@"rectangle.stack"]
                                               viewController:[self catalogForSurface:RYGDeveloperRuntimeSurfaceStories]];
    RYGSetting *glass = [RYGSetting navigationCellWithTitle:@"Liquid Glass / Throwback"
                                                   subtitle:@"Swizzle, Throwback Chrome and navigation experiment helpers"
                                                       icon:[RYGSymbol symbolWithName:@"interface"]
                                             viewController:[self catalogForSurface:RYGDeveloperRuntimeSurfaceLiquidGlass]];
    RYGSetting *internalOnly = [RYGSetting navigationCellWithTitle:@"IG-only / Internal-only"
                                                          subtitle:@"Internal visibility owners and loaded classes"
                                                              icon:[RYGSymbol symbolWithName:@"eye"]
                                                    viewController:[self catalogForSurface:RYGDeveloperRuntimeSurfaceInternalOnly]];
    RYGSetting *settingsRows = [RYGSetting navigationCellWithTitle:@"Hidden Settings Rows"
                                                          subtitle:@"Visibility gates discovered from loaded settings owners"
                                                              icon:[RYGSymbol symbolWithName:@"list"]
                                                    viewController:[self catalogForSurface:RYGDeveloperRuntimeSurfaceSettingsRows]];

    // These two retain the dedicated exact native presenters/capture hooks.
    // Their BOOL gates are still independently discoverable in Live Catalog.
    RYGSetting *bugReport = [RYGSetting navigationCellWithTitle:@"Bug Report / Sandbox"
                                                       subtitle:@"Logged-out, assistant, internal-settings and sandbox presenters"
                                                           icon:[RYGSymbol symbolWithName:@"bug"]
                                                 viewController:[[RYGDeveloperTopicViewController alloc] initWithSurface:RYGDeveloperRuntimeSurfaceBugReport]];
    RYGSetting *dogfood = [RYGSetting navigationCellWithTitle:@"Direct / Dogfooding Settings"
                                                     subtitle:@"Native Dogfooding settings/presenter plus live gates"
                                                         icon:[RYGSymbol symbolWithName:@"paw"]
                                               viewController:[[RYGDeveloperTopicViewController alloc] initWithSurface:RYGDeveloperRuntimeSurfaceDirectDogfood]];

    RYGSetting *metaLocal = [RYGSetting buttonCellWithTitle:@"MetaLocalExperiment"
                                                  subtitle:nil
                                                      icon:[RYGSymbol symbolWithName:@"insights"]
                                                    action:^{ [RYGMetaLocalExperimentBrowser presentFromCurrentViewController]; }];
    RYGSetting *runtime = [RYGSetting navigationCellWithTitle:@"Runtime Browser · ObjC"
                                                    subtitle:@"Images → classes/subclasses → methods · discovered on demand"
                                                        icon:[RYGSymbol symbolWithName:@"search"]
                                              viewController:[RYGFastRuntimeBrowserViewController new]];
    RYGSetting *cFunctions = [RYGSetting navigationCellWithTitle:@"Runtime Browser · C Functions"
                                                       subtitle:@"Per-image imported functions · force only with ABI predicate evidence"
                                                           icon:[RYGSymbol symbolWithName:@"terminal"]
                                                 viewController:[RYGCFunctionsViewController new]];

    [self applySettingSections:@[
        [RYGSettingsViewController sectionWithHeader:nil footer:nil rows:@[wordmark, easyGating, mobileConfig]],
        [RYGSettingsViewController sectionWithHeader:@"Developer features"
                                              footer:@"Known owners prewarm only after Developer opens. Full image-scoped discovery runs only for the domain you enter; hooks use LC_UUID + class + selector + live type encoding."
                                                rows:@[liveCatalog, prism, aura, stories, glass, internalOnly, bugReport, settingsRows, dogfood]],
        [RYGSettingsViewController sectionWithHeader:@"Runtime inspection"
                                              footer:@"Objective-C and C discovery are independent from the curated Developer hooks. C imports remain inspect-only unless direct call-site evidence proves 0/1 predicate use."
                                                rows:@[metaLocal, runtime, cFunctions]],
    ]];
}

@end
