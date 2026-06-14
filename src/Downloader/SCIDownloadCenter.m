#import "SCIDownloadCenter.h"
#import "../Utils.h"
#import "../Background/SCIBackgroundActivity.h"
#import <SystemConfiguration/SystemConfiguration.h>
#import <netinet/in.h>

NSString *const SCIDownloadCenterDidChangeNotification = @"SCIDownloadCenterDidChangeNotification";

// Keep terminal jobs around for the manager UI, but don't grow forever.
static const NSUInteger kSCIMaxTerminalJobs = 100;

@interface SCIDownloadJob ()
@property (nonatomic, copy, nullable) NSString *batchID;
@end

@implementation SCIDownloadJob
- (instancetype)init {
    self = [super init];
    if (self) {
        _jobID = [NSUUID.UUID.UUIDString copy];
        _createdAt = [NSDate date];
        _state = SCIDownloadJobStateQueued;
        _progress = 0.0f;
    }
    return self;
}
- (BOOL)isActive {
    return _state == SCIDownloadJobStateDownloading || _state == SCIDownloadJobStateEncoding;
}
- (BOOL)isTerminal {
    return _state == SCIDownloadJobStateFinished
        || _state == SCIDownloadJobStateFailed
        || _state == SCIDownloadJobStateCancelled;
}
@end

// Grace window: keep a drained batch open briefly so a closely-following download
// joins the same pill instead of spawning a fresh one.
static const NSTimeInterval kSCIBatchGrace = 0.7;

@interface SCIDownloadCenter ()
@property (nonatomic, strong) NSMutableArray<SCIDownloadJob *> *jobs;
@property (nonatomic, copy, nullable) NSString *currentBatchID;     // guarded by @synchronized(jobs)
@property (nonatomic, strong, nullable) SCINotificationHandle *aggregateHandle;  // main thread only
@property (nonatomic, assign) BOOL finalizeScheduled;              // main thread only
@property (nonatomic, assign) NSInteger pendingAutoRetryCount;     // carried into the next enqueue
@property (nonatomic, strong) NSMutableArray<SCIDownloadJob *> *waitingForNetwork;  // main thread only
- (BOOL)hasPendingWork;
@end

@implementation SCIDownloadCenter {
    SCNetworkReachabilityRef _reachRef;
}

+ (instancetype)shared {
    static SCIDownloadCenter *shared;
    static dispatch_once_t once;
    dispatch_once(&once, ^{ shared = [SCIDownloadCenter new]; });
    return shared;
}

- (instancetype)init {
    self = [super init];
    if (self) {
        _jobs = [NSMutableArray new];
        _waitingForNetwork = [NSMutableArray new];
        [self startReachability];
    }
    return self;
}

#pragma mark - Reachability

static void sciReachabilityCallback(SCNetworkReachabilityRef target, SCNetworkReachabilityFlags flags, void *info) {
    (void)target;
    BOOL up = (flags & kSCNetworkReachabilityFlagsReachable) && !(flags & kSCNetworkReachabilityFlagsConnectionRequired);
    [(__bridge SCIDownloadCenter *)info networkBecameReachable:up];
}

- (void)startReachability {
    struct sockaddr_in zero;
    bzero(&zero, sizeof(zero));
    zero.sin_len = sizeof(zero);
    zero.sin_family = AF_INET;
    _reachRef = SCNetworkReachabilityCreateWithAddress(NULL, (const struct sockaddr *)&zero);
    if (!_reachRef) return;
    SCNetworkReachabilityContext ctx = { 0, (__bridge void *)self, NULL, NULL, NULL };
    SCNetworkReachabilitySetCallback(_reachRef, sciReachabilityCallback, &ctx);
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
    NSArray<SCIDownloadJob *> *pending = [self.waitingForNetwork copy];
    [self.waitingForNetwork removeAllObjects];
    for (SCIDownloadJob *j in pending)
        if (j.state == SCIDownloadJobStateWaiting) [self autoRetryJob:j];
}

- (NSInteger)maxConcurrent {
    NSInteger n = (NSInteger)llround([SCIUtils getDoublePref:@"dl_max_concurrent"]);
    return MIN(6, MAX(1, n));
}

#pragma mark - Enqueue

