from pathlib import Path
import re

ROOT = Path(__file__).resolve().parents[1]

def replace(path, old, new, count=1):
    p = ROOT / path
    s = p.read_text()
    if old not in s:
        raise RuntimeError(f"missing pattern in {path}: {old[:120]!r}")
    p.write_text(s.replace(old, new, count))

def regex(path, pattern, replacement, count=1):
    p = ROOT / path
    s = p.read_text()
    out, n = re.subn(pattern, replacement, s, count=count, flags=re.S)
    if n != count:
        raise RuntimeError(f"regex count {n} != {count} in {path}: {pattern[:120]}")
    p.write_text(out)

# EasyGating: Instagram(7) calls the wrapper; x3 is pointer-sized at real call-sites.
p = "src/Debug/RYGEasyGatingRuntime.m"
replace(p,
'''typedef uint32_t (*RYGEasyGatingBoolFn)(uintptr_t context,
                                        uint32_t selectorOrGateID,
                                        uint32_t defaultValue,
                                        uint32_t exposureValue);

static RYGEasyGatingBoolFn gRYGOriginalEasyGatingWrapper;
static RYGEasyGatingBoolFn gRYGOriginalEasyGatingPlatformGetBoolean;''',
'''typedef uint32_t (*RYGEasyGatingWrapperFn)(uintptr_t context,
                                           uint32_t selectorIndex,
                                           uint32_t defaultValue,
                                           uintptr_t exposureSource);

static RYGEasyGatingWrapperFn gRYGOriginalEasyGatingWrapper;''')
replace(p, "static uintptr_t RYGStripFunctionPointer(RYGEasyGatingBoolFn function) {", "static uintptr_t RYGStripFunctionPointer(RYGEasyGatingWrapperFn function) {")
replace(p, "static BOOL RYGResolveFinalGateID(RYGEasyGatingBoolFn wrapper,", "static BOOL RYGResolveFinalGateID(RYGEasyGatingWrapperFn wrapper,")
regex(p,
r'''static uint32_t RYGEasyGatingWrapperReplacement\(uintptr_t context,\n\s+uint32_t selectorIndex,\n\s+uint32_t defaultValue,\n\s+uint32_t exposureValue\) \{.*?\n\}\n\nstatic uint32_t RYGEasyGatingPlatformReplacement.*?\n\}\n''',
'''static uint32_t RYGEasyGatingWrapperReplacement(uintptr_t context,
                                                 uint32_t selectorIndex,
                                                 uint32_t defaultValue,
                                                 uintptr_t exposureSource) {
    RYGEasyGatingWrapperFn original = gRYGOriginalEasyGatingWrapper;
    uint32_t native = original ? original(context, selectorIndex, defaultValue, exposureSource)
                               : (defaultValue ? 1u : 0u);
    uint32_t finalID = 0;
    if (!RYGResolveFinalGateID(original, selectorIndex, &finalID)) return native;
    RYGEasyGatingRecord(finalID, defaultValue != 0, exposureSource != 0, native != 0);
    NSNumber *forced = RYGEasyGatingCachedOverride(finalID);
    return forced ? (forced.boolValue ? 1u : 0u) : native;
}
''')
regex(p,
r'''    struct rebinding bindings\[\] = \{.*?\n    \};\n    if \(rebind_symbols\(bindings, sizeof\(bindings\) / sizeof\(bindings\[0\]\)\) != 0\) \{''',
'''    // Instagram(7) imports the wrapper; FBShared tail-branches internally to
    // EasyGatingPlatformGetBoolean. Rebinding the platform import cannot catch
    // that internal branch and only adds an unnecessary ABI surface.
    struct rebinding bindings[] = {
        {
            .name = "EasyGatingGetBoolean_Internal_DoNotUseOrMock",
            .replacement = (void *)&RYGEasyGatingWrapperReplacement,
            .replaced = (void **)&gRYGOriginalEasyGatingWrapper,
        },
    };
    if (rebind_symbols(bindings, sizeof(bindings) / sizeof(bindings[0])) != 0) {''')

