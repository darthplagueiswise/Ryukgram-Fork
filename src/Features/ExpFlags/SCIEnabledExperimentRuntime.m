#import "SCIEnabledExperimentRuntime.h"
#import <UIKit/UIKit.h>
#import <objc/runtime.h>
#import <dlfcn.h>

#ifdef __cplusplus
extern "C" {
#endif
BOOL SCIDexKitInstallBoolGetterHook(NSString *key, NSString *className, NSString *methodName, BOOL classMethod);
BOOL SCIDexKitIsBoolGetterHooked(NSString *key);
#ifdef __cplusplus
}
#endif

static NSString *const kSCIEnabledOverridePrefix = @"objc-enabled:";
static NSString *const kSCIEnabledObservedDefaultsKey = @"sci_enabled_experiment_observed_defaults";

@implementation SCIEnabledExperimentEntry
@end

static NSMutableDictionary<NSString *, SCIEnabledExperimentEntry *> *gSCIEnabledEntries;
static dispatch_once_t gSCIEnabledInstallOnce;

static NSString *SCIImageBasename(const char *path) {
    if (!path) return @"";
    const char *slash = strrchr(path, '/');
    return [NSString stringWithUTF8String:(slash ? slash + 1 : path)] ?: @"";
}

static NSString *SCIEnabledKey(BOOL classMethod, NSString *className, NSString *methodName) {
    return [NSString stringWithFormat:@"%@%@%@ %@",
            kSCIEnabledOverridePrefix,
            classMethod ? @"+" : @"-",
            className ?: @"",
            methodName ?: @""];
}

static BOOL SCIEnabledMethodReturnsBool(Method m) {
    if (!m) return NO;

    char rt[32] = {0};
    method_getReturnType(m, rt, sizeof(rt));
    return rt[0] == 'B' || rt[0] == 'c';
}

static NSString *SCIEnabledMethodTypes(Method m) {
    const char *types = m ? method_getTypeEncoding(m) : NULL;
    return types ? @(types) : @"";
}

static BOOL SCIEnabledContainsAny(NSString *s, NSArray<NSString *> *tokens) {
    for (NSString *token in tokens) {
        if ([s containsString:token]) return YES;
    }

    return NO;
}

static BOOL SCIEnabledStringLooksWanted(NSString *className, NSString *methodName) {
    NSString *s = [NSString stringWithFormat:@"%@ %@",
                   className ?: @"",
                   methodName ?: @""].lowercaseString;

    if (SCIEnabledContainsAny(s, @[
        @"autofillinternalsettings",
        @"autofill",
        @"prism",
        @"prismmenu",
        @"igdsprism",
        @"directnotes",
        @"notesdogfooding",
        @"notestray",
        @"quicksnap",
        @"quick_snap",
        @"instant",
        @"homecoming",
        @"liquidglass",
        @"tabbar",
        @"launcherset"
    ])) {
        return YES;
    }

    BOOL hasEnabled = SCIEnabledContainsAny(s, @[
        @"enabled",
        @"isenabled",
        @"shouldenable",
        @"shouldshow",
        @"eligib",
        @"available"
    ]);

    BOOL hasExperiment = SCIEnabledContainsAny(s, @[
        @"experiment",
        @"mobileconfig",
        @"easygating",
        @"dogfood",
        @"internal",
        @"feature",
        @"rollout"
    ]);

    return hasEnabled && hasExperiment;
}