- (SCIDownloadJob *)enqueueJobWithTitle:(NSString *)title
                                   kind:(SCIDownloadJobKind)kind
                                  start:(void (^)(void))start
                                 cancel:(void (^)(void))cancel {
    SCIDownloadJob *job = [SCIDownloadJob new];
    job.title = title ?: SCILocalized(@"Downloading…");
    job.kind = kind;
    job.startBlock = [start copy];
    job.cancelBlock = [cancel copy];
    job.stageText = SCILocalized(@"Queued");
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
    NSMutableArray<SCIDownloadJob *> *toStart = [NSMutableArray array];
    @synchronized (self.jobs) {
        NSInteger active = 0;
        for (SCIDownloadJob *j in self.jobs) if (j.isActive) active++;
        NSInteger max = self.maxConcurrent;
        for (SCIDownloadJob *j in self.jobs) {
            if (active >= max) break;
            if (j.state != SCIDownloadJobStateQueued) continue;
            j.state = SCIDownloadJobStateDownloading;
            j.stageText = SCILocalized(@"Starting…");
            [toStart addObject:j];
            active++;
        }
    }
    for (SCIDownloadJob *j in toStart) {
        void (^s)(void) = j.startBlock;
        j.startBlock = nil;   // consume — never reused (a fresh task is built on retry)
        if (s) dispatch_async(dispatch_get_main_queue(), s);
    }
    [self notifyChange];
}

#pragma mark - Producer transitions

- (void)job:(SCIDownloadJob *)job didProgress:(float)progress stage:(NSString *)stage {
    if (!job || job.isTerminal) return;
    if (job.state == SCIDownloadJobStateQueued) job.state = SCIDownloadJobStateDownloading;
    job.progress = MAX(0.0f, MIN(progress, 1.0f));
    if (stage) job.stageText = stage;
    [self notifyChange];
}

- (void)job:(SCIDownloadJob *)job enterEncodingStage:(NSString *)stage {
    if (!job || job.isTerminal) return;
    job.state = SCIDownloadJobStateEncoding;
    if (stage) job.stageText = stage;
    [self notifyChange];
}

- (void)markJobFinished:(SCIDownloadJob *)job {
    if (!job || job.isTerminal) return;
    job.state = SCIDownloadJobStateFinished;
    job.progress = 1.0f;
    job.finishedAt = [NSDate date];
    job.stageText = SCILocalized(@"Done");
    job.cancelBlock = nil;
    [self trimTerminal];
    [self pump];
}

- (void)markJob:(SCIDownloadJob *)job failedWithError:(NSError *)error {
    if (!job || job.isTerminal) return;

    if ([self shouldAutoRetryJob:job error:error]) {
        dispatch_block_t hold = ^{ [self holdJobForRetry:job]; };
        NSThread.isMainThread ? hold() : dispatch_async(dispatch_get_main_queue(), hold);
        return;
    }

    job.state = SCIDownloadJobStateFailed;
    job.error = error;
    job.finishedAt = [NSDate date];
    job.stageText = error.localizedDescription ?: SCILocalized(@"Failed");
    job.cancelBlock = nil;
    [self trimTerminal];
    [self pump];
}

- (void)markJobCancelled:(SCIDownloadJob *)job {
    if (!job || job.isTerminal) return;
    job.state = SCIDownloadJobStateCancelled;
    job.finishedAt = [NSDate date];
    job.stageText = SCILocalized(@"Cancelled");
    job.cancelBlock = nil;
    [self trimTerminal];
    [self pump];
}

#pragma mark - Auto-retry

- (BOOL)shouldAutoRetryJob:(SCIDownloadJob *)job error:(NSError *)error {
    if (!job.retryBlock) return NO;
    if (![SCIUtils getBoolPref:@"dl_auto_retry"]) return NO;
    NSInteger max = (NSInteger)llround([SCIUtils getDoublePref:@"dl_auto_retry_count"]);
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
- (void)holdJobForRetry:(SCIDownloadJob *)job {
    if (!job || job.isTerminal || job.state == SCIDownloadJobStateWaiting) return;
    job.state = SCIDownloadJobStateWaiting;

    if ([self networkReachable]) {
        job.stageText = SCILocalized(@"Retrying…");
        __weak typeof(self) weakSelf = self;
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(3.0 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
            if (job.state == SCIDownloadJobStateWaiting) [weakSelf autoRetryJob:job];
        });
    } else {
        job.stageText = SCILocalized(@"Waiting for connection…");
        [self.waitingForNetwork addObject:job];
    }
    [self pump];   // Waiting isn't active — free the slot for queued downloads.
}

