#import "RYGDownloadCenter.h"
#import "RYGDownloadHistory.h"
#import "RYGDownloadThumbs.h"
#import "../Utils.h"
#import "../Background/RYGBackgroundActivity.h"
#import <SystemConfiguration/SystemConfiguration.h>
#import <netinet/in.h>

NSString *const RYGDownloadCenterDidChangeNotification = @"RYGDownloadCenterDidChangeNotification";

RYGDownloadMediaKind RYGDownloadMediaKindForExtension(NSString *ext) {
    NSString *e = ext.lowercaseString;
    if (!e.length) return RYGDownloadMediaKindOther;
    if ([@[@"mp4", @"mov", @"m4v"] containsObject:e]) return RYGDownloadMediaKindVideo;
    if ([@[@"m4a", @"mp3", @"aac", @"wav"] containsObject:e]) return RYGDownloadMediaKindAudio;
    if ([@[@"jpg", @"jpeg", @"png", @"heic", @"webp", @"gif"] containsObject:e]) return RYGDownloadMediaKindPhoto;
    return RYGDownloadMediaKindOther;
}

// Keep terminal jobs around for the manager UI, but don't grow forever.
static const NSUInteger kRYGMaxTerminalJobs = 100;

@interface RYGDownloadJob ()
@property (nonatomic, copy, nullable) NSString *batchID;
- (void)noteReceived:(int64_t)received total:(int64_t)total;
@end

// Grace window: keep a drained batch open briefly so a closely-following download
// joins the same pill instead of spawning a fresh one.
static const NSTimeInterval kRYGBatchGrace = 0.7;

@interface RYGDownloadCenter ()
+ (void (^)(NSDictionary *))retryBlockForInfo:(NSDictionary *)info;
@property (nonatomic, strong) NSMutableArray<RYGDownloadJob *> *jobs;
@property (nonatomic, copy, nullable) NSString *currentBatchID;     // guarded by @synchronized(jobs)
@property (nonatomic, strong, nullable) RYGNotificationHandle *aggregateHandle;  // main thread only
@property (nonatomic, assign) BOOL finalizeScheduled;              // main thread only
@property (nonatomic, assign) NSInteger pendingAutoRetryCount;     // carried into the next enqueue
@property (nonatomic, strong) NSMutableArray<RYGDownloadJob *> *waitingForNetwork;  // main thread only
- (BOOL)hasPendingWork;
@end

@implementation RYGDownloadJob {
    NSTimeInterval _sampleTime;
    int64_t _sampleBytes;
}
- (instancetype)init { return [self initWithJobID:nil]; }

- (instancetype)initWithJobID:(NSString *)jobID {
    self = [super init];
    if (self) {
        _jobID = [(jobID.length ? jobID : NSUUID.UUID.UUIDString) copy];
        _createdAt = [NSDate date];
        _state = RYGDownloadJobStateQueued;
        _progress = 0.0f;
    }
    return self;
}

// Smoothed over >=0.4s windows; raw per-chunk deltas are unreadable.
- (void)noteReceived:(int64_t)received total:(int64_t)total {
    if (total > 0) _bytesExpected = total;
    _bytesReceived = received;

    NSTimeInterval now = [NSDate timeIntervalSinceReferenceDate];
    if (_sampleTime <= 0) { _sampleTime = now; _sampleBytes = received; return; }

    NSTimeInterval dt = now - _sampleTime;
    if (dt < 0.4 || received <= _sampleBytes) return;
    double instant = (double)(received - _sampleBytes) / dt;
    _bytesPerSecond = _bytesPerSecond > 0 ? (_bytesPerSecond * 0.6 + instant * 0.4) : instant;
    _sampleTime = now;
    _sampleBytes = received;
}

- (NSTimeInterval)estimatedSecondsRemaining {
    if (_bytesPerSecond <= 0 || _bytesExpected <= 0) return -1;
    int64_t left = _bytesExpected - _bytesReceived;
    if (left <= 0) return -1;
    return (double)left / _bytesPerSecond;
}
// Last moment the bytes are guaranteed present — both Photos saves move the file.
- (void)setResultFileURL:(NSURL *)resultFileURL {
    _resultFileURL = resultFileURL;
    if (resultFileURL) [RYGDownloadThumbs captureForJob:self];
}

