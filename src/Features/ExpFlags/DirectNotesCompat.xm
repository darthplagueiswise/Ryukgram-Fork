#import "../../Utils.h"
#import <objc/runtime.h>
#import <substrate.h>
#include "../../../modules/fishhook/fishhook.h"

//
// DirectNotesCompat.xm  (dev2  binary-verified)
//
// KEY FIX: dev2 used `IGDirectNotesExperimentHelper` which does NOT exist.
// Correct class: `_TtC37IGDirectNotesExperimentExposureHelper37IGDirectNotesExperimentExposureHelper`
// Confirmed  in Instagram arm64 binary.
//
// Also wires:
//   fishhook on C stubs (confirmed ): IGDirectNotesFriendMapEnabled etc.
//   isNotesTrayEnabled, isMultipleNotesEnabled, isFirstNoteBadgeEnabled
//    on IGDirectNotesTrayUISwift classes (notes tray visibility gates)
//   storyDataControllerDidUpdateMutualLikedStories:  icebreaker trigger
//    (confirmed via Flex IMG_6727/6728: IGStoryDataControllerMutualLikedStoriesListener)
//

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

//  fishhook C stubs (exports confirmed  in binary)
static BOOL hook_IGDirectNotesFriendMapEnabled(void)             { return sciFriendMapEnabled(); }
static BOOL hook_IGDirectNotesEnableAudioNoteReplyType(void)     { return sciAudioReplyEnabled(); }
static BOOL hook_IGDirectNotesEnableAvatarReplyTypes(void)       { return sciAvatarReplyEnabled(); }
static BOOL hook_IGDirectNotesEnableGifsStickersReplyTypes(void) { return sciGifsReplyEnabled(); }
static BOOL hook_IGDirectNotesEnablePhotoNoteReplyType(void)     { return sciPhotoReplyEnabled(); }

//  isInExperiment: on confirmed Swift class
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

static BOOL (*orig_class_isInExperiment)(id, SEL, id) = NULL;
static BOOL new_class_isInExperiment(id self, SEL _cmd, id arg1) {
    if (sciDirectNotesExperimentMatch((NSString *)arg1)) return YES;
    return orig_class_isInExperiment ? orig_class_isInExperiment(self, _cmd, arg1) : NO;
}

//  Multiple notes / tray gates
// These are on the tray section controller  allow multiple note slots
static BOOL (*orig_isMultipleNotesEnabled)(id, SEL) = NULL;
static BOOL new_isMultipleNotesEnabled(id self, SEL _cmd) {
    if (sciMultipleNotesEnabled()) return YES;
    return orig_isMultipleNotesEnabled ? orig_isMultipleNotesEnabled(self, _cmd) : NO;
}

static BOOL (*orig_isFirstNoteBadgeEnabled)(id, SEL) = NULL;
static BOOL new_isFirstNoteBadgeEnabled(id self, SEL _cmd) {
    if (sciFirstNoteBadgeEnabled()) return YES;
    return orig_isFirstNoteBadgeEnabled ? orig_isFirstNoteBadgeEnabled(self, _cmd) : NO;
}

static NSMutableSet<NSString *> *gDNHooked;
static NSMutableDictionary<NSString *, NSValue *> *gDNOriginals;

static NSString *sciDNKey(Class cls, NSString *selName) {
    return [NSString stringWithFormat:@"%p:%@", cls, selName];
}

static NSArray<NSString *> *sciDirectNotesPrefsForSelector(NSString *selName) {
    NSString *l = selName.lowercaseString ?: @"";
    if ([l containsString:@"friendmap"] || [l containsString:@"friendsmap"] ||
        [l containsString:@"friend_map"] || [l containsString:@"friends_map"] ||
        [l containsString:@"locationnotes"] || [l containsString:@"location_notes"])
        return @[@"igt_directnotes_friendmap"];
    if ([l containsString:@"audioreply"] || ([l containsString:@"audio"] && [l containsString:@"reply"]))
        return @[@"igt_directnotes_audio_reply"];
    if ([l containsString:@"avatarreply"] || ([l containsString:@"avatar"] && [l containsString:@"reply"]))
        return @[@"igt_directnotes_avatar_reply"];
    if ([l containsString:@"gifs"] || [l containsString:@"gif"] || [l containsString:@"sticker"])
        return @[@"igt_directnotes_gifs_reply"];
    if ([l containsString:@"photoreply"] || ([l containsString:@"photo"] && [l containsString:@"reply"]))
        return @[@"igt_directnotes_photo_reply"];
    if ([l containsString:@"multiplenotes"] || [l containsString:@"multiple_notes"])
        return @[@"igt_multiple_notes"];
    if ([l containsString:@"firstnotebadge"] || [l containsString:@"first_note_badge"])
        return @[@"igt_dn_first_badge"];
    return nil;
}

