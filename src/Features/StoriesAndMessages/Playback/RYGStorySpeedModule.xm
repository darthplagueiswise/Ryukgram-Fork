// Story playback speed. Hooks install only when enabled at launch (restart to enable).

#import "RYGStoryPlayback.h"
#import "../../../Utils.h"
#import "../../../InstagramHeaders.h"
#import <objc/message.h>

static inline BOOL rygStorySpeedEnabled(void) {
	return [RYGUtils getBoolPref:@"story_playback_speed"];
}

static float rygStorySpeedRate(void) {
	return [RYGPlaybackMenu speedRateForKey:@"story_playback_speed_rate"];
}

static void rygApplyStorySpeedTo(id videoView, float rate) {
	RYGProbeOnce(@"story.playback.speed", @"view=%@ responds=%d",
				 NSStringFromClass([videoView class]),
				 [videoView respondsToSelector:@selector(setPlaybackSpeed:)]);
	if (!videoView || ![videoView respondsToSelector:@selector(setPlaybackSpeed:)]) return;
	@try { ((void (*)(id, SEL, double))objc_msgSend)(videoView, @selector(setPlaybackSpeed:), rate); }
	@catch (__unused id e) {}
}

%group RYGStorySpeedGroup

%hook IGStoryVideoView

- (void)play {
	%orig;
	if (rygStorySpeedEnabled()) rygApplyStorySpeedTo(self, rygStorySpeedRate());
}

- (void)videoView:(id)view didInitialPlayWithStatus:(id)status {
	%orig;
	if (rygStorySpeedEnabled()) rygApplyStorySpeedTo(self, rygStorySpeedRate());
}

- (void)videoViewDidUnpause:(id)unpause {
	%orig;
	if (rygStorySpeedEnabled()) rygApplyStorySpeedTo(self, rygStorySpeedRate());
}

%end

%end

%ctor {
	[RYGPlaybackMenu registerSpeedModuleForSurface:RYGPlaybackSurfaceStories
										enabledKey:@"story_playback_speed"
										   rateKey:@"story_playback_speed_rate"
											 apply:^(float rate) {
		rygApplyStorySpeedTo(rygStoryVideoView(), rate);
	}];
	if (rygStorySpeedEnabled()) %init(RYGStorySpeedGroup);
}