- (BOOL)canRetry {
    if (_retryBlock) return YES;
    return [RYGDownloadCenter retryBlockForInfo:_retryInfo] != nil;
}

- (BOOL)isActive {
    return _state == RYGDownloadJobStateDownloading || _state == RYGDownloadJobStateEncoding;
}
- (BOOL)isTerminal {
    return _state == RYGDownloadJobStateFinished
        || _state == RYGDownloadJobStateFailed
        || _state == RYGDownloadJobStateCancelled;
}
@end

@implementation RYGDownloadCenter {
    SCNetworkReachabilityRef _reachRef;
}

+ (instancetype)shared {
    static RYGDownloadCenter *shared;
    static dispatch_once_t once;
    dispatch_once(&once, ^{ shared = [RYGDownloadCenter new]; });
    return shared;
}

#pragma mark - Retry registry

+ (NSMutableDictionary<NSString *, id> *)retryBuilders {
    static NSMutableDictionary *builders;
    static dispatch_once_t once;
    dispatch_once(&once, ^{ builders = [NSMutableDictionary dictionary]; });
    return builders;
}

+ (void)registerRetryBuilder:(void (^)(NSDictionary *))builder forKind:(NSString *)kind {
    if (!builder || !kind.length) return;
    @synchronized ([self retryBuilders]) { [self retryBuilders][kind] = [builder copy]; }
}

+ (void (^)(NSDictionary *))retryBlockForInfo:(NSDictionary *)info {
    NSString *kind = info[@"kind"];
    if (![kind isKindOfClass:NSString.class]) return nil;
    @synchronized ([self retryBuilders]) { return [self retryBuilders][kind]; }
}

- (instancetype)init {
    self = [super init];
    if (self) {
        _jobs = [[RYGDownloadHistory loadJobs] mutableCopy];
        _waitingForNetwork = [NSMutableArray new];
        [self startReachability];
    }
    return self;
}

- (void)persistHistory {
    NSArray<RYGDownloadJob *> *snapshot;
    @synchronized (self.jobs) { snapshot = [self.jobs copy]; }
    [RYGDownloadHistory saveJobs:snapshot];
}

- (void)clearHistory {
    @synchronized (self.jobs) {
        NSMutableArray *remove = [NSMutableArray array];
        for (RYGDownloadJob *j in self.jobs) if (j.isTerminal) [remove addObject:j];
        [self.jobs removeObjectsInArray:remove];
    }
    [RYGDownloadHistory resetAll];
    [self notifyChange];
}

#pragma mark - Reachability

static void rygReachabilityCallback(SCNetworkReachabilityRef target, SCNetworkReachabilityFlags flags, void *info) {
    (void)target;
    BOOL up = (flags & kSCNetworkReachabilityFlagsReachable) && !(flags & kSCNetworkReachabilityFlagsConnectionRequired);
    [(__bridge RYGDownloadCenter *)info networkBecameReachable:up];
}

- (void)startReachability {
    struct sockaddr_in zero;
    bzero(&zero, sizeof(zero));
    zero.sin_len = sizeof(zero);
    zero.sin_family = AF_INET;
    _reachRef = SCNetworkReachabilityCreateWithAddress(NULL, (const struct sockaddr *)&zero);
    if (!_reachRef) return;
    SCNetworkReachabilityContext ctx = { 0, (__bridge void *)self, NULL, NULL, NULL };
    SCNetworkReachabilitySetCallback(_reachRef, rygReachabilityCallback, &ctx);
    SCNetworkReachabilityScheduleWithRunLoop(_reachRef, CFRunLoopGetMain(), kCFRunLoopCommonModes);
}

- (BOOL)networkReachable {
    if (!_reachRef) return YES;  // assume online if we can't tell
    SCNetworkReachabilityFlags flags = 0;
    if (!SCNetworkReachabilityGetFlags(_reachRef, &flags)) return YES;
    return (flags & kSCNetworkReachabilityFlagsReachable) && !(flags & kSCNetworkReachabilityFlagsConnectionRequired);
}

- (void)networkBecameReachable:(BOOL)up {
    if (!up) return;
    NSArray<RYGDownloadJob *> *pending = [self.waitingForNetwork copy];
    [self.waitingForNetwork removeAllObjects];
    for (RYGDownloadJob *j in pending)
        if (j.state == RYGDownloadJobStateWaiting) [self autoRetryJob:j];
}

