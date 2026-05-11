#import "TweakSettings.h"
#import <Foundation/Foundation.h>
#import <objc/runtime.h>
#import <substrate.h>

// Direct Notes feature types are owned by the native Direct Notes Dogfooding
// settings UI. The old RyukGram switch rows duplicated those native options
// and could fight native state. Keep the native launcher in Developer Mode and
// hide duplicate feature switches from the Experimental menu.

static NSArray *(*orig_RYDN_sections)(id, SEL) = NULL;

static BOOL RYDNRowIsDuplicateDirectNotesSwitch(SCISetting *row) {
    if (![row isKindOfClass:[SCISetting class]]) return NO;
    NSString *title = row.title ?: @"";
    NSString *key = row.defaultsKey ?: @"";

    NSSet<NSString *> *duplicateKeys = [NSSet setWithArray:@[
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
        @"ryuk_dn_first_badge"
    ]];
    if ([duplicateKeys containsObject:key]) return YES;

    NSString *lower = title.lowercaseString ?: @"";
    return [lower hasPrefix:@"direct notes: friendmap"] ||
           [lower hasPrefix:@"direct notes: audio reply"] ||
           [lower hasPrefix:@"direct notes: avatar reply"] ||
           [lower hasPrefix:@"direct notes: gifs"] ||
           [lower hasPrefix:@"direct notes: photo reply"] ||
           [lower containsString:@"multiple notes"] ||
           [lower containsString:@"first note badge"];
}

static NSArray *RYDNCleanRows(NSArray *rows) {
    NSMutableArray *clean = [NSMutableArray arrayWithCapacity:rows.count];
    for (id item in rows) {
        if ([item isKindOfClass:[SCISetting class]] && RYDNRowIsDuplicateDirectNotesSwitch((SCISetting *)item)) {
            continue;
        }
        [clean addObject:item];
    }
    return clean;
}

static NSArray *RYDNCleanSections(NSArray *sections) {
    NSMutableArray *out = [NSMutableArray arrayWithCapacity:sections.count];
    for (id obj in sections) {
        if (![obj isKindOfClass:[NSDictionary class]]) {
            [out addObject:obj];
            continue;
        }
        NSMutableDictionary *section = [(NSDictionary *)obj mutableCopy];
        NSArray *rows = [section[@"rows"] isKindOfClass:[NSArray class]] ? section[@"rows"] : nil;
        if (rows) section[@"rows"] = RYDNCleanRows(rows);

        NSString *header = [section[@"header"] isKindOfClass:[NSString class]] ? section[@"header"] : @"";
        NSString *footer = [section[@"footer"] isKindOfClass:[NSString class]] ? section[@"footer"] : @"";
        NSString *combined = [[@[header, footer] componentsJoinedByString:@" "] lowercaseString];
        if ([combined containsString:@"direct notes"] && [section[@"rows"] count] == 0) {
            section[@"footer"] = @"Direct Notes feature types are controlled by the native Direct Notes Dogfooding menu in Developer Mode.";
        }

        [out addObject:[section copy]];
    }
    return out;
}

static void RYDNCleanNestedNavSections(NSArray *sections) {
    for (id sectionObj in sections) {
        if (![sectionObj isKindOfClass:[NSDictionary class]]) continue;
        NSArray *rows = [sectionObj[@"rows"] isKindOfClass:[NSArray class]] ? sectionObj[@"rows"] : nil;
        for (id rowObj in rows) {
            SCISetting *row = [rowObj isKindOfClass:[SCISetting class]] ? rowObj : nil;
            if (!row || ![row.navSections isKindOfClass:[NSArray class]]) continue;
            row.navSections = RYDNCleanSections(row.navSections);
            RYDNCleanNestedNavSections(row.navSections);
        }
    }
}

static NSArray *new_RYDN_sections(id self, SEL _cmd) {
    NSArray *sections = orig_RYDN_sections ? orig_RYDN_sections(self, _cmd) : @[];
    NSMutableArray *clean = [RYDNCleanSections(sections) mutableCopy];
    RYDNCleanNestedNavSections(clean);
    return clean;
}

__attribute__((constructor(65535)))
static void RYDNInstallDirectNotesMenuCleanup(void) {
    Class cls = NSClassFromString(@"SCITweakSettings");
    Class meta = object_getClass(cls);
    SEL sel = @selector(sections);
    if (!meta || !class_getClassMethod(cls, sel)) return;
    MSHookMessageEx(meta, sel, (IMP)new_RYDN_sections, (IMP *)&orig_RYDN_sections);
}
