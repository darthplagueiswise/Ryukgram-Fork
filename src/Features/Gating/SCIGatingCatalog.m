#import "SCIGatingCatalog.h"
#import "../Dogfooding/SCIDogfoodObjectRuntime.h"
#import <objc/runtime.h>
#import <objc/message.h>
#import <substrate.h>

static NSString *const kBlacklistKey = @"sci_gating_eval_blacklist";
static NSString *const kPendingKey   = @"sci_gating_eval_pending";
static NSString *const kDirectOverridesKey = @"sci_gating_direct_bool_overrides";
static NSString *const kRuntimeBoolOverridesKey = @"sci_runtime_direct_bool_overrides_v2";

static NSMutableDictionary<NSString *, NSValue *> *sSCIGatingOriginalIMPs;
static NSMutableSet<NSString *> *sSCIGatingHookedNames;

// ---- Swift name demangling (best-effort, just enough for display) ----
// Turns _TtC19IGPermissionsGatingP33_<hash>23IGPermissionsGatingImpl into
// "IGPermissionsGating.IGPermissionsGatingImpl". Falls back to the raw name.
static NSString *SCIDemangle(NSString *raw) {
    if (![raw hasPrefix:@"_TtC"]) return raw;
    const char *s = raw.UTF8String;
    NSUInteger len = strlen(s);
    NSUInteger i = 4; // past _TtC
    NSMutableArray<NSString *> *parts = [NSMutableArray array];
    while (i < len) {
        // optional private-context marker: P<digits>_<hash>
        if (s[i] == 'P') {
            i++;
            NSUInteger num = 0; BOOL any = NO;
            while (i < len && isdigit(s[i])) { num = num * 10 + (s[i] - '0'); i++; any = YES; }
            if (!any) break;
            i += num; // skip the hash payload
            continue;
        }
        if (!isdigit(s[i])) break;
        NSUInteger num = 0;
        while (i < len && isdigit(s[i])) { num = num * 10 + (s[i] - '0'); i++; }
        if (num == 0 || i + num > len) break;
        NSString *piece = [[NSString alloc] initWithBytes:(s + i) length:num encoding:NSUTF8StringEncoding];
        if (piece.length) [parts addObject:piece];
        i += num;
    }
    if (parts.count == 0) return raw;
    return [parts componentsJoinedByString:@"."];
}

static BOOL SCINameLooksLikeFlag(const char *sel) {
    if (!sel) return NO;
    NSString *n = [NSString stringWithUTF8String:sel];
    if (n.length < 3) return NO;
    if ([n hasSuffix:@"Enabled"] || [n hasSuffix:@"Disabled"]) return YES;
    static NSArray *prefixes;
    static dispatch_once_t once; dispatch_once(&once, ^{
        prefixes = @[@"is", @"should", @"has", @"are", @"can", @"use", @"allow", @"will", @"did", @"enable"];
    });
    for (NSString *p in prefixes) {
        if (n.length > p.length && [n hasPrefix:p]) {
            unichar c = [n characterAtIndex:p.length];
            if (c >= 'A' && c <= 'Z') return YES;
        }
    }
    return NO;
}

static BOOL SCIClassNameInteresting(const char *name) {
    if (!name) return NO;
    if (strstr(name, "FCNews") || strstr(name, "FCIAd")) return NO;
    if (strncmp(name, "FC", 2) == 0 || strncmp(name, "_TtC2FC", 7) == 0) return NO;

    BOOL ownedName =
        strstr(name, "IG") || strstr(name, "Instagram") ||
        strstr(name, "FB") || strstr(name, "Meta") ||
        strstr(name, "MobileConfig") || strstr(name, "Launcher") ||
        strstr(name, "Dogfood") || strstr(name, "Internal");
    if (!ownedName) return NO;

    BOOL featureName =
        strstr(name, "Gating") || strstr(name, "Experiment") ||
        strstr(name, "Rollout") || strstr(name, "FeatureGate") ||
        strstr(name, "InternalOnly") || strstr(name, "Dogfood");
    BOOL settingsName =
        strstr(name, "Config") || strstr(name, "Configuration") ||
        strstr(name, "Settings") || strstr(name, "Helper");
    return featureName || settingsName;
}

