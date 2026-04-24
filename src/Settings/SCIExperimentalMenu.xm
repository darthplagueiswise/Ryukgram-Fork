#import "TweakSettings.h"
#import "SCIExpFlagsViewController.h"
#import <objc/runtime.h>
#import <substrate.h>

extern void RGTriggerMobileConfigTryUpdate(void);
extern void RGTriggerMobileConfigForceUpdate(void);

static NSArray *(*orig_sections_exp)(id, SEL);

static SCISetting *ExpSwitch(NSString *title, NSString *subtitle, NSString *key, BOOL restart) {
    return [SCISetting switchCellWithTitle:title subtitle:subtitle defaultsKey:key requiresRestart:restart];
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
            @"header": @"Account / system",
            @"rows": @[
                ExpSwitch(@"Screenshot Blocking", @"Stores a dedicated toggle for future experiment hooks", @"igt_screenshot_block", NO),
                ExpSwitch(@"Employee MC: ig_is_employee", @"Forces ig_is_employee MobileConfig specifiers to YES (restart required)", @"igt_employee_mc", YES),
                ExpSwitch(@"Employee/TestUser MC: ig_is_employee_or_test_user", @"Forces ig_is_employee_or_test_user MobileConfig specifier to YES (restart required)", @"igt_employee_or_test_user_mc", YES),
                ExpSwitch(@"Internal Apps Installed Gate", @"Forces IGAppIsInstagramInternalAppsInstalledAndNotHiddenAfteriOS18 to YES (restart required)", @"igt_internal_apps_gate", YES),
                ExpSwitch(@"Observe InternalUse MobileConfig", @"Logs InternalUse/sessionless InternalUse boolean specifiers (restart required)", @"igt_internaluse_observer", YES)
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
                                     viewController:[SCIExpFlagsViewController new]],
                [SCISetting buttonCellWithTitle:@"Try Update Configs"
                                       subtitle:@"Calls IGMobileConfigTryUpdateConfigsWithCompletion"
                                           icon:[SCISymbol symbolWithName:@"arrow.clockwise"]
                                         action:^{ RGTriggerMobileConfigTryUpdate(); }],
                [SCISetting buttonCellWithTitle:@"Force Update Configs"
                                       subtitle:@"Calls IGMobileConfigForceUpdateConfigs"
                                           icon:[SCISymbol symbolWithName:@"exclamationmark.arrow.triangle.2.circlepath"]
                                         action:^{ RGTriggerMobileConfigForceUpdate(); }]
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
    Class cls = NSClassFromString(@"SCITweakSettings");
    if (!cls) return;
    Class meta = object_getClass(cls);
    if (!meta) return;
    SEL sel = @selector(sections);
    if (!class_getInstanceMethod(meta, sel)) return;
    MSHookMessageEx(meta, sel, (IMP)new_sections_exp, (IMP *)&orig_sections_exp);
}
