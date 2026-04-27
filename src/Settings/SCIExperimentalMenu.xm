#import "TweakSettings.h"
#import "SCIExpFlagsViewController.h"
#import "SCIResolverReportViewController.h"
#import "SCIExpFlags.h"   // ← ADD THIS LINE
#import <objc/runtime.h>
#import <objc/message.h>
#import <substrate.h>

static NSArray *(*orig_sections_exp)(id, SEL);

static SCISetting *ExpSwitch(NSString *title, NSString *subtitle, NSString *key, BOOL restart) {
    return [SCISetting switchCellWithTitle:title subtitle:subtitle defaultsKey:key requiresRestart:restart];
}

static UIViewController *RYDevTopViewControllerFrom(UIViewController *vc) {
    UIViewController *cur = vc;
    BOOL changed = YES;
    while (cur && changed) {
        changed = NO;
        if ([cur isKindOfClass:UINavigationController.class]) {
            UIViewController *next = ((UINavigationController *)cur).visibleViewController ?: ((UINavigationController *)cur).topViewController;
            if (next && next != cur) { cur = next; changed = YES; continue; }
        }
        if ([cur isKindOfClass:UITabBarController.class]) {
            UIViewController *next = ((UITabBarController *)cur).selectedViewController;
            if (next && next != cur) { cur = next; changed = YES; continue; }
        }
        UIViewController *presented = cur.presentedViewController;
        if (presented && presented != cur) { cur = presented; changed = YES; }
    }
    return cur;
}

static UIViewController *RYDevRootViewController(void) {
    UIApplication *app = UIApplication.sharedApplication;
    for (UIScene *scene in app.connectedScenes) {
        if (![scene isKindOfClass:UIWindowScene.class]) continue;
        for (UIWindow *window in ((UIWindowScene *)scene).windows) {
            if (window.isKeyWindow && window.rootViewController) return window.rootViewController;
        }
    }
    for (UIScene *scene in app.connectedScenes) {
        if (![scene isKindOfClass:UIWindowScene.class]) continue;
        for (UIWindow *window in ((UIWindowScene *)scene).windows) {
            if (window.rootViewController) return window.rootViewController;
        }
    }
    return nil;
}

static void RYDevCallOpenSelector(NSString *selectorName) {
    UIViewController *top = RYDevTopViewControllerFrom(RYDevRootViewController());
    SEL sel = NSSelectorFromString(selectorName);
    if (top && [top respondsToSelector:sel]) {
        ((void (*)(id, SEL, id))objc_msgSend)(top, sel, nil);
        return;
    }

    // Fallback: these selectors are installed by SCIDogfoodingMainLauncher.xm as an NSObject category.
    id target = top ?: RYDevRootViewController();
    if (target && [target respondsToSelector:sel]) {
        ((void (*)(id, SEL, id))objc_msgSend)(target, sel, nil);
        return;
    }

    UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"Dogfood opener"
                                                                   message:[NSString stringWithFormat:@"Selector %@ is not available. Check that SCIDogfoodingMainLauncher.xm is compiled.", selectorName]
                                                            preferredStyle:UIAlertControllerStyleAlert];
    [alert addAction:[UIAlertAction actionWithTitle:@"OK" style:UIAlertActionStyleCancel handler:nil]];
    [top presentViewController:alert animated:YES completion:nil];
}

static NSArray *experimentalNavSections(void) {
    return @[
        @{
            @"header": @"UI",
            @"footer": @"Normal experimental UI flags. Dev/debug tooling lives in DEV tests.",
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
        }
    ];
}

static void applyInternalOverridesForToggle(NSString *key, BOOL on) {
    SCIExpFlagOverride o = on ? SCIExpFlagOverrideTrue : SCIExpFlagOverrideOff;
    if ([key isEqualToString:@"igt_employee_master"]) {
        [SCIExpFlags setInternalUseOverride:o forSpecifier:0x0081030f00000a95ULL]; // ig_is_employee[0]
        [SCIExpFlags setInternalUseOverride:o forSpecifier:0x0081030f00010a96ULL]; // ig_is_employee[1]
        [SCIExpFlags setInternalUseOverride:o forSpecifier:0x008100b200000161ULL]; // ig_is_employee_or_test_user
    } else if ([key isEqualToString:@"igt_internal_apps_spoof"]) {
        // Specifier para internal apps spoof (se conhecido, caso contrário apenas o hook de símbolo cuidará disso)
        // [SCIExpFlags setInternalUseOverride:o forSpecifier:kInternalAppsSpecifier];
    }
}

