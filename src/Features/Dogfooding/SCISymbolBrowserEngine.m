#import "SCISymbolBrowserEngine.h"
#import "../../Utils.h"
#import <objc/runtime.h>
#import <objc/message.h>
#import <substrate.h>

static NSString *const kOverridesKey = @"sci_symbol_overrides";
static const char *kImageSuffix[2] = { "/Instagram", "/FBSharedFramework" };
static NSDictionary<NSString *, NSNumber *> *sRuntimeOverrideCache;
static NSMutableSet<NSString *> *sInstalledOverrideKeys;
static NSMutableDictionary<NSString *, NSNumber *> *sObservedOriginalValues;

static NSString *SCIOverrideKey(NSString *cn, NSString *sn, BOOL cm) {
	return [NSString stringWithFormat:@"%@%@#%@", cm ? @"+" : @"", cn ?: @"", sn ?: @""];
}
static NSDictionary *SCIOverrideDict(void) {
	NSDictionary *d = [SCIUtils getDictPref:kOverridesKey];
	return [d isKindOfClass:NSDictionary.class] ? d : @{};
}
static void SCIRefreshCache(void) {
	NSMutableDictionary *out = [NSMutableDictionary dictionary];
	[SCIOverrideDict() enumerateKeysAndObjectsUsingBlock:^(id k, id v, __unused BOOL *stop) {
		if ([k isKindOfClass:NSString.class] && [v isKindOfClass:NSNumber.class]) out[k] = v;
	}];
	sRuntimeOverrideCache = out.copy;
}
static NSNumber *SCIOverride(NSString *key) {
	id v = SCIOverrideDict()[key];
	return [v isKindOfClass:NSNumber.class] ? v : nil;
}
static NSNumber *SCICachedOverride(NSString *key) {
	id v = sRuntimeOverrideCache[key];
	return [v isKindOfClass:NSNumber.class] ? v : nil;
}
static void SCIRememberOriginal(NSString *key, BOOL value) {
	@synchronized([SCISymbolBrowserEngine class]) {
		if (!sObservedOriginalValues) sObservedOriginalValues = [NSMutableDictionary dictionary];
		sObservedOriginalValues[key] = @(value);
	}
}
static NSNumber *SCIObservedOriginal(NSString *key) {
	@synchronized([SCISymbolBrowserEngine class]) { return sObservedOriginalValues[key]; }
}

static SCISymbolArgumentKind SCIArgumentKindForMethod(Method m) {
	if (!m) return -1;
	unsigned n = method_getNumberOfArguments(m);
	if (n == 2) return SCISymbolArgumentNone;
	if (n != 3) return -1;
	char t[32] = {0}; method_getArgumentType(m, 2, t, sizeof(t));
	const char *p = t; while (*p == 'r' || *p == 'n' || *p == 'N' || *p == 'o' || *p == 'O' || *p == 'R' || *p == 'V') p++;
	if (*p == '@' || *p == '#' || *p == ':') return SCISymbolArgumentObject;
	if (strchr("BcCsSiIlLqQ^*", *p)) return SCISymbolArgumentInteger;
	return -1;
}
static BOOL SCIIsSupportedBoolMethod(Method m) {
	if (!m) return NO;
	char ret[16] = {0}; method_getReturnType(m, ret, sizeof(ret));
	if (!(ret[0] == 'B' || ret[0] == 'c' || ret[0] == 'C')) return NO;
	return SCIArgumentKindForMethod(m) >= 0;
}
static BOOL SCISelectorAllowed(const char *name, Method m) {
	if (!name || !m) return NO;
	if (strncmp(name, "set", 3) == 0 || strncmp(name, "init", 4) == 0) return NO;
	if (!strcmp(name, "isEqual:") || !strcmp(name, "respondsToSelector:")) return NO;
	return SCIIsSupportedBoolMethod(m);
}
static BOOL SCIParseKey(NSString *key, NSString **cn, NSString **sn, BOOL *cm) {
	BOOL isClass = [key hasPrefix:@"+"];
	NSString *body = isClass ? [key substringFromIndex:1] : key;
	NSRange r = [body rangeOfString:@"#"];
	if (r.location == NSNotFound || r.location == 0 || NSMaxRange(r) >= body.length) return NO;
	if (cn) *cn = [body substringToIndex:r.location];
	if (sn) *sn = [body substringFromIndex:NSMaxRange(r)];
	if (cm) *cm = isClass;
	return YES;
}

