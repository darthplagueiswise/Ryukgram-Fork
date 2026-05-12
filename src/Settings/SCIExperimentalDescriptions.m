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

            @"igt_homecoming": @"Observe-first Homecoming intent. Framework has Homecoming symbols, but this menu switch is not proof of a live override by itself.",
            @"igt_quicksnap": @"Observe-first QuickSnap/Instants intent. Do not assume it unlocks the feature until DexKit/MC hits confirm the real gate.",
            @"igt_directnotes_friendmap": @"Observe-first Direct Notes FriendMap intent. Native dogfood menu is separate from a real override.",
            @"igt_directnotes_audio_reply": @"Observe-first Notes audio reply intent. No force-ok status without runtime getter evidence.",
            @"igt_directnotes_avatar_reply": @"Observe-first Notes avatar reply intent. No force-ok status without runtime getter evidence.",
            @"igt_directnotes_gifs_reply": @"Observe-first Notes GIF/sticker reply intent. No force-ok status without runtime getter evidence.",
            @"igt_directnotes_photo_reply": @"Observe-first Notes photo reply intent. No force-ok status without runtime getter evidence.",
            @"igt_multiple_notes": @"Forces IGDirectNotesExperimentHelper multipleNotesEnabled: and mock duplicate gates.",
            @"igt_dn_first_badge": @"Forces Direct Notes first-note badge gate.",
            @"igt_dn_dfd_can_see": @"Forces IGDirectNotesDogfoodingSettings canSeeNotes.",
            @"igt_dn_dfd_show": @"Forces IGDirectNotesDogfoodingSettings showNotes and setShowNotes:.",
            @"igt_dn_dfd_gif": @"Forces Direct Notes GIF Notes dogfood getter.",
            @"igt_dn_dfd_icebreaker": @"Forces Direct Notes Icebreaker Notes dogfood getter.",
            @"igt_dn_dfd_location": @"Forces Direct Notes Location Notes dogfood getter.",
            @"igt_dn_dfd_lyrics": @"Forces Direct Notes Lyrics Notes dogfood getter.",
            @"igt_dn_dfd_music": @"Forces Direct Notes Music Notes dogfood getter.",
            @"igt_dn_dfd_watching": @"Forces Direct Notes Watching Now dogfood getter.",
            @"igt_dn_dfd_media_prod": @"Forces Direct Notes Media Notes production getter from IG 429.",
            @"igt_dn_dfd_original_audio": @"Forces Direct Notes Original Audio getter.",
            @"igt_dn_dfd_animated_emoji": @"Forces Direct Notes animated emoji creation getter.",
            @"igt_dn_dfd_bubble": @"Forces Direct Notes bubble customization getter.",
            @"igt_dn_dfd_tagging": @"Forces Direct Notes tagging getter.",
            @"igt_dn_dfd_listening": @"Forces Direct Notes Listening Now getter.",

            @"igt_prism": @"Observe-first Prism intent. FBSharedFramework has Prism selectors, but this key is not a verified override path.",
            @"igt_reels_first": @"Observe-first Feed/Navigation intent. Needs DexKit/MC correlation before force.",
            @"igt_friends_feed": @"Observe-first Feed/Navigation intent. Needs DexKit/MC correlation before force.",
            @"igt_tab_swiping": @"Observe-first navigation intent. Needs real selector/MC evidence before force.",
            @"igt_audio_ramping": @"Observe-first feed/audio intent. Needs real selector/MC evidence before force.",
            @"igt_feed_culling": @"Observe-first feed cleanup intent. Needs real selector/MC evidence before force.",
            @"igt_feed_dedup": @"Observe-first feed dedup intent. Needs real selector/MC evidence before force.",
            @"igt_pull_to_carrera": @"Observe-first Carrera intent. Needs real selector/MC evidence before force.",
            @"igt_screenshot_block": @"Screenshot blocking experiments. Force only if runtime evidence confirms the gate.",
            @"igt_stories_tray_decoupling": @"Forces independent Stories tray fetch/nav-chain gates.",
            @"igt_stories_tray_all_tabs": @"Forces Stories tray on all tabs.",
            @"igt_stories_show_classic": @"Prevents hiding the Stories tray on classic feed.",
            @"igt_vertical_stories_tray": @"Forces vertical Stories tray layout.",
            @"igt_stories_tray_cinema_swipe": @"Forces cinema Stories tray swipe-up gate.",
            @"igt_employee_master": @"Master switch for employee/internal intent. Runtime C broker patching remains offline-only unless explicitly installed elsewhere.",
            @"igt_employee": @"Legacy employee master toggle (kept for backward compatibility).",
            @"igt_employee_mc": @"Stores ig_is_employee MobileConfig intent; do not treat as live unless broker override is installed.",
            @"igt_employee_or_test_user_mc": @"Stores ig_is_employee_or_test_user MobileConfig intent; do not treat as live unless broker override is installed.",
            @"igt_internal": @"Internal Instagram intent. Requires real gate evidence before force.",
            @"igt_internal_apps_spoof": @"Stores internal apps-installed gate intent. Runtime body hooks are not installed from this description layer.",
            @"igt_internal_apps_gate": @"Stores internal apps-installed gate intent. Runtime body hooks are not installed from this description layer.",
            @"igt_internaluse_observer": @"Logs InternalUse MobileConfig specifiers for diagnostics only.",
            @"sci_exp_mc_hooks_enabled": @"Enable MobileConfig hooks only when explicitly selected. No startup hook stack.",
            @"sci_exp_flags_enabled": @"Enable experimental flag scanner only when explicitly selected."
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
