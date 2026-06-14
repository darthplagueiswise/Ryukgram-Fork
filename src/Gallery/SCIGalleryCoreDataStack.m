#import "SCIGalleryCoreDataStack.h"
#import "SCIGalleryPaths.h"

@interface SCIGalleryCoreDataStack ()
@property (nonatomic, strong, readwrite) NSPersistentContainer *persistentContainer;
@end

static NSString * const kSCIGalleryEntityName = @"SCIGalleryFile";

@implementation SCIGalleryCoreDataStack

+ (instancetype)shared {
	static SCIGalleryCoreDataStack *instance;
	static dispatch_once_t onceToken;
	dispatch_once(&onceToken, ^{
		instance = [[SCIGalleryCoreDataStack alloc] init];
	});
	return instance;
}

- (instancetype)init {
	self = [super init];
	if (self) {
		[self setupPersistentContainer];
	}
	return self;
}

- (NSManagedObjectModel *)buildModel {
	NSManagedObjectModel *model = [[NSManagedObjectModel alloc] init];

	NSEntityDescription *entity = [[NSEntityDescription alloc] init];
	entity.name = kSCIGalleryEntityName;
	entity.managedObjectClassName = @"SCIGalleryFile";

	NSAttributeDescription *identifier = [[NSAttributeDescription alloc] init];
	identifier.name = @"identifier";
	identifier.attributeType = NSStringAttributeType;
	identifier.optional = NO;

	NSAttributeDescription *relativePath = [[NSAttributeDescription alloc] init];
	relativePath.name = @"relativePath";
	relativePath.attributeType = NSStringAttributeType;
	relativePath.optional = NO;

	NSAttributeDescription *mediaType = [[NSAttributeDescription alloc] init];
	mediaType.name = @"mediaType";
	mediaType.attributeType = NSInteger16AttributeType;
	mediaType.optional = NO;
	mediaType.defaultValue = @0;

	NSAttributeDescription *source = [[NSAttributeDescription alloc] init];
	source.name = @"source";
	source.attributeType = NSInteger16AttributeType;
	source.optional = NO;
	source.defaultValue = @0;

	NSAttributeDescription *dateAdded = [[NSAttributeDescription alloc] init];
	dateAdded.name = @"dateAdded";
	dateAdded.attributeType = NSDateAttributeType;
	dateAdded.optional = NO;

	NSAttributeDescription *fileSize = [[NSAttributeDescription alloc] init];
	fileSize.name = @"fileSize";
	fileSize.attributeType = NSInteger64AttributeType;
	fileSize.optional = NO;
	fileSize.defaultValue = @0;

	NSAttributeDescription *isFavorite = [[NSAttributeDescription alloc] init];
	isFavorite.name = @"isFavorite";
	isFavorite.attributeType = NSBooleanAttributeType;
	isFavorite.optional = NO;
	isFavorite.defaultValue = @NO;

	NSAttributeDescription *folderPath = [[NSAttributeDescription alloc] init];
	folderPath.name = @"folderPath";
	folderPath.attributeType = NSStringAttributeType;
	folderPath.optional = YES;

	NSAttributeDescription *customName = [[NSAttributeDescription alloc] init];
	customName.name = @"customName";
	customName.attributeType = NSStringAttributeType;
	customName.optional = YES;

	NSAttributeDescription *sourceUsername = [[NSAttributeDescription alloc] init];
	sourceUsername.name = @"sourceUsername";
	sourceUsername.attributeType = NSStringAttributeType;
	sourceUsername.optional = YES;

	NSAttributeDescription *sourceUserPK = [[NSAttributeDescription alloc] init];
	sourceUserPK.name = @"sourceUserPK";
	sourceUserPK.attributeType = NSStringAttributeType;
	sourceUserPK.optional = YES;

	NSAttributeDescription *sourceProfileURLString = [[NSAttributeDescription alloc] init];
	sourceProfileURLString.name = @"sourceProfileURLString";
	sourceProfileURLString.attributeType = NSStringAttributeType;
	sourceProfileURLString.optional = YES;

	NSAttributeDescription *sourceMediaPK = [[NSAttributeDescription alloc] init];
	sourceMediaPK.name = @"sourceMediaPK";
	sourceMediaPK.attributeType = NSStringAttributeType;
	sourceMediaPK.optional = YES;

	NSAttributeDescription *sourceMediaCode = [[NSAttributeDescription alloc] init];
	sourceMediaCode.name = @"sourceMediaCode";
	sourceMediaCode.attributeType = NSStringAttributeType;
	sourceMediaCode.optional = YES;

	NSAttributeDescription *sourceMediaURLString = [[NSAttributeDescription alloc] init];
	sourceMediaURLString.name = @"sourceMediaURLString";
	sourceMediaURLString.attributeType = NSStringAttributeType;
	sourceMediaURLString.optional = YES;

	NSAttributeDescription *pixelWidth = [[NSAttributeDescription alloc] init];
	pixelWidth.name = @"pixelWidth";
	pixelWidth.attributeType = NSInteger32AttributeType;
	pixelWidth.optional = NO;
	pixelWidth.defaultValue = @0;

	NSAttributeDescription *pixelHeight = [[NSAttributeDescription alloc] init];
	pixelHeight.name = @"pixelHeight";
	pixelHeight.attributeType = NSInteger32AttributeType;
	pixelHeight.optional = NO;
	pixelHeight.defaultValue = @0;

	NSAttributeDescription *durationSeconds = [[NSAttributeDescription alloc] init];
	durationSeconds.name = @"durationSeconds";
	durationSeconds.attributeType = NSDoubleAttributeType;
	durationSeconds.optional = NO;
	durationSeconds.defaultValue = @0.0;

	entity.properties = @[
		identifier, relativePath, mediaType, source, dateAdded, fileSize, isFavorite, folderPath, customName,
		sourceUsername, sourceUserPK, sourceProfileURLString, sourceMediaPK, sourceMediaCode, sourceMediaURLString,
		pixelWidth, pixelHeight, durationSeconds
	];
	model.entities = @[entity];

	return model;
}

