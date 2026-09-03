// Hide voice/video call buttons in DM thread header.

#import "../../Utils.h"
#import "../../CallButtonHelpers.h"
#import <objc/message.h>
#import <objc/runtime.h>

static BOOL rygIsCallButton(UIView *b) {
    return [b isKindOfClass:NSClassFromString(@"IGDirectCallButton")] ||
           [b isKindOfClass:NSClassFromString(@"IGDirectJointCallButton")];
}

static BOOL rygShouldHide(UIView *b) {
    if (!rygIsCallButton(b)) return NO;
    BOOL hideA = [RYGUtils getBoolPref:@"hide_voice_call_button"];
    BOOL hideV = [RYGUtils getBoolPref:@"hide_video_call_button"];
    if (hideA && hideV) return YES;
    NSString *axId = b.accessibilityIdentifier ?: @"";
    if ([axId isEqualToString:@"audio-call"] || [axId isEqualToString:@"rtc-audio-call-button"])
        return hideA;
    if ([axId isEqualToString:@"video-chat"] || [axId isEqualToString:@"rtc-video-chat-button"])
        return hideV;
    return NO;
}

static BOOL rygPlatterContainsHiddenButton(UIView *platter) {
    NSMutableArray *q = [NSMutableArray arrayWithObject:platter];
    while (q.count) {
        UIView *v = q.firstObject;
        [q removeObjectAtIndex:0];
        if (rygShouldHide(v)) return YES;
        [q addObjectsFromArray:v.subviews];
    }
    return NO;
}

static id rygIvarValue(id obj, const char *name) {
    if (!obj) return nil;
    Ivar iv = class_getInstanceVariable([obj class], name);
    return iv ? object_getIvar(obj, iv) : nil;
}

static id rygConsolidatedCallingButton(id owner) {
    if (!owner) return nil;
    if ([owner respondsToSelector:@selector(consolidatedCallingButton)])
        return ((id (*)(id, SEL))objc_msgSend)(owner, @selector(consolidatedCallingButton));
    return rygIvarValue(owner, "_consolidatedCallingButton");
}

// -consolidatedCallingButton mints a fresh item per call, so identity can miss;
// the view-tree pass is what actually catches it.
static NSArray *rygStripCallingButton(id owner, NSArray *items) {
    if (!([RYGUtils getBoolPref:@"hide_voice_call_button"] &&
          [RYGUtils getBoolPref:@"hide_video_call_button"]))
        return items;
    if (![items isKindOfClass:[NSArray class]]) return items;

    id callBtn = rygConsolidatedCallingButton(owner)
              ?: rygConsolidatedCallingButton(rygIvarValue(owner, "callButtonsComponent"));
    NSMutableArray *out = [items mutableCopy];
    if (callBtn && [items containsObject:callBtn]) {
        [out removeObject:callBtn];
    } else {
        [out filterUsingPredicate:[NSPredicate predicateWithBlock:^BOOL(id it, __unused NSDictionary *b) {
            UIView *cv = [it respondsToSelector:@selector(customView)] ? [it customView] : nil;
            return !(cv && rygPlatterContainsHiddenButton(cv));
        }]];
    }
    return out.count == items.count ? items : out;
}

%group HideCallButtonsGroup

// One consolidated calling button opens the call-type menu; IG 444 moved it from
// this controller to the Swift orchestrator below.
%hook IGDirectThreadViewRightBarButtonsFeatureController
- (id)createRightBarButtonItems {
    RYGProbeOnce(@"callbtn.rightbar.legacy", @"IGDirectThreadViewRightBarButtonsFeatureController fired (pre-444)");
    return rygStripCallingButton(self, %orig);
}
%end

%hook _TtC42IGDirectThreadNavigationButtonOrchestrator42IGDirectThreadNavigationButtonOrchestrator
- (id)createRightBarButtonItems {
    RYGProbeOnce(@"callbtn.rightbar.orchestrator", @"IGDirectThreadNavigationButtonOrchestrator fired (444+)");
    return rygStripCallingButton(self, %orig);
}
%end

