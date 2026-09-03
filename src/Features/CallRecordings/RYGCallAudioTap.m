#import "RYGCallAudioTap.h"
#import <AudioToolbox/AudioToolbox.h>
#import <AVFoundation/AVFoundation.h>
#import <QuartzCore/QuartzCore.h>
#import <pthread.h>
#import "../../../modules/fishhook/fishhook.h"
#import "RYGCallRecordingGate.h"

NSNotificationName const RYGCallAudioTapUnitLostNotification = @"RYGCallAudioTapUnitLostNotification";
NSNotificationName const RYGCallAudioTapCallStartedNotification = @"RYGCallAudioTapCallStartedNotification";

static AudioUnit gLastStartedUnit = NULL;

#pragma mark - Shared state (touched from the realtime audio thread)

static AudioUnit gVPIO = NULL;
static AURenderCallback gOrigPlayout = NULL;
static void *gOrigPlayoutRef = NULL;
static AudioStreamBasicDescription gFormat;
static double gSampleRate = 0;

static volatile int32_t gRecording = 0;
static volatile int32_t gGhost = 0;   // ghost mute: silence our outgoing mic without telling IG
static FILE *gNear = NULL;
static FILE *gFar = NULL;
static pthread_mutex_t gFileLock = PTHREAD_MUTEX_INITIALIZER;

static CFTimeInterval gFirstSampleTime = 0;   // wall clock of first captured audio (= call connect)

static BOOL rygIsVPIO(AudioUnit unit) {
	if (!unit) return NO;
	AudioComponent comp = AudioComponentInstanceGetComponent(unit);
	if (!comp) return NO;
	AudioComponentDescription d = {0};
	if (AudioComponentGetDescription(comp, &d) != noErr) return NO;
	return d.componentType == kAudioUnitType_Output && d.componentSubType == kAudioUnitSubType_VoiceProcessingIO;
}

static inline void rygStampFirstSample(void) {
	if (gFirstSampleTime == 0) gFirstSampleTime = CACurrentMediaTime();
}

#pragma mark - Far-end (playout render callback wrapper)

static OSStatus ryg_PlayoutProc(void *ref, AudioUnitRenderActionFlags *flags, const AudioTimeStamp *ts,
								UInt32 bus, UInt32 frames, AudioBufferList *ioData) {
	OSStatus st = gOrigPlayout ? gOrigPlayout(gOrigPlayoutRef, flags, ts, bus, frames, ioData) : noErr;
	if (gRecording && ioData && ioData->mNumberBuffers) {
		AudioBuffer b = ioData->mBuffers[0];
		if (b.mData && b.mDataByteSize) {
			pthread_mutex_lock(&gFileLock);
			if (gFar) fwrite(b.mData, 1, b.mDataByteSize, gFar);
			pthread_mutex_unlock(&gFileLock);
			rygStampFirstSample();
		}
	}
	return st;
}

#pragma mark - Hooked CoreAudio functions

static OSStatus (*orig_AudioUnitSetProperty)(AudioUnit, AudioUnitPropertyID, AudioUnitScope, AudioUnitElement, const void *, UInt32);
static OSStatus (*orig_AudioUnitRender)(AudioUnit, AudioUnitRenderActionFlags *, const AudioTimeStamp *, UInt32, UInt32, AudioBufferList *);
static OSStatus (*orig_AudioComponentInstanceDispose)(AudioComponentInstance);

static OSStatus ryg_AudioUnitSetProperty(AudioUnit unit, AudioUnitPropertyID prop, AudioUnitScope scope,
										 AudioUnitElement el, const void *data, UInt32 size) {
	if (prop == kAudioUnitProperty_SetRenderCallback && data && size >= sizeof(AURenderCallbackStruct) && rygIsVPIO(unit)) {
		const AURenderCallbackStruct *cb = (const AURenderCallbackStruct *)data;
		gVPIO = unit;
		gOrigPlayout = cb->inputProc;
		gOrigPlayoutRef = cb->inputProcRefCon;
		if (unit != gLastStartedUnit) {
			gLastStartedUnit = unit;
			dispatch_async(dispatch_get_main_queue(), ^{
				[NSNotificationCenter.defaultCenter postNotificationName:RYGCallAudioTapCallStartedNotification object:nil];
			});
		}
		AURenderCallbackStruct rep = { ryg_PlayoutProc, NULL };
		return orig_AudioUnitSetProperty(unit, prop, scope, el, &rep, size);
	}
	return orig_AudioUnitSetProperty(unit, prop, scope, el, data, size);
}

