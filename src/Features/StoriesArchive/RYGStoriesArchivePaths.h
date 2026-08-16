#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

// Per-account layout. `<pk>` scoping is what the backup layer keys on
// (rygPKForRelativePath recognizes `<dir>/<pk>/...`).
//   <Documents>/StoriesArchive/<pk>/Stories.sqlite (+wal/shm)
//   <Documents>/StoriesArchive/<pk>/Media/<mediaID>.{jpg|mp4}
//   <Documents>/StoriesArchive/<pk>/Media/<mediaID>.thumb
@interface RYGStoriesArchivePaths : NSObject

+ (NSString *)rootDirectory;
+ (NSString *)accountDirectoryForPK:(NSString *)pk;
+ (NSString *)sqlitePathForPK:(NSString *)pk;
+ (NSString *)mediaDirectoryForPK:(NSString *)pk;

// Relative to the account's Media dir — what we persist on the row, so a moved
// or restored archive still resolves.
+ (NSString *)mediaRelPathForMediaID:(NSString *)mediaID ext:(NSString *)ext;
+ (NSString *)thumbRelPathForMediaID:(NSString *)mediaID;

@end

NS_ASSUME_NONNULL_END
