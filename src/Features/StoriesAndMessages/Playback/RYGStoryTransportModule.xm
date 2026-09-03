// Seek + pause section for the story Playback menu.

#import "RYGStoryPlayback.h"
#import "../../../Utils.h"
#import "../../../InstagramHeaders.h"
#import <objc/message.h>

static double rygStoryVideoDouble(id videoView, SEL sel) {
	if (![videoView respondsToSelector:sel]) return -1;
	@try { return ((double (*)(id, SEL))objc_msgSend)(videoView, sel); }
	@catch (__unused id e) { return -1; }
}

static void rygStorySeekBy(double delta) {
	id videoView = rygStoryVideoView();
	if (!videoView) return;

	double current = rygStoryVideoDouble(videoView, @selector(currentTime));
	double duration = rygStoryVideoDouble(videoView, @selector(duration));
	if (current < 0) return;

	double target = current + delta;
	if (target < 0.1) target = 0.1;   // IG ignores a seek to exactly 0
	if (duration > 0.5 && target > duration - 0.3) target = duration - 0.3;
	if (fabs(target - current) < 0.05) return;

	id receiver = rygStoryMediaController();
	if (![receiver respondsToSelector:@selector(seekToTime:)]) receiver = videoView;
	if (![receiver respondsToSelector:@selector(seekToTime:)]) return;

	@try { ((void (*)(id, SEL, double))objc_msgSend)(receiver, @selector(seekToTime:), target); }
	@catch (__unused id e) {}

	[[[UIImpactFeedbackGenerator alloc] initWithStyle:UIImpactFeedbackStyleLight] impactOccurred];
}

// IG tracks pause reasons as a set, so a resume only lands with the reason that paused.
static long long sIGPauseReason = 0;
static long long sIGResumeReason = 0;
static long long sIGVideoPauseReason = 0;
static BOOL sRYGPaused = NO;
static BOOL sRYGDrivingPlayback = NO;

static BOOL rygStoryIsPlaying(void) {
	if (sRYGPaused) return NO;
	id videoView = rygStoryVideoView();
	if ([videoView respondsToSelector:@selector(isPlaying)]) {
		@try { return ((BOOL (*)(id, SEL))objc_msgSend)(videoView, @selector(isPlaying)); }
		@catch (__unused id e) {}
	}
	id sc = rygStoryMediaController();
	if (![sc respondsToSelector:@selector(isPlaying)]) return YES;
	@try { return ((BOOL (*)(id, SEL))objc_msgSend)(sc, @selector(isPlaying)); }
	@catch (__unused id e) { return YES; }
}

static void rygStoryDrivePlayback(BOOL pause) {
	id sc = rygStoryMediaController();
	SEL sel = pause ? @selector(pauseWithReason:) : @selector(tryResumePlaybackWithReason:);
	long long reason = pause ? sIGPauseReason : sIGResumeReason;
	if (![sc respondsToSelector:sel]) return;

	sRYGDrivingPlayback = YES;
	@try { ((void (*)(id, SEL, long long))objc_msgSend)(sc, sel, reason); }
	@catch (__unused id e) {}
	sRYGDrivingPlayback = NO;

	id videoView = rygStoryVideoView();
	if (pause) {
		if ([videoView respondsToSelector:@selector(pauseWithReason:)])
			@try { ((void (*)(id, SEL, long long))objc_msgSend)(videoView, @selector(pauseWithReason:), sIGVideoPauseReason); }
			@catch (__unused id e) {}
	} else if ([videoView respondsToSelector:@selector(play)]) {
		@try { ((void (*)(id, SEL))objc_msgSend)(videoView, @selector(play)); }
		@catch (__unused id e) {}
	}
}

static void rygStoryTogglePause(void) {
	BOOL pause = rygStoryIsPlaying();
	rygStoryDrivePlayback(pause);
	sRYGPaused = pause;
}

%hook IGStoryFullscreenSectionController

- (void)pauseWithReason:(long long)reason {
	if (!sRYGDrivingPlayback) sIGPauseReason = reason;
	%orig;
}

- (void)tryResumePlaybackWithReason:(long long)reason {
	if (!sRYGDrivingPlayback) {
		sIGResumeReason = reason;
		if (sRYGPaused) return;
	}
	%orig;
}

- (void)setCurrentStoryItem:(id)item {
	sRYGPaused = NO;
	%orig;
}

%end

%hook IGStoryVideoView

- (void)pauseWithReason:(long long)reason {
	if (!sRYGDrivingPlayback) sIGVideoPauseReason = reason;
	%orig;
}

%end

%ctor {
	[RYGPlaybackMenu registerTransportModuleForSurface:RYGPlaybackSurfaceStories
											   seekKey:@"story_playback_seek"
											   stepKey:@"story_playback_seek_step"
												onSeek:^(double delta) { rygStorySeekBy(delta); }
											  pauseKey:@"story_playback_pause"
										   pauseToggle:^{ rygStoryTogglePause(); }
											 isPlaying:^BOOL { return rygStoryIsPlaying(); }];
}
