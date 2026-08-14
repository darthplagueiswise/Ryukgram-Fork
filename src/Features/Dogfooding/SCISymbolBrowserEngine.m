#import "SCISymbolBrowserEngine.h"
#import "../../Utils.h"
#import <objc/runtime.h>
#import <objc/message.h>
#import <substrate.h>
#import <mach-o/dyld.h>

static NSString *const kOverridesKey = @"sci_symbol_overrides";
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
	const char *type = ret;
	while (*type == 'r' || *type == 'n' || *type == 'N' || *type == 'o' ||
		   *type == 'O' || *type == 'R' || *type == 'V') type++;
	// arm64 iOS encodes Objective-C BOOL as `B`. Treating generic char (`c/C`)
	// as BOOL produced non-boolean rows and unsafe replacement signatures.
	if (*type != 'B') return NO;
	return SCIArgumentKindForMethod(m) >= 0;
}

// Runtime browser policy: these are common NSObject/UIKit protocol or state
// methods, not experiment gates. Reject them during discovery so they never
// reappear through search or an "All" view. The list is semantic UI policy;
// persisted exact overrides remain installable for backwards compatibility.
static NSSet<NSString *> *SCIStructuralNoiseSelectorNames(void) {
	static NSSet<NSString *> *names = nil;
	static dispatch_once_t once;
	dispatch_once(&once, ^{
		names = [NSSet setWithArray:@[
			@"isEqual:", @"isEqualToDiffableObject:", @"isEqualToString:",
			@"respondsToSelector:", @"conformsToProtocol:",
			@"isKindOfClass:", @"isMemberOfClass:", @"isProxy",
			@"allowsWeakReference", @"retainWeakReference",
			@"supportsSecureCoding", @"automaticallyNotifiesObserversForKey:",
			@"makeImmutable", @"quick_flexibilityFor:",
			@"canRespondToGesture:", @"gestureRecognizerShouldBegin:",
			@"gestureRecognizer:shouldRecognizeSimultaneouslyWithGestureRecognizer:",
			@"gestureRecognizer:shouldReceiveTouch:",
			@"gestureRecognizer:shouldBeRequiredToFailByGestureRecognizer:",
			@"gestureRecognizer:shouldRequireFailureOfGestureRecognizer:",
			@"canPerformAction:withSender:",
			@"textFieldShouldReturn:", @"textFieldShouldBeginEditing:",
			@"textFieldShouldEndEditing:", @"textFieldShouldClear:",
			@"textField:shouldChangeCharactersInRange:replacementString:",
			@"textViewShouldBeginEditing:", @"textViewShouldEndEditing:",
			@"textView:shouldChangeTextInRange:replacementText:",
			@"searchBarShouldBeginEditing:", @"searchBarShouldEndEditing:",
			@"scrollViewShouldScrollToTop:",
			@"becomeFirstResponder", @"resignFirstResponder",
			@"canBecomeFirstResponder", @"canResignFirstResponder",
			@"isFirstResponder", @"isAccessibilityElement",
			@"accessibilityActivate", @"accessibilityPerformEscape",
			@"accessibilityPerformMagicTap", @"accessibilityScroll:",
			@"isHidden", @"isSelected", @"isEnabled", @"isHighlighted",
			@"enabled", @"disabled", @"selected", @"userInteractionEnabled",
			@"isOpaque", @"clipsToBounds", @"isUserInteractionEnabled",
			@"isFocused", @"canBecomeFocused", @"prefersStatusBarHidden",
			@"prefersNavigationBarHidden", @"prefersNavigationBarDividerHidden",
			@"prefersHomeIndicatorAutoHidden", @"shouldAutorotate",
			@"isLoading", @"isPlaying", @"isMuted", @"isActive", @"isPaused",
		]];
	});
	return names;
}

static BOOL SCISelectorIsStructuralNoise(NSString *selectorName) {
	if (!selectorName.length) return YES;
	if ([SCIStructuralNoiseSelectorNames() containsObject:selectorName]) return YES;
	NSString *lower = selectorName.lowercaseString;
	return [lower hasPrefix:@"isequal"] ||
		[lower hasPrefix:@"respondstoselector"] ||
		[lower hasPrefix:@"canrespond"];
}

