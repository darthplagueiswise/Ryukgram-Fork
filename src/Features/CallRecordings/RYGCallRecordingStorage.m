#import "RYGCallRecordingStorage.h"

NSNotificationName const RYGCallRecordingsDidChangeNotification = @"RYGCallRecordingsDidChangeNotification";

static NSString *const kDir = @"RyukGram/CallRecordings";
static NSString *const kMediaDir = @"media";

@implementation RYGCallRecordingStorage

static void *kQKey = &kQKey;

static dispatch_queue_t q(void) {
	static dispatch_queue_t queue;
	static dispatch_once_t once;
	dispatch_once(&once, ^{
		queue = dispatch_queue_create("com.ryukgram.callrecordings.io", DISPATCH_QUEUE_SERIAL);
		dispatch_queue_set_specific(queue, kQKey, kQKey, NULL);
	});
	return queue;
}

static void sync_(dispatch_block_t b) {
	dispatch_get_specific(kQKey) ? b() : dispatch_sync(q(), b);
}

static NSFileManager *fm(void) { return NSFileManager.defaultManager; }

static NSString *clean(NSString *s, NSString *fallback) {
	if (!s.length) return fallback;
	NSMutableString *m = s.mutableCopy;
	NSCharacterSet *bad = [NSCharacterSet characterSetWithCharactersInString:@"/\\:?%*|\"<>"];
	for (NSUInteger i = 0; i < m.length; i++) {
		unichar c = [m characterAtIndex:i];
		if (c < 32 || [bad characterIsMember:c]) [m replaceCharactersInRange:NSMakeRange(i, 1) withString:@"_"];
	}
	return m.length ? m : fallback;
}

static NSString *dir(NSString *tail) {
	NSString *root = NSSearchPathForDirectoriesInDomains(NSApplicationSupportDirectory, NSUserDomainMask, YES).firstObject;
	NSString *d = [[root stringByAppendingPathComponent:kDir] stringByAppendingPathComponent:(tail ?: @"")];
	[fm() createDirectoryAtPath:d withIntermediateDirectories:YES attributes:nil error:nil];
	return d;
}

static NSString *owner(NSString *pk) { return clean(pk, @"anon"); }
static NSString *storeDir(void) { return dir(nil); }
static NSString *mediaDir(NSString *o) { return dir([kMediaDir stringByAppendingPathComponent:owner(o)]); }
static NSString *jsonPath(NSString *o) { return [storeDir() stringByAppendingPathComponent:[owner(o) stringByAppendingString:@".json"]]; }
static NSString *statePath(NSString *o) { return [storeDir() stringByAppendingPathComponent:[owner(o) stringByAppendingString:@".state.json"]]; }
static NSString *customNameForKey(NSString *o, NSString *field, NSString *key);
static NSMutableDictionary *readState(NSString *o);
static void writeState(NSString *o, NSDictionary *state);
static NSTimeInterval seenThresholdForGroup(NSDictionary *st, NSString *key);

+ (NSString *)storageDirectory { return storeDir(); }

static void post(NSString *o) {
	dispatch_async(dispatch_get_main_queue(), ^{
		[NSNotificationCenter.defaultCenter postNotificationName:RYGCallRecordingsDidChangeNotification
														  object:nil
														userInfo:o.length ? @{@"owner_pk": o} : @{}];
	});
}

static NSArray<RYGCallRecording *> *readAll(NSString *o) {
	NSData *data = [NSData dataWithContentsOfFile:jsonPath(o)];
	if (!data.length) return @[];
	id raw = [NSJSONSerialization JSONObjectWithData:data options:0 error:nil];
	if (![raw isKindOfClass:NSArray.class]) return @[];
	NSMutableArray *out = [NSMutableArray arrayWithCapacity:[raw count]];
	for (id d in (NSArray *)raw) {
		RYGCallRecording *m = [RYGCallRecording recordingFromJSONDict:d];
		if (m) [out addObject:m];
	}
	return out;
}

