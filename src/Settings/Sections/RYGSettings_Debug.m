#import "RYGSettingsSections.h"
#import "../../Debug/RYGDeveloperHubViewController.h"

@implementation RYGTweakSettings (Section_Debug)

+ (RYGSetting *)debugNavCell {
    // Keep one authoritative Developer entry point. Individual feature surfaces
    // are owned by RYGDeveloperHubViewController so the Settings tree cannot
    // accidentally retain an older controller/hook architecture.
    return [RYGSetting navigationCellWithTitle:@"Developer"
                                      subtitle:nil
                                          icon:[RYGSymbol symbolWithName:@"toolbox"]
                                viewController:[RYGDeveloperHubViewController new]];
}

@end