- (void)setupPersistentContainer {
	NSManagedObjectModel *model = [self buildModel];
	self.persistentContainer = [[NSPersistentContainer alloc] initWithName:@"SCIGalleryModel" managedObjectModel:model];

	NSString *storePath = [[SCIGalleryPaths galleryDirectory] stringByAppendingPathComponent:@"gallery.sqlite"];
	NSURL *storeURL = [NSURL fileURLWithPath:storePath];
	NSPersistentStoreDescription *storeDesc = [[NSPersistentStoreDescription alloc] initWithURL:storeURL];
	storeDesc.shouldMigrateStoreAutomatically = YES;
	storeDesc.shouldInferMappingModelAutomatically = YES;
	self.persistentContainer.persistentStoreDescriptions = @[storeDesc];

	[self.persistentContainer loadPersistentStoresWithCompletionHandler:^(NSPersistentStoreDescription *desc, NSError *error) {
		if (error) {
			NSLog(@"[SCInsta Gallery] Failed to load Core Data store: %@", error);
		}
	}];

	self.persistentContainer.viewContext.automaticallyMergesChangesFromParent = YES;
}

- (NSManagedObjectContext *)viewContext {
	return self.persistentContainer.viewContext;
}

- (void)saveContext {
	NSManagedObjectContext *ctx = self.viewContext;
	if (![ctx hasChanges]) return;

	NSError *error;
	if (![ctx save:&error]) {
		NSLog(@"[SCInsta Gallery] Failed to save context: %@", error);
	}
}

- (void)unloadPersistentStores {
	NSPersistentStoreCoordinator *coordinator = self.persistentContainer.persistentStoreCoordinator;
	for (NSPersistentStore *store in [coordinator.persistentStores copy]) {
		NSError *removeError = nil;
		[coordinator removePersistentStore:store error:&removeError];
		if (removeError) {
			NSLog(@"[SCInsta Gallery] Failed unloading persistent store: %@", removeError);
		}
	}
}

- (void)reloadPersistentContainer {
	[self unloadPersistentStores];
	[self setupPersistentContainer];
}

