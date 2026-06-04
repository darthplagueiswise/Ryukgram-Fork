#import <Foundation/Foundation.h>

// Level-2 launcher override engine.
// Wraps Swift class IGDogfoodingAssistantLauncherClient and persists
// overrides into FBMobileConfigOverridesTable via the native client.
@interface SCILauncherOverride : NSObject
+ (BOOL)isAvailable;
+ (BOOL)applyLauncher:(NSString *)launcherName
            parameter:(NSString *)parameterName
                value:(id)value;

// Public for the launcher-client hook: write to our persistent store WITHOUT
// invoking the native client (the hook is already inside that call, so calling
// applyLauncher would recurse / double-call orig).
+ (void)persistLauncher:(NSString *)launcherName
              parameter:(NSString *)paramName
                  value:(id)value;
+ (void)removeLauncher:(NSString *)launcherName parameter:(NSString *)parameterName;
+ (void)clearAll;
+ (NSDictionary<NSString *, NSDictionary<NSString *, id> *> *)allOverrides;
+ (NSUInteger)totalOverrideCount;
+ (void)replayPersistedOverrides;
@end
