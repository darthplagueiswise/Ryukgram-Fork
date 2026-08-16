// Diverts IG's device-id / FDID / vendor-id getters to our spoofed values while
// spoofing is enabled, and optionally blocks Apple device attestation.

#import "RYGDeviceIdentity.h"
#import "../../Utils.h"
#import <substrate.h>
#import <objc/runtime.h>
#import <objc/message.h>

// +[FOATokenRegistrationKit getDeviceId]
static NSString *(*orig_foaGetDeviceId)(id, SEL);
static NSString *new_foaGetDeviceId(id self, SEL _cmd) {
    if ([RYGDeviceIdentity spoofingEnabled]) return [RYGDeviceIdentity spoofedDeviceID];
    return orig_foaGetDeviceId(self, _cmd);
}

// -[*MobileConfigContextManager getDeviceId]
static NSString *(*orig_mcGetDeviceId)(id, SEL);
static NSString *new_mcGetDeviceId(id self, SEL _cmd) {
    if ([RYGDeviceIdentity spoofingEnabled]) return [RYGDeviceIdentity spoofedDeviceID];
    return orig_mcGetDeviceId(self, _cmd);
}
static NSString *(*orig_mcGetDeviceId2)(id, SEL);
static NSString *new_mcGetDeviceId2(id self, SEL _cmd) {
    if ([RYGDeviceIdentity spoofingEnabled]) return [RYGDeviceIdentity spoofedDeviceID];
    return orig_mcGetDeviceId2(self, _cmd);
}

// -[FBFamilyDeviceID (cached)familyDeviceIDWithConfiguration:SourceFile:SourceLine:]
static NSString *(*orig_fdid)(id, SEL, id, id, id);
static NSString *new_fdid(id self, SEL _cmd, id cfg, id file, id line) {
    if ([RYGDeviceIdentity spoofingEnabled]) return [RYGDeviceIdentity spoofedFDID];
    return orig_fdid(self, _cmd, cfg, file, line);
}
static NSString *(*orig_fdidCached)(id, SEL, id, id, id);
static NSString *new_fdidCached(id self, SEL _cmd, id cfg, id file, id line) {
    if ([RYGDeviceIdentity spoofingEnabled]) return [RYGDeviceIdentity spoofedFDID];
    return orig_fdidCached(self, _cmd, cfg, file, line);
}

// -[UIDevice identifierForVendor] — IG derives the FDID from this, so return the
// spoofed FDID here too (keeps FDID == IDFV).
static NSUUID *(*orig_idfv)(id, SEL);
static NSUUID *new_idfv(id self, SEL _cmd) {
    if ([RYGDeviceIdentity spoofingEnabled]) {
        NSUUID *u = [[NSUUID alloc] initWithUUIDString:[RYGDeviceIdentity spoofedFDID]];
        if (u) return u;
    }
    return orig_idfv(self, _cmd);
}

// Apple attestation is hardware-bound and can't be rotated; when blocked, return
// the "feature unsupported" error a device without it would give.
static NSError *rygAttestUnsupported(void) {
    return [NSError errorWithDomain:@"com.apple.devicecheck.error" code:1 userInfo:nil];
}
static BOOL rygAttestBlocked(void) {
    return [RYGDeviceIdentity spoofingEnabled] &&
           [RYGUtils getBoolPref:RYGDeviceSpoofBlockDeviceCheckKey];
}

// -[DCDevice generateTokenWithCompletionHandler:]
static void (*orig_dcGenerate)(id, SEL, id);
static void new_dcGenerate(id self, SEL _cmd, void (^handler)(NSData *, NSError *)) {
    if (rygAttestBlocked()) { if (handler) handler(nil, rygAttestUnsupported()); return; }
    orig_dcGenerate(self, _cmd, handler);
}

// -[DCAppAttestService generateKeyWithCompletionHandler:]
static void (*orig_aaGenKey)(id, SEL, id);
static void new_aaGenKey(id self, SEL _cmd, void (^handler)(NSString *, NSError *)) {
    if (rygAttestBlocked()) { if (handler) handler(nil, rygAttestUnsupported()); return; }
    orig_aaGenKey(self, _cmd, handler);
}
// -[DCAppAttestService attestKey:clientDataHash:completionHandler:]
static void (*orig_aaAttest)(id, SEL, id, id, id);
static void new_aaAttest(id self, SEL _cmd, id keyId, id hash, void (^handler)(NSData *, NSError *)) {
    if (rygAttestBlocked()) { if (handler) handler(nil, rygAttestUnsupported()); return; }
    orig_aaAttest(self, _cmd, keyId, hash, handler);
}
// -[DCAppAttestService generateAssertion:clientDataHash:completionHandler:]
static void (*orig_aaAssert)(id, SEL, id, id, id);
static void new_aaAssert(id self, SEL _cmd, id keyId, id hash, void (^handler)(NSData *, NSError *)) {
    if (rygAttestBlocked()) { if (handler) handler(nil, rygAttestUnsupported()); return; }
    orig_aaAssert(self, _cmd, keyId, hash, handler);
}

static void hookInstance(NSString *clsName, SEL sel, IMP repl, void *orig) {
    Class cls = NSClassFromString(clsName);
    if (cls && class_getInstanceMethod(cls, sel))
        MSHookMessageEx(cls, sel, repl, (IMP *)orig);
}

%ctor {
    @autoreleasepool {
        // Class method — hook the metaclass.
        Class foa = NSClassFromString(@"_TtC23FOATokenRegistrationKit23FOATokenRegistrationKit");
        if (foa && class_getClassMethod(foa, @selector(getDeviceId)))
            MSHookMessageEx(object_getClass(foa), @selector(getDeviceId),
                            (IMP)new_foaGetDeviceId, (IMP *)&orig_foaGetDeviceId);

        hookInstance(@"FBMobileConfigContextManager", @selector(getDeviceId),
                     (IMP)new_mcGetDeviceId, &orig_mcGetDeviceId);
        hookInstance(@"IGMobileConfigContextManager", @selector(getDeviceId),
                     (IMP)new_mcGetDeviceId2, &orig_mcGetDeviceId2);

        SEL fdidSel = NSSelectorFromString(@"familyDeviceIDWithConfiguration:SourceFile:SourceLine:");
        SEL fdidCachedSel = NSSelectorFromString(@"cachedFamilyDeviceIDWithConfiguration:SourceFile:SourceLine:");
        hookInstance(@"FBFamilyDeviceID", fdidSel, (IMP)new_fdid, &orig_fdid);
        hookInstance(@"FBFamilyDeviceID", fdidCachedSel, (IMP)new_fdidCached, &orig_fdidCached);

        hookInstance(@"UIDevice", @selector(identifierForVendor), (IMP)new_idfv, &orig_idfv);

        hookInstance(@"DCDevice", @selector(generateTokenWithCompletionHandler:),
                     (IMP)new_dcGenerate, &orig_dcGenerate);
        hookInstance(@"DCAppAttestService", @selector(generateKeyWithCompletionHandler:),
                     (IMP)new_aaGenKey, &orig_aaGenKey);
        hookInstance(@"DCAppAttestService", @selector(attestKey:clientDataHash:completionHandler:),
                     (IMP)new_aaAttest, &orig_aaAttest);
        hookInstance(@"DCAppAttestService", @selector(generateAssertion:clientDataHash:completionHandler:),
                     (IMP)new_aaAssert, &orig_aaAssert);
    }
}
