#import "RYGStoriesArchiveStore.h"
#import "RYGStoriesArchivePaths.h"
#import "RYGStoriesArchiveViewController.h"
#import "../StoriesAndMessages/RYGStoryViewerPins.h"
#import "../../UI/Notification/RYGNotificationActions.h"
#import "../../Utils.h"
#import <sqlite3.h>

static NSString *const kStoryEntity = @"RYGArchivedStory";
static NSString *const kViewerEntity = @"RYGArchivedStoryViewer";

NSString *const RYGStoriesArchiveDidChangeNotification = @"RYGStoriesArchiveDidChangeNotification";

@interface RYGStoriesArchiveStore ()
@property (nonatomic, copy, readwrite) NSString *accountPK;
@property (nonatomic, strong) NSPersistentContainer *container;
@end

@implementation RYGStoriesArchiveStore

#pragma mark - Registry

+ (NSMutableDictionary<NSString *, RYGStoriesArchiveStore *> *)registry {
	static NSMutableDictionary *reg;
	static dispatch_once_t once;
	dispatch_once(&once, ^{ reg = [NSMutableDictionary dictionary]; });
	return reg;
}

+ (instancetype)storeForPK:(NSString *)pk {
	if (!pk.length) return nil;
	@synchronized (self.registry) {
		RYGStoriesArchiveStore *s = self.registry[pk];
		if (!s) {
			s = [[self alloc] initWithPK:pk];
			if (s) self.registry[pk] = s;
		}
		return s;
	}
}

+ (instancetype)storeForCurrentUser {
	return [self storeForPK:[RYGUtils currentUserPK]];
}

+ (NSString *)storageDirectory {
	return [RYGStoriesArchivePaths rootDirectory];
}

#pragma mark - Model

- (NSManagedObjectModel *)buildModel {
	NSManagedObjectModel *model = [[NSManagedObjectModel alloc] init];

	NSEntityDescription *story = [[NSEntityDescription alloc] init];
	story.name = kStoryEntity;
	story.managedObjectClassName = @"RYGArchivedStory";

	NSEntityDescription *viewer = [[NSEntityDescription alloc] init];
	viewer.name = kViewerEntity;
	viewer.managedObjectClassName = @"RYGArchivedStoryViewer";

	NSMutableArray *storyProps = [NSMutableArray array];
	[storyProps addObject:[self attr:@"pk" type:NSStringAttributeType optional:NO]];
	[storyProps addObject:[self attr:@"mediaID" type:NSStringAttributeType optional:YES]];
	[storyProps addObject:[self attr:@"mediaType" type:NSInteger16AttributeType optional:NO default:@0]];
	[storyProps addObject:[self attr:@"takenAt" type:NSDateAttributeType optional:YES]];
	[storyProps addObject:[self attr:@"expiresAt" type:NSDateAttributeType optional:YES]];
	[storyProps addObject:[self attr:@"sectionID" type:NSStringAttributeType optional:YES]];
	[storyProps addObject:[self attr:@"mediaRelPath" type:NSStringAttributeType optional:YES]];
	[storyProps addObject:[self attr:@"thumbRelPath" type:NSStringAttributeType optional:YES]];
	[storyProps addObject:[self attr:@"viewersCount" type:NSInteger64AttributeType optional:NO default:@0]];
	[storyProps addObject:[self attr:@"likesCount" type:NSInteger64AttributeType optional:NO default:@0]];
	[storyProps addObject:[self attr:@"reactionsCount" type:NSInteger64AttributeType optional:NO default:@0]];
	[storyProps addObject:[self attr:@"totalViewersCount" type:NSInteger64AttributeType optional:NO default:@0]];
	[storyProps addObject:[self attr:@"lastViewersFetch" type:NSDateAttributeType optional:YES]];

	NSMutableArray *viewerProps = [NSMutableArray array];
	[viewerProps addObject:[self attr:@"pk" type:NSStringAttributeType optional:NO]];
	[viewerProps addObject:[self attr:@"username" type:NSStringAttributeType optional:YES]];
	[viewerProps addObject:[self attr:@"fullName" type:NSStringAttributeType optional:YES]];
	[viewerProps addObject:[self attr:@"profilePicURL" type:NSStringAttributeType optional:YES]];
	[viewerProps addObject:[self attr:@"isVerified" type:NSBooleanAttributeType optional:NO default:@NO]];
	[viewerProps addObject:[self attr:@"liked" type:NSBooleanAttributeType optional:NO default:@NO]];
	[viewerProps addObject:[self attr:@"following" type:NSBooleanAttributeType optional:NO default:@NO]];
	[viewerProps addObject:[self attr:@"followedBy" type:NSBooleanAttributeType optional:NO default:@NO]];
	[viewerProps addObject:[self attr:@"sortIndex" type:NSInteger32AttributeType optional:NO default:@0]];
	[viewerProps addObject:[self attr:@"addedInLatestFetch" type:NSBooleanAttributeType optional:NO default:@NO]];
	[viewerProps addObject:[self attr:@"reactionEmoji" type:NSStringAttributeType optional:YES]];
	[viewerProps addObject:[self attr:@"addedAt" type:NSDateAttributeType optional:YES]];

	NSRelationshipDescription *toViewers = [[NSRelationshipDescription alloc] init];
	toViewers.name = @"viewers";
	toViewers.destinationEntity = viewer;
	toViewers.minCount = 0;
	toViewers.maxCount = 0;
	toViewers.deleteRule = NSCascadeDeleteRule;
	toViewers.ordered = YES;

	NSRelationshipDescription *toStory = [[NSRelationshipDescription alloc] init];
	toStory.name = @"story";
	toStory.destinationEntity = story;
	toStory.minCount = 0;
	toStory.maxCount = 1;
	toStory.deleteRule = NSNullifyDeleteRule;

	toViewers.inverseRelationship = toStory;
	toStory.inverseRelationship = toViewers;

	[storyProps addObject:toViewers];
	[viewerProps addObject:toStory];

	story.properties = storyProps;
	viewer.properties = viewerProps;
	model.entities = @[story, viewer];
	return model;
}