- (NSInteger)maxConcurrent {
    NSInteger n = (NSInteger)llround([RYGUtils getDoublePref:@"dl_max_concurrent"]);
    return MIN(6, MAX(1, n));
}

#pragma mark - Enqueue

- (RYGDownloadJob *)enqueueJobWithTitle:(NSString *)title
                                   kind:(RYGDownloadJobKind)kind
                                  start:(void (^)(void))start
                                 cancel:(void (^)(void))cancel {
    RYGDownloadJob *job = [RYGDownloadJob new];
    job.title = title ?: RYGLocalized(@"Downloading…");
    job.kind = kind;
    job.startBlock = [start copy];
    job.cancelBlock = [cancel copy];
    job.stageText = RYGLocalized(@"Queued");
    job.itemCount = 1;
    job.autoRetriesUsed = self.pendingAutoRetryCount;   // inherited across an auto-retry rebuild

    @synchronized (self.jobs) {
        if (!self.currentBatchID) self.currentBatchID = [NSUUID.UUID.UUIDString copy];
        job.batchID = self.currentBatchID;
        [self.jobs addObject:job];
    }
    [self pump];
    return job;
}

#pragma mark - Pump (concurrency gate)

- (void)pump {
    NSMutableArray<RYGDownloadJob *> *toStart = [NSMutableArray array];
    @synchronized (self.jobs) {
        NSInteger active = 0;
        for (RYGDownloadJob *j in self.jobs) if (j.isActive) active++;
        NSInteger max = self.maxConcurrent;
        for (RYGDownloadJob *j in self.jobs) {
            if (active >= max) break;
            if (j.state != RYGDownloadJobStateQueued) continue;
            j.state = RYGDownloadJobStateDownloading;
            j.startedAt = [NSDate date];
            j.stageText = RYGLocalized(@"Starting…");
            [toStart addObject:j];
            active++;
        }
    }
    for (RYGDownloadJob *j in toStart) {
        void (^s)(void) = j.startBlock;
        j.startBlock = nil;   // consume — never reused (a fresh task is built on retry)
        if (s) dispatch_async(dispatch_get_main_queue(), s);
    }
    [self notifyChange];
}

#pragma mark - Producer transitions

- (void)job:(RYGDownloadJob *)job didProgress:(float)progress stage:(NSString *)stage {
    [self job:job didProgress:progress received:0 total:0 stage:stage];
}

- (void)job:(RYGDownloadJob *)job didProgress:(float)progress
   received:(int64_t)received
      total:(int64_t)total
      stage:(NSString *)stage {
    if (!job || job.isTerminal) return;
    if (job.state == RYGDownloadJobStateQueued) job.state = RYGDownloadJobStateDownloading;
    job.progress = MAX(0.0f, MIN(progress, 1.0f));
    if (received > 0 || total > 0) [job noteReceived:received total:total];
    if (stage) job.stageText = stage;
    [self notifyChange];
}

- (void)job:(RYGDownloadJob *)job enterEncodingStage:(NSString *)stage {
    if (!job || job.isTerminal) return;
    job.state = RYGDownloadJobStateEncoding;
    if (stage) job.stageText = stage;
    [self notifyChange];
}

- (void)markJobFinished:(RYGDownloadJob *)job {
    if (!job || job.isTerminal) return;
    job.state = RYGDownloadJobStateFinished;
    job.progress = 1.0f;
    job.finishedAt = [NSDate date];
    job.stageText = RYGLocalized(@"Done");
    job.cancelBlock = nil;
    [self trimTerminal];
    [self persistHistory];
    [self pump];
}

- (void)markJob:(RYGDownloadJob *)job failedWithError:(NSError *)error {
    if (!job || job.isTerminal) return;

    if ([self shouldAutoRetryJob:job error:error]) {
        dispatch_block_t hold = ^{ [self holdJobForRetry:job]; };
        NSThread.isMainThread ? hold() : dispatch_async(dispatch_get_main_queue(), hold);
        return;
    }

    job.state = RYGDownloadJobStateFailed;
    job.error = error;
    job.finishedAt = [NSDate date];
    job.stageText = error.localizedDescription ?: RYGLocalized(@"Failed");
    job.cancelBlock = nil;
    [self trimTerminal];
    [self persistHistory];
    [self pump];
}

