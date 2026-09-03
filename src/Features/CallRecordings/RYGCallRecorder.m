#import "RYGCallRecorder.h"
#import "RYGCallRecordingStorage.h"
#import "RYGCallAudioTap.h"
#import "RYGCallVideoCapture.h"
#import "RYGCallVideoTap.h"
#import "RYGCallSelfVideoTap.h"
#import "RYGCallSelfCaptureTap.h"
#import "RYGCallGridCompositor.h"
#import "RYGCallRecordingGallery.h"
#import "RYGCallRecordingsViewController.h"
#import "../Feed/RYGHomeShortcutBadges.h"
#import "../../Utils.h"

NSNotificationName const RYGCallRecorderStateDidChangeNotification = @"RYGCallRecorderStateDidChangeNotification";
NSNotificationName const RYGCallRecorderCallDidEndNotification = @"RYGCallRecorderCallDidEndNotification";

@interface RYGCallRecorder ()
@property (nonatomic, assign) BOOL isRecording;
@property (nonatomic, assign) BOOL isFinalizing;
@property (nonatomic, copy, nullable) NSString *currentIdentifier;
@property (nonatomic, strong) dispatch_queue_t workQueue;

@property (nonatomic, strong) NSURL *nearURL;
@property (nonatomic, strong) NSURL *farURL;
@property (nonatomic, strong) NSURL *gridURL;
@property (nonatomic, assign) BOOL groupActive;

@property (nonatomic, strong) RYGCallRecording *meta;
@property (nonatomic, copy) NSString *ownerPK;
@property (nonatomic, strong) NSDate *startDate;
@property (nonatomic, assign) NSInteger stopGen;
@end

@implementation RYGCallRecorder

+ (instancetype)sharedRecorder {
	static RYGCallRecorder *r;
	static dispatch_once_t once;
	dispatch_once(&once, ^{ r = [RYGCallRecorder new]; });
	return r;
}

- (instancetype)init {
	if ((self = [super init])) {
		_workQueue = dispatch_queue_create("com.ryukgram.callrecorder.work", DISPATCH_QUEUE_SERIAL);
		[NSNotificationCenter.defaultCenter addObserver:self selector:@selector(vpioLost) name:RYGCallAudioTapUnitLostNotification object:nil];
		[NSNotificationCenter.defaultCenter addObserver:self selector:@selector(vpioStarted) name:RYGCallAudioTapCallStartedNotification object:nil];
	}
	return self;
}

// Call end = VPIO disposed and not recreated; IG recreates it mid-call, hence the debounce.
- (void)vpioStarted { self.stopGen++; }

- (void)vpioLost {
	NSInteger gen = ++self.stopGen;
	dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(3.0 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
		if (gen != self.stopGen) return;   // a new call unit came up → still in a call
		[NSNotificationCenter.defaultCenter postNotificationName:RYGCallRecorderCallDidEndNotification object:nil];
		if (self.isRecording) [self stop];
	});
}

- (void)backfillMeta:(RYGCallRecording *)m {
	if (!self.meta || !m) return;
	if (!self.meta.peerUsername.length && m.peerUsername.length) self.meta.peerUsername = m.peerUsername;
	if (!self.meta.peerFullName.length && m.peerFullName.length) self.meta.peerFullName = m.peerFullName;
	if (!self.meta.peerPk.length && m.peerPk.length) self.meta.peerPk = m.peerPk;
	if (!self.meta.peerProfilePicURL.length && m.peerProfilePicURL.length) self.meta.peerProfilePicURL = m.peerProfilePicURL;
	if (!self.meta.threadId.length && m.threadId.length) self.meta.threadId = m.threadId;
	if (!self.meta.threadTitle.length && m.threadTitle.length) self.meta.threadTitle = m.threadTitle;
	self.currentIdentifier = [RYGCallRecordingStorage identifierForRecording:self.meta];
}

- (NSTimeInterval)currentDuration { return self.startDate ? -[self.startDate timeIntervalSinceNow] : 0; }

static void postState(void) {
	dispatch_async(dispatch_get_main_queue(), ^{
		[NSNotificationCenter.defaultCenter postNotificationName:RYGCallRecorderStateDidChangeNotification object:nil];
	});
}