# Runtime index: exact image path from dyld, exact BOOL return, only @ and q/Q adapters.
p = "src/Debug/RYGRuntimeIndex.m"
replace(p, "return type && (*type == 'B' || *type == 'c' || *type == 'C');", "return type && *type == 'B';")
replace(p, 'if (strchr("cCsSiIlLqQ", *type) != NULL) return RYGRuntimeArgumentInteger;', "if (*type == 'q' || *type == 'Q') return RYGRuntimeArgumentInteger;")
replace(p,
'''static const struct mach_header *RYGIndexHeaderForPath(NSString *path) {''',
'''static NSString *RYGIndexRuntimeNameForPath(NSString *path) {
    NSString *wanted = RYGIndexCanonicalPath(path);
    if (!wanted.length) return nil;
    for (uint32_t index = 0; index < _dyld_image_count(); index++) {
        const char *raw = _dyld_get_image_name(index);
        if (!raw) continue;
        NSString *runtimeName = [NSString stringWithUTF8String:raw];
        if ([RYGIndexCanonicalPath(runtimeName) isEqualToString:wanted]) return runtimeName;
    }
    return nil;
}

static const struct mach_header *RYGIndexHeaderForPath(NSString *path) {''')
replace(p,
'''    // Enumerate only classes defined by the selected Mach-O image. This keeps
    // index cost proportional to the selected image instead of the whole app.
    unsigned int imageClassCount = 0;
    const char **imageClassNames = objc_copyClassNamesForImage(canonical.fileSystemRepresentation, &imageClassCount);''',
'''    NSString *runtimeName = RYGIndexRuntimeNameForPath(canonical);
    if (!runtimeName.length) return result;
    unsigned int imageClassCount = 0;
    const char **imageClassNames = objc_copyClassNamesForImage(runtimeName.fileSystemRepresentation, &imageClassCount);''')