- (NSAttributeDescription *)attr:(NSString *)name type:(NSAttributeType)type optional:(BOOL)optional {
	return [self attr:name type:type optional:optional default:nil];
}

- (NSAttributeDescription *)attr:(NSString *)name type:(NSAttributeType)type optional:(BOOL)optional default:(id)def {
	NSAttributeDescription *a = [[NSAttributeDescription alloc] init];
	a.name = name;
	a.attributeType = type;
	a.optional = optional;
	if (def) a.defaultValue = def;
	return a;
}

#pragma mark - Lifecycle

- (instancetype)initWithPK:(NSString *)pk {
	if (!(self = [super init])) return nil;
	_accountPK = [pk copy];

	NSManagedObjectModel *model = [self buildModel];
	_container = [[NSPersistentContainer alloc] initWithName:@"RYGStoriesArchive" managedObjectModel:model];

	NSURL *storeURL = [NSURL fileURLWithPath:[RYGStoriesArchivePaths sqlitePathForPK:pk]];
	NSPersistentStoreDescription *desc = [[NSPersistentStoreDescription alloc] initWithURL:storeURL];
	desc.shouldMigrateStoreAutomatically = YES;
	desc.shouldInferMappingModelAutomatically = YES;
	_container.persistentStoreDescriptions = @[desc];

	__block BOOL ok = YES;
	[_container loadPersistentStoresWithCompletionHandler:^(NSPersistentStoreDescription *d, NSError *error) {
		if (error) { ok = NO; NSLog(@"[RyukGram][StoriesArchive] store load failed: %@", error); }
	}];
	if (!ok) return nil;

	_container.viewContext.automaticallyMergesChangesFromParent = YES;
	return self;
}

- (NSManagedObjectContext *)viewContext { return _container.viewContext; }

- (void)performBackground:(void (^)(NSManagedObjectContext *))block {
	[_container performBackgroundTask:^(NSManagedObjectContext *ctx) {
		ctx.mergePolicy = NSMergeByPropertyObjectTrumpMergePolicy;
		block(ctx);
	}];
}

#pragma mark - Fetch helpers

- (NSFetchRequest *)fetchStoryBy:(NSString *)key value:(NSString *)value {
	NSFetchRequest *r = [NSFetchRequest fetchRequestWithEntityName:kStoryEntity];
	r.predicate = [NSPredicate predicateWithFormat:@"%K == %@", key, value];
	r.fetchLimit = 1;
	r.includesSubentities = NO;
	return r;
}

