#import "TweakSettings.h"
#import "SCIExpFlagsViewController.h"
#import "SCIResolverReportViewController.h"
#import "../Features/ExpFlags/SCIExpFlags.h"
#import <objc/runtime.h>
#import <objc/message.h>
#import <substrate.h>

static NSArray *(*orig_sections_exp)(id, SEL);

// ====================== FORWARD DECLARATION ======================
static void applyInternalOverridesForToggle(NSString *key, BOOL on);

// ====================== HELPER FUNCTIONS ======================
static SCISetting *ExpSwitch(NSString *title, NSString *subtitle, NSString *key, BOOL restart) {
    return [SCISetting switchCellWithTitle:title subtitle:subtitle defaultsKey:key requiresRestart:restart];
}

static SCISetting *ExpOverrideSwitch(NSString *title, NSString *subtitle, NSString *key, BOOL restart) {
    SCISetting *s = [SCISetting switchCellWithTitle:title subtitle:subtitle defaultsKey:key requiresRestart:restart];
    s.action = ^{
        BOOL on = [[NSUserDefaults standardUserDefaults] boolForKey:key];
        applyInternalOverridesForToggle(key, on);
    };
    return s;
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

    id target = top ?: RYDevRootViewController();
    if (target && [target respondsToSelector:sel]) {
        ((void (*)(id, SEL, id))objc_msgSend)(target, sel, nil);
        return;
    }

    UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"Dogfood Opener"
                                                                   message:[NSString stringWithFormat:@"Selector %@ not available. Check SCIDogfoodingMainLauncher.xm", selectorName]
                                                            preferredStyle:UIAlertControllerStyleAlert];
    [alert addAction:[UIAlertAction actionWithTitle:@"OK" style:UIAlertActionStyleCancel handler:nil]];
    [top presentViewController:alert animated:YES completion:nil];
}

// ====================== INTERNAL OVERRIDE LOGIC ======================
static void applyInternalOverridesForToggle(NSString *key, BOOL on) {
    SCIExpFlagOverride o = on ? SCIExpFlagOverrideTrue : SCIExpFlagOverrideOff;

    if ([key isEqualToString:@"igt_employee_master"] ||
        [key isEqualToString:@"igt_employee"] ||
        [key isEqualToString:@"igt_employee_mc"] ||
        [key isEqualToString:@"igt_employee_or_test_user_mc"]) {

        [SCIExpFlags setInternalUseOverride:o forSpecifier:0x0081030f00000a95ULL];
        [SCIExpFlags setInternalUseOverride:o forSpecifier:0x0081030f00010a96ULL];
        [SCIExpFlags setInternalUseOverride:o forSpecifier:0x008100b200000161ULL];
    }
    else if ([key isEqualToString:@"igt_internal_apps_spoof"]) {
        // TODO: Add real specifier ID when discovered via SCI Resolver
    }
}

