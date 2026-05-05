#import <Foundation/Foundation.h>
#import <objc/runtime.h>
#import <substrate.h>
#import <pthread.h>
#import "../SCIExpFlags.h"
#import "../SCIExpMobileConfigMapping.h"
#import "../SCIMobileConfigMapping.h"
#import "../../../Utils.h"

static NSString *const kHooksKey = @"sci_exp_mc_objc_getter_observer_enabled";
static NSString *const kStartupKey = @"sci_exp_mc_objc_startup_hooks_enabled";
static NSString *const kStoreKey = @"sci_exp_overrides_by_name";
static NSMutableDictionary<NSString *, NSValue *> *gOrig;
static NSMutableDictionary<NSNumber *, NSString *> *gNames;
static NSMutableDictionary<NSString *, NSNumber *> *gHits;
static NSDictionary<NSString *, NSNumber *> *gOverrides;
static pthread_mutex_t gLock = PTHREAD_MUTEX_INITIALIZER;
static BOOL gInstalled = NO;
static __thread BOOL gInside = NO;

static NSString *Key(Class c, SEL s) { return [NSString stringWithFormat:@"%@:%@", NSStringFromClass(c), NSStringFromSelector(s)]; }
static NSString *Hex(unsigned long long p) { return [NSString stringWithFormat:@"mc:0x%016llx", p]; }
static NSString *Ctx(id x) { Class c = [x class]; return c ? NSStringFromClass(c) : @"?"; }

static IMP Orig(id x, SEL s) {
    Class c = [x class];
    pthread_mutex_lock(&gLock);
    while (c) {
        NSValue *v = gOrig[Key(c, s)];
        if (v) { IMP imp = (IMP)(uintptr_t)[v pointerValue]; pthread_mutex_unlock(&gLock); return imp; }
        c = class_getSuperclass(c);
    }
    pthread_mutex_unlock(&gLock);
    return NULL;
}

static void RefreshOverrides(void) {
    NSDictionary *d = [[NSUserDefaults standardUserDefaults] dictionaryForKey:kStoreKey];
    pthread_mutex_lock(&gLock);
    gOverrides = d ? [d copy] : @{};
    pthread_mutex_unlock(&gLock);
}

static SCIExpFlagOverride OverrideForKey(NSString *k) {
    if (!k.length) return SCIExpFlagOverrideOff;
    pthread_mutex_lock(&gLock);
    NSNumber *n = gOverrides[k];
    pthread_mutex_unlock(&gLock);
    return n ? (SCIExpFlagOverride)n.integerValue : SCIExpFlagOverrideOff;
}

static NSString *NameForParam(unsigned long long p) {
    NSNumber *n = @(p);
    pthread_mutex_lock(&gLock);
    NSString *cached = gNames[n];
    pthread_mutex_unlock(&gLock);
    if (cached) return cached.length ? cached : nil;

    NSString *r = [SCIMobileConfigMapping resolvedNameForParamID:p];
    if (!r.length) r = [SCIExpMobileConfigMapping resolvedNameForSpecifier:p];
    if (!r.length) r = @"";

    pthread_mutex_lock(&gLock);
    if (!gNames) gNames = [NSMutableDictionary dictionary];
    gNames[n] = r;
    pthread_mutex_unlock(&gLock);
    return r.length ? r : nil;
}

static SCIExpFlagOverride OverrideForParam(unsigned long long p) {
    NSString *name = NameForParam(p);
    if (name.length) {
        SCIExpFlagOverride byName = OverrideForKey(name);
        if (byName != SCIExpFlagOverrideOff) return byName;
    }
    return OverrideForKey(Hex(p));
}

static NSString *NameFromObj(id x) {
    if (!x) return nil;
    NSString *s = [x isKindOfClass:NSString.class] ? (NSString *)x : [x description];
    return s.length ? s : nil;
}

static SCIExpFlagOverride OverrideForNameObj(id x) {
    NSString *s = NameFromObj(x);
    return s.length ? OverrideForKey(s) : SCIExpFlagOverrideOff;
}