// IG 434 moved calling into this component.
%hook IGDirectThreadCallButtonsComponent
- (id)createCallingButtons {
    id r = %orig;
    if ([RYGUtils getBoolPref:@"hide_voice_call_button"] &&
        [RYGUtils getBoolPref:@"hide_video_call_button"] &&
        [r isKindOfClass:[NSArray class]])
        return @[];
    return r;
}
- (void)_didTapConsolidatedCallingButton {
    if ([RYGUtils getBoolPref:@"hide_voice_call_button"] &&
        [RYGUtils getBoolPref:@"hide_video_call_button"]) return;
    %orig;
}
%end

// Block taps in case a hidden button still receives hit-test events during transitions.
%hook IGDirectThreadCallButtonsCoordinator
- (void)_didTapAudioButton:(id)arg1 {
    if ([RYGUtils getBoolPref:@"hide_voice_call_button"]) return;
    %orig;
}
- (void)_didTapVideoButton:(id)arg1 {
    if ([RYGUtils getBoolPref:@"hide_video_call_button"]) return;
    %orig;
}
- (void)_didTapButtonWithCallType:(long long)type {
    BOOL resolved = NO;
    BOOL isVideo = rygCallTypeIsVideo(self, type, &resolved);
    BOOL hidden = isVideo ? [RYGUtils getBoolPref:@"hide_video_call_button"]
                          : [RYGUtils getBoolPref:@"hide_voice_call_button"];
    if (resolved && hidden) return;
    %orig;
}
- (void)_didTapButtonWithCallType:(long long)type tapSource:(id)tapSource {
    BOOL resolved = NO;
    BOOL isVideo = rygCallTypeIsVideo(self, type, &resolved);
    BOOL hidden = isVideo ? [RYGUtils getBoolPref:@"hide_video_call_button"]
                          : [RYGUtils getBoolPref:@"hide_voice_call_button"];
    if (resolved && hidden) return;
    %orig;
}
// Menu-entry filtering for the hidden type lives in CallConfirm.x's buttonMenuItems.
%end

%hook IGDirectCallButton
- (void)didMoveToWindow {
    %orig;
    if (!self.window) return;
    if (rygShouldHide((UIView *)self)) self.hidden = YES;
}
%end

%hook IGDirectJointCallButton
- (void)didMoveToWindow {
    %orig;
    if (!self.window) return;
    if (rygShouldHide((UIView *)self)) self.hidden = YES;
}
%end

// Re-pack platters on each layout: shift every non-back platter right by the
// total width of the hidden call platters to eliminate the gap.
static void rygRepackPlatters(UIView *container) {
    NSMutableArray *platters = [NSMutableArray array];
    for (UIView *sv in container.subviews)
        if ([NSStringFromClass([sv class]) isEqualToString:@"_UINavigationBarPlatterView"])
            [platters addObject:sv];

    CGFloat hiddenWidth = 0;
    NSMutableArray *alive = [NSMutableArray array];
    for (UIView *p in platters) {
        if (rygPlatterContainsHiddenButton(p)) {
            hiddenWidth += p.frame.size.width;
            p.hidden = YES;
        } else {
            p.hidden = NO;
            [alive addObject:p];
        }
    }
    if (!alive.count || hiddenWidth == 0) {
        for (UIView *p in alive) p.transform = CGAffineTransformIdentity;
        return;
    }
    for (UIView *p in alive) {
        if (p.frame.origin.x < 60) { p.transform = CGAffineTransformIdentity; continue; }
        p.transform = CGAffineTransformMakeTranslation(hiddenWidth, 0);
    }
}

%hook IGNavigationBar
- (void)layoutSubviews {
    %orig;
    NSMutableArray *q = [NSMutableArray arrayWithObject:self];
    while (q.count) {
        UIView *v = q.firstObject;
        [q removeObjectAtIndex:0];
        if ([NSStringFromClass([v class]) containsString:@"NavigationBarPlatterContainer"]) {
            rygRepackPlatters(v);
            break;
        }
        [q addObjectsFromArray:v.subviews];
    }
}
%end

%end // HideCallButtonsGroup

%ctor {
    if ([RYGUtils getBoolPref:@"hide_voice_call_button"] ||
        [RYGUtils getBoolPref:@"hide_video_call_button"]) {
        %init(HideCallButtonsGroup);
    }
}
