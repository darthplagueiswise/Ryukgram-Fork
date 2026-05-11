#import "SCIMobileConfigMapping.h"
#import "SCIMobileConfigIdNameMappingExporter.h"
#import "SCIDexKitNameResolver.h"
#import <Foundation/Foundation.h>
#import <dlfcn.h>

static const char *kSCIMCIdNameGetFilePathSymbol = "__ZN12mobileconfig23FBMobileConfigIdNameMap19getIdToNameFilePathERKNSt3__112basic_stringIcNS1_11char_traitsIcEENS1_9allocatorIcEEEE";
static const char *kSCIMCIdNameTryGetNamedParamsListSymbol = "__ZN12mobileconfig23FBMobileConfigIdNameMap21tryGetNamedParamsListERKNSt3__110shared_ptrIKNS1_6vectorINS_13config_meta_tENS1_9allocatorIS4_EEEEEERKNS1_12basic_stringIcNS1_11char_traitsIcEENS5_IcEEEE";
static const char *kSCIMCStorageReadExtraDataSymbol = "__ZN12mobileconfig28FBMobileConfigStorageManager13readExtraDataERKNSt3__112basic_stringIcNS1_11char_traitsIcEENS1_9allocatorIcEEEE";
static const char *kSCIMCStoragePersistExtraDataSymbol = "__ZN12mobileconfig28FBMobileConfigStorageManager16persistExtraDataERKNSt3__112basic_stringIcNS1_11char_traitsIcEENS1_9allocatorIcEEEES9_";

static void SCISetObserverStatus(NSString *status, NSDictionary<NSString *, id> *extra) {
    NSUserDefaults *ud = [NSUserDefaults standardUserDefaults];
    [ud setObject:status ?: @"" forKey:@"sci.mc.id_name_observer.status"];
    [ud setObject:extra ?: @{} forKey:@"sci.mc.id_name_observer.extra"];
    [ud setObject:[SCIMobileConfigMapping primaryIDNameMappingPath] ?: @"" forKey:@"sci.mc.id_name_observer.path"];
    [ud setObject:[NSDate date] forKey:@"sci.mc.id_name_observer.date"];
}

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

__attribute__((visibility("default")))
void SCIInstallMobileConfigIDNameMappingObserver(void) {
    NSDictionary *symbols = SCIProbeIDNameMappingSymbols();
    SCISetObserverStatus(@"id_name_mapping observer disabled; passive scan only", symbols ?: @{});
    NSLog(@"[RyukGram][MCIDName] TryUpdate observer disabled; passive scan only");
}

__attribute__((visibility("default")))
void SCIInstallMobileConfigIDNameMappingObserverIfNeeded(void) {
    SCIInstallMobileConfigIDNameMappingObserver();
}

__attribute__((visibility("default")))
BOOL SCIIsMobileConfigIDNameMappingObserverInstalled(void) {
    return NO;
}

%ctor {
    // Startup inert: no TryUpdate hook, no C++ calls, no delayed scan.
}
