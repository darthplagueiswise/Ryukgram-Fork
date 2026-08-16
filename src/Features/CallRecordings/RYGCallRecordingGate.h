#import "../../Utils.h"

// Feature gates read at load time so call-recording hooks are never installed when
// the feature is off — zero idle overhead on the app-wide audio/video/camera paths.
// Enabling the feature is restart-gated (settings), so a launch-time read is correct.

// Video/self/capture taps + the call VC hooks: only needed to record.
static inline BOOL RYGCallRecordingEnabled(void) {
	return [RYGUtils getBoolPref:@"call_recordings_enabled"];
}

// Audio tap + footer mute hook: needed for recording OR block-mute-signal (which
// silences the mic via the same tap), so it installs if either is on.
static inline BOOL RYGCallAudioHooksEnabled(void) {
	return [RYGUtils getBoolPref:@"call_recordings_enabled"] || [RYGUtils getBoolPref:@"call_recordings_ghost_mute"];
}
