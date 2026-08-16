#import "RYGDownloadHistory.h"
#import "RYGDownloadCenter.h"
#import "RYGDownloadThumbs.h"
#import "../Utils.h"
#import <stdatomic.h>

static NSString *const kDir = @"RyukGram/DownloadHistory";
static NSString *const kFile = @"history.json";
static NSUInteger const kMaxRecords = 300;
static NSTimeInterval const kSaveDebounce = 0.6;

@implementation RYGDownloadHistory

static void *kQKey = &kQKey;
static dispatch_queue_t ioQ(void) {
	static dispatch_queue_t q; static dispatch_once_t once;
	dispatch_once(&once, ^{
		q = dispatch_queue_create("com.ryukgram.downloadhistory.io", DISPATCH_QUEUE_SERIAL);
		dispatch_queue_set_specific(q, kQKey, kQKey, NULL);
	});
	return q;
}

+ (NSString *)storageDirectory {
	NSString *root = NSSearchPathForDirectoriesInDomains(NSApplicationSupportDirectory, NSUserDomainMask, YES).firstObject;
	NSString *dir = [root stringByAppendingPathComponent:kDir];
	[NSFileManager.defaultManager createDirectoryAtPath:dir withIntermediateDirectories:YES attributes:nil error:nil];
	return dir;
}

+ (NSString *)historyFile { return [[self storageDirectory] stringByAppendingPathComponent:kFile]; }

+ (NSInteger)retentionHours {
	NSString *v = [RYGUtils getStringPref:@"dl_history_retention"];
	if ([v isEqualToString:@"off"]) return 0;
	if ([v isEqualToString:@"forever"]) return -1;
	NSInteger h = v.integerValue;
	return h > 0 ? h : 48;
}

+ (BOOL)job:(RYGDownloadJob *)job withinWindow:(NSInteger)hours now:(NSDate *)now {
	if (hours < 0) return YES;
	NSDate *stamp = job.finishedAt ?: job.createdAt;
	return [now timeIntervalSinceDate:stamp] <= (double)hours * 3600.0;
}

#pragma mark - Serialization

+ (NSDictionary *)dictFromJob:(RYGDownloadJob *)job {
	NSMutableDictionary *d = [NSMutableDictionary dictionary];
	d[@"id"] = job.jobID;
	d[@"state"] = @(job.state);
	d[@"mediaKind"] = @(job.mediaKind);
	d[@"kind"] = @(job.kind);
	d[@"createdAt"] = @(job.createdAt.timeIntervalSince1970);
	d[@"bytes"] = @(job.bytesExpected > 0 ? job.bytesExpected : job.bytesReceived);
	if (job.title) d[@"title"] = job.title;
	if (job.subtitle) d[@"subtitle"] = job.subtitle;
	if (job.successText) d[@"successText"] = job.successText;
	if (job.finishedAt) d[@"finishedAt"] = @(job.finishedAt.timeIntervalSince1970);
	if (job.resultFileURL.isFileURL) d[@"file"] = job.resultFileURL.path;
	if (job.error.localizedDescription) d[@"error"] = job.error.localizedDescription;
	// Non-JSON retryInfo would poison the whole file on write.
	if (job.retryInfo && [NSJSONSerialization isValidJSONObject:job.retryInfo]) d[@"retry"] = job.retryInfo;
	return d;
}

