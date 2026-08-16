#import "../../Utils.h"
#import <objc/runtime.h>
#import <objc/message.h>
#import <substrate.h>

static BOOL rygDMReactInFlight = NO;

static BOOL rygDMReactModeAll(void) {
    return [[RYGUtils getStringPref:@"dm_reaction_confirm_mode"] isEqualToString:@"all"];
}

static BOOL rygDMReactModeOn(void) {
    NSString *m = [RYGUtils getStringPref:@"dm_reaction_confirm_mode"];
    return [m isEqualToString:@"all"] || [m isEqualToString:@"double_tap"];
}

// Section components hold the Swift reaction controller as a concrete type, so its
// double-tap entry is statically dispatched. Their own is a protocol method.
static void rygConfirmDMDoubleTap(dispatch_block_t originalAction) {
    if (!originalAction) return;
    if (!rygDMReactModeOn() || rygDMReactInFlight) {
        originalAction();
        return;
    }
    [RYGUtils showConfirmation:^{
        rygDMReactInFlight = YES;
        @try { originalAction(); } @catch (__unused id e) {}
        rygDMReactInFlight = NO;
    } title:RYGLocalized(@"Confirm reaction")];
}

%hook IGDirectMessageSectionComponents
- (void)performDoubleTapActionForCell:(id)cell withViewModel:(id)model {
    rygConfirmDMDoubleTap(^{
        %orig;
    });
}
%end

%hook IGDirectMessageStickerSectionComponents
- (void)performDoubleTapActionForCell:(id)cell withViewModel:(id)model {
    rygConfirmDMDoubleTap(^{
        %orig;
    });
}
%end

%hook IGDirectMessageThreadedRepliesSectionComponents
- (void)performDoubleTapActionForCell:(id)cell withViewModel:(id)model {
    rygConfirmDMDoubleTap(^{
        %orig;
    });
}
%end

static void (*orig_rygDMReactForCell)(id, SEL, id, id, BOOL, id, long long, id);
static void new_rygDMReactForCell(id self, SEL _cmd, id cell, id emoji, BOOL superReact, id model, long long source, id sessionId) {
    if (!rygDMReactModeAll() || rygDMReactInFlight) {
        orig_rygDMReactForCell(self, _cmd, cell, emoji, superReact, model, source, sessionId);
        return;
    }
    __strong id sCell = cell;
    __strong id sEmoji = emoji;
    __strong id sModel = model;
    __strong id sSession = sessionId;
    [RYGUtils showConfirmation:^{
        rygDMReactInFlight = YES;
        @try { orig_rygDMReactForCell(self, _cmd, sCell, sEmoji, superReact, sModel, source, sSession); }
        @catch (__unused id e) {}
        rygDMReactInFlight = NO;
    } title:RYGLocalized(@"Confirm reaction")];
}

static void (*orig_rygDMToggleEmoji)(id, SEL, id, id, BOOL, BOOL, long long, id);
static void new_rygDMToggleEmoji(id self, SEL _cmd, id vc, id emoji, BOOL selected, BOOL superReact, long long source, id sessionId) {
    if (!rygDMReactModeAll() || rygDMReactInFlight) {
        orig_rygDMToggleEmoji(self, _cmd, vc, emoji, selected, superReact, source, sessionId);
        return;
    }
    __strong id sVC = vc;
    __strong id sEmoji = emoji;
    __strong id sSession = sessionId;
    [RYGUtils showConfirmation:^{
        rygDMReactInFlight = YES;
        @try { orig_rygDMToggleEmoji(self, _cmd, sVC, sEmoji, selected, superReact, source, sSession); }
        @catch (__unused id e) {}
        rygDMReactInFlight = NO;
    } title:RYGLocalized(@"Confirm reaction")];
}

%ctor {
    Class cls = NSClassFromString(@"_TtC33IGDirectMessageReactionController33IGDirectMessageReactionController");
    if (!cls) cls = NSClassFromString(@"IGDirectMessageReactionController");
    if (!cls) return;

    SEL forCell = NSSelectorFromString(@"reactWithEmojiReactionForCell:emoji:isSuperReact:messageViewModel:actionSource:bottomSheetSessionId:");
    if (class_getInstanceMethod(cls, forCell))
        MSHookMessageEx(cls, forCell, (IMP)new_rygDMReactForCell, (IMP *)&orig_rygDMReactForCell);

    SEL toggle = NSSelectorFromString(@"messageReactionSelectionViewController:didToggleEmoji:isSelected:isSuperReact:actionSource:bottomSheetSessionId:");
    if (class_getInstanceMethod(cls, toggle))
        MSHookMessageEx(cls, toggle, (IMP)new_rygDMToggleEmoji, (IMP *)&orig_rygDMToggleEmoji);
}
