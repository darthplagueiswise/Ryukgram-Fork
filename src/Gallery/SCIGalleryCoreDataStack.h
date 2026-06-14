#import <Foundation/Foundation.h>
#import <CoreData/CoreData.h>

NS_ASSUME_NONNULL_BEGIN

@interface SCIGalleryCoreDataStack : NSObject

+ (instancetype)shared;

@property (nonatomic, strong, readonly) NSPersistentContainer *persistentContainer;
@property (nonatomic, strong, readonly) NSManagedObjectContext *viewContext;

- (void)saveContext;
- (void)unloadPersistentStores;
- (void)reloadPersistentContainer;

// Merge a backup's gallery into the live store (extracted dir: gallery.sqlite +
// Files/ + Thumbnails/). Dedups by content; copies media + thumbnails. Returns rows added.
- (NSUInteger)mergeGalleryFromArchiveDirectory:(NSString *)archiveDir;

@end

NS_ASSUME_NONNULL_END
