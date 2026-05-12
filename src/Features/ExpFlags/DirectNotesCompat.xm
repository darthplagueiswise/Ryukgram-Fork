#import "../../Utils.h"
#import <objc/runtime.h>
#import <substrate.h>
#include "../../../modules/fishhook/fishhook.h"

static BOOL sciFriendMapEnabled(void) {
    return [SCIUtils getBoolPref:@"igt_directnotes_friendmap"];
}
static BOOL sciAudioReplyEnabled(void) {
    return [SCIUtils getBoolPref:@"igt_directnotes_audio_reply"];
}
static BOOL sciAvatarReplyEnabled(void) {
    return [SCIUtils getBoolPref:@"igt_directnotes_avatar_reply"];
}
static BOOL sciGifsReplyEnabled(void) {
    return [SCIUtils getBoolPref:@"igt_directnotes_gifs_reply"];
}
static BOOL sciPhotoReplyEnabled(void) {
    return [SCIUtils getBoolPref:@"igt_directnotes_photo_reply"];
}
static BOOL sciMultipleNotesEnabled(void) {
    return [SCIUtils getBoolPref:@"igt_multiple_notes"];
}
static BOOL sciFirstNoteBadgeEnabled(void) {
    return [SCIUtils getBoolPref:@"igt_dn_first_badge"];
}

static BOOL (*orig_IGDirectNotesFriendMapEnabled)(void) = NULL;
static BOOL (*orig_IGDirectNotesEnableAudioNoteReplyType)(void) = NULL;
static BOOL (*orig_IGDirectNotesEnableAvatarReplyTypes)(void) = NULL;
static BOOL (*orig_IGDirectNotesEnableGifsStickersReplyTypes)(void) = NULL;
static BOOL (*orig_IGDirectNotesEnablePhotoNoteReplyType)(void) = NULL;

static BOOL hook_IGDirectNotesFriendMapEnabled(void) {
    return sciFriendMapEnabled() ? YES : (orig_IGDirectNotesFriendMapEnabled ? orig_IGDirectNotesFriendMapEnabled() : NO);
}
static BOOL hook_IGDirectNotesEnableAudioNoteReplyType(void) {
    return sciAudioReplyEnabled() ? YES : (orig_IGDirectNotesEnableAudioNoteReplyType ? orig_IGDirectNotesEnableAudioNoteReplyType() : NO);
}
static BOOL hook_IGDirectNotesEnableAvatarReplyTypes(void) {
    return sciAvatarReplyEnabled() ? YES : (orig_IGDirectNotesEnableAvatarReplyTypes ? orig_IGDirectNotesEnableAvatarReplyTypes() : NO);
}
static BOOL hook_IGDirectNotesEnableGifsStickersReplyTypes(void) {
    return sciGifsReplyEnabled() ? YES : (orig_IGDirectNotesEnableGifsStickersReplyTypes ? orig_IGDirectNotesEnableGifsStickersReplyTypes() : NO);
}
static BOOL hook_IGDirectNotesEnablePhotoNoteReplyType(void) {
    return sciPhotoReplyEnabled() ? YES : (orig_IGDirectNotesEnablePhotoNoteReplyType ? orig_IGDirectNotesEnablePhotoNoteReplyType() : NO);
}

static BOOL sciContainsAny(NSString *value, NSArray<NSString *> *needles) {
    if (![value isKindOfClass:[NSString class]] || value.length == 0) return NO;
    NSString *lower = value.lowercaseString;
    for (NSString *needle in needles) {
        if ([lower containsString:needle.lowercaseString]) return YES;
    }
    return NO;
}

