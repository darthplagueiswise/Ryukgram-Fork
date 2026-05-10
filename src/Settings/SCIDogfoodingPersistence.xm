#import <UIKit/UIKit.h>
#import <Foundation/Foundation.h>
#import <objc/runtime.h>
#import <objc/message.h>
#import <substrate.h>
#import <dlfcn.h>
#import <string>
#import "../Features/ExpFlags/SCIMobileConfigMapping.h"
#import "../Features/ExpFlags/SCIDexKitNameResolver.h"

// alpha3 fix:
// 1. The old implementation walked arbitrary object graphs and sent selectors such as
//    apply/persist/commit/flush to unknown native objects. That can execute the wrong
//    method on the wrong object and cannot be protected by @try when the crash is a
//    native EXC_BAD_ACCESS. This file is now a strict pass-through observer.
// 2. DirectNotes dogfooding persistence is observed around native table selections only.
//    No return values are changed and no native settings objects are force-applied.
// 3. The id_name_mapping exporter observes MobileConfigStorageManager::persistExtraData
//    and writes the server-provided mapping to NSHomeDirectory()/mobileconfig.

static void (*origSCIDogMainViewDidDisappear)(id self, SEL _cmd, BOOL animated);
static void (*origSCIDogSelectionViewDidDisappear)(id self, SEL _cmd, BOOL animated);
static void (*origSCIDogMainDidSelect)(id self, SEL _cmd, id tableView, NSIndexPath *indexPath);
static void (*origSCIDogSelectionDidSelect)(id self, SEL _cmd, id tableView, NSIndexPath *indexPath);

static NSString * const kSCIDogCrashActiveKey = @"sci.dogfooding.crash_guard.active";
static NSString * const kSCIDogCrashTrippedKey = @"sci.dogfooding.crash_guard.tripped";
static NSString * const kSCIDogCrashReasonKey = @"sci.dogfooding.crash_guard.reason";
static NSString * const kSCIDogCrashDateKey = @"sci.dogfooding.crash_guard.date";
static NSString * const kSCIDogCrashDisableKey = @"sci.dogfooding.persistence.disabled";

static NSString *SCIDogClassName(id obj) {
    if (!obj) return @"nil";
    return NSStringFromClass([obj class]) ?: @"?";
}

static BOOL SCIDogCrashGuardTripped(void) {
    NSUserDefaults *ud = [NSUserDefaults standardUserDefaults];
    if ([ud boolForKey:kSCIDogCrashDisableKey]) return YES;
    if (![ud boolForKey:kSCIDogCrashTrippedKey]) return NO;
    NSDate *date = [ud objectForKey:kSCIDogCrashDateKey];
    if ([date isKindOfClass:NSDate.class] && fabs(date.timeIntervalSinceNow) > 3600.0) {
        [ud removeObjectForKey:kSCIDogCrashTrippedKey];
        [ud removeObjectForKey:kSCIDogCrashReasonKey];
        [ud removeObjectForKey:kSCIDogCrashDateKey];
        [ud synchronize];
        return NO;
    }
    return YES;
}

static void SCIDogCrashGuardBootstrap(void) {
    NSUserDefaults *ud = [NSUserDefaults standardUserDefaults];
    if ([ud boolForKey:kSCIDogCrashActiveKey]) {
        NSString *reason = [ud stringForKey:kSCIDogCrashReasonKey] ?: @"previous dogfooding operation did not finish";
        [ud setBool:YES forKey:kSCIDogCrashTrippedKey];
        [ud setObject:[NSDate date] forKey:kSCIDogCrashDateKey];
        [ud setObject:reason forKey:kSCIDogCrashReasonKey];
        [ud setBool:YES forKey:kSCIDogCrashDisableKey];
        [ud removeObjectForKey:kSCIDogCrashActiveKey];
        [ud synchronize];
        NSLog(@"[RyukGram][DogfoodPersist] crash guard tripped; disabled persistence hooks reason=%@", reason);
    }
}

static void SCIDogCrashGuardBegin(NSString *reason) {
    NSUserDefaults *ud = [NSUserDefaults standardUserDefaults];
    [ud setBool:YES forKey:kSCIDogCrashActiveKey];
    [ud setObject:reason ?: @"dogfooding selection" forKey:kSCIDogCrashReasonKey];
    [ud setObject:[NSDate date] forKey:kSCIDogCrashDateKey];
    [ud synchronize];
}

static void SCIDogCrashGuardEnd(void) {
    NSUserDefaults *ud = [NSUserDefaults standardUserDefaults];
    [ud removeObjectForKey:kSCIDogCrashActiveKey];
    [ud synchronize];
}

static void SCIDogNativeFlushAfterSelection(id root, NSString *reason) {
    (void)root;
    [[NSUserDefaults standardUserDefaults] synchronize];
    CFPreferencesAppSynchronize(kCFPreferencesCurrentApplication);
    NSLog(@"[RyukGram][DogfoodPersist] pass-through selection observed reason=%@", reason ?: @"?");
}

