// Auto-scroll reels — off / ig (force IG gates) / custom (force gates + advance after each loop).

#import "../../Utils.h"
#import "../../InstagramHeaders.h"
#import <objc/runtime.h>
#import <objc/message.h>
#import <stdatomic.h>

static const void *kRYGLoopCountKey = &kRYGLoopCountKey;
static const void *kRYGArmedKey = &kRYGArmedKey;
static atomic_bool rygAdvanceInFlight = false;

static inline NSString *rygMode(void) {
	NSString *mode = [RYGUtils getStringPref:@"auto_scroll_reels_mode"];
	return mode.length ? mode : @"off";
}

static inline BOOL rygModeOn(void) { return ![rygMode() isEqualToString:@"off"]; }
static inline BOOL rygModeCustom(void) { return [rygMode() isEqualToString:@"custom"]; }

static double rygStatusValue(id status, SEL sel) {
	Method m = class_getInstanceMethod(object_getClass(status), sel);
	if (!m) return 0;
	char rt[8] = {0};
	method_getReturnType(m, rt, sizeof(rt));
	if (rt[0] == 'd') return ((double (*)(id, SEL))objc_msgSend)(status, sel);
	if (rt[0] == 'f') return ((float (*)(id, SEL))objc_msgSend)(status, sel);
	return 0;
}

static UIViewController *rygFeedVCFromView(UIView *view) {
	for (UIResponder *r = view; r; r = r.nextResponder) {
		if ([r isKindOfClass:UIViewController.class] &&
			[NSStringFromClass(r.class) isEqualToString:@"IGSundialFeedViewController"]) {
			return (UIViewController *)r;
		}
	}
	return nil;
}

// Autoscroll arms once the feed's video genuinely starts playing. Profile-opened reels
// lazy-load their first item; arming on real playback rather than a timer avoids the
// spurious first advance no matter how slow the load is.
static BOOL rygFeedArmed(UIViewController *vc) {
	return vc && [objc_getAssociatedObject(vc, kRYGArmedKey) boolValue];
}

static void rygScrollToNextFromView(UIView *view) {
	bool expected = false;
	if (!atomic_compare_exchange_strong(&rygAdvanceInFlight, &expected, true)) return;

	UIViewController *vc = rygFeedVCFromView(view);
	if (!vc || !vc.viewIfLoaded.window || !rygFeedArmed(vc)) {
		atomic_store(&rygAdvanceInFlight, false);
		return;
	}

	dispatch_async(dispatch_get_main_queue(), ^{
		SEL sel1 = @selector(scrollToNextItemAnimated:);
		SEL sel2 = @selector(sundialViewerInteractionCoordinatorWantsScrollToNextItemAnimated:);

		if ([vc respondsToSelector:sel1]) {
			((void (*)(id, SEL, BOOL))objc_msgSend)(vc, sel1, YES);
		} else if ([vc respondsToSelector:sel2]) {
			((void (*)(id, SEL, BOOL))objc_msgSend)(vc, sel2, YES);
		}

		atomic_store(&rygAdvanceInFlight, false);
	});
}

%hook IGSundialFeedViewController

- (BOOL)shouldForceEnableAutoScroll {
	return (rygModeOn() && rygFeedArmed(self)) ? YES : %orig;
}

- (BOOL)autoAdvanceToNextItem {
	return (rygModeOn() && rygFeedArmed(self)) ? YES : %orig;
}

- (void)setAutoAdvanceToNextItem:(BOOL)value {
	%orig((rygModeOn() && rygFeedArmed(self)) ? YES : value);
}

%end

%hook IGSundialViewerVideoCell

- (void)videoView:(id)view didUpdatePlaybackStatus:(id)status {
	%orig;

	if (!rygModeOn() || !status) return;

	if (rygStatusValue(status, @selector(currentTime)) > 0 &&
		rygStatusValue(status, @selector(totalTime)) > 0) {
		UIViewController *vc = rygFeedVCFromView((UIView *)self);
		if (vc && !rygFeedArmed(vc)) {
			objc_setAssociatedObject(vc, kRYGArmedKey, @YES, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
		}
	}

	if (!rygModeCustom()) return;

	SEL loopSel = @selector(loopCount);
	if (![status respondsToSelector:loopSel]) return;

	long long current = ((long long (*)(id, SEL))objc_msgSend)(status, loopSel);
	NSNumber *previous = objc_getAssociatedObject(self, kRYGLoopCountKey);

	objc_setAssociatedObject(self, kRYGLoopCountKey, @(current), OBJC_ASSOCIATION_RETAIN_NONATOMIC);

	if (!previous || current <= previous.longLongValue) return;

	rygScrollToNextFromView((UIView *)self);
}

- (void)videoViewDidPlayThroughToCompletion:(id)view {
	%orig;

	if (rygModeCustom()) {
		rygScrollToNextFromView((UIView *)self);
	}
}

- (void)prepareForReuse {
	objc_setAssociatedObject(self, kRYGLoopCountKey, nil, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
	%orig;
}

%end
