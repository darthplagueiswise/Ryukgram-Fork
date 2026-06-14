#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>

NS_ASSUME_NONNULL_BEGIN

@interface SCIInternalActions : NSObject

+ (nullable id)liveUserSession;
+ (nullable UIViewController *)topPresentedViewController;

+ (BOOL)openNotesDogfoodSettings:(out NSError **)error;

+ (BOOL)setBloksForceExperienceState:(NSInteger)state error:(out NSError **)error;
+ (NSInteger)bloksForceExperienceState;

+ (BOOL)bloksPrefetchEnabled;
+ (BOOL)setBloksPrefetchEnabled:(BOOL)on error:(out NSError **)error;
+ (BOOL)debugFooterEnabled;
+ (BOOL)setDebugFooterEnabled:(BOOL)on error:(out NSError **)error;

+ (BOOL)forceInternalEmployeeEnabled;
+ (void)setForceInternalEmployeeEnabled:(BOOL)on;

// Legacy wrappers kept for the older Dogfood Runtime browser rows.
+ (NSDictionary *)state;
+ (BOOL)forceBloksExperienceOn;
+ (BOOL)forceBloksExperienceOff;
+ (BOOL)setBloksPrefetchEnabled:(BOOL)enabled;
+ (BOOL)setDebugFooterEnabled:(BOOL)enabled;
+ (BOOL)clearForceBloksExperience;
+ (BOOL)setJsOdNumber:(NSString *)value;

@end

NS_ASSUME_NONNULL_END
