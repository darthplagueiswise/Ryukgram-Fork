#import "TweakSettings.h"
#import "SCIExpFlagsViewController.h"
#import "SCIResolverReportViewController.h"
#import "SCIMobileConfigSymbolObserverViewController.h"
#import "../Features/ExpFlags/SCIExpFlags.h"
#import <objc/runtime.h>
#import <objc/message.h>
#import <substrate.h>

static NSArray *(*orig_sections_exp)(id, SEL);

// Employee / internal MC specifiers already used by InternalModeHooks.xm
static const unsigned long long kIGMCEmployeeSpecifierA = 0x0081030f00000a95ULL; // ig_is_employee
static const unsigned long long kIGMCEmployeeSpecifierB = 0x0081030f00010a96ULL; // ig_is_employee
static const unsigned long long kIGMCEmployeeOrTestUserSpecifier = 0x008100b200000161ULL; // ig_is_employee_or_test_user

// -----------------------------------------------------------------------------
// Helpers
// -----------------------------------------------------------------------------

static SCISetting *ExpSwitch(NSString *title, NSString *subtitle, NSString *key, BOOL restart) {
    return [SCISetting switchCellWithTitle:title
                                  subtitle:subtitle
                               defaultsKey:key
                           requiresRestart:restart];
}

static SCISetting *ExpSwitchAction(NSString *title, NSString *subtitle, NSString *key, BOOL restart, void (^action)(BOOL on)) {
    SCISetting *s = [SCISetting switchCellWithTitle:title
                                           subtitle:subtitle
                                        defaultsKey:key
                                    requiresRestart:restart];
    s.action = ^{
        BOOL on = [[NSUserDefaults standardUserDefaults] boolForKey:key];
        if (action) action(on);
    };
    return s;
}

static void RYSetBoolPref(NSString *key, BOOL value) {
    if (!key.length) return;
    [[NSUserDefaults standardUserDefaults] setBool:value forKey:key];
}

static void RYRemovePref(NSString *key) {
    if (!key.length) return;
    [[NSUserDefaults standardUserDefaults] removeObjectForKey:key];
}

static void RYSyncDeveloperModeAliases(BOOL on) {
    // Keep old/internal keys compatible with the simplified UI.
    RYSetBoolPref(@"igt_employee", on);
    RYSetBoolPref(@"igt_employee_mc", on);
    RYSetBoolPref(@"igt_employee_or_test_user_mc", on);
    RYSetBoolPref(@"igt_employee_devoptions_gate", on);
    RYSetBoolPref(@"igt_internal", on);

    SCIExpFlagOverride o = on ? SCIExpFlagOverrideTrue : SCIExpFlagOverrideOff;
    [SCIExpFlags setInternalUseOverride:o forSpecifier:kIGMCEmployeeSpecifierA];
    [SCIExpFlags setInternalUseOverride:o forSpecifier:kIGMCEmployeeSpecifierB];
    [SCIExpFlags setInternalUseOverride:o forSpecifier:kIGMCEmployeeOrTestUserSpecifier];
}

static void RYSyncInternalAppsAliases(BOOL on) {
    RYSetBoolPref(@"igt_internal_apps_gate", on);
}

static void RYSyncForceGateAliases(BOOL on) {
    if (!on) {
        // The old "relaxed" mode is intentionally hidden. Turning the main force
        // switch off also clears relaxed so a stale value cannot keep forcing.
        RYSetBoolPref(@"igt_runtime_mc_true_patcher_relaxed", NO);
    }
}