static void hookSCIDogMainViewDidDisappear(id self, SEL _cmd, BOOL animated) {
    if (origSCIDogMainViewDidDisappear) origSCIDogMainViewDidDisappear(self, _cmd, animated);
    SCIDogNativeFlushAfterSelection(self, @"main viewDidDisappear");
}

static void hookSCIDogSelectionViewDidDisappear(id self, SEL _cmd, BOOL animated) {
    if (origSCIDogSelectionViewDidDisappear) origSCIDogSelectionViewDidDisappear(self, _cmd, animated);
    SCIDogNativeFlushAfterSelection(self, @"selection viewDidDisappear");
}

static void hookSCIDogMainDidSelect(id self, SEL _cmd, id tableView, NSIndexPath *indexPath) {
    SCIDogCrashGuardBegin(@"main tableView:didSelectRowAtIndexPath:");
    if (origSCIDogMainDidSelect) origSCIDogMainDidSelect(self, _cmd, tableView, indexPath);
    SCIDogNativeFlushAfterSelection(self, @"main didSelect");
    SCIDogCrashGuardEnd();
}

static void hookSCIDogSelectionDidSelect(id self, SEL _cmd, id tableView, NSIndexPath *indexPath) {
    SCIDogCrashGuardBegin(@"selection tableView:didSelectRowAtIndexPath:");
    if (origSCIDogSelectionDidSelect) origSCIDogSelectionDidSelect(self, _cmd, tableView, indexPath);
    SCIDogNativeFlushAfterSelection(self, @"selection didSelect");
    SCIDogCrashGuardEnd();
}

static Class SCIDogResolveClass(NSArray<NSString *> *names) {
    for (NSString *name in names) {
        if (!name.length) continue;
        Class cls = NSClassFromString(name);
        if (cls) return cls;
        cls = (Class)objc_getClass(name.UTF8String);
        if (cls) return cls;
    }
    return Nil;
}

static void SCIDogHookClassMethodIfPresent(Class cls, SEL sel, IMP hook, IMP *orig) {
    if (!cls || !sel || !hook || !orig || *orig) return;
    Method m = class_getInstanceMethod(cls, sel);
    if (!m) return;
    MSHookMessageEx(cls, sel, hook, orig);
}

static void SCIDogInstallPersistenceHooks(void) {
    if (SCIDogCrashGuardTripped()) {
        NSLog(@"[RyukGram][DogfoodPersist] persistence hooks skipped by crash guard");
        return;
    }

    Class mainVC = SCIDogResolveClass(@[
        @"IGDogfoodingSettings.IGDogfoodingSettingsViewController",
        @"IGDogfoodingSettingsViewController",
        @"_TtC20IGDogfoodingSettings34IGDogfoodingSettingsViewController"
    ]);

    Class selectionVC = SCIDogResolveClass(@[
        @"IGDogfoodingSettings.IGDogfoodingSettingsSelectionViewController",
        @"IGDogfoodingSettingsSelectionViewController",
        @"_TtC20IGDogfoodingSettings43IGDogfoodingSettingsSelectionViewController"
    ]);

    // Deliberately do not hook viewWillDisappear: the native controller still owns its
    // apply/persist lifecycle. We only observe after native didSelect / didDisappear.
    SCIDogHookClassMethodIfPresent(mainVC, @selector(viewDidDisappear:), (IMP)hookSCIDogMainViewDidDisappear, (IMP *)&origSCIDogMainViewDidDisappear);
    SCIDogHookClassMethodIfPresent(mainVC, @selector(tableView:didSelectRowAtIndexPath:), (IMP)hookSCIDogMainDidSelect, (IMP *)&origSCIDogMainDidSelect);

    SCIDogHookClassMethodIfPresent(selectionVC, @selector(viewDidDisappear:), (IMP)hookSCIDogSelectionViewDidDisappear, (IMP *)&origSCIDogSelectionViewDidDisappear);
    SCIDogHookClassMethodIfPresent(selectionVC, @selector(tableView:didSelectRowAtIndexPath:), (IMP)hookSCIDogSelectionDidSelect, (IMP *)&origSCIDogSelectionDidSelect);

    NSLog(@"[RyukGram][DogfoodPersist] pass-through hooks main=%@ selection=%@", mainVC ? NSStringFromClass(mainVC) : @"nil", selectionVC ? NSStringFromClass(selectionVC) : @"nil");
}

#pragma mark - id_name_mapping pass-through export observer

typedef void (*SCIMCStoragePersistExtraDataFn)(void *self, const std::string &key, const std::string &payload);
static SCIMCStoragePersistExtraDataFn origSCIMCStoragePersistExtraData = NULL;
static BOOL gSCIMCIDNameObserverInstalled = NO;