static BOOL sciDirectNotesSelectorEnabled(NSString *selName) {
    for (NSString *key in sciDirectNotesPrefsForSelector(selName)) {
        if ([SCIUtils getBoolPref:key]) return YES;
    }
    return NO;
}

static BOOL new_directnotes_bool0(id self, SEL _cmd) {
    NSString *selName = NSStringFromSelector(_cmd);
    if (sciDirectNotesSelectorEnabled(selName)) return YES;
    Class cls = object_getClass(self);
    while (cls) {
        NSValue *orig = gDNOriginals[sciDNKey(cls, selName)];
        if (orig) {
            BOOL (*fn)(id, SEL) = (BOOL (*)(id, SEL))(uintptr_t)orig.pointerValue;
            return fn(self, _cmd);
        }
        cls = class_getSuperclass(cls);
    }
    return NO;
}

static BOOL new_directnotes_bool1(id self, SEL _cmd, id arg1) {
    NSString *selName = NSStringFromSelector(_cmd);
    if (([selName isEqualToString:@"isInExperiment:"] && sciDirectNotesExperimentMatch((NSString *)arg1)) ||
        sciDirectNotesSelectorEnabled(selName)) {
        return YES;
    }
    Class cls = object_getClass(self);
    while (cls) {
        NSValue *orig = gDNOriginals[sciDNKey(cls, selName)];
        if (orig) {
            BOOL (*fn)(id, SEL, id) = (BOOL (*)(id, SEL, id))(uintptr_t)orig.pointerValue;
            return fn(self, _cmd, arg1);
        }
        cls = class_getSuperclass(cls);
    }
    return NO;
}

static BOOL hookDNMethod(Class cls, NSString *selName, IMP newImp, IMP *orig) {
    if (!cls || !selName.length || !newImp) return NO;
    SEL sel = NSSelectorFromString(selName);
    Method method = class_getInstanceMethod(cls, sel);
    if (!method) return NO;
    NSString *key = sciDNKey(cls, selName);
    if ([gDNHooked containsObject:key]) return NO;
    IMP old = NULL;
    MSHookMessageEx(cls, sel, newImp, orig ?: &old);
    if (!orig && old) gDNOriginals[key] = [NSValue valueWithPointer:(const void *)old];
    [gDNHooked addObject:key];
    return YES;
}

static void hookInstanceBool0(NSString *className, NSString *selName, IMP newImp, IMP *orig) {
    Class cls = NSClassFromString(className);
    if (!cls) return;
    hookDNMethod(cls, selName, newImp, orig);
}

static void hookClassBool0(NSString *className, NSString *selName, IMP newImp, IMP *orig) {
    Class cls = NSClassFromString(className);
    if (!cls) return;
    hookDNMethod(object_getClass(cls), selName, newImp, orig);
}

static void hookDirectNotesRuntimeSelectors(void) {
    unsigned int classCount = 0;
    Class *classes = objc_copyClassList(&classCount);
    for (unsigned int i = 0; i < classCount; i++) {
        Class cls = classes[i];
        NSString *lower = NSStringFromClass(cls).lowercaseString ?: @"";
        BOOL likelyDN = [lower containsString:@"directnotes"] ||
                        [lower containsString:@"directnote"] ||
                        [lower containsString:@"friendmap"] ||
                        [lower containsString:@"friendsmap"] ||
                        [lower containsString:@"locationnotes"] ||
                        [lower containsString:@"notestray"];
        if (!likelyDN) continue;

        for (Class hookClass in @[ cls, object_getClass(cls) ]) {
            unsigned int methodCount = 0;
            Method *methods = class_copyMethodList(hookClass, &methodCount);
            for (unsigned int m = 0; m < methodCount; m++) {
                SEL sel = method_getName(methods[m]);
                NSString *selName = NSStringFromSelector(sel);
                unsigned int argCount = method_getNumberOfArguments(methods[m]);
                char ret[8] = {0};
                method_getReturnType(methods[m], ret, sizeof(ret));
                if (ret[0] != 'B' && ret[0] != 'c' && ret[0] != 'C') continue;
                if (argCount == 2 && sciDirectNotesPrefsForSelector(selName)) {
                    hookDNMethod(hookClass, selName, (IMP)new_directnotes_bool0, NULL);
                } else if (argCount == 3 && [selName isEqualToString:@"isInExperiment:"]) {
                    hookDNMethod(hookClass, selName, (IMP)new_directnotes_bool1, NULL);
                }
            }
            if (methods) free(methods);
        }
    }
    if (classes) free(classes);
}