static BOOL SCIInstallKey(NSString *key) {
	if (!key.length) return NO;
	@synchronized([SCISymbolBrowserEngine class]) {
		if (!sInstalledOverrideKeys) sInstalledOverrideKeys = [NSMutableSet set];
		if ([sInstalledOverrideKeys containsObject:key]) return YES;
	}
	NSString *cn = nil, *sn = nil; BOOL cm = NO;
	if (!SCIParseKey(key, &cn, &sn, &cm)) return NO;
	Class cls = NSClassFromString(cn); SEL sel = NSSelectorFromString(sn);
	if (!cls || !sel) return NO;
	Class hookClass = cm ? object_getClass(cls) : cls;
	Method method = cm ? class_getClassMethod(cls, sel) : class_getInstanceMethod(cls, sel);
	if (!SCIIsSupportedBoolMethod(method)) return NO;
	SCISymbolArgumentKind kind = SCIArgumentKindForMethod(method);
	NSString *capturedKey = key.copy; SEL capturedSel = sel;
	__block IMP original = NULL;
	IMP replacement = NULL;
	if (kind == SCISymbolArgumentNone) {
		replacement = imp_implementationWithBlock(^BOOL(id receiver) {
			BOOL native = original ? ((BOOL (*)(id, SEL))original)(receiver, capturedSel) : NO;
			SCIRememberOriginal(capturedKey, native);
			NSNumber *forced = SCICachedOverride(capturedKey);
			return forced ? forced.boolValue : native;
		});
	} else if (kind == SCISymbolArgumentObject) {
		replacement = imp_implementationWithBlock(^BOOL(id receiver, id arg) {
			BOOL native = original ? ((BOOL (*)(id, SEL, id))original)(receiver, capturedSel, arg) : NO;
			SCIRememberOriginal(capturedKey, native);
			NSNumber *forced = SCICachedOverride(capturedKey);
			return forced ? forced.boolValue : native;
		});
	} else {
		replacement = imp_implementationWithBlock(^BOOL(id receiver, uint64_t arg) {
			BOOL native = original ? ((BOOL (*)(id, SEL, uint64_t))original)(receiver, capturedSel, arg) : NO;
			SCIRememberOriginal(capturedKey, native);
			NSNumber *forced = SCICachedOverride(capturedKey);
			return forced ? forced.boolValue : native;
		});
	}
	MSHookMessageEx(hookClass, sel, replacement, &original);
	@synchronized([SCISymbolBrowserEngine class]) { [sInstalledOverrideKeys addObject:key]; }
	return YES;
}

@implementation SCISymbolGetter
- (NSString *)overrideKey { return SCIOverrideKey(self.ownerClassName, self.selectorName, self.isClassMethod); }
- (BOOL)isParameterized { return self.argumentKind != SCISymbolArgumentNone; }
- (NSNumber *)override { return SCIOverride(self.overrideKey); }
- (NSNumber *)liveValue { return [SCISymbolBrowserEngine liveValueForClass:self.ownerClassName selector:self.selectorName isClassMethod:self.isClassMethod]; }
@end
@implementation SCISymbolClass @end

