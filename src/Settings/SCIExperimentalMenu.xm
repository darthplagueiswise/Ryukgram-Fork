#import "TweakSettings.h"
#import "SCIExpFlagsViewController.h"
#import "SCIExperimentRuntimeBrowserViewController.h"
#import "../Features/ExpFlags/SCIAutofillInternalDevMode.h"
#import <objc/runtime.h>
#import <substrate.h>

extern void RGTryUpdateMobileConfigAction(void);
extern void RGForceUpdateMobileConfigAction(void);

static NSArray *(*orig_sections_exp)(id, SEL);

static SCISetting *ExpSwitch(NSString *title, NSString *subtitle, NSString *key, BOOL restart) {
    return [SCISetting switchCellWithTitle:title subtitle:subtitle defaultsKey:key requiresRestart:restart];
}

static SCISetting *ExpButton(NSString *title, NSString *subtitle, NSString *symbol, void (^action)(void)) {
    return [SCISetting buttonCellWithTitle:title subtitle:subtitle icon:[SCISymbol symbolWithName:symbol] action:action];
}

static UIViewController *SCIExpTopViewController(void) {
    UIWindow *window = nil;
    for (UIScene *scene in UIApplication.sharedApplication.connectedScenes) {
        if (![scene isKindOfClass:UIWindowScene.class]) continue;
        for (UIWindow *candidate in ((UIWindowScene *)scene).windows) {
            if (candidate.isKeyWindow) { window = candidate; break; }
        }
        if (window) break;
    }
    UIViewController *vc = window.rootViewController;
    while (vc.presentedViewController) vc = vc.presentedViewController;
    if ([vc isKindOfClass:UINavigationController.class]) vc = ((UINavigationController *)vc).topViewController;
    if ([vc isKindOfClass:UITabBarController.class]) vc = ((UITabBarController *)vc).selectedViewController;
    return vc;
}

static void SCIExpPresentTextAlert(NSString *title, NSString *message) {
    dispatch_async(dispatch_get_main_queue(), ^{
        UIViewController *vc = SCIExpTopViewController();
        if (!vc) return;
        UIAlertController *a = [UIAlertController alertControllerWithTitle:title message:message preferredStyle:UIAlertControllerStyleAlert];
        [a addAction:[UIAlertAction actionWithTitle:@"Copy" style:UIAlertActionStyleDefault handler:^(__unused UIAlertAction *act) {
            UIPasteboard.generalPasteboard.string = message ?: @"";
        }]];
        [a addAction:[UIAlertAction actionWithTitle:@"OK" style:UIAlertActionStyleCancel handler:nil]];
        [vc presentViewController:a animated:YES completion:nil];
    });
}