static SCISetting *ExpOverrideSwitch(NSString *title, NSString *subtitle, NSString *key, BOOL restart) {
    SCISetting *s = [SCISetting switchCellWithTitle:title subtitle:subtitle defaultsKey:key requiresRestart:restart];
    s.action = ^{
        BOOL on = [[NSUserDefaults standardUserDefaults] boolForKey:key];
        applyInternalOverridesForToggle(key, on);
    };
    return s;
}

static NSArray *devTestsNavSections(void) {
    return @[
        @{
            @"header": @"Internal / Employee Mode",
            @"footer": @"Toggles to activate internal features. Overrides are applied to known specifiers immediately.",
            @"rows": @[
                ExpSwitch(@"Employee Mode (Master)", @"Forces ig_is_employee and ig_is_employee_or_test_user to YES via fishhook", @"igt_employee", YES),
                ExpSwitch(@"Employee MobileConfig Gate", @"Forces ig_is_employee MobileConfig specifier independently", @"igt_employee_mc", YES),
                ExpSwitch(@"Employee or Test User Gate", @"Forces ig_is_employee_or_test_user specifier", @"igt_employee_or_test_user_mc", YES),
                ExpSwitch(@"Developer Options Gate", @"Unlocks developer options menu inside Instagram", @"igt_employee_devoptions_gate", YES),
                ExpSwitch(@"Internal Apps Gate", @"Spoofs IGAppIsInstagramInternalAppsInstalledAndNotHiddenAfteriOS18 to return YES", @"igt_internal_apps_gate", YES),
                ExpSwitch(@"Internal Mode", @"Forces igt_internal flag", @"igt_internal", YES),
                ExpSwitch(@"InternalUse Observer (Logging)", @"Enables verbose NSLog output for all MobileConfig specifier calls", @"igt_internaluse_observer", YES),
                ExpSwitch(@"QuickSnap / Instants", @"Forces all ig_ios_quick_snap and ig_ios_instants specifier groups to YES", @"igt_quicksnap", YES)
            ]
        },
        @{
            @"header": @"Account / system",
            @"footer": @"Risky account/system gates. Employee Master applies real specifier overrides.",
            @"rows": @[
                ExpSwitch(@"Screenshot Blocking", @"Stores a dedicated toggle for future experiment hooks", @"igt_screenshot_block", NO),
                ExpOverrideSwitch(@"Employee Master (Legacy)", @"Master switch for all employee/internal gates. Applies specifier overrides.", @"igt_employee_master", YES),
                ExpOverrideSwitch(@"Internal Apps Spoof", @"Forces IGAppIsInstagramInternalAppsInstalledAndNotHiddenAfteriOS18 to YES.", @"igt_internal_apps_spoof", YES),
                ExpSwitch(@"Runtime MC true patcher", @"Master switch. Runtime patcher only patches symbols enabled below. Restart required", @"igt_runtime_mc_true_patcher", YES),
                ExpSwitch(@"Runtime MC true patcher relaxed", @"Skips first-8-byte pattern validation. Riskier; use only for isolated tests. Restart required", @"igt_runtime_mc_true_patcher_relaxed", YES)
            ]
        },
        @{
            @"header": @"Runtime MC symbols",
            @"footer": @"Master Runtime MC true patcher must also be ON. Legacy MEMMobileConfig/MCQMEM rows were removed because they are not exported in 426.",
            @"rows": @[
                ExpSwitch(@"Patch IG InternalUse bool", @"_IGMobileConfigBooleanValueForInternalUse -> YES", @"igt_runtime_mc_patch_ig_internaluse", YES),
                ExpSwitch(@"Patch IG ForceUpdate", @"_IGMobileConfigForceUpdateConfigs -> YES", @"igt_runtime_mc_patch_ig_force_update", YES),
                ExpSwitch(@"Patch IG SetConfigOverrides", @"_IGMobileConfigSetConfigOverrides -> YES", @"igt_runtime_mc_patch_ig_set_overrides", YES),
                ExpSwitch(@"Patch IG TryUpdate", @"_IGMobileConfigTryUpdateConfigsWithCompletion -> YES", @"igt_runtime_mc_patch_ig_try_update", YES),
                ExpSwitch(@"Patch MCI GetBoolean", @"_MCIMobileConfigGetBoolean -> YES", @"igt_runtime_mc_patch_mci_bool", YES),
                ExpSwitch(@"Patch METAExtensions GetBoolean", @"_METAExtensionsExperimentGetBoolean -> YES", @"igt_runtime_mc_patch_meta_ext_bool", YES),
                ExpSwitch(@"Patch METAExtensions no exposure", @"_METAExtensionsExperimentGetBooleanWithoutExposure -> YES", @"igt_runtime_mc_patch_meta_ext_bool_noexp", YES)
            ]
        },
        @{
            @"header": @"Dogfood native openers",
            @"footer": @"Requires Employee Master or Employee DevOptions gate to be ON. If the opener fails, enable those toggles and restart.",
            @"rows": @[
                [SCISetting buttonCellWithTitle:@"Open Direct Notes Dogfood"
                                       subtitle:@"Calls the native Direct Notes Dogfooding opener with live IGUserSession"
                                           icon:[SCISymbol symbolWithName:@"bolt.circle"]
                                         action:^{ RYDevCallOpenSelector(@"ryDogOpenNotesButtonTapped:"); }],
                [SCISetting buttonCellWithTitle:@"Try Main Dogfood Settings"
                                       subtitle:@"Attempts the native main Dogfood opener path without alloc/init fake config"
                                           icon:[SCISymbol symbolWithName:@"pawprint.circle"]
                                         action:^{ RYDevCallOpenSelector(@"ryDogOpenMainButtonTapped:"); }]
            ]
        },
        @{
            @"header": @"SCI Resolver",
            @"footer": @"DexKit-style iOS resolver. View-only scanner for classes/selectors/ivars and symbol availability. No overrides are applied.",
            @"rows": @[
                [SCISetting navigationCellWithTitle:@"Resolver: Dogfood / Developer candidates"
                                           subtitle:@"Find likely Dogfooding, DeveloperOptions, MetaConfig, InternalSettings and Employee UI builders"
                                               icon:[SCISymbol symbolWithName:@"magnifyingglass"]
                                     viewController:[[SCIResolverReportViewController alloc] initWithKind:SCIResolverReportKindDogfoodDeveloper title:@"Dogfood / Developer candidates"]],
                [SCISetting navigationCellWithTitle:@"Resolver: MobileConfig symbols"
                                           subtitle:@"Check IG/MCI/METAExtensions/MSGC/EasyGating/MCD symbol availability and runtime class candidates"
                                               icon:[SCISymbol symbolWithName:@"point.3.connected.trianglepath.dotted"]
                                     viewController:[[SCIResolverReportViewController alloc] initWithKind:SCIResolverReportKindMobileConfigSymbols title:@"MobileConfig symbols"]],
                [SCISetting navigationCellWithTitle:@"Resolver: Full scan report"
                                           subtitle:@"Full view-only scan report combining Dogfood/Developer and MobileConfig candidates"
                                               icon:[SCISymbol symbolWithName:@"doc.text.magnifyingglass"]
                                     viewController:[[SCIResolverReportViewController alloc] initWithKind:SCIResolverReportKindFull title:@"Full resolver report"]]
            ]
        },
        @{
            @"header": @"Flags Browser",
            @"footer": @"MetaLocalExperiment and IGMobileConfigContextManager browser. When this is enabled, MC observers run automatically; there are no separate observer toggles.",
            @"rows": @[
                ExpSwitch(@"Enable flags browser hooks", @"Installs MetaLocalExperiment, IGMobileConfig observers and safe diagnostics. Restart required", @"sci_exp_flags_enabled", YES),
                [SCISetting navigationCellWithTitle:@"Experimental flags browser"
                                           subtitle:@"Open MetaLocalExperiment / IGMobileConfig browser"
                                               icon:[SCISymbol symbolWithName:@"list.bullet.rectangle"]
                                     viewController:[SCIExpFlagsViewController new]]
            ]
        }
    ];
}

