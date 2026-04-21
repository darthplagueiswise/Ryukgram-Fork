#import "TweakSettings.h"
#import <objc/runtime.h>
#import <substrate.h>

static NSArray *(*orig_sections_euo)(id, SEL);

static SCISetting *EUSwitch(NSString *title, NSString *subtitle, NSString *key, BOOL restart) {
    return [SCISetting switchCellWithTitle:title subtitle:subtitle defaultsKey:key requiresRestart:restart];
}

static NSArray *euoNavSections(void) {
    return @[
        @{
            @"header": @"Experimental features",
            @"footer": @"These features rely on hidden Instagram flags and may not work on all accounts or versions.\nExperimental flags research by @euoradan (Radan).",
            @"rows": @[
                EUSwitch(@"Enable liquid glass buttons", @"Enables experimental liquid glass buttons", @"liquid_glass_buttons", YES),
                EUSwitch(@"Enable liquid glass surfaces", @"Enables liquid glass tab bar, floating navigation, and other UI elements", @"liquid_glass_surfaces", YES),
                EUSwitch(@"Enable Homecoming UI", @"Forces the Homecoming navigation style", @"igt_homecoming", YES),
                EUSwitch(@"Enable Prism design system", @"Forces Prism design system surfaces where available", @"igt_prism", YES),
                EUSwitch(@"Enable dynamic tab layout", @"Forces dynamic tab story grid and fullscreen switcher", @"igt_dynamic_tab", NO),
                EUSwitch(@"Enable Reels first/second experiment", @"Forces the Reels ordering experiment used by Instagram", @"igt_reels_first", NO),
                EUSwitch(@"Enable Friends Feed", @"Forces older-posts Friends Feed experiment", @"igt_friends_feed", NO),
                EUSwitch(@"Enable audio ramping on swipe", @"Turns on audio ramping while swiping between tabs", @"igt_audio_ramping", NO),
                EUSwitch(@"Enable feed culling", @"Forces feed culling on status bar experiment", @"igt_feed_culling", NO),
                EUSwitch(@"Enable feed dedup", @"Forces feed dedup from reels optimization", @"igt_feed_dedup", NO),
                EUSwitch(@"Enable Pull to Carrera", @"Turns on the pull-to-Carrera navigation experiment", @"igt_pull_to_carrera", NO),
                EUSwitch(@"Force employee mode", @"Makes current IGUser report employee status", @"igt_employee", NO),
                EUSwitch(@"Force internal mode", @"Makes current IGUser report internal status", @"igt_internal", NO),
                EUSwitch(@"Enable screenshot blocking", @"Uses Instagram's screenshot blocking behavior where supported", @"igt_screenshot_block", NO),
                EUSwitch(@"Direct Notes: Friend Map", @"Forces the Friend Map flag inside Direct Notes", @"igt_directnotes_friendmap", NO),
                EUSwitch(@"Enable QuickSnap", @"Forces QuickSnap experiments", @"igt_quicksnap", YES),
                EUSwitch(@"Direct Notes: Audio reply", @"Forces the audio reply type for Direct Notes", @"igt_directnotes_audio_reply", NO),
                EUSwitch(@"Direct Notes: Avatar reply", @"Forces the avatar reply type for Direct Notes", @"igt_directnotes_avatar_reply", NO),
                EUSwitch(@"Direct Notes: GIFs/Stickers reply", @"Forces GIF and sticker reply types for Direct Notes", @"igt_directnotes_gifs_reply", NO),
                EUSwitch(@"Direct Notes: Photo reply", @"Forces the photo reply type for Direct Notes", @"igt_directnotes_photo_reply", NO),
                EUSwitch(@"Enable teen app icons", @"Hold down on the Instagram logo to change the app icon", @"teen_app_icons", YES),
                EUSwitch(@"Disable app haptics", @"Disables haptics/vibrations within the app", @"disable_haptics", NO),
                EUSwitch(@"Enable hooks", @"Installs observers + overrides. Restart required.", @"sci_exp_flags_enabled", YES)
            ]
        }
    ];
}

static NSDictionary *euoSection(void) {
    return @{
        @"header": @"",
        @"rows": @[
            [SCISetting navigationCellWithTitle:@"@euoradan Experimental Features"
                                       subtitle:@""
                                           icon:[SCISymbol symbolWithName:@"testtube.2"]
                                    navSections:euoNavSections()]
        ]
    };
}

static NSArray *new_sections_euo(id self, SEL _cmd) {
    NSArray *orig = orig_sections_euo ? orig_sections_euo(self, _cmd) : @[];
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

            if ([row.title isEqualToString:@"@euoradan Experimental Features"]) {
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

            if ([row.title isEqualToString:@"Advanced"]) {
                NSArray *navSections = [row.navSections isKindOfClass:[NSArray class]] ? row.navSections : nil;
                NSMutableArray *newNavSections = [NSMutableArray array];
                for (NSDictionary *navSection in navSections) {
                    NSString *header = [navSection[@"header"] isKindOfClass:[NSString class]] ? navSection[@"header"] : nil;
                    if ([header isEqualToString:@"Experimental flags"]) {
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
    [sections insertObject:euoSection() atIndex:insertIndex];
    return sections;
}

%ctor {
    Class cls = NSClassFromString(@"SCITweakSettings");
    if (!cls) return;
    Class meta = object_getClass(cls);
    if (!meta) return;
    SEL sel = @selector(sections);
    if (!class_getInstanceMethod(meta, sel)) return;
    MSHookMessageEx(meta, sel, (IMP)new_sections_euo, (IMP *)&orig_sections_euo);
}