static BOOL SCIMethodLooksLikeNoArgumentBool(Method m) {
    if (!m || method_getNumberOfArguments(m) != 2) return NO;
    char ret[8] = {0};
    method_getReturnType(m, ret, sizeof(ret));
    return ret[0] == 'B' || ret[0] == 'c' || ret[0] == 'C';
}

static BOOL SCIClassImageAllowedForScope(Class cls, SCIGatingRuntimeScope scope) {
    const char *image = cls ? class_getImageName(cls) : NULL;
    if (!image) return NO;
    switch (scope) {
        case SCIGatingRuntimeScopeInstagramMain:
            return strstr(image, "/Instagram.app/Instagram") != NULL;
        case SCIGatingRuntimeScopeFBSharedFramework:
            return strstr(image, "/FBSharedFramework.framework/FBSharedFramework") != NULL;
    }
    return NO;
}

static void SCIAppendBoolMethods(Class cls, BOOL classMethod, NSMutableArray<NSDictionary *> *getters) {
    Class target = classMethod ? object_getClass(cls) : cls;
    unsigned int mCount = 0;
    Method *methods = target ? class_copyMethodList(target, &mCount) : NULL;
    if (!methods) return;
    for (unsigned int m = 0; m < mCount; m++) {
        Method meth = methods[m];
        if (!SCIMethodLooksLikeNoArgumentBool(meth)) continue;
        SEL sel = method_getName(meth);
        const char *sname = sel_getName(sel);
        if (!sname || !SCINameLooksLikeFlag(sname)) continue;
        [getters addObject:@{
            @"selector": [NSString stringWithUTF8String:sname],
            @"classMethod": @(classMethod),
        }];
    }
    free(methods);
}

@implementation SCIGatingCatalog

+ (NSString *)displayNameForScope:(SCIGatingRuntimeScope)scope {
    switch (scope) {
        case SCIGatingRuntimeScopeInstagramMain: return @"Instagram executable";
        case SCIGatingRuntimeScopeFBSharedFramework: return @"FBSharedFramework";
    }
    return @"Runtime";
}

+ (NSArray<NSDictionary *> *)catalog {
    NSMutableArray<NSDictionary *> *both = [NSMutableArray array];
    [both addObjectsFromArray:[self catalogForScope:SCIGatingRuntimeScopeInstagramMain]];
    [both addObjectsFromArray:[self catalogForScope:SCIGatingRuntimeScopeFBSharedFramework]];
    return both.copy;
}

+ (NSArray<NSDictionary *> *)catalogForScope:(SCIGatingRuntimeScope)scope {
    static NSMutableDictionary<NSNumber *, NSArray<NSDictionary *> *> *sCatalogByScope;
    static dispatch_once_t once;
    dispatch_once(&once, ^{ sCatalogByScope = [NSMutableDictionary dictionary]; });
    NSNumber *scopeKey = @(scope);
    @synchronized (self) {
        NSArray *cached = sCatalogByScope[scopeKey];
        if (cached) return cached;
    }

    NSMutableArray<NSDictionary *> *out = [NSMutableArray array];
    unsigned int clsCount = 0;
    Class *all = objc_copyClassList(&clsCount);
    if (all) {
        for (unsigned int i = 0; i < clsCount; i++) {
            Class cls = all[i];
            const char *cname = class_getName(cls);
            if (!SCIClassImageAllowedForScope(cls, scope)) continue;
            if (!cname || !SCIClassNameInteresting(cname)) continue;

            NSMutableArray<NSDictionary *> *getters = [NSMutableArray array];
            SCIAppendBoolMethods(cls, NO, getters);
            SCIAppendBoolMethods(cls, YES, getters);
            if (getters.count == 0) continue;

            [getters sortUsingComparator:^NSComparisonResult(NSDictionary *a, NSDictionary *b) {
                NSString *as = [NSString stringWithFormat:@"%@%@", [a[@"classMethod"] boolValue] ? @"+" : @"-", a[@"selector"] ?: @""];
                NSString *bs = [NSString stringWithFormat:@"%@%@", [b[@"classMethod"] boolValue] ? @"+" : @"-", b[@"selector"] ?: @""];
                return [as caseInsensitiveCompare:bs];
            }];
            NSString *raw = [NSString stringWithUTF8String:cname];
            [out addObject:@{ @"class": SCIDemangle(raw), @"raw": raw, @"getters": getters }];
        }
        free(all);
    }
    [out sortUsingComparator:^NSComparisonResult(NSDictionary *a, NSDictionary *b) {
        return [a[@"class"] caseInsensitiveCompare:b[@"class"]];
    }];
    NSArray *built = out.copy;
    @synchronized (self) { sCatalogByScope[scopeKey] = built; }
    return built;
}

