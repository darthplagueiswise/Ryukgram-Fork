#import "RYGMobileConfigJSONIO.h"

static NSString *RYGMCJSONSyncCanonicalCachePath(void) {
    NSString *support = NSSearchPathForDirectoriesInDomains(NSApplicationSupportDirectory, NSUserDomainMask, YES).firstObject;
    if (!support.length) return nil;
    NSString *directory = [support stringByAppendingPathComponent:@"RyukGram"];
    [NSFileManager.defaultManager createDirectoryAtPath:directory withIntermediateDirectories:YES attributes:nil error:nil];
    return [directory stringByAppendingPathComponent:@"mc_overrides_canonical.json"];
}

static BOOL RYGMCJSONSyncWriteAndVerify(NSData *data, NSString *path) {
    if (!data.length || !path.length) return NO;
    NSError *error = nil;
    if (![data writeToFile:path options:NSDataWritingAtomic error:&error]) return NO;
    NSData *roundTrip = [NSData dataWithContentsOfFile:path options:0 error:&error];
    return roundTrip.length && [roundTrip isEqualToData:data];
}

@implementation RYGMobileConfig (RYGPersistedJSONSync)

- (BOOL)ryg_syncPersistedJSONToNativeDataDirectory {
    // Portable RyukGram snapshot only. The canonical RYGMobileConfig owner calls
    // this method explicitly after coalesced user mutations. There is no +load,
    // constructor or method exchange here: JSON persistence cannot become a
    // competing startup owner.
    NSError *exportError = nil;
    NSData *overrides = [self ryg_exportOverridesData:&exportError];
    NSString *cachePath = RYGMCJSONSyncCanonicalCachePath();
    if (!overrides.length || !cachePath.length || !RYGMCJSONSyncWriteAndVerify(overrides, cachePath)) return NO;
    [self reapplyOverridesToNativeTable];
    return YES;
}

@end