static void RYResetDeveloperModeState(void) {
    NSArray<NSString *> *keys = @[
        @"igt_employee_master",
        @"igt_employee",
        @"igt_employee_mc",
        @"igt_employee_or_test_user_mc",
        @"igt_employee_devoptions_gate",
        @"igt_internal",
        @"igt_internal_apps_spoof",
        @"igt_internal_apps_gate",
        @"igt_runtime_mc_true_patcher",
        @"igt_runtime_mc_true_patcher_relaxed"
    ];

    for (NSString *key in keys) {
        RYSetBoolPref(key, NO);
    }

    [SCIExpFlags setInternalUseOverride:SCIExpFlagOverrideOff forSpecifier:kIGMCEmployeeSpecifierA];
    [SCIExpFlags setInternalUseOverride:SCIExpFlagOverrideOff forSpecifier:kIGMCEmployeeSpecifierB];
    [SCIExpFlags setInternalUseOverride:SCIExpFlagOverrideOff forSpecifier:kIGMCEmployeeOrTestUserSpecifier];

    [[NSUserDefaults standardUserDefaults] synchronize];
}

static UIViewController *RYDevTopViewControllerFrom(UIViewController *vc) {
    UIViewController *cur = vc;
    BOOL changed = YES;

    while (cur && changed) {
        changed = NO;

        if ([cur isKindOfClass:UINavigationController.class]) {
            UIViewController *next = ((UINavigationController *)cur).visibleViewController ?: ((UINavigationController *)cur).topViewController;
            if (next && next != cur) {
                cur = next;
                changed = YES;
                continue;
            }
        }

        if ([cur isKindOfClass:UITabBarController.class]) {
            UIViewController *next = ((UITabBarController *)cur).selectedViewController;
            if (next && next != cur) {
                cur = next;
                changed = YES;
                continue;
            }
        }

        UIViewController *presented = cur.presentedViewController;
        if (presented && presented != cur) {
            cur = presented;
            changed = YES;
        }
    }

    return cur;
}

static UIViewController *RYDevRootViewController(void) {
    UIApplication *app = UIApplication.sharedApplication;

    for (UIScene *scene in app.connectedScenes) {
        if (![scene isKindOfClass:UIWindowScene.class]) continue;

        for (UIWindow *window in ((UIWindowScene *)scene).windows) {
            if (window.isKeyWindow && window.rootViewController) {
                return window.rootViewController;
            }
        }
    }

    for (UIScene *scene in app.connectedScenes) {
        if (![scene isKindOfClass:UIWindowScene.class]) continue;

        for (UIWindow *window in ((UIWindowScene *)scene).windows) {
            if (window.rootViewController) {
                return window.rootViewController;
            }
        }
    }

    return nil;
}

static void RYDevShowAlert(NSString *title, NSString *message) {
    UIViewController *top = RYDevTopViewControllerFrom(RYDevRootViewController());
    if (!top) return;

    UIAlertController *alert = [UIAlertController alertControllerWithTitle:title ?: @"RyukGram"
                                                                   message:message ?: @""
                                                            preferredStyle:UIAlertControllerStyleAlert];

    [alert addAction:[UIAlertAction actionWithTitle:@"OK"
                                              style:UIAlertActionStyleCancel
                                            handler:nil]];

    [top presentViewController:alert animated:YES completion:nil];
}

static void RYDevCallOpenSelector(NSString *selectorName) {
    UIViewController *top = RYDevTopViewControllerFrom(RYDevRootViewController());
    SEL sel = NSSelectorFromString(selectorName);

    if (top && [top respondsToSelector:sel]) {
        ((void (*)(id, SEL, id))objc_msgSend)(top, sel, nil);
        return;
    }

    id target = top ?: RYDevRootViewController();

    if (target && [target respondsToSelector:sel]) {
        ((void (*)(id, SEL, id))objc_msgSend)(target, sel, nil);
        return;
    }

    RYDevShowAlert(@"Native tool unavailable",
                   [NSString stringWithFormat:@"Selector %@ is not available in the current runtime.", selectorName]);
}

// -----------------------------------------------------------------------------
// Normal experimental menu
// -----------------------------------------------------------------------------

