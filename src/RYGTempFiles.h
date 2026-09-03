#import <Foundation/Foundation.h>

// Owns the lifetime of every tweak-written scratch file. All claimed paths sit
// under NSTemporaryDirectory() with a fixed "ryuk_tmp_" prefix so the boot sweep
// is unambiguous (legacy "ryg_tmp_" leftovers are swept too).
@interface RYGTempFiles : NSObject

+ (NSURL *)claimWithExt:(NSString *)ext;
+ (NSURL *)claimWithExt:(NSString *)ext ttl:(NSTimeInterval)ttl;
// Tag rides into the filename — purely cosmetic for on-disk readability.
+ (NSURL *)claimWithExt:(NSString *)ext ttl:(NSTimeInterval)ttl tag:(NSString *)tag;

// File with a caller-chosen, user-facing name (for share sheets / document
// picker). Lives inside a tracked temp dir so lifetime still works.
+ (NSURL *)claimNamedFile:(NSString *)filename ttl:(NSTimeInterval)ttl tag:(NSString *)tag;

// Idempotent — safe to call after the TTL already fired.
+ (void)releaseURL:(NSURL *)url;

// Push the auto-delete out when an async consumer needs the file longer than
// the original claim assumed.
+ (void)extendURL:(NSURL *)url ttl:(NSTimeInterval)ttl;

// Boot-time cleanup of leftovers from prior runs / crashes. Runs off the main thread.
+ (void)sweepLeftovers;

@end
