#import "SCIMobileConfigMapping.h"
#import "SCIDexKitNameResolver.h"
#import <Foundation/Foundation.h>
#import <dlfcn.h>

static const char *kSCIMCIdNameGetFilePathSymbol = "__ZN12mobileconfig23FBMobileConfigIdNameMap19getIdToNameFilePathERKNSt3__112basic_stringIcNS1_11char_traitsIcEENS1_9allocatorIcEEEE";
static const char *kSCIMCIdNameTryGetNamedParamsListSymbol = "__ZN12mobileconfig23FBMobileConfigIdNameMap21tryGetNamedParamsListERKNSt3__110shared_ptrIKNS1_6vectorINS_13config_meta_tENS1_9allocatorIS4_EEEEEERKNS1_12basic_stringIcNS1_11char_traitsIcEENS5_IcEEEE";
static const char *kSCIMCStorageReadExtraDataSymbol = "__ZN12mobileconfig28FBMobileConfigStorageManager13readExtraDataERKNSt3__112basic_stringIcNS1_11char_traitsIcEENS1_9allocatorIcEEEE";
static const char *kSCIMCStoragePersistExtraDataSymbol = "__ZN12mobileconfig28FBMobileConfigStorageManager16persistExtraDataERKNSt3__112basic_stringIcNS1_11char_traitsIcEENS1_9allocatorIcEEEES9_";

static NSDictionary<NSString *, id> *SCIProbeIDNameMappingSymbols(void) {
    NSMutableDictionary<NSString *, id> *out = [NSMutableDictionary dictionary];
    struct Entry { const char *label; const char *symbol; } entries[] = {
        {"FBMobileConfigIdNameMap.getIdToNameFilePath", kSCIMCIdNameGetFilePathSymbol},
        {"FBMobileConfigIdNameMap.tryGetNamedParamsList", kSCIMCIdNameTryGetNamedParamsListSymbol},
        {"FBMobileConfigStorageManager.readExtraData", kSCIMCStorageReadExtraDataSymbol},
        {"FBMobileConfigStorageManager.persistExtraData", kSCIMCStoragePersistExtraDataSymbol},
    };

    for (NSUInteger i = 0; i < sizeof(entries) / sizeof(entries[0]); i++) {
        void *target = dlsym(RTLD_DEFAULT, entries[i].symbol);
        NSString *label = [NSString stringWithUTF8String:entries[i].label] ?: @"unknown";
        out[label] = target ? [NSString stringWithFormat:@"%p", target] : @"not-loaded";
    }
    return out;
}

static void SCIRecordIDNameObserverProbe(void) {
    NSDictionary<NSString *, id> *symbols = SCIProbeIDNameMappingSymbols();
    NSUInteger loaded = 0;
    for (id value in symbols.allValues) {
        if ([value isKindOfClass:NSString.class] && ![(NSString *)value isEqualToString:@"not-loaded"]) loaded++;
    }

    NSString *status = [NSString stringWithFormat:@"id_name_mapping observer probe only · symbols=%lu/%lu · C/C++ body hooks disabled for sideload safety · primary=%@",
                        (unsigned long)loaded,
                        (unsigned long)symbols.count,
                        [SCIMobileConfigMapping primaryIDNameMappingPath] ?: @""];

    NSUserDefaults *ud = [NSUserDefaults standardUserDefaults];
    [ud setObject:status ?: @"" forKey:@"sci.mc.id_name_observer.status"];
    [ud setObject:symbols ?: @{} forKey:@"sci.mc.id_name_observer.symbols"];
    [ud setObject:[SCIMobileConfigMapping primaryIDNameMappingPath] ?: @"" forKey:@"sci.mc.id_name_observer.path"];
    [ud setObject:[NSDate date] forKey:@"sci.mc.id_name_observer.date"];
    [ud removeObjectForKey:@"sci.mc.id_name_observer.error"];
    [ud synchronize];

    NSLog(@"[RyukGram][MCIDName] %@", status);
}

%ctor {
    @autoreleasepool {
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.1 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
            SCIRecordIDNameObserverProbe();
            [[NSNotificationCenter defaultCenter] postNotificationName:SCIDexKitNameResolverDidUpdateNotification object:nil];
        });
    }
}
