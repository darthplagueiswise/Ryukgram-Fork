#import "RYGDownloadLedger.h"
#import "../Utils.h"
#import "../UI/RYGPopupChrome.h"
#import "../Gallery/RYGGalleryFile.h"
#import <stdatomic.h>

static NSString *const kDir = @"RyukGram/DownloadLedger";
static NSString *const kFile = @"ledger.json";
static NSUInteger const kMaxRecords = 4000;
static NSUInteger const kMaxGalleryRefs = 20;
static NSTimeInterval const kSaveDebounce = 0.6;

static NSInteger sBypassDepth = 0;

@implementation RYGDownloadLedger

static dispatch_queue_t ioQ(void) {
	static dispatch_queue_t q; static dispatch_once_t once;
	dispatch_once(&once, ^{ q = dispatch_queue_create("com.ryukgram.downloadledger.io", DISPATCH_QUEUE_SERIAL); });
	return q;
}

+ (BOOL)enabled { return [RYGUtils getBoolPref:@"dl_duplicate_check"]; }

+ (NSString *)storageDirectory {
	NSString *root = NSSearchPathForDirectoriesInDomains(NSApplicationSupportDirectory, NSUserDomainMask, YES).firstObject;
	NSString *dir = [root stringByAppendingPathComponent:kDir];
	[NSFileManager.defaultManager createDirectoryAtPath:dir withIntermediateDirectories:YES attributes:nil error:nil];
	return dir;
}

+ (NSString *)ledgerFile { return [[self storageDirectory] stringByAppendingPathComponent:kFile]; }

#pragma mark - Store

// ioQ only.
static NSMutableDictionary<NSString *, NSDictionary *> *store(void) {
	static NSMutableDictionary *s;
	if (s) return s;
	s = [NSMutableDictionary dictionary];
	NSData *data = [NSData dataWithContentsOfFile:[RYGDownloadLedger ledgerFile]];
	if (data.length) {
		id parsed = [NSJSONSerialization JSONObjectWithData:data options:0 error:nil];
		NSDictionary *records = [parsed isKindOfClass:NSDictionary.class] ? parsed[@"records"] : nil;
		if ([records isKindOfClass:NSDictionary.class]) {
			[records enumerateKeysAndObjectsUsingBlock:^(id key, id value, __unused BOOL *stop) {
				if ([key isKindOfClass:NSString.class] && [value isKindOfClass:NSDictionary.class]) s[key] = value;
			}];
		}
	}
	return s;
}

static void pruneStore(NSMutableDictionary *s) {
	if (s.count <= kMaxRecords) return;
	NSArray *sorted = [s.allKeys sortedArrayUsingComparator:^NSComparisonResult(NSString *a, NSString *b) {
		double ta = [s[a][@"t"] doubleValue], tb = [s[b][@"t"] doubleValue];
		return ta < tb ? NSOrderedAscending : (ta > tb ? NSOrderedDescending : NSOrderedSame);
	}];
	NSUInteger drop = s.count - (kMaxRecords * 4 / 5);
	[s removeObjectsForKeys:[sorted subarrayWithRange:NSMakeRange(0, MIN(drop, sorted.count))]];
}

// Coalesced: a finishing carousel would rewrite the file per child.
static void scheduleSave(void) {
	static _Atomic(uint64_t) generation = 0;
	uint64_t mine = atomic_fetch_add(&generation, 1) + 1;
	dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(kSaveDebounce * NSEC_PER_SEC)), ioQ(), ^{
		if (atomic_load(&generation) != mine) return;
		NSDictionary *payload = @{ @"v": @1, @"records": [store() copy] };
		NSData *data = [NSJSONSerialization dataWithJSONObject:payload options:0 error:nil];
		if (data) [data writeToFile:[RYGDownloadLedger ledgerFile] atomically:YES];
	});
}

#pragma mark - Identity

// IG CDN filenames carry the asset id and survive host / signature churn.
static NSString *tokenForURL(NSURL *url) {
	NSString *name = [url.lastPathComponent stringByDeletingPathExtension];
	if ([name hasSuffix:@"_n"]) name = [name substringToIndex:name.length - 2];
	if (name.length >= 6) return name;
	return url.path.length ? url.path : url.absoluteString;
}

