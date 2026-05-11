#import <Foundation/Foundation.h>
#import <objc/runtime.h>
#import <substrate.h>
#import "../../Settings/TweakSettings.h"

// DirectNotes Dogfooding owns the Notes feature surface. This cleanup removes
// duplicated RyukGram wrapper toggles from the normal Experimental menu so the
// user uses the native dogfooding menu instead of conflicting duplicate keys.

static NSArray *(*origRYDNMenuSections)(id self, SEL _cmd) = NULL;

static BOOL RYDNRowIsDuplicatedDirectNotesToggle(id row) {
    if (![row isKindOfClass:[SCISetting class]]) return NO;
    SCISetting *setting = (SCISetting *)row;
    NSString *key = setting.defaultsKey ?: @"";
    NSString *title = (setting.title ?: @"").lowercaseString;
    NSString *subtitle = (setting.subtitle ?: @"").lowercaseString;
    NSString *joined = [@[title, subtitle] componentsJoinedByString:@" "];

    static NSSet<NSString *> *duplicateKeys;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        duplicateKeys = [NSSet setWithArray:@[
            @"igt_directnotes_friendmap",
            @"igt_directnotes_audio_reply",
            @"igt_directnotes_avatar_reply",
            @"igt_directnotes_gifs_reply",
            @"igt_directnotes_photo_reply",
            @"igt_multiple_notes",
            @"igt_dn_first_badge",
            @"ryuk_dn_friendmap",
            @"ryuk_dn_audio_reply",
            @"ryuk_dn_avatar_reply",
            @"ryuk_dn_gifs_reply",
            @"ryuk_dn_photo_reply",
            @"ryuk_dn_multiple_notes",
            @"ryuk_dn_multiple_mock",
            @"ryuk_dn_first_badge",
            @"ryuk_notes_enabled",
            @"ryuk_notes_active_now",
            @"ryuk_notes_music",
            @"ryuk_notes_friendmap_mc",
            @"ryuk_dn_dfd_gif",
            @"ryuk_dn_dfd_icebreaker",
            @"ryuk_dn_dfd_location",
            @"ryuk_dn_dfd_lyrics",
            @"ryuk_dn_dfd_music",
            @"ryuk_dn_dfd_watching",
            @"ryuk_dn_dfd_original_audio",
            @"ryuk_dn_dfd_animated_emoji",
            @"ryuk_dn_dfd_bubble",
            @"ryuk_dn_dfd_tagging",
            @"ryuk_dn_dfd_listening",
            @"ryuk_dn_dfd_can_see",
            @"ryuk_dn_dfd_show"
        ]];
    });

    if ([duplicateKeys containsObject:key]) return YES;
    if ([joined containsString:@"direct notes: friendmap"]) return YES;
    if ([joined containsString:@"direct notes: audio reply"]) return YES;
    if ([joined containsString:@"direct notes: avatar reply"]) return YES;
    if ([joined containsString:@"direct notes: gifs"]) return YES;
    if ([joined containsString:@"direct notes: photo reply"]) return YES;
    if ([joined containsString:@"friendmap / location notes gates"]) return YES;
    return NO;
}

static NSArray *RYDNCleanRows(NSArray *rows) {
    if (![rows isKindOfClass:NSArray.class]) return rows ?: @[];
    NSMutableArray *out = [NSMutableArray arrayWithCapacity:rows.count];
    for (id row in rows) {
        if (RYDNRowIsDuplicatedDirectNotesToggle(row)) continue;

        if ([row isKindOfClass:[SCISetting class]]) {
            SCISetting *setting = (SCISetting *)row;
            NSArray *navSections = [setting.navSections isKindOfClass:NSArray.class] ? setting.navSections : nil;
            if (navSections.count) {
                NSMutableArray *cleanNav = [NSMutableArray arrayWithCapacity:navSections.count];
                for (id sectionObj in navSections) {
                    if (![sectionObj isKindOfClass:NSDictionary.class]) { [cleanNav addObject:sectionObj]; continue; }
                    NSMutableDictionary *section = [(NSDictionary *)sectionObj mutableCopy];
                    section[@"rows"] = RYDNCleanRows(section[@"rows"]);
                    [cleanNav addObject:[section copy]];
                }
                setting.navSections = [cleanNav copy];
            }
        }
        [out addObject:row];
    }
    return [out copy];
}

static NSArray *RYDNCleanSections(NSArray *sections) {
    if (![sections isKindOfClass:NSArray.class]) return sections ?: @[];
    NSMutableArray *out = [NSMutableArray arrayWithCapacity:sections.count];
    for (id sectionObj in sections) {
        if (![sectionObj isKindOfClass:NSDictionary.class]) { [out addObject:sectionObj]; continue; }
        NSMutableDictionary *section = [(NSDictionary *)sectionObj mutableCopy];
        section[@"rows"] = RYDNCleanRows(section[@"rows"]);
        [out addObject:[section copy]];
    }
    return [out copy];
}

static NSArray *hookRYDNMenuSections(id self, SEL _cmd) {
    NSArray *sections = origRYDNMenuSections ? origRYDNMenuSections(self, _cmd) : @[];
    return RYDNCleanSections(sections);
}

static void RYDNInstallMenuCleanup(void) {
    Class cls = NSClassFromString(@"SCITweakSettings");
    if (!cls) return;
    Class meta = object_getClass(cls);
    SEL sel = @selector(sections);
    if (!meta || !class_getInstanceMethod(meta, sel)) return;
    static BOOL installed = NO;
    if (installed) return;
    installed = YES;
    MSHookMessageEx(meta, sel, (IMP)hookRYDNMenuSections, (IMP *)&origRYDNMenuSections);
}

__attribute__((constructor(65535)))
static void RYDNDirectNotesMenuCleanupInit(void) {
    dispatch_async(dispatch_get_main_queue(), ^{
        RYDNInstallMenuCleanup();
    });
}
