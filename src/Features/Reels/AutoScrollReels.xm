// Auto-scroll reels — off / ig (force IG gates) / custom (force gates + advance after each loop).

#import "../../Utils.h"
#import "../../InstagramHeaders.h"
#import <objc/runtime.h>
#import <objc/message.h>
#import <stdatomic.h>

static const void *kSCILoopCountKey = &kSCILoopCountKey;
// Atomic — guards against double-advance from concurrent video-end callbacks.
static atomic_bool sciAdvanceInFlight = false;

static inline NSString *sciMode(void) {
	NSString *mode = [SCIUtils getStringPref:@"auto_scroll_reels_mode"];
	return mode.length ? mode : @"off";
}

static inline BOOL sciModeOn(void) { return ![sciMode() isEqualToString:@"off"]; }
static inline BOOL sciModeCustom(void) { return [sciMode() isEqualToString:@"custom"]; }

static UIViewController *sciFeedVCFromView(UIView *view) {
	for (UIResponder *r = view; r; r = r.nextResponder) {
		if ([r isKindOfClass:UIViewController.class] &&
			[NSStringFromClass(r.class) isEqualToString:@"IGSundialFeedViewController"]) {
			return (UIViewController *)r;
		}
	}
	return nil;
}

static void sciScrollToNextFromView(UIView *view) {
	bool expected = false;
	if (!atomic_compare_exchange_strong(&sciAdvanceInFlight, &expected, true)) return;

	UIViewController *vc = sciFeedVCFromView(view);
	if (!vc || !vc.viewIfLoaded.window) {
		atomic_store(&sciAdvanceInFlight, false);
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

		atomic_store(&sciAdvanceInFlight, false);
	});
}

%hook IGSundialFeedViewController

- (BOOL)shouldForceEnableAutoScroll {
	return sciModeOn() ? YES : %orig;
}

- (BOOL)autoAdvanceToNextItem {
	return sciModeOn() ? YES : %orig;
}

- (void)setAutoAdvanceToNextItem:(BOOL)value {
	%orig(sciModeOn() ? YES : value);
}

%end

%hook IGSundialViewerVideoCell

- (void)videoView:(id)view didUpdatePlaybackStatus:(id)status {
	%orig;

	if (!sciModeCustom() || !status) return;

	SEL loopSel = @selector(loopCount);
	if (![status respondsToSelector:loopSel]) return;

	long long current = ((long long (*)(id, SEL))objc_msgSend)(status, loopSel);
	NSNumber *previous = objc_getAssociatedObject(self, kSCILoopCountKey);

	objc_setAssociatedObject(self, kSCILoopCountKey, @(current), OBJC_ASSOCIATION_RETAIN_NONATOMIC);

	if (!previous || current <= previous.longLongValue) return;

	sciScrollToNextFromView((UIView *)self);
}

- (void)videoViewDidPlayThroughToCompletion:(id)view {
	%orig;

	if (sciModeCustom()) {
		sciScrollToNextFromView((UIView *)self);
	}
}

- (void)prepareForReuse {
	objc_setAssociatedObject(self, kSCILoopCountKey, nil, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
	%orig;
}

%end