static BOOL rowIsExpFlagsDuplicate(SCISetting *row) {
    if (![row isKindOfClass:[SCISetting class]]) return NO;

    NSString *title = row.title ?: @"";
    NSString *subtitle = row.subtitle ?: @"";
    NSString *key = row.defaultsKey ?: @"";
    NSString *vcName = row.navViewController ? NSStringFromClass([row.navViewController class]) : @"";

    if ([vcName isEqualToString:@"SCIExpFlagsViewController"]) return YES;
    if ([key isEqualToString:@"sci_exp_flags_enabled"] || [key isEqualToString:@"sci_exp_mc_hooks_enabled"]) return YES;

    NSString *joined = [[@[title, subtitle] componentsJoinedByString:@" "] lowercaseString];
    if ([joined containsString:@"exp flags"] ||
        [joined containsString:@"experimental flags"] ||
        [joined containsString:@"flags browser"] ||
        [joined containsString:@"mobileconfig browser"]) {
        return YES;
    }

    return NO;
}

static void cleanAdvancedDuplicateRows(NSMutableArray *rows) {
    for (NSUInteger i = 0; i < rows.count; i++) {
        SCISetting *row = [rows[i] isKindOfClass:[SCISetting class]] ? rows[i] : nil;
        if (!row) continue;

        if (![row.title isEqualToString:@"Advanced"]) continue;
        NSArray *navSections = [row.navSections isKindOfClass:[NSArray class]] ? row.navSections : nil;
        if (!navSections.count) continue;

        NSMutableArray *cleanSections = [NSMutableArray array];
        for (NSDictionary *section in navSections) {
            if (![section isKindOfClass:[NSDictionary class]]) continue;

            NSArray *sectionRows = [section[@"rows"] isKindOfClass:[NSArray class]] ? section[@"rows"] : nil;
            NSMutableArray *cleanRows = [NSMutableArray array];

            for (id item in sectionRows) {
                SCISetting *setting = [item isKindOfClass:[SCISetting class]] ? item : nil;
                if (setting && rowIsExpFlagsDuplicate(setting)) continue;
                [cleanRows addObject:item];
            }

            NSString *header = [section[@"header"] isKindOfClass:[NSString class]] ? section[@"header"] : @"";
            NSString *footer = [section[@"footer"] isKindOfClass:[NSString class]] ? section[@"footer"] : @"";
            NSString *combined = [[@[header, footer] componentsJoinedByString:@" "] lowercaseString];
            BOOL sectionLooksDuplicate = ([combined containsString:@"exp flags"] || [combined containsString:@"experimental flags"] || [combined containsString:@"flags browser"] || [combined containsString:@"mobileconfig browser"]);

            if (sectionLooksDuplicate && cleanRows.count == 0) continue;

            NSMutableDictionary *newSection = [section mutableCopy];
            newSection[@"rows"] = cleanRows;
            [cleanSections addObject:newSection];
        }

        row.navSections = cleanSections;
        rows[i] = row;
    }
}

