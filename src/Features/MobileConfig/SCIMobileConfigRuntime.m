#import "SCIMobileConfigRuntime.h"
#include <stdlib.h>
#import "../../Utils.h"
#import <objc/runtime.h>
#import <objc/message.h>
#import <string.h>
#import <dispatch/dispatch.h>
#import "../Dogfooding/SCIDogfoodObjectRuntime.h"

extern void SCIInstallMobileConfigRuntimeHooksIfNeeded(void);

static NSString * const kObsKey = @"sci_mc_runtime_observations";
static NSString * const kOverridesKey = @"sci_mc_runtime_overrides";
static NSString * const kBootCountKey = @"sci_mc_runtime_boot_count";
static NSString * const kDisabledByGuardKey = @"sci_mc_runtime_disabled_by_guard";
static NSString * const kEnabledKey = @"sci_mc_runtime_browser_enabled";
static NSString * const kManualKey = @"sci_mc_runtime_manual_overrides_enabled";
static NSString * const kBindMapKey = @"sci_mc_runtime_name_bindings"; // canonicalName -> @[ "type:paramID", ... ]
static NSString * const kDeepSymbolsKey = @"sci_mc_runtime_deep_symbols_enabled";

static NSMutableDictionary<NSString *, NSMutableDictionary *> *sObs;
static NSMutableDictionary<NSString *, NSMutableArray<NSDictionary *> *> *sMapIndex;
static NSDate *sLastFlush;
static BOOL sMapLoaded;
static NSMapTable<id, NSMutableDictionary *> *sLiveObjects;
static NSTimeInterval sRuntimeStartTime;
static __thread BOOL sInsideMCRecord;
static BOOL sRuntimeCaptureActive;

static unsigned long long SCIULLFromObject(id obj) {
    if (!obj || obj == (id)kCFNull) return 0;
    const char *s = [[obj description] UTF8String];
    return s ? strtoull(s, NULL, 10) : 0;
}

@implementation SCIMobileConfigRuntime

+ (NSString *)keyForParamID:(unsigned long long)paramID type:(NSString *)type {
    return [NSString stringWithFormat:@"%@:%llu", type ?: @"unknown", paramID];
}

+ (NSString *)stringForValue:(id)value {
    if (!value || value == (id)kCFNull) return @"";
    if ([value isKindOfClass:NSString.class]) return value;
    if ([value isKindOfClass:NSNumber.class]) return [(NSNumber *)value stringValue];
    return [[value description] copy] ?: @"";
}

+ (NSString *)hexStringForULL:(unsigned long long)v {
    return [[NSString stringWithFormat:@"%llx", v] lowercaseString];
}

+ (NSString *)decimalStringForULL:(unsigned long long)v {
    return [NSString stringWithFormat:@"%llu", v];
}

+ (void)ensureLiveObjects {
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        sLiveObjects = [NSMapTable weakToStrongObjectsMapTable];
    });
}

+ (NSString *)addressStringForObject:(id)obj {
    return obj ? [NSString stringWithFormat:@"%p", obj] : @"";
}

+ (NSString *)shortDescriptionForObject:(id)obj {
    if (!obj) return @"";
    @try {
        NSString *d = [[obj description] copy] ?: @"";
        if (d.length > 180) d = [[d substringToIndex:180] stringByAppendingString:@"…"];
        return d;
    } @catch (__unused NSException *e) { return @"<description threw>"; }
}

+ (void)noteLiveObject:(id)object role:(NSString *)role source:(NSString *)source {
    if (!object) return;
    [SCIDogfoodObjectRuntime noteObject:object role:role ?: @"MobileConfig live object" source:source];
    [self ensureLiveObjects];
    @synchronized (sLiveObjects) {
        NSMutableDictionary *d = [sLiveObjects objectForKey:object];
        if (!d) {
            d = [@{
                @"address": [self addressStringForObject:object],
                @"class": NSStringFromClass([object class]) ?: @"",
                @"firstSeen": @([NSDate.date timeIntervalSince1970])
            } mutableCopy];
            [sLiveObjects setObject:d forKey:object];
        }
        d[@"lastSeen"] = @([NSDate.date timeIntervalSince1970]);
        NSMutableArray *roles = [d[@"roles"] mutableCopy] ?: [NSMutableArray array];
        if (role.length && ![roles containsObject:role]) [roles addObject:role];
        d[@"roles"] = roles;
        NSMutableArray *sources = [d[@"sources"] mutableCopy] ?: [NSMutableArray array];
        if (source.length && ![sources containsObject:source]) [sources addObject:source];
        d[@"sources"] = sources;
    }
}

+ (id)safeObjectFromObject:(id)obj selectorName:(NSString *)selectorName {
    if (!obj || !selectorName.length) return nil;
    SEL sel = NSSelectorFromString(selectorName);
    if (![obj respondsToSelector:sel]) return nil;
    @try {
        id (*msg)(id, SEL) = (id (*)(id, SEL))objc_msgSend;
        return msg(obj, sel);
    } @catch (__unused NSException *e) { return nil; }
}

+ (void)noteRelatedObjectsFromObject:(id)obj source:(NSString *)source {
    if (!obj) return;
    id mc = [self safeObjectFromObject:obj selectorName:@"mc"];
    if (mc) [self noteLiveObject:mc role:@"mc object" source:source ?: NSStringFromClass([obj class])];
    id launcherSet = [self safeObjectFromObject:obj selectorName:@"asIGUserLauncherSetForMigrationPurposesOnly"];
    if (launcherSet) [self noteLiveObject:launcherSet role:@"IGUserLauncherSet" source:source ?: NSStringFromClass([obj class])];
    for (NSString *ivarName in @[@"_launcherSet", @"_emptyContext"]) {
        @try {
            Ivar iv = class_getInstanceVariable([obj class], ivarName.UTF8String);
            const char *type = iv ? ivar_getTypeEncoding(iv) : NULL;
            if (iv && type && type[0] == '@') {
                id v = object_getIvar(obj, iv);
                if (v) [self noteLiveObject:v role:ivarName source:source ?: NSStringFromClass([obj class])];
            }
        } @catch (__unused NSException *e) {}
    }
}