- (RYGArchivedStory *)storyWithPK:(NSString *)pk inContext:(NSManagedObjectContext *)ctx {
	return [[ctx executeFetchRequest:[self fetchStoryBy:@"pk" value:pk] error:nil] firstObject];
}

- (RYGArchivedStory *)storyWithMediaID:(NSString *)mediaID inContext:(NSManagedObjectContext *)ctx {
	return [[ctx executeFetchRequest:[self fetchStoryBy:@"mediaID" value:mediaID] error:nil] firstObject];
}

- (NSArray<RYGArchivedStoryViewer *> *)sortedViewersForStoryPK:(NSString *)pk {
	if (!pk.length) return @[];
	NSFetchRequest *r = [NSFetchRequest fetchRequestWithEntityName:kViewerEntity];
	r.predicate = [NSPredicate predicateWithFormat:@"story.pk == %@", pk];
	r.sortDescriptors = @[[NSSortDescriptor sortDescriptorWithKey:@"sortIndex" ascending:YES]];
	return [self.viewContext executeFetchRequest:r error:nil] ?: @[];
}

#pragma mark - Upsert

- (RYGArchivedStory *)upsertStoryWithPK:(NSString *)pk
                                mediaID:(NSString *)mediaID
                              mediaType:(int16_t)mediaType
                                takenAt:(NSDate *)takenAt
                              expiresAt:(NSDate *)expiresAt
                              inContext:(NSManagedObjectContext *)ctx {
	RYGArchivedStory *s = [self storyWithPK:pk inContext:ctx];
	if (!s) {
		s = [NSEntityDescription insertNewObjectForEntityForName:kStoryEntity inManagedObjectContext:ctx];
		s.pk = pk;
	}
	s.mediaID = mediaID;
	s.mediaType = mediaType;
	if (takenAt) s.takenAt = takenAt;
	s.expiresAt = expiresAt ?: (takenAt ? [takenAt dateByAddingTimeInterval:86400.0] : nil);
	if (takenAt) {
		NSDateComponents *c = [NSCalendar.currentCalendar components:(NSCalendarUnitYear | NSCalendarUnitMonth) fromDate:takenAt];
		s.sectionID = [NSString stringWithFormat:@"%04ld-%02ld", (long)c.year, (long)c.month];
	}
	return s;
}

- (void)markStoryPK:(NSString *)pk downloadedMediaRel:(NSString *)mediaRel thumbRel:(NSString *)thumbRel {
	if (!pk.length) return;
	[self performBackground:^(NSManagedObjectContext *ctx) {
		RYGArchivedStory *s = [self storyWithPK:pk inContext:ctx];
		if (!s) return;
		if (mediaRel) s.mediaRelPath = mediaRel;
		if (thumbRel) s.thumbRelPath = thumbRel;
		[self saveContext:ctx];
		[self postChange];
	}];
}

#pragma mark - Viewers

- (void)notifyPinnedEvents:(NSArray<NSDictionary *> *)events {
	void (^openArchive)(void) = ^{ [RYGStoriesArchiveViewController presentFrom:nil]; };
	if (events.count == 1) {
		NSDictionary *e = events.firstObject;
		NSString *u = [e[@"username"] length] ? [@"@" stringByAppendingString:e[@"username"]] : RYGLocalized(@"A pinned viewer");
		NSString *title, *subtitle = u;
		if ([e[@"reacted"] boolValue]) {
			title = RYGLocalized(@"Pinned viewer reacted to your story");
			if ([e[@"emoji"] length]) subtitle = [NSString stringWithFormat:@"%@ %@", u, e[@"emoji"]];
		} else if ([e[@"liked"] boolValue]) {
			title = RYGLocalized(@"Pinned viewer liked your story");
		} else {
			title = RYGLocalized(@"Pinned viewer saw your story");
		}
		RYGNotifyTap(RYG_NOTIF_PINNED_VIEWER_ACTIVITY, title, subtitle, @"pin.fill", RYGNotificationToneInfo, openArchive);
	} else {
		RYGNotifyTap(RYG_NOTIF_PINNED_VIEWER_ACTIVITY,
			RYGLocalized(@"Pinned viewers on your story"),
			[NSString stringWithFormat:RYGLocalized(@"%lu pinned viewers just saw, liked or reacted"), (unsigned long)events.count],
			@"pin.fill", RYGNotificationToneInfo, openArchive);
	}
}