static BOOL SCISelectorAllowed(const char *name, Method m) {
	if (!name || !m) return NO;
	if (strncmp(name, "set", 3) == 0 || strncmp(name, "init", 4) == 0) return NO;
	NSString *selectorName = [NSString stringWithUTF8String:name];
	if (SCISelectorIsStructuralNoise(selectorName)) return NO;
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
+ (NSArray<NSString *> *)runtimeImagePaths {
	NSString *executable = NSBundle.mainBundle.executablePath.stringByStandardizingPath;
	NSString *frameworkRoot = [[NSBundle.mainBundle.bundlePath
		stringByAppendingPathComponent:@"Frameworks"] stringByStandardizingPath];
	NSMutableOrderedSet<NSString *> *paths = [NSMutableOrderedSet orderedSet];
	uint32_t imageCount = _dyld_image_count();
	for (uint32_t index = 0; index < imageCount; index++) {
		const char *raw = _dyld_get_image_name(index);
		if (!raw) continue;
		NSString *path = [[NSString stringWithUTF8String:raw] stringByStandardizingPath];
		if (!path.length) continue;
		BOOL isMain = executable.length && [path isEqualToString:executable];
		BOOL isFramework = frameworkRoot.length &&
			([path isEqualToString:frameworkRoot] ||
			 [path hasPrefix:[frameworkRoot stringByAppendingString:@"/"]]);
		if (isMain || isFramework) [paths addObject:path];
	}
	NSArray<NSString *> *sorted = [paths.array sortedArrayUsingComparator:
		^NSComparisonResult(NSString *a, NSString *b) {
			BOOL am = executable.length && [a isEqualToString:executable];
			BOOL bm = executable.length && [b isEqualToString:executable];
			if (am != bm) return am ? NSOrderedAscending : NSOrderedDescending;
			return [[self shortNameForImagePath:a]
				compare:[self shortNameForImagePath:b]
				options:NSCaseInsensitiveSearch];
		}];
	return sorted ?: @[];
}

+ (NSString *)shortNameForImagePath:(NSString *)imagePath {
	NSString *name = imagePath.lastPathComponent;
	return name.length ? name : @"Image";
}

+ (BOOL)isStructuralNoiseSelectorName:(NSString *)selectorName {
	return SCISelectorIsStructuralNoise(selectorName);
}

+ (NSArray<SCISymbolClass *> *)classesForImagePath:(NSString *)imagePath {
	NSString *wanted = imagePath.stringByStandardizingPath;
	if (!wanted.length) return @[];
	unsigned int count = 0; Class *all = objc_copyClassList(&count);
	if (!all) return @[];
	NSMutableArray *out = [NSMutableArray array];
	for (unsigned int i = 0; i < count; i++) {
		Class cls = all[i]; const char *img = class_getImageName(cls); if (!img) continue;
		NSString *classImage = [[NSString stringWithUTF8String:img] stringByStandardizingPath];
		if (![classImage isEqualToString:wanted]) continue;
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
+ (NSArray<SCISymbolClass *> *)classesForImage:(SCISymbolImage)image {
	if (image < SCISymbolImageInstagram || image > SCISymbolImageFBShared) return @[];
	NSArray<NSString *> *paths = [self runtimeImagePaths];
	NSString *main = NSBundle.mainBundle.executablePath.stringByStandardizingPath;
	if (image == SCISymbolImageInstagram) {
		return main.length ? [self classesForImagePath:main] : @[];
	}
	for (NSString *preferred in @[@"FBSharedFramework", @"InstagramSharedFramework"]) {
		for (NSString *path in paths) {
			if ([[self shortNameForImagePath:path] isEqualToString:preferred]) {
				return [self classesForImagePath:path];
			}
		}
	}
	return @[];
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
	for (NSString *imagePath in [self runtimeImagePaths]) {
		for (SCISymbolClass *c in [self classesForImagePath:imagePath]) {
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
