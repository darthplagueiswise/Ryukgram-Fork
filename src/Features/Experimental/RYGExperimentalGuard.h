// Crash-loop guard + pref registry for igt_* experimental flags.

#import <Foundation/Foundation.h>

@interface RYGExperimentalGuard : NSObject

+ (NSArray<NSString *> *)allPrefKeys;
+ (BOOL)anyEnabled;
+ (void)resetAll;
+ (BOOL)didResetThisLaunch;

@end