+ (NSString *)variantForMediaKind:(RYGDownloadMediaKind)kind {
	switch (kind) {
		case RYGDownloadMediaKindVideo: return @"video";
		case RYGDownloadMediaKindPhoto: return @"photo";
		case RYGDownloadMediaKindAudio: return @"audio";
		default: return @"file";
	}
}

+ (NSArray<NSString *> *)keysForURL:(NSURL *)url mediaPK:(NSString *)pk variant:(NSString *)variant {
	NSMutableArray<NSString *> *keys = [NSMutableArray array];
	NSString *token = url ? tokenForURL(url) : nil;
	if (token.length) [keys addObject:[@"u:" stringByAppendingString:token]];
	if (pk.length && variant.length) [keys addObject:[NSString stringWithFormat:@"m:%@:%@", pk, variant]];
	return keys;
}

#pragma mark - Lookup

+ (NSDictionary *)recordForKeys:(NSArray<NSString *> *)keys {
	if (!keys.count) return nil;
	__block NSDictionary *hit = nil;
	dispatch_sync(ioQ(), ^{
		NSMutableDictionary *s = store();
		for (NSString *k in keys) {
			NSDictionary *rec = s[k];
			if (rec) { hit = rec; break; }
		}
	});
	return hit;
}

+ (NSUInteger)count {
	__block NSUInteger n = 0;
	dispatch_sync(ioQ(), ^{ n = store().count; });
	return n;
}

#pragma mark - Recording

+ (void)recordKeys:(NSArray<NSString *> *)keys label:(NSString *)label galleryFileIDs:(NSArray<NSString *> *)galleryFileIDs {
	if (!keys.count || ![self enabled]) return;
	NSTimeInterval now = NSDate.date.timeIntervalSince1970;
	NSArray *snapshot = [keys copy];
	NSArray *ids = [galleryFileIDs copy];
	dispatch_async(ioQ(), ^{
		NSMutableDictionary *s = store();
		for (NSString *k in snapshot) {
			if (![k isKindOfClass:NSString.class] || !k.length) continue;
			NSDictionary *old = RYGJSONDict(s[k]);
			NSMutableDictionary *rec = [NSMutableDictionary dictionary];
			rec[@"f"] = RYGJSONScalar(old[@"f"]) ?: @(now);
			rec[@"t"] = @(now);
			rec[@"c"] = @([RYGJSONScalar(old[@"c"]) integerValue] + 1);
			NSString *oldLabel = RYGJSONString(old[@"n"]);
			if (label.length) rec[@"n"] = label;
			else if (oldLabel) rec[@"n"] = oldLabel;

			NSMutableOrderedSet *gallery = [NSMutableOrderedSet orderedSet];
			if ([old[@"g"] isKindOfClass:NSArray.class]) [gallery addObjectsFromArray:old[@"g"]];
			if (ids.count) [gallery addObjectsFromArray:ids];
			while (gallery.count > kMaxGalleryRefs) [gallery removeObjectAtIndex:0];
			if (gallery.count) rec[@"g"] = gallery.array;

			s[k] = rec;
		}
		pruneStore(s);
		scheduleSave();
	});
}

#pragma mark - Gate

+ (void)withBypass:(void (^)(void))block {
	if (!block) return;
	sBypassDepth++;
	block();
	sBypassDepth--;
}

+ (void)guardKeys:(NSArray<NSString *> *)keys proceed:(void (^)(void))proceed {
	[self guardKeyGroups:(keys.count ? @[keys] : nil) proceed:proceed];
}