+ (NSArray<NSString *> *)interestingSelectorsForClass:(Class)cls {
    if (!cls) return @[];
    NSMutableArray *out = [NSMutableArray array];
    NSMutableSet *seen = [NSMutableSet set];
    for (Class c = cls; c && c != NSObject.class; c = class_getSuperclass(c)) {
        unsigned int count = 0;
        Method *methods = class_copyMethodList(c, &count);
        for (unsigned int i = 0; i < count; i++) {
            SEL sel = method_getName(methods[i]);
            NSString *name = NSStringFromSelector(sel).lowercaseString;
            if (!name.length || [seen containsObject:name]) continue;
            BOOL keep = [name containsString:@"metadata"] || [name containsString:@"specifier"] || [name containsString:@"stable"] || [name containsString:@"param"] || [name containsString:@"launcher"] || [name containsString:@"session"] || [name isEqualToString:@"mc"];
            if (keep) {
                [seen addObject:name];
                [out addObject:NSStringFromSelector(sel)];
            }
        }
        if (methods) free(methods);
        if (out.count >= 24) break;
    }
    return out;
}

+ (NSArray<NSDictionary *> *)ivarSummariesForObject:(id)obj {
    if (!obj) return @[];
    NSMutableArray *out = [NSMutableArray array];
    for (Class c = [obj class]; c && c != NSObject.class && out.count < 32; c = class_getSuperclass(c)) {
        unsigned int count = 0;
        Ivar *ivars = class_copyIvarList(c, &count);
        for (unsigned int i = 0; i < count && out.count < 32; i++) {
            Ivar iv = ivars[i];
            NSString *name = @(ivar_getName(iv) ?: "");
            NSString *type = @(ivar_getTypeEncoding(iv) ?: "");
            NSMutableDictionary *d = [@{ @"name": name ?: @"", @"type": type ?: @"", @"offset": @(ivar_getOffset(iv)), @"owner": NSStringFromClass(c) ?: @"" } mutableCopy];
            if ([name isEqualToString:@"_specifierToMetadata"]) {
                d[@"value"] = @"native C++ unordered_map present; not dereferenced directly";
                d[@"hint"] = @"Use getStableIdFromParamSpecifier: and captured getter args";
            } else if (type.length && [type hasPrefix:@"@"] ) {
                @try {
                    id v = object_getIvar(obj, iv);
                    if (v) {
                        d[@"value"] = [NSString stringWithFormat:@"%@ %@", NSStringFromClass([v class]) ?: @"id", [self addressStringForObject:v]];
                        d[@"description"] = [self shortDescriptionForObject:v];
                    } else {
                        d[@"value"] = @"nil";
                    }
                } @catch (__unused NSException *e) { d[@"value"] = @"<object_getIvar threw>"; }
            } else {
                d[@"value"] = @"non-object ivar";
            }
            [out addObject:d];
        }
        if (ivars) free(ivars);
    }
    return out;
}

+ (NSArray<NSDictionary *> *)liveContexts {
    [self ensureLiveObjects];
    NSMutableArray *out = [NSMutableArray array];
    @synchronized (sLiveObjects) {
        NSEnumerator *e = [sLiveObjects keyEnumerator];
        id obj = nil;
        while ((obj = [e nextObject])) {
            NSMutableDictionary *base = [[sLiveObjects objectForKey:obj] mutableCopy] ?: [NSMutableDictionary dictionary];
            base[@"address"] = [self addressStringForObject:obj];
            base[@"class"] = NSStringFromClass([obj class]) ?: @"";
            base[@"description"] = [self shortDescriptionForObject:obj];
            NSString *sessionID = [self sessionIDFromObject:obj];
            if (sessionID.length) base[@"sessionID"] = sessionID;
            id mc = [self safeObjectFromObject:obj selectorName:@"mc"];
            if (mc) base[@"mc"] = [NSString stringWithFormat:@"%@ %@", NSStringFromClass([mc class]) ?: @"id", [self addressStringForObject:mc]];
            id launcherSet = [self safeObjectFromObject:obj selectorName:@"asIGUserLauncherSetForMigrationPurposesOnly"];
            if (launcherSet) base[@"launcherSet"] = [NSString stringWithFormat:@"%@ %@", NSStringFromClass([launcherSet class]) ?: @"id", [self addressStringForObject:launcherSet]];
            base[@"interestingSelectors"] = [self interestingSelectorsForClass:[obj class]];
            base[@"ivars"] = [self ivarSummariesForObject:obj];
            [out addObject:base];
        }
    }
    return [out sortedArrayUsingComparator:^NSComparisonResult(NSDictionary *a, NSDictionary *b) {
        NSString *ca = [a[@"class"] description], *cb = [b[@"class"] description];
        NSComparisonResult r = [ca compare:cb];
        if (r != NSOrderedSame) return r;
        return [[a[@"address"] description] compare:[b[@"address"] description]];
    }];
}


+ (void)ensureLoaded {
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        sObs = [NSMutableDictionary new];
        NSArray *saved = [NSUserDefaults.standardUserDefaults arrayForKey:kObsKey];
        for (NSDictionary *d in saved) {
            if (![d isKindOfClass:NSDictionary.class]) continue;
            NSString *pid = [d[@"paramID"] description];
            NSString *type = [d[@"type"] description];
            if (!pid.length || !type.length) continue;
            sObs[[self keyForParamID:SCIULLFromObject(pid) type:type]] = [d mutableCopy];
        }
    });
}

+ (BOOL)runtimeHooksEnabled {
    return sRuntimeCaptureActive;
}

+ (void)setRuntimeCaptureActive:(BOOL)active {
    @synchronized (self) {
        if (sRuntimeCaptureActive == active) return;
        sRuntimeCaptureActive = active;
    }

    NSUserDefaults *d = NSUserDefaults.standardUserDefaults;
    if (active) {
        sRuntimeStartTime = [NSDate.date timeIntervalSince1970];
        [d removeObjectForKey:kDisabledByGuardKey];
        [d setInteger:0 forKey:kBootCountKey];
        dispatch_async(dispatch_get_main_queue(), ^{ SCIInstallMobileConfigRuntimeHooksIfNeeded(); });
    } else {
        [self flushIfNeededForce:YES];
    }
    [d synchronize];
    [[NSNotificationCenter defaultCenter] postNotificationName:NSUserDefaultsDidChangeNotification object:d userInfo:@{ @"key": kEnabledKey }];
}