@implementation SCISymbolBrowserEngine
+ (NSArray<SCISymbolClass *> *)classesForImage:(SCISymbolImage)image {
	if (image < SCISymbolImageInstagram || image > SCISymbolImageFBShared) return @[];
	const char *suffix = kImageSuffix[image]; size_t sl = strlen(suffix);
	unsigned int count = 0; Class *all = objc_copyClassList(&count);
	if (!all) return @[];
	NSMutableArray *out = [NSMutableArray array];
	for (unsigned int i = 0; i < count; i++) {
		Class cls = all[i]; const char *img = class_getImageName(cls); if (!img) continue;
		size_t il = strlen(img); if (il < sl || strcmp(img + il - sl, suffix)) continue;
		NSString *cn = NSStringFromClass(cls); if (!cn.length) continue;
		NSMutableArray *methodsOut = [NSMutableArray array];
		for (int pass = 0; pass < 2; pass++) {
			BOOL cm = pass == 1; Class owner = cm ? object_getClass(cls) : cls; if (!owner) continue;
			unsigned int mc = 0; Method *methods = class_copyMethodList(owner, &mc);
			for (unsigned int j = 0; j < mc; j++) {
				Method m = methods[j]; SEL sel = method_getName(m); const char *name = sel_getName(sel);
				if (!SCISelectorAllowed(name, m)) continue;
				SCISymbolGetter *g = [SCISymbolGetter new];
				g.ownerClassName = cn; g.selectorName = NSStringFromSelector(sel); g.isClassMethod = cm;
				g.argumentKind = SCIArgumentKindForMethod(m);
				g.typeEncoding = [NSString stringWithUTF8String:method_getTypeEncoding(m) ?: ""];
				[methodsOut addObject:g];
			}
			if (methods) free(methods);
		}
		if (methodsOut.count) {
			[methodsOut sortUsingComparator:^NSComparisonResult(SCISymbolGetter *a, SCISymbolGetter *b) { return [a.selectorName compare:b.selectorName]; }];
			SCISymbolClass *entry = [SCISymbolClass new]; entry.className = cn; entry.getters = methodsOut.copy; [out addObject:entry];
		}
	}
	free(all);
	[out sortUsingComparator:^NSComparisonResult(SCISymbolClass *a, SCISymbolClass *b) { return [a.className compare:b.className]; }];
	return out.copy;
}
+ (NSNumber *)liveValueForClass:(NSString *)cn selector:(NSString *)sn isClassMethod:(BOOL)cm {
	Class cls = NSClassFromString(cn); SEL sel = NSSelectorFromString(sn); if (!cls || !sel) return nil;
	Method m = cm ? class_getClassMethod(cls, sel) : class_getInstanceMethod(cls, sel);
	if (!m || SCIArgumentKindForMethod(m) != SCISymbolArgumentNone) return SCIObservedOriginal(SCIOverrideKey(cn, sn, cm));
	id target = cm ? (id)cls : nil;
	if (!cm) {
		for (NSString *candidate in @[@"sharedConfig", @"sharedInstance", @"shared", @"sharedManager", @"defaultConfig", @"defaultInstance", @"experimentManager"]) {
			SEL s = NSSelectorFromString(candidate);
			if ([cls respondsToSelector:s]) { id (*f)(id,SEL)=(id(*)(id,SEL))objc_msgSend; @try { target=f(cls,s); } @catch (__unused id e) {} if(target) break; }
		}
	}
	if (!target || ![target respondsToSelector:sel]) return SCIObservedOriginal(SCIOverrideKey(cn, sn, cm));
	@try { BOOL (*f)(id,SEL)=(BOOL(*)(id,SEL))objc_msgSend; return @(f(target,sel)); } @catch (__unused id e) { return nil; }
}
+ (NSNumber *)overrideForKey:(NSString *)key { return SCIOverride(key); }
+ (BOOL)hookInstalledForKey:(NSString *)key { @synchronized(self) { return [sInstalledOverrideKeys containsObject:key]; } }
+ (BOOL)installOverrideForKey:(NSString *)key { return SCIInstallKey(key); }
+ (void)setOverride:(NSNumber *)value forClass:(NSString *)cn selector:(NSString *)sn isClassMethod:(BOOL)cm {
	NSString *key = SCIOverrideKey(cn, sn, cm); NSMutableDictionary *d = [SCIOverrideDict() mutableCopy];
	if (value) d[key] = value; else [d removeObjectForKey:key];
	[SCIUtils setPref:d.copy forKey:kOverridesKey]; SCIRefreshCache(); if (value) SCIInstallKey(key);
}
+ (void)reinstallPersistedHooks {
	SCIRefreshCache(); for (NSString *key in sRuntimeOverrideCache) SCIInstallKey(key);
}