static BOOL sciDirectNotesExperimentMatch(NSString *name) {
    if (sciFriendMapEnabled() && sciContainsAny(name, @[@"friendmap", @"friend_map", @"friends_map", @"location", @"ig_ios_friendmap_", @"friendmapenabled"])) return YES;
    if (sciAudioReplyEnabled() && sciContainsAny(name, @[@"audio", @"original_audio", @"music"])) return YES;
    if (sciAvatarReplyEnabled() && sciContainsAny(name, @[@"avatar", @"emoji"])) return YES;
    if (sciGifsReplyEnabled() && sciContainsAny(name, @[@"gif", @"gifs", @"sticker", @"quickreplies"])) return YES;
    if (sciPhotoReplyEnabled() && sciContainsAny(name, @[@"photo", @"camera", @"image"])) return YES;
    if (sciMultipleNotesEnabled() && sciContainsAny(name, @[@"multiplenotes", @"multiple_notes", @"mockduplicates", @"mock_duplicates"])) return YES;
    if (sciFirstNoteBadgeEnabled() && sciContainsAny(name, @[@"firstnotebadge", @"first_note_badge"])) return YES;
    if ([SCIUtils getBoolPref:@"igt_dn_dfd_location"] && sciContainsAny(name, @[@"locationnote", @"location_notes", @"location"])) return YES;
    if ([SCIUtils getBoolPref:@"igt_dn_dfd_lyrics"] && sciContainsAny(name, @[@"lyrics", @"lyric"])) return YES;
    if ([SCIUtils getBoolPref:@"igt_dn_dfd_music"] && sciContainsAny(name, @[@"music", @"spotify", @"listeningnow", @"listening_now"])) return YES;
    if ([SCIUtils getBoolPref:@"igt_dn_dfd_original_audio"] && sciContainsAny(name, @[@"originalaudio", @"original_audio"])) return YES;
    if ([SCIUtils getBoolPref:@"igt_dn_dfd_media_prod"] && sciContainsAny(name, @[@"medianotes", @"media_notes", @"media_notes_production"])) return YES;
    if ([SCIUtils getBoolPref:@"igt_dn_dfd_icebreaker"] && sciContainsAny(name, @[@"icebreaker", @"question"])) return YES;
    return NO;
}

static BOOL (*orig_isInExperiment)(id, SEL, id) = NULL;
static BOOL new_isInExperiment(id self, SEL _cmd, id arg1) {
    if (sciDirectNotesExperimentMatch((NSString *)arg1)) return YES;
    return orig_isInExperiment ? orig_isInExperiment(self, _cmd, arg1) : NO;
}

static BOOL (*orig_multipleNotesEnabled)(id, SEL, id) = NULL;
static BOOL new_multipleNotesEnabled(id self, SEL _cmd, id launcherSet) {
    if (sciMultipleNotesEnabled()) return YES;
    return orig_multipleNotesEnabled ? orig_multipleNotesEnabled(self, _cmd, launcherSet) : NO;
}

static BOOL (*orig_multipleNotesMockDup)(id, SEL, id) = NULL;
static BOOL new_multipleNotesMockDup(id self, SEL _cmd, id launcherSet) {
    if (sciMultipleNotesEnabled()) return YES;
    return orig_multipleNotesMockDup ? orig_multipleNotesMockDup(self, _cmd, launcherSet) : NO;
}

static BOOL (*orig_firstNoteBadge)(id, SEL) = NULL;
static BOOL new_firstNoteBadge(id self, SEL _cmd) {
    if (sciFirstNoteBadgeEnabled()) return YES;
    return orig_firstNoteBadge ? orig_firstNoteBadge(self, _cmd) : NO;
}

static Class sciDirectNotesHelperClass(void) {
    Class helper = NSClassFromString(@"_TtC34IGDirectNotesExperimentHelperSwift29IGDirectNotesExperimentHelper");
    if (!helper) helper = NSClassFromString(@"IGDirectNotesExperimentHelperSwift.IGDirectNotesExperimentHelper");
    if (!helper) helper = NSClassFromString(@"IGDirectNotesExperimentHelper");
    return helper;
}

static BOOL sciMethodReturnsBool(Method method) {
    if (!method) return NO;
    char rt[16] = {0};
    method_getReturnType(method, rt, sizeof(rt));
    return rt[0] == 'B' || rt[0] == 'c' || rt[0] == 'C';
}