static NSArray *experimentalNavSections(void) {
    return @[
        @{
            @"header": @"UI & Design",
            @"footer": @"Experimental UI features and design system toggles.",
            @"rows": @[
                ExpSwitch(@"Liquid Glass Buttons",
                          @"Enables experimental Liquid Glass button style.",
                          @"liquid_glass_buttons",
                          YES),

                ExpSwitch(@"Liquid Glass Surfaces",
                          @"Enables Liquid Glass tab bar and floating navigation.",
                          @"liquid_glass_surfaces",
                          YES),

                ExpSwitch(@"Homecoming Navigation",
                          @"Forces the new Homecoming navigation style.",
                          @"igt_homecoming",
                          YES),

                ExpSwitch(@"Prism Design System",
                          @"Enables Prism design system experiments.",
                          @"igt_prism",
                          NO),

                ExpSwitch(@"Teen App Icons",
                          @"Hold Instagram logo to change app icon.",
                          @"teen_app_icons",
                          YES),

                ExpSwitch(@"Disable Haptics",
                          @"Disables haptics and vibrations.",
                          @"disable_haptics",
                          NO)
            ]
        },

        @{
            @"header": @"Direct Notes & Inbox",
            @"footer": @"QuickSnap and Direct Notes related experiments.",
            @"rows": @[
                ExpSwitch(@"QuickSnap / Instants",
                          @"Enables QuickSnap helper and related MobileConfig groups.",
                          @"igt_quicksnap",
                          YES),

                ExpSwitch(@"Direct Notes: FriendMap",
                          @"Enables FriendMap / location notes gates.",
                          @"igt_directnotes_friendmap",
                          YES),

                ExpSwitch(@"Direct Notes: Audio Reply",
                          @"Enables Direct Notes audio reply experiments.",
                          @"igt_directnotes_audio_reply",
                          NO),

                ExpSwitch(@"Direct Notes: Avatar Reply",
                          @"Enables Direct Notes avatar reply experiments.",
                          @"igt_directnotes_avatar_reply",
                          NO),

                ExpSwitch(@"Direct Notes: GIFs/Stickers",
                          @"Enables Direct Notes GIF and sticker reply experiments.",
                          @"igt_directnotes_gifs_reply",
                          NO),

                ExpSwitch(@"Direct Notes: Photo Reply",
                          @"Enables Direct Notes photo reply experiments.",
                          @"igt_directnotes_photo_reply",
                          NO)
            ]
        },

        @{
            @"header": @"Feed & Navigation",
            @"footer": @"Feed, tabs and navigation experiments.",
            @"rows": @[
                ExpSwitch(@"Reels First / Second",
                          @"Dedicated toggle for Reels placement experiments.",
                          @"igt_reels_first",
                          NO),

                ExpSwitch(@"Friends Feed",
                          @"Dedicated toggle for friends feed experiments.",
                          @"igt_friends_feed",
                          NO),

                ExpSwitch(@"Tab Swiping",
                          @"Dedicated toggle for tab swiping experiments.",
                          @"igt_tab_swiping",
                          NO),

                ExpSwitch(@"Audio Ramping",
                          @"Dedicated toggle for audio ramping on swipe.",
                          @"igt_audio_ramping",
                          NO),

                ExpSwitch(@"Feed Culling",
                          @"Dedicated toggle for feed culling experiments.",
                          @"igt_feed_culling",
                          NO),

                ExpSwitch(@"Feed Dedup",
                          @"Dedicated toggle for feed deduplication.",
                          @"igt_feed_dedup",
                          NO),

                ExpSwitch(@"Pull to Carrera",
                          @"Dedicated toggle for pull to Carrera experiment.",
                          @"igt_pull_to_carrera",
                          NO)
            ]
        }
    ];
}

// -----------------------------------------------------------------------------
// Simplified developer menu
// -----------------------------------------------------------------------------

