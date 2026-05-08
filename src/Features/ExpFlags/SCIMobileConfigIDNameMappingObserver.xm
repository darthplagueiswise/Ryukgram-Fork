#import "SCIMobileConfigMapping.h"
#import "SCIDexKitNameResolver.h"
#import <Foundation/Foundation.h>
#import <dlfcn.h>
#import <memory>
#import <string>
#import <vector>

extern "C" void MSHookFunction(void *symbol, void *replace, void **result);

namespace mobileconfig { struct config_meta_t; }
typedef std::shared_ptr<const std::vector<mobileconfig::config_meta_t>> SCIMCConfigMetaListPtr;

static const char *kSCIMCIdNameGetFilePathSymbol = "__ZN12mobileconfig23FBMobileConfigIdNameMap19getIdToNameFilePathERKNSt3__112basic_stringIcNS1_11char_traitsIcEENS1_9allocatorIcEEEE";
static const char *kSCIMCIdNameTryGetNamedParamsListSymbol = "__ZN12mobileconfig23FBMobileConfigIdNameMap21tryGetNamedParamsListERKNSt3__110shared_ptrIKNS1_6vectorINS_13config_meta_tENS1_9allocatorIS4_EEEEEERKNS1_12basic_stringIcNS1_11char_traitsIcEENS5_IcEEEE";
static const char *kSCIMCStorageReadExtraDataSymbol = "__ZN12mobileconfig28FBMobileConfigStorageManager13readExtraDataERKNSt3__112basic_stringIcNS1_11char_traitsIcEENS1_9allocatorIcEEEE";
static const char *kSCIMCStoragePersistExtraDataSymbol = "__ZN12mobileconfig28FBMobileConfigStorageManager16persistExtraDataERKNSt3__112basic_stringIcNS1_11char_traitsIcEENS1_9allocatorIcEEEES9_";

typedef std::string (*SCIMCIdNameGetFilePathFn)(const std::string &root);
typedef SCIMCConfigMetaListPtr (*SCIMCIdNameTryGetNamedParamsListFn)(const SCIMCConfigMetaListPtr &params, const std::string &path);
typedef std::string (*SCIMCStorageReadExtraDataFn)(void *self, const std::string &key);
typedef void (*SCIMCStoragePersistExtraDataFn)(void *self, const std::string &key, const std::string &payload);

static SCIMCIdNameGetFilePathFn orig_SCIMCIdNameGetFilePath = NULL;
static SCIMCIdNameTryGetNamedParamsListFn orig_SCIMCIdNameTryGetNamedParamsList = NULL;
static SCIMCStorageReadExtraDataFn orig_SCIMCStorageReadExtraData = NULL;
static SCIMCStoragePersistExtraDataFn orig_SCIMCStoragePersistExtraData = NULL;

static BOOL gSCIMCIdNameGetFilePathInstalled = NO;
static BOOL gSCIMCIdNameTryGetNamedParamsListInstalled = NO;
static BOOL gSCIMCStorageReadExtraDataInstalled = NO;
static BOOL gSCIMCStoragePersistExtraDataInstalled = NO;

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

static BOOL SCIKeyLooksLikeIDNameMapping(NSString *key) {
    NSString *lowerKey = key.lowercaseString ?: @"";
    return [lowerKey containsString:@"id_name_mapping"] || [lowerKey containsString:@"id-name-mapping"] || [lowerKey containsString:@"idnamemapping"];
}

