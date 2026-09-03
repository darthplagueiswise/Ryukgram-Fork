#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

extern NSNotificationName const RYGCallAudioTapUnitLostNotification;
// Fired once when a call's audio unit comes up (call connected) — the reliable
// "call started" signal, unlike VC viewDidAppear which re-fires on PiP return.
extern NSNotificationName const RYGCallAudioTapCallStartedNotification;

// Captures both directions of an IG (WebRTC) call by tapping the VoiceProcessingIO
// audio unit: the playout render callback = far-end (their voice), AudioUnitRender
// on the input bus = mic (your voice). Written as two raw PCM files, mixed on stop.
@interface RYGCallAudioTap : NSObject

// Arms capture into two int16 mono PCM files. Returns NO if no call audio unit is live.
+ (BOOL)startCapturingToNearPath:(NSString *)nearPath farPath:(NSString *)farPath;
+ (void)stop;

// YES once the VoiceProcessingIO unit has been seen (a call is/was up).
+ (BOOL)isCallAudioLive;

// Sample rate of the captured PCM (0 until a unit is seen).
+ (double)sampleRate;

// Ghost mute: silence your outgoing mic without triggering IG's mute (no indicator
// shows on the other end). Independent of recording.
+ (void)setGhostMuted:(BOOL)muted;
+ (BOOL)isGhostMuted;

// Wall-clock (CACurrentMediaTime) of the first captured audio sample — the true
// media t=0 (call connect), used to align video that starts later.
+ (double)firstSampleWallTime;

// Offline: mix the two int16-mono PCM files (sample-wise, clamped) into one AAC .m4a.
+ (BOOL)mixNearPath:(NSString *)nearPath farPath:(NSString *)farPath
			toM4APath:(NSString *)outPath sampleRate:(double)sampleRate;

@end

NS_ASSUME_NONNULL_END
