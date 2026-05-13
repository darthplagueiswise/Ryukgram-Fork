#import "TweakSettings.h"
#import "SCIExpFlagsViewController.h"
#import "SCIResolverReportViewController.h"
#import "SCIDogfoodingMainLauncher.h"
#import "SCIDexKitViewController.h"
#import "SCIEnabledExperimentTogglesViewController.h"
#import "SCIExperimentRuntimeBrowserViewController.h"
#import "SCIExpPersistedQueryViewController.h"
#import "SCIMobileConfigBrokerViewController.h"
#import "SCIMobileConfigSymbolObserverViewController.h"
#import "../Features/ExpFlags/SCIExpFlags.h"
#import "../Features/ExpFlags/SCIAutofillInternalDevMode.h"
#import "../Features/ExpFlags/SCIPersistedQueryCatalog.h"
#import <objc/runtime.h>
#import <objc/message.h>
#import <substrate.h>

static NSArray *(*orig_sections_exp)(id, SEL);

static const unsigned long long kIGMCEmployeeSpecifierA = 0x0081030f00000a95ULL;
static const unsigned long long kIGMCEmployeeSpecifierB = 0x0081030f00010a96ULL;
static const unsigned long long kIGMCEmployeeOrTestUserSpecifier = 0x008100b200000161ULL;

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

static void RYSyncDeveloperModeAliases(BOOL on) {
    RYSetBoolPref(@"igt_employee_master", on);
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
        @"igt_runtime_mc_true_patcher_relaxed",
        @"sci_exp_flags_enabled",
        @"sci_exp_mc_hooks_enabled",
        @"sci_exp_mc_c_hooks_enabled",
        @"sci_exp_mc_objc_focus_enabled",
        @"sci_exp_mc_objc_focus_target",
        @"sci_exp_mc_objc_allow_getbool_unary",
        @"igt_internaluse_observer",
        @"igt_runtime_mc_symbol_observer_verbose"
    ];

    for (NSString *key in keys) RYSetBoolPref(key, NO);

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
        for (UIWindow *window in ((UIWindowScene *)scene).windows) if (window.isKeyWindow && window.rootViewController) return window.rootViewController;
    }
    for (UIScene *scene in app.connectedScenes) {
        if (![scene isKindOfClass:UIWindowScene.class]) continue;
        for (UIWindow *window in ((UIWindowScene *)scene).windows) if (window.rootViewController) return window.rootViewController;
    }
    return nil;
}

static void RYDevShowAlert(NSString *title, NSString *message) {
    UIViewController *top = RYDevTopViewControllerFrom(RYDevRootViewController());
    if (!top) return;
    UIAlertController *alert = [UIAlertController alertControllerWithTitle:title ?: @"RyukGram"
                                                                   message:message ?: @""
                                                            preferredStyle:UIAlertControllerStyleAlert];
    [alert addAction:[UIAlertAction actionWithTitle:@"OK" style:UIAlertActionStyleCancel handler:nil]];
    [top presentViewController:alert animated:YES completion:nil];
}

static void RYDevShowAlertWithCopy(NSString *title, NSString *message) {
    UIViewController *top = RYDevTopViewControllerFrom(RYDevRootViewController());
    if (!top) return;
    UIAlertController *alert = [UIAlertController alertControllerWithTitle:title ?: @"RyukGram"
                                                                   message:message ?: @""
                                                            preferredStyle:UIAlertControllerStyleAlert];
    [alert addAction:[UIAlertAction actionWithTitle:@"Copy" style:UIAlertActionStyleDefault handler:^(__unused UIAlertAction *a) {
        UIPasteboard.generalPasteboard.string = message ?: @"";
    }]];
    [alert addAction:[UIAlertAction actionWithTitle:@"OK" style:UIAlertActionStyleCancel handler:nil]];
    [top presentViewController:alert animated:YES completion:nil];
}