// ====================== EXPERIMENTAL NAV SECTIONS ======================
static NSArray *experimentalNavSections(void) {
    return @[
        @{
            @"header": @"UI & Design",
            @"footer": @"Experimental UI features and design system toggles.",
            @"rows": @[
                ExpSwitch(@"Liquid Glass Buttons", @"Enables experimental liquid glass button style", @"liquid_glass_buttons", YES),
                ExpSwitch(@"Liquid Glass Surfaces", @"Enables liquid glass tab bar and floating navigation", @"liquid_glass_surfaces", YES),
                ExpSwitch(@"Homecoming Navigation", @"Forces the new Homecoming navigation style", @"igt_homecoming", YES),
                ExpSwitch(@"Prism Design System", @"Enables Prism design system experiments", @"igt_prism", NO),
                ExpSwitch(@"Teen App Icons", @"Hold Instagram logo to change app icon", @"teen_app_icons", YES),
                ExpSwitch(@"Disable Haptics", @"Completely disables haptics and vibrations", @"disable_haptics", NO)
            ]
        },
        @{
            @"header": @"Direct Notes & Inbox",
            @"footer": @"QuickSnap and Direct Notes related experiments.",
            @"rows": @[
                ExpSwitch(@"QuickSnap", @"Enables QuickSnap helper and notes tray gates", @"igt_quicksnap", YES),
                ExpSwitch(@"Direct Notes: FriendMap", @"Enables FriendMap / location notes", @"igt_directnotes_friendmap", YES),
                ExpSwitch(@"Direct Notes: Audio Reply", @"Future Direct Notes audio reply hook", @"igt_directnotes_audio_reply", NO),
                ExpSwitch(@"Direct Notes: Avatar Reply", @"Future Direct Notes avatar reply hook", @"igt_directnotes_avatar_reply", NO),
                ExpSwitch(@"Direct Notes: GIFs/Stickers", @"Future Direct Notes GIFs and stickers reply", @"igt_directnotes_gifs_reply", NO),
                ExpSwitch(@"Direct Notes: Photo Reply", @"Future Direct Notes photo reply hook", @"igt_directnotes_photo_reply", NO)
            ]
        },
        @{
            @"header": @"Feed & Navigation",
            @"footer": @"Feed, tabs and navigation experiments.",
            @"rows": @[
                ExpSwitch(@"Reels First / Second", @"Dedicated toggle for future reels experiments", @"igt_reels_first", NO),
                ExpSwitch(@"Friends Feed", @"Dedicated toggle for friends feed experiments", @"igt_friends_feed", NO),
                ExpSwitch(@"Tab Swiping", @"Dedicated toggle for tab swiping experiments", @"igt_tab_swiping", NO),
                ExpSwitch(@"Audio Ramping", @"Dedicated toggle for audio ramping on swipe", @"igt_audio_ramping", NO),
                ExpSwitch(@"Feed Culling", @"Dedicated toggle for feed culling experiments", @"igt_feed_culling", NO),
                ExpSwitch(@"Feed Dedup", @"Dedicated toggle for feed deduplication", @"igt_feed_dedup", NO),
                ExpSwitch(@"Pull to Carrera", @"Dedicated toggle for pull to carrera experiment", @"igt_pull_to_carrera", NO)
            ]
        }
    ];
}

