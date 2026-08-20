#import "RYGMobileConfigJSONIO.h"
#import "RYGMobileConfigNameMappingStore.h"

@implementation RYGMobileConfig (RYGPersistedJSONSync)

- (BOOL)ryg_syncPersistedJSONToNativeDataDirectory {
    NSString *directory = [self ryg_nativeDataDirectory];
    if (!directory.length) return NO;

    BOOL wroteAnything = NO;
    BOOL success = YES;

    NSData *mapping = RYGMCLoadCachedNameMappingData();
    NSString *mappingPath = [self ryg_nativeNameMappingPath];
    if (mapping.length && mappingPath.length) {
        wroteAnything = YES;
        if (![mapping writeToFile:mappingPath options:NSDataWritingAtomic error:nil]) success = NO;
    }

    // Export from the current live override state rather than blindly copying
    // an old imported sidecar. This makes Clear/Native actions remove supported
    // rows while still preserving mapping-only rows and _qe_overrides_.
    NSError *exportError = nil;
    NSData *overrides = [self ryg_exportOverridesData:&exportError];
    NSString *overridesPath = [self ryg_nativeOverridesJSONPath];
    if (overrides.length && overridesPath.length) {
        wroteAnything = YES;
        if (![overrides writeToFile:overridesPath options:NSDataWritingAtomic error:nil]) success = NO;
    } else if (exportError) {
        success = NO;
    }

    return wroteAnything && success;
}

@end
