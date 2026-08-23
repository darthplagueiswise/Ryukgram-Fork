#import "RYGMobileConfig.h"
#import "RYGMobileConfigJSONIO.h"
#import "RYGMobileConfigNameMappingStore.h"
#import <Foundation/Foundation.h>
#import <objc/runtime.h>
#import <objc/message.h>
#import <os/lock.h>

// The native context manager is the path authority.  Older bridge revisions
// tried to prove that its path belonged to one "unambiguous" App Group and
// could therefore reject a perfectly valid getOverridesTablePath result after
// sideload signing.  Capture the manager once from a real getter invocation and
// keep the exact <user>.data path it reports.  No runtime scan is involved.

static NSString *const kRYGMCNativeAuthorityPathKey = @"ryg_mc_native_authority_path_v2";
static os_unfair_lock gRYGMCNativeAuthorityLock = OS_UNFAIR_LOCK_INIT;
static NSString *gRYGMCNativeAuthorityPath;
static IMP gRYGMCCaptureFBUpstream;
static IMP gRYGMCCaptureIGUpstream;
static BOOL gRYGMCCaptureFBInstalled;
static BOOL gRYGMCCaptureIGInstalled;

static NSString *RYGMCNativeDataDirectoryFromValue(id value) {
    NSString *path = nil;
    if ([value isKindOfClass:NSURL.class]) path = [(NSURL *)value path];
    else if ([value isKindOfClass:NSString.class]) path = value;
    if ([path hasPrefix:@"file://"]) path = [NSURL URLWithString:path].path;
    path = path.stringByStandardizingPath;
    if (!path.length) return nil;
    if ([path.pathExtension.lowercaseString isEqualToString:@"data"]) return path;
    NSString *parent = path.stringByDeletingLastPathComponent;
    return [parent.pathExtension.lowercaseString isEqualToString:@"data"] ? parent : nil;
}

static NSString *RYGMCNativeAuthorityValidatedDirectory(NSString *path, BOOL create) {
    path = path.stringByStandardizingPath;
    if (!path.length || ![path.pathExtension.lowercaseString isEqualToString:@"data"]) return nil;
    BOOL isDirectory = NO;
    if ([NSFileManager.defaultManager fileExistsAtPath:path isDirectory:&isDirectory]) return isDirectory ? path : nil;
    if (!create) return nil;
    NSError *error = nil;
    if (![NSFileManager.defaultManager createDirectoryAtPath:path withIntermediateDirectories:YES attributes:nil error:&error]) return nil;
    return path;
}

static void RYGMCCaptureNativeDirectoryFromManager(id manager) {
    if (!manager) return;
    SEL selector = NSSelectorFromString(@"getOverridesTablePath");
    Method method = class_getInstanceMethod([manager class], selector);
    if (!method || method_getNumberOfArguments(method) != 2) return;
    char ret[32] = {0};
    method_getReturnType(method, ret, sizeof(ret));
    if (ret[0] != '@') return;
    id value = ((id (*)(id, SEL))objc_msgSend)(manager, selector);
    NSString *directory = RYGMCNativeAuthorityValidatedDirectory(RYGMCNativeDataDirectoryFromValue(value), YES);
    if (!directory.length) return;
    os_unfair_lock_lock(&gRYGMCNativeAuthorityLock);
    gRYGMCNativeAuthorityPath = [directory copy];
    os_unfair_lock_unlock(&gRYGMCNativeAuthorityLock);
    [NSUserDefaults.standardUserDefaults setObject:directory forKey:kRYGMCNativeAuthorityPathKey];
}

static void RYGMCUninstallCapture(Class cls, SEL selector, IMP wrapper, IMP upstream, BOOL *installedFlag) {
    if (!cls || !selector || !upstream) return;
    Method method = class_getInstanceMethod(cls, selector);
    if (method && method_getImplementation(method) == wrapper) (void)method_setImplementation(method, upstream);
    if (installedFlag) *installedFlag = NO;
}

static BOOL RYGMCCaptureFBGetBool(id self, SEL cmd, unsigned long long pid) {
    RYGMCCaptureNativeDirectoryFromManager(self);
    Class cls = object_getClass(self) ? [self class] : Nil;
    RYGMCUninstallCapture(cls, cmd, (IMP)RYGMCCaptureFBGetBool, gRYGMCCaptureFBUpstream, &gRYGMCCaptureFBInstalled);
    return gRYGMCCaptureFBUpstream ? ((BOOL (*)(id,SEL,unsigned long long))gRYGMCCaptureFBUpstream)(self,cmd,pid) : NO;
}

static BOOL RYGMCCaptureIGGetBool(id self, SEL cmd, unsigned long long pid) {
    RYGMCCaptureNativeDirectoryFromManager(self);
    Class cls = object_getClass(self) ? [self class] : Nil;
    RYGMCUninstallCapture(cls, cmd, (IMP)RYGMCCaptureIGGetBool, gRYGMCCaptureIGUpstream, &gRYGMCCaptureIGInstalled);
    return gRYGMCCaptureIGUpstream ? ((BOOL (*)(id,SEL,unsigned long long))gRYGMCCaptureIGUpstream)(self,cmd,pid) : NO;
}

