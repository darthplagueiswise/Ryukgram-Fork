#import "RYGBackgroundActivity.h"
#import "../Utils.h"
#import <AVFoundation/AVFoundation.h>
#import <UIKit/UIKit.h>

// Momentary playback each cycle renews the assertion; the rolling UIBackgroundTask
// bridges the gaps. Don't play continuously or drop the bg task — both break it.
static const NSTimeInterval kRYGCycleInterval = 10.0;

static inline void RYGWAV16(NSMutableData *d, uint16_t v) { [d appendBytes:&v length:2]; }
static inline void RYGWAV32(NSMutableData *d, uint32_t v) { [d appendBytes:&v length:4]; }

// Silent PCM WAV built in memory — no bundled asset to ship.
// 0.2s mono @ 8kHz.
static NSData *RYGSilentWAVData(void) {
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
		[d appendBytes:"RIFF" length:4]; RYGWAV32(d, 36 + dataLen); [d appendBytes:"WAVE" length:4];
		[d appendBytes:"fmt " length:4]; RYGWAV32(d, 16); RYGWAV16(d, 1); RYGWAV16(d, channels);
		RYGWAV32(d, sampleRate); RYGWAV32(d, byteRate); RYGWAV16(d, blockAlign); RYGWAV16(d, bitsPerSample);
		[d appendBytes:"data" length:4]; RYGWAV32(d, dataLen);
		[d increaseLengthBy:dataLen]; // zero-filled = silence
		data = d.copy;
	});
	return data;
}

@interface RYGBackgroundActivity ()
@property (nonatomic, strong) NSMutableSet<NSString *> *sources;
@property (nonatomic, strong, nullable) AVAudioPlayer *player;
@property (nonatomic, assign) UIBackgroundTaskIdentifier bgTask;
@property (nonatomic, assign) BOOL running;
@property (nonatomic, assign) BOOL interrupted;
@property (nonatomic, assign) NSUInteger generation;
@end

@implementation RYGBackgroundActivity

+ (instancetype)shared {
	static RYGBackgroundActivity *s;
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

	RYGBackgroundActivity *m = self.shared;
	dispatch_async(dispatch_get_main_queue(), ^{
		active ? [m.sources addObject:source] : [m.sources removeObject:source];
		[m reconcile];
	});
}

+ (BOOL)prefAllowsSource:(NSString *)source {
	if ([source isEqualToString:@"dm_keepalive"]) return [RYGUtils getBoolPref:@"deleted_messages_keepalive"];
	if ([source isEqualToString:@"cache_autoclear"]) {
		NSString *mode = [[NSUserDefaults standardUserDefaults] stringForKey:@"cache_auto_clear_mode"];
		return mode.length && ![mode isEqualToString:@"off"];
	}
	return [RYGUtils getBoolPref:@"bg_keepalive"];
}

- (void)reconcile {
	BOOL authorized = NO;
	for (NSString *s in self.sources) {
		if ([RYGBackgroundActivity prefAllowsSource:s]) { authorized = YES; break; }
	}

	authorized ? [self startKeepAlive] : [self stopKeepAlive];
}

#pragma mark - Lifecycle

- (void)startKeepAlive {
	if (self.running) return;

	// Activation can fail transiently (call/Siri/reel owns the session) — start anyway,
	// marked interrupted so the cycle keeps reclaiming.
	self.running = YES;
	self.interrupted = ![self activateSession];
	[NSNotificationCenter.defaultCenter addObserver:self selector:@selector(handleInterruption:) name:AVAudioSessionInterruptionNotification object:AVAudioSession.sharedInstance];
	[NSNotificationCenter.defaultCenter addObserver:self selector:@selector(handleMediaReset:) name:AVAudioSessionMediaServicesWereResetNotification object:AVAudioSession.sharedInstance];
	[self runCycle:self.generation];
}

- (void)stopKeepAlive {
	if (!self.running) return;

	self.running = NO;
	self.interrupted = NO;
	self.generation++;

	[NSNotificationCenter.defaultCenter removeObserver:self name:AVAudioSessionInterruptionNotification object:AVAudioSession.sharedInstance];
	[NSNotificationCenter.defaultCenter removeObserver:self name:AVAudioSessionMediaServicesWereResetNotification object:AVAudioSession.sharedInstance];
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

	// Play failure is transient (interruption, IG tearing down the shared session when a
	// reel pauses on backgrounding, media reset) — never stop while sources are active,
	// reclaim instead. Retry fast when unhealthy: the bg-task budget is only ~30s.
	BOOL healthy = YES;
	if (self.interrupted || ![self playAudio]) {
		self.player = nil;
		healthy = [self activateSession] && [self playAudio];
		if (healthy) self.interrupted = NO;
	}

	[self armBgTask:gen afterDelay:healthy ? kRYGCycleInterval : 2.0];
}

- (void)armBgTask:(NSUInteger)gen afterDelay:(NSTimeInterval)delay {
	[self endBgTask];

	__weak typeof(self) weakSelf = self;
	self.bgTask = [UIApplication.sharedApplication beginBackgroundTaskWithName:@"ryg.keepalive" expirationHandler:^{
		dispatch_async(dispatch_get_main_queue(), ^{
			RYGBackgroundActivity *m = weakSelf;
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

	dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(delay * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
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
		self.player = [[AVAudioPlayer alloc] initWithData:RYGSilentWAVData() error:&err];
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
		self.interrupted = ![self activateSession];
		[self runCycle:self.generation];
	}
}

// Media-services reset kills the player and wipes the session config — route the next
// cycle through the reclaim path with a fresh player.
- (void)handleMediaReset:(__unused NSNotification *)note {
	if (!self.running) return;
	self.player = nil;
	self.interrupted = YES;
}

@end