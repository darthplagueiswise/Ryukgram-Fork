#import <Foundation/Foundation.h>
#import "RYGCallRecordingModels.h"

NS_ASSUME_NONNULL_BEGIN

extern NSNotificationName const RYGCallRecorderStateDidChangeNotification;
// Posted once when a call truly ends (audio unit gone and not recreated).
extern NSNotificationName const RYGCallRecorderCallDidEndNotification;

// Orchestrates a call recording: audio tap (far-end + mic) + the video grid, muxed
// into one file on stop. One recording at a time.
@interface RYGCallRecorder : NSObject

+ (instancetype)sharedRecorder;

@property (nonatomic, readonly) BOOL isRecording;
@property (nonatomic, readonly) BOOL isFinalizing;
@property (nonatomic, readonly) NSTimeInterval currentDuration;
// Grouping identity of the in-progress recording (nil when idle). Used to detect a
// new call vs a mid-call VPIO restart.
@property (nonatomic, readonly, copy, nullable) NSString *currentIdentifier;

// meta carries peer/thread identity captured from the call; recorder fills in
// mediaPath / duration / size / startedAt and persists it on stop.
- (void)startWithVideo:(BOOL)video meta:(RYGCallRecording *)meta;
- (void)stop;
- (void)toggleWithVideo:(BOOL)video meta:(RYGCallRecording *)meta;

// Fill in any empty peer/thread fields on the in-progress recording (identity
// resolves late — session isn't populated when auto-record starts).
- (void)backfillMeta:(RYGCallRecording *)meta;

@end

NS_ASSUME_NONNULL_END
