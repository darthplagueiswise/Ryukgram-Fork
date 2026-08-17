#import "RYGMobileConfig.h"
#import <Foundation/Foundation.h>
#import <objc/runtime.h>
#import <objc/message.h>
#import <substrate.h>
#import <dlfcn.h>
#import <execinfo.h>
#import <pthread.h>
#import <mach-o/dyld.h>
#include <stdint.h>
#include <string.h>

static NSMutableDictionary<NSNumber *, NSString *> *gRYGExternalMCCallSites;
static pthread_mutex_t gRYGExternalMCLock = PTHREAD_MUTEX_INITIALIZER;
static BOOL gRYGExternalInstallScheduled;

static unsigned long long RYGExternalCanonicalPID(unsigned long long pid) {
    unsigned long long type = (pid >> 48) & 0x0F;
    return (pid & 0x0000FFFFFFFFFFFFULL) | ((0x40ULL | type) << 48);
}

static BOOL RYGPathIsRyukGram(NSString *path) {
    NSString *name = path.lastPathComponent.lowercaseString;
    return [name containsString:@"ryukgram"];
}

static BOOL RYGPathBelongsToInstagramApp(NSString *path) {
    NSString *standard = path.stringByStandardizingPath;
    NSString *bundle = NSBundle.mainBundle.bundlePath.stringByStandardizingPath;
    NSString *executable = NSBundle.mainBundle.executablePath.stringByStandardizingPath;
    if (!standard.length || !bundle.length) return NO;
    if ([standard isEqualToString:executable]) return YES;
    return [standard hasPrefix:[bundle stringByAppendingString:@"/"]];
}

static NSString *RYGExternalCallerDescription(void) {
    void *frames[16] = {0};
    int count = backtrace(frames, 16);
    for (int index = 1; index < count; index++) {
        Dl_info info = {0};
        if (!dladdr(frames[index], &info) || !info.dli_fname) continue;
        NSString *path = [NSString stringWithUTF8String:info.dli_fname] ?: @"";
        if (RYGPathIsRyukGram(path)) continue;
        if (!RYGPathBelongsToInstagramApp(path)) return nil;
        NSString *symbol = info.dli_sname ? [NSString stringWithUTF8String:info.dli_sname] : nil;
        return symbol.length
            ? [NSString stringWithFormat:@"%@ · %@", path.lastPathComponent ?: @"Instagram", symbol]
            : (path.lastPathComponent ?: @"Instagram runtime");
    }
    return nil;
}

static void RYGRecordExternalMobileConfigRead(unsigned long long pid) {
    NSString *caller = RYGExternalCallerDescription();
    if (!caller.length || !pid) return;
    NSNumber *key = @(RYGExternalCanonicalPID(pid));
    pthread_mutex_lock(&gRYGExternalMCLock);
    if (!gRYGExternalMCCallSites) gRYGExternalMCCallSites = [NSMutableDictionary dictionary];
    if (!gRYGExternalMCCallSites[key]) gRYGExternalMCCallSites[key] = caller;
    pthread_mutex_unlock(&gRYGExternalMCLock);
}

static NSString *RYGExternalCallSiteForPID(unsigned long long pid) {
    NSNumber *key = @(RYGExternalCanonicalPID(pid));
    pthread_mutex_lock(&gRYGExternalMCLock);
    NSString *value = gRYGExternalMCCallSites[key];
    pthread_mutex_unlock(&gRYGExternalMCLock);
    return value;
}

#define RYG_WRAP_RET0(NAME, RET, FALLBACK) \
static RET (*orig_ext_##NAME)(id, SEL, unsigned long long); \
static RET new_ext_##NAME(id self, SEL cmd, unsigned long long pid) { \
    RYGRecordExternalMobileConfigRead(pid); \
    return orig_ext_##NAME ? orig_ext_##NAME(self, cmd, pid) : (FALLBACK); \
}
#define RYG_WRAP_RETDEF(NAME, RET, DEFRET) \
static RET (*orig_ext_##NAME)(id, SEL, unsigned long long, RET); \
static RET new_ext_##NAME(id self, SEL cmd, unsigned long long pid, RET def) { \
    RYGRecordExternalMobileConfigRead(pid); \
    return orig_ext_##NAME ? orig_ext_##NAME(self, cmd, pid, def) : (DEFRET); \
}
#define RYG_WRAP_RETOPTS(NAME, RET, FALLBACK) \
static RET (*orig_ext_##NAME)(id, SEL, unsigned long long, id); \
static RET new_ext_##NAME(id self, SEL cmd, unsigned long long pid, id opts) { \
    RYGRecordExternalMobileConfigRead(pid); \
    return orig_ext_##NAME ? orig_ext_##NAME(self, cmd, pid, opts) : (FALLBACK); \
}
#define RYG_WRAP_RETOPTSDEF(NAME, RET, DEFRET) \
static RET (*orig_ext_##NAME)(id, SEL, unsigned long long, id, RET); \
static RET new_ext_##NAME(id self, SEL cmd, unsigned long long pid, id opts, RET def) { \
    RYGRecordExternalMobileConfigRead(pid); \
    return orig_ext_##NAME ? orig_ext_##NAME(self, cmd, pid, opts, def) : (DEFRET); \
}