#pragma mark - Backup merge

// Content identity from stored attributes (no file I/O) so a re-imported backup dedups.
static NSString *sciGalleryFingerprint(NSDictionary *a) {
	id pk = a[@"sourceMediaPK"];
	NSString *pkPart = ([pk isKindOfClass:NSString.class] && [(NSString *)pk length]) ? pk : @"";
	return [NSString stringWithFormat:@"%@|%@|%@|%@x%@|%@",
			pkPart,
			a[@"fileSize"] ?: @0,
			a[@"mediaType"] ?: @0,
			a[@"pixelWidth"] ?: @0, a[@"pixelHeight"] ?: @0,
			a[@"durationSeconds"] ?: @0];
}

static NSString *sciUniqueRelativePath(NSString *rel, NSSet *taken) {
	if (![taken containsObject:rel]) return rel;
	NSString *ext = rel.pathExtension;
	NSString *base = ext.length ? [rel substringToIndex:rel.length - ext.length - 1] : rel;
	for (NSUInteger i = 0; i < 10000; i++) {
		NSString *suffix = [[NSUUID UUID].UUIDString substringToIndex:8];
		NSString *candidate = ext.length ? [NSString stringWithFormat:@"%@_%@.%@", base, suffix, ext]
										 : [NSString stringWithFormat:@"%@_%@", base, suffix];
		if (![taken containsObject:candidate]) return candidate;
	}
	return [NSString stringWithFormat:@"%@_%@", [NSUUID UUID].UUIDString, rel.lastPathComponent];
}