- (NSArray<NSString *> *)mediaIDsNeedingViewerRefreshBefore:(NSDate *)cutoff {
	__block NSArray<NSString *> *out = @[];
	NSManagedObjectContext *ctx = self.viewContext;
	[ctx performBlockAndWait:^{
		NSDate *lo = [[NSDate date] dateByAddingTimeInterval:-172800.0];
		NSFetchRequest *r = [NSFetchRequest fetchRequestWithEntityName:kStoryEntity];
		r.predicate = [NSPredicate predicateWithFormat:@"takenAt >= %@ AND (lastViewersFetch == nil OR lastViewersFetch < %@)", lo, cutoff];
		r.sortDescriptors = @[[NSSortDescriptor sortDescriptorWithKey:@"takenAt" ascending:NO]];
		r.includesSubentities = NO;
		NSMutableArray *ids = [NSMutableArray array];
		for (RYGArchivedStory *s in [ctx executeFetchRequest:r error:nil])
			if (s.mediaID.length) [ids addObject:s.mediaID];
		out = ids;
	}];
	return out;
}

// viewers may be empty: a 0-viewer snapshot still records lastViewersFetch so the
// 24–48h window doesn't re-poll it every refresh.
- (void)saveViewers:(NSArray<NSDictionary *> *)viewers
          totalCount:(NSInteger)totalCount
          forMediaID:(NSString *)mediaID {
	if (!mediaID.length) return;

	BOOL notifyPinned = [RYGUtils getBoolPref:@"ryg_stories_archive_notify_pinned"]
	                    && [RYGUtils getBoolPref:@"ryg_story_viewer_sort_enabled"];

	[self performBackground:^(NSManagedObjectContext *ctx) {
		RYGArchivedStory *story = [self storyWithMediaID:mediaID inContext:ctx];
		if (!story) return;

		BOOL hadPriorFetch = story.lastViewersFetch != nil;
		NSMutableDictionary<NSString *, NSNumber *> *wasLiked = [NSMutableDictionary dictionary];
		NSMutableDictionary<NSString *, NSString *> *wasReaction = [NSMutableDictionary dictionary];
		NSMutableDictionary<NSString *, RYGArchivedStoryViewer *> *existing = [NSMutableDictionary dictionary];
		for (RYGArchivedStoryViewer *v in story.viewers) {
			if (v.pk.length) { existing[v.pk] = v; wasLiked[v.pk] = @(v.liked); if (v.reactionEmoji.length) wasReaction[v.pk] = v.reactionEmoji; }
			v.addedInLatestFetch = NO;
		}

		NSMutableArray<NSDictionary *> *pinnedEvents = [NSMutableArray array];

		NSInteger i = 0;
		for (NSDictionary *d in viewers) {
			NSString *pk = d[@"pk"];
			if (![pk isKindOfClass:NSString.class] || !pk.length) continue;

			if (notifyPinned && hadPriorFetch && [RYGStoryViewerPins isPinned:pk]) {
				BOOL existedBefore = wasLiked[pk] != nil;
				BOOL nowLiked = [d[@"liked"] boolValue];
				BOOL newlyLiked = nowLiked && ![wasLiked[pk] boolValue];
				NSString *emoji = [d[@"reaction_emoji"] length] ? d[@"reaction_emoji"] : nil;
				BOOL newlyReacted = emoji && ![emoji isEqualToString:(wasReaction[pk] ?: @"")];
				if (!existedBefore || newlyLiked || newlyReacted)
					[pinnedEvents addObject:@{ @"username": d[@"username"] ?: @"", @"liked": @(newlyLiked), @"reacted": @(newlyReacted), @"emoji": emoji ?: @"" }];
			}

			RYGArchivedStoryViewer *v = existing[pk];
			if (!v) {
				v = [NSEntityDescription insertNewObjectForEntityForName:kViewerEntity inManagedObjectContext:ctx];
				v.pk = pk;
				v.addedAt = [NSDate date];
				v.story = story;
				v.addedInLatestFetch = YES;
				existing[pk] = v;
			}
			v.sortIndex = (int32_t)i++;
			v.username = d[@"username"];
			v.fullName = d[@"full_name"];
			v.profilePicURL = d[@"profile_pic_url"];
			v.isVerified = [d[@"is_verified"] boolValue];
			v.liked = [d[@"liked"] boolValue];
			v.following = [d[@"following"] boolValue];
			v.followedBy = [d[@"followed_by"] boolValue];
			v.reactionEmoji = [d[@"reaction_emoji"] length] ? d[@"reaction_emoji"] : nil;
		}

		NSInteger likes = 0, reactions = 0;
		for (NSDictionary *d in viewers) {
			if ([d[@"liked"] boolValue]) likes++;
			if ([d[@"reaction_emoji"] length]) reactions++;
		}
		story.viewersCount = viewers.count;
		story.likesCount = likes;
		story.reactionsCount = reactions;
		if (totalCount > 0) story.totalViewersCount = totalCount;
		story.lastViewersFetch = [NSDate date];
		[self saveContext:ctx];
		[self postChange];

		if (pinnedEvents.count) dispatch_async(dispatch_get_main_queue(), ^{ [self notifyPinnedEvents:pinnedEvents]; });
	}];
}

