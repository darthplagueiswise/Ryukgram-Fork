#import "../../Utils.h"
#import <objc/message.h>

static NSTimeInterval const kRYGReelTapArmWindow = 2.0;

static __weak id rygArmedReelCell;
static NSTimeInterval rygArmedReelAt;

static BOOL rygCellShowsClip(id cell) {
	if (![cell respondsToSelector:@selector(post)]) return NO;
	id media = ((id (*)(id, SEL))objc_msgSend)(cell, @selector(post));
	if (![media respondsToSelector:@selector(isClipsMedia)]) return NO;
	return ((BOOL (*)(id, SEL))objc_msgSend)(media, @selector(isClipsMedia));
}

static BOOL rygCellIsPlaying(id cell) {
	if ([cell respondsToSelector:@selector(playbackFailedToStart)] &&
		((BOOL (*)(id, SEL))objc_msgSend)(cell, @selector(playbackFailedToStart)))
		return NO;

	if (![cell respondsToSelector:@selector(playbackStatus)]) return YES;
	id status = ((id (*)(id, SEL))objc_msgSend)(cell, @selector(playbackStatus));
	if (![status respondsToSelector:@selector(isActive)]) return YES;
	return ((BOOL (*)(id, SEL))objc_msgSend)(status, @selector(isActive));
}

static void rygPlayReelInPlace(id cell) {
	if (!rygCellIsPlaying(cell)) {
		if ([cell respondsToSelector:@selector(retryStartPlayback)])
			((void (*)(id, SEL))objc_msgSend)(cell, @selector(retryStartPlayback));
		return;
	}

	if ([cell respondsToSelector:@selector(toggleAudioEnabledWithReason:)])
		((void (*)(id, SEL, long long))objc_msgSend)(cell, @selector(toggleAudioEnabledWithReason:), 0LL);
}

static BOOL rygInterceptReelTap(id cell) {
	if (!rygCellShowsClip(cell)) return NO;

	NSString *mode = [RYGUtils getStringPref:@"feed_reel_tap"];
	if ([mode isEqualToString:@"inline"]) {
		rygPlayReelInPlace(cell);
		return YES;
	}

	NSTimeInterval now = [NSDate timeIntervalSinceReferenceDate];
	if (rygArmedReelCell == cell && now - rygArmedReelAt <= kRYGReelTapArmWindow) {
		rygArmedReelCell = nil;
		return NO;
	}

	rygArmedReelCell = cell;
	rygArmedReelAt = now;
	rygPlayReelInPlace(cell);
	return YES;
}

%group RYGFeedReelTap

%hook _TtC33IGFeedItemModernVideoCellDelegate37IGFeedItemModernVideoCellDelegateImpl

- (void)modernFeedVideoCellDidObserveSingleTap:(id)cell gestureRecognizer:(id)recognizer {
	RYGProbeOnce(@"feed-reel-tap.modern-delegate", @"%@", NSStringFromClass([cell class]));
	if (rygInterceptReelTap(cell)) return;
	%orig;
}

%end

%hook _TtC18IGFeedItemPageCell15IGPageMediaView

- (void)modernFeedVideoCellDidObserveSingleTap:(id)cell gestureRecognizer:(id)recognizer {
	RYGProbeOnce(@"feed-reel-tap.page-delegate", @"%@", NSStringFromClass([cell class]));
	if (rygInterceptReelTap(cell)) return;
	%orig;
}

%end

%end

%ctor {
	NSString *mode = [RYGUtils getStringPref:@"feed_reel_tap"];
	if ([mode isEqualToString:@"inline"] || [mode isEqualToString:@"double"])
		%init(RYGFeedReelTap);
}
