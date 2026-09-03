#import <Foundation/Foundation.h>
#import "RYGCallRecordingModels.h"

NS_ASSUME_NONNULL_BEGIN

extern NSNotificationName const RYGCallRecorderStateDidChangeNotification;
// Posted once when a call truly ends (audio unit gone and not recreated).
extern NSNotificationName const RYGCallRecorderCallDidEndNotification;

// Audio tap (far end + mic) plus the video grid, muxed into one file on stop.
@interface RYGCallRecorder : NSObject

+ (instancetype)sharedRecorder;

@property (nonatomic, readonly) BOOL isRecording;
@property (nonatomic, readonly) BOOL isFinalizing;
@property (nonatomic, readonly) NSTimeInterval currentDuration;
// nil when idle; a change means a new call rather than a mid-call VPIO restart.
@property (nonatomic, readonly, copy, nullable) NSString *currentIdentifier;

- (void)startWithVideo:(BOOL)video meta:(RYGCallRecording *)meta automatic:(BOOL)automatic;
- (void)stop;

// Identity resolves late, so empty peer/thread fields are filled in as it arrives.
- (void)backfillMeta:(RYGCallRecording *)meta;

@end

NS_ASSUME_NONNULL_END