static void RYDevOpenMainDogfood(void) {
    UIViewController *top = RYDevTopViewControllerFrom(RYDevRootViewController());
    if (!top) { RYDevShowAlert(@"Dogfood unavailable", @"No active presenter was found."); return; }
    RYDogOpenMainFrom(top);
}

static void RYDevOpenDirectNotesDogfood(void) {
    UIViewController *top = RYDevTopViewControllerFrom(RYDevRootViewController());
    if (!top) { RYDevShowAlert(@"Direct Notes Dogfood unavailable", @"No active presenter was found."); return; }
    RYDogOpenDirectNotesFrom(top);
}

static NSArray *experimentalNavSections(void) {
    return @[
        @{
            @"header": @"UI & Design",
            @"footer": @"Experimental UI features and design system toggles.",
            @"rows": @[
                ExpSwitch(@"Liquid Glass Buttons", @"Enables experimental Liquid Glass button style.", @"liquid_glass_buttons", YES),
                ExpSwitch(@"Liquid Glass Surfaces", @"Enables Liquid Glass tab bar and floating navigation.", @"liquid_glass_surfaces", YES),
                ExpSwitch(@"Homecoming Navigation", @"Forces the new Homecoming navigation style.", @"igt_homecoming", YES),
                ExpSwitch(@"Prism Design System", @"Enables Prism design system experiments.", @"igt_prism", NO),
                ExpSwitch(@"Teen App Icons", @"Hold Instagram logo to change app icon.", @"teen_app_icons", YES),
                ExpSwitch(@"Disable Haptics", @"Disables haptics and vibrations.", @"disable_haptics", NO)
            ]
        },
        @{
            @"header": @"Direct Notes & Inbox",
            @"footer": @"QuickSnap and Direct Notes related experiments.",
            @"rows": @[
                ExpSwitch(@"QuickSnap / Instants", @"Enables QuickSnap helper and related MobileConfig groups.", @"igt_quicksnap", YES),
                ExpSwitch(@"Direct Notes: FriendMap", @"Enables FriendMap / location notes gates.", @"igt_directnotes_friendmap", YES),
                ExpSwitch(@"Direct Notes: Audio Reply", @"Enables Direct Notes audio reply experiments.", @"igt_directnotes_audio_reply", NO),
                ExpSwitch(@"Direct Notes: Avatar Reply", @"Enables Direct Notes avatar reply experiments.", @"igt_directnotes_avatar_reply", NO),
                ExpSwitch(@"Direct Notes: GIFs/Stickers", @"Enables Direct Notes GIF and sticker reply experiments.", @"igt_directnotes_gifs_reply", NO),
                ExpSwitch(@"Direct Notes: Photo Reply", @"Enables Direct Notes photo reply experiments.", @"igt_directnotes_photo_reply", NO)
            ]
        },
        @{
            @"header": @"Feed & Navigation",
            @"footer": @"Feed, tabs and navigation experiments.",
            @"rows": @[
                ExpSwitch(@"Reels First / Second", @"Dedicated toggle for Reels placement experiments.", @"igt_reels_first", NO),
                ExpSwitch(@"Friends Feed", @"Dedicated toggle for friends feed experiments.", @"igt_friends_feed", NO),
                ExpSwitch(@"Tab Swiping", @"Dedicated toggle for tab swiping experiments.", @"igt_tab_swiping", NO),
                ExpSwitch(@"Audio Ramping", @"Dedicated toggle for audio ramping on swipe.", @"igt_audio_ramping", NO),
                ExpSwitch(@"Feed Culling", @"Dedicated toggle for feed culling experiments.", @"igt_feed_culling", NO),
                ExpSwitch(@"Feed Dedup", @"Dedicated toggle for feed deduplication.", @"igt_feed_dedup", NO),
                ExpSwitch(@"Pull to Carrera", @"Dedicated toggle for pull to Carrera experiment.", @"igt_pull_to_carrera", NO),
                ExpSwitch(@"Mutual Interest", @"Mutual Interest feature in Direct Messages.", @"igt_mutual_interest", YES),
                ExpSwitch(@"Icebreaker", @"Icebreaker feature for mutually liked reels.", @"igt_icebreaker", YES),
                ExpSwitch(@"Story Grid", @"Story grid view in profile and tray.", @"igt_story_grid", YES),
                ExpSwitch(@"Stories Tray Decoupling", @"Decouple Stories tray from feed fetch.", @"igt_stories_tray_decoupling", NO),
                ExpSwitch(@"DM Inline Like", @"Inline like button in DM message menu.", @"igt_dm_inline_like", NO),
                ExpSwitch(@"Multiple Notes", @"Allow posting multiple Notes simultaneously.", @"igt_multiple_notes", NO),
                ExpSwitch(@"DN First Note Badge", @"First Note badge indicator.", @"igt_dn_first_badge", NO)
            ]
        }
    ];
}

