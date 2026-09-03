// Reels playback speed. Hooks install only when enabled at launch (restart to enable).

#import "RYGReelsPlaybackEntry.h"
#import "../../../Utils.h"
#import "../../../InstagramHeaders.h"
#import <objc/runtime.h>
#import <objc/message.h>

static inline BOOL rygSpeedEnabled(void) {
	return [RYGUtils getBoolPref:@"reels_playback_speed"];
}

static float rygSpeedRate(void) {
	return [RYGPlaybackMenu speedRateForKey:@"reels_playback_speed_rate"];
}

static id rygPlayerOf(id view) {
	if (![view respondsToSelector:@selector(videoPlayer)]) return nil;
	@try { return ((id(*)(id, SEL))objc_msgSend)(view, @selector(videoPlayer)); }
	@catch (__unused id e) { return nil; }
}

static void rygApplyRateToPlayer(id player, float rate) {
	if (!player || ![player respondsToSelector:@selector(setPlaybackSpeed:)]) return;
	@try { ((void(*)(id, SEL, float))objc_msgSend)(player, @selector(setPlaybackSpeed:), rate); }
	@catch (__unused id e) {}
}

static BOOL rygViewIsInReels(UIView *view) {
	for (UIView *v = view; v; v = v.superview)
		if ([NSStringFromClass([v class]) containsString:@"Sundial"]) return YES;
	for (UIResponder *r = view; r; r = r.nextResponder)
		if ([NSStringFromClass([r class]) containsString:@"Sundial"]) return YES;
	return NO;
}

static NSHashTable *sReelsPlayers;
static BOOL rygIsReelsPlayer(id player) {
	return player && sReelsPlayers && [sReelsPlayers containsObject:player];
}
static void rygRegisterReelsPlayer(id player) {
	if (!player) return;
	if (!sReelsPlayers) sReelsPlayers = [NSHashTable weakObjectsHashTable];
	[sReelsPlayers addObject:player];
}
static void rygApplyRateToReelsPlayers(float rate) {
	for (id p in sReelsPlayers.allObjects) rygApplyRateToPlayer(p, rate);
}

static void rygApplyRateEverywhere(float rate) {
	rygApplyRateToReelsPlayers(rate);
	dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.10 * NSEC_PER_SEC)),
		dispatch_get_main_queue(), ^{ rygApplyRateToReelsPlayers(rate); });
	dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.30 * NSEC_PER_SEC)),
		dispatch_get_main_queue(), ^{ rygApplyRateToReelsPlayers(rate); });
}

#pragma mark - Module registration + speed hook

static void rygApplyRateToSelf(id view, id playerArg) {
	if (!rygSpeedEnabled()) return;
	id player = playerArg ?: rygPlayerOf(view);
	if (!player) return;
	if (![view isKindOfClass:[UIView class]] || !rygViewIsInReels((UIView *)view)) return;
	rygRegisterReelsPlayer(player);
	float rate = rygSpeedRate();
	if (fabsf(rate - 1.0f) < 0.001f) return;
	rygApplyRateToPlayer(player, rate);
}

%group RYGSpeedGroup

%hook IGStatefulVideoPlayer

- (void)setPlaybackSpeed:(float)speed {
	if (rygSpeedEnabled() && rygIsReelsPlayer(self)) {
		float ours = rygSpeedRate();
		if (ours > 0 && fabsf(ours - 1.0f) > 0.001f) {
			%orig(ours);
			return;
		}
	}
	%orig(speed);
}

%end

%hook _TtC11IGVideoView11IGVideoView

- (void)videoPlayerDidInitialPlay:(id)player { %orig; rygApplyRateToSelf(self, player); }
- (void)videoPlayerDidReadyToDisplay:(id)player { %orig; rygApplyRateToSelf(self, player); }
- (void)videoPlayerDidFinishPrepare:(id)player { %orig; rygApplyRateToSelf(self, player); }
- (void)videoPlayerDidUnpause:(id)player { %orig; rygApplyRateToSelf(self, player); }

%end

%end

%ctor {
	[RYGPlaybackMenu registerSpeedModuleForSurface:RYGPlaybackSurfaceReels
										enabledKey:@"reels_playback_speed"
										   rateKey:@"reels_playback_speed_rate"
											 apply:^(float rate) { rygApplyRateEverywhere(rate); }];
	if (rygSpeedEnabled()) %init(RYGSpeedGroup);
}