static BOOL RYGMCCaptureMethodLooksCompatible(Method method) {
    if (!method || method_getNumberOfArguments(method) != 3) return NO;
    char ret[32] = {0};
    method_getReturnType(method, ret, sizeof(ret));
    if (!(ret[0] == 'B' || ret[0] == 'c' || ret[0] == 'C')) return NO;
    return YES;
}

static void RYGMCTryInstallCaptureForClass(const char *className, IMP wrapper, IMP *upstream, BOOL *installedFlag) {
    if (!className || !wrapper || !upstream || !installedFlag || *installedFlag) return;
    Class cls = objc_lookUpClass(className);
    SEL selector = NSSelectorFromString(@"getBool:");
    Method method = cls ? class_getInstanceMethod(cls, selector) : NULL;
    Method pathMethod = cls ? class_getInstanceMethod(cls, NSSelectorFromString(@"getOverridesTablePath")) : NULL;
    if (!RYGMCCaptureMethodLooksCompatible(method) || !pathMethod) return;
    IMP current = method_getImplementation(method);
    if (!current || current == wrapper) return;
    *upstream = current;
    (void)method_setImplementation(method, wrapper);
    *installedFlag = method_getImplementation(method) == wrapper;
}

static void RYGMCTryInstallOneShotManagerCapture(void) {
    if (!gRYGMCNativeAuthorityPath.length) {
        NSString *saved = [NSUserDefaults.standardUserDefaults stringForKey:kRYGMCNativeAuthorityPathKey];
        NSString *valid = RYGMCNativeAuthorityValidatedDirectory(saved, NO);
        if (valid.length) {
            os_unfair_lock_lock(&gRYGMCNativeAuthorityLock);
            gRYGMCNativeAuthorityPath = [valid copy];
            os_unfair_lock_unlock(&gRYGMCNativeAuthorityLock);
        }
    }
    RYGMCTryInstallCaptureForClass("FBMobileConfigContextManager", (IMP)RYGMCCaptureFBGetBool, &gRYGMCCaptureFBUpstream, &gRYGMCCaptureFBInstalled);
    RYGMCTryInstallCaptureForClass("IGMobileConfigContextManager", (IMP)RYGMCCaptureIGGetBool, &gRYGMCCaptureIGUpstream, &gRYGMCCaptureIGInstalled);
}

@interface RYGMobileConfig (RYGNativeAuthorityPrivate)
- (NSString *)ryg_nativeDataDirectory;
- (NSString *)ryg_authorityNativeDataDirectory;
@end

@implementation RYGMobileConfig (RYGNativeAuthority)

- (NSString *)ryg_authorityNativeDataDirectory {
    NSString *captured = nil;
    os_unfair_lock_lock(&gRYGMCNativeAuthorityLock);
    captured = [gRYGMCNativeAuthorityPath copy];
    os_unfair_lock_unlock(&gRYGMCNativeAuthorityLock);
    captured = RYGMCNativeAuthorityValidatedDirectory(captured, NO);
    if (captured.length) return captured;

    // After exchange this invokes the previous resolver chain.  If it already
    // has a manager-backed .data result, accept it directly; do not apply an
    // additional App-Group ambiguity test.
    NSString *previous = [self ryg_authorityNativeDataDirectory];
    previous = RYGMCNativeAuthorityValidatedDirectory(previous, YES);
    if (previous.length) {
        os_unfair_lock_lock(&gRYGMCNativeAuthorityLock);
        gRYGMCNativeAuthorityPath = [previous copy];
        os_unfair_lock_unlock(&gRYGMCNativeAuthorityLock);
        [NSUserDefaults.standardUserDefaults setObject:previous forKey:kRYGMCNativeAuthorityPathKey];
        return previous;
    }

    // A manager may have become active after the previous resolver ran.  The
    // one-shot getter wrapper captures it without keeping another hot hook.
    RYGMCTryInstallOneShotManagerCapture();
    return nil;
}

@end

static void RYGMCInstallNativeAuthority(void) {
    Class cls = RYGMobileConfig.class;
    Method original = class_getInstanceMethod(cls, @selector(ryg_nativeDataDirectory));
    Method replacement = class_getInstanceMethod(cls, @selector(ryg_authorityNativeDataDirectory));
    if (original && replacement && method_getImplementation(original) != method_getImplementation(replacement))
        method_exchangeImplementations(original, replacement);
}

__attribute__((constructor(120))) static void RYGMobileConfigCaptureManagerBootstrap(void) {
    RYGMCTryInstallOneShotManagerCapture();
    // The hot owner schedules one main-queue reassertion. Install our one-shot
    // capture after that block as well; once a manager is captured the wrapper
    // removes itself permanently.
    dispatch_async(dispatch_get_main_queue(), ^{ RYGMCTryInstallOneShotManagerCapture(); });
}

__attribute__((constructor(65470))) static void RYGMobileConfigInstallNativeAuthority(void) {
    RYGMCInstallNativeAuthority();
}