# Runtime engine: exact BOOL ABI, declared methods only, exact persistence identity.
p = "src/Debug/RYGRuntimeBrowserEngine.m"
replace(p, "static NSMutableSet<NSString *> *gRYGInstalledKeys;", "static NSMutableSet<NSString *> *gRYGInstalledKeys;\nstatic NSString *const kRYGRuntimePersistedOverridesKey = @\"ryg_runtime_bool_overrides_v4\";")
replace(p, "return type && (*type == 'B' || *type == 'c' || *type == 'C');", "return type && *type == 'B';")
marker = "static BOOL RYGInstallUnifiedBoolHook(NSString *key) {"
insert = r'''static Method RYGDeclaredMethod(Class owner, SEL selector) {
    if (!owner || !selector) return NULL;
    unsigned int count = 0;
    Method *methods = class_copyMethodList(owner, &count);
    Method found = NULL;
    for (unsigned int index = 0; methods && index < count; index++) {
        if (method_getName(methods[index]) == selector) { found = methods[index]; break; }
    }
    if (methods) free(methods);
    return found;
}

static NSMutableDictionary *RYGReadPersistedOverrideSpecs(void) {
    id raw = [NSUserDefaults.standardUserDefaults dictionaryForKey:kRYGRuntimePersistedOverridesKey];
    return [raw isKindOfClass:NSDictionary.class] ? [(NSDictionary *)raw mutableCopy] : [NSMutableDictionary dictionary];
}

static void RYGPersistOverrideSpec(RYGRuntimeBoolMethod *method, NSNumber *value) {
    if (!method.overrideKey.length) return;
    NSMutableDictionary *specs = RYGReadPersistedOverrideSpecs();
    if (!value) [specs removeObjectForKey:method.overrideKey];
    else specs[method.overrideKey] = @{
        @"value": @([value boolValue]),
        @"encoding": method.typeEncoding ?: @"",
        @"image": RYGCanonicalImagePath(method.imagePath ?: @"")
    };
    [NSUserDefaults.standardUserDefaults setObject:specs.copy forKey:kRYGRuntimePersistedOverridesKey];
}

''' + marker
replace(p, marker, insert)
replace(p, "Method method = owner && selector ? class_getInstanceMethod(owner, selector) : NULL;", "Method method = owner && selector ? RYGDeclaredMethod(owner, selector) : NULL;", 1)
replace(p, "Method current = class_getInstanceMethod(owner, selector);", "Method current = RYGDeclaredMethod(owner, selector);", 1)
replace(p,
'''+ (void)setOverride:(NSNumber *)value forMethod:(RYGRuntimeBoolMethod *)method {
    if (![method isKindOfClass:RYGRuntimeBoolMethod.class] || !method.overrideKey.length) return;
    if (value && !RYGInstallUnifiedBoolHook(method.overrideKey)) return;
    @synchronized(self) {
        if (!gRYGOverrides) gRYGOverrides = [NSMutableDictionary dictionary];
        if (value) gRYGOverrides[method.overrideKey] = @(value.boolValue);
        else [gRYGOverrides removeObjectForKey:method.overrideKey];
    }
}

+ (void)reinstallPersistedOverrides { }''',
'''+ (void)setOverride:(NSNumber *)value forMethod:(RYGRuntimeBoolMethod *)method {
    if (![method isKindOfClass:RYGRuntimeBoolMethod.class] || !method.overrideKey.length) return;
    if (value && !RYGInstallUnifiedBoolHook(method.overrideKey)) return;
    @synchronized(self) {
        if (!gRYGOverrides) gRYGOverrides = [NSMutableDictionary dictionary];
        if (value) gRYGOverrides[method.overrideKey] = @(value.boolValue);
        else [gRYGOverrides removeObjectForKey:method.overrideKey];
    }
    RYGPersistOverrideSpec(method, value);
}

+ (void)reinstallPersistedOverrides {
    NSDictionary *specs = [NSUserDefaults.standardUserDefaults dictionaryForKey:kRYGRuntimePersistedOverridesKey];
    if (![specs isKindOfClass:NSDictionary.class] || !specs.count) return;
    [specs enumerateKeysAndObjectsUsingBlock:^(NSString *key, NSDictionary *spec, BOOL *stop) {
        (void)stop;
        if (![key isKindOfClass:NSString.class] || ![spec isKindOfClass:NSDictionary.class]) return;
        NSNumber *value = [spec[@"value"] isKindOfClass:NSNumber.class] ? spec[@"value"] : nil;
        NSString *expectedEncoding = [spec[@"encoding"] isKindOfClass:NSString.class] ? spec[@"encoding"] : @"";
        NSString *expectedImage = [spec[@"image"] isKindOfClass:NSString.class] ? spec[@"image"] : @"";
        if (!value || !expectedEncoding.length || !expectedImage.length) return;
        NSString *className = nil, *selectorName = nil; BOOL classMethod = NO;
        if (!RYGParseMethodKey(key, &className, &selectorName, &classMethod)) return;
        Class cls = objc_lookUpClass(className.UTF8String);
        Class owner = cls ? (classMethod ? object_getClass(cls) : cls) : Nil;
        SEL selector = selectorName.length ? NSSelectorFromString(selectorName) : NULL;
        Method method = RYGDeclaredMethod(owner, selector);
        const char *types = method ? method_getTypeEncoding(method) : NULL;
        NSString *encoding = types ? [NSString stringWithUTF8String:types] : @"";
        if (!method || !RYGMethodHasSupportedBoolABI(method) || ![encoding isEqualToString:expectedEncoding]) return;
        IMP imp = method_getImplementation(method);
        Dl_info info = {0};
        NSString *actualImage = (imp && dladdr((const void *)imp, &info) && info.dli_fname)
            ? RYGCanonicalImagePath([NSString stringWithUTF8String:info.dli_fname]) : @"";
        if (![actualImage isEqualToString:expectedImage]) return;
        if (!RYGInstallUnifiedBoolHook(key)) return;
        @synchronized(self) {
            if (!gRYGOverrides) gRYGOverrides = [NSMutableDictionary dictionary];
            gRYGOverrides[key] = @([value boolValue]);
        }
    }];
}''')
replace(p,
'''@implementation RYGRuntimeBoolMethod''',
'''static void RYGRuntimePersistedImageDidLoad(const struct mach_header *header, intptr_t slide) {
    (void)header; (void)slide;
    dispatch_async(dispatch_get_main_queue(), ^{ [RYGRuntimeBrowserEngine reinstallPersistedOverrides]; });
}

__attribute__((constructor(230))) static void RYGRuntimePersistedBootstrap(void) {
    @autoreleasepool {
        NSDictionary *specs = [NSUserDefaults.standardUserDefaults dictionaryForKey:kRYGRuntimePersistedOverridesKey];
        if (![specs isKindOfClass:NSDictionary.class] || !specs.count) return;
        _dyld_register_func_for_add_image(RYGRuntimePersistedImageDidLoad);
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.8 * NSEC_PER_SEC)),
                       dispatch_get_main_queue(), ^{ [RYGRuntimeBrowserEngine reinstallPersistedOverrides]; });
    }
}

@implementation RYGRuntimeBoolMethod''')

