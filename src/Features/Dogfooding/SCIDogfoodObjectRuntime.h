#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>

NS_ASSUME_NONNULL_BEGIN

@interface SCIDogfoodObjectRuntime : NSObject

+ (void)installIfNeeded;
+ (void)noteObject:(nullable id)object role:(NSString *)role source:(nullable NSString *)source;
+ (void)noteSettingsObject:(nullable id)object role:(NSString *)role source:(nullable NSString *)source;
+ (void)noteAction:(NSString *)action status:(NSString *)status detail:(nullable id)detail;
+ (void)noteLiveUserSession:(nullable id)session source:(nullable NSString *)source;

+ (void)noteDogfoodingSettingChangeWithItem:(nullable id)item
                                  options:(nullable id)options
                              toggleValue:(nullable id)toggleValue
                                   source:(nullable NSString *)source;
+ (NSArray<NSDictionary *> *)dogfoodingSettingChanges;

+ (UIViewController *)topViewController;
+ (nullable id)activeUserSession;
+ (nullable id)bestLauncherSet;
+ (nullable id)bestDogfooder;
+ (NSDictionary *)runtimeState;
+ (NSArray<NSDictionary *> *)liveObjectGraph;
+ (NSArray<NSDictionary *> *)runtimeStubsMatching:(nullable NSString *)query limit:(NSUInteger)limit;
+ (NSDictionary *)detailsForRuntimeStubClass:(NSString *)className;
+ (nullable id)liveInstanceOfClass:(Class)cls;
+ (nullable id)liveInstanceOfClassNameContaining:(NSString *)needle;
+ (NSArray<NSDictionary *> *)settingsInjectionTargets;
+ (NSArray<NSDictionary *> *)recentActions;
+ (NSDictionary *)fullSnapshot;
+ (NSDictionary *)fullSnapshotIncludingDetails:(BOOL)includeDetails;
+ (NSDictionary *)detailsForObjectAddress:(NSString *)address;
+ (void)clear;

+ (BOOL)tryOpenNativeDogfoodSettings;
+ (BOOL)tryOpenNotesDogfooding;
+ (BOOL)tryOpenMetaLocalExperimentBrowser;

+ (void)injectRowsIntoSettingsIfPossibleFromViewController:(UIViewController *)vc;

@end

NS_ASSUME_NONNULL_END
