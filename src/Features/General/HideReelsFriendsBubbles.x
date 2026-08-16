// Reels: hide the friends-tab avatar bubbles and the floating social-context
// overlay (reposted / commented / etc).

#import "../../Utils.h"
#import "../../InstagramHeaders.h"
#import <objc/runtime.h>

// MARK: - Friends-tab avatar bubbles

// Cached ancestor check so the sizing hooks below don't re-walk per call.
static const void *kRYGFRBScopedKey = &kRYGFRBScopedKey;

static BOOL rygFRBIsReelsFacepile(UIView *v) {
    NSNumber *cached = objc_getAssociatedObject(v, kRYGFRBScopedKey);
    if (cached) return cached.boolValue;
    Class tabCls = NSClassFromString(
        @"_TtC32IGSundialFriendsLaneEntryPointUI30IGFriendsLaneEntryPointTabView");
    BOOL ok = NO;
    for (UIView *p = v; p; p = p.superview) {
        if (tabCls && [p isKindOfClass:tabCls]) { ok = YES; break; }
    }
    if (v.window) {
        objc_setAssociatedObject(v, kRYGFRBScopedKey, @(ok), OBJC_ASSOCIATION_RETAIN);
    }
    return ok;
}

%hook IGStoryFacepileView

- (void)setFrame:(CGRect)frame {
    if ([RYGUtils getBoolPref:@"hide_reels_friends_bubbles"] && rygFRBIsReelsFacepile(self)) {
        frame.size = CGSizeZero;
    }
    %orig(frame);
}

- (void)setBounds:(CGRect)bounds {
    if ([RYGUtils getBoolPref:@"hide_reels_friends_bubbles"] && rygFRBIsReelsFacepile(self)) {
        bounds.size = CGSizeZero;
    }
    %orig(bounds);
}

- (CGSize)sizeThatFits:(CGSize)size {
    if ([RYGUtils getBoolPref:@"hide_reels_friends_bubbles"] && rygFRBIsReelsFacepile(self)) {
        return CGSizeZero;
    }
    return %orig;
}

- (CGSize)intrinsicContentSize {
    if ([RYGUtils getBoolPref:@"hide_reels_friends_bubbles"] && rygFRBIsReelsFacepile(self)) {
        return CGSizeZero;
    }
    return %orig;
}

- (void)didMoveToWindow {
    %orig;
    if (!self.window) return;
    if ([RYGUtils getBoolPref:@"hide_reels_friends_bubbles"] && rygFRBIsReelsFacepile(self)) {
        self.hidden = YES;
    }
}

%end

// MARK: - Floating social context overlay

%hook _TtC25IGFloatingSocialContextUI39IGFloatingSocialContextMediaOverlayView

- (void)setHidden:(BOOL)hidden {
    if ([RYGUtils getBoolPref:@"hide_reels_floating_social_context"]) {
        %orig(YES);
    } else {
        %orig(hidden);
    }
}

- (void)didMoveToWindow {
    %orig;
    if (self.window && [RYGUtils getBoolPref:@"hide_reels_floating_social_context"]) {
        self.hidden = YES;
    }
}

%end
