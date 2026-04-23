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

static void hookInstanceBool1(NSString *className, NSString *selName, IMP newImp, IMP *orig) {
    Class cls = NSClassFromString(className);
    if (!cls) return;
    SEL sel = NSSelectorFromString(selName);
    if (!class_getInstanceMethod(cls, sel)) return;
    MSHookMessageEx(cls, sel, newImp, orig);
}

static void hookReplyToggleIfNeeded(BOOL enabled, NSString *className) {
    if (!enabled) return;
    hookClassBool0(className, @"isEnabled", (IMP)new_reply_enabled, (IMP *)&orig_reply_enabled);
    hookClassBool0(className, @"enabled", (IMP)new_reply_enabled, NULL);
}

%ctor {
    Class helper = NSClassFromString(@"IGDirectNotesExperimentHelper");
    SEL sel = NSSelectorFromString(@"isInExperiment:");
    if (helper && class_getInstanceMethod(helper, sel)) {
        MSHookMessageEx(helper, sel, (IMP)new_isInExperiment, (IMP *)&orig_isInExperiment);
    }

    hookReplyToggleIfNeeded(sciFriendMapEnabled(), @"_IGDirectNotesFriendMapEnabled");
    hookReplyToggleIfNeeded(sciAudioReplyEnabled(), @"_IGDirectNotesEnableAudioNoteReplyType");
    hookReplyToggleIfNeeded(sciAvatarReplyEnabled(), @"_IGDirectNotesEnableAvatarReplyTypes");
    hookReplyToggleIfNeeded(sciGifsReplyEnabled(), @"_IGDirectNotesEnableGifsStickersReplyTypes");
    hookReplyToggleIfNeeded(sciPhotoReplyEnabled(), @"_IGDirectNotesEnablePhotoNoteReplyType");
}
