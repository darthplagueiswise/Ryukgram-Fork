#import "TweakSettings.h"
#import "SCIExpFlagsViewController.h"
#import <objc/runtime.h>
#import <substrate.h>

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
                ExpSwitch(@"Employee DevOptions gate", @"Forces exported employee/test-user/dogfooding MC gates discovered from FBSharedFramework. Restart required", @"igt_employee_devoptions_gate", YES),
                ExpSwitch(@"Employee MC: ig_is_employee", @"Forces ig_is_employee MobileConfig specifiers to YES (restart required)", @"igt_employee_mc", YES),
                ExpSwitch(@"Employee/TestUser MC: ig_is_employee_or_test_user", @"Forces ig_is_employee_or_test_user MobileConfig specifier to YES (restart required)", @"igt_employee_or_test_user_mc", YES),
                ExpSwitch(@"Internal Apps Installed Gate", @"Forces IGAppIsInstagramInternalAppsInstalledAndNotHiddenAfteriOS18 to YES (restart required)", @"igt_internal_apps_gate", YES),
                ExpSwitch(@"Observe InternalUse MobileConfig", @"Logs InternalUse/sessionless InternalUse boolean specifiers. ON by default for missing prefs. Restart required", @"igt_internaluse_observer", YES),
                ExpSwitch(@"Observe MobileConfig updates", @"Safely logs TryUpdate/ForceUpdate calls as pass-through only. ON by default for missing prefs. Restart required", @"igt_mobileconfig_update_observer", YES),
                ExpSwitch(@"Runtime MC true patcher", @"Master switch. Runtime patcher only patches symbols enabled below. Restart required", @"igt_runtime_mc_true_patcher", YES),
                ExpSwitch(@"Runtime MC true patcher relaxed", @"Skips first-8-byte pattern validation. Riskier; use only for isolated tests. Restart required", @"igt_runtime_mc_true_patcher_relaxed", YES)
            ]
        },
        @{
            @"header": @"Runtime MC symbols",
            @"footer": @"Master Runtime MC true patcher must also be ON. These switches only stub/force symbols to YES.",
            @"rows": @[
                ExpSwitch(@"Patch IG InternalUse bool", @"_IGMobileConfigBooleanValueForInternalUse -> YES", @"igt_runtime_mc_patch_ig_internaluse", YES),
                ExpSwitch(@"Patch IG ForceUpdate", @"_IGMobileConfigForceUpdateConfigs -> YES", @"igt_runtime_mc_patch_ig_force_update", YES),
                ExpSwitch(@"Patch IG SetConfigOverrides", @"_IGMobileConfigSetConfigOverrides -> YES", @"igt_runtime_mc_patch_ig_set_overrides", YES),
                ExpSwitch(@"Patch IG TryUpdate", @"_IGMobileConfigTryUpdateConfigsWithCompletion -> YES", @"igt_runtime_mc_patch_ig_try_update", YES),
                ExpSwitch(@"Patch MCI GetBoolean", @"_MCIMobileConfigGetBoolean -> YES", @"igt_runtime_mc_patch_mci_bool", YES),
                ExpSwitch(@"Patch METAExtensions GetBoolean", @"_METAExtensionsExperimentGetBoolean -> YES", @"igt_runtime_mc_patch_meta_ext_bool", YES),
                ExpSwitch(@"Patch METAExtensions no exposure", @"_METAExtensionsExperimentGetBooleanWithoutExposure -> YES", @"igt_runtime_mc_patch_meta_ext_bool_noexp", YES),
                ExpSwitch(@"Patch MCQMEM CQL bool", @"_MCQMEMMobileConfigCqlGetBooleanInternalDoNotUseOrMock -> YES", @"igt_runtime_mc_patch_mcqmem_cql_bool", YES),
                ExpSwitch(@"Patch MEM Capability bool", @"_MEMMobileConfigFeatureCapabilityGetBoolean_Internal_DoNotUseOrMock -> YES", @"igt_runtime_mc_patch_mem_capability_bool", YES),
                ExpSwitch(@"Patch MEM DevConfig bool", @"_MEMMobileConfigFeatureDevConfigGetBoolean_Internal_DoNotUseOrMock -> YES", @"igt_runtime_mc_patch_mem_devconfig_bool", YES),
                ExpSwitch(@"Patch MEM Platform bool", @"_MEMMobileConfigPlatformGetBoolean -> YES", @"igt_runtime_mc_patch_mem_platform_bool", YES),
                ExpSwitch(@"Patch MEM Protocol bool", @"_MEMMobileConfigProtocolExperimentGetBoolean_Internal_DoNotUseOrMock -> YES", @"igt_runtime_mc_patch_mem_protocol_bool", YES)
            ]
        },
        @{
            @"header": @"Flags browser",
            @"footer": @"MetaLocalExperiment and IGMobileConfigContextManager browser.",
            @"rows": @[
                ExpSwitch(@"Enable flags browser hooks", @"Installs MetaLocalExperiment and IGMobileConfig observers + overrides. ON by default for missing prefs", @"sci_exp_flags_enabled", YES),
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
    Class cls = NSClassFromString(@"SCITweakSettings");
    if (!cls) return;
    Class meta = object_getClass(cls);
    if (!meta) return;
    SEL sel = @selector(sections);
    if (!class_getInstanceMethod(meta, sel)) return;
    MSHookMessageEx(meta, sel, (IMP)new_sections_exp, (IMP *)&orig_sections_exp);
}