# Fast Runtime Browser: make the transition render before image/menu/index work starts.
p = "src/Debug/RYGFastRuntimeBrowserViewController.m"
replace(p,
'''    [self refreshImages];
    [self rebuildImageMenu];
    RYGLiquidGlassApplyToViewController(self);
    [self loadSelectedImage];''',
'''    RYGLiquidGlassApplyToViewController(self);
    __weak typeof(self) weakSelf = self;
    dispatch_async(dispatch_get_main_queue(), ^{
        __strong typeof(weakSelf) self = weakSelf;
        if (!self || !self.view.window) return;
        [self refreshImages];
        [self rebuildImageMenu];
        [self loadSelectedImage];
    });''')

# Developer surfaces: exact encodings only, Objective-C runtime swapping, persistence, functional Stories callback.
p = "src/Debug/RYGDeveloperTopicViewController.m"
replace(p, 'static NSString *const kRYGDogfoodOwnedMCStatePref = @"ryg_dev_dogfood_owned_mc_state_v2";', 'static NSString *const kRYGDogfoodOwnedMCStatePref = @"ryg_dev_dogfood_owned_mc_state_v2";\nstatic NSString *const kRYGPrismSetterModePref = @"ryg_dev_prism_setter_mode_v2";\nstatic NSString *const kRYGRedesignSetterModePref = @"ryg_dev_redesign_setter_mode_v2";')
replace(p, 'return type && strchr("BcC", *type) != NULL;', "return type && *type == 'B';")
replace(p, "return type && (*type == '@' || *type == '#' || *type == ':');", "return type && *type == '@';")
replace(p, 'return type && strchr("cCsSiIlLqQ", *type) != NULL;', "return type && (*type == 'q' || *type == 'Q');")
replace(p, 'if (RYGBugMenuFullSignatureMatches(method)) MSHookMessageEx(cls, selector, (IMP)RYGBugMenuInit, &gRYGBugMenuOriginal);', 'if (RYGBugMenuFullSignatureMatches(method)) gRYGBugMenuOriginal = method_setImplementation(method, (IMP)RYGBugMenuInit);')
replace(p, 'if (RYGBugMenuLegacySignatureMatches(method)) MSHookMessageEx(cls, selector, (IMP)RYGBugMenuLegacyInit, &gRYGBugMenuLegacyOriginal);', 'if (RYGBugMenuLegacySignatureMatches(method)) gRYGBugMenuLegacyOriginal = method_setImplementation(method, (IMP)RYGBugMenuLegacyInit);')
replace(p, 'MSHookMessageEx(controller, selector, (IMP)RYGDogfoodSettingsInit, &gRYGDogfoodSettingsInitOriginal);', 'gRYGDogfoodSettingsInitOriginal = method_setImplementation(method, (IMP)RYGDogfoodSettingsInit);')
replace(p, 'MSHookMessageEx(meta, selector, (IMP)RYGDogfoodSettingsOpen, &gRYGDogfoodSettingsOpenOriginal);', 'gRYGDogfoodSettingsOpenOriginal = method_setImplementation(method, (IMP)RYGDogfoodSettingsOpen);')
replace(p, 'MSHookMessageEx(cls, selector, (IMP)RYGDogfoodLauncherOverride, &gRYGDogfoodLauncherOriginal);', 'gRYGDogfoodLauncherOriginal = method_setImplementation(method, (IMP)RYGDogfoodLauncherOverride);')
replace(p, 'MSHookMessageEx(cls, selector, replacement, original);\n    return *original != NULL;', '*original = method_setImplementation(method, replacement);\n    return *original != NULL;')
regex(p,
r'''static BOOL RYGOpenStoryTrayDebug\(void\) \{.*?\n\}\n\nstatic id RYGSharedHelper''',
'''static BOOL RYGOpenStoryTrayDebug(void) {
    RYGRuntimeBoolMethod *gate = RYGStoryTrayGateMethod();
    if (!gate) return NO;
    NSNumber *forced = gate.overrideValue;
    NSNumber *observed = gate.liveValue;
    BOOL current = forced ? forced.boolValue : (observed ? observed.boolValue : NO);
    Class cls = objc_lookUpClass("_TtC25IGOverlayStoriesTrayDebug39IGOverlayStoriesTrayDebugViewController");
    SEL selector = NSSelectorFromString(@"presentFrom:currentlyEnabled:onApplyAndRestart:");
    Method method = cls ? class_getClassMethod(cls, selector) : NULL;
    if (!method || method_getNumberOfArguments(method) != 5 || !RYGMethodReturns(method, 'v') ||
        !RYGMethodArgumentMatches(method, 2, '@') || !RYGMethodArgumentMatches(method, 3, 'B')) return NO;
    char callbackType[96] = {0};
    method_getArgumentType(method, 4, callbackType, sizeof(callbackType));
    const char *unqualified = RYGUnqualifiedType(callbackType);
    if (!unqualified || strncmp(unqualified, "@?", 2) != 0) return NO;
    UIViewController *top = RYGTopViewController();
    if (!top) return NO;
    void (^completion)(BOOL) = ^(BOOL enabled) {
        [RYGRuntimeBrowserEngine setOverride:@(enabled) forMethod:gate];
    };
    ((void (*)(id, SEL, id, BOOL, id))objc_msgSend)((id)cls, selector, top, current, completion);
    return YES;
}

static id RYGSharedHelper''')
# Stop rebuilding the full MobileConfig model on every Developer page activation.
replace(p, '    [mobileConfig reloadFromRuntime];\n', '', 3)
replace(p,
'''+ (void)activatePersistedNativeFeatures {
    NSUserDefaults *defaults = NSUserDefaults.standardUserDefaults;
    BOOL dogfoodMode = [defaults boolForKey:kRYGDogfoodModePref];''',
'''+ (void)activatePersistedNativeFeatures {
    NSUserDefaults *defaults = NSUserDefaults.standardUserDefaults;
    NSNumber *prismMode = [defaults objectForKey:kRYGPrismSetterModePref];
    NSNumber *redesignMode = [defaults objectForKey:kRYGRedesignSetterModePref];
    gRYGPrismSetterMode = [prismMode isKindOfClass:NSNumber.class] ? prismMode.integerValue : -1;
    gRYGRedesignSetterMode = [redesignMode isKindOfClass:NSNumber.class] ? redesignMode.integerValue : -1;
    if (gRYGPrismSetterMode >= 0) (void)RYGInstallBoolSetterHook(@"IGBloksFollowButtonView", @"setPrismEnabled:", (IMP)RYGPrismSetter, &gRYGPrismSetterOriginal);
    if (gRYGRedesignSetterMode >= 0) (void)RYGInstallBoolSetterHook(@"IGTableViewCell", @"setListRedesignOn:", (IMP)RYGRedesignSetter, &gRYGRedesignSetterOriginal);
    [RYGRuntimeBrowserEngine reinstallPersistedOverrides];
    BOOL dogfoodMode = [defaults boolForKey:kRYGDogfoodModePref];''')