static BOOL writeAll(NSString *o, NSArray<RYGCallRecording *> *list) {
	NSMutableArray *raw = [NSMutableArray arrayWithCapacity:list.count];
	for (RYGCallRecording *m in list) {
		NSDictionary *d = [m toJSONDict];
		if (d) [raw addObject:d];
	}
	NSData *data = [NSJSONSerialization dataWithJSONObject:raw options:0 error:nil];
	return data.length && [data writeToFile:jsonPath(o) atomically:YES];
}

static void sortByDate(NSMutableArray<RYGCallRecording *> *a) {
	[a sortUsingComparator:^NSComparisonResult(RYGCallRecording *x, RYGCallRecording *y) {
		return [(y.startedAt ?: NSDate.distantPast) compare:(x.startedAt ?: NSDate.distantPast)];
	}];
}

static NSString *absPath(NSString *rel, NSString *o) {
	return rel.length ? [mediaDir(o) stringByAppendingPathComponent:rel.lastPathComponent] : nil;
}

static void removeFile(RYGCallRecording *m, NSString *o) {
	NSString *p = absPath(m.mediaPath, o);
	if (p.length) [fm() removeItemAtPath:p error:nil];
}

static BOOL rewrite(NSString *o, void (^mutate)(NSMutableArray<RYGCallRecording *> *list, BOOL *changed)) {
	__block BOOL changed = NO, ok = NO;
	sync_(^{
		NSMutableArray *list = [readAll(o) mutableCopy];
		mutate(list, &changed);
		if (changed) ok = writeAll(o, list);
	});
	if (ok) post(o);
	return ok;
}

static NSString *groupKey(RYGCallRecording *m) {
	if (m.threadId.length) return [@"t:" stringByAppendingString:m.threadId];
	if (m.peerPk.length) return [@"s:" stringByAppendingString:m.peerPk];
	if (m.isGroup && m.threadTitle.length) return [@"g:" stringByAppendingString:m.threadTitle];
	return @"uncategorized";   // no identity → a single catch-all bucket, never lost
}

#pragma mark - Read

+ (NSArray<RYGCallRecording *> *)allRecordingsForOwnerPK:(NSString *)ownerPK {
	__block NSArray *out = nil;
	sync_(^{ out = readAll(ownerPK); });
	return out ?: @[];
}

+ (NSArray<RYGCallRecording *> *)recordingsForIdentifier:(NSString *)identifier ownerPK:(NSString *)ownerPK {
	if (!identifier.length) return @[];
	__block NSMutableArray *out = nil;
	sync_(^{
		out = [NSMutableArray array];
		for (RYGCallRecording *m in readAll(ownerPK)) {
			if ([groupKey(m) isEqualToString:identifier]) {
				m.customName = customNameForKey(ownerPK, @"recordingNames", m.recordingId);
				[out addObject:m];
			}
		}
	});
	return out ?: @[];
}

+ (NSArray<RYGCallRecordingGroup *> *)groupedForOwnerPK:(NSString *)ownerPK {
	__block NSArray *result = nil;
	sync_(^{
		NSMutableDictionary<NSString *, NSMutableArray *> *map = [NSMutableDictionary dictionary];
		NSMutableArray<NSString *> *order = [NSMutableArray array];
		for (RYGCallRecording *m in readAll(ownerPK)) {
			NSString *key = groupKey(m);
			if (!key) continue;
			if (!map[key]) { map[key] = [NSMutableArray array]; [order addObject:key]; }
			[map[key] addObject:m];
		}

		NSMutableDictionary *st = readState(ownerPK);
		NSMutableArray *groups = [NSMutableArray arrayWithCapacity:map.count];
		for (NSString *key in order) {
			NSArray<RYGCallRecording *> *recs = map[key];
			RYGCallRecording *latest = recs.firstObject;
			if (!latest) continue;

			RYGCallRecordingGroup *g = [RYGCallRecordingGroup new];
			g.identifier = key;
			NSTimeInterval thr = seenThresholdForGroup(st, key);
			NSUInteger uc = 0;
			for (RYGCallRecording *m in recs) if ([(m.startedAt ?: NSDate.distantPast) timeIntervalSince1970] > thr) uc++;
			g.unreadCount = uc;
			g.customName = customNameForKey(ownerPK, @"groupNames", key);
			g.threadId = latest.threadId;
			g.isGroup = latest.isGroup;
			g.threadTitle = latest.threadTitle;
			g.threadAvatarURL = latest.threadAvatarURL;
			g.peerPk = latest.peerPk;
			g.peerUsername = latest.peerUsername;
			g.peerFullName = latest.peerFullName;
			g.peerProfilePicURL = latest.peerProfilePicURL;
			g.recordings = recs;
			[groups addObject:g];
		}

		[groups sortUsingComparator:^NSComparisonResult(RYGCallRecordingGroup *a, RYGCallRecordingGroup *b) {
			return [(b.lastRecordedAt ?: NSDate.distantPast) compare:(a.lastRecordedAt ?: NSDate.distantPast)];
		}];
		result = groups;
	});
	return result ?: @[];
}

