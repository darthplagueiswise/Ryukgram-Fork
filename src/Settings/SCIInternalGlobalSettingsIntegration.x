#import "TweakSettings.h"
#import "SCISetting.h"
#import "SCISymbol.h"
#import "../Utils.h"
#import "../Features/Dogfooding/SCIInternalMenusLauncher.h"
#import <UIKit/UIKit.h>

void SCIInstallEmployeeInternalHooksIfNeeded(void);
void SCIRefreshGraphQLDogfoodForceEnabled(void);
void SCIInstallGraphQLDogfoodForceHooksIfNeeded(void);
void SCIRequestInternalGlobalHooksInstall(void);
NSString *SCIInternalGlobalHookStatus(void);

static UIViewController *SCIInternalGlobalTopViewController(void) {
    UIWindow *window = nil;
    for (UIScene *scene in UIApplication.sharedApplication.connectedScenes) {
        if (![scene isKindOfClass:UIWindowScene.class]) continue;
        if (scene.activationState != UISceneActivationStateForegroundActive) continue;
        for (UIWindow *candidate in ((UIWindowScene *)scene).windows) {
            if (candidate.isKeyWindow) {
                window = candidate;
                break;
            }
        }
        if (window) break;
    }

    UIViewController *top = window.rootViewController;
    while (top.presentedViewController && !top.presentedViewController.isBeingDismissed) {
        top = top.presentedViewController;
    }
    return top;
}

static void SCIInternalGlobalShowStatus(NSString *title, NSString *message) {
    UIViewController *top = SCIInternalGlobalTopViewController();
    if (!top) return;
    UIAlertController *alert = [UIAlertController alertControllerWithTitle:title
        message:message ?: @"No status available"
        preferredStyle:UIAlertControllerStyleAlert];
    [alert addAction:[UIAlertAction actionWithTitle:SCILocalized(@"OK")
        style:UIAlertActionStyleDefault handler:nil]];
    [top presentViewController:alert animated:YES completion:nil];
}

static void SCIInternalGlobalApplyMaster(BOOL on) {
    // Keep the old and new consumers on one canonical preference state.
    [SCIUtils setPref:@(on) forKey:@"sci_employee_internal"];
    [SCIUtils setPref:@(on) forKey:@"sci_force_ig_internal_employee"];
    [SCIUtils setPref:@(on) forKey:@"sci_force_ig_is_employee"];
    [SCIUtils setPref:@NO forKey:@"sci_tier2_employee_internal"];

    SCIInstallEmployeeInternalHooksIfNeeded();
    SCIRefreshGraphQLDogfoodForceEnabled();
    SCIInstallGraphQLDogfoodForceHooksIfNeeded();
    SCIRequestInternalGlobalHooksInstall();
}

static SCISetting *SCIInternalGlobalEntryCell(void) {
    return [SCISetting navigationCellWithTitle:SCILocalized(@"Internal / Dogfood Lab")
        subtitle:SCILocalized(@"Employee identity, Internal Settings, MobileConfig and native menu diagnostics")
        icon:[SCISymbol symbolWithIGName:@"bcn_wrench_outline_24" fallback:@"wrench.and.screwdriver"]
        navSections:@[
            @{
                @"header": SCILocalized(@"Internal Global"),
                @"footer": SCILocalized(@"These controls install only exact, ABI-validated Objective-C hooks. No __TEXT patch and no global runtime scan are used."),
                @"rows": @[
                    [SCISetting switchCellWithTitle:SCILocalized(@"Employee / Internal master")
                        subtitle:SCILocalized(@"Forces the canonical local employee identity and the verified MobileConfig employee parameter")
                        value:^BOOL {
                            return [SCIUtils getBoolPref:@"sci_force_ig_internal_employee"] ||
                                   [SCIUtils getBoolPref:@"sci_employee_internal"];
                        }
                        action:^(BOOL on) {
                            SCIInternalGlobalApplyMaster(on);
                            [SCIUtils showToastForDuration:2.5
                                title:on ? @"Internal Global enabled" : @"Internal Global disabled"
                                subtitle:on ? @"Installing exact identity, MobileConfig and menu hooks" : @"Original results are used"];
                        }],
                    [SCISetting switchCellWithTitle:SCILocalized(@"Internal Settings menu")
                        subtitle:SCILocalized(@"Forces the validated Bug Reporter initializer fields and availability")
                        value:^BOOL { return [SCIUtils getBoolPref:@"sci_force_internal_settings_menu"]; }
                        action:^(BOOL on) {
                            [SCIUtils setPref:@(on) forKey:@"sci_force_internal_settings_menu"];
                            SCIInstallEmployeeInternalHooksIfNeeded();
                            SCIRequestInternalGlobalHooksInstall();
                        }],
                    [SCISetting switchCellWithTitle:SCILocalized(@"Internal Settings while logged out")
                        subtitle:SCILocalized(@"Forces only the independent sessionless Internal Settings route")
                        value:^BOOL { return [SCIUtils getBoolPref:@"sci_force_internal_settings_loggedout"]; }
                        action:^(BOOL on) {
                            [SCIUtils setPref:@(on) forKey:@"sci_force_internal_settings_loggedout"];
                            SCIInstallEmployeeInternalHooksIfNeeded();
                            SCIRequestInternalGlobalHooksInstall();
                        }],
                ]
            },
            @{
                @"header": SCILocalized(@"Validation"),
                @"rows": @[
                    [SCISetting buttonCellWithTitle:SCILocalized(@"Apply Internal Global hooks now")
                        subtitle:SCILocalized(@"Runs bounded exact-class retries for late-loaded Instagram components")
                        icon:[SCISymbol symbolWithName:@"arrow.clockwise"]
                        action:^{
                            SCIRequestInternalGlobalHooksInstall();
                            dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.6 * NSEC_PER_SEC)),
                                           dispatch_get_main_queue(), ^{
                                SCIInternalGlobalShowStatus(@"Internal Global", SCIInternalGlobalHookStatus());
                            });
                        }],
                    [SCISetting buttonCellWithTitle:SCILocalized(@"Internal Global hook status")
                        subtitle:SCILocalized(@"Shows installed MobileConfig, Bug Reporter, opener and XPlugins layers")
                        icon:[SCISymbol symbolWithName:@"checkmark.shield"]
                        action:^{ SCIInternalGlobalShowStatus(@"Internal Global", SCIInternalGlobalHookStatus()); }],
                    [SCISetting buttonCellWithTitle:SCILocalized(@"Open Instagram Debug Menu")
                        subtitle:SCILocalized(@"Reapplies the hooks, dismisses RyukGram and calls the native IGWindow entry point")
                        icon:[SCISymbol symbolWithIGName:@"bcn_bug_outline_24" fallback:@"ladybug"]
                        action:^{
                            SCIRequestInternalGlobalHooksInstall();
                            [SCIInternalMenusLauncher openInstagramDebugMenuWithCompletion:^(NSString *result) {
                                if (![result hasPrefix:@"presented"]) {
                                    SCIInternalGlobalShowStatus(@"Instagram Debug Menu", result);
                                }
                            }];
                        }],
                ]
            }
        ]];
}

%hook SCITweakSettings

+ (NSArray *)sections {
    NSArray *original = %orig;
    NSMutableArray *sections = original ? [original mutableCopy] : [NSMutableArray array];
    NSDictionary *internalSection = @{
        @"header": @"",
        @"rows": @[ SCIInternalGlobalEntryCell() ]
    };
    NSUInteger insertionIndex = sections.count > 0 ? sections.count - 1 : 0;
    [sections insertObject:internalSection atIndex:insertionIndex];
    return sections;
}

%end