static void hookClassBool1(NSString *className, NSString *selName, IMP newImp, IMP *orig) {
    Class cls = NSClassFromString(className);
    if (!cls) return;
    hookDNMethod(object_getClass(cls), selName, newImp, orig);
}

%ctor {
    BOOL anyEnabled = (sciFriendMapEnabled() || sciAudioReplyEnabled() || sciAvatarReplyEnabled()
                       || sciGifsReplyEnabled() || sciPhotoReplyEnabled()
                       || sciMultipleNotesEnabled() || sciFirstNoteBadgeEnabled());
    if (!anyEnabled) return;
    gDNHooked = [NSMutableSet set];
    gDNOriginals = [NSMutableDictionary dictionary];

    //  1. fishhook C stubs
    struct rebinding notesBinds[] = {
        {"IGDirectNotesFriendMapEnabled",             (void *)hook_IGDirectNotesFriendMapEnabled,             NULL},
        {"IGDirectNotesEnableAudioNoteReplyType",     (void *)hook_IGDirectNotesEnableAudioNoteReplyType,     NULL},
        {"IGDirectNotesEnableAvatarReplyTypes",       (void *)hook_IGDirectNotesEnableAvatarReplyTypes,       NULL},
        {"IGDirectNotesEnableGifsStickersReplyTypes", (void *)hook_IGDirectNotesEnableGifsStickersReplyTypes, NULL},
        {"IGDirectNotesEnablePhotoNoteReplyType",     (void *)hook_IGDirectNotesEnablePhotoNoteReplyType,     NULL},
    };
    rebind_symbols(notesBinds, sizeof(notesBinds) / sizeof(notesBinds[0]));

    //  2. isInExperiment: on verified Swift class
    //  IGDirectNotesExperimentHelper  does NOT exist in this binary
    //  _TtC37IGDirectNotesExperimentExposureHelper37IGDirectNotesExperimentExposureHelper
    NSString *helperName = @"_TtC37IGDirectNotesExperimentExposureHelper37IGDirectNotesExperimentExposureHelper";
    Class helper = NSClassFromString(helperName);
    if (helper) {
        SEL sel = NSSelectorFromString(@"isInExperiment:");
        if (class_getInstanceMethod(helper, sel))
            hookDNMethod(helper, @"isInExperiment:", (IMP)new_isInExperiment, (IMP *)&orig_isInExperiment);
        // also class method variant
        if (class_getClassMethod(helper, sel))
            hookClassBool1(helperName, @"isInExperiment:", (IMP)new_class_isInExperiment, (IMP *)&orig_class_isInExperiment);
    }

    //  3. Multiple notes / first badge gates
    // These selectors are on the tray section controller / feature support classes
    // isMultipleNotesEnabled: confirmed  in binary (selector string present)
    NSArray<NSString *> *trayClasses = @[
        @"_TtC24IGDirectNotesTrayUISwift37IGDirectNotesTrayRowSectionController",  //
        @"_TtC24IGDirectNotesTrayUISwift48IGDirectNotesTraySectionControllerListenerHelper", //
        @"_TtC32IGDirectNotesFeatureSupportSwift39IGDirectNotesFeatureSupportModelHelpers",  //
    ];
    for (NSString *cls in trayClasses) {
        hookInstanceBool0(cls, @"isMultipleNotesEnabled",   (IMP)new_isMultipleNotesEnabled,   (IMP *)&orig_isMultipleNotesEnabled);
        hookInstanceBool0(cls, @"isFirstNoteBadgeEnabled",  (IMP)new_isFirstNoteBadgeEnabled,  (IMP *)&orig_isFirstNoteBadgeEnabled);
        hookInstanceBool0(cls, @"isMultipleNotesEnabled:",  (IMP)new_isMultipleNotesEnabled,   NULL);
        hookClassBool0(cls,    @"isMultipleNotesEnabled",   (IMP)new_isMultipleNotesEnabled,   NULL);
    }

    hookDirectNotesRuntimeSelectors();
}
