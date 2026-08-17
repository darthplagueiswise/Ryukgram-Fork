#import "RYGMobileConfigToolsViewController.h"
#import "RYGMobileConfig.h"
#import "RYGMobileConfigJSONIO.h"
#import "../../Settings/RYGSetting.h"
#import "../../Settings/RYGSymbol.h"
#import <objc/runtime.h>
#import <objc/message.h>

@interface RYGMobileConfig (RYGToolsStatusPrivate)
- (unsigned long long)bestParamIDFor:(RYGMCParam *)param;
- (void *)overridesTableForPid:(unsigned long long)pid;
- (NSString *)ryg_nativePersistenceStatus;
- (NSString *)ryg_nativePersistencePath;
@end

static NSUInteger RYGNativeTableReadyOverrideCount(RYGMobileConfig *mc) {
    NSUInteger ready = 0;
    SEL bestSelector = NSSelectorFromString(@"bestParamIDFor:");
    SEL tableSelector = NSSelectorFromString(@"overridesTableForPid:");
    if (![mc respondsToSelector:bestSelector] || ![mc respondsToSelector:tableSelector]) return 0;
    for (RYGMCConfig *config in mc.allConfigs) {
        for (RYGMCParam *param in config.params) {
            if ([mc overrideStateFor:param] != RYGMCOverrideSet) continue;
            unsigned long long pid = ((unsigned long long (*)(id, SEL, id))objc_msgSend)(mc, bestSelector, param);
            if (pid && ((void *(*)(id, SEL, unsigned long long))objc_msgSend)(mc, tableSelector, pid)) ready++;
        }
    }
    return ready;
}

@implementation RYGMobileConfigToolsViewController (RYGStatus)

- (void)ryg_status_rebuildSections {
    [self ryg_status_rebuildSections];

    NSArray *existing = nil;
    @try { existing = [self valueForKey:@"sections"]; } @catch (__unused id exception) {}
    if (!existing) return;

    RYGMobileConfig *mc = [RYGMobileConfig shared];
    NSUInteger overrides = mc.overrideCount;
    NSUInteger nativeReady = RYGNativeTableReadyOverrideCount(mc);
    NSString *nativeSubtitle = overrides
        ? [NSString stringWithFormat:@"%lu of %lu overridden parameters currently resolve to Instagram's native FBMobileConfigOverridesTable. Reapply retries pending units.",
           (unsigned long)nativeReady, (unsigned long)overrides]
        : @"No RyukGram MobileConfig overrides are currently selected. Native table availability is shown per parameter in the live browser.";

    NSString *path = [mc ryg_nativeOverridesJSONPath];
    NSString *persistSubtitle = path.length
        ? [NSString stringWithFormat:@"Canonical mc_overrides.json\n%@", path]
        : @"Waiting for Instagram's actual Documents/mobileconfig/*.data directory. A parent mobileconfig directory is never accepted as the target.";

    RYGSetting *native = [RYGSetting staticCellWithTitle:@"Native MobileConfig table"
                                                subtitle:nativeSubtitle
                                                    icon:[RYGSymbol symbolWithName:@"sliders"]];
    RYGSetting *disk = [RYGSetting staticCellWithTitle:@"Container persistence"
                                              subtitle:persistSubtitle
                                                  icon:[RYGSymbol symbolWithName:@"document"]];
    NSDictionary *status = [RYGSettingsViewController sectionWithHeader:@"Apply status"
                                                                  footer:@"Runtime application and JSON persistence are intentionally separate operations."
                                                                    rows:@[native, disk]];

    NSMutableArray *sections = [NSMutableArray arrayWithObject:status];
    [sections addObjectsFromArray:existing];
    [self applySettingSections:sections.copy];
}

@end

__attribute__((constructor(160))) static void RYGInstallMobileConfigToolsStatus(void) {
    Class cls = RYGMobileConfigToolsViewController.class;
    Method original = class_getInstanceMethod(cls, @selector(rebuildSections));
    Method replacement = class_getInstanceMethod(cls, @selector(ryg_status_rebuildSections));
    if (original && replacement) method_exchangeImplementations(original, replacement);
}
