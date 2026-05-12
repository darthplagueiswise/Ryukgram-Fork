#import "../../Utils.h"
#import <objc/runtime.h>
#import <substrate.h>
#include "../../../modules/fishhook/fishhook.h"

// ─────────────────────────────────────────────────────────────────────────────
// DirectNotesCompat.xm  (beta2 — binary-verified)
//
// Hook strategy:
//   1. fishhook C-function stubs (fast, run at GOT-rebind time)
//   2. ObjC MSHookMessageEx on verified Swift class
//      _TtC37IGDirectNotesExperimentExposureHelper37IGDirectNotesExperimentExposureHelper
//      (confirmed ✅ IG binary)
//   Note: IGDirectNotesExperimentHelper does NOT exist in this binary.
//         The correct ObjC-visible name is the Swift class above.
// ─────────────────────────────────────────────────────────────────────────────

static BOOL sciFriendMapEnabled(void)   { return [SCIUtils getBoolPref:@"igt_directnotes_friendmap"]; }
static BOOL sciAudioReplyEnabled(void)  { return [SCIUtils getBoolPref:@"igt_directnotes_audio_reply"]; }
static BOOL sciAvatarReplyEnabled(void) { return [SCIUtils getBoolPref:@"igt_directnotes_avatar_reply"]; }
static BOOL sciGifsReplyEnabled(void)   { return [SCIUtils getBoolPref:@"igt_directnotes_gifs_reply"]; }
static BOOL sciPhotoReplyEnabled(void)  { return [SCIUtils getBoolPref:@"igt_directnotes_photo_reply"]; }

// ── C-stub hooks (fishhook) ──────────────────────────────────────────────────
// These are exported C functions in the Instagram binary that return BOOL.
// fishhook rebinds them in the GOT before first call.

static BOOL hook_IGDirectNotesFriendMapEnabled(void)             { return sciFriendMapEnabled(); }
static BOOL hook_IGDirectNotesEnableAudioNoteReplyType(void)     { return sciAudioReplyEnabled(); }
static BOOL hook_IGDirectNotesEnableAvatarReplyTypes(void)       { return sciAvatarReplyEnabled(); }
static BOOL hook_IGDirectNotesEnableGifsStickersReplyTypes(void) { return sciGifsReplyEnabled(); }
static BOOL hook_IGDirectNotesEnablePhotoNoteReplyType(void)     { return sciPhotoReplyEnabled(); }

// ── ObjC hooks ───────────────────────────────────────────────────────────────
// isInExperiment: on _TtC37IGDirectNotesExperimentExposureHelper (verified ✅)
// Receives the experiment name string and returns BOOL.

static BOOL sciContainsAny(NSString *value, NSArray<NSString *> *needles) {
    if (![value isKindOfClass:[NSString class]] || value.length == 0) return NO;
    NSString *lower = value.lowercaseString;
    for (NSString *needle in needles) {
        if ([lower containsString:needle.lowercaseString]) return YES;
    }
    return NO;
}

static BOOL sciDirectNotesExperimentMatch(NSString *name) {
    if (sciFriendMapEnabled()   && sciContainsAny(name, @[@"friendmap", @"friends_map", @"ig_ios_friendmap_", @"friendmapenabled", @"nsx_friend_map"])) return YES;
    if (sciAudioReplyEnabled()  && sciContainsAny(name, @[@"audio"])) return YES;
    if (sciAvatarReplyEnabled() && sciContainsAny(name, @[@"avatar"])) return YES;
    if (sciGifsReplyEnabled()   && sciContainsAny(name, @[@"gifs", @"sticker"])) return YES;
    if (sciPhotoReplyEnabled()  && sciContainsAny(name, @[@"photo"])) return YES;
    return NO;
}

static BOOL (*orig_isInExperiment)(id, SEL, id) = NULL;
static BOOL new_isInExperiment(id self, SEL _cmd, id arg1) {
    if (sciDirectNotesExperimentMatch((NSString *)arg1)) return YES;
    return orig_isInExperiment ? orig_isInExperiment(self, _cmd, arg1) : NO;
}

// is_notes_active_now_enabled / is_notes_tray_enabled — string properties
// confirmed ✅ IG binary; these are on the main tray service, not a gate.
static BOOL (*orig_notes_active)(id, SEL) = NULL;
static BOOL new_notes_active(id self, SEL _cmd) {
    // Only override if any notes feature is on
    if (sciFriendMapEnabled() || sciAudioReplyEnabled() || sciAvatarReplyEnabled()
        || sciGifsReplyEnabled() || sciPhotoReplyEnabled()) return YES;
    return orig_notes_active ? orig_notes_active(self, _cmd) : NO;
}

%ctor {
    BOOL anyEnabled = (sciFriendMapEnabled() || sciAudioReplyEnabled() || sciAvatarReplyEnabled()
                       || sciGifsReplyEnabled() || sciPhotoReplyEnabled());
    if (!anyEnabled) return;

    // ── 1. fishhook C stubs ──────────────────────────────────────────────────
    struct rebinding notesBinds[] = {
        {"IGDirectNotesFriendMapEnabled",             (void *)hook_IGDirectNotesFriendMapEnabled,             NULL},
        {"IGDirectNotesEnableAudioNoteReplyType",     (void *)hook_IGDirectNotesEnableAudioNoteReplyType,     NULL},
        {"IGDirectNotesEnableAvatarReplyTypes",       (void *)hook_IGDirectNotesEnableAvatarReplyTypes,       NULL},
        {"IGDirectNotesEnableGifsStickersReplyTypes", (void *)hook_IGDirectNotesEnableGifsStickersReplyTypes, NULL},
        {"IGDirectNotesEnablePhotoNoteReplyType",     (void *)hook_IGDirectNotesEnablePhotoNoteReplyType,     NULL},
    };
    rebind_symbols(notesBinds, sizeof(notesBinds) / sizeof(notesBinds[0]));

    // ── 2. ObjC hook on confirmed Swift class ────────────────────────────────
    // Verified ✅: _TtC37IGDirectNotesExperimentExposureHelper37IGDirectNotesExperimentExposureHelper
    // Note: IGDirectNotesExperimentHelper (bare ObjC name) does NOT exist in this binary.
    NSString *helperName = @"_TtC37IGDirectNotesExperimentExposureHelper37IGDirectNotesExperimentExposureHelper";
    Class helper = NSClassFromString(helperName);
    if (helper) {
        SEL sel = NSSelectorFromString(@"isInExperiment:");
        if (class_getInstanceMethod(helper, sel))
            MSHookMessageEx(helper, sel, (IMP)new_isInExperiment, (IMP *)&orig_isInExperiment);
        // Also hook class method variant if present
        if (class_getClassMethod(helper, sel))
            MSHookMessageEx(object_getClass(helper), sel, (IMP)new_isInExperiment, (IMP *)&orig_isInExperiment);
    } else {
        NSLog(@"[RyukGram][DNCompat] WARNING: %@ not found; isInExperiment hook skipped", helperName);
    }
}