replace(p, '                gRYGPrismSetterMode = value;', '                gRYGPrismSetterMode = value;\n                if (value < 0) [NSUserDefaults.standardUserDefaults removeObjectForKey:kRYGPrismSetterModePref];\n                else [NSUserDefaults.standardUserDefaults setInteger:value forKey:kRYGPrismSetterModePref];')
replace(p, '                gRYGRedesignSetterMode = value;', '                gRYGRedesignSetterMode = value;\n                if (value < 0) [NSUserDefaults.standardUserDefaults removeObjectForKey:kRYGRedesignSetterModePref];\n                else [NSUserDefaults.standardUserDefaults setInteger:value forKey:kRYGRedesignSetterModePref];')
replace(p, 'if (!RYGOpenStoryTrayDebug()) [RYGUtils showErrorHUDWithDescription:@"Story Tray observation is armed. Let Instagram evaluate isTrayAttachedToHeaderEnabled: once, then retry; RyukGram will not invent the launcher-set result."];', 'if (!RYGOpenStoryTrayDebug()) [RYGUtils showErrorHUDWithDescription:@"Native Story Tray Debug controller is unavailable or its ABI no longer matches."];')

# MobileConfig engine: one-lock seen snapshot; exact B; targeted canonical JSON update instead of full export on every toggle.
p = "src/Features/ExpFlags/RYGMobileConfig.h"
replace(p, '- (NSString *)callSiteFor:(RYGMCParam *)param;', '- (NSString *)callSiteFor:(RYGMCParam *)param;\n- (NSSet<NSNumber *> *)seenParamIDs;')

