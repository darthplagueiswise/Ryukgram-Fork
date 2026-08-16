#import <Foundation/Foundation.h>
#import <CoreData/CoreData.h>

NS_ASSUME_NONNULL_BEGIN

@interface RYGGalleryCoreDataStack : NSObject

+ (instancetype)shared;

@property (nonatomic, strong, readonly) NSPersistentContainer *persistentContainer;
@property (nonatomic, strong, readonly) NSManagedObjectContext *viewContext;

// YES when a pre-RYG store is on disk and not yet migrated (persisted flag, cheap).
@property (nonatomic, assign, readonly) BOOL pendingLegacyMigration;

// Rows in the un-migrated legacy store (for the migrate prompt); 0 if none.
- (NSUInteger)legacyMigrationItemCount;

// Migrates the legacy store into the live store. Run off the main thread.
- (BOOL)performLegacyMigrationLogged;

// Migrates first if pending, so a write can't be lost. Used by import / save paths.
- (BOOL)ensureLegacyMigrationSilently;

- (void)saveContext;

// Folds the WAL into gallery.sqlite so a backup archives a complete store.
- (void)checkpointStoreForExport;

- (void)unloadPersistentStores;
- (void)reloadPersistentContainer;

// Row-level import of a backup's gallery (extracted dir: gallery.sqlite + Files/
// + Thumbnails/) into the live store. replace = wipe existing rows + media first;
// NO = merge with content dedup. Never swaps the sqlite. Returns rows added.
- (NSUInteger)importGalleryFromArchiveDirectory:(NSString *)archiveDir replace:(BOOL)replace;

@end

NS_ASSUME_NONNULL_END