static NSString *SCIEnabledSource(NSString *className, NSString *methodName) {
    NSString *s = [NSString stringWithFormat:@"%@ %@",
                   className ?: @"",
                   methodName ?: @""].lowercaseString;

    if (SCIEnabledContainsAny(s, @[@"autofillinternalsettings", @"autofill"])) return @"Autofill/Internal";
    if (SCIEnabledContainsAny(s, @[@"prism", @"prismmenu", @"igdsprism"])) return @"Prism/Menu";
    if (SCIEnabledContainsAny(s, @[@"directnotes", @"notesdogfooding", @"notestray"])) return @"Direct Notes";
    if (SCIEnabledContainsAny(s, @[@"quicksnap", @"quick_snap", @"instant"])) return @"QuickSnap/Direct";
    if ([s containsString:@"homecoming"]) return @"Homecoming";
    if (SCIEnabledContainsAny(s, @[@"liquidglass", @"tabbar", @"launcherset"])) return @"LiquidGlass/TabBar";
    if ([s containsString:@"fbcustomexperimentmanager"]) return @"FBCustomExperimentManager";
    if ([s containsString:@"fdidexperimentgenerator"]) return @"FDIDExperimentGenerator";
    if ([s containsString:@"lidexperimentgenerator"] || [s containsString:@"lidlocalexperiment"]) return @"LID/MetaLocalExperiment";
    if ([s containsString:@"metalocalexperiment"]) return @"MetaLocalExperiment";
    if ([s containsString:@"mobileconfig"] || [s containsString:@"easygating"]) return @"MobileConfig/EasyGating";
    if ([s containsString:@"dogfood"] || [s containsString:@"internal"]) return @"Dogfood/Internal";
    if ([s containsString:@"friend"] || [s containsString:@"friending"]) return @"Friending/FriendsTab";
    if ([s containsString:@"feed"]) return @"Feed";
    if ([s containsString:@"direct"] || [s containsString:@"inbox"] || [s containsString:@"thread"]) return @"Direct/Inbox";
    if ([s containsString:@"blend"]) return @"Blend";
    if ([s containsString:@"magicmode"] || [s containsString:@"genai"]) return @"GenAI/MagicMod";

    return @"Main Executable";
}

static NSDictionary *SCIEnabledObservedDefaults(void) {
    NSDictionary *d = [[NSUserDefaults standardUserDefaults] dictionaryForKey:kSCIEnabledObservedDefaultsKey];
    return [d isKindOfClass:NSDictionary.class] ? d : @{};
}

static void SCIEnabledRefreshEntry(SCIEnabledExperimentEntry *entry, NSDictionary *observedDefaults) {
    entry.savedState = [SCIExpFlags overrideForName:entry.key];

    NSNumber *observed = observedDefaults[entry.key];
    if (observed != nil) {
        entry.defaultKnown = YES;
        entry.defaultValue = observed.boolValue;
    }
}

@implementation SCIEnabledExperimentRuntime

+ (void)install {
    dispatch_once(&gSCIEnabledInstallOnce, ^{
        gSCIEnabledEntries = [NSMutableDictionary dictionary];

        NSDictionary *observedDefaults = SCIEnabledObservedDefaults();
        NSString *mainImageName = NSBundle.mainBundle.executablePath.lastPathComponent ?: @"";

        unsigned int classCount = 0;
        Class *classes = objc_copyClassList(&classCount);

        for (unsigned int c = 0; c < classCount; c++) {
            Class cls = classes[c];
            NSString *className = NSStringFromClass(cls);

            if (!className.length) continue;

            for (int pass = 0; pass < 2; pass++) {
                BOOL classMethod = (pass == 1);
                Class methodClass = classMethod ? object_getClass(cls) : cls;

                if (!methodClass) continue;

                unsigned int methodCount = 0;
                Method *methods = class_copyMethodList(methodClass, &methodCount);

                for (unsigned int i = 0; i < methodCount; i++) {
                    Method m = methods[i];

                    if (!SCIEnabledMethodReturnsBool(m)) continue;
                    if (method_getNumberOfArguments(m) != 2) continue;

                    SEL sel = method_getName(m);
                    NSString *methodName = NSStringFromSelector(sel);

                    if (!SCIEnabledStringLooksWanted(className, methodName)) continue;

                    Dl_info info;
                    memset(&info, 0, sizeof(info));

                    if (dladdr((void *)method_getImplementation(m), &info) == 0) continue;

                    NSString *imageName = SCIImageBasename(info.dli_fname);
                    if (![imageName isEqualToString:mainImageName]) continue;

                    NSString *key = SCIEnabledKey(classMethod, className, methodName);
                    if (gSCIEnabledEntries[key]) continue;

                    SCIEnabledExperimentEntry *entry = [SCIEnabledExperimentEntry new];
                    entry.key = key;
                    entry.className = className;
                    entry.methodName = methodName;
                    entry.source = SCIEnabledSource(className, methodName);
                    entry.imageName = imageName;
                    entry.typeEncoding = SCIEnabledMethodTypes(m);
                    entry.classMethod = classMethod;
                    entry.defaultKnown = NO;
                    entry.defaultValue = NO;
                    entry.hitCount = 0;

                    SCIEnabledRefreshEntry(entry, observedDefaults);

                    gSCIEnabledEntries[key] = entry;

                    if ([SCIExpFlags overrideForName:key] != SCIExpFlagOverrideOff) {
                        SCIDexKitInstallBoolGetterHook(key, className, methodName, classMethod);
                    }
                }

                if (methods) free(methods);
            }
        }

        if (classes) free(classes);

        NSLog(@"[RyukGram][EnabledExperiments] metadata scan entries=%lu",
              (unsigned long)gSCIEnabledEntries.count);
    });
}

