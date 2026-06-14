#import "../../Utils.h"

extern BOOL sciStoryAudioBypass;

static BOOL sciReelRefreshBypassing = NO;
static BOOL sciReelRefreshAlertShowing = NO;

#pragma mark - Prefs

static inline NSString *SCIReelsTapMode(void) {
	NSString *mode = [SCIUtils getStringPref:@"reels_tap_control"];
	return mode.length ? mode : nil;
}

static inline BOOL SCIReelsAutoUnmuteDisabled(void) {
	return [SCIUtils getBoolPref:@"disable_auto_unmuting_reels"];
}

#pragma mark - Refresh helpers

static inline IGRefreshControl *SCIReelsRefreshControl(id vc) {
	if ([vc respondsToSelector:@selector(refreshControl)]) {
		return ((IGRefreshControl *(*)(id, SEL))objc_msgSend)(vc, @selector(refreshControl));
	}

	return nil;
}

static void SCIReelsResetRefreshState(IGRefreshControl *rc) {
	if (!rc) return;

	Ivar stateIvar = class_getInstanceVariable([rc class], "_refreshState");
	if (stateIvar) {
		*(NSInteger *)((char *)(__bridge void *)rc + ivar_getOffset(stateIvar)) = 0;
	}

	if ([rc respondsToSelector:@selector(endRefreshing)]) {
		((void (*)(id, SEL))objc_msgSend)(rc, @selector(endRefreshing));
	}
}

static void SCIReelsEndRefresh(id vc) {
	if (!vc) return;

	if ([vc respondsToSelector:@selector(finishPullToRefreshLoading)]) {
		((void (*)(id, SEL))objc_msgSend)(vc, @selector(finishPullToRefreshLoading));
		return;
	}

	IGRefreshControl *rc = SCIReelsRefreshControl(vc);
	SCIReelsResetRefreshState(rc);

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
	NSString *tapMode = SCIReelsTapMode();

	if ([tapMode isEqualToString:@"pause"]) {
		tapToPauseEnabled = YES;
	} else if ([tapMode isEqualToString:@"mute"]) {
		tapToPauseEnabled = NO;
	}

	if ([SCIUtils getBoolPref:@"reels_show_scrubber"]) {
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
	if ([SCIUtils getBoolPref:@"prevent_doom_scrolling"]) {
		SCIReelsEndRefresh(self);
		return;
	}

	if (sciReelRefreshBypassing || ![SCIUtils getBoolPref:@"refresh_reel_confirm"]) {
		%orig(arg1, arg2);
		return;
	}

	UIViewController *presenter = (UIViewController *)self;

	if (![presenter isViewLoaded] || sciReelRefreshAlertShowing || presenter.presentedViewController) {
		SCIReelsEndRefresh(self);
		return;
	}

	SCIReelsEndRefresh(self);
	sciReelRefreshAlertShowing = YES;

	UIAlertController *alert = [UIAlertController alertControllerWithTitle:SCILocalized(@"Refresh Reels?")
		message:nil
		preferredStyle:UIAlertControllerStyleAlert];

	__weak id target = self;

	[alert addAction:[UIAlertAction actionWithTitle:SCILocalized(@"Cancel")
		style:UIAlertActionStyleCancel
		handler:^(__unused UIAlertAction *action) {
			sciReelRefreshAlertShowing = NO;
		}]];

	[alert addAction:[UIAlertAction actionWithTitle:SCILocalized(@"Refresh")
		style:UIAlertActionStyleDefault
		handler:^(__unused UIAlertAction *action) {
			__strong id strongTarget = target;
			if (!strongTarget) { sciReelRefreshAlertShowing = NO; return; }
			sciReelRefreshBypassing = YES;
			((void (*)(id, SEL, NSInteger, BOOL))objc_msgSend)(strongTarget, @selector(_refreshReelsWithParamsForNetworkRequest:userDidPullToRefresh:), arg1, arg2);
			sciReelRefreshBypassing = NO;
			sciReelRefreshAlertShowing = NO;
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
	if (!SCIReelsAutoUnmuteDisabled()) {
		%orig(notification);
	}
}

- (void)_handleMuteSwitchStateChanged {
	if (sciStoryAudioBypass || !SCIReelsAutoUnmuteDisabled()) {
		%orig;
	}
}

- (void)_handleAudioSessionDeactivation {
	if (!SCIReelsAutoUnmuteDisabled()) {
		%orig;
	}
}

- (void)_handleDidUnplugHeadphones {
	if (!SCIReelsAutoUnmuteDisabled()) {
		%orig;
	}
}

%end
