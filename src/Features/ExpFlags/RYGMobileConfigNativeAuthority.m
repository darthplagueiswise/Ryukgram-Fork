#import "RYGMobileConfig.h"
#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>
#import <objc/runtime.h>
#import <objc/message.h>
#import <os/lock.h>
#import <mach-o/dyld.h>

// Native MobileConfig path authority.
//
// Binary evidence from FBSharedFramework(20260823-232938):
//   -FBMobileConfigContextManager getBool:              B24@0:8{mc_bool_param_t=Q}16
//   -FBMobileConfigContextManager getOverridesTablePath @16@0:8
//   -IGMobileConfigContextManager getBool:              B24@0:8{mc_bool_param_t=Q}16
//   -IGMobileConfigContextManager getOverridesTablePath @16@0:8
//
// The active manager instance is authoritative. Capturing it must stay out of
// the expensive path: the one-shot getter wrapper only retains `self`, restores
// the previous IMP, and forwards. Filesystem/path work happens only when the
// MobileConfig import/export UI asks for ryg_nativeDataDirectory.

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
    const char *type = RYGMCUnqualifiedType(ret);
    return type && *type == '@';
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
    // dictionary, scan or dispatch here.
    RYGMCRetainObservedManager(self);
    IMP upstream = gRYGMCCaptureFBUpstream;
    RYGMCUninstallCapture([self class], cmd, (IMP)RYGMCCaptureFBGetBool, upstream, &gRYGMCCaptureFBInstalled);
    return upstream ? ((BOOL (*)(id, SEL, unsigned long long))upstream)(self, cmd, pid) : NO;
}

static BOOL RYGMCCaptureIGGetBool(id self, SEL cmd, unsigned long long pid) {
    RYGMCRetainObservedManager(self);
    IMP upstream = gRYGMCCaptureIGUpstream;
    RYGMCUninstallCapture([self class], cmd, (IMP)RYGMCCaptureIGGetBool, upstream, &gRYGMCCaptureIGInstalled);
    return upstream ? ((BOOL (*)(id, SEL, unsigned long long))upstream)(self, cmd, pid) : NO;
}

static void RYGMCTryInstallCaptureForClass(const char *className,
                                            IMP wrapper,
                                            IMP *upstream,
                                            BOOL *installedFlag) {
    if (!className || !wrapper || !upstream || !installedFlag || RYGMCCurrentObservedManager()) return;
    Class cls = objc_lookUpClass(className);
    if (!cls) return;

    SEL getter = NSSelectorFromString(@"getBool:");
    Method getterMethod = class_getInstanceMethod(cls, getter);
    Method pathMethod = class_getInstanceMethod(cls, NSSelectorFromString(@"getOverridesTablePath"));
    if (!RYGMCCaptureMethodLooksCompatible(getterMethod) || !RYGMCCapturePathMethodLooksCompatible(pathMethod)) return;

    IMP current = method_getImplementation(getterMethod);
    if (!current) return;
    if (current == wrapper) {
        *installedFlag = YES;
        return;
    }

    // Another owner may legitimately reassert this hot getter after us. Until a
    // real manager has been observed, always wrap the CURRENT implementation so
    // the next native call captures self and restores exactly that upstream.
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

static void RYGMCNativeAuthorityImageDidLoad(const struct mach_header *header, intptr_t slide) {
    (void)header; (void)slide;
    if (RYGMCCurrentObservedManager()) return;
    // O(1) late-load retry only. No path lookup or filesystem access here.
    RYGMCTryInstallOneShotManagerCapture();
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

    id value = ((id (*)(id, SEL))objc_msgSend)(manager, selector);
    return RYGMCValidatedNativeDirectory(RYGMCNativeDataDirectoryFromValue(value), YES);
}

@interface RYGMobileConfig (RYGNativeAuthorityPrivate)
- (NSString *)ryg_nativeDataDirectory;
- (NSString *)ryg_authorityNativeDataDirectory;
@end

@implementation RYGMobileConfig (RYGNativeAuthority)

- (NSString *)ryg_authorityNativeDataDirectory {
    // Native manager wins. It already knows the account-specific <user>.data;
    // never reject that result because more than one application-group exists.
    NSString *native = RYGMCDataDirectoryFromObservedManager();
    if (native.length) return native;

    RYGMCTryInstallOneShotManagerCapture();

    // Preserve older resolver only as a fallback for a concrete existing .data
    // path. The UI must never describe "one unambiguous App Group" as a native
    // MobileConfig requirement.
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
    RYGMCTryInstallOneShotManagerCapture();
    if (!RYGMCCurrentObservedManager()) _dyld_register_func_for_add_image(RYGMCNativeAuthorityImageDidLoad);
    dispatch_async(dispatch_get_main_queue(), ^{
        RYGMCTryInstallOneShotManagerCapture();
        [NSNotificationCenter.defaultCenter addObserverForName:UIApplicationDidBecomeActiveNotification
                                                         object:nil
                                                          queue:NSOperationQueue.mainQueue
                                                     usingBlock:^(__unused NSNotification *note) {
            if (!RYGMCCurrentObservedManager()) RYGMCTryInstallOneShotManagerCapture();
        }];
    });
}

__attribute__((constructor(65470))) static void RYGMobileConfigInstallNativeAuthority(void) {
    RYGMCInstallNativeAuthority();
}