static BOOL Apply(SCIExpFlagOverride o, BOOL v) {
    // ObjC getters are lifecycle-critical. By default this observer MUST NOT alter return values.
    // Enable sci_exp_mc_objc_apply_overrides_enabled only after we have identified a safe param/callsite.
    id enabled = [[NSUserDefaults standardUserDefaults] objectForKey:@"sci_exp_mc_objc_apply_overrides_enabled"];
    if (!enabled || ![enabled boolValue]) return v;
    if (o == SCIExpFlagOverrideTrue) return YES;
    if (o == SCIExpFlagOverrideFalse) return NO;
    return v;
}

static NSString *OText(SCIExpFlagOverride o) {
    if (o == SCIExpFlagOverrideTrue) return @"ForceON";
    if (o == SCIExpFlagOverrideFalse) return @"ForceOFF";
    return @"Off";
}

static BOOL ShouldRecord(unsigned long long p, SEL s) {
    NSString *k = [NSString stringWithFormat:@"%@:%016llx", NSStringFromSelector(s), p];
    pthread_mutex_lock(&gLock);
    if (!gHits) gHits = [NSMutableDictionary dictionary];
    NSUInteger c = gHits[k].unsignedIntegerValue + 1;
    gHits[k] = @(c);
    pthread_mutex_unlock(&gLock);
    return c <= 2 || (c % 2048) == 0;
}

static void Rec(id x, SEL s, unsigned long long p, NSString *name, BOOL def, BOOL orig, BOOL fin, SCIExpFlagOverride o) {
    if (!ShouldRecord(p, s)) return;
    NSString *resolved = name.length ? name : NameForParam(p);
    NSString *np = resolved.length ? [NSString stringWithFormat:@" · name=%@", resolved] : @"";
    NSString *d = [NSString stringWithFormat:@"source=ObjC MobileConfig getter · selector=%@ · context=%@%@ · default=%d · original=%d · final=%d · override=%@ · shadowTrue=1 · wouldChangeIfTrue=%d", NSStringFromSelector(s), Ctx(x), np, def ? 1 : 0, orig ? 1 : 0, fin ? 1 : 0, OText(o), orig ? 0 : 1];
    [SCIExpFlags recordMCParamID:p type:SCIExpMCTypeBool defaultValue:d originalValue:orig ? @"YES" : @"NO" contextClass:Ctx(x) selectorName:NSStringFromSelector(s)];
}

static BOOL H1(id x, SEL s, unsigned long long p) {
    BOOL (*orig)(id, SEL, unsigned long long) = (BOOL (*)(id, SEL, unsigned long long))Orig(x, s);
    if (gInside) return orig ? orig(x, s, p) : NO;
    gInside = YES;
    BOOL ov = orig ? orig(x, s, p) : NO;
    SCIExpFlagOverride o = OverrideForParam(p);
    BOOL fv = Apply(o, ov);
    Rec(x, s, p, nil, ov, ov, fv, o);
    gInside = NO;
    return fv;
}

static BOOL H2(id x, SEL s, unsigned long long p, BOOL def) {
    BOOL (*orig)(id, SEL, unsigned long long, BOOL) = (BOOL (*)(id, SEL, unsigned long long, BOOL))Orig(x, s);
    if (gInside) return orig ? orig(x, s, p, def) : def;
    gInside = YES;
    BOOL ov = orig ? orig(x, s, p, def) : def;
    SCIExpFlagOverride o = OverrideForParam(p);
    BOOL fv = Apply(o, ov);
    Rec(x, s, p, nil, def, ov, fv, o);
    gInside = NO;
    return fv;
}

static BOOL H3(id x, SEL s, unsigned long long p, void *opt) {
    BOOL (*orig)(id, SEL, unsigned long long, void *) = (BOOL (*)(id, SEL, unsigned long long, void *))Orig(x, s);
    if (gInside) return orig ? orig(x, s, p, opt) : NO;
    gInside = YES;
    BOOL ov = orig ? orig(x, s, p, opt) : NO;
    SCIExpFlagOverride o = OverrideForParam(p);
    BOOL fv = Apply(o, ov);
    Rec(x, s, p, nil, ov, ov, fv, o);
    gInside = NO;
    return fv;
}