RYG_WRAP_RET0(getBool, BOOL, NO)
RYG_WRAP_RETDEF(getBoolDef, BOOL, def)
RYG_WRAP_RETOPTS(getBoolOpts, BOOL, NO)
RYG_WRAP_RETOPTSDEF(getBoolOptsDef, BOOL, def)
RYG_WRAP_RET0(getInt, long long, 0)
RYG_WRAP_RETDEF(getIntDef, long long, def)
RYG_WRAP_RETOPTS(getIntOpts, long long, 0)
RYG_WRAP_RETOPTSDEF(getIntOptsDef, long long, def)
RYG_WRAP_RET0(getDouble, double, 0.0)
RYG_WRAP_RETDEF(getDoubleDef, double, def)
RYG_WRAP_RETOPTS(getDoubleOpts, double, 0.0)
RYG_WRAP_RETOPTSDEF(getDoubleOptsDef, double, def)

static id (*orig_ext_getString)(id, SEL, unsigned long long);
static id new_ext_getString(id self, SEL cmd, unsigned long long pid) {
    RYGRecordExternalMobileConfigRead(pid);
    return orig_ext_getString ? orig_ext_getString(self, cmd, pid) : nil;
}
static id (*orig_ext_getStringDef)(id, SEL, unsigned long long, id);
static id new_ext_getStringDef(id self, SEL cmd, unsigned long long pid, id def) {
    RYGRecordExternalMobileConfigRead(pid);
    return orig_ext_getStringDef ? orig_ext_getStringDef(self, cmd, pid, def) : def;
}
static id (*orig_ext_getStringOpts)(id, SEL, unsigned long long, id);
static id new_ext_getStringOpts(id self, SEL cmd, unsigned long long pid, id opts) {
    RYGRecordExternalMobileConfigRead(pid);
    return orig_ext_getStringOpts ? orig_ext_getStringOpts(self, cmd, pid, opts) : nil;
}
static id (*orig_ext_getStringOptsDef)(id, SEL, unsigned long long, id, id);
static id new_ext_getStringOptsDef(id self, SEL cmd, unsigned long long pid, id opts, id def) {
    RYGRecordExternalMobileConfigRead(pid);
    return orig_ext_getStringOptsDef ? orig_ext_getStringOptsDef(self, cmd, pid, opts, def) : def;
}

static const char *RYGExternalSkipQualifiers(const char *type) {
    while (type && strchr("rnNoORV", *type)) type++;
    return type;
}

static BOOL RYGExternalTypeMatches(const char *raw, char expected) {
    const char *type = RYGExternalSkipQualifiers(raw);
    if (!type || !*type) return NO;
    switch (expected) {
        case 'P': return *type == 'Q' || *type == 'q' || (*type == '{' && (strstr(type, "=Q}") || strstr(type, "=q}")));
        case 'B': return *type == 'B' || *type == 'c' || *type == 'C';
        case 'Q': return *type == 'q' || *type == 'Q';
        case 'D': return *type == 'd';
        case '@': return *type == '@';
        default: return NO;
    }
}

static BOOL RYGExternalMethodMatches(Method method, char returnType, const char *arguments) {
    if (!method || !arguments || method_getNumberOfArguments(method) != strlen(arguments) + 2) return NO;
    char encoded[128] = {0};
    method_getReturnType(method, encoded, sizeof(encoded));
    if (!RYGExternalTypeMatches(encoded, returnType)) return NO;
    for (unsigned int index = 0; arguments[index]; index++) {
        memset(encoded, 0, sizeof(encoded));
        method_getArgumentType(method, index + 2, encoded, sizeof(encoded));
        if (!RYGExternalTypeMatches(encoded, arguments[index])) return NO;
    }
    return YES;
}

static BOOL RYGExternalHook(Class cls, NSString *name, IMP replacement, IMP *original, char returnType, const char *arguments) {
    if (!cls || !replacement || !original || *original) return original && *original;
    Method method = class_getInstanceMethod(cls, NSSelectorFromString(name));
    if (!RYGExternalMethodMatches(method, returnType, arguments)) return NO;
    MSHookMessageEx(cls, method_getName(method), replacement, original);
    return *original != NULL;
}

static NSUInteger RYGExternalManagerScore(Class cls) {
    if (!cls) return 0;
    NSUInteger score = 0;
    for (NSString *name in @[@"getBool:", @"getInt64:", @"getDouble:", @"getString:"]) {
        if (class_getInstanceMethod(cls, NSSelectorFromString(name))) score++;
    }
    return score;
}

