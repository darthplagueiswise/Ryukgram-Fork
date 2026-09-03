#import "../../Utils.h"

extern BOOL rygStoryAudioBypass;

static BOOL rygReelRefreshBypassing = NO;
static BOOL rygReelRefreshAlertShowing = NO;

#pragma mark - Prefs

static inline NSString *RYGReelsTapMode(void) {
	NSString *mode = [RYGUtils getStringPref:@"reels_tap_control"];
	return mode.length ? mode : nil;
}

static inline BOOL RYGReelsAutoUnmuteDisabled(void) {
	return [RYGUtils getBoolPref:@"disable_auto_unmuting_reels"];
}

#pragma mark - Refresh helpers

static inline IGRefreshControl *RYGReelsRefreshControl(id vc) {
	if ([vc respondsToSelector:@selector(refreshControl)]) {
		return ((IGRefreshControl *(*)(id, SEL))objc_msgSend)(vc, @selector(refreshControl));
	}

	return nil;
}

static void RYGReelsResetRefreshState(IGRefreshControl *rc) {
	if (!rc) return;

	Ivar stateIvar = class_getInstanceVariable([rc class], "_refreshState");
	if (stateIvar) {
		*(NSInteger *)((char *)(__bridge void *)rc + ivar_getOffset(stateIvar)) = 0;
	}

	if ([rc respondsToSelector:@selector(endRefreshing)]) {
		((void (*)(id, SEL))objc_msgSend)(rc, @selector(endRefreshing));
	}
}

static void RYGReelsEndRefresh(id vc) {
	if (!vc) return;

	if ([vc respondsToSelector:@selector(finishPullToRefreshLoading)]) {
		((void (*)(id, SEL))objc_msgSend)(vc, @selector(finishPullToRefreshLoading));
		return;
	}

	IGRefreshControl *rc = RYGReelsRefreshControl(vc);
	RYGReelsResetRefreshState(rc);

	if (rc && [vc respondsToSelector:@selector(refreshControlDidEndFinishLoadingAnimation:)]) {
		((void (*)(id, SEL, id))objc_msgSend)(vc, @selector(refreshControlDidEndFinishLoadingAnimation:), rc);
	}
}

#pragma mark - Playback controls config

%hook IGSundialPlaybackControlsTestConfiguration

- (id)initWithLauncherSet:(id)set
	tapToPauseEnabled:(BOOL)tapToPauseEnabled
	combineSingleTapPlaybackControls:(BOOL)controls
	isVideoPreviewThumbnailEnabled:(BOOL)previewThumbEnabled
	minScrubberDurationSec:(NSInteger)minSec
	seekResumeScrubberCooldownSec:(CGFloat)seekSec
	tapResumeScrubberCooldownSec:(CGFloat)tapSec
	persistentScrubberMinVideoDuration:(NSInteger)duration
	isScrubberForShortVideoEnabled:(BOOL)shortScrubberEnabled
{
	NSString *tapMode = RYGReelsTapMode();

	if ([tapMode isEqualToString:@"pause"]) {
		tapToPauseEnabled = YES;
	} else if ([tapMode isEqualToString:@"mute"]) {
		tapToPauseEnabled = NO;
	}

	if ([RYGUtils getBoolPref:@"reels_show_scrubber"]) {
		minSec = 0;
		duration = 0;
		shortScrubberEnabled = YES;
	}

	return %orig(set, tapToPauseEnabled, controls, previewThumbEnabled, minSec, seekSec, tapSec, duration, shortScrubberEnabled);
}

%end

#pragma mark - Reels refresh confirmation / doom-scroll prevention

%hook IGSundialFeedViewController

- (void)_refreshReelsWithParamsForNetworkRequest:(NSInteger)arg1 userDidPullToRefresh:(BOOL)arg2 {
	if ([RYGUtils getBoolPref:@"prevent_doom_scrolling"]) {
		RYGReelsEndRefresh(self);
		return;
	}

	if (rygReelRefreshBypassing || ![RYGUtils getBoolPref:@"refresh_reel_confirm"]) {
		%orig(arg1, arg2);
		return;
	}

	UIViewController *presenter = (UIViewController *)self;

	if (![presenter isViewLoaded] || rygReelRefreshAlertShowing || presenter.presentedViewController) {
		RYGReelsEndRefresh(self);
		return;
	}

	RYGReelsEndRefresh(self);
	rygReelRefreshAlertShowing = YES;

	UIAlertController *alert = [UIAlertController alertControllerWithTitle:RYGLocalized(@"Refresh Reels?")
		message:nil
		preferredStyle:UIAlertControllerStyleAlert];

	__weak id target = self;

	[alert addAction:[UIAlertAction actionWithTitle:RYGLocalized(@"Cancel")
		style:UIAlertActionStyleCancel
		handler:^(__unused UIAlertAction *action) {
			rygReelRefreshAlertShowing = NO;
		}]];

	[alert addAction:[UIAlertAction actionWithTitle:RYGLocalized(@"Refresh")
		style:UIAlertActionStyleDefault
		handler:^(__unused UIAlertAction *action) {
			__strong id strongTarget = target;
			if (!strongTarget) { rygReelRefreshAlertShowing = NO; return; }
			rygReelRefreshBypassing = YES;
			((void (*)(id, SEL, NSInteger, BOOL))objc_msgSend)(strongTarget, @selector(_refreshReelsWithParamsForNetworkRequest:userDidPullToRefresh:), arg1, arg2);
			rygReelRefreshBypassing = NO;
			rygReelRefreshAlertShowing = NO;
		}]];

	[presenter presentViewController:alert animated:YES completion:nil];
}

%end

#pragma mark - Disable auto-unmuting reels

// Blocks video playback audio controller paths that can auto-unmute:
// hardware volume buttons, mute switch changes, audio session deactivation,
// and headphone unplug events.

%hook IGVideoPlaybackAudioController

- (void)_handleDidPressVolumeButtonNotification:(id)notification {
	if (!RYGReelsAutoUnmuteDisabled()) {
		%orig(notification);
	}
}

- (void)_handleMuteSwitchStateChanged {
	if (rygStoryAudioBypass || !RYGReelsAutoUnmuteDisabled()) {
		%orig;
	}
}

- (void)_handleAudioSessionDeactivation {
	if (!RYGReelsAutoUnmuteDisabled()) {
		%orig;
	}
}

- (void)_handleDidUnplugHeadphones {
	if (!RYGReelsAutoUnmuteDisabled()) {
		%orig;
	}
}

%end