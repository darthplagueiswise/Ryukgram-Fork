// Story reply + emoji reaction hooks. Routes through the interaction pipeline.

#import "RYGStoryInteractionPipeline.h"
#import "../../Utils.h"
#import "StoryHelpers.h"
#import <objc/message.h>
#import <objc/runtime.h>
#import <substrate.h>

extern __weak UIViewController *rygActiveStoryVC;
extern BOOL rygAdvanceBypassActive;

// Reply-to-author sheet path: text / sticker / voice.
%hook IGDirectReplyToAuthorSendManager
- (void)sendWithText:(id)text privateReplyEmoji:(id)emoji selectedMusic:(id)music {
    %orig;
    if (rygActiveStoryVC) rygStoryInteraction(RYGStoryInteractionTextReply, nil, nil, nil);
}
- (void)sendStickerReply:(id)sticker {
    %orig;
    if (rygActiveStoryVC) rygStoryInteraction(RYGStoryInteractionTextReply, nil, nil, nil);
}
- (void)sendAudioClipWithURL:(id)url waveform:(id)waveform duration:(double)duration {
    %orig;
    if (rygActiveStoryVC) rygStoryInteraction(RYGStoryInteractionTextReply, nil, nil, nil);
}
%end

// Inline reply bar: the send pill lives inside IGDirectComposerOvalContainerView —
// match the container, not the label, so it's language-independent.
%hook IGTapButton
- (void)didTapSwiftOnALButton:(id)arg {
    %orig;
    if (!rygActiveStoryVC) return;
    for (UIView *a = ((UIView *)self).superview; a; a = a.superview) {
        if ([NSStringFromClass(a.class) containsString:@"IGDirectComposerOvalContainer"]) {
            rygStoryInteraction(RYGStoryInteractionTextReply, nil, nil, nil);
            return;
        }
    }
}
%end

// Composer's send callback (alternate path).
%hook IGDirectReplyToAuthorViewController
- (void)replyToAuthorComposerViewControllerDidSend {
    %orig;
    if (rygActiveStoryVC) rygStoryInteraction(RYGStoryInteractionTextReply, nil, nil, nil);
}
- (void)replyToAuthorComposerViewControllerDidTapSendButton:(id)composer text:(id)text {
    %orig;
    if (rygActiveStoryVC) rygStoryInteraction(RYGStoryInteractionTextReply, nil, nil, nil);
}
%end

// Composer emoji reaction buttons
static void (*orig_footerEmojiQuick)(id, SEL, id, id);
static void new_footerEmojiQuick(id self, SEL _cmd, id inputView, id btn) {
    rygStoryInteraction(RYGStoryInteractionEmojiReaction,
        ^{ orig_footerEmojiQuick(self, _cmd, inputView, btn); }, nil, nil);
}

static void (*orig_footerEmojiReaction)(id, SEL, id, id);
static void new_footerEmojiReaction(id self, SEL _cmd, id inputView, id btn) {
    rygStoryInteraction(RYGStoryInteractionEmojiReaction,
        ^{ orig_footerEmojiReaction(self, _cmd, inputView, btn); }, nil, nil);
}

// Swipe-up quick reactions. qrCtrl → qrDelegate internally, gate only qrCtrl.
static void (*orig_qrCtrlDidTapEmoji)(id, SEL, id, id, id);
static void new_qrCtrlDidTapEmoji(id self, SEL _cmd, id view, id sourceBtn, id emoji) {
    rygStoryInteraction(RYGStoryInteractionEmojiReaction,
        ^{ orig_qrCtrlDidTapEmoji(self, _cmd, view, sourceBtn, emoji); }, nil, nil);
}

static void (*orig_qrDelegateDidTapEmoji)(id, SEL, id, id, id);
static void new_qrDelegateDidTapEmoji(id self, SEL _cmd, id ctrl, id sourceBtn, id emoji) {
    orig_qrDelegateDidTapEmoji(self, _cmd, ctrl, sourceBtn, emoji);
}

static void rygInstallReplyHooks(void) {
    static BOOL installed = NO;
    if (installed) return;

    Class footerCls  = NSClassFromString(@"IGStoryDefaultFooter.IGStoryFullscreenDefaultFooterView");
    Class qrCtrl     = NSClassFromString(@"IGStoryQuickReactions.IGStoryQuickReactionsController");
    Class qrDelegate = NSClassFromString(@"IGStoryQuickReactionsDelegate.IGStoryQuickReactionsDelegateImpl");
    if (!footerCls || !qrCtrl || !qrDelegate) return;
    installed = YES;

    SEL quick = NSSelectorFromString(@"inputView:didTapEmojiQuickReactionButton:");
    if (class_getInstanceMethod(footerCls, quick))
        MSHookMessageEx(footerCls, quick, (IMP)new_footerEmojiQuick, (IMP *)&orig_footerEmojiQuick);

    SEL reaction = NSSelectorFromString(@"inputView:didTapEmojiReactionButton:");
    if (class_getInstanceMethod(footerCls, reaction))
        MSHookMessageEx(footerCls, reaction, (IMP)new_footerEmojiReaction, (IMP *)&orig_footerEmojiReaction);

    SEL qrSel = NSSelectorFromString(@"quickReactionsView:sourceEmojiButton:didTapEmoji:");
    if (class_getInstanceMethod(qrCtrl, qrSel))
        MSHookMessageEx(qrCtrl, qrSel, (IMP)new_qrCtrlDidTapEmoji, (IMP *)&orig_qrCtrlDidTapEmoji);

    SEL qrdSel = NSSelectorFromString(@"storyQuickReactionsController:sourceEmojiButton:didTapEmoji:");
    if (class_getInstanceMethod(qrDelegate, qrdSel))
        MSHookMessageEx(qrDelegate, qrdSel, (IMP)new_qrDelegateDidTapEmoji, (IMP *)&orig_qrDelegateDidTapEmoji);
}

%hook IGStoryFullscreenOverlayView
- (void)didMoveToWindow {
    %orig;
    rygInstallReplyHooks();
}
%end

%ctor {
    rygInstallReplyHooks();
}
