#import "RYGMobileConfig.h"
#import <Foundation/Foundation.h>
#import <objc/runtime.h>
#import <objc/message.h>
#import <os/lock.h>

// Native MobileConfig path authority.
//
// Binary evidence from FBSharedFramework(20260821-132949):
//   -IGMobileConfigContextManager getBool:              B24@0:8{mc_bool_param_t=Q}16
//   -IGMobileConfigContextManager getOverridesTablePath @16@0:8
// There is no class/singleton method on the manager metaclass.  Therefore the
// only safe authority is a real manager instance observed from a native getter.
//
// CRITICAL: observing that instance must never perform path lookup, filesystem
// work or preference I/O.  The first getBool: wrapper only retains `self`,
// restores the previous IMP, and immediately forwards.  getOverridesTablePath
// is invoked later, only when import/export asks for ryg_nativeDataDirectory.

static os_unfair_lock gRYGMCNativeAuthorityLock = OS_UNFAIR_LOCK_INIT;
static id gRYGMCObservedManager;
static IMP gRYGMCCaptureFBUpstream;
static IMP gRYGMCCaptureIGUpstream;
static BOOL gRYGMCCaptureFBInstalled;
static BOOL gRYGMCCaptureIGInstalled;

static const char *RYGMCUnqualifiedType(const char *type) {
    while (type && *type && strchr("rnNoORV", *type)) type++;
    return type;
}

static BOOL RYGMCCaptureMethodLooksCompatible(Method method) {
    if (!method || method_getNumberOfArguments(method) != 3) return NO;
    char ret[32] = {0};
    method_getReturnType(method, ret, sizeof(ret));
    const char *returnType = RYGMCUnqualifiedType(ret);
    if (!returnType || !strchr("BcC", *returnType)) return NO;

    // The native parameter is a one-word mc_bool_param_t wrapper.  Objective-C
    // encodes it as a struct containing Q in the current FBShared build; older
    // builds may expose the underlying Q/q directly.  Both are one x-register.
    char arg[96] = {0};
    method_getArgumentType(method, 2, arg, sizeof(arg));
    const char *argumentType = RYGMCUnqualifiedType(arg);
    if (!argumentType || !*argumentType) return NO;
    if (*argumentType == 'Q' || *argumentType == 'q') return YES;
    return *argumentType == '{' && (strstr(argumentType, "=Q}") || strstr(argumentType, "=q}"));
}

static BOOL RYGMCCapturePathMethodLooksCompatible(Method method) {
    if (!method || method_getNumberOfArguments(method) != 2) return NO;
    char ret[32] = {0};
    method_getReturnType(method, ret, sizeof(ret));
    return *RYGMCUnqualifiedType(ret) == '@';
}

static void RYGMCRetainObservedManager(id manager) {
    if (!manager) return;
    os_unfair_lock_lock(&gRYGMCNativeAuthorityLock);
    if (!gRYGMCObservedManager) gRYGMCObservedManager = manager;
    os_unfair_lock_unlock(&gRYGMCNativeAuthorityLock);
}

static id RYGMCCurrentObservedManager(void) {
    os_unfair_lock_lock(&gRYGMCNativeAuthorityLock);
    id manager = gRYGMCObservedManager;
    os_unfair_lock_unlock(&gRYGMCNativeAuthorityLock);
    return manager;
}

static void RYGMCUninstallCapture(Class cls, SEL selector, IMP wrapper, IMP upstream, BOOL *installedFlag) {
    if (!cls || !selector || !upstream) return;
    Method method = class_getInstanceMethod(cls, selector);
    if (method && method_getImplementation(method) == wrapper)
        (void)method_setImplementation(method, upstream);
    if (installedFlag) *installedFlag = NO;
}

static BOOL RYGMCCaptureFBGetBool(id self, SEL cmd, unsigned long long pid) {
    // Hot-path guarantee: no getOverridesTablePath, filesystem, defaults,
    // dictionary, runtime scan or dispatch here.
    RYGMCRetainObservedManager(self);
    Class cls = [self class];
    IMP upstream = gRYGMCCaptureFBUpstream;
    RYGMCUninstallCapture(cls, cmd, (IMP)RYGMCCaptureFBGetBool, upstream, &gRYGMCCaptureFBInstalled);
    return upstream ? ((BOOL (*)(id, SEL, unsigned long long))upstream)(self, cmd, pid) : NO;
}

static BOOL RYGMCCaptureIGGetBool(id self, SEL cmd, unsigned long long pid) {
    // Hot-path guarantee: no getOverridesTablePath, filesystem, defaults,
    // dictionary, runtime scan or dispatch here.
    RYGMCRetainObservedManager(self);
    Class cls = [self class];
    IMP upstream = gRYGMCCaptureIGUpstream;
    RYGMCUninstallCapture(cls, cmd, (IMP)RYGMCCaptureIGGetBool, upstream, &gRYGMCCaptureIGInstalled);
    return upstream ? ((BOOL (*)(id, SEL, unsigned long long))upstream)(self, cmd, pid) : NO;
}