#pragma mark - Write

+ (BOOL)saveRecording:(RYGCallRecording *)recording forOwnerPK:(NSString *)ownerPK {
	if (!recording.recordingId.length) return NO;
	return rewrite(ownerPK, ^(NSMutableArray<RYGCallRecording *> *list, BOOL *changed) {
		NSIndexSet *dupes = [list indexesOfObjectsPassingTest:^BOOL(RYGCallRecording *m, NSUInteger idx, BOOL *stop) {
			return [m.recordingId isEqualToString:recording.recordingId];
		}];
		if (dupes.count) [list removeObjectsAtIndexes:dupes];
		[list addObject:recording];
		sortByDate(list);
		*changed = YES;
	});
}

+ (void)deleteRecordingId:(NSString *)recordingId forOwnerPK:(NSString *)ownerPK {
	if (!recordingId.length) return;
	rewrite(ownerPK, ^(NSMutableArray<RYGCallRecording *> *list, BOOL *changed) {
		for (NSInteger i = (NSInteger)list.count - 1; i >= 0; i--) {
			RYGCallRecording *m = list[i];
			if (![m.recordingId isEqualToString:recordingId]) continue;
			removeFile(m, ownerPK);
			[list removeObjectAtIndex:(NSUInteger)i];
			*changed = YES;
		}
	});
}

+ (void)deleteRecordingsForIdentifier:(NSString *)identifier ownerPK:(NSString *)ownerPK {
	if (!identifier.length) return;
	rewrite(ownerPK, ^(NSMutableArray<RYGCallRecording *> *list, BOOL *changed) {
		for (NSInteger i = (NSInteger)list.count - 1; i >= 0; i--) {
			RYGCallRecording *m = list[i];
			if (![groupKey(m) isEqualToString:identifier]) continue;
			removeFile(m, ownerPK);
			[list removeObjectAtIndex:(NSUInteger)i];
			*changed = YES;
		}
	});
}

+ (void)resetForOwnerPK:(NSString *)ownerPK {
	__block BOOL changed = NO;
	sync_(^{
		NSString *json = jsonPath(ownerPK), *media = mediaDir(ownerPK);
		changed = [fm() fileExistsAtPath:json] || [fm() fileExistsAtPath:media];
		[fm() removeItemAtPath:json error:nil];
		[fm() removeItemAtPath:media error:nil];
	});
	if (changed) post(ownerPK);
}

+ (void)resetAll {
	__block BOOL changed = NO;
	sync_(^{
		NSString *d = storeDir();
		changed = [fm() fileExistsAtPath:d];
		[fm() removeItemAtPath:d error:nil];
	});
	if (changed) post(nil);
}

#pragma mark - Backup merge

