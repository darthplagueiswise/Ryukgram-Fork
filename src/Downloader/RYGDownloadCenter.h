#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

/// Posted (on main) whenever any job is added, mutated, or removed.
extern NSString *const RYGDownloadCenterDidChangeNotification;

typedef NS_ENUM(NSInteger, RYGDownloadJobState) {
    RYGDownloadJobStateQueued,
    RYGDownloadJobStateDownloading,
    RYGDownloadJobStateEncoding,
    RYGDownloadJobStateWaiting,     // transient failure — will retry on reconnect / shortly
    RYGDownloadJobStateFinished,
    RYGDownloadJobStateFailed,
    RYGDownloadJobStateCancelled,
};

typedef NS_ENUM(NSInteger, RYGDownloadJobKind) {
    RYGDownloadJobKindSimpleURL,   // single NSURLSession download
    RYGDownloadJobKindDashMux,     // DASH video+audio download + ffmpeg mux
};

typedef NS_ENUM(NSInteger, RYGDownloadMediaKind) {
    RYGDownloadMediaKindOther,
    RYGDownloadMediaKindVideo,
    RYGDownloadMediaKindPhoto,
    RYGDownloadMediaKindAudio,
};

FOUNDATION_EXPORT RYGDownloadMediaKind RYGDownloadMediaKindForExtension(NSString *_Nullable ext);

@interface RYGDownloadJob : NSObject
/// Thumbnails are filed under this, so a restored job keeps its saved ID.
/// Pass nil for a fresh download.
- (instancetype)initWithJobID:(nullable NSString *)jobID NS_DESIGNATED_INITIALIZER;

@property (nonatomic, copy, readonly) NSString *jobID;
@property (nonatomic, copy) NSString *title;
@property (nonatomic, copy, nullable) NSString *subtitle;     // attribution / source
@property (nonatomic, assign) RYGDownloadJobKind kind;
@property (nonatomic, assign) RYGDownloadMediaKind mediaKind;
@property (nonatomic, assign) RYGDownloadJobState state;
@property (nonatomic, assign) float progress;
@property (nonatomic, copy, nullable) NSString *stageText;    // "Downloading 42%", "Encoding…", "Queued"
@property (nonatomic, strong, nullable) NSError *error;
@property (nonatomic, strong) NSDate *createdAt;
@property (nonatomic, strong, nullable) NSDate *startedAt;
@property (nonatomic, strong, nullable) NSDate *finishedAt;
@property (nonatomic, assign) NSInteger autoRetriesUsed;
@property (nonatomic, assign) int64_t bytesReceived;
@property (nonatomic, assign) int64_t bytesExpected;
/// Smoothed transfer rate; 0 until two samples land.
@property (nonatomic, readonly) double bytesPerSecond;
/// Seconds left at the current rate, or -1 when it can't be estimated.
@property (nonatomic, readonly) NSTimeInterval estimatedSecondsRemaining;
/// Media items this one job covers; the batch pill counts items, not jobs.
@property (nonatomic, assign) NSUInteger itemCount;
/// A later phase (e.g. save after download) over items already counted; excluded from the batch total.
@property (nonatomic, assign) BOOL continuationPhase;
/// Set before markJobFinished — the single-job pill's success summary. nil → "Done".
@property (nonatomic, copy, nullable) NSString *successText;
/// The finished file, for the manager's preview / share / redownload.
@property (nonatomic, strong, nullable) NSURL *resultFileURL;

/// Runs the real work (resume the task / kick off the mux). Invoked by the center
/// when a concurrency slot frees up. nil after the job leaves the queue.
@property (nonatomic, copy, nullable) void (^startBlock)(void);
/// Cancels in-flight work for this job.
@property (nonatomic, copy, nullable) void (^cancelBlock)(void);
/// Rebuilds and enqueues the job. Lost when the app dies — `retryInfo` survives.
@property (nonatomic, copy, nullable) void (^retryBlock)(void);
/// JSON-safe rebuild recipe, keyed by `kind` onto a registered builder.
@property (nonatomic, copy, nullable) NSDictionary *retryInfo;

/// A live retryBlock, or a retryInfo whose builder is registered.
@property (nonatomic, readonly) BOOL canRetry;

@property (nonatomic, readonly) BOOL isActive;     // downloading | encoding
@property (nonatomic, readonly) BOOL isTerminal;   // finished | failed | cancelled
@end

@interface RYGDownloadCenter : NSObject
+ (instancetype)shared;

/// Rebuilds a `kind` of download from persisted retryInfo. Register from +load.
+ (void)registerRetryBuilder:(void (^)(NSDictionary *info))builder forKind:(NSString *)kind;

/// Reads `dl_max_concurrent` fresh, clamped to 1…6 (default 3).
@property (nonatomic, readonly) NSInteger maxConcurrent;

/// Register a new job. State starts Queued; the center pumps it to Downloading
/// when a slot is free, then calls `start`. Returns the job so the caller can
/// stash it + attach a retryBlock.
- (RYGDownloadJob *)enqueueJobWithTitle:(NSString *)title
                                   kind:(RYGDownloadJobKind)kind
                                  start:(void (^)(void))start
                                 cancel:(nullable void (^)(void))cancel;

// Producer-side transitions.
- (void)job:(RYGDownloadJob *)job didProgress:(float)progress stage:(nullable NSString *)stage;
- (void)job:(RYGDownloadJob *)job didProgress:(float)progress
     received:(int64_t)received
        total:(int64_t)total
        stage:(nullable NSString *)stage;
- (void)job:(RYGDownloadJob *)job enterEncodingStage:(nullable NSString *)stage;
- (void)markJobFinished:(RYGDownloadJob *)job;
- (void)markJob:(RYGDownloadJob *)job failedWithError:(nullable NSError *)error;
- (void)markJobCancelled:(RYGDownloadJob *)job;

// User-side actions (manager UI).
- (void)cancelJob:(RYGDownloadJob *)job;
- (void)retryJob:(RYGDownloadJob *)job;
- (void)removeJob:(RYGDownloadJob *)job;
- (void)clearFinished;
/// Drops every terminal job and the persisted history behind them.
- (void)clearHistory;

/// Snapshot in insertion order (oldest first).
- (NSArray<RYGDownloadJob *> *)allJobs;
- (NSInteger)activeCount;
- (NSInteger)queuedCount;
@end

NS_ASSUME_NONNULL_END