- (NSUInteger)mergeGalleryFromArchiveDirectory:(NSString *)archiveDir {
	NSFileManager *fm = NSFileManager.defaultManager;
	NSString *foreignStorePath = [archiveDir stringByAppendingPathComponent:@"gallery.sqlite"];
	BOOL isDir = NO;
	if (![fm fileExistsAtPath:foreignStorePath isDirectory:&isDir] || isDir) {
		NSLog(@"[SCInsta Gallery] merge: no gallery.sqlite in %@", archiveDir);
		return 0;
	}

	NSString *foreignFiles = [archiveDir stringByAppendingPathComponent:@"Files"];
	NSString *foreignThumbs = [archiveDir stringByAppendingPathComponent:@"Thumbnails"];
	NSString *localFiles = [SCIGalleryPaths galleryMediaDirectory];
	NSString *localThumbs = [SCIGalleryPaths galleryThumbnailsDirectory];

	NSManagedObjectModel *model = self.persistentContainer.managedObjectModel;
	NSArray<NSString *> *attrKeys = [model.entitiesByName[kSCIGalleryEntityName].attributesByName allKeys];

	// Throwaway copy — open read/write so Core Data can checkpoint a -wal sidecar.
	NSPersistentStoreCoordinator *foreignPSC = [[NSPersistentStoreCoordinator alloc] initWithManagedObjectModel:model];
	NSError *err = nil;
	if (![foreignPSC addPersistentStoreWithType:NSSQLiteStoreType configuration:nil
											URL:[NSURL fileURLWithPath:foreignStorePath]
										options:@{ NSMigratePersistentStoresAutomaticallyOption: @YES,
												   NSInferMappingModelAutomaticallyOption: @YES }
										  error:&err]) {
		NSLog(@"[SCInsta Gallery] merge: cannot open backup store: %@", err);
		return 0;
	}
	NSManagedObjectContext *foreignCtx = [[NSManagedObjectContext alloc] initWithConcurrencyType:NSPrivateQueueConcurrencyType];
	foreignCtx.persistentStoreCoordinator = foreignPSC;

	// Snapshot foreign rows to plain dicts so nothing crosses contexts.
	__block NSArray<NSDictionary *> *foreignSnaps = @[];
	[foreignCtx performBlockAndWait:^{
		NSFetchRequest *fr = [NSFetchRequest fetchRequestWithEntityName:kSCIGalleryEntityName];
		NSArray *rows = [foreignCtx executeFetchRequest:fr error:nil] ?: @[];
		NSMutableArray *snaps = [NSMutableArray arrayWithCapacity:rows.count];
		for (NSManagedObject *o in rows) [snaps addObject:[o dictionaryWithValuesForKeys:attrKeys]];
		foreignSnaps = snaps;
	}];

	__block NSUInteger added = 0;
	NSManagedObjectContext *localCtx = [self.persistentContainer newBackgroundContext];
	[localCtx performBlockAndWait:^{
		NSFetchRequest *fr = [NSFetchRequest fetchRequestWithEntityName:kSCIGalleryEntityName];
		NSArray *localRows = [localCtx executeFetchRequest:fr error:nil] ?: @[];

		NSMutableSet *fingerprints = [NSMutableSet set];
		NSMutableSet *takenRelPaths = [NSMutableSet set];
		for (NSManagedObject *o in localRows) {
			[fingerprints addObject:sciGalleryFingerprint([o dictionaryWithValuesForKeys:attrKeys])];
			NSString *rel = [o valueForKey:@"relativePath"];
			if (rel.length) [takenRelPaths addObject:rel];
		}

		for (NSDictionary *snap in foreignSnaps) {
			NSString *fp = sciGalleryFingerprint(snap);
			if ([fingerprints containsObject:fp]) continue;

			NSString *foreignRel = [snap[@"relativePath"] isKindOfClass:NSString.class] ? snap[@"relativePath"] : nil;
			NSString *foreignId  = [snap[@"identifier"] isKindOfClass:NSString.class] ? snap[@"identifier"] : nil;
			if (!foreignRel.length) continue;

			NSString *srcMedia = [foreignFiles stringByAppendingPathComponent:foreignRel];
			if (![fm fileExistsAtPath:srcMedia]) continue; // DB row with no payload — skip

			NSString *newRel = sciUniqueRelativePath(foreignRel, takenRelPaths);
			NSString *dstMedia = [localFiles stringByAppendingPathComponent:newRel];
			[fm createDirectoryAtPath:dstMedia.stringByDeletingLastPathComponent withIntermediateDirectories:YES attributes:nil error:nil];
			NSError *copyErr = nil;
			if (![fm copyItemAtPath:srcMedia toPath:dstMedia error:&copyErr]) {
				NSLog(@"[SCInsta Gallery] merge: media copy failed (%@): %@", foreignRel, copyErr);
				continue;
			}

			NSString *newId = [NSUUID UUID].UUIDString;
			if (foreignId.length) {
				NSString *srcThumb = [foreignThumbs stringByAppendingPathComponent:[foreignId stringByAppendingPathExtension:@"jpg"]];
				NSString *dstThumb = [localThumbs stringByAppendingPathComponent:[newId stringByAppendingPathExtension:@"jpg"]];
				if ([fm fileExistsAtPath:srcThumb]) {
					[fm createDirectoryAtPath:dstThumb.stringByDeletingLastPathComponent withIntermediateDirectories:YES attributes:nil error:nil];
					[fm copyItemAtPath:srcThumb toPath:dstThumb error:nil]; // missing thumb regenerates lazily
				}
			}

			NSManagedObject *row = [NSEntityDescription insertNewObjectForEntityForName:kSCIGalleryEntityName inManagedObjectContext:localCtx];
			for (NSString *k in attrKeys) {
				id v = snap[k];
				if (v && v != [NSNull null]) [row setValue:v forKey:k];
			}
			[row setValue:newId forKey:@"identifier"];
			[row setValue:newRel forKey:@"relativePath"];

			[fingerprints addObject:fp];
			[takenRelPaths addObject:newRel];
			added++;
		}

		if (added) {
			NSError *saveErr = nil;
			if (![localCtx save:&saveErr]) {
				NSLog(@"[SCInsta Gallery] merge: save failed: %@", saveErr);
				added = 0;
			}
		}
	}];

	for (NSPersistentStore *s in [foreignPSC.persistentStores copy]) [foreignPSC removePersistentStore:s error:nil];
	NSLog(@"[SCInsta Gallery] merge: added %lu of %lu backup rows", (unsigned long)added, (unsigned long)foreignSnaps.count);
	return added;
}

@end