static NSArray *developerNavSections(void) {
    return @[
        @{
            @"header": @"Employee / Dogfood Bootstrap",
            @"footer": @"Only identity state is persisted here. Runtime C broker hooks and ObjC getter hooks are intentionally not exposed in sideload builds.",
            @"rows": @[
                ExpSwitchAction(@"Enable Employee / Dogfood Mode",
                                @"Stores the known employee/test-user specifier intent. C broker patching is offline-only in sideload.",
                                @"igt_employee_master",
                                YES,
                                ^(BOOL on) { RYSyncDeveloperModeAliases(on); }),
                ExpSwitchAction(@"Spoof Internal Apps",
                                @"Stores internal-app gate intent. Runtime body hooks are not installed from this menu.",
                                @"igt_internal_apps_spoof",
                                YES,
                                ^(BOOL on) { RYSyncInternalAppsAliases(on); })
            ]
        },
        @{
            @"header": @"Native Dogfood Entry Points",
            @"footer": @"Real validated developer selectors in this build. These open native controllers and do not install MC hooks.",
            @"rows": @[
                [SCISetting buttonCellWithTitle:@"Open Main Dogfood Settings"
                                       subtitle:@"Selector: +[IGDogfoodingSettings openWithConfig:onViewController:userSession:]"
                                           icon:[SCISymbol symbolWithName:@"pawprint.circle"]
                                         action:^{ RYDevOpenMainDogfood(); }],
                [SCISetting buttonCellWithTitle:@"Open Direct Notes Dogfood"
                                       subtitle:@"Selector: +[IGDirectNotesDogfoodingSettingsStaticFuncs notesDogfoodingSettingsOpenOnViewController:userSession:]"
                                           icon:[SCISymbol symbolWithName:@"bolt.circle"]
                                         action:^{ RYDevOpenDirectNotesDogfood(); }]
            ]
        },
        @{
            @"header": @"Diagnostics",
            @"footer": @"Read-only mapping tools. MC observers, C broker hooks and ObjC getter hooks were removed from the visible Developer Mode menu to avoid hook stacking.",
            @"rows": @[
                [SCISetting navigationCellWithTitle:@"Meta/Internal Flags Browser"
                                           subtitle:@"MetaLocalExperiment, InternalUse specifiers and already observed values."
                                               icon:[SCISymbol symbolWithName:@"list.bullet.rectangle"]
                                     viewController:[SCIExpFlagsViewController new]],
                [SCISetting navigationCellWithTitle:@"SCI Resolver"
                                           subtitle:@"Full resolver report. Read-only scan; no MC hook is installed from here."
                                               icon:[SCISymbol symbolWithName:@"magnifyingglass"]
                                     viewController:[[SCIResolverReportViewController alloc] initWithKind:SCIResolverReportKindFull title:@"Full Resolver Report"]],
                [SCISetting navigationCellWithTitle:@"DexKit 2.0"
                                           subtitle:@"DexKit-based MobileConfig name resolution and discovery."
                                               icon:[SCISymbol symbolWithName:@"cpu"]
                                     viewController:[SCIDexKitViewController new]],
                [SCISetting navigationCellWithTitle:@"Runtime Browser"
                                           subtitle:@"Browse and search MobileConfig flags at runtime."
                                               icon:[SCISymbol symbolWithName:@"externaldrive.connected.to.line.below"]
                                     viewController:[SCIExperimentRuntimeBrowserViewController new]],
                [SCISetting navigationCellWithTitle:@"MC Broker v2"
                                           subtitle:@"Centralized MobileConfig broker with name resolution."
                                               icon:[SCISymbol symbolWithName:@"server.rack"]
                                     viewController:[SCIMobileConfigBrokerViewController new]],
                [SCISetting navigationCellWithTitle:@"Symbol Observer"
                                           subtitle:@"Observe MobileConfig symbol access in real-time."
                                               icon:[SCISymbol symbolWithName:@"eye"]
                                     viewController:[SCIMobileConfigSymbolObserverViewController new]],
                [SCISetting navigationCellWithTitle:@"Persisted GraphQL Mapping"
                                           subtitle:@"QuickSnap/Instants, Dogfood, Homecoming and client_doc_id operation catalog from schema JSON."
                                               icon:[SCISymbol symbolWithName:@"doc.text.magnifyingglass"]
                                     viewController:[SCIExpPersistedQueryViewController new]],
                [SCISetting buttonCellWithTitle:@"Persisted GraphQL Diagnostic"
                                       subtitle:@"Shows loaded schema source plus priority QuickSnap and Dogfood operation matches."
                                           icon:[SCISymbol symbolWithName:@"list.bullet.clipboard"]
                                         action:^{
                                             [[SCIPersistedQueryCatalog sharedCatalog] reload];
                                             RYDevShowAlertWithCopy(@"Persisted GraphQL", [[SCIPersistedQueryCatalog sharedCatalog] diagnosticReport]);
                                         }],
                [SCISetting buttonCellWithTitle:@"Apply Autofill Defaults"
                                       subtitle:@"Writes Autofill backing defaults for internal dev mode."
                                           icon:[SCISymbol symbolWithName:@"bolt.circle"]
                                         action:^{
                                             [SCIAutofillInternalDevMode applyEnabledToggles];
                                             RYDevShowAlertWithCopy(@"Autofill", [SCIAutofillInternalDevMode statusText]);
                                         }],
                [SCISetting buttonCellWithTitle:@"Autofill Status"
                                       subtitle:@"Backing defaults + selector availability."
                                           icon:[SCISymbol symbolWithName:@"doc.text.magnifyingglass"]
                                         action:^{
                                             RYDevShowAlertWithCopy(@"Autofill", [SCIAutofillInternalDevMode statusText]);
                                         }],
                [SCISetting buttonCellWithTitle:@"Reset Developer Mode State"
                                       subtitle:@"Turns off identity aliases and all legacy MC hook toggles."
                                           icon:[SCISymbol symbolWithName:@"arrow.counterclockwise.circle"]
                                         action:^{
                                             RYResetDeveloperModeState();
                                             RYDevShowAlert(@"Developer Mode reset", @"Dogfood mode, MC hook aliases and internal app spoof aliases were turned off.");
                                         }]
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
    if ([vcName isEqualToString:@"SCIMobileConfigSymbolObserverViewController"]) return YES;
    if ([vcName isEqualToString:@"SCIObjCMobileConfigObserverViewController"]) return YES;
    if ([vcName isEqualToString:@"SCIDexKitCGatesViewController"]) return YES;

    NSArray<NSString *> *hiddenKeys = @[
        @"sci_exp_flags_enabled",
        @"sci_exp_mc_hooks_enabled",
        @"sci_exp_mc_c_hooks_enabled",
        @"sci_exp_mc_objc_focus_enabled",
        @"sci_exp_mc_objc_focus_target",
        @"sci_exp_mc_objc_allow_getbool_unary",
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
        @"igt_runtime_mc_true_patcher_relaxed",
        @"igt_runtime_mc_symbol_observer_verbose"
    ];
    if ([hiddenKeys containsObject:key]) return YES;

    NSString *joined = [[@[title, subtitle] componentsJoinedByString:@" "] lowercaseString];
    return [joined containsString:@"exp flags"] ||
           [joined containsString:@"experimental flags"] ||
           [joined containsString:@"advanced experimental features"] ||
           [joined containsString:@"hidden instagram experiments"] ||
           [joined containsString:@"flags browser"] ||
           [joined containsString:@"mobileconfig browser"] ||
           [joined containsString:@"mobileconfig observer"] ||
           [joined containsString:@"mc override lab"] ||
           [joined containsString:@"mc observer"] ||
           [joined containsString:@"objc getter"] ||
           [joined containsString:@"c broker"] ||
           [joined containsString:@"runtime mc patcher"] ||
           [joined containsString:@"internaluse observer"] ||
           [joined containsString:@"employee mode"] ||
           [joined containsString:@"employee mobileconfig"] ||
           [joined containsString:@"developer options gate"] ||
           [joined containsString:@"internal apps gate"] ||
           [joined containsString:@"dogfood / developer options"] ||
           [joined containsString:@"native dogfood"];
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
            BOOL sectionLooksDuplicate = [combined containsString:@"exp flags"] ||
                                          [combined containsString:@"experimental flags"] ||
                                          [combined containsString:@"advanced experimental features"] ||
                                          [combined containsString:@"hidden instagram experiments"] ||
                                          [combined containsString:@"flags browser"] ||
                                          [combined containsString:@"mobileconfig browser"] ||
                                          [combined containsString:@"mobileconfig observer"] ||
                                          [combined containsString:@"mc override lab"] ||
                                          [combined containsString:@"mc observer"] ||
                                          [combined containsString:@"c broker"] ||
                                          [combined containsString:@"objc getter"] ||
                                          [combined containsString:@"employee"] ||
                                          [combined containsString:@"runtime mc patcher"] ||
                                          [combined containsString:@"internaluse observer"] ||
                                          [combined containsString:@"dogfood / developer options"] ||
                                          [combined containsString:@"native dogfood"];
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
                                       subtitle:@"Dogfood controllers and read-only diagnostics. No MC hook stack."
                                           icon:[SCISymbol symbolWithName:@"hammer"]
                                    navSections:developerNavSections()]
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

            if ([row.title isEqualToString:@"Experimental"] ||
                [row.title isEqualToString:@"Developer Mode"] ||
                [row.title isEqualToString:@"DEV Tests"]) return sections;

            if ([row.title isEqualToString:@"General"]) {
                NSArray *navSections = [row.navSections isKindOfClass:[NSArray class]] ? row.navSections : nil;
                NSMutableArray *newNavSections = [NSMutableArray array];
                for (NSDictionary *navSection in navSections) {
                    NSString *header = [navSection[@"header"] isKindOfClass:[NSString class]] ? navSection[@"header"] : nil;
                    if ([header isEqualToString:@"Experimental features"]) continue;
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
    [SCIAutofillInternalDevMode registerDefaults];
    [SCIPersistedQueryCatalog prewarmInBackground];
    Class cls = NSClassFromString(@"SCITweakSettings");
    if (!cls) return;
    Class meta = object_getClass(cls);
    if (!meta) return;
    SEL sel = @selector(sections);
    if (!class_getInstanceMethod(meta, sel)) return;
    MSHookMessageEx(meta, sel, (IMP)new_sections_exp, (IMP *)&orig_sections_exp);
}