+ (void)mergeImportedStoreAtPath:(NSString *)importedDir {
	BOOL isDir = NO;
	if (!importedDir.length || ![fm() fileExistsAtPath:importedDir isDirectory:&isDir] || !isDir) return;
	NSArray *names = [fm() contentsOfDirectoryAtPath:importedDir error:nil] ?: @[];
	__block BOOL changed = NO;

	sync_(^{
		for (NSString *name in names) {
			if (![name hasSuffix:@".json"]) continue;
			NSString *o = [name substringToIndex:name.length - @".json".length];
			NSData *data = [NSData dataWithContentsOfFile:[importedDir stringByAppendingPathComponent:name]];
			id raw = data.length ? [NSJSONSerialization JSONObjectWithData:data options:0 error:nil] : nil;
			if (![raw isKindOfClass:NSArray.class]) continue;

			NSMutableArray *list = [readAll(o) mutableCopy];
			NSMutableSet *seen = [NSMutableSet set];
			for (RYGCallRecording *m in list) if (m.recordingId.length) [seen addObject:m.recordingId];

			BOOL added = NO;
			for (id d in (NSArray *)raw) {
				RYGCallRecording *m = [RYGCallRecording recordingFromJSONDict:d];
				if (!m || (m.recordingId.length && [seen containsObject:m.recordingId])) continue;
				if (m.recordingId.length) [seen addObject:m.recordingId];
				[list addObject:m];
				added = YES;
			}
			if (!added) continue;
			sortByDate(list);
			changed |= writeAll(o, list);
		}

		NSString *srcMediaRoot = [importedDir stringByAppendingPathComponent:kMediaDir];
		for (NSString *o in [fm() contentsOfDirectoryAtPath:srcMediaRoot error:nil] ?: @[]) {
			NSString *srcOwnerDir = [srcMediaRoot stringByAppendingPathComponent:o];
			BOOL ownerIsDir = NO;
			if (![fm() fileExistsAtPath:srcOwnerDir isDirectory:&ownerIsDir] || !ownerIsDir) continue;
			NSString *dstOwnerDir = mediaDir(o);
			for (NSString *f in [fm() contentsOfDirectoryAtPath:srcOwnerDir error:nil] ?: @[]) {
				NSString *dst = [dstOwnerDir stringByAppendingPathComponent:f];
				if ([fm() fileExistsAtPath:dst]) continue;
				changed |= [fm() copyItemAtPath:[srcOwnerDir stringByAppendingPathComponent:f] toPath:dst error:nil];
			}
		}
	});

	if (changed) post(nil);
}

#pragma mark - Media

+ (NSString *)absolutePathForRelativePath:(NSString *)relativePath ownerPK:(NSString *)ownerPK {
	return absPath(relativePath, ownerPK);
}

+ (NSString *)reserveMediaURLForRecordingId:(NSString *)recordingId
                                  extension:(NSString *)ext
                                    ownerPK:(NSString *)ownerPK
                                relativePath:(NSString **)outRelative {
	NSString *safeId = clean(recordingId, @"call");
	NSString *cleanExt = clean(ext.length ? ext : @"mp4", @"mp4");
	if ([cleanExt hasPrefix:@"."]) cleanExt = [cleanExt substringFromIndex:1];
	NSString *rel = [NSString stringWithFormat:@"%@.%@", safeId, cleanExt.length ? cleanExt : @"mp4"];
	if (outRelative) *outRelative = rel;
	return [mediaDir(ownerPK) stringByAppendingPathComponent:rel];
}

+ (unsigned long long)mediaSizeBytesForOwnerPK:(NSString *)ownerPK {
	__block unsigned long long total = 0;
	sync_(^{
		NSDirectoryEnumerator *en = [fm() enumeratorAtPath:mediaDir(ownerPK)];
		for (__unused NSString *rel in en) {
			NSDictionary *a = en.fileAttributes;
			if ([a[NSFileType] isEqualToString:NSFileTypeRegular]) total += [a[NSFileSize] unsignedLongLongValue];
		}
	});
	return total;
}

#pragma mark - Unread

// A recording is seen if older than the global mark OR its group's own mark.
static NSTimeInterval seenThresholdForGroup(NSDictionary *st, NSString *key) {
	NSTimeInterval global = [st[@"lastSeenAt"] doubleValue];
	id gs = st[@"groupSeenAt"];
	NSTimeInterval grp = [gs isKindOfClass:NSDictionary.class] ? [gs[key] doubleValue] : 0;
	return MAX(global, grp);
}