static void sciHookNotesMethod(Class cls, NSString *selectorName, unsigned int argCount, IMP replacement, IMP *original) {
    if (!cls || !selectorName.length) return;
    SEL sel = NSSelectorFromString(selectorName);
    Method method = class_getClassMethod(cls, sel);
    if (!method) method = class_getInstanceMethod(cls, sel);
    if (!method || !sciMethodReturnsBool(method) || method_getNumberOfArguments(method) != argCount) return;
    IMP old = method_setImplementation(method, replacement);
    if (original) *original = old;
}

static BOOL sciOldDirectNotesCPrefsEnabled(void) {
    return sciFriendMapEnabled() ||
           sciAudioReplyEnabled() ||
           sciAvatarReplyEnabled() ||
           sciGifsReplyEnabled() ||
           sciPhotoReplyEnabled();
}

static BOOL sciAnyDirectNotesExperimentPrefEnabled(void) {
    if (sciOldDirectNotesCPrefsEnabled() || sciMultipleNotesEnabled() || sciFirstNoteBadgeEnabled()) return YES;
    for (NSString *key in @[
        @"igt_dn_dfd_location",
        @"igt_dn_dfd_lyrics",
        @"igt_dn_dfd_music",
        @"igt_dn_dfd_original_audio",
        @"igt_dn_dfd_media_prod",
        @"igt_dn_dfd_icebreaker"
    ]) {
        if ([SCIUtils getBoolPref:key]) return YES;
    }
    return NO;
}

%ctor {
    if (sciOldDirectNotesCPrefsEnabled()) {
        struct rebinding notesBinds[] = {
            {"IGDirectNotesFriendMapEnabled", (void *)hook_IGDirectNotesFriendMapEnabled, (void **)&orig_IGDirectNotesFriendMapEnabled},
            {"IGDirectNotesEnableAudioNoteReplyType", (void *)hook_IGDirectNotesEnableAudioNoteReplyType, (void **)&orig_IGDirectNotesEnableAudioNoteReplyType},
            {"IGDirectNotesEnableAvatarReplyTypes", (void *)hook_IGDirectNotesEnableAvatarReplyTypes, (void **)&orig_IGDirectNotesEnableAvatarReplyTypes},
            {"IGDirectNotesEnableGifsStickersReplyTypes", (void *)hook_IGDirectNotesEnableGifsStickersReplyTypes, (void **)&orig_IGDirectNotesEnableGifsStickersReplyTypes},
            {"IGDirectNotesEnablePhotoNoteReplyType", (void *)hook_IGDirectNotesEnablePhotoNoteReplyType, (void **)&orig_IGDirectNotesEnablePhotoNoteReplyType},
        };
        rebind_symbols(notesBinds, sizeof(notesBinds) / sizeof(notesBinds[0]));
    }

    if (!sciAnyDirectNotesExperimentPrefEnabled()) return;

    Class helper = sciDirectNotesHelperClass();
    sciHookNotesMethod(helper, @"multipleNotesEnabled:", 3, (IMP)new_multipleNotesEnabled, (IMP *)&orig_multipleNotesEnabled);
    sciHookNotesMethod(helper, @"multipleNotesMockDuplicatesEnabled:", 3, (IMP)new_multipleNotesMockDup, (IMP *)&orig_multipleNotesMockDup);
    sciHookNotesMethod(helper, @"firstNoteBadgeEnabled", 2, (IMP)new_firstNoteBadge, (IMP *)&orig_firstNoteBadge);

    SEL sel = NSSelectorFromString(@"isInExperiment:");
    Method method = helper ? class_getInstanceMethod(helper, sel) : NULL;
    if (!method && helper) method = class_getClassMethod(helper, sel);
    if (method && sciMethodReturnsBool(method) && method_getNumberOfArguments(method) == 3) {
        orig_isInExperiment = (BOOL (*)(id, SEL, id))method_setImplementation(method, (IMP)new_isInExperiment);
    }
}