+ (NSUInteger)classCount { return [self catalog].count; }

+ (NSUInteger)getterCount {
    NSUInteger n = 0;
    for (NSDictionary *d in [self catalog]) n += [d[@"getters"] count];
    return n;
}

// ---- crash-guarded evaluation ----

+ (NSString *)keyForClass:(NSString *)cls selector:(NSString *)sel {
    return [NSString stringWithFormat:@"%@.%@", cls ?: @"", sel ?: @""];
}

+ (void)reconcileCrashGuardOnLaunch {
    NSUserDefaults *d = NSUserDefaults.standardUserDefaults;
    NSString *pending = [d stringForKey:kPendingKey];
    if (pending.length) {
        NSMutableArray *bl = [[d arrayForKey:kBlacklistKey] mutableCopy] ?: [NSMutableArray array];
        if (![bl containsObject:pending]) [bl addObject:pending];
        [d setObject:bl forKey:kBlacklistKey];
        [d removeObjectForKey:kPendingKey];
        [d synchronize];
    }
}

+ (BOOL)isBlacklistedClass:(NSString *)cls selector:(NSString *)sel {
    NSArray *bl = [NSUserDefaults.standardUserDefaults arrayForKey:kBlacklistKey];
    return [bl containsObject:[self keyForClass:cls selector:sel]];
}

+ (void)clearBlacklist {
    [NSUserDefaults.standardUserDefaults removeObjectForKey:kBlacklistKey];
    [NSUserDefaults.standardUserDefaults removeObjectForKey:kPendingKey];
    [NSUserDefaults.standardUserDefaults synchronize];
}

// Try to find a live, correctly-typed instance so evaluation is safe even for getters
// that read instance ivars. Never call a class IMP with a synthetic receiver.
+ (nullable id)bestReceiverForClass:(Class)cls {
    @try {
        id ref = [SCIDogfoodObjectRuntime liveInstanceOfClass:cls];
        if (ref && [ref isKindOfClass:cls]) return ref;
    } @catch (__unused id e) {}
    return nil;
}

+ (NSString *)canonicalNameForClass:(NSString *)rawClassName selector:(NSString *)selectorName {
    return [NSString stringWithFormat:@"%@#%@", rawClassName ?: @"", selectorName ?: @""];
}

+ (NSDictionary<NSString *, NSNumber *> *)directOverrides {
    NSDictionary *d = [NSUserDefaults.standardUserDefaults dictionaryForKey:kDirectOverridesKey];
    return [d isKindOfClass:NSDictionary.class] ? d : @{};
}

+ (NSDictionary<NSString *, NSNumber *> *)runtimeBoolOverrides {
    NSDictionary *d = [NSUserDefaults.standardUserDefaults dictionaryForKey:kRuntimeBoolOverridesKey];
    return [d isKindOfClass:NSDictionary.class] ? d : @{};
}

