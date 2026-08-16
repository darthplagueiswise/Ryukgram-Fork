#import "RYGStoriesArchiveManager.h"
#import "RYGStoriesArchiveStore.h"
#import "RYGStoriesArchivePaths.h"
#import "../../Utils.h"
#import "../../Networking/RYGInstagramAPI.h"
#import "../../Background/RYGBackgroundActivity.h"
#import "../../Observers/RYGObservers.h"
#import "../../Observers/RYGAccountObserver.h"
#import "../Feed/RYGHomeShortcutBadges.h"
#import <objc/runtime.h>
#import <objc/message.h>

static NSString *const kBGSource = @"stories_archive";

// IG serves stories as jpg/mp4, but derive the real extension from the URL so an
// unexpected type (webp, heic, mov, …) is stored correctly instead of mislabeled.
static NSString *rygExtForURL(NSURL *url, int16_t type) {
	NSString *e = url.pathExtension.lowercaseString;
	NSCharacterSet *nonAlnum = [[NSCharacterSet alphanumericCharacterSet] invertedSet];
	if (e.length >= 2 && e.length <= 4 && [e rangeOfCharacterFromSet:nonAlnum].location == NSNotFound) return e;
	return type == 2 ? @"mp4" : @"jpg";
}

static id rygSAObjCall(id obj, NSString *sel) {
	if (!obj || !sel.length) return nil;
	SEL s = NSSelectorFromString(sel);
	if (![obj respondsToSelector:s]) return nil;
	@try { return ((id (*)(id, SEL))objc_msgSend)(obj, s); } @catch (__unused id e) { return nil; }
}

static id rygSAIvar(id obj, const char *name) {
	if (!obj || !name) return nil;
	Ivar iv = NULL;
	for (Class c = [obj class]; c && !iv; c = class_getSuperclass(c))
		iv = class_getInstanceVariable(c, name);
	return iv ? object_getIvar(obj, iv) : nil;
}

static NSString *rygPKFromMaybeUser(id user) {
	if (!user) return nil;
	if ([user isKindOfClass:NSDictionary.class]) {
		NSDictionary *d = user;
		for (NSString *k in @[@"pk", @"pk_id", @"strong_id__", @"id"]) {
			id v = d[k];
			if ([v isKindOfClass:NSString.class] && [(NSString *)v length]) return v;
			if ([v isKindOfClass:NSNumber.class]) return [v description];
		}
		return nil;
	}
	return [RYGUtils pkFromIGUser:user];
}

static NSString *rygStoryAuthorPK(id media) {
	if (!media) return nil;
	NSString *pk = rygPKFromMaybeUser(rygSAObjCall(media, @"user"));
	if (pk.length) return pk;

	NSDictionary *fc = [RYGUtils fieldCacheForObject:media];
	if ([fc isKindOfClass:NSDictionary.class]) {
		pk = rygPKFromMaybeUser(fc[@"user"]);
		if (pk.length) return pk;
		for (NSString *k in @[@"user_id", @"owner_id", @"strong_id__"]) {
			id v = fc[k];
			if ([v isKindOfClass:NSString.class] && [(NSString *)v length]) return v;
			if ([v isKindOfClass:NSNumber.class]) return [v description];
		}
		id owner = fc[@"owner"];
		pk = rygPKFromMaybeUser(owner);
		if (pk.length) return pk;
	}
	return nil;
}

// IGStoryTraySectionController → dataSource → trayViewModels. Plain selectors on
// IG 438; ivar fallbacks kept for version drift.
static NSArray *rygSATrayViewModels(id sc) {
	id ds = rygSAObjCall(sc, @"dataSource") ?: rygSAIvar(sc, "_dataSource");
	id vms = ds ? (rygSAObjCall(ds, @"trayViewModels") ?: rygSAIvar(ds, "trayViewModels") ?: rygSAIvar(ds, "_trayViewModels")) : nil;
	if (!vms) vms = rygSAIvar(rygSAIvar(sc, "_dataController"), "_trayViewModels");
	return [vms isKindOfClass:NSArray.class] ? vms : nil;
}

@interface RYGStoriesArchiveManager ()
@property (nonatomic, assign) BOOL isSaving;
@property (nonatomic, assign) BOOL isFetchingViewers;
@property (nonatomic, strong) NSDate *sessionStart;
@property (nonatomic, weak) id lastTraySection;
@end

