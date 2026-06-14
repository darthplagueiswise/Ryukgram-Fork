// Confirm note likes (like button, double-tap in tray/profile) + emoji quick-reaction.

#import "../../Utils.h"
#import <objc/runtime.h>
#import <objc/message.h>
#import <substrate.h>

typedef void (*SciVoidFn)(id, SEL);
typedef void (*SciTap1Fn)(id, SEL, id);
typedef void (*SciTap2Fn)(id, SEL, id, id);
typedef void (*SciTrayDoubleTapFn)(id, SEL, id, id, NSInteger, id);

static SciVoidFn orig_composerLike   = NULL;
static SciTap2Fn orig_emojiQuickTap  = NULL;
static SciTrayDoubleTapFn orig_trayDoubleTap = NULL;
static SciTap1Fn orig_profileDoubleTap = NULL;

static void new_composerLike(id self, SEL _cmd) {
    if (![SCIUtils getBoolPref:@"note_like_confirm"]) { orig_composerLike(self, _cmd); return; }
    __strong id sSelf = self;
    [SCIUtils showConfirmation:^{
        @try { orig_composerLike(sSelf, _cmd); }
        @catch (__unused id e) {}
    } title:SCILocalized(@"Confirm note like")];
}

// IG 431 routes the emoji quick-reaction tap through the input view's delegate.
// The notes reply composer VC is itself that delegate, so this is already note-scoped.
static void new_emojiQuickTap(id self, SEL _cmd, id inputView, id button) {
    if (![SCIUtils getBoolPref:@"note_react_confirm"]) {
        orig_emojiQuickTap(self, _cmd, inputView, button);
        return;
    }
    __strong id sSelf = self, sIn = inputView, sBtn = button;
    [SCIUtils showConfirmation:^{
        @try { orig_emojiQuickTap(sSelf, _cmd, sIn, sBtn); }
        @catch (__unused id e) {}
    } title:SCILocalized(@"Confirm note emoji reaction")];
}

// Double-tap to like in the DM inbox tray — the cell/section-controller chain
// bottoms out here on IGNotesTrayController.
static void new_trayDoubleTap(id self, SEL _cmd, id sectionController, id viewModel, NSInteger itemPosition, id pogCell) {
    if (![SCIUtils getBoolPref:@"note_like_confirm"]) {
        orig_trayDoubleTap(self, _cmd, sectionController, viewModel, itemPosition, pogCell);
        return;
    }
    __strong id sSelf = self, sSec = sectionController, sVM = viewModel, sPog = pogCell;
    [SCIUtils showConfirmation:^{
        @try { orig_trayDoubleTap(sSelf, _cmd, sSec, sVM, itemPosition, sPog); }
        @catch (__unused id e) {}
    } title:SCILocalized(@"Confirm note like")];
}

// Double-tap to like a note shown on a profile.
static void new_profileDoubleTap(id self, SEL _cmd, id note) {
    if (![SCIUtils getBoolPref:@"note_like_confirm"]) {
        orig_profileDoubleTap(self, _cmd, note);
        return;
    }
    __strong id sSelf = self, sNote = note;
    [SCIUtils showConfirmation:^{
        @try { orig_profileDoubleTap(sSelf, _cmd, sNote); }
        @catch (__unused id e) {}
    } title:SCILocalized(@"Confirm note like")];
}

%ctor {
    SEL sComposerLike = NSSelectorFromString(@"didTapLikeButton");
    SEL sEmojiQuick   = NSSelectorFromString(@"inputView:didTapEmojiQuickReactionButton:");
    SEL sTrayDouble   = NSSelectorFromString(@"notesTrayRowSectionController:didDoubleTapViewModel:itemPosition:pogCell:");
    SEL sProfDouble   = NSSelectorFromString(@"handleNoteDoubleTap:");

    Class tray = NSClassFromString(@"_TtC21IGNotesTrayController21IGNotesTrayController");
    if (tray && class_getInstanceMethod(tray, sTrayDouble))
        MSHookMessageEx(tray, sTrayDouble, (IMP)new_trayDoubleTap, (IMP *)&orig_trayDoubleTap);

    Class prof = NSClassFromString(@"_TtC21IGProfileDetailHeader32IGProfileAvatarActionsController");
    if (prof && class_getInstanceMethod(prof, sProfDouble))
        MSHookMessageEx(prof, sProfDouble, (IMP)new_profileDoubleTap, (IMP *)&orig_profileDoubleTap);

    Class composer = NSClassFromString(@"_TtC26IGDirectReplyToAuthorSwift33IGDirectReplyToAuthorComposerView");
    if (composer && class_getInstanceMethod(composer, sComposerLike))
        MSHookMessageEx(composer, sComposerLike, (IMP)new_composerLike, (IMP *)&orig_composerLike);

    Class replyComposer = NSClassFromString(@"IGDirectReplyToAuthorComposerViewController");
    if (replyComposer && class_getInstanceMethod(replyComposer, sEmojiQuick))
        MSHookMessageEx(replyComposer, sEmojiQuick, (IMP)new_emojiQuickTap, (IMP *)&orig_emojiQuickTap);
}