// Rebuild the job from scratch (fresh task/session), carrying the attempt count forward.
- (void)autoRetryJob:(SCIDownloadJob *)job {
    void (^rb)(void) = job.retryBlock;
    NSInteger next = job.autoRetriesUsed + 1;
    [self.waitingForNetwork removeObject:job];
    [self removeJob:job];
    self.pendingAutoRetryCount = next;
    if (rb) rb();
    self.pendingAutoRetryCount = 0;
}

#pragma mark - User actions

- (void)cancelJob:(SCIDownloadJob *)job {
    if (!job || job.isTerminal) return;
    void (^cb)(void) = job.cancelBlock;
    // Transition immediately so the UI flips now — async producers (ffmpeg mux)
    // may take a moment to actually stop; their later callback is a no-op once
    // the job is already terminal.
    [self markJobCancelled:job];
    if (cb) cb();
}

- (void)retryJob:(SCIDownloadJob *)job {
    if (!job) return;
    void (^rb)(void) = job.retryBlock;
    if (!rb) return;
    [self removeJob:job];
    rb();
}

- (void)removeJob:(SCIDownloadJob *)job {
    if (!job) return;
    @synchronized (self.jobs) { [self.jobs removeObject:job]; }
    [self notifyChange];
}

- (void)clearFinished {
    @synchronized (self.jobs) {
        NSMutableArray *remove = [NSMutableArray array];
        for (SCIDownloadJob *j in self.jobs)
            if (j.state == SCIDownloadJobStateFinished) [remove addObject:j];
        [self.jobs removeObjectsInArray:remove];
    }
    [self notifyChange];
}

- (void)trimTerminal {
    @synchronized (self.jobs) {
        NSUInteger terminal = 0;
        for (SCIDownloadJob *j in self.jobs) if (j.isTerminal) terminal++;
        if (terminal <= kSCIMaxTerminalJobs) return;
        NSUInteger toDrop = terminal - kSCIMaxTerminalJobs;
        NSMutableArray *remove = [NSMutableArray array];
        for (SCIDownloadJob *j in self.jobs) {
            if (remove.count >= toDrop) break;
            if (j.isTerminal) [remove addObject:j];   // oldest terminal first (insertion order)
        }
        [self.jobs removeObjectsInArray:remove];
    }
}

#pragma mark - Reads

- (NSArray<SCIDownloadJob *> *)allJobs {
    @synchronized (self.jobs) { return [self.jobs copy]; }
}
- (NSInteger)activeCount {
    NSInteger n = 0;
    @synchronized (self.jobs) { for (SCIDownloadJob *j in self.jobs) if (j.isActive) n++; }
    return n;
}
- (BOOL)hasPendingWork {
    @synchronized (self.jobs) { for (SCIDownloadJob *j in self.jobs) if (!j.isTerminal) return YES; }
    return NO;
}
- (NSInteger)queuedCount {
    NSInteger n = 0;
    @synchronized (self.jobs) { for (SCIDownloadJob *j in self.jobs) if (j.state == SCIDownloadJobStateQueued) n++; }
    return n;
}

- (void)notifyChange {
    dispatch_block_t post = ^{
        [self refreshAggregate];
        // hasPendingWork, not activeCount — so a backgrounded retry-wait stays alive.
        [SCIBackgroundActivity setSource:@"downloads" active:[self hasPendingWork]];
        [[NSNotificationCenter defaultCenter] postNotificationName:SCIDownloadCenterDidChangeNotification object:self];
    };
    NSThread.isMainThread ? post() : dispatch_async(dispatch_get_main_queue(), post);
}

#pragma mark - Aggregate pill (main thread only)

