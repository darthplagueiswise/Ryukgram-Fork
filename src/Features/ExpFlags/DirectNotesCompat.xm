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
    return NO;
}

static BOOL (*orig_isInExperiment)(id, SEL, id) = NULL;
static BOOL new_isInExperiment(id self, SEL _cmd, id arg1) {
    if (sciDirectNotesExperimentMatch((NSString *)arg1)) return YES;
    return orig_isInExperiment ? orig_isInExperiment(self, _cmd, arg1) : NO;
}

%ctor {
    struct rebinding notesBinds[] = {
        {"IGDirectNotesFriendMapEnabled", (void *)hook_IGDirectNotesFriendMapEnabled, (void **)&orig_IGDirectNotesFriendMapEnabled},
        {"IGDirectNotesEnableAudioNoteReplyType", (void *)hook_IGDirectNotesEnableAudioNoteReplyType, (void **)&orig_IGDirectNotesEnableAudioNoteReplyType},
        {"IGDirectNotesEnableAvatarReplyTypes", (void *)hook_IGDirectNotesEnableAvatarReplyTypes, (void **)&orig_IGDirectNotesEnableAvatarReplyTypes},
        {"IGDirectNotesEnableGifsStickersReplyTypes", (void *)hook_IGDirectNotesEnableGifsStickersReplyTypes, (void **)&orig_IGDirectNotesEnableGifsStickersReplyTypes},
        {"IGDirectNotesEnablePhotoNoteReplyType", (void *)hook_IGDirectNotesEnablePhotoNoteReplyType, (void **)&orig_IGDirectNotesEnablePhotoNoteReplyType},
    };
    rebind_symbols(notesBinds, sizeof(notesBinds) / sizeof(notesBinds[0]));

    Class helper = NSClassFromString(@"_TtC34IGDirectNotesExperimentHelperSwift29IGDirectNotesExperimentHelper");
    if (!helper) helper = NSClassFromString(@"IGDirectNotesExperimentHelperSwift.IGDirectNotesExperimentHelper");
    if (!helper) helper = NSClassFromString(@"IGDirectNotesExperimentHelper");
    SEL sel = NSSelectorFromString(@"isInExperiment:");
    if (helper && class_getInstanceMethod(helper, sel)) {
        MSHookMessageEx(helper, sel, (IMP)new_isInExperiment, (IMP *)&orig_isInExperiment);
    }
}
