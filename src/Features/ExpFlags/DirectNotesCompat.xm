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

static BOOL hook_IGDirectNotesFriendMapEnabled(void) { return sciFriendMapEnabled(); }
static BOOL hook_IGDirectNotesEnableAudioNoteReplyType(void) { return sciAudioReplyEnabled(); }
static BOOL hook_IGDirectNotesEnableAvatarReplyTypes(void) { return sciAvatarReplyEnabled(); }
static BOOL hook_IGDirectNotesEnableGifsStickersReplyTypes(void) { return sciGifsReplyEnabled(); }
static BOOL hook_IGDirectNotesEnablePhotoNoteReplyType(void) { return sciPhotoReplyEnabled(); }

static BOOL sciContainsAny(NSString *value, NSArray<NSString *> *needles) {
    if (![value isKindOfClass:[NSString class]] || value.length == 0) return NO;
    NSString *lower = value.lowercaseString;
    for (NSString *needle in needles) {
        if ([lower containsString:needle.lowercaseString]) return YES;
    }
    return NO;
}

static BOOL sciDirectNotesExperimentMatch(NSString *name) {
    if (sciFriendMapEnabled() && sciContainsAny(name, @[@"friendmap", @"friends_map", @"ig_ios_friendmap_", @"friendmapenabled"])) return YES;
    if (sciAudioReplyEnabled() && sciContainsAny(name, @[@"audio"])) return YES;
    if (sciAvatarReplyEnabled() && sciContainsAny(name, @[@"avatar"])) return YES;
    if (sciGifsReplyEnabled() && sciContainsAny(name, @[@"gifs", @"sticker"])) return YES;
    if (sciPhotoReplyEnabled() && sciContainsAny(name, @[@"photo"])) return YES;
    return NO;
}

static BOOL (*orig_isInExperiment)(id, SEL, id) = NULL;
static BOOL new_isInExperiment(id self, SEL _cmd, id arg1) {
    if (sciDirectNotesExperimentMatch((NSString *)arg1)) return YES;
    return orig_isInExperiment ? orig_isInExperiment(self, _cmd, arg1) : NO;
}

%ctor {
    struct rebinding notesBinds[] = {
        {"IGDirectNotesFriendMapEnabled", (void *)hook_IGDirectNotesFriendMapEnabled, NULL},
        {"IGDirectNotesEnableAudioNoteReplyType", (void *)hook_IGDirectNotesEnableAudioNoteReplyType, NULL},
        {"IGDirectNotesEnableAvatarReplyTypes", (void *)hook_IGDirectNotesEnableAvatarReplyTypes, NULL},
        {"IGDirectNotesEnableGifsStickersReplyTypes", (void *)hook_IGDirectNotesEnableGifsStickersReplyTypes, NULL},
        {"IGDirectNotesEnablePhotoNoteReplyType", (void *)hook_IGDirectNotesEnablePhotoNoteReplyType, NULL},
    };
    rebind_symbols(notesBinds, sizeof(notesBinds) / sizeof(notesBinds[0]));

    Class helper = NSClassFromString(@"IGDirectNotesExperimentHelper");
    SEL sel = NSSelectorFromString(@"isInExperiment:");
    if (helper && class_getInstanceMethod(helper, sel)) {
        MSHookMessageEx(helper, sel, (IMP)new_isInExperiment, (IMP *)&orig_isInExperiment);
    }
}