static NSArray *developerNavSections(void) {
    return @[
        @{
            @"header": @"Developer Mode",
            @"footer": @"Small set of high-level toggles. Old Employee/MC/Internal switches are now treated as internal aliases.",
            @"rows": @[
                ExpSwitchAction(@"Enable Developer/Internal Mode",
                                @"Forces known employee, test-user and dogfood identity gates.",
                                @"igt_employee_master",
                                YES,
                                ^(BOOL on) {
                                    RYSyncDeveloperModeAliases(on);
                                }),

                ExpSwitchAction(@"Force MobileConfig Boolean Gates",
                                @"Forces MCI, META Extensions, MSGC and EasyGating boolean gates to YES. DVM adapter remains observe-only.",
                                @"igt_runtime_mc_true_patcher",
                                YES,
                                ^(BOOL on) {
                                    RYSyncForceGateAliases(on);
                                }),

                ExpSwitchAction(@"Spoof Internal Apps",
                                @"Makes Instagram think internal Meta apps are installed and visible.",
                                @"igt_internal_apps_spoof",
                                YES,
                                ^(BOOL on) {
                                    RYSyncInternalAppsAliases(on);
                                })
            ]
        },

        @{
            @"header": @"Diagnostics",
            @"footer": @"Use these first when mapping unknown gates. Safe observer mode does not change return values.",
            @"rows": @[
                ExpSwitch(@"Enable Flags Browser",
                          @"Installs MetaLocalExperiment and MobileConfig observers. Safe, restart required.",
                          @"sci_exp_flags_enabled",
                          YES),

                ExpSwitch(@"Verbose Gate Logging",
                          @"Logs every observed gate call to console. Debug only, restart required.",
                          @"igt_internaluse_observer",
                          YES),

                [SCISetting navigationCellWithTitle:@"Experimental Flags Browser"
                                           subtitle:@"Inspect observed gates and set manual per-gate overrides."
                                               icon:[SCISymbol symbolWithName:@"list.bullet.rectangle"]
                                     viewController:[SCIExpFlagsViewController new]],

                [SCISetting navigationCellWithTitle:@"MobileConfig Observer"
                                           subtitle:@"Would change, category filters, JSON/CSV export and runtime id_name_mapping import."
                                               icon:[SCISymbol symbolWithName:@"waveform.path.ecg.rectangle"]
                                     viewController:[SCIMobileConfigSymbolObserverViewController new]],

                [SCISetting navigationCellWithTitle:@"SCI Resolver"
                                           subtitle:@"Full symbol and MobileConfig resolver report."
                                               icon:[SCISymbol symbolWithName:@"magnifyingglass"]
                                     viewController:[[SCIResolverReportViewController alloc] initWithKind:SCIResolverReportKindFull
                                                                                                    title:@"Full Resolver Report"]]
            ]
        },

        @{
            @"header": @"Native Tools",
            @"footer": @"These call native Instagram dogfood/debug entry points when present in the loaded app build.",
            @"rows": @[
                [SCISetting buttonCellWithTitle:@"Open Direct Notes Dogfood"
                                       subtitle:@"Calls native Direct Notes dogfooding opener."
                                           icon:[SCISymbol symbolWithName:@"bolt.circle"]
                                         action:^{
                                             RYDevCallOpenSelector(@"ryDogOpenNotesButtonTapped:");
                                         }],

                [SCISetting buttonCellWithTitle:@"Open Main Dogfood Settings"
                                       subtitle:@"Attempts native main dogfood settings path."
                                           icon:[SCISymbol symbolWithName:@"pawprint.circle"]
                                         action:^{
                                             RYDevCallOpenSelector(@"ryDogOpenMainButtonTapped:");
                                         }],

                [SCISetting buttonCellWithTitle:@"Reset Developer Mode State"
                                       subtitle:@"Turns off hidden legacy aliases and clears employee/test-user overrides."
                                           icon:[SCISymbol symbolWithName:@"arrow.counterclockwise.circle"]
                                         action:^{
                                             RYResetDeveloperModeState();
                                             RYDevShowAlert(@"Developer Mode reset",
                                                            @"Developer/Internal Mode, Force Gates, Internal Apps spoof and hidden legacy aliases were turned off.");
                                         }]
            ]
        }
    ];
}

