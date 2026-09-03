// Backup archive container: packs source dirs (+ in-memory files like
// manifest.json) into one ZLIB blob via libcompression, and extracts it back.
// Own tar-like format with a magic header — in-app only, not a real .zip.
// Streamed via a temp staging file so a huge gallery stays memory-bounded.

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

@interface RYGArchive : NSObject

// rootDirs: in-archive prefix -> on-disk dir, walked recursively.
// extraFiles: in-archive path -> raw bytes (e.g. manifest.json). Either may be empty.
+ (BOOL)createArchiveAtURL:(NSURL *)dst
                  rootDirs:(nullable NSDictionary<NSString *, NSString *> *)rootDirs
                extraFiles:(nullable NSDictionary<NSString *, NSData *> *)extraFiles
                     error:(NSError **)error;

// Extracts every entry under destDir, recreating the in-archive directory tree.
+ (BOOL)extractArchiveAtURL:(NSURL *)src
                toDirectory:(NSString *)destDir
                      error:(NSError **)error;

// Cheap magic-byte probe so import can tell a .ryukbak blob from raw JSON.
+ (BOOL)dataLooksLikeArchive:(NSData *)data;

@end

NS_ASSUME_NONNULL_END