#pragma mark - Query

- (NSArray<RYGArchivedStory *> *)allStoriesSortedByDateDescending {
	NSFetchRequest *r = [NSFetchRequest fetchRequestWithEntityName:kStoryEntity];
	r.sortDescriptors = @[[NSSortDescriptor sortDescriptorWithKey:@"takenAt" ascending:NO]];
	r.includesSubentities = NO;
	return [self.viewContext executeFetchRequest:r error:nil] ?: @[];
}

- (NSString *)absoluteMediaPathForStory:(RYGArchivedStory *)story {
	if (!story.mediaRelPath.length) return nil;
	return [[RYGStoriesArchivePaths accountDirectoryForPK:self.accountPK] stringByAppendingPathComponent:story.mediaRelPath];
}

- (NSString *)absoluteThumbPathForStory:(RYGArchivedStory *)story {
	if (!story.thumbRelPath.length) return nil;
	return [[RYGStoriesArchivePaths accountDirectoryForPK:self.accountPK] stringByAppendingPathComponent:story.thumbRelPath];
}

#pragma mark - Delete

- (void)deleteStory:(RYGArchivedStory *)story {
	if (!story) return;
	[self removeMediaFilesForStory:story];
	NSManagedObjectContext *ctx = self.viewContext;
	[ctx performBlockAndWait:^{
		[ctx deleteObject:story];
		[self saveContext:ctx];
	}];
	[self postChange];
}

- (void)deleteAllStories {
	NSManagedObjectContext *ctx = self.viewContext;
	[ctx performBlockAndWait:^{
		NSFetchRequest *r = [NSFetchRequest fetchRequestWithEntityName:kStoryEntity];
		for (RYGArchivedStory *s in [ctx executeFetchRequest:r error:nil]) {
			[self removeMediaFilesForStory:s];
			[ctx deleteObject:s];
		}
		[self saveContext:ctx];
	}];
	[self postChange];
}

- (void)removeMediaFilesForStory:(RYGArchivedStory *)story {
	NSString *base = [RYGStoriesArchivePaths accountDirectoryForPK:self.accountPK];
	for (NSString *rel in @[story.mediaRelPath ?: @"", story.thumbRelPath ?: @""]) {
		if (!rel.length) continue;
		[NSFileManager.defaultManager removeItemAtPath:[base stringByAppendingPathComponent:rel] error:nil];
	}
}

#pragma mark - Save / export / unload

- (void)saveContext:(NSManagedObjectContext *)ctx {
	if (!ctx.hasChanges) return;
	NSError *e = nil;
	if (![ctx save:&e]) NSLog(@"[RyukGram][StoriesArchive] save failed: %@", e);
}

- (void)postChange {
	dispatch_async(dispatch_get_main_queue(), ^{
		[NSNotificationCenter.defaultCenter postNotificationName:RYGStoriesArchiveDidChangeNotification
		                                                  object:nil
		                                                userInfo:@{@"pk": self.accountPK ?: @""}];
	});
}