+ (BOOL)manualOverridesEnabled {
    return [SCIUtils getBoolPref:kManualKey];
}

+ (BOOL)checkAndArmCrashGuard {
    if (![self runtimeHooksEnabled]) return NO;
    NSUserDefaults *d = NSUserDefaults.standardUserDefaults;
    NSInteger c = [d integerForKey:kBootCountKey];
    if (c >= 3) {
        [d setBool:NO forKey:kEnabledKey];
        [d setBool:YES forKey:kDisabledByGuardKey];
        [d setInteger:0 forKey:kBootCountKey];
        [d synchronize];
        return YES;
    }
    [d setInteger:c + 1 forKey:kBootCountKey];
    [d synchronize];
    return NO;
}

+ (void)markLaunchStable {
    NSUserDefaults *d = NSUserDefaults.standardUserDefaults;
    [d setInteger:0 forKey:kBootCountKey];
    [d removeObjectForKey:kDisabledByGuardKey];
    [d synchronize];
}

+ (void)flushIfNeededForce:(BOOL)force {
    NSDate *now = [NSDate date];
    if (!force && sLastFlush && [now timeIntervalSinceDate:sLastFlush] < 5.0) return;
    sLastFlush = now;
    NSArray *arr = [[sObs allValues] sortedArrayUsingComparator:^NSComparisonResult(NSDictionary *a, NSDictionary *b) {
        NSInteger ca = [a[@"count"] integerValue], cb = [b[@"count"] integerValue];
        if (ca > cb) return NSOrderedAscending;
        if (ca < cb) return NSOrderedDescending;
        return [[b[@"lastSeen"] description] compare:[a[@"lastSeen"] description]];
    }];
    if (arr.count > 700) arr = [arr subarrayWithRange:NSMakeRange(0, 700)];
    [NSUserDefaults.standardUserDefaults setObject:arr forKey:kObsKey];
}

+ (nullable NSString *)sessionIDFromObject:(id)obj {
    if (!obj) return nil;
    @try {
        SEL s = NSSelectorFromString(@"sessionID");
        if ([obj respondsToSelector:s]) {
            id (*msg)(id, SEL) = (id (*)(id, SEL))objc_msgSend;
            id v = msg(obj, s);
            NSString *out = [self stringForValue:v];
            if (out.length) return out;
        }
    } @catch (__unused NSException *e) {}
    @try {
        Ivar iv = class_getInstanceVariable([obj class], "_sessionID");
        if (iv) {
            id v = object_getIvar(obj, iv);
            NSString *out = [self stringForValue:v];
            if (out.length) return out;
        }
    } @catch (__unused NSException *e) {}
    return nil;
}

+ (nullable NSString *)nativeStableIDFromObject:(id)obj paramID:(unsigned long long)paramID usedObject:(NSString * _Nullable * _Nullable)usedObject {
    if (!obj) return nil;
    SEL sel = NSSelectorFromString(@"getStableIdFromParamSpecifier:");
    NSArray *targets = nil;
    id mcObj = nil;
    @try {
        SEL mcSel = NSSelectorFromString(@"mc");
        if ([obj respondsToSelector:mcSel]) {
            id (*mcMsg)(id, SEL) = (id (*)(id, SEL))objc_msgSend;
            mcObj = mcMsg(obj, mcSel);
        }
    } @catch (__unused NSException *e) {}
    targets = mcObj ? @[obj, mcObj] : @[obj];
    for (id target in targets) {
        if (![target respondsToSelector:sel]) continue;
        @try {
            NSMethodSignature *sig = [target methodSignatureForSelector:sel];
            const char *rt = sig.methodReturnType;
            if (!rt) continue;
            while (*rt == 'r' || *rt == 'n' || *rt == 'N' || *rt == 'o' || *rt == 'O' || *rt == 'R' || *rt == 'V') rt++;
            if (*rt == '@') {
                id (*msg)(id, SEL, unsigned long long) = (id (*)(id, SEL, unsigned long long))objc_msgSend;
                id v = msg(target, sel, paramID);
                NSString *out = [self stringForValue:v];
                if (out.length) {
                    if (usedObject) *usedObject = NSStringFromClass([target class]);
                    return out;
                }
            } else if (*rt == 'Q' || *rt == 'q' || *rt == 'I' || *rt == 'i' || *rt == 'L' || *rt == 'l') {
                unsigned long long (*msg)(id, SEL, unsigned long long) = (unsigned long long (*)(id, SEL, unsigned long long))objc_msgSend;
                unsigned long long v = msg(target, sel, paramID);
                if (usedObject) *usedObject = NSStringFromClass([target class]);
                return [self decimalStringForULL:v];
            }
        } @catch (__unused NSException *e) {}
    }
    return nil;
}


+ (BOOL)deepCallerSymbolsEnabled {
    return [SCIUtils getBoolPref:kDeepSymbolsKey];
}

+ (NSArray<NSString *> *)interestingNeedles {
    return @[@"dogfood", @"dogfooding", @"dogfooder", @"employee", @"is_employee", @"staff", @"internal", @"internalfb", @"is_internal_build", @"launcher", @"launcherset", @"notes", @"directnotes", @"quicksnap", @"instants", @"mobile_config_debug"];
}

+ (BOOL)onCriticalFacebookQueue {
    // O reader de MobileConfig roda em qualquer thread, inclusive nas filas de
    // banco/rede do Facebook (com.facebook.lightspeed.database.*, MCI/MSGC). Fazer
    // trabalho pesado ali (callStackSymbols, introspecção KVC de objetos Swift)
    // foi a causa do abort() em MCIStatsIncrement (crash 2026-06-17, thread 36).
    // Detecta a fila atual pelo label e bloqueia o enrichment nessas filas.
    const char *label = dispatch_queue_get_label(DISPATCH_CURRENT_QUEUE_LABEL);
    if (!label) return NO;
    return (strstr(label, "facebook") != NULL) || (strstr(label, "lightspeed") != NULL) ||
           (strstr(label, "MCI") != NULL) || (strstr(label, "mci") != NULL) ||
           (strstr(label, "mobileconfig") != NULL) || (strstr(label, "MobileConfig") != NULL) ||
           (strstr(label, "database") != NULL) || (strstr(label, "networker") != NULL);
}