+ (NSUInteger)unreadCountForOwnerPK:(NSString *)ownerPK {
	__block NSUInteger n = 0;
	sync_(^{
		NSMutableDictionary *st = readState(ownerPK);
		for (RYGCallRecording *m in readAll(ownerPK))
			if ([(m.startedAt ?: NSDate.distantPast) timeIntervalSince1970] > seenThresholdForGroup(st, groupKey(m))) n++;
	});
	return n;
}

+ (void)markAllSeenForOwnerPK:(NSString *)ownerPK {
	__block BOOL changed = NO;
	sync_(^{
		NSTimeInterval newest = 0;
		for (RYGCallRecording *m in readAll(ownerPK)) {
			NSTimeInterval t = [(m.startedAt ?: NSDate.distantPast) timeIntervalSince1970];
			if (t > newest) newest = t;
		}
		NSMutableDictionary *st = readState(ownerPK);   // merge — never clobber ignore list / synced ids / names
		if (newest <= [st[@"lastSeenAt"] doubleValue]) return;
		st[@"lastSeenAt"] = @(newest);
		writeState(ownerPK, st);
		changed = YES;
	});
	if (changed) post(ownerPK);
}

+ (void)markGroupSeen:(NSString *)identifier ownerPK:(NSString *)ownerPK {
	if (!identifier.length) return;
	__block BOOL changed = NO;
	sync_(^{
		NSMutableDictionary *st = readState(ownerPK);
		id cur = st[@"groupSeenAt"];
		NSMutableDictionary *gs = [cur isKindOfClass:NSDictionary.class] ? [cur mutableCopy] : [NSMutableDictionary dictionary];
		NSTimeInterval now = [NSDate date].timeIntervalSince1970;
		if ([gs[identifier] doubleValue] >= now) return;
		gs[identifier] = @(now);
		st[@"groupSeenAt"] = gs;
		writeState(ownerPK, st);
		changed = YES;
	});
	if (changed) post(ownerPK);
}

#pragma mark - Retention

+ (NSUInteger)pruneOlderThanDays:(NSInteger)days forOwnerPK:(NSString *)ownerPK {
	if (days <= 0) return 0;
	__block NSUInteger removed = 0;
	NSTimeInterval cutoff = [NSDate date].timeIntervalSince1970 - days * 86400.0;
	rewrite(ownerPK, ^(NSMutableArray<RYGCallRecording *> *list, BOOL *changed) {
		for (NSInteger i = (NSInteger)list.count - 1; i >= 0; i--) {
			RYGCallRecording *m = list[i];
			if ([(m.startedAt ?: NSDate.distantPast) timeIntervalSince1970] >= cutoff) continue;
			removeFile(m, ownerPK);
			[list removeObjectAtIndex:(NSUInteger)i];
			*changed = YES; removed++;
		}
	});
	return removed;
}

#pragma mark - State (synced ids, custom names)

static NSMutableDictionary *readState(NSString *o) {
	NSData *d = [NSData dataWithContentsOfFile:statePath(o)];
	id s = d.length ? [NSJSONSerialization JSONObjectWithData:d options:0 error:nil] : nil;
	return [s isKindOfClass:NSDictionary.class] ? [s mutableCopy] : [NSMutableDictionary dictionary];
}

static void writeState(NSString *o, NSDictionary *state) {
	NSData *out = [NSJSONSerialization dataWithJSONObject:state options:0 error:nil];
	if (out.length) [out writeToFile:statePath(o) atomically:YES];
}

+ (BOOL)isGallerySynced:(NSString *)recordingId ownerPK:(NSString *)ownerPK {
	if (!recordingId.length) return NO;
	__block BOOL synced = NO;
	sync_(^{
		id ids = readState(ownerPK)[@"gallerySyncedIds"];
		synced = [ids isKindOfClass:NSArray.class] && [ids containsObject:recordingId];
	});
	return synced;
}