// -----------------------------------------------------------------------------
// Duplicate cleanup
// -----------------------------------------------------------------------------

static BOOL rowIsExpFlagsDuplicate(SCISetting *row) {
    if (![row isKindOfClass:[SCISetting class]]) return NO;

    NSString *title = row.title ?: @"";
    NSString *subtitle = row.subtitle ?: @"";
    NSString *key = row.defaultsKey ?: @"";
    NSString *vcName = row.navViewController ? NSStringFromClass([row.navViewController class]) : @"";

    if ([vcName isEqualToString:@"SCIExpFlagsViewController"]) return YES;

    NSArray<NSString *> *hiddenKeys = @[
        @"sci_exp_flags_enabled",
        @"sci_exp_mc_hooks_enabled",
        @"igt_employee_master",
        @"igt_employee",
        @"igt_employee_mc",
        @"igt_employee_or_test_user_mc",
        @"igt_employee_devoptions_gate",
        @"igt_internal",
        @"igt_internal_apps_spoof",
        @"igt_internal_apps_gate",
        @"igt_internaluse_observer",
        @"igt_runtime_mc_true_patcher",
        @"igt_runtime_mc_true_patcher_relaxed"
    ];

    if ([hiddenKeys containsObject:key]) return YES;

    NSString *joined = [[@[title, subtitle] componentsJoinedByString:@" "] lowercaseString];

    if ([joined containsString:@"exp flags"] ||
        [joined containsString:@"experimental flags"] ||
        [joined containsString:@"flags browser"] ||
        [joined containsString:@"mobileconfig browser"] ||
        [joined containsString:@"employee mode"] ||
        [joined containsString:@"employee mobileconfig"] ||
        [joined containsString:@"developer options gate"] ||
        [joined containsString:@"runtime mc patcher"] ||
        [joined containsString:@"internal apps gate"] ||
        [joined containsString:@"internaluse observer"]) {
        return YES;
    }

    return NO;
}

static void cleanAdvancedDuplicateRows(NSMutableArray *rows) {
    for (NSUInteger i = 0; i < rows.count; i++) {
        SCISetting *row = [rows[i] isKindOfClass:[SCISetting class]] ? rows[i] : nil;
        if (!row) continue;

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

            BOOL sectionLooksDuplicate =
                [combined containsString:@"exp flags"] ||
                [combined containsString:@"experimental flags"] ||
                [combined containsString:@"flags browser"] ||
                [combined containsString:@"mobileconfig browser"] ||
                [combined containsString:@"employee"] ||
                [combined containsString:@"runtime mc patcher"] ||
                [combined containsString:@"internaluse observer"];

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
                                       subtitle:@"LiquidGlass, Homecoming, QuickSnap, Direct Notes and UI experiments."
                                           icon:[SCISymbol symbolWithName:@"testtube.2"]
                                    navSections:experimentalNavSections()],

            [SCISetting navigationCellWithTitle:@"Developer Mode"
                                       subtitle:@"Internal identity, MobileConfig gates, observers and native debug tools."
                                           icon:[SCISymbol symbolWithName:@"hammer"]
                                    navSections:developerNavSections()]
        ]
    };
}

// -----------------------------------------------------------------------------
// Install into SCITweakSettings.sections
// -----------------------------------------------------------------------------

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

            // Already injected.
            if ([row.title isEqualToString:@"Experimental"] ||
                [row.title isEqualToString:@"Developer Mode"] ||
                [row.title isEqualToString:@"DEV Tests"]) {
                return sections;
            }

            // Remove older Experimental features section from General to avoid duplicates.
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
