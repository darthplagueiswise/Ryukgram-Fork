#import "../../Utils.h"
#import <objc/runtime.h>

// Highlights vs stories split by _analyticsModule substring.
static BOOL rygTapIsHighlight(id target) {
    Ivar iv = class_getInstanceVariable(object_getClass(target), "_analyticsModule");
    if (!iv) return NO;
    id v = nil;
    @try { v = object_getIvar(target, iv); } @catch (__unused id e) { return NO; }
    if (![v isKindOfClass:[NSString class]]) return NO;
    return [((NSString *)v).lowercaseString containsString:@"highlight"];
}

static id rygReadIvar(id obj, const char *name) {
    if (!obj || !name) return nil;
    Class c = object_getClass(obj);
    Ivar iv = nil;
    while (c && !iv) {
        iv = class_getInstanceVariable(c, name);
        if (!iv) c = class_getSuperclass(c);
    }
    if (!iv) return nil;
    id v = nil;
    @try { v = object_getIvar(obj, iv); } @catch (__unused id e) {}
    return v;
}

// IGStoryOverlayTapModelObject uses one-ivar-per-sticker-kind.
// Extend to grow "reactions only" scope to polls/sliders/quizzes if needed.
static const char * const kRygReactionIvars[] = {
    "_reactionSticker_reactionStickerDataFragment",
    NULL
};

// IGStoryViewerTapTarget._tappableOverlay._object._tapModelObject.<ivar> non-nil iff reaction.
static BOOL rygTapIsReactionSticker(id target) {
    id overlay = rygReadIvar(target, "_tappableOverlay");
    if (!overlay) return NO;
    id obj = rygReadIvar(overlay, "_object");
    if (!obj) return NO;
    id tapObj = rygReadIvar(obj, "_tapModelObject");
    if (!tapObj) return NO;

    for (const char * const *name = kRygReactionIvars; *name; name++) {
        if (rygReadIvar(tapObj, *name)) return YES;
    }
    return NO;
}

%hook IGStoryViewerTapTarget
- (void)_didTap:(id)arg1 forEvent:(id)arg2 {
    BOOL highlight = rygTapIsHighlight(self);
    NSString *mode = [RYGUtils getStringPref:highlight ? @"sticker_interact_highlights_mode"
                                                       : @"sticker_interact_stories_mode"];
    if (!mode.length || [mode isEqualToString:@"off"]) return %orig;
    if ([mode isEqualToString:@"reactions"] && !rygTapIsReactionSticker(self)) return %orig;

    NSString *title = highlight ? RYGLocalized(@"Confirm sticker interaction (highlights)")
                                : RYGLocalized(@"Confirm sticker interaction (stories)");
    [RYGUtils showConfirmation:^(void) { %orig; } title:title];
}
%end