static NSArray *expNavSections(void) {
    return @[
        @{
            @"header": @"UI",
            @"footer": @"Experimental UI flags. Keep everything off unless you are testing a specific surface.",
            @"rows": @[
                ExpSwitch(@"Enable liquid glass buttons", @"Enables experimental liquid glass buttons", @"liquid_glass_buttons", YES),
                ExpSwitch(@"Enable liquid glass surfaces", @"Enables experimental tab bar and floating navigation surfaces", @"liquid_glass_surfaces", YES),
                ExpSwitch(@"Enable Homecoming UI", @"Forces the Homecoming navigation style", @"igt_homecoming", YES),
                ExpSwitch(@"Enable Prism Design System", @"Stores a dedicated Prism toggle for future hooks", @"igt_prism", NO),
                ExpSwitch(@"Enable teen app icons", @"Hold down on the Instagram logo to change the app icon", @"teen_app_icons", YES),
                ExpSwitch(@"Disable app haptics", @"Disables haptics/vibrations within the app", @"disable_haptics", NO)
            ]
        },
        @{
            @"header": @"Direct Notes & Inbox",
            @"footer": @"QuickSnap and FriendMap hooks are only installed when their toggles are ON at app launch.",
            @"rows": @[
                ExpSwitch(@"Enable QuickSnap", @"Hooks the QuickSnap helper and notes tray gates", @"igt_quicksnap", YES),
                ExpSwitch(@"Direct Notes: FriendMap", @"Hooks FriendMap / location notes gates", @"igt_directnotes_friendmap", YES),
                ExpSwitch(@"Direct Notes: Audio reply", @"Stores a dedicated toggle for future Direct Notes reply hooks", @"igt_directnotes_audio_reply", NO),
                ExpSwitch(@"Direct Notes: Avatar reply", @"Stores a dedicated toggle for future Direct Notes reply hooks", @"igt_directnotes_avatar_reply", NO),
                ExpSwitch(@"Direct Notes: GIFs/Stickers reply", @"Stores a dedicated toggle for future Direct Notes reply hooks", @"igt_directnotes_gifs_reply", NO),
                ExpSwitch(@"Direct Notes: Photo reply", @"Stores a dedicated toggle for future Direct Notes reply hooks", @"igt_directnotes_photo_reply", NO)
            ]
        },
        @{
            @"header": @"Feed, tabs, and navigation",
            @"rows": @[
                ExpSwitch(@"Reels First / Second", @"Stores a dedicated toggle for future experiment hooks", @"igt_reels_first", NO),
                ExpSwitch(@"Friends Feed", @"Stores a dedicated toggle for future experiment hooks", @"igt_friends_feed", NO),
                ExpSwitch(@"Tab Swiping", @"Stores a dedicated toggle for future experiment hooks", @"igt_tab_swiping", NO),
                ExpSwitch(@"Audio Ramping on Swipe", @"Stores a dedicated toggle for future experiment hooks", @"igt_audio_ramping", NO),
                ExpSwitch(@"Feed Culling", @"Stores a dedicated toggle for future experiment hooks", @"igt_feed_culling", NO),
                ExpSwitch(@"Feed Dedup", @"Stores a dedicated toggle for future experiment hooks", @"igt_feed_dedup", NO),
                ExpSwitch(@"Pull to Carrera", @"Stores a dedicated toggle for future experiment hooks", @"igt_pull_to_carrera", NO)
            ]
        },
        @{
            @"header": @"Account / dogfood gates",
            @"footer": @"Filtered hooks only. Employee toggles force known MobileConfig specifiers, not every InternalUse boolean. Restart after changing toggles.",
            @"rows": @[
                ExpSwitch(@"Employee MC: ig_is_employee", @"Forces only _ig_is_employee specifiers to YES", @"igt_employee", YES),
                ExpSwitch(@"Employee/TestUser MC", @"Forces only _ig_is_employee_or_test_user to YES", @"igt_employee_test_user", YES),
                ExpSwitch(@"Internal Apps Installed Gate", @"Pretends Instagram internal apps are installed/not hidden", @"igt_internal", YES),
                ExpSwitch(@"Observe InternalUse MobileConfig", @"Logs InternalUse boolean calls into MC IDs without changing values", @"igt_internaluse_observer", YES),
                ExpSwitch(@"Screenshot Blocking", @"Stores a dedicated toggle for future experiment hooks", @"igt_screenshot_block", NO)
            ]
        },
        @{
            @"header": @"Developer Mode / runtime experiments",
            @"footer": @"Runtime browser scans the loaded Objective-C classes in the main Instagram executable and frameworks. It is view-first: copy/test methods before adding risky hooks.",
            @"rows": @[
                [SCISetting navigationCellWithTitle:@"Runtime experiment browser"
                                           subtitle:@"Search every loaded Experiment/Enabled/BOOL method, property and ivar"
                                               icon:[SCISymbol symbolWithName:@"books.vertical"]
                                     viewController:[SCIExperimentRuntimeBrowserViewController new]],
                ExpSwitch(@"Autofill debug footer", @"Calls IGAutofillInternalSettings setDebugFooterEnabledWithEnabled:YES", @"sci_dev_autofill_debug_footer", NO),
                ExpSwitch(@"Force Bloks experience", @"Calls setForceBloksExperienceOn at launch/foreground", @"sci_dev_autofill_force_bloks", NO),
                ExpSwitch(@"Bloks prefetch", @"Calls setBloksPrefetchEnabledWithEnabled:YES", @"sci_dev_autofill_bloks_prefetch", NO),
                ExpButton(@"Apply Autofill internal now", @"Runs selected Autofill internal actions immediately", @"bolt.circle", ^{
                    [SCIAutofillInternalDevMode applyEnabledToggles];
                    SCIExpPresentTextAlert(@"Autofill Internal Status", [SCIAutofillInternalDevMode statusText]);
                }),
                ExpButton(@"Show Autofill internal status", @"Reads getDebugFooterEnabled, getForceBloksExperience and Bloks getters", @"doc.text.magnifyingglass", ^{
                    SCIExpPresentTextAlert(@"Autofill Internal Status", [SCIAutofillInternalDevMode statusText]);
                })
            ]
        },
        @{
            @"header": @"MobileConfig refresh",
            @"footer": @"Manual actions. Use only after the app is open and stable.",
            @"rows": @[
                ExpButton(@"Try update configs", @"Calls IGMobileConfigTryUpdateConfigsWithCompletion", @"arrow.clockwise", ^{ RGTryUpdateMobileConfigAction(); }),
                ExpButton(@"Force update configs", @"Calls IGMobileConfigForceUpdateConfigs", @"arrow.clockwise.circle", ^{ RGForceUpdateMobileConfigAction(); })
            ]
        },
        @{
            @"header": @"Flags browser",
            @"footer": @"MetaLocalExperiment and IGMobileConfigContextManager browser and manual overrides.",
            @"rows": @[
                ExpSwitch(@"Enable flags browser hooks", @"Installs MetaLocalExperiment and IGMobileConfig observers + overrides", @"sci_exp_flags_enabled", YES),
                [SCISetting navigationCellWithTitle:@"Experimental flags browser"
                                           subtitle:@"Open MetaLocalExperiment / IGMobileConfig browser"
                                               icon:[SCISymbol symbolWithName:@"list.bullet.rectangle"]
                                     viewController:[SCIExpFlagsViewController new]]
            ]
        }
    ];
}

