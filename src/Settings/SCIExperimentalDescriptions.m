#import <Foundation/Foundation.h>
#import <objc/runtime.h>
#import <substrate.h>
#import "SCISetting.h"

static NSArray *(*orig_SCITweakSettings_sections)(id, SEL) = NULL;

static NSDictionary<NSString *, NSString *> *SCIExperimentalDescriptionMap(void) {
    static NSDictionary<NSString *, NSString *> *map;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        map = @{
            @"liquid_glass_buttons": @"Liquid Glass buttons and controls.",
            @"liquid_glass_surfaces": @"Liquid Glass tab bar and surfaces.",
            @"teen_app_icons": @"Hidden Instagram app icon picker.",
            @"disable_haptics": @"Disable Instagram haptic feedback.",

            @"igt_homecoming": @"New Homecoming navigation UI.",
            @"igt_quicksnap": @"Share QuickSnap/Instant photos feature.",
            @"igt_directnotes_friendmap": @"New Friends Map feature.",
            @"igt_directnotes_audio_reply": @"Audio replies for Notes.",
            @"igt_directnotes_avatar_reply": @"Avatar replies for Notes.",
            @"igt_directnotes_gifs_reply": @"GIF and sticker replies for Notes.",
            @"igt_directnotes_photo_reply": @"Photo replies for Notes.",

            @"igt_prism": @"New Prism design system.",
            @"igt_reels_first": @"Reels-first experience.",
            @"igt_friends_feed": @"Friends-only feed experience.",
            @"igt_tab_swiping": @"Swipe between main tabs.",
            @"igt_audio_ramping": @"Smooth audio changes while swiping.",
            @"igt_feed_culling": @"Experimental feed cleanup.",
            @"igt_feed_dedup": @"Reduce duplicate feed content.",
            @"igt_pull_to_carrera": @"Pull-to-Carrera experiment.",
            @"igt_screenshot_block": @"Screenshot blocking experiments.",
            @"igt_employee": @"Legacy employee master toggle (kept for backward compatibility).",
            @"igt_employee_mc": @"Forces ig_is_employee MobileConfig specifiers to true.",
            @"igt_employee_or_test_user_mc": @"Forces ig_is_employee_or_test_user MobileConfig specifier to true.",
            @"igt_internal": @"Internal Instagram features.",
            @"igt_internal_apps_gate": @"Forces internal apps-installed gate to true.",
            @"igt_internaluse_observer": @"Logs InternalUse MobileConfig specifiers for diagnostics.",
            @"sci_exp_mc_hooks_enabled": @"Enable MobileConfig hooks.",
            @"sci_exp_flags_enabled": @"Enable experimental flag scanner."
        };
    });
    return map;
}

static BOOL SCIShouldRemoveFooter(id footer) {
    if (![footer isKindOfClass:[NSString class]]) return NO;
    NSString *s = [(NSString *)footer lowercaseString];
    return [s containsString:@"quicksnap and friendmap hooks"] ||
           [s containsString:@"metalocalexperiment and igmobile"] ||
           [s containsString:@"configcontextmanager browser"];
}

static void SCIApplyExperimentalDescriptionsToRows(NSArray *rows);

static NSArray *SCICleanSections(NSArray *sections) {
    NSMutableArray *cleaned = [NSMutableArray arrayWithCapacity:sections.count];
    for (id section in sections) {
        if (![section isKindOfClass:[NSDictionary class]]) {
            [cleaned addObject:section];
            continue;
        }

        NSMutableDictionary *copy = [(NSDictionary *)section mutableCopy];
        if (SCIShouldRemoveFooter(copy[@"footer"])) copy[@"footer"] = @"";

        NSArray *rows = copy[@"rows"];
        SCIApplyExperimentalDescriptionsToRows(rows);
        [cleaned addObject:[copy copy]];
    }
    return [cleaned copy];
}

static void SCIApplyExperimentalDescriptionsToRows(NSArray *rows) {
    for (id row in rows) {
        if (![row isKindOfClass:[SCISetting class]]) continue;
        SCISetting *setting = (SCISetting *)row;

        NSString *desc = SCIExperimentalDescriptionMap()[setting.defaultsKey ?: @""];
        if (desc.length) setting.subtitle = desc;

        if ([setting.title isEqualToString:@"Experimental flags"]) setting.subtitle = @"";

        if ([setting.navSections isKindOfClass:[NSArray class]]) {
            setting.navSections = SCICleanSections(setting.navSections);
        }
    }
}

static NSArray *new_SCITweakSettings_sections(id self, SEL _cmd) {
    NSArray *sections = orig_SCITweakSettings_sections ? orig_SCITweakSettings_sections(self, _cmd) : @[];
    return SCICleanSections(sections);
}

__attribute__((constructor))
static void SCIInstallExperimentalDescriptionPatch(void) {
    Class cls = NSClassFromString(@"SCITweakSettings");
    Class meta = object_getClass(cls);
    SEL sel = NSSelectorFromString(@"sections");
    if (!meta || !class_getClassMethod(cls, sel)) return;
    MSHookMessageEx(meta, sel, (IMP)new_SCITweakSettings_sections, (IMP *)&orig_SCITweakSettings_sections);
}
