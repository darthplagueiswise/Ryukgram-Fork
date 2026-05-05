#import "SCIMobileConfigBrokerRouter.h"
#import "SCIMobileConfigBrokerStore.h"
#import <Foundation/Foundation.h>
#import <dlfcn.h>

static NSMutableDictionary<NSString *, NSString *> *gMCBRErrors;

static void MCBREnsureState(void) {
    if (!gMCBRErrors) gMCBRErrors = [NSMutableDictionary dictionary];
}

static NSString *MCBRBasename(const char *path) {
    if (!path) return @"";
    const char *slash = strrchr(path, '/');
    return [NSString stringWithUTF8String:(slash ? slash + 1 : path)] ?: @"";
}

static void *MCBRDlsymFlexible(NSString *symbol) {
    if (!symbol.length) return NULL;
    const char *s = symbol.UTF8String;
    void *p = dlsym(RTLD_DEFAULT, s);
    if (p) return p;
    if (s[0] == '_') return dlsym(RTLD_DEFAULT, s + 1);
    NSString *underscored = [@"_" stringByAppendingString:symbol];
    return dlsym(RTLD_DEFAULT, underscored.UTF8String);
}

static NSError *MCBRError(NSInteger code, NSString *message) {
    return [NSError errorWithDomain:@"SCIMobileConfigBrokerRouter" code:code userInfo:@{NSLocalizedDescriptionKey: message ?: @"unknown"}];
}

static NSString *MCBRReadOnlyStatusForDescriptor(SCIMobileConfigBrokerDescriptor *d) {
    if (!d.symbol.length) return @"missing symbol";
    void *addr = MCBRDlsymFlexible(d.symbol);
    if (!addr) return [NSString stringWithFormat:@"symbol not loaded yet: %@", d.symbol];

    Dl_info info; memset(&info, 0, sizeof(info));
    if (dladdr(addr, &info) == 0 || !info.dli_fname) return @"dladdr failed";

    NSString *owner = MCBRBasename(info.dli_fname);
    uint64_t cur = 0;
    memcpy(&cur, addr, sizeof(cur));

    NSMutableString *status = [NSMutableString stringWithFormat:@"scan-only · owner=%@ · addr=%p · orig8=0x%016llx", owner ?: @"?", addr, (unsigned long long)cur];
    if (d.imageName.length && ![owner isEqualToString:d.imageName]) {
        [status appendFormat:@" · owner mismatch expected=%@", d.imageName];
    }
    if (d.expectedOrig8 && cur != d.expectedOrig8) {
        [status appendFormat:@" · fingerprint mismatch expected=0x%016llx", (unsigned long long)d.expectedOrig8];
    }
    [status appendString:@" · offline patch required for full C broker interception"];
    return status;
}

@implementation SCIMobileConfigBrokerRouter

+ (void)bootstrap {
    [SCIMobileConfigBrokerStore registerDefaultsAndMigrate];
    NSLog(@"[RyukGram][MCBR] sideload-safe mode: runtime body hooks disabled; scan remains read-only");
}

+ (BOOL)installBroker:(SCIMobileConfigBrokerDescriptor *)descriptor error:(NSError * _Nullable * _Nullable)error {
    NSString *status = MCBRReadOnlyStatusForDescriptor(descriptor);
    NSString *msg = [NSString stringWithFormat:@"%@: %@", descriptor.brokerID ?: descriptor.symbol ?: @"broker", status ?: @"offline patch required"];
    [SCIMobileConfigBrokerStore noteLastError:msg brokerID:descriptor.brokerID];
    @synchronized(self) { MCBREnsureState(); if (descriptor.brokerID.length) gMCBRErrors[descriptor.brokerID] = msg; }
    if (error) *error = MCBRError(403, msg);
    NSLog(@"[RyukGram][MCBR] blocked runtime C broker hook: %@", msg);
    return NO;
}

+ (BOOL)isInstalled:(NSString *)brokerID {
    (void)brokerID;
    return NO;
}

+ (NSUInteger)installedCount {
    return 0;
}

+ (NSDictionary<NSString *,NSString *> *)installErrors {
    @synchronized(self) { MCBREnsureState(); return [gMCBRErrors copy] ?: @{}; }
}

+ (void)installEnabledBrokers {
    for (SCIMobileConfigBrokerDescriptor *d in [SCIMobileConfigBrokerDescriptor allDescriptors]) {
        if (![SCIMobileConfigBrokerStore shouldInstallBrokerID:d.brokerID]) continue;
        NSString *status = MCBRReadOnlyStatusForDescriptor(d);
        NSString *msg = [NSString stringWithFormat:@"%@: %@", d.brokerID ?: d.symbol ?: @"broker", status ?: @"offline patch required"];
        [SCIMobileConfigBrokerStore noteLastError:msg brokerID:d.brokerID];
        @synchronized(self) { MCBREnsureState(); if (d.brokerID.length) gMCBRErrors[d.brokerID] = msg; }
        NSLog(@"[RyukGram][MCBR] skipped saved C broker hook in sideload mode: %@", msg);
    }
}

+ (void)retryPendingBrokersForImageBasename:(NSString *)basename {
    (void)basename;
}

@end

%ctor {
    [SCIMobileConfigBrokerRouter bootstrap];
}