+ (BOOL)deepCaptureReady {
    if (![self deepCallerSymbolsEnabled]) return NO;
    // Nunca enriquecer (callStackSymbols) nas filas críticas do FB — causa abort.
    if ([self onCriticalFacebookQueue]) return NO;
    if (sRuntimeStartTime <= 0) sRuntimeStartTime = [NSDate.date timeIntervalSince1970];
    return ([NSDate.date timeIntervalSince1970] - sRuntimeStartTime) > 45.0;
}

+ (NSArray<NSString *> *)filteredCallerSymbols {
    if (![self deepCaptureReady]) return @[];
    NSArray<NSString *> *frames = [NSThread callStackSymbols];
    NSMutableArray *out = [NSMutableArray array];
    NSArray *needles = [self interestingNeedles];
    for (NSString *frame in frames) {
        NSString *low = frame.lowercaseString;
        if ([low containsString:@"ryukgram.dylib"] || [low containsString:@"scimobileconfig"] || [low containsString:@"sciadaptiveglass"] || [low containsString:@"scifallbackglass"] || [low containsString:@"scidogfoodbrowser"]) continue;
        for (NSString *needle in needles) {
            if ([low containsString:needle]) {
                NSString *shortFrame = frame.length > 220 ? [[frame substringToIndex:220] stringByAppendingString:@"…"] : frame;
                if (![out containsObject:shortFrame]) [out addObject:shortFrame];
                break;
            }
        }
        if (out.count >= 8) break;
    }
    return out;
}

+ (NSArray<NSString *> *)tagsForSourceClass:(NSString *)sourceClass selector:(NSString *)selector callerSymbols:(NSArray<NSString *> *)symbols nativeMeta:(NSDictionary *)nativeMeta mapCandidates:(NSArray<NSDictionary *> *)mapCandidates {
    NSMutableSet *tags = [NSMutableSet set];
    NSMutableString *hay = [NSMutableString stringWithFormat:@"%@ %@ ", sourceClass ?: @"", selector ?: @""];
    for (NSString *s in symbols) [hay appendFormat:@"%@ ", s];
    for (NSString *k in nativeMeta) [hay appendFormat:@"%@ %@ ", k, [nativeMeta[k] description]];
    for (NSDictionary *m in mapCandidates) [hay appendFormat:@"%@ %@ %@ ", m[@"raw"] ?: @"", m[@"match"] ?: @"", m[@"config"] ?: @""];
    NSString *low = hay.lowercaseString;
    NSDictionary *rules = @{
        @"dogfood": @[@"dogfood", @"dogfooding", @"dogfooder"],
        @"employee": @[@"employee", @"is_employee", @"staff"],
        @"internal": @[@"internal", @"internalfb", @"is_internal_build", @"mobile_config_debug_internal"],
        @"launcher": @[@"launcher", @"launcherset"],
        @"notes": @[@"notes", @"directnotes"],
        @"quicksnap": @[@"quicksnap", @"instants"]
    };
    for (NSString *tag in rules) {
        for (NSString *needle in rules[tag]) {
            if ([low containsString:needle]) { [tags addObject:tag]; break; }
        }
    }
    return [[tags allObjects] sortedArrayUsingSelector:@selector(compare:)];
}

+ (id)safeCallParamSelector:(NSString *)selectorName onObject:(id)obj paramID:(unsigned long long)paramID usedObject:(NSString **)usedObject {
    if (!obj || !selectorName.length) return nil;
    SEL sel = NSSelectorFromString(selectorName);
    NSArray *targets = nil;
    id mcObj = nil;
    @try {
        SEL mcSel = NSSelectorFromString(@"mc");
        if ([obj respondsToSelector:mcSel]) {
            id (*mcMsg)(id, SEL) = (id (*)(id, SEL))objc_msgSend;
            mcObj = mcMsg(obj, mcSel);
        }
    } @catch (__unused NSException *e) {}
    targets = mcObj ? @[obj, mcObj] : @[obj];
    for (id target in targets) {
        if (![target respondsToSelector:sel]) continue;
        @try {
            NSMethodSignature *sig = [target methodSignatureForSelector:sel];
            if (!sig || sig.numberOfArguments < 3) continue;
            const char *rt = sig.methodReturnType;
            while (rt && (*rt == 'r' || *rt == 'n' || *rt == 'N' || *rt == 'o' || *rt == 'O' || *rt == 'R' || *rt == 'V')) rt++;
            if (usedObject) *usedObject = NSStringFromClass([target class]);
            if (rt && *rt == '@') {
                id (*msg)(id, SEL, unsigned long long) = (id (*)(id, SEL, unsigned long long))objc_msgSend;
                return msg(target, sel, paramID);
            }
            if (rt && (*rt == 'B' || *rt == 'c')) {
                BOOL (*msg)(id, SEL, unsigned long long) = (BOOL (*)(id, SEL, unsigned long long))objc_msgSend;
                return @(msg(target, sel, paramID));
            }
            if (rt && (*rt == 'Q' || *rt == 'q' || *rt == 'I' || *rt == 'i' || *rt == 'L' || *rt == 'l')) {
                long long (*msg)(id, SEL, unsigned long long) = (long long (*)(id, SEL, unsigned long long))objc_msgSend;
                return @(msg(target, sel, paramID));
            }
            if (rt && (*rt == 'd' || *rt == 'f')) {
                double (*msg)(id, SEL, unsigned long long) = (double (*)(id, SEL, unsigned long long))objc_msgSend;
                return @(msg(target, sel, paramID));
            }
        } @catch (__unused NSException *e) {}
    }
    return nil;
}