static BOOL SCILooksLikeIDNameMappingPayload(NSString *key, NSData *payload) {
    if (SCIKeyLooksLikeIDNameMapping(key)) return YES;
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
    if (!payload.length) return;
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

static void SCITryExportIDNameMappingFile(NSString *source, NSString *path) {
    if (!SCIKeyLooksLikeIDNameMapping(path)) return;

    BOOL isDir = NO;
    NSFileManager *fm = [NSFileManager defaultManager];
    if (![fm fileExistsAtPath:path isDirectory:&isDir] || isDir) {
        NSLog(@"[RyukGram][MCIDName] observed mapping path not readable yet source=%@ path=%@", source, path);
        return;
    }

    NSData *payload = [NSData dataWithContentsOfFile:path];
    if (!payload.length) {
        NSLog(@"[RyukGram][MCIDName] observed mapping path empty source=%@ path=%@", source, path);
        return;
    }

    SCIExportIDNameMappingPayload(source, path, payload);
}

static NSString *SCIInstalledSummary(void) {
    return [NSString stringWithFormat:@"getPath=%@ tryNamed=%@ readExtra=%@ persistExtra=%@",
            gSCIMCIdNameGetFilePathInstalled ? @"yes" : @"no",
            gSCIMCIdNameTryGetNamedParamsListInstalled ? @"yes" : @"no",
            gSCIMCStorageReadExtraDataInstalled ? @"yes" : @"no",
            gSCIMCStoragePersistExtraDataInstalled ? @"yes" : @"no"];
}

static BOOL SCIAllIDNameObserversInstalled(void) {
    return gSCIMCIdNameGetFilePathInstalled &&
           gSCIMCIdNameTryGetNamedParamsListInstalled &&
           gSCIMCStorageReadExtraDataInstalled &&
           gSCIMCStoragePersistExtraDataInstalled;
}

static BOOL SCIInstallIDNameObserverSymbol(const char *symbol, void *replacement, void **original, BOOL *installed, NSString *label) {
    if (*installed) return YES;

    void *target = dlsym(RTLD_DEFAULT, symbol);
    if (!target) return NO;

    *installed = YES;
    MSHookFunction(target, replacement, original);
    NSLog(@"[RyukGram][MCIDName] %@ pass-through observer installed target=%p", label, target);
    return YES;
}

static std::string hook_SCIMCIdNameGetFilePath(const std::string &root) {
    std::string path;
    if (orig_SCIMCIdNameGetFilePath) {
        path = orig_SCIMCIdNameGetFilePath(root);
    }

    @autoreleasepool {
        @try {
            NSString *pathString = SCIStringFromStdString(path);
            if (pathString.length) {
                NSLog(@"[RyukGram][MCIDName] getIdToNameFilePath path=%@ root=%@", pathString, SCIStringFromStdString(root));
                SCITryExportIDNameMappingFile(@"FBMobileConfigIdNameMap.getIdToNameFilePath", pathString);
            }
        } @catch (__unused NSException *exception) {
        }
    }

    return path;
}

static SCIMCConfigMetaListPtr hook_SCIMCIdNameTryGetNamedParamsList(const SCIMCConfigMetaListPtr &params, const std::string &path) {
    SCIMCConfigMetaListPtr result;
    if (orig_SCIMCIdNameTryGetNamedParamsList) {
        result = orig_SCIMCIdNameTryGetNamedParamsList(params, path);
    }

    @autoreleasepool {
        @try {
            NSString *pathString = SCIStringFromStdString(path);
            if (pathString.length) {
                NSLog(@"[RyukGram][MCIDName] tryGetNamedParamsList path=%@", pathString);
                SCITryExportIDNameMappingFile(@"FBMobileConfigIdNameMap.tryGetNamedParamsList", pathString);
            }
        } @catch (__unused NSException *exception) {
        }
    }

    return result;
}

static std::string hook_SCIMCStorageReadExtraData(void *self, const std::string &key) {
    std::string payload;
    if (orig_SCIMCStorageReadExtraData) {
        payload = orig_SCIMCStorageReadExtraData(self, key);
    }

    @autoreleasepool {
        @try {
            SCIExportIDNameMappingPayload(@"FBMobileConfigStorageManager.readExtraData", SCIStringFromStdString(key), SCIDataFromStdString(payload));
        } @catch (__unused NSException *exception) {
        }
    }

    return payload;
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
    if (SCIAllIDNameObserversInstalled()) return;

    SCIInstallIDNameObserverSymbol(kSCIMCIdNameGetFilePathSymbol,
                                   (void *)&hook_SCIMCIdNameGetFilePath,
                                   (void **)&orig_SCIMCIdNameGetFilePath,
                                   &gSCIMCIdNameGetFilePathInstalled,
                                   @"FBMobileConfigIdNameMap.getIdToNameFilePath");

    SCIInstallIDNameObserverSymbol(kSCIMCIdNameTryGetNamedParamsListSymbol,
                                   (void *)&hook_SCIMCIdNameTryGetNamedParamsList,
                                   (void **)&orig_SCIMCIdNameTryGetNamedParamsList,
                                   &gSCIMCIdNameTryGetNamedParamsListInstalled,
                                   @"FBMobileConfigIdNameMap.tryGetNamedParamsList");

    SCIInstallIDNameObserverSymbol(kSCIMCStorageReadExtraDataSymbol,
                                   (void *)&hook_SCIMCStorageReadExtraData,
                                   (void **)&orig_SCIMCStorageReadExtraData,
                                   &gSCIMCStorageReadExtraDataInstalled,
                                   @"FBMobileConfigStorageManager.readExtraData");

    SCIInstallIDNameObserverSymbol(kSCIMCStoragePersistExtraDataSymbol,
                                   (void *)&hook_SCIMCStoragePersistExtraData,
                                   (void **)&orig_SCIMCStoragePersistExtraData,
                                   &gSCIMCStoragePersistExtraDataInstalled,
                                   @"FBMobileConfigStorageManager.persistExtraData");

    if (!SCIAllIDNameObserversInstalled()) {
        if (attempt < 20) {
            dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.5 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
                SCIInstallIDNameMappingObserverAttempt(attempt + 1);
            });
        } else {
            NSLog(@"[RyukGram][MCIDName] observer install incomplete: %@", SCIInstalledSummary());
        }
        return;
    }

    NSLog(@"[RyukGram][MCIDName] all pass-through observers installed: %@", SCIInstalledSummary());
}

%ctor {
    @autoreleasepool {
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.1 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
            SCIInstallIDNameMappingObserverAttempt(0);
        });
    }
}