- (void)checkpointForExport {
	NSManagedObjectContext *ctx = self.viewContext;
	[ctx performBlockAndWait:^{ [self saveContext:ctx]; }];

	sqlite3 *db = NULL;
	NSString *path = [RYGStoriesArchivePaths sqlitePathForPK:self.accountPK];
	if (sqlite3_open_v2(path.fileSystemRepresentation, &db, SQLITE_OPEN_READWRITE, NULL) == SQLITE_OK) {
		sqlite3_exec(db, "PRAGMA wal_checkpoint(TRUNCATE);", NULL, NULL, NULL);
	}
	if (db) sqlite3_close(db);
}

- (void)unload {
	NSPersistentStoreCoordinator *psc = _container.persistentStoreCoordinator;
	for (NSPersistentStore *store in [psc.persistentStores copy]) {
		[psc removePersistentStore:store error:nil];
	}
	@synchronized (self.class.registry) {
		[self.class.registry removeObjectForKey:self.accountPK];
	}
}

#pragma mark - Backup

+ (void)checkpointAllForExport {
	NSArray *stores;
	@synchronized (self.registry) { stores = self.registry.allValues; }
	for (RYGStoriesArchiveStore *s in stores) [s checkpointForExport];
}

+ (void)resetAll {
	NSArray *stores;
	@synchronized (self.registry) { stores = self.registry.allValues; }
	for (RYGStoriesArchiveStore *s in stores) [s unload];
	[NSFileManager.defaultManager removeItemAtPath:[RYGStoriesArchivePaths rootDirectory] error:nil];
}

+ (void)resetForPK:(NSString *)pk {
	if (!pk.length) return;
	RYGStoriesArchiveStore *s;
	@synchronized (self.registry) { s = self.registry[pk]; }
	[s unload];
	[NSFileManager.defaultManager removeItemAtPath:[RYGStoriesArchivePaths accountDirectoryForPK:pk] error:nil];
}

// Reads an incoming Core Data store via raw sqlite (survives model drift) and
// upserts its rows into the live store for that pk. Local rows win; the import
// only adds stories/viewers/media we don't already have.
+ (void)mergeImportedStoreAtPath:(NSString *)extractedDir {
	BOOL isDir = NO;
	if (![NSFileManager.defaultManager fileExistsAtPath:extractedDir isDirectory:&isDir] || !isDir) return;

	NSCharacterSet *nonDigit = [[NSCharacterSet characterSetWithCharactersInString:@"0123456789"] invertedSet];
	for (NSString *pk in [NSFileManager.defaultManager contentsOfDirectoryAtPath:extractedDir error:nil]) {
		if ([pk rangeOfCharacterFromSet:nonDigit].location != NSNotFound) continue;
		NSString *incomingSQL = [[extractedDir stringByAppendingPathComponent:pk] stringByAppendingPathComponent:@"Stories.sqlite"];
		if (![NSFileManager.defaultManager fileExistsAtPath:incomingSQL]) continue;

		NSArray<NSDictionary *> *stories = [self readIncomingStoriesAt:incomingSQL];
		if (!stories.count) continue;

		RYGStoriesArchiveStore *store = [self storeForPK:pk];
		if (!store) continue;

		NSString *incomingMedia = [[extractedDir stringByAppendingPathComponent:pk] stringByAppendingPathComponent:@"Media"];
		NSString *liveBase = [RYGStoriesArchivePaths accountDirectoryForPK:pk];
		[RYGStoriesArchivePaths mediaDirectoryForPK:pk];

		[store mergeStories:stories fromMediaDir:incomingMedia toBase:liveBase];
	}
}