+ (NSDictionary *)nativeMetadataFromObject:(id)obj paramID:(unsigned long long)paramID {
    if (!obj) return @{};
    NSMutableDictionary *out = [NSMutableDictionary dictionary];
    NSDictionary *selectors = @{
        @"latestCreator": @"getLatestCreatorForParameter:",
        @"latestCreationSource": @"getLatestCreationSourceForParameter:",
        @"latestRequestTimestamp": @"getLatestRequestTimestampForParameter:",
        @"latestRequestAppVersion": @"getLatestRequestAppVersionForParameter:",
        @"advancedLogging": @"isAdvancedLoggingEnabledForParam:"
    };
    for (NSString *key in selectors) {
        NSString *used = nil;
        id value = [self safeCallParamSelector:selectors[key] onObject:obj paramID:paramID usedObject:&used];
        NSString *str = [self stringForValue:value];
        if (str.length) {
            out[key] = str;
            if (used.length) out[[key stringByAppendingString:@"Resolver"]] = used;
        }
    }
    return out;
}

+ (BOOL)paramDictionaryLooksDogfood:(NSDictionary *)d {
    NSMutableString *hay = [NSMutableString string];
    for (NSString *k in d) {
        id v = d[k];
        [hay appendFormat:@"%@ %@ ", k, [v description]];
        if ([v isKindOfClass:NSArray.class]) for (id x in (NSArray *)v) [hay appendFormat:@"%@ ", [x description]];
        if ([v isKindOfClass:NSDictionary.class]) for (id kk in (NSDictionary *)v) [hay appendFormat:@"%@ %@ ", kk, [v[kk] description]];
    }
    NSString *low = hay.lowercaseString;
    for (NSString *needle in [self interestingNeedles]) if ([low containsString:needle]) return YES;
    return NO;
}

+ (NSArray<NSDictionary *> *)dogfoodCandidateParams {
    NSMutableArray *out = [NSMutableArray array];
    for (NSDictionary *d in [self hotParams]) {
        NSArray *tags = [d[@"tags"] isKindOfClass:NSArray.class] ? d[@"tags"] : @[];
        BOOL tagged = tags.count > 0;
        if (!tagged && [self paramDictionaryLooksDogfood:d]) tagged = YES;
        if (tagged) [out addObject:d];
    }
    return out;
}

+ (void)recordParamID:(unsigned long long)paramID
                 type:(NSString *)type
             returned:(id)returned
         defaultValue:(id)defaultValue
          sourceClass:(NSString *)sourceClass
             selector:(NSString *)selector
{
    [self recordParamID:paramID type:type returned:returned defaultValue:defaultValue sourceObject:nil selector:selector];
    if (!sourceClass.length) return;
    [self ensureLoaded];
    @synchronized (sObs) {
        NSMutableDictionary *d = sObs[[self keyForParamID:paramID type:type]];
        if (d && ![d[@"sourceClass"] description].length) d[@"sourceClass"] = sourceClass;
    }
}

+ (void)recordParamID:(unsigned long long)paramID
                 type:(NSString *)type
             returned:(id)returned
         defaultValue:(id)defaultValue
         sourceObject:(id)sourceObject
             selector:(NSString *)selector
{
    if (![self runtimeHooksEnabled]) return;
    if (sInsideMCRecord) return;
    sInsideMCRecord = YES;
    @try {
    if (sRuntimeStartTime <= 0) sRuntimeStartTime = [NSDate.date timeIntervalSince1970];
    [self ensureLoaded];
    NSString *key = [self keyForParamID:paramID type:type];
    // Name<->paramID binding: when a gating getter is being evaluated under a marker
    // (set by beginBindingForName:), the param it reads here belongs to that flag.
    {
        NSMutableDictionary *btd = NSThread.currentThread.threadDictionary;
        if (btd[@"sci_bind_name"]) {
            id bk = btd[@"sci_bind_keys"];
            if ([bk isKindOfClass:NSMutableArray.class] && ![bk containsObject:key]) [bk addObject:key];
        }
    }
    NSString *sourceClass = sourceObject ? NSStringFromClass([sourceObject class]) : @"";
    BOOL shouldEnrich = NO;
    @synchronized (sObs) {
        NSMutableDictionary *existing = sObs[key];
        NSInteger c = [existing[@"count"] integerValue];
        shouldEnrich = (!existing || c < 2 || (c % 500) == 0);
    }
    // A introspecção pesada (KVC/ivars de objetos Swift, callStackSymbols) NÃO
    // pode rodar nas filas críticas do FB (DB/MCI/networker) — é onde o app
    // aborta. Nessas filas, só registramos o paramID/valor (barato e seguro).
    if (shouldEnrich && [self onCriticalFacebookQueue]) shouldEnrich = NO;
    if (sourceObject && shouldEnrich) {
        [self noteLiveObject:sourceObject role:@"getter source" source:selector ?: @""];
        [self noteRelatedObjectsFromObject:sourceObject source:selector ?: sourceClass];
    }
    NSString *stableResolver = nil;
    NSString *stableID = (sourceObject && shouldEnrich) ? [self nativeStableIDFromObject:sourceObject paramID:paramID usedObject:&stableResolver] : nil;
    NSString *sessionID = (sourceObject && shouldEnrich) ? [self sessionIDFromObject:sourceObject] : nil;
    NSArray *candidates = shouldEnrich ? [self mapCandidatesForParamID:paramID stableID:stableID] : @[];
    NSDictionary *nativeMeta = (sourceObject && shouldEnrich) ? [self nativeMetadataFromObject:sourceObject paramID:paramID] : @{};
    NSArray *callerSymbols = shouldEnrich ? [self filteredCallerSymbols] : @[];
    NSArray *tags = shouldEnrich ? [self tagsForSourceClass:sourceClass selector:selector callerSymbols:callerSymbols nativeMeta:nativeMeta mapCandidates:candidates] : @[];
    @synchronized (sObs) {
        NSMutableDictionary *d = sObs[key];
        NSTimeInterval now = [NSDate.date timeIntervalSince1970];
        if (!d) {
            d = [@{
                @"paramID": [self decimalStringForULL:paramID],
                @"hex": [NSString stringWithFormat:@"0x%@", [self hexStringForULL:paramID]],
                @"low32": [self decimalStringForULL:(paramID & 0xffffffffULL)],
                @"low32Hex": [NSString stringWithFormat:@"0x%@", [self hexStringForULL:(paramID & 0xffffffffULL)]],
                @"high32": [self decimalStringForULL:(paramID >> 32)],
                @"type": type ?: @"unknown",
                @"count": @0,
                @"firstSeen": @(now)
            } mutableCopy];
            sObs[key] = d;
        }
        d[@"count"] = @([d[@"count"] integerValue] + 1);
        d[@"lastSeen"] = @(now);
        d[@"returned"] = [self stringForValue:returned];
        if (defaultValue) d[@"default"] = [self stringForValue:defaultValue];
        if (sourceClass.length) d[@"sourceClass"] = sourceClass;
        if (selector.length) d[@"selector"] = selector;
        if (stableID.length) {
            d[@"stableID"] = stableID;
            unsigned long long sv = strtoull(stableID.UTF8String, NULL, 10);
            if (sv) d[@"stableHex"] = [NSString stringWithFormat:@"0x%@", [self hexStringForULL:sv]];
        }
        if (stableResolver.length) d[@"stableResolver"] = stableResolver;
        if (sessionID.length) d[@"sessionID"] = sessionID;
        if (nativeMeta.count) d[@"nativeMeta"] = nativeMeta;
        if (callerSymbols.count) d[@"callerSymbols"] = callerSymbols;
        if (tags.count) d[@"tags"] = tags;
        if (candidates.count) {
            d[@"mapCandidates"] = candidates;
            NSDictionary *m = candidates.firstObject;
            d[@"map"] = [NSString stringWithFormat:@"%@:%@ %@ %@", m[@"file"] ?: @"params_map", m[@"line"] ?: @0, m[@"match"] ?: @"", m[@"raw"] ?: @""];
        }
    }
    [self flushIfNeededForce:NO];
    } @finally {
        sInsideMCRecord = NO;
    }
}

