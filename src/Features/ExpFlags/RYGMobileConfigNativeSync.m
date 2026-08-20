#import "RYGMobileConfigJSONIO.h"
#import "RYGMobileConfigNameMappingStore.h"

@implementation RYGMobileConfig (RYGNativeJSONSync)

- (BOOL)ryg_syncPersistedJSONToNativeDataDirectory {
    NSString *directory = [self ryg_nativeDataDirectory];
    if (!directory.length) return NO;

    NSFileManager *fileManager = NSFileManager.defaultManager;
    BOOL isDirectory = NO;
    if (![fileManager fileExistsAtPath:directory isDirectory:&isDirectory] || !isDirectory) return NO;

    BOOL wroteAnything = NO;

    NSData *mapping = RYGMCLoadCachedNameMappingData();
    NSString *mappingPath = [self ryg_nativeNameMappingPath];
    if (mapping.length && mappingPath.length) {
        NSError *error = nil;
        if ([mapping writeToFile:mappingPath options:NSDataWritingAtomic error:&error]) wroteAnything = YES;
    }

    NSError *overrideError = nil;
    NSData *overrides = [self ryg_exportOverridesData:&overrideError];
    NSString *overridesPath = [self ryg_nativeOverridesJSONPath];
    if (overrides.length && overridesPath.length) {
        NSError *error = nil;
        if ([overrides writeToFile:overridesPath options:NSDataWritingAtomic error:&error]) wroteAnything = YES;
    }

    return wroteAnything;
}

@end
