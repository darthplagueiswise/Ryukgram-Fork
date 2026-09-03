#import "RYGGalleryCoreDataStack.h"
#import "RYGGalleryPaths.h"
#import "RYGGalleryFile.h"
#import <sqlite3.h>

@interface RYGGalleryCoreDataStack ()
@property (nonatomic, strong, readwrite) NSPersistentContainer *persistentContainer;
@property (nonatomic, assign, readwrite) BOOL pendingLegacyMigration;
@end

static NSString * const kRYGGalleryEntityName = @"RYGGalleryFile";
static NSString * const kRYGGalleryStoreMigratedDefault = @"ryg_gallery_store_migrated_v2";

#define RYGGMLog(fmt, ...) NSLog(@"[RyukGram][GalleryMigrate] " fmt, ##__VA_ARGS__)

// Gallery attribute → SQLite column ("Z"+UPPER) + kind. 't' = Core Data timestamp.
typedef struct { const char *attr; const char *col; char kind; } RYGGalleryColumn;
static const RYGGalleryColumn kRYGGalleryColumns[] = {
	{"identifier","ZIDENTIFIER",'s'}, {"relativePath","ZRELATIVEPATH",'s'},
	{"mediaType","ZMEDIATYPE",'i'}, {"source","ZSOURCE",'i'},
	{"dateAdded","ZDATEADDED",'t'}, {"fileSize","ZFILESIZE",'i'},
	{"isFavorite","ZISFAVORITE",'i'}, {"folderPath","ZFOLDERPATH",'s'},
	{"customName","ZCUSTOMNAME",'s'}, {"sourceUsername","ZSOURCEUSERNAME",'s'},
	{"sourceUserPK","ZSOURCEUSERPK",'s'}, {"sourceProfileURLString","ZSOURCEPROFILEURLSTRING",'s'},
	{"sourceMediaPK","ZSOURCEMEDIAPK",'s'}, {"sourceMediaCode","ZSOURCEMEDIACODE",'s'},
	{"sourceMediaURLString","ZSOURCEMEDIAURLSTRING",'s'}, {"pixelWidth","ZPIXELWIDTH",'i'},
	{"pixelHeight","ZPIXELHEIGHT",'i'}, {"durationSeconds","ZDURATIONSECONDS",'d'},
};
static const int kRYGGalleryColumnCount = sizeof(kRYGGalleryColumns) / sizeof(kRYGGalleryColumns[0]);

// Finds the Core Data gallery table (ZSCIGALLERYFILE / ZRYGGALLERYFILE / any Z*GALLERYFILE).
static NSString *rygFindGalleryTable(sqlite3 *db) {
	sqlite3_stmt *st = NULL;
	NSString *found = nil;
	if (sqlite3_prepare_v2(db, "SELECT name FROM sqlite_master WHERE type='table' AND upper(name) LIKE 'Z%GALLERYFILE'", -1, &st, NULL) == SQLITE_OK) {
		if (sqlite3_step(st) == SQLITE_ROW) {
			const char *n = (const char *)sqlite3_column_text(st, 0);
			if (n) found = [NSString stringWithUTF8String:n];
		}
	}
	sqlite3_finalize(st);
	return found;
}