- (void)markJobCancelled:(RYGDownloadJob *)job {
    if (!job || job.isTerminal) return;
    job.state = RYGDownloadJobStateCancelled;
    job.finishedAt = [NSDate date];
    job.stageText = RYGLocalized(@"Cancelled");
    job.cancelBlock = nil;
    [self trimTerminal];
    [self persistHistory];
    [self pump];
}

#pragma mark - Auto-retry

- (BOOL)shouldAutoRetryJob:(RYGDownloadJob *)job error:(NSError *)error {
    if (!job.retryBlock) return NO;
    if (![RYGUtils getBoolPref:@"dl_auto_retry"]) return NO;
    NSInteger max = (NSInteger)llround([RYGUtils getDoublePref:@"dl_auto_retry_count"]);
    if (job.autoRetriesUsed >= MAX(0, max)) return NO;

    // Offline right now → always transient (covers ffmpeg mux failures whose error
    // isn't an NSURLError). It'll park in Waiting and resume on reconnect.
    if (![self networkReachable]) return YES;

    // Online but a known transient network blip.
    if (![error.domain isEqualToString:NSURLErrorDomain]) return NO;
    switch (error.code) {
        case NSURLErrorTimedOut:
        case NSURLErrorCannotConnectToHost:
        case NSURLErrorNetworkConnectionLost:
        case NSURLErrorNotConnectedToInternet:
        case NSURLErrorDNSLookupFailed:
        case NSURLErrorResourceUnavailable:
            return YES;
        default:
            return NO;
    }
}

// Park a transiently-failed job until it can sensibly retry: a short delay if the
// network is up (brief blip), or until reachability reports back online.
- (void)holdJobForRetry:(RYGDownloadJob *)job {
    if (!job || job.isTerminal || job.state == RYGDownloadJobStateWaiting) return;
    job.state = RYGDownloadJobStateWaiting;

    if ([self networkReachable]) {
        job.stageText = RYGLocalized(@"Retrying…");
        __weak typeof(self) weakSelf = self;
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(3.0 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
            if (job.state == RYGDownloadJobStateWaiting) [weakSelf autoRetryJob:job];
        });
    } else {
        job.stageText = RYGLocalized(@"Waiting for connection…");
        [self.waitingForNetwork addObject:job];
    }
    [self pump];   // Waiting isn't active — free the slot for queued downloads.
}

// Rebuild the job from scratch (fresh task/session), carrying the attempt count forward.
- (void)autoRetryJob:(RYGDownloadJob *)job {
    void (^rb)(void) = job.retryBlock;
    NSInteger next = job.autoRetriesUsed + 1;
    [self.waitingForNetwork removeObject:job];
    [self removeJob:job];
    self.pendingAutoRetryCount = next;
    if (rb) rb();
    self.pendingAutoRetryCount = 0;
}

#pragma mark - User actions

- (void)cancelJob:(RYGDownloadJob *)job {
    if (!job || job.isTerminal) return;
    void (^cb)(void) = job.cancelBlock;
    // Transition immediately so the UI flips now — async producers (ffmpeg mux)
    // may take a moment to actually stop; their later callback is a no-op once
    // the job is already terminal.
    [self markJobCancelled:job];
    if (cb) cb();
}

- (void)retryJob:(RYGDownloadJob *)job {
    if (!job) return;
    void (^rb)(void) = job.retryBlock;
    if (rb) {
        [self removeJob:job];
        rb();
        return;
    }
    // Restored from history — rebuild from the persisted inputs.
    NSDictionary *info = job.retryInfo;
    void (^builder)(NSDictionary *) = [RYGDownloadCenter retryBlockForInfo:info];
    if (!builder) return;
    [self removeJob:job];
    builder(info);
}

- (void)removeJob:(RYGDownloadJob *)job {
    if (!job) return;
    @synchronized (self.jobs) { [self.jobs removeObject:job]; }
    [self persistHistory];
    [self notifyChange];
}

- (void)clearFinished {
    @synchronized (self.jobs) {
        NSMutableArray *remove = [NSMutableArray array];
        for (RYGDownloadJob *j in self.jobs)
            if (j.state == RYGDownloadJobStateFinished) [remove addObject:j];
        [self.jobs removeObjectsInArray:remove];
    }
    [self persistHistory];
    [self notifyChange];
}

