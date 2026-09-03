// Hide / confirm the "Send to group chat" facepile shown under "Send separately"
// in the share sheet. Classes declared in InstagramHeaders.h.

#import "../../Utils.h"
#import "../../InstagramHeaders.h"
#import <objc/runtime.h>

static const void *kRYGSTGTapKey = &kRYGSTGTapKey;

static BOOL rygSTGIsFacepileClass(UIView *v) {
    return [NSStringFromClass([v class]) containsString:@"CreateOrSendToGroupFacepileButton"];
}

static UIView *rygSTGFindInner(UIView *outer) {
    UIView *inner = nil;
    @try { inner = [outer valueForKey:@"bottomButtonsView"]; } @catch (__unused id e) {}
    if (!inner) {
        for (UIView *sub in outer.subviews) {
            if ([NSStringFromClass([sub class]) containsString:@"IGSharesheetBottomButtonsView"]) {
                return sub;
            }
        }
    }
    return inner;
}

// Shrink the bottom-buttons container to fit only its non-facepile children
// plus a small bottom margin. Never grows the size.
static CGSize rygSTGShrunkSize(UIView *outer, CGSize fallback) {
    UIView *inner = rygSTGFindInner(outer);
    if (!inner) return fallback;
    CGFloat maxY = 0;
    for (UIView *sub in inner.subviews) {
        if (rygSTGIsFacepileClass(sub)) continue;
        if (sub.hidden || CGRectIsEmpty(sub.frame)) continue;
        maxY = fmax(maxY, CGRectGetMaxY(sub.frame));
    }
    if (maxY > 0 && maxY + 16 < fallback.height) {
        return CGSizeMake(fallback.width, maxY + 16);
    }
    return fallback;
}

%hook _TtC12IGShareSheet38IGShareSheetBottomButtonsViewContainer

- (CGSize)intrinsicContentSize {
    CGSize r = %orig;
    if (![RYGUtils getBoolPref:@"hide_send_to_group"]) return r;
    CGSize s = rygSTGShrunkSize(self, r);
    if (!CGSizeEqualToSize(s, r)) [self invalidateIntrinsicContentSize];
    return s;
}

- (CGSize)sizeThatFits:(CGSize)size {
    CGSize r = %orig;
    if (![RYGUtils getBoolPref:@"hide_send_to_group"]) return r;
    return rygSTGShrunkSize(self, r);
}

%end

%hook _TtC12IGShareSheet45IGShareSheetCreateOrSendToGroupFacepileButton

- (CGSize)sizeThatFits:(CGSize)size {
    if ([RYGUtils getBoolPref:@"hide_send_to_group"]) return CGSizeZero;
    return %orig;
}

- (CGSize)intrinsicContentSize {
    if ([RYGUtils getBoolPref:@"hide_send_to_group"]) return CGSizeZero;
    return %orig;
}

- (void)didMoveToSuperview {
    %orig;
    if (![RYGUtils getBoolPref:@"hide_send_to_group"] || !self.superview) return;
    self.hidden = YES;
    for (UIView *p = self; p; p = p.superview) {
        [p invalidateIntrinsicContentSize];
        [p setNeedsLayout];
    }
}

- (void)didMoveToWindow {
    %orig;
    if (!self.window) return;
    if ([RYGUtils getBoolPref:@"hide_send_to_group"]) {
        self.hidden = YES;
        return;
    }
    if (![RYGUtils getBoolPref:@"confirm_send_to_group"]) return;
    if (objc_getAssociatedObject(self, kRYGSTGTapKey)) return;

    UITapGestureRecognizer *tap = [[UITapGestureRecognizer alloc]
        initWithTarget:self action:@selector(rygSTGHandleTap:)];
    tap.cancelsTouchesInView = YES;
    [self addGestureRecognizer:tap];
    objc_setAssociatedObject(self, kRYGSTGTapKey, tap, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
}

// FacepileButton inherits from UIControl with secondaryButtonTappedWithButton:
// registered for TouchUpInside. Replay it after confirmation.
%new - (void)rygSTGHandleTap:(UITapGestureRecognizer *)g {
    [RYGUtils showConfirmation:^{
        if ([self isKindOfClass:[UIControl class]]) {
            [(UIControl *)self sendActionsForControlEvents:UIControlEventTouchUpInside];
        }
    } title:RYGLocalized(@"Send to group chat?")];
}

%end