- (void)startWithVideo:(BOOL)video meta:(RYGCallRecording *)meta automatic:(BOOL)automatic {
	if (self.isRecording || self.isFinalizing) return;

	meta.recordingId = [NSUUID UUID].UUIDString;
	meta.startedAt = [NSDate date];
	meta.startedAutomatically = automatic;
	self.meta = meta;
	self.currentIdentifier = [RYGCallRecordingStorage identifierForRecording:meta];
	self.ownerPK = [RYGUtils currentUserPK] ?: @"anon";
	self.startDate = meta.startedAt;

	self.nearURL = [RYGTempFiles claimWithExt:@"pcm" ttl:1800 tag:@"callnear"];
	self.farURL = [RYGTempFiles claimWithExt:@"pcm" ttl:1800 tag:@"callfar"];

	if (![RYGCallAudioTap startCapturingToNearPath:self.nearURL.path farPath:self.farURL.path]) {
		[RYGTempFiles releaseURL:self.nearURL];
		[RYGTempFiles releaseURL:self.farURL];
		[self resetState];
		RYGNotifyError(RYG_NOTIF_CALL_RECORDING, RYGLocalized(@"Can't record"), RYGLocalized(@"Could not start the recorder."));
		return;
	}

	self.groupActive = NO;
	if (video) {
		// One compositor for every video call — it adapts to the live cameras.
		self.gridURL = [RYGTempFiles claimWithExt:@"mp4" ttl:1800 tag:@"callgrid"];
		self.groupActive = [RYGCallGridCompositor startToURL:self.gridURL];
		if (self.groupActive) {
			[RYGCallVideoTap setGroupMode:YES];
			BOOL selfCam = [RYGUtils getBoolPref:@"call_recordings_self_cam"];
			if (selfCam) { [RYGCallSelfVideoTap setGroupMode:YES]; [RYGCallSelfCaptureTap armForCall]; }
		} else { [RYGTempFiles releaseURL:self.gridURL]; self.gridURL = nil; }
	}
	meta.isVideo = self.groupActive;

	self.isRecording = YES;
	postState();
	RYGNotifyInfo(RYG_NOTIF_CALL_RECORDING, RYGLocalized(@"Recording call"), meta.displayName);
}

- (void)stop {
	if (!self.isRecording) return;
	self.isRecording = NO;
	self.isFinalizing = YES;
	postState();

	[RYGCallAudioTap stop];
	NSTimeInterval duration = self.startDate ? -[self.startDate timeIntervalSinceNow] : 0;
	NSURL *nearURL = self.nearURL, *farURL = self.farURL, *gridURL = self.gridURL;
	BOOL groupActive = self.groupActive;
	RYGCallRecording *meta = self.meta;
	NSString *ownerPK = self.ownerPK;
	double rate = [RYGCallAudioTap sampleRate];

	__weak typeof(self) weakSelf = self;
	void (^finalize)(BOOL) = ^(BOOL gridOK) {
		dispatch_async(weakSelf.workQueue, ^{
			NSURL *mixed = [RYGTempFiles claimWithExt:@"m4a" ttl:600 tag:@"callmix"];
			NSString *audioMode = [RYGUtils getStringPref:@"call_recordings_audio"];
			NSString *nearP = [audioMode isEqualToString:@"theirs"] ? nil : nearURL.path;   // near = your mic
			NSString *farP  = [audioMode isEqualToString:@"mine"]   ? nil : farURL.path;    // far = them
			BOOL aok = [RYGCallAudioTap mixNearPath:nearP farPath:farP toM4APath:mixed.path sampleRate:rate];
			[RYGTempFiles releaseURL:nearURL];
			[RYGTempFiles releaseURL:farURL];

			if (!aok) {
				[RYGTempFiles releaseURL:mixed];
				if (gridURL) [RYGTempFiles releaseURL:gridURL];
				[weakSelf failWith:RYGLocalized(@"No call audio was captured.")];
				return;
			}

			if (groupActive && gridOK && gridURL) {
				NSString *rel = nil;
				NSString *finalPath = [RYGCallRecordingStorage reserveMediaURLForRecordingId:meta.recordingId extension:@"mp4" ownerPK:ownerPK relativePath:&rel];
				double audioT0 = [RYGCallAudioTap firstSampleWallTime];
				double gT0 = [RYGCallGridCompositor firstFrameWallTime];
				double delta = (audioT0 > 0 && gT0 > 0) ? (gT0 - audioT0) : 0;   // + video later, - audio later
				double vOff = delta > 0 ? delta : 0, aOff = delta < 0 ? -delta : 0;
				[RYGCallVideoCapture muxVideo:gridURL audio:mixed videoOffset:vOff audioOffset:aOff toURL:[NSURL fileURLWithPath:finalPath] completion:^(BOOL ok) {
					dispatch_async(weakSelf.workQueue, ^{
						if (gridURL) [RYGTempFiles releaseURL:gridURL];
						if (ok) { [RYGTempFiles releaseURL:mixed]; meta.isVideo = YES; [weakSelf commit:meta rel:rel path:finalPath duration:duration ownerPK:ownerPK]; }
						else { meta.isVideo = NO; [weakSelf installAudioOnly:mixed meta:meta duration:duration ownerPK:ownerPK]; }
					});
				}];
				return;
			}

			if (gridURL) [RYGTempFiles releaseURL:gridURL];
			meta.isVideo = NO;
			[weakSelf installAudioOnly:mixed meta:meta duration:duration ownerPK:ownerPK];
		});
	};

	if (groupActive) {
		[RYGCallVideoTap setGroupMode:NO];
		[RYGCallSelfVideoTap setGroupMode:NO];
		[RYGCallGridCompositor stopWithCompletion:^(BOOL ok) { finalize(ok); }];
	} else {
		finalize(NO);
	}
}

