#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

/// Posted (on main) whenever any job is added, mutated, or removed.
extern NSString *const SCIDownloadCenterDidChangeNotification;

typedef NS_ENUM(NSInteger, SCIDownloadJobState) {
    SCIDownloadJobStateQueued,
    SCIDownloadJobStateDownloading,
    SCIDownloadJobStateEncoding,
    SCIDownloadJobStateWaiting,     // transient failure — will retry on reconnect / shortly
    SCIDownloadJobStateFinished,
    SCIDownloadJobStateFailed,
    SCIDownloadJobStateCancelled,
};

typedef NS_ENUM(NSInteger, SCIDownloadJobKind) {
    SCIDownloadJobKindSimpleURL,   // single NSURLSession download
    SCIDownloadJobKindDashMux,     // DASH video+audio download + ffmpeg mux
};

@interface SCIDownloadJob : NSObject
@property (nonatomic, copy, readonly) NSString *jobID;
@property (nonatomic, copy) NSString *title;
@property (nonatomic, copy, nullable) NSString *subtitle;     // attribution / source
@property (nonatomic, assign) SCIDownloadJobKind kind;
@property (nonatomic, assign) SCIDownloadJobState state;
@property (nonatomic, assign) float progress;
@property (nonatomic, copy, nullable) NSString *stageText;    // "Downloading 42%", "Encoding…", "Queued"
@property (nonatomic, strong, nullable) NSError *error;
@property (nonatomic, strong, readonly) NSDate *createdAt;
@property (nonatomic, strong, nullable) NSDate *finishedAt;
@property (nonatomic, assign) NSInteger autoRetriesUsed;
/// Set before markJobFinished — the single-job pill's success summary. nil → "Done".
@property (nonatomic, copy, nullable) NSString *successText;
/// The finished file, for the manager's preview / share / redownload.
@property (nonatomic, strong, nullable) NSURL *resultFileURL;

/// Runs the real work (resume the task / kick off the mux). Invoked by the center
/// when a concurrency slot frees up. nil after the job leaves the queue.
@property (nonatomic, copy, nullable) void (^startBlock)(void);
/// Cancels in-flight work for this job.
@property (nonatomic, copy, nullable) void (^cancelBlock)(void);
/// Builds a fresh job from the same inputs and enqueues it (for retry / redownload).
@property (nonatomic, copy, nullable) void (^retryBlock)(void);

@property (nonatomic, readonly) BOOL isActive;     // downloading | encoding
@property (nonatomic, readonly) BOOL isTerminal;   // finished | failed | cancelled
@end

@interface SCIDownloadCenter : NSObject
+ (instancetype)shared;

/// Reads `dl_max_concurrent` fresh, clamped to 1…6 (default 3).
@property (nonatomic, readonly) NSInteger maxConcurrent;

/// Register a new job. State starts Queued; the center pumps it to Downloading
/// when a slot is free, then calls `start`. Returns the job so the caller can
/// stash it + attach a retryBlock.
- (SCIDownloadJob *)enqueueJobWithTitle:(NSString *)title
                                   kind:(SCIDownloadJobKind)kind
                                  start:(void (^)(void))start
                                 cancel:(nullable void (^)(void))cancel;

// Producer-side transitions.
- (void)job:(SCIDownloadJob *)job didProgress:(float)progress stage:(nullable NSString *)stage;
- (void)job:(SCIDownloadJob *)job enterEncodingStage:(nullable NSString *)stage;
- (void)markJobFinished:(SCIDownloadJob *)job;
- (void)markJob:(SCIDownloadJob *)job failedWithError:(nullable NSError *)error;
- (void)markJobCancelled:(SCIDownloadJob *)job;

// User-side actions (manager UI).
- (void)cancelJob:(SCIDownloadJob *)job;
- (void)retryJob:(SCIDownloadJob *)job;
- (void)removeJob:(SCIDownloadJob *)job;
- (void)clearFinished;

/// Snapshot in insertion order (oldest first).
- (NSArray<SCIDownloadJob *> *)allJobs;
- (NSInteger)activeCount;
- (NSInteger)queuedCount;
@end

NS_ASSUME_NONNULL_END