+ (void)markGallerySynced:(NSString *)recordingId ownerPK:(NSString *)ownerPK {
	if (!recordingId.length) return;
	sync_(^{
		NSMutableDictionary *st = readState(ownerPK);
		id cur = st[@"gallerySyncedIds"];
		NSMutableArray *ids = [cur isKindOfClass:NSArray.class] ? [cur mutableCopy] : [NSMutableArray array];
		if (![ids containsObject:recordingId]) { [ids addObject:recordingId]; st[@"gallerySyncedIds"] = ids; writeState(ownerPK, st); }
	});
}

static NSString *customNameForKey(NSString *o, NSString *field, NSString *key) {
	if (!key.length) return nil;
	__block NSString *name = nil;
	sync_(^{
		id map = readState(o)[field];
		id v = [map isKindOfClass:NSDictionary.class] ? map[key] : nil;
		name = [v isKindOfClass:NSString.class] && [v length] ? v : nil;
	});
	return name;
}

static void setCustomNameForKey(NSString *o, NSString *field, NSString *key, NSString *name) {
	if (!key.length) return;
	sync_(^{
		NSMutableDictionary *st = readState(o);
		id cur = st[field];
		NSMutableDictionary *map = [cur isKindOfClass:NSDictionary.class] ? [cur mutableCopy] : [NSMutableDictionary dictionary];
		if (name.length) map[key] = name; else [map removeObjectForKey:key];
		st[field] = map;
		writeState(o, st);
	});
	post(o);
}

+ (NSString *)identifierForRecording:(RYGCallRecording *)recording { return groupKey(recording); }

+ (BOOL)isCallIgnored:(NSString *)identifier ownerPK:(NSString *)ownerPK {
	if (!identifier.length) return NO;
	__block BOOL ignored = NO;
	sync_(^{
		id list = readState(ownerPK)[@"ignoredCalls"];
		if ([list isKindOfClass:NSArray.class])
			for (NSDictionary *d in list) if ([d[@"id"] isEqualToString:identifier]) { ignored = YES; break; }
	});
	return ignored;
}

+ (void)setCall:(NSString *)identifier ignored:(BOOL)ignored name:(NSString *)name ownerPK:(NSString *)ownerPK {
	if (!identifier.length) return;
	sync_(^{
		NSMutableDictionary *st = readState(ownerPK);
		id cur = st[@"ignoredCalls"];
		NSMutableArray *list = [cur isKindOfClass:NSArray.class] ? [cur mutableCopy] : [NSMutableArray array];
		NSUInteger idx = [list indexOfObjectPassingTest:^BOOL(NSDictionary *d, NSUInteger i, BOOL *stop) { return [d[@"id"] isEqualToString:identifier]; }];
		if (ignored) {
			if (idx == NSNotFound) [list addObject:@{ @"id": identifier, @"name": name.length ? name : RYGLocalized(@"Unknown chat") }];
		} else if (idx != NSNotFound) [list removeObjectAtIndex:idx];
		st[@"ignoredCalls"] = list;
		writeState(ownerPK, st);
	});
	post(ownerPK);
}

+ (NSArray<NSDictionary *> *)ignoredCallsForOwnerPK:(NSString *)ownerPK {
	__block NSArray *out = @[];
	sync_(^{ id l = readState(ownerPK)[@"ignoredCalls"]; if ([l isKindOfClass:NSArray.class]) out = l; });
	return out;
}

+ (NSString *)customNameForRecordingId:(NSString *)recordingId ownerPK:(NSString *)ownerPK { return customNameForKey(ownerPK, @"recordingNames", recordingId); }
+ (void)setCustomName:(NSString *)name forRecordingId:(NSString *)recordingId ownerPK:(NSString *)ownerPK { setCustomNameForKey(ownerPK, @"recordingNames", recordingId, name); }
+ (NSString *)customNameForGroupIdentifier:(NSString *)identifier ownerPK:(NSString *)ownerPK { return customNameForKey(ownerPK, @"groupNames", identifier); }
+ (void)setCustomName:(NSString *)name forGroupIdentifier:(NSString *)identifier ownerPK:(NSString *)ownerPK { setCustomNameForKey(ownerPK, @"groupNames", identifier, name); }

@end
