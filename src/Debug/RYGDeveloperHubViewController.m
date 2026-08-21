#import "RYGDeveloperHubViewController.h"
#import "RYGDeveloperTopicViewController.h"
#import "RYGWordmarkViewController.h"
#import "RYGFastRuntimeBrowserViewController.h"
#import "RYGEasyGatingViewController.h"
#import "RYGMetaLocalExperimentBrowser.h"
#import "../Features/ExpFlags/RYGFastMobileConfigBrowserViewController.h"
#import "../UI/RYGLiquidGlass.h"

@implementation RYGDeveloperHubViewController
- (instancetype)init { return [super initWithTitle:@"Developer"]; }
- (void)viewDidLoad { [super viewDidLoad]; [RYGDeveloperTopicViewController activatePersistedNativeFeatures]; [self rebuildSections]; RYGLiquidGlassApplyToViewController(self); }
- (void)rebuildSections {
    RYGSetting *wordmark=[RYGSetting navigationCellWithTitle:@"IGWordMark" subtitle:nil icon:[RYGSymbol symbolWithName:@"instagram"] viewController:[RYGWordmarkViewController new]];
    RYGSetting *easy=[RYGSetting navigationCellWithTitle:@"Easy Gating Internal" subtitle:@"Final mapped IDs observed live" icon:[RYGSymbol symbolWithName:@"key"] viewController:[RYGEasyGatingViewController new]];
    RYGSetting *mc=[RYGSetting navigationCellWithTitle:@"MobileConfig" subtitle:@"One-shot runtime snapshot · direct native overrides · import/export" icon:[RYGSymbol symbolWithName:@"sliders"] viewController:[RYGFastMobileConfigBrowserViewController new]];
    RYGSetting *prism=[RYGSetting navigationCellWithTitle:@"Prism / Redesign" subtitle:@"Exact ABI-validated owners" icon:[RYGSymbol symbolWithName:@"layout"] viewController:[[RYGDeveloperTopicViewController alloc]initWithSurface:RYGDeveloperRuntimeSurfacePrism]];
    RYGSetting *glass=[RYGSetting navigationCellWithTitle:@"Liquid Glass" subtitle:@"Native override helpers + Throwback gates" icon:[RYGSymbol symbolWithName:@"interface"] viewController:[[RYGDeveloperTopicViewController alloc]initWithSurface:RYGDeveloperRuntimeSurfaceLiquidGlass]];
    RYGSetting *stories=[RYGSetting navigationCellWithTitle:@"Stories / Story Tray" subtitle:@"Native Story Tray debug + exact gate" icon:[RYGSymbol symbolWithName:@"rectangle.stack"] viewController:[[RYGDeveloperTopicViewController alloc]initWithSurface:RYGDeveloperRuntimeSurfaceStories]];
    RYGSetting *subs=[RYGSetting navigationCellWithTitle:@"SubsConsumer / IGPlus / Aura" subtitle:@"IGConsumerSubsService exact BOOL gates" icon:[RYGSymbol symbolWithName:@"heart"] viewController:[[RYGDeveloperTopicViewController alloc]initWithSurface:RYGDeveloperRuntimeSurfaceConsumerSubs]];
    RYGSetting *internal=[RYGSetting navigationCellWithTitle:@"IG-only / Internal-only" subtitle:@"Exact Bug Reporter visibility ABI" icon:[RYGSymbol symbolWithName:@"eye"] viewController:[[RYGDeveloperTopicViewController alloc]initWithSurface:RYGDeveloperRuntimeSurfaceInternalOnly]];
    RYGSetting *dogfood=[RYGSetting navigationCellWithTitle:@"Dogfooding Mode" subtitle:@"Native menu + EasyGating + name-resolved MobileConfig" icon:[RYGSymbol symbolWithName:@"paw"] viewController:[[RYGDeveloperTopicViewController alloc]initWithSurface:RYGDeveloperRuntimeSurfaceDirectDogfood]];
    // Proven working path: deliberately unchanged.
    RYGSetting *meta=[RYGSetting buttonCellWithTitle:@"MetaLocalExperiment" subtitle:nil icon:[RYGSymbol symbolWithName:@"insights"] action:^{[RYGMetaLocalExperimentBrowser presentFromCurrentViewController];}];
    RYGSetting *runtime=[RYGSetting navigationCellWithTitle:@"Runtime Browser · Live" subtitle:@"Cached ObjC methods + rebindable C import slots · explicit Refresh" icon:[RYGSymbol symbolWithName:@"search"] viewController:[RYGFastRuntimeBrowserViewController new]];
    [self applySettingSections:@[[RYGSettingsViewController sectionWithHeader:nil footer:nil rows:@[wordmark,easy,mc]],[RYGSettingsViewController sectionWithHeader:@"Validated surfaces" footer:nil rows:@[prism,glass,stories,subs,internal,dogfood]],[RYGSettingsViewController sectionWithHeader:nil footer:nil rows:@[meta,runtime]]]];
}
@end
