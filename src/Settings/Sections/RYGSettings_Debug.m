#import "RYGSettingsSections.h"
#import "../../Debug/RYGDeveloperGateViewController.h"
#import "../../Debug/RYGDeveloperRuntimeBrowserViewController.h"
#import "../../Debug/RYGMetaLocalExperimentBrowser.h"
#import "../../Features/ExpFlags/RYGMobileConfigToolsViewController.h"

@implementation RYGTweakSettings (Section_Debug)

+ (RYGSetting *)debugNavCell {
    RYGSetting *wordmark = [RYGSetting navigationCellWithTitle:@"IGWordMark"
                                                      subtitle:@"1A, 1A Alt, 1B and 1B Alt assets + exact live gates"
                                                          icon:[RYGSymbol symbolWithName:@"instagram"]
                                                viewController:[[RYGDeveloperGateViewController alloc]
                                                    initWithSurface:RYGDeveloperGateSurfaceWordMark]];

    RYGSetting *internal = [RYGSetting navigationCellWithTitle:@"Easy Gating Internal"
                                                      subtitle:@"Employee, internal, dogfood and IG-only gates from the loaded binaries"
                                                          icon:[RYGSymbol symbolWithName:@"key"]
                                                viewController:[[RYGDeveloperGateViewController alloc]
                                                    initWithSurface:RYGDeveloperGateSurfaceInternal]];

    RYGSetting *prism = [RYGSetting navigationCellWithTitle:@"Prism UI"
                                                   subtitle:@"Exact Prism selectors currently loaded by Instagram / FBSharedFramework"
                                                       icon:[RYGSymbol symbolWithName:@"layout"]
                                             viewController:[[RYGDeveloperGateViewController alloc]
                                                 initWithSurface:RYGDeveloperGateSurfacePrism]];

    RYGSetting *glass = [RYGSetting navigationCellWithTitle:@"Liquid Glass"
                                                   subtitle:@"Liquid Glass gates; Throwback is a single option inside"
                                                       icon:[RYGSymbol symbolWithName:@"interface"]
                                             viewController:[[RYGDeveloperGateViewController alloc]
                                                 initWithSurface:RYGDeveloperGateSurfaceLiquidGlass]];

    RYGSetting *metaLocal = [RYGSetting buttonCellWithTitle:@"MetaLocalExperiment"
                                                   subtitle:@"Open Instagram's native MetaLocalExperiment list controller"
                                                       icon:[RYGSymbol symbolWithName:@"insights"]
                                                     action:^{ [RYGMetaLocalExperimentBrowser presentFromCurrentViewController]; }];

    RYGSetting *mobileConfig = [RYGSetting navigationCellWithTitle:@"MobileConfig"
                                                          subtitle:@"Live table, id_name_mapping.json and mc_overrides.json"
                                                              icon:[RYGSymbol symbolWithName:@"sliders"]
                                                    viewController:[RYGMobileConfigToolsViewController new]];

    RYGSetting *runtime = [RYGSetting navigationCellWithTitle:@"Runtime Browser · Live"
                                                     subtitle:@"Choose executable/framework, inspect BOOL gates and observe/override explicitly"
                                                         icon:[RYGSymbol symbolWithName:@"search"]
                                               viewController:[RYGDeveloperRuntimeBrowserViewController new]];

    return [RYGSetting navigationCellWithTitle:@"Developer"
                                      subtitle:@"Exact internal gates, native experiments, MobileConfig and live runtime"
                                          icon:[RYGSymbol symbolWithName:@"toolbox"]
                                   navSections:@[
        [RYGSettingsViewController sectionWithHeader:@"Developer surfaces"
                                              footer:@"Gate pages are backed by methods that exist in the loaded Instagram images. MetaLocalExperiment opens Instagram's native list controller."
                                                rows:@[wordmark, internal, prism, glass, metaLocal]],
        [RYGSettingsViewController sectionWithHeader:@"Runtime & configuration"
                                              footer:@"Runtime observation/forcing is explicit per supported ABI. MobileConfig applies through Instagram's native overrides table and persists the canonical JSON separately."
                                                rows:@[mobileConfig, runtime]],
    ]];
}

@end
