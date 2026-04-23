#import "../../Utils.h"
#import <objc/runtime.h>
#import <substrate.h>

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

static BOOL (*orig_dn_location)(id, SEL, id) = NULL;
static BOOL new_dn_location(id self, SEL _cmd, id arg1) { return sciFriendMapEnabled(); }
static BOOL (*orig_dn_iteration)(id, SEL, id) = NULL;
static BOOL new_dn_iteration(id self, SEL _cmd, id arg1) { return sciFriendMapEnabled(); }
static BOOL (*orig_dn_bottom_attr)(id, SEL, id) = NULL;
static BOOL new_dn_bottom_attr(id self, SEL _cmd, id arg1) { return sciFriendMapEnabled(); }
static BOOL (*orig_dn_audience)(id, SEL, id) = NULL;
static BOOL new_dn_audience(id self, SEL _cmd, id arg1) { return sciFriendMapEnabled(); }
static BOOL (*orig_dn_tray_gen)(id, SEL, id) = NULL;
static BOOL new_dn_tray_gen(id self, SEL _cmd, id arg1) { return sciFriendMapEnabled(); }
static BOOL (*orig_dn_details_gen)(id, SEL, id) = NULL;
static BOOL new_dn_details_gen(id self, SEL _cmd, id arg1) { return sciFriendMapEnabled(); }
static BOOL (*orig_dn_ambient_data)(id, SEL, id, BOOL) = NULL;
static BOOL new_dn_ambient_data(id self, SEL _cmd, id arg1, BOOL arg2) { return sciFriendMapEnabled(); }
static BOOL (*orig_dn_theme_entry)(id, SEL, id) = NULL;
static BOOL new_dn_theme_entry(id self, SEL _cmd, id arg1) { return sciFriendMapEnabled(); }
static BOOL (*orig_dn_text_required)(id, SEL, id) = NULL;
static BOOL new_dn_text_required(id self, SEL _cmd, id arg1) { return sciFriendMapEnabled(); }

static BOOL (*orig_reply_enabled)(id, SEL) = NULL;
static BOOL new_reply_enabled(id self, SEL _cmd) { return YES; }

static void hookClassBool0(NSString *className, NSString *selName, IMP newImp, IMP *orig) {
    Class cls = NSClassFromString(className);
    if (!cls) return;
    Class meta = object_getClass(cls);
    if (!meta) return;
    SEL sel = NSSelectorFromString(selName);
    if (!class_getInstanceMethod(meta, sel)) return;
    MSHookMessageEx(meta, sel, newImp, orig);
}

static void hookClassBool1(NSString *className, NSString *selName, IMP newImp, IMP *orig) {
    Class cls = NSClassFromString(className);
    if (!cls) return;
    Class meta = object_getClass(cls);
    if (!meta) return;
    SEL sel = NSSelectorFromString(selName);
    if (!class_getInstanceMethod(meta, sel)) return;
    MSHookMessageEx(meta, sel, newImp, orig);
}

static void hookClassBool2(NSString *className, NSString *selName, IMP newImp, IMP *orig) {
    Class cls = NSClassFromString(className);
    if (!cls) return;
    Class meta = object_getClass(cls);
    if (!meta) return;
    SEL sel = NSSelectorFromString(selName);
    if (!class_getInstanceMethod(meta, sel)) return;
    MSHookMessageEx(meta, sel, newImp, orig);
}

static void hookReplyToggleIfNeeded(BOOL enabled, NSString *className) {
    if (!enabled) return;
    hookClassBool0(className, @"isEnabled", (IMP)new_reply_enabled, (IMP *)&orig_reply_enabled);
    hookClassBool0(className, @"enabled", (IMP)new_reply_enabled, NULL);
}

%ctor {
    if (sciFriendMapEnabled()) {
        hookClassBool0(@"_IGDirectNotesFriendMapEnabled", @"isEnabled", (IMP)new_reply_enabled, NULL);
        hookClassBool0(@"_IGDirectNotesFriendMapEnabled", @"enabled", (IMP)new_reply_enabled, NULL);

        NSString *directNotesHelper = @"_TtC34IGDirectNotesExperimentHelperSwift29IGDirectNotesExperimentHelper";
        hookClassBool1(directNotesHelper, @"locationNotesEnabled:", (IMP)new_dn_location, (IMP *)&orig_dn_location);
        hookClassBool1(directNotesHelper, @"locationNotesIterationEnabled:", (IMP)new_dn_iteration, (IMP *)&orig_dn_iteration);
        hookClassBool1(directNotesHelper, @"locationNotesBottomAttributionEnabled:", (IMP)new_dn_bottom_attr, (IMP *)&orig_dn_bottom_attr);
        hookClassBool1(directNotesHelper, @"audienceAllFollowersEnabled:", (IMP)new_dn_audience, (IMP *)&orig_dn_audience);
        hookClassBool1(directNotesHelper, @"isTrayGeneratorSwiftEnabled:", (IMP)new_dn_tray_gen, (IMP *)&orig_dn_tray_gen);
        hookClassBool1(directNotesHelper, @"isDetailsGeneratorSwiftEnabled:", (IMP)new_dn_details_gen, (IMP *)&orig_dn_details_gen);
        hookClassBool2(directNotesHelper, @"ambientDataCreationEnabled:shouldExpose:", (IMP)new_dn_ambient_data, (IMP *)&orig_dn_ambient_data);
        hookClassBool1(directNotesHelper, @"themeEnhancementsEntryPointEnabled:", (IMP)new_dn_theme_entry, (IMP *)&orig_dn_theme_entry);
        hookClassBool1(directNotesHelper, @"locationNotesTextRequiredEnabled:", (IMP)new_dn_text_required, (IMP *)&orig_dn_text_required);
    }

    hookReplyToggleIfNeeded(sciAudioReplyEnabled(), @"_IGDirectNotesEnableAudioNoteReplyType");
    hookReplyToggleIfNeeded(sciAvatarReplyEnabled(), @"_IGDirectNotesEnableAvatarReplyTypes");
    hookReplyToggleIfNeeded(sciGifsReplyEnabled(), @"_IGDirectNotesEnableGifsStickersReplyTypes");
    hookReplyToggleIfNeeded(sciPhotoReplyEnabled(), @"_IGDirectNotesEnablePhotoNoteReplyType");
}
