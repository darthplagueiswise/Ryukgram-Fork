// Block mute signal: hijack IG's in-call mute button. When enabled, tapping mute runs
// our impl — silence your outgoing mic without telling IG (no "muted" indicator on the
// other end) — and toggles the button's native muted look. IG's mute never fires.

#import "../../Utils.h"
#import "../../InstagramHeaders.h"
#import "RYGCallAudioTap.h"
#import "RYGCallRecordingGate.h"
#import <objc/runtime.h>

%group CallGhostMute

%hook IGVideoCallFooterView

- (void)_audioButtonTapped:(id)sender {
	if (![RYGUtils getBoolPref:@"call_recordings_ghost_mute"]) {
		%orig;
		return;
	}

	BOOL nowGhost = ![RYGCallAudioTap isGhostMuted];
	[RYGCallAudioTap setGhostMuted:nowGhost];

	Ivar iv = class_getInstanceVariable(object_getClass(self), "_audioButton");
	id btn = iv ? object_getIvar(self, iv) : nil;
	if ([btn isKindOfClass:UIControl.class]) [(UIControl *)btn setSelected:nowGhost];

	RYGNotifyInfo(RYG_NOTIF_CALL_RECORDING,
				  nowGhost ? RYGLocalized(@"Muted silently") : RYGLocalized(@"Unmuted"), @"");
}

%end

%end

%ctor {
	if (RYGCallAudioHooksEnabled()) %init(CallGhostMute);
}
