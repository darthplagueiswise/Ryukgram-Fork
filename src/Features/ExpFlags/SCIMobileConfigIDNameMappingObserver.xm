#import "SCIMobileConfigMapping.h"
#import "SCIDexKitNameResolver.h"
#import <Foundation/Foundation.h>
#import <dlfcn.h>
#import <string>

extern "C" void MSHookFunction(void *symbol, void *replace, void **result);

static const char *kSCIMCStoragePersistExtraDataSymbol = "__ZN12mobileconfig28FBMobileConfigStorageManager16persistExtraDataERKNSt3__112basic_stringIcNS1_11char_traitsIcEENS1_9allocatorIcEEEES9_";

typedef void (*SCIMCStoragePersistExtraDataFn)(void *self, const std::string &key, const std::string &payload);
static SCIMCStoragePersistExtraDataFn orig_SCIMCStoragePersistExtraData = NULL;
static BOOL gSCIMCIDNameObserverInstalled = NO;

static NSString *SCIStringFromStdString(const std::string &value) {
    if (value.empty()) return @"";
    NSString *s = [[NSString alloc] initWithBytes:value.data()
                                          length:value.size()
                                        encoding:NSUTF8StringEncoding];
    return s ?: @"";
}

static NSData *SCIDataFromStdString(const std::string &value) {
    if (value.empty()) return nil;
    return [NSData dataWithBytes:value.data() length:value.size()];
}

static BOOL SCIDataLooksLikeJSON(NSData *data) {
    if (!data.length) return NO;
    const uint8_t *bytes = (const uint8_t *)data.bytes;
    NSUInteger len = data.length;
    for (NSUInteger i = 0; i < len && i < 4096; i++) {
        uint8_t c = bytes[i];
        if (c == ' ' || c == '\n' || c == '\r' || c == '\t') continue;
        return c == '[' || c == '{';
    }
    return NO;
}

static BOOL SCILooksLikeIDNameMappingPayload(NSString *key, NSData *payload) {
    NSString *lowerKey = key.lowercaseString ?: @"";
    if ([lowerKey containsString:@"id_name_mapping"]) return YES;
    if (!payload.length || payload.length < 16) return NO;
    if (payload.length > (64 * 1024 * 1024)) return NO;
    if (!SCIDataLooksLikeJSON(payload)) return NO;

    NSUInteger sampleLen = MIN((NSUInteger)8192, payload.length);
    NSString *sample = [[NSString alloc] initWithData:[payload subdataWithRange:NSMakeRange(0, sampleLen)]
                                             encoding:NSUTF8StringEncoding] ?: @"";
    NSString *lower = sample.lowercaseString ?: @"";
    if ([lower containsString:@"id_to_names"] || [lower containsString:@"idtonames"] || [lower containsString:@"id_name_mapping"]) return YES;
    if ([lower containsString:@"config_name"] || [lower containsString:@"param_name"] || [lower containsString:@"mappings"]) return YES;

    NSString *trimmed = [sample stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet];
    return [trimmed hasPrefix:@"["] && [lower containsString:@":"];
}

static void SCIRecordIDNameObserverStatus(NSString *source, NSString *key, NSString *path, NSUInteger bytes, NSString *errorText) {
    NSUserDefaults *ud = [NSUserDefaults standardUserDefaults];
    [ud setObject:source ?: @"" forKey:@"sci.mc.id_name_observer.source"];
    [ud setObject:key ?: @"" forKey:@"sci.mc.id_name_observer.key"];
    [ud setObject:path ?: @"" forKey:@"sci.mc.id_name_observer.path"];
    [ud setObject:@(bytes) forKey:@"sci.mc.id_name_observer.bytes"];
    [ud setObject:[NSDate date] forKey:@"sci.mc.id_name_observer.date"];
    if (errorText.length) [ud setObject:errorText forKey:@"sci.mc.id_name_observer.error"];
    else [ud removeObjectForKey:@"sci.mc.id_name_observer.error"];
    [ud synchronize];
}

static void SCIExportIDNameMappingPayload(NSString *source, NSString *key, NSData *payload) {
    if (!SCILooksLikeIDNameMappingPayload(key, payload)) return;

    NSError *jsonError = nil;
    id json = [NSJSONSerialization JSONObjectWithData:payload options:0 error:&jsonError];
    if (!json) {
        SCIRecordIDNameObserverStatus(source, key, @"", payload.length, jsonError.localizedDescription ?: @"invalid json");
        return;
    }

    NSString *path = [SCIMobileConfigMapping primaryIDNameMappingPath];
    if (!path.length) return;

    NSFileManager *fm = [NSFileManager defaultManager];
    [fm createDirectoryAtPath:path.stringByDeletingLastPathComponent withIntermediateDirectories:YES attributes:nil error:nil];

    BOOL ok = [payload writeToFile:path atomically:YES];
    SCIRecordIDNameObserverStatus(source, key, path, payload.length, ok ? nil : @"write failed");

    if (ok) {
        dispatch_async(dispatch_get_main_queue(), ^{
            [[NSNotificationCenter defaultCenter] postNotificationName:SCIDexKitNameResolverDidUpdateNotification object:nil];
        });
        NSLog(@"[RyukGram][MCIDName] exported id_name_mapping payload bytes=%@ source=%@ key=%@ path=%@", @(payload.length), source, key, path);
    }
}

static void hook_SCIMCStoragePersistExtraData(void *self, const std::string &key, const std::string &payload) {
    @autoreleasepool {
        @try {
            SCIExportIDNameMappingPayload(@"FBMobileConfigStorageManager.persistExtraData", SCIStringFromStdString(key), SCIDataFromStdString(payload));
        } @catch (__unused NSException *exception) {
        }
    }

    if (orig_SCIMCStoragePersistExtraData) {
        orig_SCIMCStoragePersistExtraData(self, key, payload);
    }
}

static void SCIInstallIDNameMappingObserverAttempt(NSUInteger attempt) {
    if (gSCIMCIDNameObserverInstalled) return;

    void *target = dlsym(RTLD_DEFAULT, kSCIMCStoragePersistExtraDataSymbol);
    if (!target) {
        if (attempt < 20) {
            dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.5 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
                SCIInstallIDNameMappingObserverAttempt(attempt + 1);
            });
        } else {
            NSLog(@"[RyukGram][MCIDName] persistExtraData symbol not loaded");
        }
        return;
    }

    gSCIMCIDNameObserverInstalled = YES;
    MSHookFunction(target, (void *)&hook_SCIMCStoragePersistExtraData, (void **)&orig_SCIMCStoragePersistExtraData);
    NSLog(@"[RyukGram][MCIDName] pass-through observer installed target=%p", target);
}

%ctor {
    @autoreleasepool {
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.1 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
            SCIInstallIDNameMappingObserverAttempt(0);
        });
    }
}
