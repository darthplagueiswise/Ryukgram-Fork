#import "RYGSettingsSections.h"
#import "../../Debug/RYGDeveloperHubViewController.h"

@implementation RYGTweakSettings (Section_Debug)

+ (RYGSetting *)debugNavCell {
    return [RYGSetting navigationCellWithTitle:@"Developer"
                                      subtitle:@"Internal surfaces, MobileConfig and live runtime browser"
                                          icon:[RYGSymbol symbolWithName:@"hammer.fill"]
                                viewController:[RYGDeveloperHubViewController new]];
}

@end