p = "src/Features/ExpFlags/RYGMobileConfig.xm"
replace(p,
'''- (RYGMCOverrideState)overrideStateFor:(RYGMCParam *)param { return (param.runtimeBacked && param.paramID && _overrides[@(rygCanonicalPid(param.paramID))]) ? RYGMCOverrideSet : RYGMCOverrideNone; }''',
'''- (BOOL)updateCanonicalJSONForParam:(RYGMCParam *)param value:(id)value {
    if (!param) return NO;
    NSString *path = [self ryg_nativeOverridesJSONPath];
    if (!path.length) return NO;
    NSMutableDictionary *root = nil;
    NSData *existingData = [NSData dataWithContentsOfFile:path options:0 error:nil];
    if (existingData.length) {
        id parsed = [NSJSONSerialization JSONObjectWithData:existingData options:NSJSONReadingMutableContainers error:nil];
        if ([parsed isKindOfClass:NSDictionary.class]) root = [parsed mutableCopy];
    }
    if (!root) root = [NSMutableDictionary dictionary];
    NSString *configKey = [NSString stringWithFormat:@"%u:", param.configNumber];
    NSArray *existing = [root[configKey] isKindOfClass:NSArray.class] ? root[configKey] : @[];
    NSMutableArray<NSString *> *lines = [NSMutableArray arrayWithCapacity:existing.count + 1];
    NSString *prefix = [NSString stringWithFormat:@"%u: : ", param.paramIndex];
    for (id raw in existing) if ([raw isKindOfClass:NSString.class] && ![(NSString *)raw hasPrefix:prefix]) [lines addObject:raw];
    if (value) {
        NSString *text = nil;
        if (param.type == RYGMCTypeBool) text = [value boolValue] ? @"true" : @"false";
        else if (param.type == RYGMCTypeInt) text = [NSString stringWithFormat:@"%lld", [value longLongValue]];
        else if (param.type == RYGMCTypeDouble) text = [NSString stringWithFormat:@"%.17g", [value doubleValue]];
        else if (param.type == RYGMCTypeString && [value isKindOfClass:NSString.class]) text = value;
        if (text) [lines addObject:[prefix stringByAppendingString:text]];
    }
    if (lines.count) root[configKey] = lines.copy; else [root removeObjectForKey:configKey];
    NSData *data = [NSJSONSerialization dataWithJSONObject:root options:0 error:nil];
    return data.length && [data writeToFile:path options:NSDataWritingAtomic error:nil];
}

- (RYGMCOverrideState)overrideStateFor:(RYGMCParam *)param { return (param.runtimeBacked && param.paramID && _overrides[@(rygCanonicalPid(param.paramID))]) ? RYGMCOverrideSet : RYGMCOverrideNone; }''')
replace(p, 'unsigned long long pid = rygCanonicalPid(param.paramID); if (![self writeNativeBothUnitsForPid:pid value:value]) return NO; rygActivateOverride(pid,value); _overrides[@(pid)] = value; [self saveOverrides]; return YES;', 'unsigned long long pid = rygCanonicalPid(param.paramID); if (![self writeNativeBothUnitsForPid:pid value:value]) return NO; rygActivateOverride(pid,value); _overrides[@(pid)] = value; [self saveOverrides]; (void)[self updateCanonicalJSONForParam:param value:value]; return YES;')
replace(p, '- (void)clearOverrideFor:(RYGMCParam *)param { if (!param.runtimeBacked || !param.paramID) return; unsigned long long pid = rygCanonicalPid(param.paramID); [self removeNativeBothUnitsForPid:pid]; rygDeactivateOverride(pid); [_overrides removeObjectForKey:@(pid)]; [self saveOverrides]; }', '- (void)clearOverrideFor:(RYGMCParam *)param { if (!param.runtimeBacked || !param.paramID) return; unsigned long long pid = rygCanonicalPid(param.paramID); [self removeNativeBothUnitsForPid:pid]; rygDeactivateOverride(pid); [_overrides removeObjectForKey:@(pid)]; [self saveOverrides]; (void)[self updateCanonicalJSONForParam:param value:nil]; }')
replace(p, '- (void)resetAllOverrides { for (NSNumber *k in _overrides.allKeys.copy) { [self removeNativeBothUnitsForPid:k.unsignedLongLongValue]; rygDeactivateOverride(k.unsignedLongLongValue); } [_overrides removeAllObjects]; [self saveOverrides]; }', '- (void)resetAllOverrides { for (NSNumber *k in _overrides.allKeys.copy) { [self removeNativeBothUnitsForPid:k.unsignedLongLongValue]; rygDeactivateOverride(k.unsignedLongLongValue); } [_overrides removeAllObjects]; [self saveOverrides]; [self syncOverridesJSON]; }')
replace(p,
'- (NSString *)callSiteFor:(RYGMCParam *)param { if (!param.runtimeBacked || !param.paramID) return nil; unsigned long long best = [self bestParamIDFor:param]; pthread_mutex_lock(&gLock); NSValue *v = gCallSites[@(best)] ?: gCallSites[@(rygVariantPid(param.paramID,0x40))] ?: gCallSites[@(rygVariantPid(param.paramID,0x80))]; pthread_mutex_unlock(&gLock); if (!v) return nil; Dl_info info = {0}; if (dladdr(v.pointerValue,&info) && info.dli_sname) return [NSString stringWithUTF8String:info.dli_sname]; return @"Instagram runtime"; }',
'- (NSString *)callSiteFor:(RYGMCParam *)param { if (!param.runtimeBacked || !param.paramID) return nil; unsigned long long best = [self bestParamIDFor:param]; pthread_mutex_lock(&gLock); NSValue *v = gCallSites[@(best)] ?: gCallSites[@(rygVariantPid(param.paramID,0x40))] ?: gCallSites[@(rygVariantPid(param.paramID,0x80))]; pthread_mutex_unlock(&gLock); if (!v) return nil; Dl_info info = {0}; if (dladdr(v.pointerValue,&info) && info.dli_sname) return [NSString stringWithUTF8String:info.dli_sname]; return @"Instagram runtime"; }\n- (NSSet<NSNumber *> *)seenParamIDs { pthread_mutex_lock(&gLock); NSArray<NSNumber *> *keys = gCallSites.allKeys.copy ?: @[]; pthread_mutex_unlock(&gLock); NSMutableSet<NSNumber *> *out = [NSMutableSet setWithCapacity:keys.count]; for (NSNumber *key in keys) { unsigned long long raw = key.unsignedLongLongValue; if (raw) [out addObject:@(rygCanonicalPid(raw))]; } return out.copy; }')
replace(p, '- (void)saveOverrides { NSMutableDictionary *disk = [NSMutableDictionary dictionary]; for (NSNumber *k in _overrides) disk[k.stringValue] = _overrides[k]; [disk writeToFile:[self storePathFor:@"mc_overrides.plist"] atomically:YES]; [self syncOverridesJSON]; }', '- (void)saveOverrides { NSMutableDictionary *disk = [NSMutableDictionary dictionary]; for (NSNumber *k in _overrides) disk[k.stringValue] = _overrides[k]; [disk writeToFile:[self storePathFor:@"mc_overrides.plist"] atomically:YES]; }')
replace(p, "case 'B': return *t == 'B' || *t == 'c' || *t == 'C';", "case 'B': return *t == 'B';")