static void RYGInstallExternalMobileConfigSeenHooks(void) {
    Class fb = NSClassFromString(@"FBMobileConfigContextManager");
    Class ig = NSClassFromString(@"IGMobileConfigContextManager");
    Class cls = RYGExternalManagerScore(fb) >= RYGExternalManagerScore(ig) ? fb : ig;
    if (!cls) return;

    RYGExternalHook(cls, @"getBool:", (IMP)new_ext_getBool, (IMP *)&orig_ext_getBool, 'B', "P");
    RYGExternalHook(cls, @"getBool:withDefault:", (IMP)new_ext_getBoolDef, (IMP *)&orig_ext_getBoolDef, 'B', "PB");
    RYGExternalHook(cls, @"getBool:withOptions:", (IMP)new_ext_getBoolOpts, (IMP *)&orig_ext_getBoolOpts, 'B', "P@");
    RYGExternalHook(cls, @"getBool:withOptions:withDefault:", (IMP)new_ext_getBoolOptsDef, (IMP *)&orig_ext_getBoolOptsDef, 'B', "P@B");
    RYGExternalHook(cls, @"getInt64:", (IMP)new_ext_getInt, (IMP *)&orig_ext_getInt, 'Q', "P");
    RYGExternalHook(cls, @"getInt64:withDefault:", (IMP)new_ext_getIntDef, (IMP *)&orig_ext_getIntDef, 'Q', "PQ");
    RYGExternalHook(cls, @"getInt64:withOptions:", (IMP)new_ext_getIntOpts, (IMP *)&orig_ext_getIntOpts, 'Q', "P@");
    RYGExternalHook(cls, @"getInt64:withOptions:withDefault:", (IMP)new_ext_getIntOptsDef, (IMP *)&orig_ext_getIntOptsDef, 'Q', "P@Q");
    RYGExternalHook(cls, @"getDouble:", (IMP)new_ext_getDouble, (IMP *)&orig_ext_getDouble, 'D', "P");
    RYGExternalHook(cls, @"getDouble:withDefault:", (IMP)new_ext_getDoubleDef, (IMP *)&orig_ext_getDoubleDef, 'D', "PD");
    RYGExternalHook(cls, @"getDouble:withOptions:", (IMP)new_ext_getDoubleOpts, (IMP *)&orig_ext_getDoubleOpts, 'D', "P@");
    RYGExternalHook(cls, @"getDouble:withOptions:withDefault:", (IMP)new_ext_getDoubleOptsDef, (IMP *)&orig_ext_getDoubleOptsDef, 'D', "P@D");
    RYGExternalHook(cls, @"getString:", (IMP)new_ext_getString, (IMP *)&orig_ext_getString, '@', "P");
    RYGExternalHook(cls, @"getString:withDefault:", (IMP)new_ext_getStringDef, (IMP *)&orig_ext_getStringDef, '@', "P@");
    RYGExternalHook(cls, @"getString:withOptions:", (IMP)new_ext_getStringOpts, (IMP *)&orig_ext_getStringOpts, '@', "P@");
    RYGExternalHook(cls, @"getString:withOptions:withDefault:", (IMP)new_ext_getStringOptsDef, (IMP *)&orig_ext_getStringOptsDef, '@', "P@@");
}

static void RYGScheduleExternalSeenInstall(void) {
    @synchronized(RYGMobileConfig.class) {
        if (gRYGExternalInstallScheduled) return;
        gRYGExternalInstallScheduled = YES;
    }
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.35 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
        @synchronized(RYGMobileConfig.class) { gRYGExternalInstallScheduled = NO; }
        RYGInstallExternalMobileConfigSeenHooks();
    });
}

static void RYGExternalSeenImageDidLoad(const struct mach_header *header, intptr_t slide) {
    (void)header; (void)slide;
    RYGScheduleExternalSeenInstall();
}

@implementation RYGMobileConfig (RYGExternalSeenTracker)

- (NSString *)ryg_external_callSiteFor:(RYGMCParam *)param {
    if (!param) return nil;
    unsigned long long pid = param.paramID;
    SEL bestSelector = NSSelectorFromString(@"bestParamIDFor:");
    if ([self respondsToSelector:bestSelector]) {
        pid = ((unsigned long long (*)(id, SEL, id))objc_msgSend)(self, bestSelector, param);
    }
    return RYGExternalCallSiteForPID(pid);
}

@end

__attribute__((constructor(65520))) static void RYGInstallExternalMobileConfigSeenTracker(void) {
    @autoreleasepool {
        Class cls = RYGMobileConfig.class;
        Method original = class_getInstanceMethod(cls, @selector(callSiteFor:));
        Method replacement = class_getInstanceMethod(cls, @selector(ryg_external_callSiteFor:));
        if (original && replacement) method_exchangeImplementations(original, replacement);
        RYGScheduleExternalSeenInstall();
        _dyld_register_func_for_add_image(RYGExternalSeenImageDidLoad);
    }
}
