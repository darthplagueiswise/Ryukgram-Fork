#import "RYGDeveloperHubViewController.h"
#import "RYGDeveloperTopicViewController.h"
#import "RYGWordmarkViewController.h"
#import "RYGRuntimeBrowserViewController.h"
#import "RYGEasyGatingViewController.h"
#import "RYGMetaLocalExperimentBrowser.h"
#import "../Features/ExpFlags/RYGMobileConfigToolsViewController.h"
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
                                                      subtitle:nil
                                                          icon:[RYGSymbol symbolWithName:@"instagram"]
                                                viewController:[RYGWordmarkViewController new]];

    RYGSetting *easyGating = [RYGSetting navigationCellWithTitle:@"Easy Gating Internal"
                                                        subtitle:nil
                                                            icon:[RYGSymbol symbolWithName:@"key"]
                                                  viewController:[RYGEasyGatingViewController new]];

    RYGSetting *mobileConfig = [RYGSetting navigationCellWithTitle:@"MobileConfig"
                                                          subtitle:nil
                                                              icon:[RYGSymbol symbolWithName:@"sliders"]
                                                    viewController:[RYGMobileConfigToolsViewController new]];

    RYGSetting *prism = [RYGSetting navigationCellWithTitle:@"Prism UI"
                                                   subtitle:nil
                                                       icon:[RYGSymbol symbolWithName:@"layout"]
                                             viewController:[[RYGDeveloperTopicViewController alloc]
                                                 initWithSurface:RYGDeveloperRuntimeSurfacePrism]];

    RYGSetting *glass = [RYGSetting navigationCellWithTitle:@"Liquid Glass"
                                                   subtitle:nil
                                                       icon:[RYGSymbol symbolWithName:@"interface"]
                                             viewController:[[RYGDeveloperTopicViewController alloc]
                                                 initWithSurface:RYGDeveloperRuntimeSurfaceLiquidGlass]];

    RYGSetting *stories = [RYGSetting navigationCellWithTitle:@"Stories · Tray & Grid"
                                                     subtitle:nil
                                                         icon:[RYGSymbol symbolWithName:@"stories"]
                                               viewController:[[RYGDeveloperTopicViewController alloc]
                                                   initWithSurface:RYGDeveloperRuntimeSurfaceStories]];

    RYGSetting *internalOnly = [RYGSetting navigationCellWithTitle:@"IG-only / Internal-only"
                                                          subtitle:nil
                                                              icon:[RYGSymbol symbolWithName:@"eye"]
                                                    viewController:[[RYGDeveloperTopicViewController alloc]
                                                        initWithSurface:RYGDeveloperRuntimeSurfaceInternalOnly]];

    RYGSetting *bugReport = [RYGSetting navigationCellWithTitle:@"Bug Report"
                                                       subtitle:nil
                                                           icon:[RYGSymbol symbolWithName:@"bug"]
                                                 viewController:[[RYGDeveloperTopicViewController alloc]
                                                     initWithSurface:RYGDeveloperRuntimeSurfaceBugReport]];

    RYGSetting *settingsRows = [RYGSetting navigationCellWithTitle:@"Hidden Settings Rows"
                                                          subtitle:nil
                                                              icon:[RYGSymbol symbolWithName:@"list"]
                                                    viewController:[[RYGDeveloperTopicViewController alloc]
                                                        initWithSurface:RYGDeveloperRuntimeSurfaceSettingsRows]];

    RYGSetting *dogfood = [RYGSetting navigationCellWithTitle:@"Direct Dogfooding Settings"
                                                     subtitle:nil
                                                         icon:[RYGSymbol symbolWithName:@"paw"]
                                               viewController:[[RYGDeveloperTopicViewController alloc]
                                                   initWithSurface:RYGDeveloperRuntimeSurfaceDirectDogfood]];

    RYGSetting *metaLocal = [RYGSetting buttonCellWithTitle:@"MetaLocalExperiment"
                                                   subtitle:nil
                                                       icon:[RYGSymbol symbolWithName:@"insights"]
                                                     action:^{
        [RYGMetaLocalExperimentBrowser presentFromCurrentViewController];
    }];

    RYGSetting *runtime = [RYGSetting navigationCellWithTitle:@"Runtime Browser · Live"
                                                     subtitle:nil
                                                         icon:[RYGSymbol symbolWithName:@"search"]
                                               viewController:[RYGRuntimeBrowserViewController new]];

    NSArray *sections = @[
        [RYGSettingsViewController sectionWithHeader:nil
                                              footer:nil
                                                rows:@[
            wordmark,
            easyGating,
            mobileConfig,
            prism,
            glass,
            stories,
            internalOnly,
            bugReport,
            settingsRows,
            dogfood,
        ]],
        [RYGSettingsViewController sectionWithHeader:nil
                                              footer:nil
                                                rows:@[metaLocal, runtime]],
    ];
    [self applySettingSections:sections];
}

@end
