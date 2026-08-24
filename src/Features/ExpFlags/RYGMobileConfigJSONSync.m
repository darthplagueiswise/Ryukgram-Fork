#import "RYGMobileConfigJSONIO.h"
#import "RYGMobileConfigNameMappingStore.h"

static BOOL RYGMCJSONSyncWriteAndVerify(NSData *data, NSString *path) {
    if (!data.length || !path.length) return NO;
    NSData *existing = [NSData dataWithContentsOfFile:path options:0 error:nil];
    if ([existing isEqualToData:data]) return YES;
    NSError *error = nil;
    if (![data writeToFile:path options:NSDataWritingAtomic error:&error]) return NO;
    NSData *roundTrip = [NSData dataWithContentsOfFile:path options:0 error:&error];
    return roundTrip.length && [roundTrip isEqualToData:data];
}

@implementation RYGMobileConfig (RYGPersistedJSONSync)

- (BOOL)ryg_syncPersistedJSONToNativeDataDirectory {
    // The active Instagram <user>.data directory is the persistence authority.
    // No Application Support shadow document is created or restored here.
    NSString *directory = [self ryg_nativeDataDirectory];
    if (!directory.length) return NO;

    NSError *exportError = nil;
    NSData *overrides = [self ryg_exportOverridesData:&exportError];
    if (!overrides.length) return NO;

    BOOL success = YES;
    NSData *mapping = RYGMCLoadCachedNameMappingData();
    NSString *mappingPath = [self ryg_nativeNameMappingPath];
    if (mapping.length) {
        if (!mappingPath.length || !RYGMCJSONSyncWriteAndVerify(mapping, mappingPath)) success = NO;
    }

    NSString *overridesPath = [self ryg_nativeOverridesJSONPath];
    if (!overridesPath.length || !RYGMCJSONSyncWriteAndVerify(overrides, overridesPath)) success = NO;
    return success;
}

@end