static const char *kSCIMCStoragePersistExtraDataSymbols[] = {
    "__ZN12mobileconfig28FBMobileConfigStorageManager16persistExtraDataERKNSt3__112basic_stringIcNS1_11char_traitsIcEENS1_9allocatorIcEEEES9_",
    "_ZN12mobileconfig28FBMobileConfigStorageManager16persistExtraDataERKNSt3__112basic_stringIcNS1_11char_traitsIcEENS1_9allocatorIcEEEES9_"
};

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
    if ([lowerKey containsString:@"id_name_mapping"] || [lowerKey containsString:@"id-name-mapping"] || [lowerKey containsString:@"idnamemapping"]) return YES;
    if (!payload.length || payload.length < 16 || payload.length > (64 * 1024 * 1024)) return NO;
    if (!SCIDataLooksLikeJSON(payload)) return NO;

    NSUInteger sampleLen = MIN((NSUInteger)8192, payload.length);
    NSString *sample = [[NSString alloc] initWithData:[payload subdataWithRange:NSMakeRange(0, sampleLen)] encoding:NSUTF8StringEncoding] ?: @"";
    NSString *lower = sample.lowercaseString ?: @"";
    if ([lower containsString:@"id_to_names"] || [lower containsString:@"idtonames"] || [lower containsString:@"id_name_mapping"]) return YES;
    if ([lower containsString:@"config_name"] || [lower containsString:@"param_name"] || [lower containsString:@"mappings"]) return YES;
    return NO;
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

    NSDictionary *parsed = [SCIMobileConfigMapping parseMappingObject:json source:source ?: @"persistExtraData"];
    if (![parsed isKindOfClass:NSDictionary.class] || parsed.count == 0) {
        SCIRecordIDNameObserverStatus(source, key, @"", payload.length, @"json did not parse into id_name_mapping entries");
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
            [[NSNotificationCenter defaultCenter] postNotificationName:SCIDexKitNameResolverRuntimeFeedDidUpdateNotification object:nil];
        });
        NSLog(@"[RyukGram][MCIDName] exported id_name_mapping entries=%@ bytes=%@ key=%@ path=%@", @(parsed.count), @(payload.length), key, path);
    }
}

static void hookSCIMCStoragePersistExtraData(void *self, const std::string &key, const std::string &payload) {
    @autoreleasepool {
        @try {
            SCIExportIDNameMappingPayload(@"FBMobileConfigStorageManager.persistExtraData", SCIStringFromStdString(key), SCIDataFromStdString(payload));
        } @catch (__unused NSException *exception) {
        }
    }

    if (origSCIMCStoragePersistExtraData) {
        origSCIMCStoragePersistExtraData(self, key, payload);
    }
}

static void SCIInstallIDNameMappingObserverAttempt(NSUInteger attempt) {
    if (gSCIMCIDNameObserverInstalled) return;

    void *target = NULL;
    for (NSUInteger i = 0; i < sizeof(kSCIMCStoragePersistExtraDataSymbols) / sizeof(kSCIMCStoragePersistExtraDataSymbols[0]); i++) {
        target = dlsym(RTLD_DEFAULT, kSCIMCStoragePersistExtraDataSymbols[i]);
        if (target) break;
    }

    if (!target) {
        if (attempt < 24) {
            dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.5 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
                SCIInstallIDNameMappingObserverAttempt(attempt + 1);
            });
        } else {
            NSLog(@"[RyukGram][MCIDName] persistExtraData symbol not loaded");
        }
        return;
    }

    gSCIMCIDNameObserverInstalled = YES;
    MSHookFunction(target, (void *)&hookSCIMCStoragePersistExtraData, (void **)&origSCIMCStoragePersistExtraData);
    NSLog(@"[RyukGram][MCIDName] pass-through observer installed target=%p", target);
}

#ifdef __cplusplus
extern "C" {
#endif
__attribute__((visibility("default"))) void SCIInstallDogfoodingPersistenceHooks(void) {
    dispatch_async(dispatch_get_main_queue(), ^{
        SCIDogInstallPersistenceHooks();
    });
}

__attribute__((visibility("default"))) void SCIInstallPassiveIDNameMappingPersistObserver(void) {
    dispatch_async(dispatch_get_main_queue(), ^{
        SCIRecordIDNameObserverStatus(@"disabled", @"", @"", 0, @"persistExtraData hook disabled; scan paths only");
    });
}

__attribute__((visibility("default"))) BOOL SCIIsPassiveIDNameMappingPersistObserverInstalled(void) {
    return gSCIMCIDNameObserverInstalled;
}
#ifdef __cplusplus
}
#endif

__attribute__((constructor))
static void SCIDogfoodingPersistenceInit(void) {
    @autoreleasepool {
        SCIDogCrashGuardBootstrap();
        NSLog(@"[RyukGram][DogfoodPersist] startup inert; hooks and id_name observer are manual/debug only");
    }
}