# Fast MobileConfig browser: one seen snapshot and direct native apply for runtime-backed rows.
p = "src/Features/ExpFlags/RYGFastMobileConfigBrowserViewController.m"
replace(p, '''static NSString *RYGFastMCConfigKey(unsigned int configNumber) {
    return [NSString stringWithFormat:@"%u:", configNumber];
}''', '''static NSString *RYGFastMCConfigKey(unsigned int configNumber) {
    return [NSString stringWithFormat:@"%u:", configNumber];
}

static unsigned long long RYGFastMCCanonicalPid(unsigned long long pid) {
    if (!pid) return 0;
    unsigned long long type = (pid >> 48) & 0x0FULL;
    return (pid & 0x0000FFFFFFFFFFFFULL) | ((0x40ULL | type) << 48);
}''')
replace(p, '- (BOOL)setValueText:(nullable NSString *)valueText forParam:(RYGMCParam *)param error:(NSError **)error;\n@end', '- (BOOL)setValueText:(nullable NSString *)valueText forParam:(RYGMCParam *)param error:(NSError **)error;\n- (void)updateCachedValueText:(nullable NSString *)valueText forParam:(RYGMCParam *)param;\n@end')
replace(p,
'- (BOOL)setValueText:(NSString *)valueText forParam:(RYGMCParam *)param error:(NSError **)error {',
'''- (void)updateCachedValueText:(NSString *)valueText forParam:(RYGMCParam *)param {
    if (!param) return;
    NSString *key = RYGFastMCConfigKey(param.configNumber);
    NSArray *existing = [self.root[key] isKindOfClass:NSArray.class] ? self.root[key] : @[];
    NSMutableArray<NSString *> *lines = [NSMutableArray array];
    for (id raw in existing) {
        if (![raw isKindOfClass:NSString.class]) continue;
        unsigned int index = 0;
        if (RYGFastMCParseLine(raw, &index, NULL) && index == param.paramIndex) continue;
        [lines addObject:raw];
    }
    if (valueText) [lines addObject:[NSString stringWithFormat:@"%u%@%@", param.paramIndex, kRYGFastMCSeparator, valueText]];
    if (lines.count) self.root[key] = lines.copy; else [self.root removeObjectForKey:key];
}

- (BOOL)setValueText:(NSString *)valueText forParam:(RYGMCParam *)param error:(NSError **)error {''')
replace(p, 'NSMutableDictionary<NSNumber *, NSString *> *blobs = [NSMutableDictionary dictionaryWithCapacity:configs.count];\n        NSMutableSet<NSNumber *> *seen = [NSMutableSet set];', 'NSMutableDictionary<NSNumber *, NSString *> *blobs = [NSMutableDictionary dictionaryWithCapacity:configs.count];\n        NSSet<NSNumber *> *seenPIDs = [engine seenParamIDs];\n        NSMutableSet<NSNumber *> *seen = [NSMutableSet set];')
replace(p, 'if (!configSeen && param.isRuntimeBacked && [engine callSiteFor:param].length) configSeen = YES;', 'if (!configSeen && param.isRuntimeBacked && param.paramID && [seenPIDs containsObject:@(RYGFastMCCanonicalPid(param.paramID))]) configSeen = YES;')
replace(p,
'''- (BOOL)setText:(NSString *)text forParam:(RYGMCParam *)param {
    NSError *error = nil; BOOL ok = [self.documentStore setValueText:text forParam:param error:&error];
    if (!ok) [RYGUtils showErrorHUDWithDescription:error.localizedDescription ?: @"Could not update mc_overrides.json"];
    else { if (self.documentDidChange) self.documentDidChange(); [self.tableView reloadData]; }
    return ok;
}''',
'''- (BOOL)setText:(NSString *)text forParam:(RYGMCParam *)param {
    NSError *error = nil;
    BOOL ok = NO;
    if (param.isRuntimeBacked && RYGMCTypeIsRuntimeValue(param.type)) {
        RYGMobileConfig *engine = RYGMobileConfig.shared;
        if (!text) {
            [engine clearOverrideFor:param];
            [self.documentStore updateCachedValueText:nil forParam:param];
            ok = YES;
        } else {
            id value = nil;
            switch (param.type) {
                case RYGMCTypeBool: value = @([text.lowercaseString isEqualToString:@"true"]); break;
                case RYGMCTypeInt: value = @([text longLongValue]); break;
                case RYGMCTypeDouble: value = @([text doubleValue]); break;
                case RYGMCTypeString: value = text; break;
                default: break;
            }
            ok = value && [engine setOverride:value for:param];
            if (ok) [self.documentStore updateCachedValueText:text forParam:param];
        }
    } else {
        ok = [self.documentStore setValueText:text forParam:param error:&error];
    }
    if (!ok) [RYGUtils showErrorHUDWithDescription:error.localizedDescription ?: @"Could not apply MobileConfig override"];
    else { if (self.documentDidChange) self.documentDidChange(); [self.tableView reloadData]; }
    return ok;
}''')

print("binary-validated staging transformation applied")
