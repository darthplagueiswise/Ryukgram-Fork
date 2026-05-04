#import "SCIEnabledExperimentRuntime.h"
#import "SCIDexKitStore.h"
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

@implementation SCIEnabledExperimentEntry
@end

static NSMutableDictionary<NSString *, SCIEnabledExperimentEntry *> *gSCIEnabledEntries;
static dispatch_once_t gSCIEnabledInstallOnce;

static NSString *SCIImageBasename(const char *path) {
    if (!path) return @"";
    const char *slash = strrchr(path, '/');
    return [NSString stringWithUTF8String:(slash ? slash + 1 : path)] ?: @"";
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
    NSString *s = [NSString stringWithFormat:@"%@ %@", className ?: @"", methodName ?: @""].lowercaseString;

    if (SCIEnabledContainsAny(s, @[
        @"autofillinternalsettings", @"autofill",
        @"prism", @"prismmenu", @"igdsprism",
        @"directnotes", @"notesdogfooding", @"notestray",
        @"quicksnap", @"quick_snap", @"instant",
        @"homecoming", @"liquidglass", @"tabbar", @"launcherset"
    ])) return YES;

    BOOL hasEnabled = SCIEnabledContainsAny(s, @[@"enabled", @"isenabled", @"shouldenable", @"shouldshow", @"eligib", @"available"]);
    BOOL hasExperiment = SCIEnabledContainsAny(s, @[@"experiment", @"mobileconfig", @"easygating", @"dogfood", @"internal", @"feature", @"rollout"]);
    return hasEnabled && hasExperiment;
}

static NSString *SCIEnabledSource(NSString *className, NSString *methodName) {
    NSString *s = [NSString stringWithFormat:@"%@ %@", className ?: @"", methodName ?: @""].lowercaseString;

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

static void SCIEnabledRefreshEntry(SCIEnabledExperimentEntry *entry) {
    entry.savedState = [SCIDexKitStore overrideForKey:entry.key];
    NSNumber *observed = [SCIDexKitStore observedBoolGetterValueForKey:entry.key];
    if (observed != nil) {
        entry.defaultKnown = YES;
        entry.defaultValue = observed.boolValue;
    }
}

@implementation SCIEnabledExperimentRuntime

+ (void)install {
    dispatch_once(&gSCIEnabledInstallOnce, ^{
        gSCIEnabledEntries = [NSMutableDictionary dictionary];
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

                    NSString *key = [SCIDexKitStore boolGetterKeyWithClassName:className methodName:methodName classMethod:classMethod];
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
                    SCIEnabledRefreshEntry(entry);
                    gSCIEnabledEntries[key] = entry;

                    if ([SCIDexKitStore overrideForKey:key] != SCIExpFlagOverrideOff) {
                        SCIDexKitInstallBoolGetterHook(key, className, methodName, classMethod);
                    }
                }
                if (methods) free(methods);
            }
        }
        if (classes) free(classes);
        NSLog(@"[RyukGram][EnabledExperiments] DexKit store scan entries=%lu", (unsigned long)gSCIEnabledEntries.count);
    });
}

+ (NSArray<SCIEnabledExperimentEntry *> *)allEntries {
    [self install];
    NSArray *values = nil;
    @synchronized(self) {
        values = [gSCIEnabledEntries.allValues copy];
        for (SCIEnabledExperimentEntry *e in values) SCIEnabledRefreshEntry(e);
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
        if (mode == 4 && [SCIDexKitStore overrideForKey:e.key] == SCIExpFlagOverrideOff) continue;
        if (q.length) {
            NSString *hay = [NSString stringWithFormat:@"%@ %@ %@ %@ %@", e.source, e.className, e.methodName, e.typeEncoding, e.key].lowercaseString;
            if (![hay containsString:q]) continue;
        }
        [out addObject:e];
    }
    return out;
}

+ (void)setSavedState:(SCIExpFlagOverride)state forEntry:(SCIEnabledExperimentEntry *)entry {
    if (!entry.key.length) return;
    if (state != SCIExpFlagOverrideOff) {
        SCIDexKitInstallBoolGetterHook(entry.key, entry.className, entry.methodName, entry.classMethod);
    }
    [SCIDexKitStore setOverride:state forKey:entry.key];
    entry.savedState = state;
}

+ (SCIExpFlagOverride)savedStateForEntry:(SCIEnabledExperimentEntry *)entry {
    return [SCIDexKitStore overrideForKey:entry.key];
}

+ (NSString *)stateLabelForEntry:(SCIEnabledExperimentEntry *)entry {
    return [SCIDexKitStore overrideLabelForKey:entry.key];
}

+ (NSString *)defaultLabelForEntry:(SCIEnabledExperimentEntry *)entry {
    return [SCIDexKitStore systemLabelForKnown:entry.defaultKnown value:entry.defaultValue];
}

+ (NSString *)summaryTextForEntry:(SCIEnabledExperimentEntry *)entry {
    NSString *router = SCIDexKitIsBoolGetterHooked(entry.key) ? @"live" : @"off";
    return [NSString stringWithFormat:@"%@ · system=%@ · %@ · router=%@", entry.source ?: @"?", [self defaultLabelForEntry:entry], [self stateLabelForEntry:entry], router];
}

+ (NSUInteger)installedCount {
    [self install];
    NSUInteger n = 0;
    for (SCIEnabledExperimentEntry *entry in gSCIEnabledEntries.allValues) if (SCIDexKitIsBoolGetterHooked(entry.key)) n++;
    return n;
}

@end