static OSStatus ryg_AudioUnitRender(AudioUnit unit, AudioUnitRenderActionFlags *flags, const AudioTimeStamp *ts,
									UInt32 bus, UInt32 frames, AudioBufferList *ioData) {
	OSStatus st = orig_AudioUnitRender(unit, flags, ts, bus, frames, ioData);
	if (st == noErr && unit == gVPIO && bus == 1 && ioData && ioData->mNumberBuffers) {
		AudioBuffer b = ioData->mBuffers[0];
		if (gRecording && b.mData && b.mDataByteSize) {   // record your real voice first
			pthread_mutex_lock(&gFileLock);
			if (gNear) fwrite(b.mData, 1, b.mDataByteSize, gNear);
			pthread_mutex_unlock(&gFileLock);
			rygStampFirstSample();
		}
		// Ghost mute: zero what IG transmits. IG never called mute, so no mute
		// signal reaches the peer → no "muted" indicator on their end.
		if (__atomic_load_n(&gGhost, __ATOMIC_RELAXED))
			for (UInt32 i = 0; i < ioData->mNumberBuffers; i++)
				if (ioData->mBuffers[i].mData) memset(ioData->mBuffers[i].mData, 0, ioData->mBuffers[i].mDataByteSize);
	}
	return st;
}

static OSStatus ryg_AudioComponentInstanceDispose(AudioComponentInstance inst) {
	if (inst == gVPIO) {
		gVPIO = NULL; gOrigPlayout = NULL; gOrigPlayoutRef = NULL;
		__atomic_store_n(&gGhost, 0, __ATOMIC_RELAXED);
		if (gRecording) {
			dispatch_async(dispatch_get_main_queue(), ^{
				[NSNotificationCenter.defaultCenter postNotificationName:RYGCallAudioTapUnitLostNotification object:nil];
			});
		}
	}
	return orig_AudioComponentInstanceDispose(inst);
}

#pragma mark - Public

@implementation RYGCallAudioTap

+ (void)load {
	if (!RYGCallAudioHooksEnabled()) return;
	struct rebinding r[] = {
		{ "AudioUnitSetProperty", (void *)ryg_AudioUnitSetProperty, (void **)&orig_AudioUnitSetProperty },
		{ "AudioUnitRender", (void *)ryg_AudioUnitRender, (void **)&orig_AudioUnitRender },
		{ "AudioComponentInstanceDispose", (void *)ryg_AudioComponentInstanceDispose, (void **)&orig_AudioComponentInstanceDispose },
	};
	rebind_symbols(r, 3);
}

+ (BOOL)isCallAudioLive { return gVPIO != NULL; }
+ (double)sampleRate { return gSampleRate; }
+ (void)setGhostMuted:(BOOL)muted { __atomic_store_n(&gGhost, muted ? 1 : 0, __ATOMIC_SEQ_CST); }
+ (BOOL)isGhostMuted { return __atomic_load_n(&gGhost, __ATOMIC_RELAXED) != 0; }
+ (double)firstSampleWallTime { return gFirstSampleTime; }

+ (BOOL)startCapturingToNearPath:(NSString *)nearPath farPath:(NSString *)farPath {

	AudioStreamBasicDescription fmt = {0};
	UInt32 sz = sizeof(fmt);
	if (gVPIO && AudioUnitGetProperty(gVPIO, kAudioUnitProperty_StreamFormat, kAudioUnitScope_Input, 0, &fmt, &sz) == noErr && fmt.mSampleRate > 0) {
		gFormat = fmt;
		gSampleRate = fmt.mSampleRate;
	} else if (gSampleRate <= 0) {
		gSampleRate = 48000;
	}

	pthread_mutex_lock(&gFileLock);
	gNear = fopen(nearPath.fileSystemRepresentation, "wb");
	gFar = fopen(farPath.fileSystemRepresentation, "wb");
	if (gNear) setvbuf(gNear, NULL, _IOFBF, 1 << 16);
	if (gFar) setvbuf(gFar, NULL, _IOFBF, 1 << 16);
	gFirstSampleTime = 0;
	BOOL ok = gNear && gFar;
	pthread_mutex_unlock(&gFileLock);

	if (!ok) { [self stop]; return NO; }
	__atomic_store_n(&gRecording, 1, __ATOMIC_SEQ_CST);
	return YES;
}

