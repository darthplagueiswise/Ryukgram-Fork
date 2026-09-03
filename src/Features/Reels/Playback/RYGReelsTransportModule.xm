// Seek + pause section for the reel Playback menu.

#import "RYGReelsPlaybackEntry.h"
#import "../../../Utils.h"
#import "../../../InstagramHeaders.h"
#import <objc/runtime.h>
#import <objc/message.h>

static SEL rygCellSeekSel(void) {
	return @selector(seekToTime:preciseTime:trigger:isSeekingOnTap:completionHandler:);
}

// Tracks the playing cell so the menu follows auto-scroll without reopening.
static __weak id sCurrentReelCell;

static id rygActiveReelCell(void) {
	id c = sCurrentReelCell;
	if (c && [c respondsToSelector:rygCellSeekSel()]
		&& [c isKindOfClass:[UIView class]] && ((UIView *)c).window) return c;
	return [RYGReelsPlaybackEntry capturedReelCell];
}

// IG tracks playback reasons as a set, so a resume only lands with the reason that paused.
static long long sIGPauseReason = 0;
static long long sIGPlayReason = 0;
static BOOL sRYGDrivingPlayback = NO;

%hook IGSundialViewerVideoCell
- (void)videoViewDidUnpause:(id)v { %orig; sCurrentReelCell = self; }
- (void)videoView:(id)v didInitialPlayWithStatus:(id)s { %orig; sCurrentReelCell = self; }

- (void)pauseWithReason:(long long)reason {
	if (!sRYGDrivingPlayback) sIGPauseReason = reason;
	%orig;
}

- (void)playWithReason:(long long)reason {
	if (!sRYGDrivingPlayback) sIGPlayReason = reason;
	%orig;
}
%end

// Accumulate from the last target when currentPlaybackTime hasn't caught up yet.
static __weak id sLastSeekCell;
static double sLastSeekTarget = -1;

static void rygSeekBy(double delta) {
	id cell = rygActiveReelCell();
	if (!cell || ![cell respondsToSelector:rygCellSeekSel()]) return;

	double cur = [cell respondsToSelector:@selector(currentPlaybackTime)]
		? ((double(*)(id, SEL))objc_msgSend)(cell, @selector(currentPlaybackTime)) : 0;

	double base = cur;
	if (cell == sLastSeekCell && sLastSeekTarget >= 0 && cur <= 0.05) base = sLastSeekTarget;

	double target = base + delta;
	if (target < 0.1) target = 0.1;   // IG ignores a seek to exactly 0
	if (fabs(target - base) < 0.05) return;

	@try {
		((void(*)(id, SEL, double, BOOL, NSInteger, BOOL, id))objc_msgSend)
			(cell, rygCellSeekSel(), target, YES, 0, NO, nil);
	} @catch (__unused id e) {}

	sLastSeekCell = cell;
	sLastSeekTarget = target;

	UIImpactFeedbackGenerator *h = [[UIImpactFeedbackGenerator alloc]
		initWithStyle:UIImpactFeedbackStyleLight];
	[h impactOccurred];
}

static BOOL rygReelIsPlaying(void) {
	id cell = rygActiveReelCell();
	if (![cell respondsToSelector:@selector(isPlaying)]) return YES;
	@try { return ((BOOL (*)(id, SEL))objc_msgSend)(cell, @selector(isPlaying)); }
	@catch (__unused id e) { return YES; }
}

static void rygReelTogglePause(void) {
	id cell = rygActiveReelCell();
	BOOL pause = rygReelIsPlaying();
	SEL sel = pause ? @selector(pauseWithReason:) : @selector(playWithReason:);
	if (![cell respondsToSelector:sel]) return;

	sRYGDrivingPlayback = YES;
	@try {
		((void (*)(id, SEL, long long))objc_msgSend)(cell, sel, pause ? sIGPauseReason : sIGPlayReason);
	} @catch (__unused id e) {}
	sRYGDrivingPlayback = NO;
}

#pragma mark - Module registration

%ctor {
	[RYGPlaybackMenu registerTransportModuleForSurface:RYGPlaybackSurfaceReels
											   seekKey:@"reels_playback_seek"
											   stepKey:@"reels_playback_seek_step"
												onSeek:^(double delta) { rygSeekBy(delta); }
											  pauseKey:@"reels_playback_pause"
										   pauseToggle:^{ rygReelTogglePause(); }
											 isPlaying:^BOOL { return rygReelIsPlaying(); }];
}