- (void)installAudioOnly:(NSURL *)mixedURL meta:(RYGCallRecording *)meta duration:(NSTimeInterval)duration ownerPK:(NSString *)ownerPK {
	NSString *rel = nil;
	NSString *finalPath = [RYGCallRecordingStorage reserveMediaURLForRecordingId:meta.recordingId extension:@"m4a" ownerPK:ownerPK relativePath:&rel];
	[NSFileManager.defaultManager removeItemAtPath:finalPath error:nil];
	BOOL ok = [NSFileManager.defaultManager copyItemAtPath:mixedURL.path toPath:finalPath error:nil];
	[RYGTempFiles releaseURL:mixedURL];
	if (!ok) { [self failWith:RYGLocalized(@"Could not save the recording.")]; return; }
	[self commit:meta rel:rel path:finalPath duration:duration ownerPK:ownerPK];
}

- (void)commit:(RYGCallRecording *)meta rel:(NSString *)rel path:(NSString *)finalPath duration:(NSTimeInterval)duration ownerPK:(NSString *)ownerPK {
	unsigned long long size = [[NSFileManager.defaultManager attributesOfItemAtPath:finalPath error:nil][NSFileSize] unsignedLongLongValue];
	meta.mediaPath = rel;
	meta.durationSeconds = duration;
	meta.fileSizeBytes = size;
	[RYGCallRecordingStorage saveRecording:meta forOwnerPK:ownerPK];
	[RYGHomeShortcutBadges bumpActionID:@"call_recordings"];
	NSInteger retention = (NSInteger)[RYGUtils getStringPref:@"call_recordings_retention"].integerValue;
	if (retention > 0) [RYGCallRecordingStorage pruneOlderThanDays:retention forOwnerPK:ownerPK];
	if ([RYGUtils getBoolPref:@"call_recordings_sync_gallery"])
		[RYGCallRecordingGallery syncRecording:meta absolutePath:finalPath ownerPK:ownerPK];
	[self resetState];
	dispatch_async(dispatch_get_main_queue(), ^{
		RYGNotifyTap(RYG_NOTIF_CALL_RECORDING, RYGLocalized(@"Call recorded"), meta.displayName, nil, RYGNotificationToneSuccess, ^{
			[RYGCallRecordingsViewController presentFromViewController:nil];
		});
	});
}

- (void)failWith:(NSString *)message {
	[self resetState];
	dispatch_async(dispatch_get_main_queue(), ^{
		RYGNotifyError(RYG_NOTIF_CALL_RECORDING, RYGLocalized(@"Recording failed"), message);
	});
}

- (void)resetState {
	self.nearURL = nil;
	self.farURL = nil;
	self.gridURL = nil;
	self.groupActive = NO;
	self.meta = nil;
	self.currentIdentifier = nil;
	self.startDate = nil;
	self.isRecording = NO;
	self.isFinalizing = NO;
	postState();
}

@end