+ (NSArray<SCIEnabledExperimentEntry *> *)allEntries {
    [self install];

    NSArray *values = nil;

    @synchronized(self) {
        values = [gSCIEnabledEntries.allValues copy];

        NSDictionary *observedDefaults = SCIEnabledObservedDefaults();

        for (SCIEnabledExperimentEntry *e in values) {
            SCIEnabledRefreshEntry(e, observedDefaults);
        }
    }

    return [values sortedArrayUsingComparator:^NSComparisonResult(SCIEnabledExperimentEntry *a, SCIEnabledExperimentEntry *b) {
        NSComparisonResult c = [a.source caseInsensitiveCompare:b.source];
        if (c != NSOrderedSame) return c;

        c = [a.className caseInsensitiveCompare:b.className];
        if (c != NSOrderedSame) return c;

        return [a.methodName caseInsensitiveCompare:b.methodName];
    }];
}

+ (NSArray<SCIEnabledExperimentEntry *> *)filteredEntriesForQuery:(NSString *)query mode:(NSInteger)mode {
    NSString *q = query.lowercaseString ?: @"";
    NSMutableArray *out = [NSMutableArray array];

    for (SCIEnabledExperimentEntry *e in [self allEntries]) {
        if (mode == 1 && !e.defaultKnown) continue;
        if (mode == 2 && (!e.defaultKnown || !e.defaultValue)) continue;
        if (mode == 3 && (!e.defaultKnown || e.defaultValue)) continue;
        if (mode == 4 && [SCIExpFlags overrideForName:e.key] == SCIExpFlagOverrideOff) continue;

        if (q.length) {
            NSString *hay = [NSString stringWithFormat:@"%@ %@ %@ %@ %@",
                             e.source,
                             e.className,
                             e.methodName,
                             e.typeEncoding,
                             e.key].lowercaseString;

            if (![hay containsString:q]) continue;
        }

        [out addObject:e];
    }

    return out;
}

+ (void)setSavedState:(SCIExpFlagOverride)state forEntry:(SCIEnabledExperimentEntry *)entry {
    if (!entry.key.length) return;

    if (state != SCIExpFlagOverrideOff) {
        SCIDexKitInstallBoolGetterHook(entry.key,
                                       entry.className,
                                       entry.methodName,
                                       entry.classMethod);
    }

    [SCIExpFlags setOverride:state forName:entry.key];
    entry.savedState = state;
}

+ (SCIExpFlagOverride)savedStateForEntry:(SCIEnabledExperimentEntry *)entry {
    return [SCIExpFlags overrideForName:entry.key];
}

+ (NSString *)stateLabelForEntry:(SCIEnabledExperimentEntry *)entry {
    SCIExpFlagOverride state = [self savedStateForEntry:entry];

    if (state == SCIExpFlagOverrideTrue) return @"OVERRIDE ON";
    if (state == SCIExpFlagOverrideFalse) return @"OVERRIDE OFF";

    return @"SYSTEM";
}

+ (NSString *)defaultLabelForEntry:(SCIEnabledExperimentEntry *)entry {
    if (!entry.defaultKnown) return @"unknown";
    return entry.defaultValue ? @"ON" : @"OFF";
}

+ (NSString *)summaryTextForEntry:(SCIEnabledExperimentEntry *)entry {
    NSString *router = SCIDexKitIsBoolGetterHooked(entry.key) ? @"router=live" : @"router=off";

    return [NSString stringWithFormat:@"source=%@ · system=%@ · state=%@ · %@ · %@ · %@",
            entry.source ?: @"?",
            [self defaultLabelForEntry:entry],
            [self stateLabelForEntry:entry],
            router,
            entry.imageName ?: @"?",
            entry.typeEncoding ?: @""];
}

+ (NSUInteger)installedCount {
    [self install];

    NSUInteger n = 0;

    for (SCIEnabledExperimentEntry *entry in gSCIEnabledEntries.allValues) {
        if (SCIDexKitIsBoolGetterHooked(entry.key)) n++;
    }

    return n;
}

@end