// ====================== DEV TESTS NAV SECTIONS (PROFESSIONAL) ======================
static NSArray *devTestsNavSections(void) {
    return @[
        // === CORE EMPLOYEE MODE ===
        @{
            @"header": @"Core Employee Mode",
            @"footer": @"Most important toggles. These force internal/employee state across the app.",
            @"rows": @[
                ExpOverrideSwitch(@"Employee Master", 
                    @"Master switch — forces ig_is_employee + ig_is_employee_or_test_user + all related gates", 
                    @"igt_employee_master", YES),
                
                ExpOverrideSwitch(@"Employee Mode (Full)", 
                    @"Complete employee unlock using fishhook + specifier overrides", 
                    @"igt_employee", YES),
                
                ExpOverrideSwitch(@"Employee MobileConfig", 
                    @"Forces all MobileConfig employee gates (use with Master)", 
                    @"igt_employee_mc", YES),
            ]
        },
        
        // === ADVANCED GATES ===
        @{
            @"header": @"Advanced Internal Gates",
            @"footer": @"Fine-grained control over specific internal features and developer options.",
            @"rows": @[
                ExpOverrideSwitch(@"Employee or Test User Gate", 
                    @"Forces only the ig_is_employee_or_test_user specifier", 
                    @"igt_employee_or_test_user_mc", YES),
                
                ExpSwitch(@"Developer Options Gate", 
                    @"Unlocks the hidden Developer Options menu inside Instagram", 
                    @"igt_employee_devoptions_gate", YES),
                
                ExpSwitch(@"Internal Mode", 
                    @"Forces the igt_internal experiment flag", 
                    @"igt_internal", YES),
                
                ExpOverrideSwitch(@"Internal Apps Spoof", 
                    @"Spoofs internal apps detection (bypasses many restrictions)", 
                    @"igt_internal_apps_spoof", YES),
                
                ExpSwitch(@"Internal Apps Gate", 
                    @"Enables internal apps detection bypass", 
                    @"igt_internal_apps_gate", YES),
            ]
        },
        
        // === OBSERVERS & DIAGNOSTICS ===
        @{
            @"header": @"Observers & Diagnostics",
            @"footer": @"Logging and debugging tools. Enable when testing or reporting bugs.",
            @"rows": @[
                ExpSwitch(@"InternalUse Observer (Verbose)", 
                    @"Logs every MobileConfig specifier call with full details", 
                    @"igt_internaluse_observer", YES),
                
                ExpSwitch(@"Runtime MC Patcher (Master)", 
                    @"Enables runtime patching of MobileConfig symbols (restart required)", 
                    @"igt_runtime_mc_true_patcher", YES),
                
                ExpSwitch(@"Runtime MC Patcher (Relaxed)", 
                    @"Skips some safety checks — advanced testing only", 
                    @"igt_runtime_mc_true_patcher_relaxed", YES),
            ]
        },
        
        // === SPECIAL FEATURES ===
        @{
            @"header": @"Special Features",
            @"footer": @"QuickSnap, Instants and other internal experimental features.",
            @"rows": @[
                ExpSwitch(@"QuickSnap / Instants Force", 
                    @"Forces all QuickSnap and Instants experiment groups to enabled", 
                    @"igt_quicksnap", YES),
                
                ExpSwitch(@"Screenshot Blocking", 
                    @"Prevents screenshots in sensitive areas (experimental)", 
                    @"igt_screenshot_block", NO),
            ]
        },
        
        // === TOOLS ===
        @{
            @"header": @"Tools & Resolvers",
            @"footer": @"Native Instagram debug tools and our advanced resolver.",
            @"rows": @[
                [SCISetting buttonCellWithTitle:@"Open Direct Notes Dogfood"
                                       subtitle:@"Calls native Direct Notes dogfooding opener"
                                           icon:[SCISymbol symbolWithName:@"bolt.circle"]
                                         action:^{ RYDevCallOpenSelector(@"ryDogOpenNotesButtonTapped:"); }],
                
                [SCISetting buttonCellWithTitle:@"Open Main Dogfood Settings"
                                       subtitle:@"Attempts native main dogfood settings path"
                                           icon:[SCISymbol symbolWithName:@"pawprint.circle"]
                                         action:^{ RYDevCallOpenSelector(@"ryDogOpenMainButtonTapped:"); }],
                
                [SCISetting navigationCellWithTitle:@"SCI Resolver"
                                           subtitle:@"Advanced symbol & MobileConfig resolver (for developers)"
                                               icon:[SCISymbol symbolWithName:@"magnifyingglass"]
                                     viewController:[[SCIResolverReportViewController alloc] initWithKind:SCIResolverReportKindFull title:@"Full Resolver Report"]],
            ]
        },
        
        // === FLAGS BROWSER ===
        @{
            @"header": @"Flags Browser",
            @"footer": @"MetaLocalExperiment and IGMobileConfig live browser.",
            @"rows": @[
                ExpSwitch(@"Enable Flags Browser Hooks", 
                    @"Installs MetaLocalExperiment & MobileConfig observers (restart required)", 
                    @"sci_exp_flags_enabled", YES),
                
                [SCISetting navigationCellWithTitle:@"Experimental Flags Browser"
                                           subtitle:@"Browse and inspect all experiment flags in real time"
                                               icon:[SCISymbol symbolWithName:@"list.bullet.rectangle"]
                                     viewController:[SCIExpFlagsViewController new]],
            ]
        }
    ];
}

// ====================== DUPLICATE CLEANING & FINAL ASSEMBLY ======================
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
            [SCISetting navigationCellWithTitle:@"DEV Tests"
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

            if ([row.title isEqualToString:@"Experimental"] || [row.title isEqualToString:@"DEV Tests"]) {
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
