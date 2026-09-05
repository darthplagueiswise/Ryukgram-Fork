#import "RYGMobileConfig.h"
#import <Foundation/Foundation.h>
#import <objc/runtime.h>
#import <objc/message.h>
#import <os/lock.h>
#import <dlfcn.h>

// Native MobileConfig path authority.
//
// Priority is always Instagram's current FBT MobileConfig manager:
//   FBMobileConfigFBTGlobalSessionManager.sharedInstance
//     -> currentSessionContextManagerHolder
//     -> mcFbtManager
//     -> mobileconfig
//     -> getOverridesTablePath
//
// When that chain is not initialized yet, the Developer tools may still need to
// read id_name_mapping.json / mc_overrides.json that Instagram already persisted.
// The fallback below enumerates EXISTING accessible app/group containers only.
// It never invents an AppGroup UUID and never creates a mobileconfig/.data tree.

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

static BOOL RYGMCObjectNoArgMethod(Method method) {
    if (!method || method_getNumberOfArguments(method) != 2) return NO;
    char ret[32] = {0};
    method_getReturnType(method, ret, sizeof(ret));
    const char *type = RYGMCUnqualifiedType(ret);
    return type && *type == '@';
}

static id RYGMCCallObjectNoArg(id receiver, BOOL classMethod, const char *selectorName) {
    if (!receiver || !selectorName) return nil;
    SEL selector = sel_registerName(selectorName);
    Method method = classMethod
        ? class_getClassMethod((Class)receiver, selector)
        : class_getInstanceMethod([receiver class], selector);
    if (!RYGMCObjectNoArgMethod(method)) return nil;
    @try { return ((id (*)(id, SEL))objc_msgSend)(receiver, selector); }
    @catch (__unused NSException *exception) { return nil; }
}