+ (BOOL)className:(NSString *)cn matchesAny:(NSArray<NSString *> *)needles {
	NSString *l = cn.lowercaseString; for (NSString *n in needles) if ([l containsString:n.lowercaseString]) return YES; return NO;
}
+ (BOOL)selectorName:(NSString *)sn matchesAny:(NSArray<NSString *> *)needles {
	NSString *l = sn.lowercaseString; for (NSString *n in needles) if ([l containsString:n.lowercaseString]) return YES; return NO;
}
+ (NSUInteger)setForClassNeedles:(NSArray<NSString *> *)classNeedles selectorNeedles:(NSArray<NSString *> *)selectorNeedles value:(NSNumber *)value requireBoth:(BOOL)both {
	NSUInteger n = 0;
	for (SCISymbolImage img = SCISymbolImageInstagram; img <= SCISymbolImageFBShared; img++) {
		for (SCISymbolClass *c in [self classesForImage:img]) {
			BOOL cm = [self className:c.className matchesAny:classNeedles];
			for (SCISymbolGetter *g in c.getters) {
				BOOL sm = [self selectorName:g.selectorName matchesAny:selectorNeedles];
				if (both ? !(cm && sm) : !(cm || sm)) continue;
				[self setOverride:value forClass:c.className selector:g.selectorName isClassMethod:g.isClassMethod]; n++;
			}
		}
	}
	return n;
}
+ (NSUInteger)setExperimentManagersForced:(NSNumber *)value {
	return [self setForClassNeedles:@[@"FBCCIGExperimentManager", @"FBCustomExperimentManager"] selectorNeedles:@[@"isFeatureEnabled:", @"isFeatureEnabledWithoutLogging:"] value:value requireBoth:YES];
}
+ (NSUInteger)setExperimentConfigsForced:(NSNumber *)value {
	return [self setForClassNeedles:@[@"ExperimentConfig", @"ExperimentConfiguration", @"QuickExperimentConfig"] selectorNeedles:@[@"isEnabled", @"isBacktestEnabled", @"shouldLogImmediately", @"shouldEnable", @"isFeatureEnabled"] value:value requireBoth:YES];
}
+ (NSUInteger)setExperimentHelpersForced:(NSNumber *)value {
	return [self setForClassNeedles:@[@"IGMagicMod", @"IGStoriesTab", @"IGDirectNotes", @"IGLiquidGlass", @"ExperimentHelper", @"GatingHelper", @"FeatureHelper"] selectorNeedles:@[@"enabled", @"enable", @"feature", @"experiment", @"backtest", @"dogfood", @"internal"] value:value requireBoth:YES];
}
+ (NSUInteger)sweepForceForClassNeedles:(NSArray<NSString *> *)classNeedles selectorNeedles:(NSArray<NSString *> *)selectorNeedles forcedValue:(BOOL)forcedValue {
	return [self setForClassNeedles:classNeedles selectorNeedles:selectorNeedles value:@(forcedValue) requireBoth:NO];
}
@end

// Reinstall only exact saved method keys. This does not enumerate the runtime.
__attribute__((constructor)) static void SCISymbolBrowserExactOverrideBootstrap(void) {
	@autoreleasepool { [SCISymbolBrowserEngine reinstallPersistedHooks]; }
}
