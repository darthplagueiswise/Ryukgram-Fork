#import "RYGSettingsSections.h"
#import "../../Debug/RYGDeveloperFeatureViewController.h"
#import "../../Debug/RYGRuntimeBrowserViewController.h"
#import "../../Features/ExpFlags/RYGMobileConfigToolsViewController.h"

@implementation RYGTweakSettings (Section_Debug)

+ (RYGSetting *)debugNavCell {
    RYGSetting *wordmark = [RYGSetting navigationCellWithTitle:@"IGWordMark"
                                                      subtitle:@"1A / 1B preview and live wordmark gates"
                                                          icon:[RYGSymbol symbolWithName:@"instagram"]
                                                viewController:[[RYGDeveloperFeatureViewController alloc]
                                                    initWithTitle:@"IGWordMark"
                                                    keywords:@[@"wordmark", @"igds_wordmark", @"BCNWordmark"]
                                                    wordmarkPreview:YES
                                                    allowsRecommendedApply:NO]];

    RYGSetting *internal = [RYGSetting navigationCellWithTitle:@"Easy Gating Internal"
                                                      subtitle:@"Employee, internal, dogfood, metamate and IG-only BOOL gates"
                                                          icon:[RYGSymbol symbolWithName:@"key"]
                                                viewController:[[RYGDeveloperFeatureViewController alloc]
                                                    initWithTitle:@"Easy Gating Internal"
                                                    keywords:@[@"employee", @"internal", @"dogfood", @"dogfooding", @"metamate", @"igonly", @"ig_only"]
                                                    wordmarkPreview:NO
                                                    allowsRecommendedApply:YES]];

    RYGSetting *prism = [RYGSetting navigationCellWithTitle:@"Prism UI"
                                                   subtitle:@"IGDS Prism runtime and MobileConfig options"
                                                       icon:[RYGSymbol symbolWithName:@"layout"]
                                             viewController:[[RYGDeveloperFeatureViewController alloc]
                                                 initWithTitle:@"Prism UI"
                                                 keywords:@[@"prism", @"igdsprism", @"isPrismEnabled", @"isRevertedPrismColorEnabled"]
                                                 wordmarkPreview:NO
                                                 allowsRecommendedApply:YES]];

    RYGSetting *glass = [RYGSetting navigationCellWithTitle:@"Liquid Glass"
                                                   subtitle:@"IGLiquidGlass, IGDSGlassButton and interactive glass gates"
                                                       icon:[RYGSymbol symbolWithName:@"interface"]
                                             viewController:[[RYGDeveloperFeatureViewController alloc]
                                                 initWithTitle:@"Liquid Glass"
                                                 keywords:@[@"liquidglass", @"liquid_glass", @"igdsglass", @"glassbutton", @"IGLiquidGlassInteractiveTabBar", @"lucent"]
                                                 wordmarkPreview:NO
                                                 allowsRecommendedApply:YES]];

    RYGSetting *stories = [RYGSetting navigationCellWithTitle:@"Stories — Tray & Grid"
                                                     subtitle:@"Portable Story Tray, Story Tray and Story Grid"
                                                         icon:[RYGSymbol symbolWithName:@"story"]
                                               viewController:[[RYGDeveloperFeatureViewController alloc]
                                                   initWithTitle:@"Stories — Tray & Grid"
                                                   keywords:@[@"storytray", @"story_tray", @"storiestray", @"storygrid", @"story_grid", @"portableStoryTray"]
                                                   wordmarkPreview:NO
                                                   allowsRecommendedApply:YES]];

    RYGSetting *throwback = [RYGSetting navigationCellWithTitle:@"Liquid Glass Throwback"
                                                       subtitle:@"Throwback feed and alternate header-related gates"
                                                           icon:[RYGSymbol symbolWithName:@"history"]
                                                 viewController:[[RYGDeveloperFeatureViewController alloc]
                                                     initWithTitle:@"Liquid Glass Throwback"
                                                     keywords:@[@"throwback", @"feed_timeline_throwback", @"IGThrowbackFeed", @"header"]
                                                     wordmarkPreview:NO
                                                     allowsRecommendedApply:YES]];

    RYGSetting *igOnly = [RYGSetting navigationCellWithTitle:@"IG-only / Internal-only"
                                                    subtitle:@"Hidden IG-only and internal-only surfaces"
                                                        icon:[RYGSymbol symbolWithName:@"eye_off"]
                                              viewController:[[RYGDeveloperFeatureViewController alloc]
                                                  initWithTitle:@"IG-only / Internal-only"
                                                  keywords:@[@"igonly", @"ig_only", @"internalonly", @"internal_only", @"isInternalOnly", @"IGPartnerAnalyticsIsIGOnly"]
                                                  wordmarkPreview:NO
                                                  allowsRecommendedApply:YES]];

    RYGSetting *bugReport = [RYGSetting navigationCellWithTitle:@"Bug Report"
                                                       subtitle:@"Logged-out, Dogfooding Assistant, internal settings and sandbox gates"
                                                           icon:[RYGSymbol symbolWithName:@"toolbox"]
                                                 viewController:[[RYGDeveloperFeatureViewController alloc]
                                                     initWithTitle:@"Bug Report"
                                                     keywords:@[@"bugreport", @"bug_report", @"dogfoodingassistant", @"dogfooding_assistant", @"loggedout", @"logged_out", @"sandbox", @"rageshake"]
                                                     wordmarkPreview:NO
                                                     allowsRecommendedApply:YES]];

    RYGSetting *hiddenRows = [RYGSetting navigationCellWithTitle:@"Hidden Settings Rows"
                                                        subtitle:@"Visibility gates for internal settings, menus and rows"
                                                            icon:[RYGSymbol symbolWithName:@"settings"]
                                                  viewController:[[RYGDeveloperFeatureViewController alloc]
                                                      initWithTitle:@"Hidden Settings Rows"
                                                      keywords:@[@"settings", @"settingsrow", @"menurow", @"hiddenrow", @"shouldhide", @"shouldshow", @"visible", @"internalsettings"]
                                                      wordmarkPreview:NO
                                                      allowsRecommendedApply:YES]];

    RYGSetting *dogfood = [RYGSetting navigationCellWithTitle:@"Direct Dogfooding Settings"
                                                     subtitle:@"IGDogfoodingSettings, sessions and direct dogfood gates"
                                                         icon:[RYGSymbol symbolWithName:@"users"]
                                               viewController:[[RYGDeveloperFeatureViewController alloc]
                                                   initWithTitle:@"Direct Dogfooding Settings"
                                                   keywords:@[@"IGDogfoodingSettings", @"dogfoodingsettings", @"dogfoodingsessions", @"dogfood", @"dogfooding", @"direct"]
                                                   wordmarkPreview:NO
                                                   allowsRecommendedApply:YES]];

    RYGSetting *localExperiment = [RYGSetting navigationCellWithTitle:@"MetaLocalExperiment"
                                                             subtitle:@"Meta local experiment runtime surface"
                                                                 icon:[RYGSymbol symbolWithName:@"insights"]
                                                       viewController:[[RYGDeveloperFeatureViewController alloc]
                                                           initWithTitle:@"MetaLocalExperiment"
                                                           keywords:@[@"MetaLocalExperiment", @"localexperiment", @"experimentlogger"]
                                                           wordmarkPreview:NO
                                                           allowsRecommendedApply:YES]];

    RYGSetting *mobileConfig = [RYGSetting navigationCellWithTitle:@"MobileConfig"
                                                          subtitle:@"Live table, id_name_mapping.json and mc_overrides.json"
                                                              icon:[RYGSymbol symbolWithName:@"sliders"]
                                                    viewController:[RYGMobileConfigToolsViewController new]];

    RYGSetting *runtime = [RYGSetting navigationCellWithTitle:@"Runtime Browser · Live"
                                                     subtitle:@"Select executable/framework, inspect BOOL gates and Mach-O symbols"
                                                         icon:[RYGSymbol symbolWithName:@"search"]
                                               viewController:[RYGRuntimeBrowserViewController new]];

    return [RYGSetting navigationCellWithTitle:@"Developer"
                                      subtitle:@"Internal surfaces, MobileConfig and live runtime browser"
                                          icon:[RYGSymbol symbolWithName:@"toolbox"]
                                   navSections:@[
        [RYGSettingsViewController sectionWithHeader:@"Developer surfaces"
                                              footer:@"These pages scan only the currently loaded Instagram executable and FBSharedFramework. Opening a page does not install runtime hooks."
                                                rows:@[wordmark, internal, prism, glass, stories, throwback, igOnly, bugReport, hiddenRows, dogfood, localExperiment]],
        [RYGSettingsViewController sectionWithHeader:@"Runtime & configuration"
                                              footer:@"The runtime browser can inspect every loaded app-owned image; MobileConfig works against Instagram's active native override table."
                                                rows:@[mobileConfig, runtime]],
    ]];
}

@end