+ (RYGDownloadJob *)jobFromDict:(NSDictionary *)d {
	if (![d isKindOfClass:NSDictionary.class]) return nil;
	NSNumber *state = d[@"state"];
	if (![state isKindOfClass:NSNumber.class]) return nil;

	NSString *jobID = [d[@"id"] isKindOfClass:NSString.class] ? d[@"id"] : nil;
	RYGDownloadJob *job = [[RYGDownloadJob alloc] initWithJobID:jobID];
	job.state = (RYGDownloadJobState)state.integerValue;
	if (!job.isTerminal) return nil;

	job.title = d[@"title"] ?: RYGLocalized(@"Download");
	job.subtitle = d[@"subtitle"];
	job.successText = d[@"successText"];
	job.mediaKind = (RYGDownloadMediaKind)[d[@"mediaKind"] integerValue];
	job.kind = (RYGDownloadJobKind)[d[@"kind"] integerValue];
	job.bytesExpected = [d[@"bytes"] longLongValue];
	job.progress = (job.state == RYGDownloadJobStateFinished) ? 1.0f : 0.0f;

	NSNumber *created = d[@"createdAt"];
	if ([created isKindOfClass:NSNumber.class]) job.createdAt = [NSDate dateWithTimeIntervalSince1970:created.doubleValue];
	NSNumber *finished = d[@"finishedAt"];
	if ([finished isKindOfClass:NSNumber.class]) job.finishedAt = [NSDate dateWithTimeIntervalSince1970:finished.doubleValue];

	// HD output is a 15-min scratch file and plain output lives in Caches, so by
	// now it's usually gone — a dead URL would offer Preview/Share on nothing.
	NSString *path = d[@"file"];
	if ([path isKindOfClass:NSString.class] && path.length && [NSFileManager.defaultManager fileExistsAtPath:path])
		job.resultFileURL = [NSURL fileURLWithPath:path];

	NSDictionary *retry = d[@"retry"];
	if ([retry isKindOfClass:NSDictionary.class]) job.retryInfo = retry;

	NSString *err = d[@"error"];
	if ([err isKindOfClass:NSString.class] && err.length)
		job.error = [NSError errorWithDomain:@"RYGDownloadHistory" code:0
		                            userInfo:@{ NSLocalizedDescriptionKey: err }];
	return job;
}

#pragma mark - Load / save

+ (NSArray<RYGDownloadJob *> *)loadJobs {
	NSInteger hours = [self retentionHours];
	if (hours == 0) { [self resetAll]; return @[]; }


	__block NSArray *raw = nil;
	dispatch_sync(ioQ(), ^{
		NSData *data = [NSData dataWithContentsOfFile:[self historyFile]];
		if (!data.length) return;
		id parsed = [NSJSONSerialization JSONObjectWithData:data options:0 error:nil];
		if ([parsed isKindOfClass:NSArray.class]) raw = parsed;
	});

	NSDate *now = [NSDate date];
	NSMutableArray<RYGDownloadJob *> *jobs = [NSMutableArray array];
	for (NSDictionary *d in raw) {
		RYGDownloadJob *job = [self jobFromDict:d];
		if (job && [self job:job withinWindow:hours now:now]) [jobs addObject:job];
	}
	[jobs sortUsingComparator:^NSComparisonResult(RYGDownloadJob *a, RYGDownloadJob *b) {
		return [(a.finishedAt ?: a.createdAt) compare:(b.finishedAt ?: b.createdAt)];
	}];
	if (jobs.count > kMaxRecords) [jobs removeObjectsInRange:NSMakeRange(0, jobs.count - kMaxRecords)];
	return jobs;
}

// Coalesced — a burst of finishing jobs would rewrite the file per job.
+ (void)saveJobs:(NSArray<RYGDownloadJob *> *)jobs {
	NSMutableSet<NSString *> *live = [NSMutableSet set];
	for (RYGDownloadJob *j in jobs) [live addObject:j.jobID];
	[RYGDownloadThumbs pruneKeepingJobIDs:live];

	NSInteger hours = [self retentionHours];
	if (hours == 0) { [self removeHistoryFile]; return; }

	NSDate *now = [NSDate date];
	NSMutableArray<NSDictionary *> *records = [NSMutableArray array];
	for (RYGDownloadJob *j in jobs) {
		if (!j.isTerminal) continue;
		if (![self job:j withinWindow:hours now:now]) continue;
		[records addObject:[self dictFromJob:j]];
	}
	if (records.count > kMaxRecords) [records removeObjectsInRange:NSMakeRange(0, records.count - kMaxRecords)];

	static _Atomic(uint64_t) generation = 0;
	uint64_t mine = atomic_fetch_add(&generation, 1) + 1;
	dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(kSaveDebounce * NSEC_PER_SEC)), ioQ(), ^{
		if (atomic_load(&generation) != mine) return;   // a newer snapshot superseded this one
		NSData *data = [NSJSONSerialization dataWithJSONObject:records options:0 error:nil];
		if (data) [data writeToFile:[self historyFile] atomically:YES];
	});
}

+ (void)removeHistoryFile {
	dispatch_sync(ioQ(), ^{
		[NSFileManager.defaultManager removeItemAtPath:[self historyFile] error:nil];
	});
}

+ (void)resetAll {
	[self removeHistoryFile];
	[RYGDownloadThumbs removeAll];
}

@end
