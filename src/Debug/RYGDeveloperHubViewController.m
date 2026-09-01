#import "RYGDeveloperHubViewController.h"
#import "RYGDeveloperTopicViewController.h"
#import "RYGDeveloperFeatureCatalog.h"
#import "RYGDeveloperFeatureCatalogViewController.h"
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
    // Developer-only prewarm: this is intentionally not part of app cold start.
    // startIfNeeded installs only a cheap dyld generation marker and schedules
    // known-owner scans on a private utility queue. No runtime-wide class walk
    // happens until a catalogue domain is explicitly opened.
    [[RYGDeveloperFeatureCatalog sharedCatalog] startIfNeeded];
    [self rebuildSections];
    RYGLiquidGlassApplyToViewController(self);
}

- (void)rebuildSections {
    RYGSetting *wordmark = [RYGSetting navigationCellWithTitle:@"IGWordMark" subtitle:nil icon:[RYGSymbol symbolWithName:@"instagram"] viewController:[RYGWordmarkViewController new]];
    RYGSetting *easyGating = [RYGSetting navigationCellWithTitle:@"Easy Gating Runtime" subtitle:@"Current wrapper mapper discovered structurally · final IDs observed live" icon:[RYGSymbol symbolWithName:@"key"] viewController:[RYGEasyGatingViewController new]];
    RYGSetting *mobileConfig = [RYGSetting navigationCellWithTitle:@"ABProps / MobileConfig Runtime" subtitle:@"Typed live parameter table · StartupConfigs · portable snapshots" icon:[RYGSymbol symbolWithName:@"sliders"] viewController:[RYGMobileConfigToolsViewController new]];
    RYGSetting *liveCatalog = [RYGSetting navigationCellWithTitle:@"Live Feature Catalog" subtitle:@"Prism, Aura/IGPlus, Stories, Glass and internal domains · no Runtime Browser required" icon:[RYGSymbol symbolWithName:@"list"] viewController:[RYGDeveloperFeatureCatalogViewController new]];
    RYGSetting *prism = [RYGSetting navigationCellWithTitle:@"Prism UI" subtitle:@"Exact setters + on-demand IGDS/BSLDS runtime discovery" icon:[RYGSymbol symbolWithName:@"layout"] viewController:[[RYGDeveloperTopicViewController alloc] initWithSurface:RYGDeveloperRuntimeSurfacePrism]];
    RYGSetting *stories = [RYGSetting navigationCellWithTitle:@"Story Tray / Story Grid" subtitle:@"Exact persistent Story Tray and Dynamic Story Grid gates" icon:[RYGSymbol symbolWithName:@"rectangle.stack"] viewController:[[RYGDeveloperTopicViewController alloc] initWithSurface:RYGDeveloperRuntimeSurfaceStories]];
    RYGSetting *glass = [RYGSetting navigationCellWithTitle:@"Liquid Glass Throwback" subtitle:@"Persistent native Swizzle, Throwback Chrome and Navigation helpers" icon:[RYGSymbol symbolWithName:@"interface"] viewController:[[RYGDeveloperTopicViewController alloc] initWithSurface:RYGDeveloperRuntimeSurfaceLiquidGlass]];
    RYGSetting *internalOnly = [RYGSetting navigationCellWithTitle:@"IG-only / Internal-only" subtitle:@"Exact internal visibility owner + on-demand runtime discovery" icon:[RYGSymbol symbolWithName:@"eye"] viewController:[[RYGDeveloperTopicViewController alloc] initWithSurface:RYGDeveloperRuntimeSurfaceInternalOnly]];
    RYGSetting *bugReport = [RYGSetting navigationCellWithTitle:@"Bug Report Menu" subtitle:@"Logged out, assistant, internal settings, shake and sandbox" icon:[RYGSymbol symbolWithName:@"bug"] viewController:[[RYGDeveloperTopicViewController alloc] initWithSurface:RYGDeveloperRuntimeSurfaceBugReport]];
    RYGSetting *settingsRows = [RYGSetting navigationCellWithTitle:@"Hidden Settings Rows" subtitle:@"On-demand visibility discovery with persisted exact hooks" icon:[RYGSymbol symbolWithName:@"list"] viewController:[[RYGDeveloperTopicViewController alloc] initWithSurface:RYGDeveloperRuntimeSurfaceSettingsRows]];
    RYGSetting *dogfood = [RYGSetting navigationCellWithTitle:@"Direct / Dogfooding Settings" subtitle:@"Native hooks; MobileConfig resolution only when explicitly applied" icon:[RYGSymbol symbolWithName:@"paw"] viewController:[[RYGDeveloperTopicViewController alloc] initWithSurface:RYGDeveloperRuntimeSurfaceDirectDogfood]];
    RYGSetting *metaLocal = [RYGSetting buttonCellWithTitle:@"Meta / Family Local Experiments" subtitle:@"Native list + FDID generator + current Odin family device ID" icon:[RYGSymbol symbolWithName:@"insights"] action:^{ [RYGMetaLocalExperimentBrowser presentFromCurrentViewController]; }];
    RYGSetting *runtime = [RYGSetting navigationCellWithTitle:@"Runtime Browser · Typed" subtitle:@"Images → classes → BOOL, integer, floating-point and object getters; persisted exact hooks" icon:[RYGSymbol symbolWithName:@"search"] viewController:[RYGFastRuntimeBrowserViewController new]];

    [self applySettingSections:@[
        [RYGSettingsViewController sectionWithHeader:nil footer:nil rows:@[wordmark, easyGating, mobileConfig]],
        [RYGSettingsViewController sectionWithHeader:@"Native / live surfaces" footer:@"Bug Report and Dogfooding are opened by IGWindow so Instagram supplies the real sessions, providers and uploader. Broad runtime discovery runs only for the selected domain." rows:@[liveCatalog, prism, stories, glass, internalOnly, bugReport, settingsRows, dogfood]],
        [RYGSettingsViewController sectionWithHeader:nil footer:nil rows:@[metaLocal, runtime]],
    ]];
}

@end
