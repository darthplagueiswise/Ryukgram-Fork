#import "SCIBackgroundActivity.h"
#import "../Utils.h"
#import <AVFoundation/AVFoundation.h>
#import <UIKit/UIKit.h>

// Momentary playback each cycle renews the assertion; the rolling UIBackgroundTask
// bridges the gaps. Don't play continuously or drop the bg task — both break it.
static const NSTimeInterval kSCICycleInterval = 10.0;

static inline void SCIWAV16(NSMutableData *d, uint16_t v) { [d appendBytes:&v length:2]; }
static inline void SCIWAV32(NSMutableData *d, uint32_t v) { [d appendBytes:&v length:4]; }

// Silent PCM WAV built in memory — no bundled asset to ship.
// 0.2s mono @ 8kHz.
static NSData *SCISilentWAVData(void) {
	static NSData *data;
	static dispatch_once_t once;
	dispatch_once(&once, ^{
		const uint32_t sampleRate = 8000, channels = 1, bitsPerSample = 16;
		const uint32_t frames = sampleRate / 5;
		const uint32_t bytesPerSample = bitsPerSample / 8;
		const uint32_t dataLen = frames * channels * bytesPerSample;
		const uint32_t byteRate = sampleRate * channels * bytesPerSample;
		const uint16_t blockAlign = channels * bytesPerSample;

		NSMutableData *d = [NSMutableData dataWithCapacity:44 + dataLen];
		[d appendBytes:"RIFF" length:4]; SCIWAV32(d, 36 + dataLen); [d appendBytes:"WAVE" length:4];
		[d appendBytes:"fmt " length:4]; SCIWAV32(d, 16); SCIWAV16(d, 1); SCIWAV16(d, channels);
		SCIWAV32(d, sampleRate); SCIWAV32(d, byteRate); SCIWAV16(d, blockAlign); SCIWAV16(d, bitsPerSample);
		[d appendBytes:"data" length:4]; SCIWAV32(d, dataLen);
		[d increaseLengthBy:dataLen]; // zero-filled = silence
		data = d.copy;
	});
	return data;
}

@interface SCIBackgroundActivity ()
@property (nonatomic, strong) NSMutableSet<NSString *> *sources;
@property (nonatomic, strong, nullable) AVAudioPlayer *player;
@property (nonatomic, assign) UIBackgroundTaskIdentifier bgTask;
@property (nonatomic, assign) BOOL running;
@property (nonatomic, assign) BOOL interrupted;
@property (nonatomic, assign) NSUInteger generation;
@end

@implementation SCIBackgroundActivity

+ (instancetype)shared {
	static SCIBackgroundActivity *s;
	static dispatch_once_t once;
	dispatch_once(&once, ^{ s = self.new; });
	return s;
}

- (instancetype)init {
	if ((self = [super init])) {
		_sources = NSMutableSet.set;
		_bgTask = UIBackgroundTaskInvalid;
	}
	return self;
}

#pragma mark - Public

+ (void)setSource:(NSString *)source active:(BOOL)active {
	if (!source.length) return;

	SCIBackgroundActivity *m = self.shared;
	dispatch_async(dispatch_get_main_queue(), ^{
		active ? [m.sources addObject:source] : [m.sources removeObject:source];
		[m reconcile];
	});
}

+ (BOOL)prefAllowsSource:(NSString *)source {
	if ([source isEqualToString:@"dm_keepalive"]) return [SCIUtils getBoolPref:@"deleted_messages_keepalive"];
	return [SCIUtils getBoolPref:@"bg_keepalive"];
}

- (void)reconcile {
	BOOL authorized = NO;
	for (NSString *s in self.sources) {
		if ([SCIBackgroundActivity prefAllowsSource:s]) { authorized = YES; break; }
	}

	authorized ? [self startKeepAlive] : [self stopKeepAlive];
}

#pragma mark - Lifecycle

- (void)startKeepAlive {
	if (self.running || ![self activateSession]) return;

	self.running = YES;
	self.interrupted = NO;
	[NSNotificationCenter.defaultCenter addObserver:self selector:@selector(handleInterruption:) name:AVAudioSessionInterruptionNotification object:AVAudioSession.sharedInstance];
	[self runCycle:self.generation];
}

