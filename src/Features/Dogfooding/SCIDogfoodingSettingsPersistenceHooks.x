// SCIDogfoodingSettingsPersistenceHooks.x
// Native Notes/Dogfooding persistence is handled by SCILauncherClientHook.x,
// which captures the real IGDogfoodingAssistantLauncherClient writes. We do not
// hook IGDogfoodingSettings Swift delegate callbacks here because those callbacks
// are UI-mutation thunks and caused crashes when tapping any Notes option.

#import "SCIDogfoodObjectRuntime.h"
#import <Foundation/Foundation.h>

%ctor {
    @autoreleasepool {
        [SCIDogfoodObjectRuntime noteAction:@"Dogfooding persistence" status:@"using launcher-client hook" detail:@"Swift delegate hooks disabled; persistence is captured from IGDogfoodingAssistantLauncherClient.overrideLauncherWithUserSession:launcherName:parametersToValues:"];
    }
}