- (void)trimTerminal {
    @synchronized (self.jobs) {
        NSUInteger terminal = 0;
        for (RYGDownloadJob *j in self.jobs) if (j.isTerminal) terminal++;
        if (terminal <= kRYGMaxTerminalJobs) return;
        NSUInteger toDrop = terminal - kRYGMaxTerminalJobs;
        NSMutableArray *remove = [NSMutableArray array];
        for (RYGDownloadJob *j in self.jobs) {
            if (remove.count >= toDrop) break;
            if (j.isTerminal) [remove addObject:j];   // oldest terminal first (insertion order)
        }
        [self.jobs removeObjectsInArray:remove];
    }
}

#pragma mark - Reads

- (NSArray<RYGDownloadJob *> *)allJobs {
    @synchronized (self.jobs) { return [self.jobs copy]; }
}
- (NSInteger)activeCount {
    NSInteger n = 0;
    @synchronized (self.jobs) { for (RYGDownloadJob *j in self.jobs) if (j.isActive) n++; }
    return n;
}
- (BOOL)hasPendingWork {
    @synchronized (self.jobs) { for (RYGDownloadJob *j in self.jobs) if (!j.isTerminal) return YES; }
    return NO;
}
- (NSInteger)queuedCount {
    NSInteger n = 0;
    @synchronized (self.jobs) { for (RYGDownloadJob *j in self.jobs) if (j.state == RYGDownloadJobStateQueued) n++; }
    return n;
}

- (void)notifyChange {
    dispatch_block_t post = ^{
        [self refreshAggregate];
        // hasPendingWork, not activeCount — so a backgrounded retry-wait stays alive.
        [RYGBackgroundActivity setSource:@"downloads" active:[self hasPendingWork]];
        [[NSNotificationCenter defaultCenter] postNotificationName:RYGDownloadCenterDidChangeNotification object:self];
    };
    NSThread.isMainThread ? post() : dispatch_async(dispatch_get_main_queue(), post);
}

#pragma mark - Aggregate pill (main thread only)

// One pill represents the whole in-flight batch. It counts up as items resolve,
// then collapses into a single success/error summary when the batch empties.
- (void)refreshAggregate {
    NSString *batch;
    NSArray<RYGDownloadJob *> *batchJobs;
    @synchronized (self.jobs) {
        batch = self.currentBatchID;
        if (!batch) batchJobs = @[];
        else {
            NSMutableArray *m = [NSMutableArray array];
            for (RYGDownloadJob *j in self.jobs) if ([j.batchID isEqualToString:batch]) [m addObject:j];
            batchJobs = m;
        }
    }

    if (!batch || batchJobs.count == 0) {
        if (self.aggregateHandle && !self.aggregateHandle.isFinished) [self.aggregateHandle dismiss];
        self.aggregateHandle = nil;
        return;
    }

    NSUInteger jobCount = batchJobs.count, nonTerminal = 0;
    double weighted = 0.0, weightTotal = 0.0;
    BOOL hasContinuation = NO;
    RYGDownloadJob *soleActive = nil;
    for (RYGDownloadJob *j in batchJobs) {
        NSUInteger ic = j.itemCount ?: 1;
        weightTotal += ic;
        weighted += ic * (j.isTerminal ? 1.0f : j.progress);
        if (j.continuationPhase) hasContinuation = YES;
        if (!j.isTerminal) { nonTerminal++; soleActive = j; }
    }
    float overall = weightTotal > 0 ? (float)(weighted / weightTotal) : 0.0f;

    // Count items over the final-phase jobs if any, else every job.
    NSUInteger reportTotal = 0, reportDone = 0;
    for (RYGDownloadJob *j in batchJobs) {
        if (j.continuationPhase != hasContinuation) continue;
        NSUInteger ic = j.itemCount ?: 1;
        reportTotal += ic;
        float frac = j.isTerminal ? (j.state == RYGDownloadJobStateFinished ? 1.0f : 0.0f) : j.progress;
        reportDone += MIN(ic, (NSUInteger)lroundf(ic * frac));
    }

    if (nonTerminal == 0) {
        // Batch drained — hold the pill briefly so a quick follow-up download joins it.
        if (self.aggregateHandle) [self.aggregateHandle setProgress:1.0f];
        if (!self.finalizeScheduled) {
            self.finalizeScheduled = YES;
            __weak typeof(self) weakSelf = self;
            NSString *batchToken = batch;
            dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(kRYGBatchGrace * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
                [weakSelf finalizeBatchIfIdle:batchToken];
            });
        }
        return;
    }

    self.finalizeScheduled = NO;  // batch active again — cancel any pending finalize intent

    if (!self.aggregateHandle || self.aggregateHandle.isFinished) {
        __weak typeof(self) weakSelf = self;
        NSString *batchToken = batch;
        self.aggregateHandle = RYGNotifyProgress(RYG_NOTIF_DOWNLOAD,
                                                 RYGLocalized(@"Downloading…"),
                                                 ^{ [weakSelf cancelBatch:batchToken]; });
    }

    RYGNotificationHandle *h = self.aggregateHandle;
    if (jobCount == 1) {
        // Phase + percent, not the raw stage text ("Downloading video…" stays in the manager).
        int pct = (int)lroundf(overall * 100.0f);
        NSString *fmt = (soleActive.state == RYGDownloadJobStateEncoding)
            ? RYGLocalized(@"Encoding %d%%") : RYGLocalized(@"Downloading %d%%");
        [h setTitle:[NSString stringWithFormat:fmt, pct]];
        [h setSubtitle:nil];
    } else {
        [h setTitle:[NSString stringWithFormat:RYGLocalized(@"Downloading %lu items"), (unsigned long)reportTotal]];
        [h setSubtitle:[NSString stringWithFormat:RYGLocalized(@"%lu of %lu done"), (unsigned long)reportDone, (unsigned long)reportTotal]];
    }
    [h setProgress:overall];
}

