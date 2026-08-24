#import "RYGCFunctionResolver.h"
#import <UIKit/UIKit.h>
#import <objc/runtime.h>
#import <mach-o/dyld.h>
#import <mach-o/loader.h>
#include <stdatomic.h>

static NSString *const kRYGCPersistedOverridesKey = @"ryg_runtime_c_predicate_overrides_v1";
static atomic_uint_fast64_t gRYGCRestoreGeneration = 0;

static NSString *RYGCUUIDForLoadedHeader(const struct mach_header_64 *header) {
    if (!header || !header->ncmds || header->sizeofcmds > 64 * 1024 * 1024) return nil;
    const uint8_t *cursor = (const uint8_t *)(header + 1);
    const uint8_t *end = cursor + header->sizeofcmds;
    for (uint32_t index = 0; index < header->ncmds; index++) {
        if (cursor + sizeof(struct load_command) > end) return nil;
        const struct load_command *command = (const struct load_command *)cursor;
        if (command->cmdsize < sizeof(*command) || cursor + command->cmdsize > end) return nil;
        if (command->cmd == LC_UUID && command->cmdsize >= sizeof(struct uuid_command)) {
            const unsigned char *u = ((const struct uuid_command *)cursor)->uuid;
            return [NSString stringWithFormat:@"%02X%02X%02X%02X-%02X%02X-%02X%02X-%02X%02X-%02X%02X%02X%02X%02X%02X",
                    u[0],u[1],u[2],u[3],u[4],u[5],u[6],u[7],u[8],u[9],u[10],u[11],u[12],u[13],u[14],u[15]];
        }
        cursor += command->cmdsize;
    }
    return nil;
}

static NSString *RYGCCurrentImagePathForUUID(NSString *wantedUUID) {
    if (!wantedUUID.length) return nil;
    uint32_t count = _dyld_image_count();
    for (uint32_t index = 0; index < count; index++) {
        const struct mach_header *rawHeader = _dyld_get_image_header(index);
        const char *rawPath = _dyld_get_image_name(index);
        if (!rawHeader || rawHeader->magic != MH_MAGIC_64 || !rawPath) continue;
        NSString *uuid = RYGCUUIDForLoadedHeader((const struct mach_header_64 *)rawHeader);
        if (![uuid.uppercaseString isEqualToString:wantedUUID.uppercaseString]) continue;
        return [NSString stringWithUTF8String:rawPath];
    }
    return nil;
}

static NSDictionary<NSString *, NSDictionary *> *RYGCPersistedSnapshot(void) {
    id raw = [NSUserDefaults.standardUserDefaults dictionaryForKey:kRYGCPersistedOverridesKey];
    return [raw isKindOfClass:NSDictionary.class] ? raw : @{};
}

static void RYGCSavePersisted(NSString *identity, RYGCFunctionRow *row, NSNumber *value) {
    if (!identity.length) return;
    NSMutableDictionary *next = [RYGCPersistedSnapshot() mutableCopy];
    if (!value) {
        [next removeObjectForKey:identity];
    } else {
        next[identity] = @{
            @"uuid": row.imageUUID ?: @"",
            @"symbol": row.symbolName ?: @"",
            @"fishhook": row.fishhookName ?: @"",
            @"value": @(value.boolValue),
            @"abi": @"predicate-v1",
        };
    }
    if (next.count) [NSUserDefaults.standardUserDefaults setObject:next.copy forKey:kRYGCPersistedOverridesKey];
    else [NSUserDefaults.standardUserDefaults removeObjectForKey:kRYGCPersistedOverridesKey];
}

static void RYGCRestorePersistedOverrides(void) {
    NSDictionary<NSString *, NSDictionary *> *snapshot = RYGCPersistedSnapshot();
    if (!snapshot.count) return;
    for (NSString *identity in snapshot) {
        NSDictionary *record = [snapshot[identity] isKindOfClass:NSDictionary.class] ? snapshot[identity] : nil;
        NSString *uuid = [record[@"uuid"] isKindOfClass:NSString.class] ? record[@"uuid"] : nil;
        NSString *symbol = [record[@"symbol"] isKindOfClass:NSString.class] ? record[@"symbol"] : nil;
        NSString *fishhook = [record[@"fishhook"] isKindOfClass:NSString.class] ? record[@"fishhook"] : nil;
        NSNumber *value = [record[@"value"] isKindOfClass:NSNumber.class] ? record[@"value"] : nil;
        if (!uuid.length || !symbol.length || !fishhook.length || !value || ![record[@"abi"] isEqual:@"predicate-v1"]) continue;
        NSString *imagePath = RYGCCurrentImagePathForUUID(uuid);
        if (!imagePath.length) continue;

        // Predicate evidence was proved before persistence and is valid only for
        // this exact LC_UUID. Replaying therefore needs no __text/symbol scan.
        RYGCFunctionRow *row = [RYGCFunctionRow new];
        row.imagePath = imagePath;
        row.imageUUID = uuid;
        row.symbolName = symbol;
        row.fishhookName = fishhook;
        row.predicateHookable = YES;
        row.evidence = @"Persisted ABI predicate proof · exact LC_UUID";
        NSError *error = nil;
        (void)[RYGCFunctionResolver setOverride:value forFunction:row error:&error];
    }
}

@interface RYGCFunctionResolver (RYGCPersistence)
+ (BOOL)ryg_persist_setOverride:(nullable NSNumber *)value forFunction:(RYGCFunctionRow *)function error:(NSError * _Nullable * _Nullable)error;
@end

@implementation RYGCFunctionResolver (RYGCPersistence)

+ (BOOL)ryg_persist_setOverride:(NSNumber *)value forFunction:(RYGCFunctionRow *)function error:(NSError **)error {
    // After exchange this selector addresses the resolver's native implementation.
    BOOL success = [self ryg_persist_setOverride:value forFunction:function error:error];
    if (success && function.identity.length) RYGCSavePersisted(function.identity, function, value);
    return success;
}

@end

static void RYGCScheduleExactRestore(NSTimeInterval delay) {
    if (!RYGCPersistedSnapshot().count) return;
    uint64_t generation = atomic_fetch_add_explicit(&gRYGCRestoreGeneration, 1, memory_order_acq_rel) + 1;
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(delay * NSEC_PER_SEC)), dispatch_get_global_queue(QOS_CLASS_UTILITY, 0), ^{
        if (generation != atomic_load_explicit(&gRYGCRestoreGeneration, memory_order_acquire)) return;
        @autoreleasepool { RYGCRestorePersistedOverrides(); }
    });
}

__attribute__((constructor(227))) static void RYGInstallCFunctionPersistence(void) {
    Class cls = RYGCFunctionResolver.class;
    Method original = class_getClassMethod(cls, @selector(setOverride:forFunction:error:));
    Method replacement = class_getClassMethod(cls, @selector(ryg_persist_setOverride:forFunction:error:));
    if (original && replacement && method_getNumberOfArguments(original) == method_getNumberOfArguments(replacement))
        method_exchangeImplementations(original, replacement);

    dispatch_async(dispatch_get_main_queue(), ^{
        [NSNotificationCenter.defaultCenter addObserverForName:UIApplicationDidFinishLaunchingNotification object:nil queue:NSOperationQueue.mainQueue usingBlock:^(__unused NSNotification *note) {
            RYGCScheduleExactRestore(0.7);
        }];
        [NSNotificationCenter.defaultCenter addObserverForName:UIApplicationDidBecomeActiveNotification object:nil queue:NSOperationQueue.mainQueue usingBlock:^(__unused NSNotification *note) {
            RYGCScheduleExactRestore(0.25);
        }];
    });
}