- (void)mergeStories:(NSArray<NSDictionary *> *)stories fromMediaDir:(NSString *)srcMedia toBase:(NSString *)liveBase {
	__block BOOL changed = NO;
	NSManagedObjectContext *ctx = self.viewContext;
	[ctx performBlockAndWait:^{
		for (NSDictionary *sd in stories) {
			NSString *pk = sd[@"pk"];
			if (![pk isKindOfClass:NSString.class] || !pk.length) continue;

			RYGArchivedStory *story = [self storyWithPK:pk inContext:ctx];
			if (!story) {
				story = [NSEntityDescription insertNewObjectForEntityForName:kStoryEntity inManagedObjectContext:ctx];
				story.pk = pk;
				story.mediaID = sd[@"mediaID"];
				story.mediaType = [sd[@"mediaType"] shortValue];
				story.takenAt = sd[@"takenAt"];
				story.expiresAt = sd[@"expiresAt"];
				story.sectionID = sd[@"sectionID"];
				story.mediaRelPath = sd[@"mediaRelPath"];
				story.thumbRelPath = sd[@"thumbRelPath"];
				story.viewersCount = [sd[@"viewersCount"] longLongValue];
				story.totalViewersCount = [sd[@"totalViewersCount"] longLongValue];
				story.lastViewersFetch = sd[@"lastViewersFetch"];
				changed = YES;
			}

			NSMutableSet<NSString *> *seen = [NSMutableSet set];
			for (RYGArchivedStoryViewer *v in story.viewers) if (v.pk.length) [seen addObject:v.pk];
			for (NSDictionary *vd in sd[@"viewers"]) {
				NSString *vpk = vd[@"pk"];
				if (![vpk isKindOfClass:NSString.class] || !vpk.length || [seen containsObject:vpk]) continue;
				[seen addObject:vpk];
				RYGArchivedStoryViewer *v = [NSEntityDescription insertNewObjectForEntityForName:kViewerEntity inManagedObjectContext:ctx];
				v.pk = vpk;
				v.username = vd[@"username"];
				v.fullName = vd[@"fullName"];
				v.profilePicURL = vd[@"profilePicURL"];
				v.isVerified = [vd[@"isVerified"] boolValue];
				v.liked = [vd[@"liked"] boolValue];
				v.following = [vd[@"following"] boolValue];
				v.followedBy = [vd[@"followedBy"] boolValue];
				v.sortIndex = [vd[@"sortIndex"] intValue];
				v.reactionEmoji = vd[@"reactionEmoji"];
				v.addedAt = vd[@"addedAt"];
				v.story = story;
				changed = YES;
			}

			// Recompute aggregates from the merged viewer set (counts drive the grid filter/sort).
			NSInteger vc = 0, lc = 0, rc = 0;
			for (RYGArchivedStoryViewer *v in story.viewers) {
				vc++;
				if (v.liked) lc++;
				if (v.reactionEmoji.length) rc++;
			}
			story.viewersCount = vc;
			story.likesCount = lc;
			story.reactionsCount = rc;
		}
		if (changed) [self saveContext:ctx];
	}];

	NSFileManager *fm = NSFileManager.defaultManager;
	for (NSString *f in [fm contentsOfDirectoryAtPath:srcMedia error:nil] ?: @[]) {
		NSString *dst = [[liveBase stringByAppendingPathComponent:@"Media"] stringByAppendingPathComponent:f];
		if ([fm fileExistsAtPath:dst]) continue;
		[fm copyItemAtPath:[srcMedia stringByAppendingPathComponent:f] toPath:dst error:nil];
	}
	if (changed) [self postChange];
}

+ (NSDictionary *)dateFromCDReal:(sqlite3_stmt *)st col:(int)i {
	if (sqlite3_column_type(st, i) == SQLITE_NULL) return nil;
	return (id)[NSDate dateWithTimeIntervalSinceReferenceDate:sqlite3_column_double(st, i)];
}