- (void)cancelBatch:(NSString *)batchToken {
    NSArray<RYGDownloadJob *> *snapshot;
    @synchronized (self.jobs) { snapshot = [self.jobs copy]; }
    for (RYGDownloadJob *j in snapshot)
        if ([j.batchID isEqualToString:batchToken] && !j.isTerminal) [self cancelJob:j];
}

// Fires after the grace window. Summarizes only if the batch is still the current
// one and still fully drained; otherwise a follow-up download revived it.
- (void)finalizeBatchIfIdle:(NSString *)batchToken {
    self.finalizeScheduled = NO;

    NSArray<RYGDownloadJob *> *batchJobs;
    @synchronized (self.jobs) {
        if (![self.currentBatchID isEqualToString:batchToken]) return;  // already finalized
        NSMutableArray *m = [NSMutableArray array];
        for (RYGDownloadJob *j in self.jobs) if ([j.batchID isEqualToString:batchToken]) [m addObject:j];
        batchJobs = m;
    }

    NSUInteger jobCount = batchJobs.count;
    BOOL hasContinuation = NO;
    for (RYGDownloadJob *j in batchJobs) {
        if (!j.isTerminal) { [self refreshAggregate]; return; }  // revived
        if (j.continuationPhase) hasContinuation = YES;
    }

    NSUInteger itemsDone = 0, itemsFailed = 0;
    RYGDownloadJob *reportJob = nil;
    for (RYGDownloadJob *j in batchJobs) {
        if (j.continuationPhase != hasContinuation) continue;
        NSUInteger ic = j.itemCount ?: 1;
        if (j.state == RYGDownloadJobStateFinished) { itemsDone += ic; reportJob = j; }
        else if (j.state == RYGDownloadJobStateFailed) itemsFailed += ic;
    }

    RYGNotificationHandle *h = self.aggregateHandle;
    if (h && !h.isFinished) {
        if (itemsFailed > 0 && itemsDone > 0)
            [h error:[NSString stringWithFormat:RYGLocalized(@"%lu saved, %lu failed"), (unsigned long)itemsDone, (unsigned long)itemsFailed]];
        else if (itemsFailed > 0)
            [h error:[NSString stringWithFormat:RYGLocalized(@"%lu failed"), (unsigned long)itemsFailed]];
        else if (itemsDone == 0)
            [h cancelled:RYGLocalized(@"Cancelled")];
        else if (jobCount == 1)
            [h success:(batchJobs.firstObject.successText ?: RYGLocalized(@"Done"))];
        else
            [h success:(reportJob.successText ?: [NSString stringWithFormat:RYGLocalized(@"Downloaded %lu items"), (unsigned long)itemsDone])];
    }
    self.aggregateHandle = nil;
    @synchronized (self.jobs) { if ([self.currentBatchID isEqualToString:batchToken]) self.currentBatchID = nil; }
}

@end