@implementation RYGStoriesArchiveManager

+ (instancetype)shared {
	static RYGStoriesArchiveManager *s;
	static dispatch_once_t once;
	dispatch_once(&once, ^{ s = [self new]; [s startObserving]; });
	return s;
}

- (void)startObserving {
	self.sessionStart = [NSDate date];
	[[RYGObservers account] start];
	[NSNotificationCenter.defaultCenter addObserver:self selector:@selector(accountChanged)
	                                           name:RYGActiveAccountDidChangeNotification object:nil];
}

// On quick-switch the tray repopulates with the new account's reels; re-run
// capture against the same tray section once it settles, and refetch viewers.
- (void)accountChanged {
	self.sessionStart = [NSDate date];
	self.isSaving = NO;
	self.isFetchingViewers = NO;
	dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(1.5 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
		[self recheck];
	});
}

- (void)recheck {
	if (self.lastTraySection) [self handleTraySectionController:self.lastTraySection];
	[self checkAndFetchViewers];
}

// Cutoff before which a story's viewers are considered stale. "launch" refetches
// each live story once per app session; the intervals are periodic.
- (NSDate *)viewerRefreshCutoff {
	NSString *mode = [RYGUtils getStringPref:@"ryg_stories_archive_viewer_refresh"];
	if ([mode isEqualToString:@"15m"]) return [NSDate dateWithTimeIntervalSinceNow:-900];
	if ([mode isEqualToString:@"1h"]) return [NSDate dateWithTimeIntervalSinceNow:-3600];
	if ([mode isEqualToString:@"6h"]) return [NSDate dateWithTimeIntervalSinceNow:-21600];
	return self.sessionStart ?: [NSDate date];
}

#pragma mark - Extraction

// Returns dicts: pk / mediaID / mediaType / takenAt / mediaURL / thumbURL. Only
// items whose media author == ownerPK are returned, so a stale reel lingering
// across a quick-switch can't leak another account's story into this archive.
- (NSArray<NSDictionary *> *)ownStoriesFromTray:(id)sc ownerPK:(NSString *)ownerPK {
	NSMutableArray *out = [NSMutableArray array];
	for (id vm in rygSATrayViewModels(sc)) {
		NSNumber *isCurrent = nil;
		@try { isCurrent = [vm valueForKey:@"isCurrentUserReel"]; } @catch (__unused id e) {}
		if (![isCurrent boolValue]) continue;

		id sorted = nil;
		SEL siSel = NSSelectorFromString(@"sortedItems");
		if ([vm respondsToSelector:siSel])
			@try { sorted = ((id (*)(id, SEL))objc_msgSend)(vm, siSel); } @catch (__unused id e) {}
		if (![sorted isKindOfClass:NSArray.class]) continue;

		for (id item in (NSArray *)sorted) {
			NSUInteger subtype = 0;
			Ivar st = class_getInstanceVariable([item class], "_subtype");
			if (st) subtype = *(NSUInteger *)((__bridge void *)item + ivar_getOffset(st));
			if (subtype != 0) continue;

			id media = rygSAIvar(item, "_mediaItem_mediaItem");
			if (!media) continue;

			// Fail closed: archive only when the media author is confirmed == ownerPK.
			NSString *authorPK = rygStoryAuthorPK(media);
			if (!ownerPK.length || ![authorPK isEqualToString:ownerPK]) continue;

			NSString *pk = [rygSAObjCall(media, @"pk") description];
			NSString *mediaID = [rygSAObjCall(media, @"mediaId") description];
			if (!pk.length || !mediaID.length) continue;

			int16_t mediaType = 1;
			SEL mtSel = NSSelectorFromString(@"itemMediaType");
			if ([media respondsToSelector:mtSel])
				@try { mediaType = (int16_t)((NSInteger (*)(id, SEL))objc_msgSend)(media, mtSel); } @catch (__unused id e) {}
			if (mediaType != 2) mediaType = 1;

			id taken = rygSAObjCall(media, @"takenAtDate");
			if (taken && ![taken isKindOfClass:NSDate.class]) {
				id d = rygSAObjCall(taken, @"date");
				taken = [d isKindOfClass:NSDate.class] ? d : nil;
			}

			NSURL *mediaURL = mediaType == 2 ? [RYGUtils getVideoUrlForMedia:media] : [RYGUtils getPhotoUrlForMedia:media];
			NSURL *thumbURL = [RYGUtils getPhotoUrlForMedia:media];
			if (!mediaURL) continue;

			NSMutableDictionary *d = [NSMutableDictionary dictionary];
			d[@"pk"] = pk;
			d[@"mediaID"] = mediaID;
			d[@"mediaType"] = @(mediaType);
			if ([taken isKindOfClass:NSDate.class]) d[@"takenAt"] = taken;
			d[@"mediaURL"] = mediaURL;
			d[@"ext"] = rygExtForURL(mediaURL, mediaType);
			if (thumbURL) d[@"thumbURL"] = thumbURL;
			[out addObject:d];
		}
	}
	return out;
}

