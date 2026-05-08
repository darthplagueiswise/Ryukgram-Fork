#import "SCIMobileConfigMapping.h"
#import "SCIMobileConfigIdNameMappingExporter.h"
#import "SCIDexKitNameResolver.h"
#import <Foundation/Foundation.h>
#import <dlfcn.h>
#import <mach-o/dyld.h>
#import "../../../modules/fishhook/fishhook.h"

static const char *kSCIMCIdNameGetFilePathSymbol = "__ZN12mobileconfig23FBMobileConfigIdNameMap19getIdToNameFilePathERKNSt3__112basic_stringIcNS1_11char_traitsIcEENS1_9allocatorIcEEEE";
static const char *kSCIMCIdNameTryGetNamedParamsListSymbol = "__ZN12mobileconfig23FBMobileConfigIdNameMap21tryGetNamedParamsListERKNSt3__110shared_ptrIKNS1_6vectorINS_13config_meta_tENS1_9allocatorIS4_EEEEEERKNS1_12basic_stringIcNS1_11char_traitsIcEENS5_IcEEEE";
static const char *kSCIMCStorageReadExtraDataSymbol = "__ZN12mobileconfig28FBMobileConfigStorageManager13readExtraDataERKNSt3__112basic_stringIcNS1_11char_traitsIcEENS1_9allocatorIcEEEE";
static const char *kSCIMCStoragePersistExtraDataSymbol = "__ZN12mobileconfig28FBMobileConfigStorageManager16persistExtraDataERKNSt3__112basic_stringIcNS1_11char_traitsIcEENS1_9allocatorIcEEEES9_";

// Public export wrapper in FBSharedFramework starts as:
//   mov w4, #0
//   b   worker
// The import observer therefore treats x0-x3 as raw/pass-through arguments and
// preserves x0 as a raw uintptr_t return. It does not call the export directly.
typedef uintptr_t (*SCIIGTryUpdateImportFn)(void *arg0, void *arg1, void *arg2, void *arg3);
static SCIIGTryUpdateImportFn orig_SCIIGTryUpdateImport = NULL;
static BOOL gSCITryUpdateImportInstalled = NO;
static NSUInteger gSCITryUpdateImportCalls = 0;

static void SCISetObserverStatus(NSString *status, NSDictionary<NSString *, id> *extra) {
    NSUserDefaults *ud = [NSUserDefaults standardUserDefaults];
    [ud setObject:status ?: @"" forKey:@"sci.mc.id_name_observer.status"];
    [ud setObject:extra ?: @{} forKey:@"sci.mc.id_name_observer.extra"];
    [ud setObject:[SCIMobileConfigMapping primaryIDNameMappingPath] ?: @"" forKey:@"sci.mc.id_name_observer.path"];
    [ud setObject:[NSDate date] forKey:@"sci.mc.id_name_observer.date"];
    [ud synchronize];
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

static void SCIScanIDMapAfterTryUpdate(NSString *source) {
    dispatch_async(dispatch_get_global_queue(QOS_CLASS_UTILITY, 0), ^{
        NSDictionary *result = [SCIMobileConfigIdNameMappingExporter exportIDNameMappingNow];
        NSString *status = result[@"status"] ?: @"id_name_mapping scan completed";
        SCISetObserverStatus([NSString stringWithFormat:@"%@ · after %@", status, source ?: @"TryUpdate"], result ?: @{});
        [[NSNotificationCenter defaultCenter] postNotificationName:SCIMobileConfigIdNameMappingExporterDidUpdateNotification object:nil];
        [[NSNotificationCenter defaultCenter] postNotificationName:SCIDexKitNameResolverDidUpdateNotification object:nil];
    });
}

static uintptr_t SCIIGTryUpdateImportObserver(void *arg0, void *arg1, void *arg2, void *arg3) {
    gSCITryUpdateImportCalls++;
    NSDictionary *raw = @{
        @"mode": @"fishhook-import-only",
        @"calls": @(gSCITryUpdateImportCalls),
        @"arg0": [NSString stringWithFormat:@"%p", arg0],
        @"arg1": [NSString stringWithFormat:@"%p", arg1],
        @"arg2": [NSString stringWithFormat:@"%p", arg2],
        @"arg3": [NSString stringWithFormat:@"%p", arg3],
        @"completion": @"raw pointer only; not wrapped until block ABI is validated"
    };
    SCISetObserverStatus(@"IGMobileConfigTryUpdateConfigsWithCompletion import observed", raw);

    uintptr_t ret = 0;
    if (orig_SCIIGTryUpdateImport) {
        ret = orig_SCIIGTryUpdateImport(arg0, arg1, arg2, arg3);
    }

    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(1.0 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
        SCIScanIDMapAfterTryUpdate(@"TryUpdate+1s");
    });
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(3.0 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
        SCIScanIDMapAfterTryUpdate(@"TryUpdate+3s");
    });

    return ret;
}

static void SCIInstallTryUpdateImportObserver(void) {
    if (gSCITryUpdateImportInstalled) return;

    const struct mach_header *header = _dyld_get_image_header(0);
    intptr_t slide = _dyld_get_image_vmaddr_slide(0);
    const char *imageName = _dyld_get_image_name(0);
    if (!header) {
        SCISetObserverStatus(@"TryUpdate import observer not installed · no main image header", @{});
        return;
    }

    struct rebinding rb;
    rb.name = "IGMobileConfigTryUpdateConfigsWithCompletion";
    rb.replacement = (void *)&SCIIGTryUpdateImportObserver;
    rb.replaced = (void **)&orig_SCIIGTryUpdateImport;

    int rc = rebind_symbols_image((void *)header, slide, &rb, 1);
    gSCITryUpdateImportInstalled = (rc == 0 && orig_SCIIGTryUpdateImport != NULL);

    NSDictionary *symbols = SCIProbeIDNameMappingSymbols();
    NSMutableDictionary *statusInfo = [symbols mutableCopy] ?: [NSMutableDictionary dictionary];
    statusInfo[@"tryUpdateImport"] = gSCITryUpdateImportInstalled ? @"installed" : @"not-imported-or-not-rebound";
    statusInfo[@"mainImage"] = imageName ? [NSString stringWithUTF8String:imageName] : @"unknown";
    statusInfo[@"fishhookResult"] = @(rc);
    statusInfo[@"originalImport"] = orig_SCIIGTryUpdateImport ? [NSString stringWithFormat:@"%p", orig_SCIIGTryUpdateImport] : @"none";

    NSString *status = [NSString stringWithFormat:@"id_name_mapping observer ready · C++ body hooks disabled · TryUpdate import %@ · primary=%@",
                        gSCITryUpdateImportInstalled ? @"observed" : @"not found",
                        [SCIMobileConfigMapping primaryIDNameMappingPath] ?: @""];
    SCISetObserverStatus(status, statusInfo);
    NSLog(@"[RyukGram][MCIDName] %@", status);
}

%ctor {
    @autoreleasepool {
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.2 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
            SCIInstallTryUpdateImportObserver();
        });
    }
}
