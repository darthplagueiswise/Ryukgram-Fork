#import "RYGMobileConfig.h"
#import "RYGMobileConfigNameMappingStore.h"

@implementation RYGMobileConfig (RYGBackupCompatibility)

+ (NSString *)storageDirectory {
    NSString *support = NSSearchPathForDirectoriesInDomains(NSApplicationSupportDirectory,
                                                              NSUserDomainMask,
                                                              YES).firstObject;
    if (!support.length) support = [NSHomeDirectory() stringByAppendingPathComponent:@"Library/Application Support"];
    NSString *directory = [support stringByAppendingPathComponent:@"RyukGram"];
    [NSFileManager.defaultManager createDirectoryAtPath:directory
                            withIntermediateDirectories:YES
                                             attributes:nil
                                                  error:nil];
    return directory;
}

+ (NSArray<NSString *> *)ryg_ownedBackupRelativePaths {
    return @[
        @"mc_overrides.plist",
        @"mc_notes.plist",
        @"mc_overrides_canonical.json",
        @"MobileConfig/id_name_mapping.json",
    ];
}

+ (void)resetStore {
    RYGMobileConfig *shared = self.shared;
    [shared resetAllOverrides];
    NSString *root = [self storageDirectory];
    NSFileManager *fm = NSFileManager.defaultManager;
    for (NSString *relative in [self ryg_ownedBackupRelativePaths])
        [fm removeItemAtPath:[root stringByAppendingPathComponent:relative] error:nil];
    [shared reloadFromRuntime];
}

+ (void)mergeImportedStoreAtPath:(NSString *)path {
    if (!path.length) return;
    NSFileManager *fm = NSFileManager.defaultManager;
    BOOL isDirectory = NO;
    if (![fm fileExistsAtPath:path isDirectory:&isDirectory] || !isDirectory) return;

    NSString *destinationRoot = [self storageDirectory];
    for (NSString *relative in [self ryg_ownedBackupRelativePaths]) {
        NSString *source = [path stringByAppendingPathComponent:relative];
        BOOL sourceDirectory = NO;
        if (![fm fileExistsAtPath:source isDirectory:&sourceDirectory] || sourceDirectory) continue;
        NSString *destination = [destinationRoot stringByAppendingPathComponent:relative];
        [fm createDirectoryAtPath:destination.stringByDeletingLastPathComponent
      withIntermediateDirectories:YES
                       attributes:nil
                            error:nil];
        NSData *data = [NSData dataWithContentsOfFile:source options:0 error:nil];
        if (data.length) [data writeToFile:destination options:NSDataWritingAtomic error:nil];
    }
}

+ (void)reloadStoreFromDisk {
    RYGMobileConfig *shared = self.shared;
    NSString *plistPath = [[self storageDirectory] stringByAppendingPathComponent:@"mc_overrides.plist"];
    NSDictionary *disk = [NSDictionary dictionaryWithContentsOfFile:plistPath] ?: @{};
    NSMutableDictionary<NSNumber *, id> *clean = [NSMutableDictionary dictionary];
    [disk enumerateKeysAndObjectsUsingBlock:^(id rawKey, id value, BOOL *stop) {
        (void)stop;
        if (![rawKey isKindOfClass:NSString.class]) return;
        const char *digits = [(NSString *)rawKey UTF8String];
        if (!digits || !*digits || *digits == '-') return;
        char *end = NULL;
        unsigned long long pid = strtoull(digits, &end, 10);
        if (end == digits || *end != '\0' || !pid) return;
        RYGMCType type = (RYGMCType)((pid >> 48) & 0x0f);
        BOOL valid = type == RYGMCTypeString ? [value isKindOfClass:NSString.class] :
                     (type == RYGMCTypeBool || type == RYGMCTypeInt || type == RYGMCTypeDouble) && [value isKindOfClass:NSNumber.class];
        if (valid) clean[@(pid)] = value;
    }];

    // KVC writes the canonical owner's private _overrides ivar; no second store
    // object/backend is created. This compatibility path runs only during an
    // explicit backup restore.
    @try { [shared setValue:clean forKey:@"overrides"]; } @catch (__unused NSException *exception) {}
    [shared reloadFromRuntime];
    [shared reapplyOverridesToNativeTable];
}

@end