static NSDictionary *expSection(void) {
    return @{
        @"header": @"",
        @"rows": @[
            [SCISetting navigationCellWithTitle:@"Experimental"
                                       subtitle:@""
                                           icon:[SCISymbol symbolWithName:@"testtube.2"]
                                    navSections:expNavSections()]
        ]
    };
}

static NSArray *new_sections_exp(id self, SEL _cmd) {
    NSArray *orig = orig_sections_exp ? orig_sections_exp(self, _cmd) : @[];
    NSMutableArray *sections = [orig mutableCopy] ?: [NSMutableArray array];

    for (NSUInteger i = 0; i < sections.count; i++) {
        NSDictionary *section = [sections[i] isKindOfClass:[NSDictionary class]] ? sections[i] : nil;
        NSArray *rows = [section[@"rows"] isKindOfClass:[NSArray class]] ? section[@"rows"] : nil;
        if (!rows.count) continue;

        NSMutableArray *newRows = [rows mutableCopy];
        BOOL sectionChanged = NO;

        for (NSInteger r = (NSInteger)newRows.count - 1; r >= 0; r--) {
            id rowObj = newRows[(NSUInteger)r];
            if (![rowObj isKindOfClass:[SCISetting class]]) continue;
            SCISetting *row = (SCISetting *)rowObj;

            if ([row.title isEqualToString:@"Experimental"]) {
                return sections;
            }

            if ([row.title isEqualToString:@"General"]) {
                NSArray *navSections = [row.navSections isKindOfClass:[NSArray class]] ? row.navSections : nil;
                NSMutableArray *newNavSections = [NSMutableArray array];
                for (NSDictionary *navSection in navSections) {
                    NSString *header = [navSection[@"header"] isKindOfClass:[NSString class]] ? navSection[@"header"] : nil;
                    if ([header isEqualToString:@"Experimental features"]) {
                        sectionChanged = YES;
                        continue;
                    }
                    [newNavSections addObject:navSection];
                }
                row.navSections = newNavSections;
                newRows[(NSUInteger)r] = row;
            }
        }

        if (sectionChanged) {
            NSMutableDictionary *newSection = [section mutableCopy];
            newSection[@"rows"] = newRows;
            sections[i] = newSection;
        }
    }

    NSUInteger insertIndex = sections.count;
    if (insertIndex > 0) insertIndex -= 1;
    [sections insertObject:expSection() atIndex:insertIndex];
    return sections;
}

%ctor {
    [SCIAutofillInternalDevMode registerDefaults];
    Class cls = NSClassFromString(@"SCITweakSettings");
    if (!cls) return;
    Class meta = object_getClass(cls);
    if (!meta) return;
    SEL sel = @selector(sections);
    if (!class_getInstanceMethod(meta, sel)) return;
    MSHookMessageEx(meta, sel, (IMP)new_sections_exp, (IMP *)&orig_sections_exp);
}