static BOOL H4(id x, SEL s, unsigned long long p, void *opt, BOOL def) {
    BOOL (*orig)(id, SEL, unsigned long long, void *, BOOL) = (BOOL (*)(id, SEL, unsigned long long, void *, BOOL))Orig(x, s);
    if (gInside) return orig ? orig(x, s, p, opt, def) : def;
    gInside = YES;
    BOOL ov = orig ? orig(x, s, p, opt, def) : def;
    SCIExpFlagOverride o = OverrideForParam(p);
    BOOL fv = Apply(o, ov);
    Rec(x, s, p, nil, def, ov, fv, o);
    gInside = NO;
    return fv;
}

static BOOL HName(id x, SEL s, id name, BOOL def) {
    BOOL (*orig)(id, SEL, id, BOOL) = (BOOL (*)(id, SEL, id, BOOL))Orig(x, s);
    if (gInside) return orig ? orig(x, s, name, def) : def;
    gInside = YES;
    BOOL ov = orig ? orig(x, s, name, def) : def;
    NSString *n = NameFromObj(name);
    unsigned long long pseudo = n.length ? (unsigned long long)n.hash : 0ULL;
    SCIExpFlagOverride o = OverrideForNameObj(name);
    BOOL fv = Apply(o, ov);
    Rec(x, s, pseudo, n, def, ov, fv, o);
    gInside = NO;
    return fv;
}

static void InstallOne(Class c, NSString *selName, IMP repl) {
    if (!c || !selName.length || !repl) return;
    SEL s = NSSelectorFromString(selName);
    if (!class_getInstanceMethod(c, s)) return;
    pthread_mutex_lock(&gLock);
    BOOL exists = gOrig[Key(c, s)] != nil;
    pthread_mutex_unlock(&gLock);
    if (exists) return;
    IMP o = NULL;
    MSHookMessageEx(c, s, repl, &o);
    if (!o) return;
    pthread_mutex_lock(&gLock);
    if (!gOrig) gOrig = [NSMutableDictionary dictionary];
    gOrig[Key(c, s)] = [NSValue valueWithPointer:(const void *)(uintptr_t)o];
    pthread_mutex_unlock(&gLock);
}

static void InstallCommon(NSString *cn) {
    Class c = NSClassFromString(cn);
    InstallOne(c, @"getBool:", (IMP)H1);
    InstallOne(c, @"getBool:withDefault:", (IMP)H2);
    InstallOne(c, @"getBool:withOptions:", (IMP)H3);
    InstallOne(c, @"getBool:withOptions:withDefault:", (IMP)H4);
    InstallOne(c, @"getBoolWithoutLogging:", (IMP)H1);
    InstallOne(c, @"getBoolWithoutLogging:withDefault:", (IMP)H2);
}

static void InstallAll(void) {
    if (gInstalled) return;
    gInstalled = YES;
    RefreshOverrides();
    [[NSNotificationCenter defaultCenter] addObserverForName:NSUserDefaultsDidChangeNotification object:nil queue:nil usingBlock:^(__unused NSNotification *n) { RefreshOverrides(); }];
    for (NSString *cn in @[@"IGMobileConfigContextManager", @"IGMobileConfigSessionlessContextManager", @"IGMobileConfigUserSessionContextManager", @"FBMobileConfigContextManager", @"FBMobileConfigSessionlessContextManager", @"FBMobileConfigUserSessionContextManager", @"FBMobileConfigContextObjcImpl"]) InstallCommon(cn);
    if ([SCIUtils getBoolPref:kStartupKey]) {
        Class s = NSClassFromString(@"FBMobileConfigStartupConfigs");
        InstallOne(s, @"getBool:withDefault:", (IMP)H2);
        InstallOne(s, @"getBool:withOptions:withDefault:", (IMP)H4);
        InstallOne(s, @"getBool_XStackIncompatibleButUsedAcrossFBAndIG:withDefault:", (IMP)HName);
        Class d = NSClassFromString(@"FBMobileConfigStartupConfigsDeprecated");
        InstallOne(d, @"getBool_XStackIncompatibleButUsedAcrossFBAndIG:withDefault:", (IMP)HName);
    }
    NSLog(@"[RyukGram][MCOverride] delayed ObjC MobileConfig hooks installed");
}

%ctor {
    if (![SCIUtils getBoolPref:kHooksKey]) return;
    dispatch_async(dispatch_get_main_queue(), ^{
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(12.0 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
            if ([SCIUtils getBoolPref:kHooksKey]) InstallAll();
        });
    });
}