// Reads all gallery rows from a raw sqlite store into attribute dicts. Bypasses
// Core Data entirely, so it survives any model hash/name/schema drift.
static NSArray<NSDictionary *> *rygReadGalleryRows(NSString *sqlitePath, NSUInteger *outTotal) {
	if (outTotal) *outTotal = 0;
	// Read-write so a WAL-mode store's -wal sidecar is read (read-only can't replay it).
	sqlite3 *db = NULL;
	if (sqlite3_open_v2(sqlitePath.fileSystemRepresentation, &db, SQLITE_OPEN_READWRITE, NULL) != SQLITE_OK) {
		if (db) { sqlite3_close(db); db = NULL; }
		if (sqlite3_open_v2(sqlitePath.fileSystemRepresentation, &db, SQLITE_OPEN_READONLY, NULL) != SQLITE_OK) {
			RYGGMLog(@"raw read: cannot open %@ (%s)", sqlitePath, sqlite3_errmsg(db));
			if (db) sqlite3_close(db);
			return @[];
		}
		RYGGMLog(@"raw read: opened read-only (WAL rows may be missing) %@", sqlitePath.lastPathComponent);
	} else {
		char *cperr = NULL;
		if (sqlite3_exec(db, "PRAGMA wal_checkpoint(TRUNCATE);", NULL, NULL, &cperr) != SQLITE_OK) {
			RYGGMLog(@"raw read: wal_checkpoint note: %s", cperr ? cperr : "");
		}
		if (cperr) sqlite3_free(cperr);
	}

	NSString *table = rygFindGalleryTable(db);
	if (!table) { RYGGMLog(@"raw read: no gallery table in %@", sqlitePath); sqlite3_close(db); return @[]; }

	// Which of our columns actually exist in this store (older stores have fewer).
	NSMutableSet<NSString *> *present = [NSMutableSet set];
	sqlite3_stmt *info = NULL;
	NSString *pragma = [NSString stringWithFormat:@"PRAGMA table_info(%@)", table];
	if (sqlite3_prepare_v2(db, pragma.UTF8String, -1, &info, NULL) == SQLITE_OK) {
		while (sqlite3_step(info) == SQLITE_ROW) {
			const char *c = (const char *)sqlite3_column_text(info, 1);
			if (c) [present addObject:[[NSString stringWithUTF8String:c] uppercaseString]];
		}
	}
	sqlite3_finalize(info);

	NSString *sql = [NSString stringWithFormat:@"SELECT * FROM %@", table];
	sqlite3_stmt *st = NULL;
	if (sqlite3_prepare_v2(db, sql.UTF8String, -1, &st, NULL) != SQLITE_OK) {
		RYGGMLog(@"raw read: select failed on %@: %s", table, sqlite3_errmsg(db));
		sqlite3_close(db);
		return @[];
	}

	int ncol = sqlite3_column_count(st);
	NSMutableDictionary<NSString *, NSNumber *> *colIndex = [NSMutableDictionary dictionary];
	for (int i = 0; i < ncol; i++) {
		const char *cn = sqlite3_column_name(st, i);
		if (cn) colIndex[[[NSString stringWithUTF8String:cn] uppercaseString]] = @(i);
	}

	NSMutableArray<NSDictionary *> *rows = [NSMutableArray array];
	while (sqlite3_step(st) == SQLITE_ROW) {
		NSMutableDictionary *row = [NSMutableDictionary dictionary];
		for (int k = 0; k < kRYGGalleryColumnCount; k++) {
			RYGGalleryColumn c = kRYGGalleryColumns[k];
			NSString *colU = [NSString stringWithUTF8String:c.col];
			if (![present containsObject:colU]) continue;
			NSNumber *idxN = colIndex[colU];
			if (!idxN) continue;
			int idx = idxN.intValue;
			if (sqlite3_column_type(st, idx) == SQLITE_NULL) continue;

			NSString *key = [NSString stringWithUTF8String:c.attr];
			switch (c.kind) {
				case 's': {
					const char *v = (const char *)sqlite3_column_text(st, idx);
					if (v) row[key] = [NSString stringWithUTF8String:v];
					break;
				}
				case 'i': row[key] = @(sqlite3_column_int64(st, idx)); break;
				case 'd': row[key] = @(sqlite3_column_double(st, idx)); break;
				case 't': row[key] = [NSDate dateWithTimeIntervalSinceReferenceDate:sqlite3_column_double(st, idx)]; break;
			}
		}
		if (row.count) [rows addObject:row];
	}
	sqlite3_finalize(st);
	sqlite3_close(db);

	if (outTotal) *outTotal = rows.count;
	RYGGMLog(@"raw read: %lu rows from %@ (%@)", (unsigned long)rows.count, table, sqlitePath.lastPathComponent);
	return rows;
}