+ (void)guardKeyGroups:(NSArray<NSArray<NSString *> *> *)groups proceed:(void (^)(void))proceed {
	if (!proceed) return;
	if (sBypassDepth > 0 || ![self enabled] || !groups.count) { proceed(); return; }

	NSUInteger items = 0, dupes = 0;
	NSTimeInterval latest = 0;
	NSMutableOrderedSet<NSString *> *galleryIDs = [NSMutableOrderedSet orderedSet];
	for (NSArray<NSString *> *group in groups) {
		if (!group.count) continue;
		items++;
		NSDictionary *rec = [self recordForKeys:group];
		if (!rec) continue;
		dupes++;
		latest = MAX(latest, [RYGJSONScalar(rec[@"t"]) doubleValue]);
		if ([rec[@"g"] isKindOfClass:NSArray.class]) [galleryIDs addObjectsFromArray:rec[@"g"]];
	}
	if (!dupes) { proceed(); return; }

	NSArray<NSString *> *alive = ([RYGUtils getBoolPref:@"ryg_gallery_enabled"] && galleryIDs.count)
		? [RYGGalleryFile existingIdentifiersFrom:galleryIDs.array] : @[];

	NSMutableArray<NSString *> *parts = [NSMutableArray array];
	if (items > 1) {
		[parts addObject:[NSString stringWithFormat:RYGLocalized(@"%lu of %lu items are already saved."),
		                  (unsigned long)dupes, (unsigned long)items]];
	} else if (latest > 0) {
		NSString *when = [NSDateFormatter localizedStringFromDate:[NSDate dateWithTimeIntervalSince1970:latest]
		                                               dateStyle:NSDateFormatterMediumStyle
		                                               timeStyle:NSDateFormatterShortStyle];
		[parts addObject:[NSString stringWithFormat:RYGLocalized(@"You saved this on %@."), when]];
	}
	if (alive.count) [parts addObject:RYGLocalized(@"Still in your gallery.")];

	dispatch_block_t ask = ^{
		UIAlertController *alert = [UIAlertController alertControllerWithTitle:RYGLocalized(@"Already downloaded")
		                                                              message:[parts componentsJoinedByString:@" "]
		                                                       preferredStyle:UIAlertControllerStyleAlert];
		[alert addAction:[UIAlertAction actionWithTitle:RYGLocalized(@"Download again")
		                                          style:UIAlertActionStyleDefault
		                                        handler:^(__unused id a) { proceed(); }]];
		if (alive.count) {
			[alert addAction:[UIAlertAction actionWithTitle:RYGLocalized(@"Remove and download again")
			                                          style:UIAlertActionStyleDestructive
			                                        handler:^(__unused id a) {
				[RYGGalleryFile removeFilesWithIdentifiers:alive];
				proceed();
			}]];
		}
		[alert addAction:[UIAlertAction actionWithTitle:RYGLocalized(@"Cancel") style:UIAlertActionStyleCancel handler:nil]];

		UIViewController *host = UIDevice.currentDevice.userInterfaceIdiom == UIUserInterfaceIdiomPad
			? [RYGPopupChrome topMostController] : nil;
		if (host) [host presentViewController:alert animated:YES completion:nil];
		else [RYGUtils presentAlertInOwnWindow:alert];
	};
	NSThread.isMainThread ? ask() : dispatch_async(dispatch_get_main_queue(), ask);
}

#pragma mark - Maintenance

+ (void)clearAll {
	dispatch_sync(ioQ(), ^{
		[store() removeAllObjects];
		[NSFileManager.defaultManager removeItemAtPath:[self ledgerFile] error:nil];
	});
}

+ (void)mergeImportedStoreAtPath:(NSString *)path {
	if (!path.length) return;
	NSData *data = [NSData dataWithContentsOfFile:[path stringByAppendingPathComponent:kFile]];
	if (!data.length) return;
	id parsed = [NSJSONSerialization JSONObjectWithData:data options:0 error:nil];
	NSDictionary *records = [parsed isKindOfClass:NSDictionary.class] ? parsed[@"records"] : nil;
	if (![records isKindOfClass:NSDictionary.class]) return;

	dispatch_sync(ioQ(), ^{
		NSMutableDictionary *s = store();
		[records enumerateKeysAndObjectsUsingBlock:^(id key, id value, __unused BOOL *stop) {
			if (![key isKindOfClass:NSString.class] || ![value isKindOfClass:NSDictionary.class]) return;
			NSDictionary *old = RYGJSONDict(s[key]);
			if (!old || [RYGJSONScalar(value[@"t"]) doubleValue] > [RYGJSONScalar(old[@"t"]) doubleValue]) s[key] = value;
		}];
		pruneStore(s);
		scheduleSave();
	});
}

@end