+ (nullable NSNumber *)directOverrideStateForName:(NSString *)name {
    id v = [self directOverrides][name ?: @""];
    return [v respondsToSelector:@selector(boolValue)] ? @([v boolValue]) : nil;
}

+ (NSString *)runtimeBoolKeyForClass:(NSString *)rawClassName selector:(NSString *)selectorName classMethod:(BOOL)isClassMethod {
    return [NSString stringWithFormat:@"%c%@#%@", isClassMethod ? '+' : '-', rawClassName ?: @"", selectorName ?: @""];
}

+ (BOOL)splitRuntimeBoolKey:(NSString *)name className:(NSString **)className selectorName:(NSString **)selectorName classMethod:(BOOL *)isClassMethod {
    if (name.length < 4) return NO;
    unichar prefix = [name characterAtIndex:0];
    if (prefix != '+' && prefix != '-') return NO;
    NSRange r = [name rangeOfString:@"#"];
    if (r.location == NSNotFound || r.location <= 1 || NSMaxRange(r) >= name.length) return NO;
    if (className) *className = [name substringWithRange:NSMakeRange(1, r.location - 1)];
    if (selectorName) *selectorName = [name substringFromIndex:NSMaxRange(r)];
    if (isClassMethod) *isClassMethod = (prefix == '+');
    return YES;
}

+ (BOOL)splitCanonicalName:(NSString *)name className:(NSString **)className selectorName:(NSString **)selectorName {
    NSRange r = [name rangeOfString:@"#"];
    if (r.location == NSNotFound || r.location == 0 || NSMaxRange(r) >= name.length) return NO;
    if (className) *className = [name substringToIndex:r.location];
    if (selectorName) *selectorName = [name substringFromIndex:NSMaxRange(r)];
    return YES;
}

+ (BOOL)installDirectHookForClass:(NSString *)rawClassName selector:(NSString *)selectorName {
    return [self installRuntimeBoolHookForClass:rawClassName
                                       selector:selectorName
                                    classMethod:NO
                                     legacyName:[self canonicalNameForClass:rawClassName selector:selectorName]];
}

+ (BOOL)methodLooksLikeNoArgumentBool:(Method)m {
    return SCIMethodLooksLikeNoArgumentBool(m);
}

+ (BOOL)installRuntimeBoolHookForClass:(NSString *)rawClassName selector:(NSString *)selectorName classMethod:(BOOL)isClassMethod legacyName:(nullable NSString *)legacyName {
    if (!rawClassName.length || !selectorName.length) return NO;
    NSString *name = [self runtimeBoolKeyForClass:rawClassName selector:selectorName classMethod:isClassMethod];

    @synchronized (self) {
        if ([sSCIGatingHookedNames containsObject:name]) return YES;
    }

    Class cls = objc_getClass(rawClassName.UTF8String);
    SEL sel = NSSelectorFromString(selectorName);
    if (!cls || !sel) return NO;
    Method meth = isClassMethod ? class_getClassMethod(cls, sel) : class_getInstanceMethod(cls, sel);
    if (!meth) return NO;
    if (![self methodLooksLikeNoArgumentBool:meth]) return NO;
    Class hookClass = isClassMethod ? object_getClass(cls) : cls;
    if (!hookClass) return NO;

    __block IMP originalIMP = NULL;
    IMP replacement = imp_implementationWithBlock(^BOOL(id receiver) {
        NSNumber *forced = [SCIGatingCatalog runtimeBoolOverrideStateForClass:rawClassName selector:selectorName classMethod:isClassMethod];
        if (!forced && legacyName.length) forced = [SCIGatingCatalog directOverrideStateForName:legacyName];
        if (forced) return forced.boolValue;
        IMP orig = NULL;
        @synchronized ([SCIGatingCatalog class]) {
            orig = [[sSCIGatingOriginalIMPs objectForKey:name] pointerValue];
        }
        return orig ? ((BOOL (*)(id, SEL))orig)(receiver, sel) : NO;
    });

    MSHookMessageEx(hookClass, sel, replacement, &originalIMP);
    @synchronized (self) {
        if (!sSCIGatingOriginalIMPs) sSCIGatingOriginalIMPs = [NSMutableDictionary dictionary];
        if (!sSCIGatingHookedNames) sSCIGatingHookedNames = [NSMutableSet set];
        if (originalIMP) sSCIGatingOriginalIMPs[name] = [NSValue valueWithPointer:originalIMP];
        [sSCIGatingHookedNames addObject:name];
    }
    return YES;
}