static void RYGMCTryInstallCaptureForClass(const char *className,
                                            IMP wrapper,
                                            IMP *upstream,
                                            BOOL *installedFlag) {
    if (!className || !wrapper || !upstream || !installedFlag || *installedFlag || RYGMCCurrentObservedManager()) return;
    Class cls = objc_lookUpClass(className);
    if (!cls) return;

    SEL getter = NSSelectorFromString(@"getBool:");
    Method getterMethod = class_getInstanceMethod(cls, getter);
    Method pathMethod = class_getInstanceMethod(cls, NSSelectorFromString(@"getOverridesTablePath"));
    if (!RYGMCCaptureMethodLooksCompatible(getterMethod) || !RYGMCCapturePathMethodLooksCompatible(pathMethod)) return;

    IMP current = method_getImplementation(getterMethod);
    if (!current || current == wrapper) return;
    *upstream = current;
    (void)method_setImplementation(getterMethod, wrapper);
    *installedFlag = method_getImplementation(getterMethod) == wrapper;
}

static void RYGMCTryInstallOneShotManagerCapture(void) {
    if (RYGMCCurrentObservedManager()) return;
    RYGMCTryInstallCaptureForClass("FBMobileConfigContextManager",
                                   (IMP)RYGMCCaptureFBGetBool,
                                   &gRYGMCCaptureFBUpstream,
                                   &gRYGMCCaptureFBInstalled);
    RYGMCTryInstallCaptureForClass("IGMobileConfigContextManager",
                                   (IMP)RYGMCCaptureIGGetBool,
                                   &gRYGMCCaptureIGUpstream,
                                   &gRYGMCCaptureIGInstalled);
}

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

static NSString *RYGMCValidatedNativeDirectory(NSString *path, BOOL create) {
    path = path.stringByStandardizingPath;
    if (!path.length || ![path.pathExtension.lowercaseString isEqualToString:@"data"]) return nil;
    BOOL isDirectory = NO;
    if ([NSFileManager.defaultManager fileExistsAtPath:path isDirectory:&isDirectory])
        return isDirectory ? path : nil;
    if (!create) return nil;
    return [NSFileManager.defaultManager createDirectoryAtPath:path
                                    withIntermediateDirectories:YES
                                                     attributes:nil
                                                          error:nil] ? path : nil;
}

static NSString *RYGMCDataDirectoryFromObservedManager(void) {
    id manager = RYGMCCurrentObservedManager();
    if (!manager) return nil;
    SEL selector = NSSelectorFromString(@"getOverridesTablePath");
    Method method = class_getInstanceMethod([manager class], selector);
    if (!RYGMCCapturePathMethodLooksCompatible(method)) return nil;

    // This is deliberately outside every MobileConfig getter.  Import/export is
    // the caller that pays for native path resolution and filesystem validation.
    id value = ((id (*)(id, SEL))objc_msgSend)(manager, selector);
    return RYGMCValidatedNativeDirectory(RYGMCNativeDataDirectoryFromValue(value), YES);
}

@interface RYGMobileConfig (RYGNativeAuthorityPrivate)
- (NSString *)ryg_nativeDataDirectory;
- (NSString *)ryg_authorityNativeDataDirectory;
@end

@implementation RYGMobileConfig (RYGNativeAuthority)

- (NSString *)ryg_authorityNativeDataDirectory {
    // First choice: the exact active manager observed from a native getter.
    NSString *native = RYGMCDataDirectoryFromObservedManager();
    if (native.length) return native;

    // A context class may have loaded after tweak construction.  Arm the
    // one-shot observer for the next real getter, but never wait/spin here.
    RYGMCTryInstallOneShotManagerCapture();

    // After method exchange this invokes the previous resolver chain.  Accept a
    // concrete .data result directly; do not impose another App-Group ambiguity
    // heuristic on a path that is already manager-backed.
    NSString *previous = [self ryg_authorityNativeDataDirectory];
    return RYGMCValidatedNativeDirectory(previous, previous.length > 0);
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
    // This performs only class/method lookup + one IMP replacement.  The first
    // getter stores `self` and immediately restores the previous IMP.  No I/O.
    RYGMCTryInstallOneShotManagerCapture();
    dispatch_async(dispatch_get_main_queue(), ^{ RYGMCTryInstallOneShotManagerCapture(); });
}

__attribute__((constructor(65470))) static void RYGMobileConfigInstallNativeAuthority(void) {
    RYGMCInstallNativeAuthority();
}