static NSDictionary *expDevTopSection(void) {
    return @{
        @"header": @"",
        @"rows": @[
            [SCISetting navigationCellWithTitle:@"Experimental"
                                       subtitle:@"LiquidGlass, Homecoming, QuickSnap, Direct Notes and normal feature experiments"
                                           icon:[SCISymbol symbolWithName:@"testtube.2"]
                                    navSections:experimentalNavSections()],
            [SCISetting navigationCellWithTitle:@"DEV tests"
                                       subtitle:@"MobileConfig, account/system gates, runtime MC symbols, resolver and flags browser"
                                           icon:[SCISymbol symbolWithName:@"hammer"]
                                    navSections:devTestsNavSections()]
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

        for (NSInteger r = (NSInteger)newRows.count - 1; r >= 0; r--) {
            id rowObj = newRows[(NSUInteger)r];
            if (![rowObj isKindOfClass:[SCISetting class]]) continue;
            SCISetting *row = (SCISetting *)rowObj;

            if ([row.title isEqualToString:@"Experimental"] || [row.title isEqualToString:@"DEV tests"]) {
                return sections;
            }

            if ([row.title isEqualToString:@"General"]) {
                NSArray *navSections = [row.navSections isKindOfClass:[NSArray class]] ? row.navSections : nil;
                NSMutableArray *newNavSections = [NSMutableArray array];
                for (NSDictionary *navSection in navSections) {
                    NSString *header = [navSection[@"header"] isKindOfClass:[NSString class]] ? navSection[@"header"] : nil;
                    if ([header isEqualToString:@"Experimental features"]) {
                        continue;
                    }
                    [newNavSections addObject:navSection];
                }
                row.navSections = newNavSections;
                newRows[(NSUInteger)r] = row;
            }
        }

        cleanAdvancedDuplicateRows(newRows);

        NSMutableDictionary *newSection = [section mutableCopy];
        newSection[@"rows"] = newRows;
        sections[i] = newSection;
    }

    NSUInteger insertIndex = sections.count;
    if (insertIndex > 0) insertIndex -= 1;
    [sections insertObject:expDevTopSection() atIndex:insertIndex];
    return sections;
}

%ctor {
    Class cls = NSClassFromString(@"SCITweakSettings");
    if (!cls) return;
    Class meta = object_getClass(cls);
    if (!meta) return;
    SEL sel = @selector(sections);
    if (!class_getInstanceMethod(meta, sel)) return;
    MSHookMessageEx(meta, sel, (IMP)new_sections_exp, (IMP *)&orig_sections_exp);
}