- (void)stopKeepAlive {
	if (!self.running) return;

	self.running = NO;
	self.interrupted = NO;
	self.generation++;

	[NSNotificationCenter.defaultCenter removeObserver:self name:AVAudioSessionInterruptionNotification object:AVAudioSession.sharedInstance];
	[self endBgTask];
	[self stopAudio];
	self.player = nil;

	// Do NOT deactivate AVAudioSession here.
	// Instagram/Reels uses the same process audio session, and deactivating it
	// can briefly mute the currently playing Reel when downloads finish.
}

- (BOOL)activateSession {
	NSError *err = nil;
	AVAudioSession *s = AVAudioSession.sharedInstance;

	[s setCategory:AVAudioSessionCategoryPlayback withOptions:AVAudioSessionCategoryOptionMixWithOthers error:&err];
	if (err) { NSLog(@"[RyukGram][BGActivity] session category failed: %@", err); return NO; }

	[s setActive:YES error:&err];
	if (err) { NSLog(@"[RyukGram][BGActivity] session activate failed: %@", err); return NO; }

	return YES;
}

#pragma mark - Cycle

- (void)runCycle:(NSUInteger)gen {
	if (!self.running || gen != self.generation) return;

	// Mid-interruption the silent player can't start — don't stopKeepAlive (that drops
	// the InterruptionEnded resume). Reclaim the session, else hold and retry next cycle.
	if (self.interrupted) {
		if ([self activateSession] && [self playAudio]) self.interrupted = NO;
		else { [self armBgTask:gen]; return; }
	} else if (![self playAudio]) {
		[self stopKeepAlive];
		return;
	}

	[self armBgTask:gen];
}

- (void)armBgTask:(NSUInteger)gen {
	[self endBgTask];

	__weak typeof(self) weakSelf = self;
	self.bgTask = [UIApplication.sharedApplication beginBackgroundTaskWithName:@"sci.keepalive" expirationHandler:^{
		dispatch_async(dispatch_get_main_queue(), ^{
			SCIBackgroundActivity *m = weakSelf;
			if (!m || !m.running) return;
			[m endBgTask];
			[m runCycle:m.generation];
		});
	}];

	[self stopAudio];

	if (self.bgTask == UIBackgroundTaskInvalid) {
		dispatch_async(dispatch_get_main_queue(), ^{ [weakSelf runCycle:gen]; });
		return;
	}

	dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(kSCICycleInterval * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
		[weakSelf runCycle:gen];
	});
}

- (void)endBgTask {
	if (self.bgTask == UIBackgroundTaskInvalid) return;
	[UIApplication.sharedApplication endBackgroundTask:self.bgTask];
	self.bgTask = UIBackgroundTaskInvalid;
}

#pragma mark - Audio

- (BOOL)playAudio {
	if (!self.player) {
		NSError *err = nil;
		self.player = [[AVAudioPlayer alloc] initWithData:SCISilentWAVData() error:&err];
		if (err || !self.player) { NSLog(@"[RyukGram][BGActivity] player init failed: %@", err); return NO; }

		self.player.volume = 0.0f;
		self.player.numberOfLoops = 0;
		[self.player prepareToPlay];
	}

	self.player.currentTime = 0;
	return self.player.play;
}

- (void)stopAudio {
	if (!self.player.isPlaying) return;
	[self.player stop];
	self.player.currentTime = 0;
}

- (void)handleInterruption:(NSNotification *)note {
	if (!self.running) return;

	AVAudioSessionInterruptionType type = [note.userInfo[AVAudioSessionInterruptionTypeKey] unsignedIntegerValue];
	if (type == AVAudioSessionInterruptionTypeBegan) {
		self.interrupted = YES;
		[self stopAudio];
		return;
	}

	if (type == AVAudioSessionInterruptionTypeEnded) {
		self.interrupted = NO;
		[self activateSession] ? [self runCycle:self.generation] : [self stopKeepAlive];
	}
}

@end