#pragma mark - Capture

// pk of the account whose session owns this tray, not the globally-active one:
// warm background sessions fire their own tray controllers.
- (NSString *)sessionPKForSectionController:(id)sc {
	id session = nil;
	@try { session = [sc valueForKey:@"userSession"]; } @catch (__unused id e) {}
	if (!session) session = rygSAIvar(sc, "_userSession");
	if (!session) return nil;
	id user = nil;
	@try { user = [session valueForKey:@"user"]; } @catch (__unused id e) {}
	return [RYGUtils pkFromIGUser:user];
}

- (void)handleTraySectionController:(id)sc {
	if (sc) self.lastTraySection = sc;
	if (![RYGUtils getBoolPref:@"ryg_stories_archive"]) return;
	if (self.isSaving) return;

	NSString *sessionPK = [self sessionPKForSectionController:sc];
	if (!sessionPK.length) return;

	// Only archive the account in the foreground; a warm background session firing
	// its own tray must not write while a different account is active.
	NSString *activePK = [RYGUtils currentUserPK];
	if (activePK.length && ![sessionPK isEqualToString:activePK]) return;

	NSArray<NSDictionary *> *stories = [self ownStoriesFromTray:sc ownerPK:sessionPK];
	if (!stories.count) return;

	RYGStoriesArchiveStore *store = [RYGStoriesArchiveStore storeForPK:sessionPK];
	if (!store) return;

	self.isSaving = YES;
	[store performBackground:^(NSManagedObjectContext *ctx) {
		NSMutableArray<NSDictionary *> *toDownload = [NSMutableArray array];
		NSString *base = [RYGStoriesArchivePaths accountDirectoryForPK:store.accountPK];
		NSInteger newCount = 0;

		for (NSDictionary *s in stories) {
			NSString *mediaID = s[@"mediaID"];
			int16_t type = [s[@"mediaType"] shortValue];
			NSString *mediaRel = [RYGStoriesArchivePaths mediaRelPathForMediaID:mediaID ext:s[@"ext"]];
			BOOL onDisk = [NSFileManager.defaultManager fileExistsAtPath:[base stringByAppendingPathComponent:mediaRel]];

			RYGArchivedStory *row = [store storyWithPK:s[@"pk"] inContext:ctx];
			if (row && onDisk) continue;
			if (!row) newCount++;

			[store upsertStoryWithPK:s[@"pk"] mediaID:mediaID mediaType:type
			                 takenAt:s[@"takenAt"] expiresAt:nil inContext:ctx];
			[toDownload addObject:s];
		}
		if (ctx.hasChanges) [ctx save:NULL];
		if (newCount > 0) dispatch_async(dispatch_get_main_queue(), ^{ [RYGHomeShortcutBadges addCount:newCount toActionID:@"stories_archive"]; });

		if (toDownload.count) {
			dispatch_async(dispatch_get_main_queue(), ^{ [self downloadStories:toDownload store:store]; });
		} else {
			self.isSaving = NO;
		}
	}];
}