// One pill represents the whole in-flight batch. It counts up as items resolve,
// then collapses into a single success/error summary when the batch empties.
- (void)refreshAggregate {
    NSString *batch;
    NSArray<SCIDownloadJob *> *batchJobs;
    @synchronized (self.jobs) {
        batch = self.currentBatchID;
        if (!batch) batchJobs = @[];
        else {
            NSMutableArray *m = [NSMutableArray array];
            for (SCIDownloadJob *j in self.jobs) if ([j.batchID isEqualToString:batch]) [m addObject:j];
            batchJobs = m;
        }
    }

    if (!batch || batchJobs.count == 0) {
        if (self.aggregateHandle && !self.aggregateHandle.isFinished) [self.aggregateHandle dismiss];
        self.aggregateHandle = nil;
        return;
    }

    NSUInteger total = batchJobs.count, done = 0, nonTerminal = 0;
    float effective = 0.0f;
    SCIDownloadJob *soleActive = nil;
    for (SCIDownloadJob *j in batchJobs) {
        switch (j.state) {
            case SCIDownloadJobStateFinished:  done++; effective += 1.0f; break;
            case SCIDownloadJobStateFailed:           effective += 1.0f; break;
            case SCIDownloadJobStateCancelled:        effective += 1.0f; break;
            default:                           nonTerminal++; effective += j.progress; soleActive = j; break;
        }
    }
    float overall = total ? effective / (float)total : 0.0f;

    if (nonTerminal == 0) {
        // Batch drained — hold the pill briefly so a quick follow-up download joins it.
        if (self.aggregateHandle) [self.aggregateHandle setProgress:1.0f];
        if (!self.finalizeScheduled) {
            self.finalizeScheduled = YES;
            __weak typeof(self) weakSelf = self;
            NSString *batchToken = batch;
            dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(kSCIBatchGrace * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
                [weakSelf finalizeBatchIfIdle:batchToken];
            });
        }
        return;
    }

    self.finalizeScheduled = NO;  // batch active again — cancel any pending finalize intent

    if (!self.aggregateHandle || self.aggregateHandle.isFinished) {
        __weak typeof(self) weakSelf = self;
        NSString *batchToken = batch;
        self.aggregateHandle = SCINotifyProgress(SCI_NOTIF_DOWNLOAD,
                                                 SCILocalized(@"Downloading…"),
                                                 ^{ [weakSelf cancelBatch:batchToken]; });
    }

    SCINotificationHandle *h = self.aggregateHandle;
    if (total == 1) {
        // Phase + percent, not the raw stage text ("Downloading video…" stays in the manager).
        int pct = (int)lroundf(overall * 100.0f);
        NSString *fmt = (soleActive.state == SCIDownloadJobStateEncoding)
            ? SCILocalized(@"Encoding %d%%") : SCILocalized(@"Downloading %d%%");
        [h setTitle:[NSString stringWithFormat:fmt, pct]];
        [h setSubtitle:nil];
    } else {
        [h setTitle:[NSString stringWithFormat:SCILocalized(@"Downloading %lu items"), (unsigned long)nonTerminal]];
        [h setSubtitle:[NSString stringWithFormat:SCILocalized(@"%lu of %lu done"), (unsigned long)done, (unsigned long)total]];
    }
    [h setProgress:overall];
}

- (void)cancelBatch:(NSString *)batchToken {
    NSArray<SCIDownloadJob *> *snapshot;
    @synchronized (self.jobs) { snapshot = [self.jobs copy]; }
    for (SCIDownloadJob *j in snapshot)
        if ([j.batchID isEqualToString:batchToken] && !j.isTerminal) [self cancelJob:j];
}

// Fires after the grace window. Summarizes only if the batch is still the current
// one and still fully drained; otherwise a follow-up download revived it.
- (void)finalizeBatchIfIdle:(NSString *)batchToken {
    self.finalizeScheduled = NO;

    NSArray<SCIDownloadJob *> *batchJobs;
    @synchronized (self.jobs) {
        if (![self.currentBatchID isEqualToString:batchToken]) return;  // already finalized
        NSMutableArray *m = [NSMutableArray array];
        for (SCIDownloadJob *j in self.jobs) if ([j.batchID isEqualToString:batchToken]) [m addObject:j];
        batchJobs = m;
    }

    NSUInteger total = batchJobs.count, done = 0, failed = 0;
    for (SCIDownloadJob *j in batchJobs) {
        if (!j.isTerminal) { [self refreshAggregate]; return; }  // revived
        if (j.state == SCIDownloadJobStateFinished) done++;
        else if (j.state == SCIDownloadJobStateFailed) failed++;
    }

    SCINotificationHandle *h = self.aggregateHandle;
    if (h && !h.isFinished) {
        if (failed > 0 && done > 0)
            [h error:[NSString stringWithFormat:SCILocalized(@"%lu saved, %lu failed"), (unsigned long)done, (unsigned long)failed]];
        else if (failed > 0)
            [h error:[NSString stringWithFormat:SCILocalized(@"%lu failed"), (unsigned long)failed]];
        else if (done == 0)
            [h cancelled:SCILocalized(@"Cancelled")];
        else if (total == 1)
            [h success:(batchJobs.firstObject.successText ?: SCILocalized(@"Done"))];
        else
            [h success:[NSString stringWithFormat:SCILocalized(@"Downloaded %lu items"), (unsigned long)done]];
    }
    self.aggregateHandle = nil;
    @synchronized (self.jobs) { if ([self.currentBatchID isEqualToString:batchToken]) self.currentBatchID = nil; }
}

@end
