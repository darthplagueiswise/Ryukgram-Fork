#import "../../Utils.h"
#import <objc/message.h>

%group RYGDisableFeedAutoplay

%hook _TtC14IGFeedPlayback22IGFeedPlaybackStrategy

- (id)initWithShouldDisableAutoplay:(BOOL)disable shouldClearStaleReservation:(BOOL)clear {
	return %orig(YES, clear);
}

- (id)initWithShouldDisableAutoplay:(BOOL)disable shouldClearStaleReservation:(BOOL)clear shouldBypassDisabledAutoplayForVoiceover:(BOOL)bypassVO {
	return %orig(YES, clear, bypassVO);
}

- (id)initWithShouldDisableAutoplay:(BOOL)disable shouldClearStaleReservation:(BOOL)clear shouldBypassDisabledAutoplayForVoiceover:(BOOL)bypassVO shouldOverrideDefaultThresholds:(BOOL)override launcherSet:(id)launcherSet {
	return %orig(YES, clear, bypassVO, override, launcherSet);
}

%end

%hook _TtC21IGModernFeedVideoCell21IGModernFeedVideoCell

- (void)videoPlayerOverlayControllerDidSingleTap:(id)overlay gestureRecognizer:(id)gr {
	%orig;

	SEL respondsSel = @selector(respondsToSelector:);
	SEL carouselSel = @selector(isTouchFromCarousel);
	SEL retrySel = @selector(retryStartPlayback);

	BOOL hasCarousel = ((BOOL (*)(id, SEL, SEL))objc_msgSend)(self, respondsSel, carouselSel);
	if (!hasCarousel) return;

	BOOL isCarousel = ((BOOL (*)(id, SEL))objc_msgSend)(self, carouselSel);
	if (!isCarousel) return;

	BOOL hasRetry = ((BOOL (*)(id, SEL, SEL))objc_msgSend)(self, respondsSel, retrySel);
	if (hasRetry)
		((void (*)(id, SEL))objc_msgSend)(self, retrySel);
}

%end

%end

%ctor {
	if ([RYGUtils getBoolPref:@"disable_feed_autoplay"])
		%init(RYGDisableFeedAutoplay);
}