+ (NSArray<NSDictionary *> *)hotParams {
    [self ensureLoaded];
    @synchronized (sObs) {
        return [[[sObs allValues] sortedArrayUsingComparator:^NSComparisonResult(NSDictionary *a, NSDictionary *b) {
            NSInteger ca = [a[@"count"] integerValue], cb = [b[@"count"] integerValue];
            if (ca > cb) return NSOrderedAscending;
            if (ca < cb) return NSOrderedDescending;
            return [[b[@"lastSeen"] description] compare:[a[@"lastSeen"] description]];
        }] copy];
    }
}

+ (void)clearObservations {
    [self ensureLoaded];
    @synchronized (sObs) { [sObs removeAllObjects]; }
    [NSUserDefaults.standardUserDefaults removeObjectForKey:kObsKey];
}

+ (NSArray<NSString *> *)candidateMapRoots {
    NSMutableArray *roots = [NSMutableArray array];
    NSString *home = NSHomeDirectory();
    if (home.length) {
        [roots addObject:home];
        [roots addObject:[home stringByAppendingPathComponent:@"Documents"]];
        [roots addObject:[home stringByAppendingPathComponent:@"Library"]];
    }
    NSURL *group = [NSFileManager.defaultManager containerURLForSecurityApplicationGroupIdentifier:@"group.com.burbn.instagram"];
    if (group.path.length) [roots addObject:group.path];
    return roots;
}

+ (NSArray<NSString *> *)findParamsMapFilesUnder:(NSString *)root maxDepth:(NSInteger)maxDepth {
    if (!root.length || maxDepth < 0) return @[];
    BOOL isDir = NO;
    if (![NSFileManager.defaultManager fileExistsAtPath:root isDirectory:&isDir] || !isDir) return @[];
    NSMutableArray *out = [NSMutableArray array];
    NSDirectoryEnumerator *e = [NSFileManager.defaultManager enumeratorAtURL:[NSURL fileURLWithPath:root]
                                                  includingPropertiesForKeys:@[NSURLIsDirectoryKey]
                                                                     options:NSDirectoryEnumerationSkipsHiddenFiles
                                                                errorHandler:nil];
    for (NSURL *url in e) {
        NSString *rel = [url.path substringFromIndex:root.length];
        NSUInteger depth = [[rel componentsSeparatedByString:@"/"] count];
        if ((NSInteger)depth > maxDepth) { [e skipDescendants]; continue; }
        NSString *name = url.lastPathComponent.lowercaseString;
        if ([name hasPrefix:@"params_map"] && [name hasSuffix:@".txt"]) [out addObject:url.path];
    }
    return out;
}

+ (BOOL)parseToken:(NSString *)token asHex:(BOOL)hex out:(unsigned long long *)outValue {
    if (!token.length || !outValue) return NO;
    NSString *t = [token stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet].lowercaseString;
    if (!t.length || [t isEqualToString:@"*"]) return NO;
    if ([t hasPrefix:@"0x"]) { t = [t substringFromIndex:2]; hex = YES; }
    NSCharacterSet *bad = hex ? [[NSCharacterSet characterSetWithCharactersInString:@"0123456789abcdef"] invertedSet] : [[NSCharacterSet decimalDigitCharacterSet] invertedSet];
    if ([t rangeOfCharacterFromSet:bad].location != NSNotFound) return NO;
    *outValue = strtoull(t.UTF8String, NULL, hex ? 16 : 10);
    return YES;
}

+ (void)addMapHit:(NSDictionary *)hit key:(NSString *)key into:(NSMutableDictionary<NSString *, NSMutableArray<NSDictionary *> *> *)idx {
    if (!key.length || !hit) return;
    NSMutableArray *arr = idx[key];
    if (!arr) { arr = [NSMutableArray array]; idx[key] = arr; }
    if (arr.count < 20) [arr addObject:hit];
}