@implementation RYGGalleryCoreDataStack

+ (instancetype)shared {
	static RYGGalleryCoreDataStack *instance;
	static dispatch_once_t onceToken;
	dispatch_once(&onceToken, ^{
		instance = [[RYGGalleryCoreDataStack alloc] init];
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
	entity.name = kRYGGalleryEntityName;
	entity.managedObjectClassName = @"RYGGalleryFile";

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

- (NSURL *)storeURL {
	return [NSURL fileURLWithPath:[[RYGGalleryPaths galleryDirectory] stringByAppendingPathComponent:@"gallery.sqlite"]];
}

// The old store, moved aside so a fresh RYG store can take its place. Rows get
// copied out of here into the live store, then it's deleted.
- (NSURL *)legacyStashURL {
	return [NSURL fileURLWithPath:[[RYGGalleryPaths galleryDirectory] stringByAppendingPathComponent:@"gallery_legacy.sqlite"]];
}

- (BOOL)storeMarkedMigrated {
	return [[NSUserDefaults standardUserDefaults] boolForKey:kRYGGalleryStoreMigratedDefault];
}

- (void)markStoreMigrated {
	[[NSUserDefaults standardUserDefaults] setBool:YES forKey:kRYGGalleryStoreMigratedDefault];
}

- (void)moveStoreFile:(NSURL *)from to:(NSURL *)to {
	NSFileManager *fm = NSFileManager.defaultManager;
	for (NSString *suffix in @[@"", @"-wal", @"-shm"]) {
		NSString *src = [from.path stringByAppendingString:suffix];
		NSString *dst = [to.path stringByAppendingString:suffix];
		[fm removeItemAtPath:dst error:NULL];
		if ([fm fileExistsAtPath:src]) [fm moveItemAtPath:src toPath:dst error:NULL];
	}
}

- (void)deleteStoreFile:(NSURL *)url {
	NSFileManager *fm = NSFileManager.defaultManager;
	for (NSString *suffix in @[@"", @"-wal", @"-shm"]) {
		[fm removeItemAtPath:[url.path stringByAppendingString:suffix] error:NULL];
	}
}

- (NSUInteger)legacyMigrationItemCount {
	if (!self.pendingLegacyMigration) return 0;
	NSUInteger total = 0;
	rygReadGalleryRows([self legacyStashURL].path, &total);
	return total;
}

// Copies rows from a raw sqlite gallery store into the live RYG store. Preserves
// identifier (thumbnails are keyed by it) and relativePath (media already on disk).
- (NSUInteger)importRawRowsFromStoreAtPath:(NSString *)path intoContext:(NSManagedObjectContext *)ctx dedup:(BOOL)dedup {
	NSUInteger total = 0;
	NSArray<NSDictionary *> *rows = rygReadGalleryRows(path, &total);
	if (!rows.count) return 0;

	NSMutableSet<NSString *> *existingIds = [NSMutableSet set];
	if (dedup) {
		NSFetchRequest *fr = [NSFetchRequest fetchRequestWithEntityName:kRYGGalleryEntityName];
		fr.propertiesToFetch = @[@"identifier"];
		fr.resultType = NSDictionaryResultType;
		for (NSDictionary *d in [ctx executeFetchRequest:fr error:NULL]) {
			NSString *rid = d[@"identifier"];
			if (rid.length) [existingIds addObject:rid];
		}
	}

	NSUInteger added = 0;
	for (NSDictionary *row in rows) {
		NSString *rid = row[@"identifier"];
		if (dedup && rid.length && [existingIds containsObject:rid]) continue;

		NSManagedObject *obj = [NSEntityDescription insertNewObjectForEntityForName:kRYGGalleryEntityName inManagedObjectContext:ctx];
		[row enumerateKeysAndObjectsUsingBlock:^(NSString *k, id v, __unused BOOL *stop) {
			[obj setValue:v forKey:k];
		}];
		if (!rid.length) [obj setValue:[NSUUID UUID].UUIDString forKey:@"identifier"];
		if (rid.length) [existingIds addObject:rid];
		added++;
	}
	RYGGMLog(@"imported %lu of %lu raw rows (dedup=%d)", (unsigned long)added, (unsigned long)rows.count, dedup);
	return added;
}

// Copies the stashed legacy store's rows into the live RYG store, then deletes it.
- (BOOL)performLegacyMigrationLogged {
	if (!self.pendingLegacyMigration) {
		RYGGMLog(@"performLegacyMigration: nothing pending, skipping");
		return YES;
	}

	NSString *stashPath = [self legacyStashURL].path;
	if (![NSFileManager.defaultManager fileExistsAtPath:stashPath]) {
		RYGGMLog(@"performLegacyMigration: no stash file, marking done");
		[self markStoreMigrated];
		self.pendingLegacyMigration = NO;
		return YES;
	}

	NSManagedObjectContext *ctx = self.viewContext;
	__block NSUInteger added = 0;
	__block BOOL ok = YES;
	[ctx performBlockAndWait:^{
		added = [self importRawRowsFromStoreAtPath:stashPath intoContext:ctx dedup:YES];
		NSError *saveErr = nil;
		if (ctx.hasChanges && ![ctx save:&saveErr]) {
			RYGGMLog(@"FAILED: save after import: %@", saveErr);
			ok = NO;
		}
	}];
	if (!ok) return NO;

	[self deleteStoreFile:[self legacyStashURL]];
	[self markStoreMigrated];
	self.pendingLegacyMigration = NO;
	RYGGMLog(@"SUCCESS: restored %lu items from legacy store", (unsigned long)added);
	return YES;
}

// Called by write paths (import/save) that must not lose data if the user
// hasn't triggered the gallery-open popup yet.
- (BOOL)ensureLegacyMigrationSilently {
	if (!self.pendingLegacyMigration) return YES;
	RYGGMLog(@"ensureLegacyMigrationSilently: migrating before a write");
	return [self performLegacyMigrationLogged];
}

- (void)setupPersistentContainer {
	NSManagedObjectModel *model = [self buildModel];
	self.persistentContainer = [[NSPersistentContainer alloc] initWithName:@"RYGGalleryModel" managedObjectModel:model];

	NSURL *storeURL = [self storeURL];
	NSFileManager *fm = NSFileManager.defaultManager;

	self.pendingLegacyMigration = NO;
	if (![self storeMarkedMigrated]) {
		[self prepareLegacyStashIfNeeded:storeURL model:model fm:fm];
	}

	NSPersistentStoreDescription *storeDesc = [[NSPersistentStoreDescription alloc] initWithURL:storeURL];
	// Same-name lightweight migration only (adding attributes over time); the
	// legacy rename is handled by the raw copy, not Core Data.
	storeDesc.shouldMigrateStoreAutomatically = YES;
	storeDesc.shouldInferMappingModelAutomatically = YES;
	self.persistentContainer.persistentStoreDescriptions = @[storeDesc];

	[self.persistentContainer loadPersistentStoresWithCompletionHandler:^(NSPersistentStoreDescription *desc, NSError *error) {
		if (error) {
			NSLog(@"[RyukGram Gallery] Failed to load Core Data store: %@", error);
		}
	}];

	self.persistentContainer.viewContext.automaticallyMergesChangesFromParent = YES;
}

// If the on-disk store isn't RYG-readable, stash it aside so a fresh RYG store
// loads; rows copy in later. Resumes a stash from an interrupted migration.
- (void)prepareLegacyStashIfNeeded:(NSURL *)storeURL model:(NSManagedObjectModel *)model fm:(NSFileManager *)fm {
	if ([fm fileExistsAtPath:[self legacyStashURL].path]) {
		RYGGMLog(@"found leftover legacy stash — resuming migration");
		self.pendingLegacyMigration = YES;
		return;
	}

	if (![fm fileExistsAtPath:storeURL.path]) {
		RYGGMLog(@"no store on disk — fresh install, nothing to migrate");
		[self markStoreMigrated];
		return;
	}

	NSDictionary *meta = [NSPersistentStoreCoordinator metadataForPersistentStoreOfType:NSSQLiteStoreType
																					 URL:storeURL options:nil error:NULL];
	BOOL rygReadable = meta && [model isConfiguration:nil compatibleWithStoreMetadata:meta];
	NSDictionary *storeHashes = meta[NSStoreModelVersionHashesKey];
	RYGGMLog(@"store entities=%@ rygReadable=%d", storeHashes.allKeys, rygReadable);

	if (rygReadable) {
		[self markStoreMigrated];   // already RYG format
		return;
	}

	RYGGMLog(@"legacy store detected — stashing aside for raw import");
	[self moveStoreFile:storeURL to:[self legacyStashURL]];
	self.pendingLegacyMigration = YES;
}

- (NSManagedObjectContext *)viewContext {
	return self.persistentContainer.viewContext;
}

- (void)checkpointStoreForExport {
	[self saveContext]; // flush pending Core Data changes into the WAL first

	// Second read-write connection folds Core Data's WAL frames into the main
	// file. WAL allows concurrent connections, so the live store is untouched.
	sqlite3 *db = NULL;
	NSString *path = [self storeURL].path;
	if (sqlite3_open_v2(path.fileSystemRepresentation, &db, SQLITE_OPEN_READWRITE, NULL) == SQLITE_OK) {
		char *e = NULL;
		if (sqlite3_exec(db, "PRAGMA wal_checkpoint(TRUNCATE);", NULL, NULL, &e) != SQLITE_OK)
			RYGGMLog(@"export checkpoint note: %s", e ? e : "");
		if (e) sqlite3_free(e);
	} else {
		RYGGMLog(@"export checkpoint: cannot open store (%s)", sqlite3_errmsg(db));
	}
	if (db) sqlite3_close(db);
}

- (void)saveContext {
	NSManagedObjectContext *ctx = self.viewContext;
	if (ctx.persistentStoreCoordinator.persistentStores.count == 0) {
		if (self.pendingLegacyMigration) RYGGMLog(@"saveContext skipped — store not loaded yet (migration pending)");
		return;
	}
	if (![ctx hasChanges]) return;

	NSError *error;
	if (![ctx save:&error]) {
		NSLog(@"[RyukGram Gallery] Failed to save context: %@", error);
	}
}

- (void)unloadPersistentStores {
	NSPersistentStoreCoordinator *coordinator = self.persistentContainer.persistentStoreCoordinator;
	for (NSPersistentStore *store in [coordinator.persistentStores copy]) {
		NSError *removeError = nil;
		[coordinator removePersistentStore:store error:&removeError];
		if (removeError) {
			NSLog(@"[RyukGram Gallery] Failed unloading persistent store: %@", removeError);
		}
	}
}

- (void)reloadPersistentContainer {
	[self unloadPersistentStores];
	[self setupPersistentContainer];
}

#pragma mark - Backup merge

// Content identity from stored attributes (no file I/O) so a re-imported backup dedups.
static NSString *rygGalleryFingerprint(NSDictionary *a) {
	id pk = a[@"sourceMediaPK"];
	NSString *pkPart = ([pk isKindOfClass:NSString.class] && [(NSString *)pk length]) ? pk : @"";
	return [NSString stringWithFormat:@"%@|%@|%@|%@x%@|%@",
			pkPart,
			a[@"fileSize"] ?: @0,
			a[@"mediaType"] ?: @0,
			a[@"pixelWidth"] ?: @0, a[@"pixelHeight"] ?: @0,
			a[@"durationSeconds"] ?: @0];
}

static NSString *rygUniqueRelativePath(NSString *rel, NSSet *taken) {
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

// Row-level import into the live RYG store — never swaps the sqlite file, so the
// store always stays RYG-valid (a foreign/legacy sqlite would strand the flag).
// replace = wipe existing rows + media first; merge = keep them and dedup.
- (NSUInteger)importGalleryFromArchiveDirectory:(NSString *)archiveDir replace:(BOOL)replace {
	[self ensureLegacyMigrationSilently]; // local store must be RYG-format before we insert into it

	NSFileManager *fm = NSFileManager.defaultManager;
	NSString *foreignStorePath = [archiveDir stringByAppendingPathComponent:@"gallery.sqlite"];
	BOOL isDir = NO;
	if (![fm fileExistsAtPath:foreignStorePath isDirectory:&isDir] || isDir) {
		NSLog(@"[RyukGram Gallery] import: no gallery.sqlite in %@", archiveDir);
		return 0;
	}

	NSString *foreignFiles = [archiveDir stringByAppendingPathComponent:@"Files"];
	NSString *foreignThumbs = [archiveDir stringByAppendingPathComponent:@"Thumbnails"];
	NSString *localFiles = [RYGGalleryPaths galleryMediaDirectory];
	NSString *localThumbs = [RYGGalleryPaths galleryThumbnailsDirectory];

	NSManagedObjectModel *model = self.persistentContainer.managedObjectModel;
	NSArray<NSString *> *attrKeys = [model.entitiesByName[kRYGGalleryEntityName].attributesByName allKeys];

	// Read the backup store raw — works for old SCIGalleryFile backups and any
	// schema drift, with no Core Data model-hash matching.
	NSArray<NSDictionary *> *foreignSnaps = rygReadGalleryRows(foreignStorePath, NULL);
	if (!foreignSnaps.count) {
		NSLog(@"[RyukGram Gallery] merge: no rows in backup store");
		return 0;
	}

	__block NSUInteger added = 0;
	NSManagedObjectContext *localCtx = [self.persistentContainer newBackgroundContext];
	[localCtx performBlockAndWait:^{
		if (replace) {
			NSFetchRequest *wipe = [NSFetchRequest fetchRequestWithEntityName:kRYGGalleryEntityName];
			for (NSManagedObject *o in [localCtx executeFetchRequest:wipe error:nil] ?: @[]) [localCtx deleteObject:o];
			[localCtx save:NULL];
			[self clearDirectoryContents:localFiles fm:fm];
			[self clearDirectoryContents:localThumbs fm:fm];
			RYGGMLog(@"import(replace): wiped existing gallery rows + media");
		}

		NSFetchRequest *fr = [NSFetchRequest fetchRequestWithEntityName:kRYGGalleryEntityName];
		NSArray *localRows = [localCtx executeFetchRequest:fr error:nil] ?: @[];

		NSMutableSet *fingerprints = [NSMutableSet set];
		NSMutableSet *takenRelPaths = [NSMutableSet set];
		for (NSManagedObject *o in localRows) {
			[fingerprints addObject:rygGalleryFingerprint([o dictionaryWithValuesForKeys:attrKeys])];
			NSString *rel = [o valueForKey:@"relativePath"];
			if (rel.length) [takenRelPaths addObject:rel];
		}

		NSMutableSet<NSString *> *importedForeignRels = [NSMutableSet set];
		NSUInteger skipDup = 0, skipNoRel = 0, skipNoMedia = 0;

		for (NSDictionary *snap in foreignSnaps) {
			NSString *fp = rygGalleryFingerprint(snap);
			if ([fingerprints containsObject:fp]) { skipDup++; continue; }

			NSString *foreignRel = [snap[@"relativePath"] isKindOfClass:NSString.class] ? snap[@"relativePath"] : nil;
			NSString *foreignId  = [snap[@"identifier"] isKindOfClass:NSString.class] ? snap[@"identifier"] : nil;
			if (!foreignRel.length) { skipNoRel++; continue; }

			NSString *srcMedia = [foreignFiles stringByAppendingPathComponent:foreignRel];
			if (![fm fileExistsAtPath:srcMedia]) { skipNoMedia++; continue; } // DB row with no payload — skip
			[importedForeignRels addObject:foreignRel];

			NSString *newRel = rygUniqueRelativePath(foreignRel, takenRelPaths);
			NSString *dstMedia = [localFiles stringByAppendingPathComponent:newRel];
			[fm createDirectoryAtPath:dstMedia.stringByDeletingLastPathComponent withIntermediateDirectories:YES attributes:nil error:nil];
			NSError *copyErr = nil;
			if (![fm copyItemAtPath:srcMedia toPath:dstMedia error:&copyErr]) {
				NSLog(@"[RyukGram Gallery] merge: media copy failed (%@): %@", foreignRel, copyErr);
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

			NSManagedObject *row = [NSEntityDescription insertNewObjectForEntityForName:kRYGGalleryEntityName inManagedObjectContext:localCtx];
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

		RYGGMLog(@"import: %lu rows read, added %lu (skip dup=%lu norel=%lu nomedia=%lu)",
				 (unsigned long)foreignSnaps.count, (unsigned long)added,
				 (unsigned long)skipDup, (unsigned long)skipNoRel, (unsigned long)skipNoMedia);

		// Recovery: media present in the backup with no usable DB row (corrupt /
		// truncated sqlite) is imported straight from the file so nothing is lost.
		NSUInteger recovered = 0;
		for (NSString *name in [fm contentsOfDirectoryAtPath:foreignFiles error:NULL] ?: @[]) {
			if ([name hasPrefix:@"."] || [importedForeignRels containsObject:name]) continue;
			NSString *src = [foreignFiles stringByAppendingPathComponent:name];
			BOOL isDir = NO;
			if (![fm fileExistsAtPath:src isDirectory:&isDir] || isDir) continue;

			NSString *newRel = rygUniqueRelativePath(name, takenRelPaths);
			NSString *dst = [localFiles stringByAppendingPathComponent:newRel];
			if (![fm copyItemAtPath:src toPath:dst error:NULL]) continue;

			NSDictionary *attrs = [fm attributesOfItemAtPath:dst error:NULL];
			NSManagedObject *row = [NSEntityDescription insertNewObjectForEntityForName:kRYGGalleryEntityName inManagedObjectContext:localCtx];
			[row setValue:[NSUUID UUID].UUIDString forKey:@"identifier"];
			[row setValue:newRel forKey:@"relativePath"];
			[row setValue:@(RYGGalleryMediaTypeForExtension(name.pathExtension)) forKey:@"mediaType"];
			[row setValue:@(RYGGallerySourceImported) forKey:@"source"];
			[row setValue:[NSDate date] forKey:@"dateAdded"];
			[row setValue:@([attrs[NSFileSize] longLongValue]) forKey:@"fileSize"];
			[takenRelPaths addObject:newRel];
			added++;
			recovered++;
		}
		if (recovered) RYGGMLog(@"import: recovered %lu orphaned media file(s) with no DB row", (unsigned long)recovered);

		if (added) {
			NSError *saveErr = nil;
			if (![localCtx save:&saveErr]) {
				NSLog(@"[RyukGram Gallery] import: save failed: %@", saveErr);
				added = 0;
			}
		}
	}];

	NSLog(@"[RyukGram Gallery] import: added %lu total (replace=%d)", (unsigned long)added, replace);
	return added;
}

- (void)clearDirectoryContents:(NSString *)dir fm:(NSFileManager *)fm {
	for (NSString *name in [fm contentsOfDirectoryAtPath:dir error:NULL]) {
		[fm removeItemAtPath:[dir stringByAppendingPathComponent:name] error:NULL];
	}
}

@end