+ (void)installPersistedDirectOverrideHooks {
    NSDictionary *overrides = [self directOverrides];
    for (NSString *name in overrides) {
        NSString *cls = nil, *sel = nil;
        if ([self splitCanonicalName:name className:&cls selectorName:&sel]) {
            [self installDirectHookForClass:cls selector:sel];
        }
    }
    NSDictionary *runtimeOverrides = [self runtimeBoolOverrides];
    for (NSString *name in runtimeOverrides) {
        NSString *cls = nil, *sel = nil; BOOL classMethod = NO;
        if ([self splitRuntimeBoolKey:name className:&cls selectorName:&sel classMethod:&classMethod]) {
            NSString *legacy = classMethod ? nil : [self canonicalNameForClass:cls selector:sel];
            [self installRuntimeBoolHookForClass:cls selector:sel classMethod:classMethod legacyName:legacy];
        }
    }
}

+ (void)setDirectBoolOverride:(BOOL)value class:(NSString *)rawClassName selector:(NSString *)selectorName {
    if (!rawClassName.length || !selectorName.length) return;
    NSString *name = [self canonicalNameForClass:rawClassName selector:selectorName];
    [self installDirectHookForClass:rawClassName selector:selectorName];
    NSMutableDictionary *d = [[self directOverrides] mutableCopy];
    d[name] = @(value);
    [NSUserDefaults.standardUserDefaults setObject:d forKey:kDirectOverridesKey];
    [NSUserDefaults.standardUserDefaults synchronize];
}

+ (void)clearDirectOverrideForName:(NSString *)name {
    if (!name.length) return;
    NSMutableDictionary *d = [[self directOverrides] mutableCopy];
    [d removeObjectForKey:name];
    [NSUserDefaults.standardUserDefaults setObject:d forKey:kDirectOverridesKey];
    [NSUserDefaults.standardUserDefaults synchronize];
}

+ (void)clearDirectOverrides {
    [NSUserDefaults.standardUserDefaults removeObjectForKey:kDirectOverridesKey];
    [NSUserDefaults.standardUserDefaults removeObjectForKey:kRuntimeBoolOverridesKey];
    [NSUserDefaults.standardUserDefaults synchronize];
}

+ (BOOL)canRuntimeHookBoolMethodForClass:(NSString *)rawClassName selector:(NSString *)selectorName classMethod:(BOOL)isClassMethod {
    if (!rawClassName.length || !selectorName.length) return NO;
    Class cls = objc_getClass(rawClassName.UTF8String);
    SEL sel = NSSelectorFromString(selectorName);
    if (!cls || !sel) return NO;
    Method meth = isClassMethod ? class_getClassMethod(cls, sel) : class_getInstanceMethod(cls, sel);
    return [self methodLooksLikeNoArgumentBool:meth];
}

+ (nullable NSNumber *)runtimeBoolOverrideStateForClass:(NSString *)rawClassName selector:(NSString *)selectorName classMethod:(BOOL)isClassMethod {
    NSString *key = [self runtimeBoolKeyForClass:rawClassName selector:selectorName classMethod:isClassMethod];
    id v = [self runtimeBoolOverrides][key ?: @""];
    if ([v respondsToSelector:@selector(boolValue)]) return @([v boolValue]);
    if (!isClassMethod) return [self directOverrideStateForName:[self canonicalNameForClass:rawClassName selector:selectorName]];
    return nil;
}