+ (void)indexV2ParamsMap:(NSString *)txt file:(NSString *)file into:(NSMutableDictionary<NSString *, NSMutableArray<NSDictionary *> *> *)idx {
    __block NSUInteger lineNo = 0;
    __block NSString *currentConfig = @"";
    [txt enumerateLinesUsingBlock:^(NSString *line, BOOL *stop) {
        lineNo++;
        if (lineNo == 1 || !line.length) return;
        NSArray<NSString *> *parts = [line componentsSeparatedByString:@","];
        NSString *first = parts.count > 0 ? [parts[0] stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet] : @"";
        if ([first isEqualToString:@"*"] && parts.count >= 3) {
            NSString *cfg = [parts[2] stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet];
            if (cfg.length) currentConfig = cfg;
        }
        for (NSUInteger i = 0; i < parts.count; i++) {
            NSString *tok = [parts[i] stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet];
            if (!tok.length || [tok isEqualToString:@"*"]) continue;
            unsigned long long dec = 0, hex = 0;
            BOOL okDec = [self parseToken:tok asHex:NO out:&dec];
            BOOL okHex = [self parseToken:tok asHex:YES out:&hex];
            NSDictionary *hit = @{ @"file": file ?: @"params_map.txt",
                                   @"line": @(lineNo),
                                   @"column": @(i + 1),
                                   @"token": tok,
                                   @"config": currentConfig ?: @"",
                                   @"match": [NSString stringWithFormat:@"v2 col%lu token=%@ config=%@", (unsigned long)(i + 1), tok, currentConfig ?: @""],
                                   @"raw": line };
            if (okDec) [self addMapHit:hit key:[NSString stringWithFormat:@"dec:%llu", dec] into:idx];
            if (okHex) [self addMapHit:hit key:[NSString stringWithFormat:@"hex:%@", [self hexStringForULL:hex]] into:idx];
        }
    }];
}

+ (void)indexV4ParamsMap:(NSData *)data file:(NSString *)file into:(NSMutableDictionary<NSString *, NSMutableArray<NSDictionary *> *> *)idx {
    if (data.length < 80) return;
    const uint8_t *b = data.bytes;
    NSUInteger start = 0;
    for (NSUInteger i = 0; i + 32 < data.length && i < 128; i++) {
        BOOL hexish = YES;
        for (NSUInteger j = 0; j < 32; j++) {
            uint8_t c = b[i + j];
            if (!((c >= '0' && c <= '9') || (c >= 'a' && c <= 'f') || (c >= 'A' && c <= 'F'))) { hexish = NO; break; }
        }
        if (hexish) { start = i + 32; break; }
    }
    if (!start) return;
    NSUInteger limit = MIN(data.length, start + 1024 * 128);
    for (NSUInteger off = start; off + 8 <= limit; off += 8) {
        unsigned long long v = 0;
        memcpy(&v, b + off, 8);
        if (!v) continue;
        NSDictionary *hit = @{ @"file": file ?: @"params_map_v4_u0.txt",
                               @"line": @(0),
                               @"offset": @(off),
                               @"token": [self decimalStringForULL:v],
                               @"match": [NSString stringWithFormat:@"v4 u64@0x%lx", (unsigned long)off],
                               @"raw": [NSString stringWithFormat:@"binary v4 offset 0x%lx", (unsigned long)off] };
        [self addMapHit:hit key:[NSString stringWithFormat:@"dec:%llu", v] into:idx];
        [self addMapHit:hit key:[NSString stringWithFormat:@"hex:%@", [self hexStringForULL:v]] into:idx];
        unsigned long long lo32 = v & 0xffffffffULL;
        if (lo32) [self addMapHit:hit key:[NSString stringWithFormat:@"hex:%@", [self hexStringForULL:lo32]] into:idx];
    }
}