- (void)downloadStories:(NSArray<NSDictionary *> *)stories store:(RYGStoriesArchiveStore *)store {
	[RYGBackgroundActivity setSource:kBGSource active:YES];
	[RYGStoriesArchivePaths mediaDirectoryForPK:store.accountPK];
	NSString *base = [RYGStoriesArchivePaths accountDirectoryForPK:store.accountPK];

	dispatch_group_t group = dispatch_group_create();
	for (NSDictionary *s in stories) {
		NSString *mediaID = s[@"mediaID"];
		NSString *mediaRel = [RYGStoriesArchivePaths mediaRelPathForMediaID:mediaID ext:s[@"ext"]];
		NSString *thumbRel = [RYGStoriesArchivePaths thumbRelPathForMediaID:mediaID];

		dispatch_group_enter(group);
		[self downloadURL:s[@"mediaURL"] toPath:[base stringByAppendingPathComponent:mediaRel] completion:^(BOOL okMedia) {
			void (^finishThumb)(BOOL) = ^(BOOL okThumb) {
				[store markStoryPK:s[@"pk"]
				 downloadedMediaRel:okMedia ? mediaRel : nil
				           thumbRel:okThumb ? thumbRel : nil];
				dispatch_group_leave(group);
			};
			NSURL *thumbURL = s[@"thumbURL"];
			if (thumbURL) [self downloadURL:thumbURL toPath:[base stringByAppendingPathComponent:thumbRel] completion:finishThumb];
			else finishThumb(NO);
		}];
	}

	dispatch_group_notify(group, dispatch_get_main_queue(), ^{
		[RYGBackgroundActivity setSource:kBGSource active:NO];
		self.isSaving = NO;
	});
}

- (void)downloadURL:(NSURL *)url toPath:(NSString *)path completion:(void (^)(BOOL))completion {
	if (!url) { completion(NO); return; }
	NSURLSessionDownloadTask *task = [NSURLSession.sharedSession downloadTaskWithURL:url completionHandler:^(NSURL *tmp, NSURLResponse *resp, NSError *err) {
		NSInteger code = [resp isKindOfClass:NSHTTPURLResponse.class] ? [(NSHTTPURLResponse *)resp statusCode] : -1;
		BOOL ok = NO;
		if (!err && tmp && code >= 200 && code < 300) {
			NSFileManager *fm = NSFileManager.defaultManager;
			[fm removeItemAtPath:path error:nil];
			ok = [fm moveItemAtURL:tmp toURL:[NSURL fileURLWithPath:path] error:nil];
		}
		completion(ok);
	}];
	[task resume];
}

#pragma mark - Viewers

- (void)checkAndFetchViewers {
	if (![RYGUtils getBoolPref:@"ryg_stories_archive_auto_viewers"]) return;
	if (self.isFetchingViewers) return;

	RYGStoriesArchiveStore *store = [RYGStoriesArchiveStore storeForCurrentUser];
	if (!store) return;

	NSArray<NSString *> *mediaIDs = [store mediaIDsNeedingViewerRefreshBefore:[self viewerRefreshCutoff]];
	if (!mediaIDs.count) return;

	self.isFetchingViewers = YES;
	[RYGBackgroundActivity setSource:kBGSource active:YES];
	[self fetchViewersSequential:[mediaIDs mutableCopy] store:store];
}

- (void)refreshViewersForMediaID:(NSString *)mediaID completion:(void (^)(NSInteger))completion {
	RYGStoriesArchiveStore *store = [RYGStoriesArchiveStore storeForCurrentUser];
	if (!mediaID.length || !store) { if (completion) completion(-1); return; }
	[RYGInstagramAPI fetchAllStoryViewersForMediaID:mediaID progress:nil completion:^(NSArray<NSDictionary *> *viewers, NSInteger totalCount, NSError *error) {
		if (!error) [store saveViewers:viewers totalCount:totalCount forMediaID:mediaID];
		if (completion) dispatch_async(dispatch_get_main_queue(), ^{ completion(error ? -1 : (NSInteger)viewers.count); });
	}];
}

- (void)fetchViewersSequential:(NSMutableArray<NSString *> *)mediaIDs store:(RYGStoriesArchiveStore *)store {
	if (!mediaIDs.count) {
		self.isFetchingViewers = NO;
		[RYGBackgroundActivity setSource:kBGSource active:NO];
		return;
	}
	NSString *mediaID = mediaIDs.lastObject;
	[mediaIDs removeLastObject];

	[RYGInstagramAPI fetchAllStoryViewersForMediaID:mediaID progress:nil completion:^(NSArray<NSDictionary *> *viewers, NSInteger totalCount, NSError *error) {
		if (!error) [store saveViewers:viewers totalCount:totalCount forMediaID:mediaID];
		[self fetchViewersSequential:mediaIDs store:store];
	}];
}

@end