+ (void)stop {
	__atomic_store_n(&gRecording, 0, __ATOMIC_SEQ_CST);
	pthread_mutex_lock(&gFileLock);
	if (gNear) { fclose(gNear); gNear = NULL; }
	if (gFar) { fclose(gFar); gFar = NULL; }
	pthread_mutex_unlock(&gFileLock);
}

+ (BOOL)mixNearPath:(NSString *)nearPath farPath:(NSString *)farPath toM4APath:(NSString *)outPath sampleRate:(double)sampleRate {
	NSData *near = [NSData dataWithContentsOfFile:nearPath];
	NSData *far = [NSData dataWithContentsOfFile:farPath];
	NSUInteger nN = near.length / 2, nF = far.length / 2;
	NSUInteger n = MAX(nN, nF);
	if (n == 0) return NO;

	const int16_t *sN = (const int16_t *)near.bytes;
	const int16_t *sF = (const int16_t *)far.bytes;

	// Balance the two sides: the far end is often much quieter than the mic. Normalize
	// each stream toward a target peak (capped gain so silence/noise isn't blown up).
	int32_t peakN = 0, peakF = 0;
	for (NSUInteger i = 0; i < nN; i++) { int32_t a = sN[i] < 0 ? -sN[i] : sN[i]; if (a > peakN) peakN = a; }
	for (NSUInteger i = 0; i < nF; i++) { int32_t a = sF[i] < 0 ? -sF[i] : sF[i]; if (a > peakF) peakF = a; }
	const double target = 22000.0;
	double gN = peakN > 800 ? MIN(4.0, target / peakN) : 1.0;
	double gF = peakF > 800 ? MIN(4.0, target / peakF) : 1.0;

	int16_t *mixed = malloc(n * sizeof(int16_t));
	if (!mixed) return NO;
	for (NSUInteger i = 0; i < n; i++) {
		int32_t a = i < nN ? (int32_t)lround(sN[i] * gN) : 0;
		int32_t b = i < nF ? (int32_t)lround(sF[i] * gF) : 0;
		int32_t s = a + b;
		if (s > 32767) s = 32767; else if (s < -32768) s = -32768;
		mixed[i] = (int16_t)s;
	}

	double rate = sampleRate > 0 ? sampleRate : 48000;
	AVAudioFormat *pcmFmt = [[AVAudioFormat alloc] initWithCommonFormat:AVAudioPCMFormatInt16 sampleRate:rate channels:1 interleaved:YES];
	NSDictionary *settings = @{
		AVFormatIDKey: @(kAudioFormatMPEG4AAC),
		AVSampleRateKey: @(rate),
		AVNumberOfChannelsKey: @1,
		AVEncoderBitRateKey: @96000,
	};
	[NSFileManager.defaultManager removeItemAtPath:outPath error:nil];
	NSError *err = nil;
	AVAudioFile *file = [[AVAudioFile alloc] initForWriting:[NSURL fileURLWithPath:outPath] settings:settings
											  commonFormat:AVAudioPCMFormatInt16 interleaved:YES error:&err];
	if (!file) { NSLog(@"[RyukGram][CallTap] mix: file open failed %@", err); free(mixed); return NO; }

	BOOL ok = YES;
	NSUInteger off = 0;
	const AVAudioFrameCount chunk = 16384;
	while (off < n) {
		AVAudioFrameCount c = (AVAudioFrameCount)MIN((NSUInteger)chunk, n - off);
		AVAudioPCMBuffer *buf = [[AVAudioPCMBuffer alloc] initWithPCMFormat:pcmFmt frameCapacity:c];
		buf.frameLength = c;
		memcpy(buf.int16ChannelData[0], mixed + off, c * sizeof(int16_t));
		if (![file writeFromBuffer:buf error:&err]) { NSLog(@"[RyukGram][CallTap] mix: write failed %@", err); ok = NO; break; }
		off += c;
	}
	free(mixed);
	file = nil;
	return ok;
}

@end