+ (void)reloadParamsMapIndex {
    NSMutableDictionary *idx = [NSMutableDictionary dictionary];
    for (NSString *root in [self candidateMapRoots]) {
        for (NSString *path in [self findParamsMapFilesUnder:root maxDepth:8]) {
            NSData *data = [NSData dataWithContentsOfFile:path options:NSDataReadingMappedIfSafe error:nil];
            if (!data.length || data.length > 4 * 1024 * 1024) continue;
            NSString *file = path.lastPathComponent ?: @"params_map";
            if (data.length >= 3 && !memcmp(data.bytes, "v4>", 3)) {
                [self indexV4ParamsMap:data file:file into:idx];
                continue;
            }
            NSString *txt = [[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding];
            if (!txt.length || ![txt hasPrefix:@"v2,"]) continue;
            [self indexV2ParamsMap:txt file:file into:idx];
        }
    }
    sMapIndex = idx;
    sMapLoaded = YES;
}

+ (NSDictionary<NSString *, NSArray<NSDictionary *> *> *)paramsMapIndex {
    if (!sMapLoaded) [self reloadParamsMapIndex];
    return sMapIndex ?: @{};
}

+ (void)addCandidateKeysForULL:(unsigned long long)v into:(NSMutableArray<NSString *> *)keys label:(NSString *)label {
    if (!keys) return;
    [keys addObject:[NSString stringWithFormat:@"dec:%llu|%@", v, label ?: @""]];
    [keys addObject:[NSString stringWithFormat:@"hex:%@|%@", [self hexStringForULL:v], label ?: @""]];
    unsigned long long low32 = v & 0xffffffffULL;
    unsigned long long high32 = v >> 32;
    unsigned long long low16 = v & 0xffffULL;
    if (low32 && low32 != v) [keys addObject:[NSString stringWithFormat:@"hex:%@|%@ low32", [self hexStringForULL:low32], label ?: @""]];
    if (high32) [keys addObject:[NSString stringWithFormat:@"hex:%@|%@ high32", [self hexStringForULL:high32], label ?: @""]];
    if (low16 && low16 != low32 && low16 != v) [keys addObject:[NSString stringWithFormat:@"hex:%@|%@ low16", [self hexStringForULL:low16], label ?: @""]];
}

+ (NSArray<NSDictionary *> *)mapCandidatesForParamID:(unsigned long long)paramID stableID:(NSString *)stableID {
    NSDictionary *idx = [self paramsMapIndex];
    if (!idx.count) return @[];
    NSMutableArray<NSString *> *keys = [NSMutableArray array];
    [self addCandidateKeysForULL:paramID into:keys label:@"specifier"];
    unsigned long long svDec = stableID.length ? strtoull(stableID.UTF8String, NULL, 10) : 0;
    unsigned long long svHex = stableID.length ? strtoull(stableID.UTF8String, NULL, 16) : 0;
    if (svDec) [self addCandidateKeysForULL:svDec into:keys label:@"stableID-dec"];
    if (svHex && svHex != svDec) [self addCandidateKeysForULL:svHex into:keys label:@"stableID-hex"];
    NSMutableArray *out = [NSMutableArray array];
    NSMutableSet *seen = [NSMutableSet set];
    for (NSString *compound in keys) {
        NSArray *parts = [compound componentsSeparatedByString:@"|"];
        NSString *key = parts.firstObject;
        NSString *label = parts.count > 1 ? parts[1] : @"";
        NSArray *hits = idx[key];
        for (NSDictionary *h in hits) {
            NSString *dedupe = [NSString stringWithFormat:@"%@:%@:%@", h[@"file"] ?: @"", h[@"line"] ?: h[@"offset"] ?: @0, h[@"column"] ?: @0];
            if ([seen containsObject:dedupe]) continue;
            [seen addObject:dedupe];
            NSMutableDictionary *m = [h mutableCopy];
            m[@"match"] = [NSString stringWithFormat:@"%@ via %@", h[@"match"] ?: key, label.length ? label : key];
            [out addObject:m];
            if (out.count >= 6) return out;
        }
    }
    return out;
}

+ (NSString *)mapSummaryForParamID:(unsigned long long)paramID {
    NSDictionary *m = [self mapCandidatesForParamID:paramID stableID:nil].firstObject;
    if (!m) return @"";
    return [NSString stringWithFormat:@"%@:%@ %@ %@", m[@"file"] ?: @"params_map", m[@"line"] ?: m[@"offset"] ?: @0, m[@"match"] ?: @"", m[@"raw"] ?: @""];
}

+ (NSDictionary<NSString *, id> *)manualOverrides {
    NSDictionary *d = [NSUserDefaults.standardUserDefaults dictionaryForKey:kOverridesKey];
    return [d isKindOfClass:NSDictionary.class] ? d : @{};
}

+ (id)overrideForParamID:(unsigned long long)paramID type:(NSString *)type original:(id)original {
    if (![self runtimeHooksEnabled] || ![self manualOverridesEnabled]) return nil;
    NSDictionary *overrides = [self manualOverrides];
    id v = overrides[[self keyForParamID:paramID type:type]];
    return v ?: nil;
}

+ (void)setManualOverride:(id)value paramID:(unsigned long long)paramID type:(NSString *)type {
    if (!value || !type.length) return;
    NSMutableDictionary *d = [[self manualOverrides] mutableCopy];
    d[[self keyForParamID:paramID type:type]] = value;
    [NSUserDefaults.standardUserDefaults setObject:d forKey:kOverridesKey];
    [NSUserDefaults.standardUserDefaults synchronize];
}

+ (void)removeManualOverrideForParamID:(unsigned long long)paramID type:(NSString *)type {
    NSMutableDictionary *d = [[self manualOverrides] mutableCopy];
    [d removeObjectForKey:[self keyForParamID:paramID type:type]];
    [NSUserDefaults.standardUserDefaults setObject:d forKey:kOverridesKey];
    [NSUserDefaults.standardUserDefaults synchronize];
}

// ---- name<->paramID binding (used by the gating patcher) ----

+ (void)beginBindingForName:(NSString *)name {
    if (!name.length) return;
    NSMutableDictionary *td = NSThread.currentThread.threadDictionary;
    td[@"sci_bind_name"] = name;
    td[@"sci_bind_keys"] = [NSMutableArray array];
}

+ (NSArray<NSString *> *)endBinding {
    NSMutableDictionary *td = NSThread.currentThread.threadDictionary;
    NSString *name = td[@"sci_bind_name"];
    NSArray *keys = [td[@"sci_bind_keys"] copy] ?: @[];
    [td removeObjectForKey:@"sci_bind_name"];
    [td removeObjectForKey:@"sci_bind_keys"];
    if (name.length && keys.count) {
        NSUserDefaults *ud = NSUserDefaults.standardUserDefaults;
        @synchronized (sObs) {
            NSMutableDictionary *map = [[ud dictionaryForKey:kBindMapKey] mutableCopy] ?: [NSMutableDictionary dictionary];
            NSMutableArray *existing = [map[name] mutableCopy] ?: [NSMutableArray array];
            for (NSString *k in keys) if (![existing containsObject:k]) [existing addObject:k];
            map[name] = existing;
            [ud setObject:map forKey:kBindMapKey];
            [ud synchronize];
        }
    }
    return keys;
}

+ (NSArray<NSString *> *)boundKeysForName:(NSString *)name {
    NSDictionary *map = [NSUserDefaults.standardUserDefaults dictionaryForKey:kBindMapKey];
    id a = map[name];
    return [a isKindOfClass:NSArray.class] ? a : @[];
}

+ (NSString *)nameForKey:(NSString *)key {
    NSDictionary *map = [NSUserDefaults.standardUserDefaults dictionaryForKey:kBindMapKey];
    for (NSString *n in map) { if ([map[n] containsObject:key]) return n; }
    return nil;
}

+ (void)applyOverrideValue:(id)value forKey:(NSString *)key {
    NSRange r = [key rangeOfString:@":"];
    if (r.location == NSNotFound) return;
    NSString *type = [key substringToIndex:r.location];
    unsigned long long pid = strtoull([key substringFromIndex:r.location + 1].UTF8String, NULL, 10);
    if (value) [self setManualOverride:value paramID:pid type:type];
    else [self removeManualOverrideForParamID:pid type:type];
}

+ (void)setBoolOverride:(BOOL)v forName:(NSString *)name {
    for (NSString *k in [self boundKeysForName:name]) [self applyOverrideValue:@(v) forKey:k];
}

+ (void)clearOverrideForName:(NSString *)name {
    for (NSString *k in [self boundKeysForName:name]) [self applyOverrideValue:nil forKey:k];
}

+ (NSNumber *)overrideStateForName:(NSString *)name {
    NSDictionary *ov = [self manualOverrides];
    for (NSString *k in [self boundKeysForName:name]) { id v = ov[k]; if (v) return @([v boolValue]); }
    return nil;
}

+ (void)clearManualOverrides {
    [NSUserDefaults.standardUserDefaults removeObjectForKey:kOverridesKey];
}

@end