+ (NSArray<NSDictionary *> *)readIncomingStoriesAt:(NSString *)path {
	sqlite3 *db = NULL;
	if (sqlite3_open_v2(path.fileSystemRepresentation, &db, SQLITE_OPEN_READWRITE, NULL) != SQLITE_OK) {
		if (sqlite3_open_v2(path.fileSystemRepresentation, &db, SQLITE_OPEN_READONLY, NULL) != SQLITE_OK) {
			if (db) sqlite3_close(db);
			return @[];
		}
	} else {
		sqlite3_exec(db, "PRAGMA wal_checkpoint(TRUNCATE);", NULL, NULL, NULL);
	}

	NSMutableDictionary<NSNumber *, NSMutableArray *> *viewersByStory = [NSMutableDictionary dictionary];
	sqlite3_stmt *vst = NULL;
	if (sqlite3_prepare_v2(db, "SELECT ZSTORY,ZPK,ZUSERNAME,ZFULLNAME,ZPROFILEPICURL,ZISVERIFIED,ZLIKED,ZFOLLOWING,ZFOLLOWEDBY,ZSORTINDEX,ZADDEDAT,ZREACTIONEMOJI FROM ZRYGARCHIVEDSTORYVIEWER", -1, &vst, NULL) == SQLITE_OK) {
		while (sqlite3_step(vst) == SQLITE_ROW) {
			NSNumber *sid = @(sqlite3_column_int64(vst, 0));
			const unsigned char *vpk = sqlite3_column_text(vst, 1);
			if (!vpk) continue;
			NSMutableDictionary *v = [NSMutableDictionary dictionary];
			v[@"pk"] = @((const char *)vpk);
			if (sqlite3_column_text(vst, 2)) v[@"username"] = @((const char *)sqlite3_column_text(vst, 2));
			if (sqlite3_column_text(vst, 3)) v[@"fullName"] = @((const char *)sqlite3_column_text(vst, 3));
			if (sqlite3_column_text(vst, 4)) v[@"profilePicURL"] = @((const char *)sqlite3_column_text(vst, 4));
			v[@"isVerified"] = @(sqlite3_column_int(vst, 5));
			v[@"liked"] = @(sqlite3_column_int(vst, 6));
			v[@"following"] = @(sqlite3_column_int(vst, 7));
			v[@"followedBy"] = @(sqlite3_column_int(vst, 8));
			v[@"sortIndex"] = @(sqlite3_column_int(vst, 9));
			id ad = [self dateFromCDReal:vst col:10]; if (ad) v[@"addedAt"] = ad;
			if (sqlite3_column_text(vst, 11)) v[@"reactionEmoji"] = @((const char *)sqlite3_column_text(vst, 11));
			NSMutableArray *arr = viewersByStory[sid];
			if (!arr) { arr = [NSMutableArray array]; viewersByStory[sid] = arr; }
			[arr addObject:v];
		}
	}
	sqlite3_finalize(vst);

	NSMutableArray<NSDictionary *> *stories = [NSMutableArray array];
	sqlite3_stmt *sst = NULL;
	if (sqlite3_prepare_v2(db, "SELECT Z_PK,ZPK,ZMEDIAID,ZMEDIATYPE,ZTAKENAT,ZEXPIRESAT,ZSECTIONID,ZMEDIARELPATH,ZTHUMBRELPATH,ZVIEWERSCOUNT,ZTOTALVIEWERSCOUNT,ZLASTVIEWERSFETCH FROM ZRYGARCHIVEDSTORY", -1, &sst, NULL) == SQLITE_OK) {
		while (sqlite3_step(sst) == SQLITE_ROW) {
			const unsigned char *pk = sqlite3_column_text(sst, 1);
			if (!pk) continue;
			NSMutableDictionary *s = [NSMutableDictionary dictionary];
			s[@"pk"] = @((const char *)pk);
			if (sqlite3_column_text(sst, 2)) s[@"mediaID"] = @((const char *)sqlite3_column_text(sst, 2));
			s[@"mediaType"] = @(sqlite3_column_int(sst, 3));
			id t = [self dateFromCDReal:sst col:4]; if (t) s[@"takenAt"] = t;
			id e = [self dateFromCDReal:sst col:5]; if (e) s[@"expiresAt"] = e;
			if (sqlite3_column_text(sst, 6)) s[@"sectionID"] = @((const char *)sqlite3_column_text(sst, 6));
			if (sqlite3_column_text(sst, 7)) s[@"mediaRelPath"] = @((const char *)sqlite3_column_text(sst, 7));
			if (sqlite3_column_text(sst, 8)) s[@"thumbRelPath"] = @((const char *)sqlite3_column_text(sst, 8));
			s[@"viewersCount"] = @(sqlite3_column_int64(sst, 9));
			s[@"totalViewersCount"] = @(sqlite3_column_int64(sst, 10));
			id lf = [self dateFromCDReal:sst col:11]; if (lf) s[@"lastViewersFetch"] = lf;
			s[@"viewers"] = viewersByStory[@(sqlite3_column_int64(sst, 0))] ?: @[];
			[stories addObject:s];
		}
	}
	sqlite3_finalize(sst);
	sqlite3_close(db);
	return stories;
}

@end
