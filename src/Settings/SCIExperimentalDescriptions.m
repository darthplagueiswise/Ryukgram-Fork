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
            @"liquid_glass_buttons": @"Forces the Liquid Glass navigation/button helper. Usually safe; restart required so IG rebuilds the affected UI.",
            @"liquid_glass_surfaces": @"Enables floating tab bar/surface-level Liquid Glass gates through the tab bar exports. Restart required.",
            @"teen_app_icons": @"Unlocks Instagram's hidden teen/app icon picker. Long-press the Instagram logo after restart if the picker exists in this build.",
            @"disable_haptics": @"Turns off Instagram haptic feedback/vibrations where the app exposes a haptics gate.",

            @"igt_homecoming": @"Enables the Homecoming navigation UI through MetaLocalExperiment/FamilyLocalExperiment/LIDExperiment plus IGNavConfiguration.",
            @"igt_quicksnap": @"Attempts to enable QuickSnap/Instants. Uses rollout names, QuickSnap helper gates, tray gates, and MobileConfig keys such as quick_snap/quicksnap/instants.",
            @"igt_directnotes_friendmap": @"Enables Direct Notes Friend Map using the working path: IGDirectNotesExperimentHelper isInExperiment plus FriendMap experiment-name matching.",
            @"igt_directnotes_audio_reply": @"Enables the hidden Direct Notes audio reply experiment gates when the corresponding reply type exists.",
            @"igt_directnotes_avatar_reply": @"Enables the hidden Direct Notes avatar reply experiment gates when the corresponding reply type exists.",
            @"igt_directnotes_gifs_reply": @"Enables Direct Notes GIF/sticker reply experiments when present in this Instagram build.",
            @"igt_directnotes_photo_reply": @"Enables Direct Notes photo reply experiments when present in this Instagram build.",

            @"igt_prism": @"Experimental Prism Design System rollout switch. Leave off unless testing Prism-specific experiment names or selectors.",
            @"igt_reels_first": @"Attempts to enable Reels-first navigation/feed experiments. May depend on server-side account rollout.",
            @"igt_friends_feed": @"Attempts to enable hidden Friends Feed experiments and related navigation entry points.",
            @"igt_tab_swiping": @"Enables tab-swipe navigation gates when the matching IG navigation experiment is present.",
            @"igt_audio_ramping": @"Enables audio-ramping-on-swipe experiments for feed/reels navigation when present.",
            @"igt_feed_culling": @"Forces feed culling/status-bar optimization gates used by some experimental home feed builds.",
            @"igt_feed_dedup": @"Forces feed de-duplication optimization gates, especially dedup from Reels/home feed surfaces.",
            @"igt_pull_to_carrera": @"Attempts to enable hidden Pull to Carrera experiment gates if this build still contains them.",
            @"igt_screenshot_block": @"Forces screenshot-blocking experiment gates used by some private/visual-message surfaces. Use carefully.",
            @"igt_employee": @"Attempts to unlock employee/developer-only gates. Best results require matching the exact employee MobileConfig/experiment IDs for this build.",
            @"igt_internal": @"Attempts to enable internal/dogfood-style gates. This is broader than Employee and can break flows if IG expects internal services.",
            @"sci_exp_mc_hooks_enabled": @"Master switch for MobileConfig observation/override hooks used by Experimental Flags. Enable before browsing/testing MC IDs.",
            @"sci_exp_flags_enabled": @"Master switch for Experimental Flags discovery hooks. Collects MetaLocalExperiment, LIDExperiment, MobileConfig IDs, and scanned names while you browse IG."
        };
    });
    return map;
}

static NSString *SCIExperimentalButtonSubtitle(NSString *title) {
    if (![title isKindOfClass:[NSString class]]) return nil;
    if ([title isEqualToString:@"Experimental flags"]) {
        return @"Open the scanner/browser for MetaLocalExperiment, LIDExperiment, MobileConfig IDs, scanned names, and overrides.";
    }
    return nil;
}

static void SCIApplyExperimentalDescriptionsToRows(NSArray *rows);

static void SCIApplyExperimentalDescriptionsToSections(NSArray *sections) {
    for (id section in sections) {
        if (![section isKindOfClass:[NSDictionary class]]) continue;
        NSArray *rows = [(NSDictionary *)section objectForKey:@"rows"];
        SCIApplyExperimentalDescriptionsToRows(rows);
    }
}

static void SCIApplyExperimentalDescriptionsToRows(NSArray *rows) {
    for (id row in rows) {
        if (![row isKindOfClass:[SCISetting class]]) continue;
        SCISetting *setting = (SCISetting *)row;

        NSString *desc = SCIExperimentalDescriptionMap()[setting.defaultsKey ?: @""];
        if (desc.length) setting.subtitle = desc;

        NSString *buttonDesc = SCIExperimentalButtonSubtitle(setting.title);
        if (buttonDesc.length) setting.subtitle = buttonDesc;

        if ([setting.navSections isKindOfClass:[NSArray class]]) {
            SCIApplyExperimentalDescriptionsToSections(setting.navSections);
        }
    }
}

static NSArray *new_SCITweakSettings_sections(id self, SEL _cmd) {
    NSArray *sections = orig_SCITweakSettings_sections ? orig_SCITweakSettings_sections(self, _cmd) : @[];
    SCIApplyExperimentalDescriptionsToSections(sections);
    return sections;
}

__attribute__((constructor))
static void SCIInstallExperimentalDescriptionPatch(void) {
    Class cls = NSClassFromString(@"SCITweakSettings");
    Class meta = object_getClass(cls);
    SEL sel = NSSelectorFromString(@"sections");
    if (!meta || !class_getClassMethod(cls, sel)) return;
    MSHookMessageEx(meta, sel, (IMP)new_SCITweakSettings_sections, (IMP *)&orig_SCITweakSettings_sections);
}