static BOOL RYGMCGetterMethodLooksCompatible(Method method) {
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

static BOOL RYGMCPathMethodLooksCompatible(Method method) { return RYGMCObjectNoArgMethod(method); }

static void RYGMCRetainObservedManager(id manager) {
    if (!manager) return;
    os_unfair_lock_lock(&gRYGMCNativeAuthorityLock);
    gRYGMCObservedManager = manager;
    os_unfair_lock_unlock(&gRYGMCNativeAuthorityLock);
}

static id RYGMCCurrentObservedManager(void) {
    os_unfair_lock_lock(&gRYGMCNativeAuthorityLock);
    id manager = gRYGMCObservedManager;
    os_unfair_lock_unlock(&gRYGMCNativeAuthorityLock);
    return manager;
}

static id RYGMCActiveSessionContextManager(void) {
    Class globalClass = objc_lookUpClass("FBMobileConfigFBTGlobalSessionManager");
    if (!globalClass) return nil;
    id global = RYGMCCallObjectNoArg((id)globalClass, YES, "sharedInstance");
    id holder = RYGMCCallObjectNoArg(global, NO, "currentSessionContextManagerHolder");
    id fbtManager = RYGMCCallObjectNoArg(holder, NO, "mcFbtManager");
    id manager = RYGMCCallObjectNoArg(fbtManager, NO, "mobileconfig");
    if (!manager) return nil;
    Method pathMethod = class_getInstanceMethod([manager class], sel_registerName("getOverridesTablePath"));
    return RYGMCPathMethodLooksCompatible(pathMethod) ? manager : nil;
}

static void RYGMCUninstallCapture(Class cls, SEL selector, IMP wrapper, IMP upstream, BOOL *installedFlag) {
    if (!cls || !selector || !upstream) return;
    Method method = class_getInstanceMethod(cls, selector);
    if (method && method_getImplementation(method) == wrapper)
        (void)method_setImplementation(method, upstream);
    if (installedFlag) *installedFlag = NO;
}

static BOOL RYGMCCaptureFBGetBool(id self, SEL cmd, unsigned long long pid) {
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
    SEL getter = sel_registerName("getBool:");
    Method getterMethod = class_getInstanceMethod(cls, getter);
    Method pathMethod = class_getInstanceMethod(cls, sel_registerName("getOverridesTablePath"));
    if (!RYGMCGetterMethodLooksCompatible(getterMethod) || !RYGMCPathMethodLooksCompatible(pathMethod)) return;
    IMP current = method_getImplementation(getterMethod);
    if (!current) return;
    if (current == wrapper) { *installedFlag = YES; return; }
    *upstream = current;
    (void)method_setImplementation(getterMethod, wrapper);
    *installedFlag = method_getImplementation(getterMethod) == wrapper;
}

static void RYGMCTryInstallOneShotManagerCapture(void) {
    if (RYGMCCurrentObservedManager()) return;
    RYGMCTryInstallCaptureForClass("FBMobileConfigContextManager", (IMP)RYGMCCaptureFBGetBool,
                                   &gRYGMCCaptureFBUpstream, &gRYGMCCaptureFBInstalled);
    RYGMCTryInstallCaptureForClass("IGMobileConfigContextManager", (IMP)RYGMCCaptureIGGetBool,
                                   &gRYGMCCaptureIGUpstream, &gRYGMCCaptureIGInstalled);
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

static NSString *RYGMCValidatedNativeDirectory(NSString *path) {
    path = path.stringByStandardizingPath;
    if (!path.length || ![path.pathExtension.lowercaseString isEqualToString:@"data"]) return nil;
    BOOL isDirectory = NO;
    if ([NSFileManager.defaultManager fileExistsAtPath:path isDirectory:&isDirectory])
        return isDirectory ? path : nil;
    return nil;
}

static NSString *RYGMCDataDirectoryFromManager(id manager) {
    if (!manager) return nil;
    SEL selector = sel_registerName("getOverridesTablePath");
    Method method = class_getInstanceMethod([manager class], selector);
    if (!RYGMCPathMethodLooksCompatible(method)) return nil;
    id value = nil;
    @try { value = ((id (*)(id, SEL))objc_msgSend)(manager, selector); }
    @catch (__unused NSException *exception) { return nil; }
    return RYGMCValidatedNativeDirectory(RYGMCNativeDataDirectoryFromValue(value));
}

#pragma mark - Existing-container fallback

typedef CFTypeRef (*RYGMCSecTaskCreateFromSelfFn)(CFAllocatorRef allocator);
typedef CFTypeRef (*RYGMCSecTaskCopyValueForEntitlementFn)(CFTypeRef task, CFStringRef entitlement, CFErrorRef *error);

static NSArray<NSString *> *RYGMCApplicationGroupIdentifiers(void) {
    RYGMCSecTaskCreateFromSelfFn createTask = (RYGMCSecTaskCreateFromSelfFn)dlsym(RTLD_DEFAULT, "SecTaskCreateFromSelf");
    RYGMCSecTaskCopyValueForEntitlementFn copyValue = (RYGMCSecTaskCopyValueForEntitlementFn)dlsym(RTLD_DEFAULT, "SecTaskCopyValueForEntitlement");
    if (!createTask || !copyValue) return @[];
    CFTypeRef task = createTask(kCFAllocatorDefault);
    if (!task) return @[];
    CFTypeRef raw = copyValue(task, CFSTR("com.apple.security.application-groups"), NULL);
    CFRelease(task);
    NSArray *groups = CFBridgingRelease(raw);
    if (![groups isKindOfClass:NSArray.class]) return @[];
    NSMutableArray<NSString *> *valid = [NSMutableArray array];
    for (id item in groups) if ([item isKindOfClass:NSString.class] && [item length]) [valid addObject:item];
    return valid.copy;
}

static NSArray<NSString *> *RYGMCExistingContainerRoots(void) {
    NSFileManager *fm = NSFileManager.defaultManager;
    NSMutableOrderedSet<NSString *> *roots = [NSMutableOrderedSet orderedSet];
    NSString *home = NSHomeDirectory().stringByStandardizingPath;
    if (home.length) [roots addObject:home];

    // Common sideload bridge used by this project: an AppGroup directory made
    // visible inside the data container. It is accepted only when it already
    // exists; nothing is created here.
    NSString *bridged = [[home stringByAppendingPathComponent:@"Documents/AppGroup"] stringByStandardizingPath];
    BOOL bridgeDirectory = NO;
    if ([fm fileExistsAtPath:bridged isDirectory:&bridgeDirectory] && bridgeDirectory) [roots addObject:bridged];

    for (NSString *group in RYGMCApplicationGroupIdentifiers()) {
        NSURL *url = nil;
        @try { url = [fm containerURLForSecurityApplicationGroupIdentifier:group]; }
        @catch (__unused NSException *exception) { url = nil; }
        NSString *path = url.path.stringByStandardizingPath;
        BOOL isDirectory = NO;
        if (path.length && [fm fileExistsAtPath:path isDirectory:&isDirectory] && isDirectory) [roots addObject:path];
    }
    return roots.array;
}

static NSInteger RYGMCArtifactScore(NSString *dataDirectory, NSTimeInterval *latestDate) {
    NSFileManager *fm = NSFileManager.defaultManager;
    NSInteger score = 0;
    NSTimeInterval latest = 0;
    NSArray<NSString *> *strongNames = @[@"id_name_mapping.json", @"mc_overrides.json"];
    for (NSUInteger i = 0; i < strongNames.count; i++) {
        NSString *path = [dataDirectory stringByAppendingPathComponent:strongNames[i]];
        BOOL isDirectory = NO;
        if (![fm fileExistsAtPath:path isDirectory:&isDirectory] || isDirectory) continue;
        score += i == 0 ? 100 : 90;
        NSDictionary *attrs = [fm attributesOfItemAtPath:path error:nil];
        latest = MAX(latest, [attrs.fileModificationDate timeIntervalSince1970]);
    }
    NSArray<NSString *> *children = [fm contentsOfDirectoryAtPath:dataDirectory error:nil] ?: @[];
    for (NSString *name in children) {
        NSString *lower = name.lowercaseString;
        if ([lower hasPrefix:@"mc_sync_response_dump"] || [lower containsString:@"params_map"] || [lower containsString:@"mobileconfigadminid"]) {
            score += 5;
            NSDictionary *attrs = [fm attributesOfItemAtPath:[dataDirectory stringByAppendingPathComponent:name] error:nil];
            latest = MAX(latest, [attrs.fileModificationDate timeIntervalSince1970]);
        }
    }
    if (latestDate) *latestDate = latest;
    return score;
}

static NSString *RYGMCDiscoverExistingDataDirectory(void) {
    NSFileManager *fm = NSFileManager.defaultManager;
    NSString *best = nil;
    NSInteger bestScore = 0;
    NSTimeInterval bestDate = 0;

    for (NSString *root in RYGMCExistingContainerRoots()) {
        NSArray<NSString *> *mobileRoots = @[
            [root stringByAppendingPathComponent:@"Documents/mobileconfig"],
            [root stringByAppendingPathComponent:@"mobileconfig"],
        ];
        for (NSString *mobileRoot in mobileRoots) {
            BOOL mobileDirectory = NO;
            if (![fm fileExistsAtPath:mobileRoot isDirectory:&mobileDirectory] || !mobileDirectory) continue;
            for (NSString *child in [fm contentsOfDirectoryAtPath:mobileRoot error:nil] ?: @[]) {
                if (![child.pathExtension.lowercaseString isEqualToString:@"data"]) continue;
                NSString *candidate = [[mobileRoot stringByAppendingPathComponent:child] stringByStandardizingPath];
                BOOL candidateDirectory = NO;
                if (![fm fileExistsAtPath:candidate isDirectory:&candidateDirectory] || !candidateDirectory) continue;
                NSTimeInterval latest = 0;
                NSInteger score = RYGMCArtifactScore(candidate, &latest);
                if (score > bestScore || (score == bestScore && score > 0 && latest > bestDate)) {
                    best = candidate;
                    bestScore = score;
                    bestDate = latest;
                }
            }
        }
    }
    return bestScore > 0 ? best : nil;
}

@interface RYGMobileConfig (RYGNativeAuthorityPrivate)
- (NSString *)ryg_nativeDataDirectory;
- (NSString *)ryg_authorityNativeDataDirectory;
@end

@implementation RYGMobileConfig (RYGNativeAuthority)

- (id)ryg_resolveActiveSessionManager {
    // Explicit browser/editor path only. No discovery runs from a MobileConfig
    // getter hot path.
    id manager = RYGMCActiveSessionContextManager() ?: RYGMCCurrentObservedManager();
    if (manager) RYGMCRetainObservedManager(manager);
    if (!manager) RYGMCTryInstallOneShotManagerCapture();
    return manager;
}

- (NSString *)ryg_authorityNativeDataDirectory {
    id manager = [self ryg_resolveActiveSessionManager];
    NSString *native = RYGMCDataDirectoryFromManager(manager ?: RYGMCCurrentObservedManager());
    if (native.length) return native;

    // A file already persisted in the real accessible container must be visible
    // even before a MobileConfig getter happens. Read-only filesystem discovery
    // is therefore the second authority, not a locally fabricated cache path.
    NSString *existing = RYGMCDiscoverExistingDataDirectory();
    if (existing.length) return existing;

    RYGMCTryInstallOneShotManagerCapture();

    // After method_exchangeImplementations this selector points at JSONIO's
    // original mcDirectory-backed implementation. Keep it as the final legacy
    // fallback for builds with a nonstandard but already-resolved manager path.
    NSString *previous = [self ryg_authorityNativeDataDirectory];
    return RYGMCValidatedNativeDirectory(previous);
}

@end

__attribute__((constructor(65470))) static void RYGMobileConfigInstallNativeAuthority(void) {
    Class cls = RYGMobileConfig.class;
    Method original = class_getInstanceMethod(cls, @selector(ryg_nativeDataDirectory));
    Method replacement = class_getInstanceMethod(cls, @selector(ryg_authorityNativeDataDirectory));
    if (original && replacement && method_getImplementation(original) != method_getImplementation(replacement))
        method_exchangeImplementations(original, replacement);
}