+ (void)setRuntimeBoolOverride:(BOOL)value class:(NSString *)rawClassName selector:(NSString *)selectorName classMethod:(BOOL)isClassMethod {
    if (!rawClassName.length || !selectorName.length) return;
    NSString *legacy = isClassMethod ? nil : [self canonicalNameForClass:rawClassName selector:selectorName];
    if (![self installRuntimeBoolHookForClass:rawClassName selector:selectorName classMethod:isClassMethod legacyName:legacy]) return;
    NSMutableDictionary *d = [[self runtimeBoolOverrides] mutableCopy];
    d[[self runtimeBoolKeyForClass:rawClassName selector:selectorName classMethod:isClassMethod]] = @(value);
    [NSUserDefaults.standardUserDefaults setObject:d forKey:kRuntimeBoolOverridesKey];
    if (!isClassMethod) {
        NSMutableDictionary *legacyOverrides = [[self directOverrides] mutableCopy];
        legacyOverrides[legacy] = @(value);
        [NSUserDefaults.standardUserDefaults setObject:legacyOverrides forKey:kDirectOverridesKey];
    }
    [NSUserDefaults.standardUserDefaults synchronize];
}

+ (void)clearRuntimeBoolOverrideForClass:(NSString *)rawClassName selector:(NSString *)selectorName classMethod:(BOOL)isClassMethod {
    if (!rawClassName.length || !selectorName.length) return;
    NSMutableDictionary *d = [[self runtimeBoolOverrides] mutableCopy];
    [d removeObjectForKey:[self runtimeBoolKeyForClass:rawClassName selector:selectorName classMethod:isClassMethod]];
    [NSUserDefaults.standardUserDefaults setObject:d forKey:kRuntimeBoolOverridesKey];
    if (!isClassMethod) {
        NSMutableDictionary *legacyOverrides = [[self directOverrides] mutableCopy];
        [legacyOverrides removeObjectForKey:[self canonicalNameForClass:rawClassName selector:selectorName]];
        [NSUserDefaults.standardUserDefaults setObject:legacyOverrides forKey:kDirectOverridesKey];
    }
    [NSUserDefaults.standardUserDefaults synchronize];
}

+ (nullable NSNumber *)evaluateClass:(NSString *)rawClassName selector:(NSString *)selectorName {
    if (!rawClassName.length || !selectorName.length) return nil;
    if ([self isBlacklistedClass:rawClassName selector:selectorName]) return nil;

    Class cls = objc_getClass(rawClassName.UTF8String);
    if (!cls) return nil;
    SEL sel = NSSelectorFromString(selectorName);
    if (!sel) return nil;
    Method meth = class_getInstanceMethod(cls, sel);
    if (!meth) return nil;
    if (![self methodLooksLikeNoArgumentBool:meth]) return nil;
    IMP imp = method_getImplementation(meth);
    if (!imp) return nil;

    id receiver = [self bestReceiverForClass:cls];
    if (!receiver) return nil;

    // Arm the crash guard: if the call segfaults (uncatchable), the next launch will
    // see this key still pending and blacklist it.
    NSUserDefaults *d = NSUserDefaults.standardUserDefaults;
    NSString *key = [self keyForClass:rawClassName selector:selectorName];
    [d setObject:key forKey:kPendingKey];
    [d synchronize];

    NSNumber *result = nil;
    @try {
        BOOL v = ((BOOL (*)(id, SEL))imp)(receiver, sel);
        result = @(v);
    } @catch (__unused id e) {
        result = nil;
    }

    // Disarm — we survived.
    [d removeObjectForKey:kPendingKey];
    [d synchronize];

    return result;
}


+ (BOOL)hasLiveReceiverForClass:(NSString *)rawClassName {
    if (!rawClassName.length) return NO;
    Class cls = objc_getClass(rawClassName.UTF8String);
    if (!cls) return NO;
    return [self bestReceiverForClass:cls] != nil;
}

@end
