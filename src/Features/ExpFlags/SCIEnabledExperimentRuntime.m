#import "SCIEnabledExperimentRuntime.h"
#import <UIKit/UIKit.h>
#import <objc/runtime.h>
#import <objc/message.h>
#import <dlfcn.h>
#import <substrate.h>

static NSString *const kSCIEnabledOverridePrefix = @"objc-enabled:";

@implementation SCIEnabledExperimentEntry
@end

static NSMutableDictionary<NSString *, SCIEnabledExperimentEntry *> *gSCIEnabledEntries;
static NSMutableDictionary<NSString *, NSValue *> *gSCIEnabledOriginalIMPs;
static NSUInteger gSCIEnabledInstalledCount = 0;
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

static BOOL SCIEnabledStringLooksWanted(NSString *className, NSString *methodName) {
    NSString *s = [NSString stringWithFormat:@"%@ %@", className ?: @"", methodName ?: @""].lowercaseString;
    BOOL hasEnabled = [s containsString:@"enabled"] || [s containsString:@"isenabled"] || [s containsString:@"shouldenable"] || [s containsString:@"shouldshow"] || [s containsString:@"eligib"];
    BOOL hasExperiment = [s containsString:@"experiment"] || [s containsString:@"mobileconfig"] || [s containsString:@"easygating"] || [s containsString:@"launcherset"] || [s containsString:@"dogfood"] || [s containsString:@"internal"] || [s containsString:@"feature"];
    return hasEnabled && hasExperiment;
}

static NSString *SCIEnabledSource(NSString *className, NSString *methodName) {
    NSString *s = [NSString stringWithFormat:@"%@ %@", className ?: @"", methodName ?: @""].lowercaseString;
    if ([s containsString:@"fbcustomexperimentmanager"]) return @"FBCustomExperimentManager";
    if ([s containsString:@"fdidexperimentgenerator"]) return @"FDIDExperimentGenerator";
    if ([s containsString:@"lidexperimentgenerator"] || [s containsString:@"lidlocalexperiment"]) return @"LID/MetaLocalExperiment";
    if ([s containsString:@"metalocalexperiment"]) return @"MetaLocalExperiment";
    if ([s containsString:@"mobileconfig"] || [s containsString:@"easygating"]) return @"MobileConfig/EasyGating";
    if ([s containsString:@"launcherset"]) return @"IGUserLauncherSet";
    if ([s containsString:@"dogfood"] || [s containsString:@"internal"]) return @"Dogfood/Internal";
    if ([s containsString:@"quick"] || [s containsString:@"snap"]) return @"QuickSnap/Direct";
    if ([s containsString:@"friend"] || [s containsString:@"friending"]) return @"Friending/FriendsTab";
    if ([s containsString:@"feed"]) return @"Feed";
    if ([s containsString:@"direct"] || [s containsString:@"inbox"] || [s containsString:@"thread"]) return @"Direct/Inbox";
    if ([s containsString:@"blend"]) return @"Blend";
    if ([s containsString:@"magicmode"] || [s containsString:@"genai"]) return @"GenAI/MagicMod";
    return @"Main Executable";
}

static NSString *SCIEnabledKeyForReceiver(id receiver, SEL sel, NSString **declaredClassOut) {
    NSString *methodName = NSStringFromSelector(sel);
    BOOL classMethod = object_isClass(receiver);
    Class cls = classMethod ? (Class)receiver : object_getClass(receiver);
    while (cls) {
        NSString *className = NSStringFromClass(cls);
        NSString *key = SCIEnabledKey(classMethod, className, methodName);
        if (gSCIEnabledOriginalIMPs[key]) {
            if (declaredClassOut) *declaredClassOut = className;
            return key;
        }
        cls = class_getSuperclass(cls);
    }
    return nil;
}

static BOOL SCIEnabledBoolReplacement(id self, SEL _cmd) {
    NSString *declaredClass = nil;
    NSString *key = SCIEnabledKeyForReceiver(self, _cmd, &declaredClass);
    NSValue *origValue = key ? gSCIEnabledOriginalIMPs[key] : nil;
    BOOL original = NO;
    if (origValue) {
        BOOL (*orig)(id, SEL) = (BOOL (*)(id, SEL))origValue.pointerValue;
        if (orig) original = orig(self, _cmd);
    }

    if (key) {
        @synchronized([SCIEnabledExperimentRuntime class]) {
            SCIEnabledExperimentEntry *entry = gSCIEnabledEntries[key];
            entry.defaultKnown = YES;
            entry.defaultValue = original;
            entry.hitCount++;
            entry.savedState = [SCIExpFlags overrideForName:key];
        }
        SCIExpFlagOverride state = [SCIExpFlags overrideForName:key];
        if (state == SCIExpFlagOverrideTrue) return YES;
        if (state == SCIExpFlagOverrideFalse) return NO;
    }
    return original;
}

@implementation SCIEnabledExperimentRuntime

+ (void)install {
    dispatch_once(&gSCIEnabledInstallOnce, ^{
        gSCIEnabledEntries = [NSMutableDictionary dictionary];
        gSCIEnabledOriginalIMPs = [NSMutableDictionary dictionary];

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
                unsigned int methodCount = 0;
                Method *methods = class_copyMethodList(methodClass, &methodCount);
                for (unsigned int i = 0; i < methodCount; i++) {
                    Method m = methods[i];
                    SEL sel = method_getName(m);
                    NSString *methodName = NSStringFromSelector(sel);
                    if (!SCIEnabledMethodReturnsBool(m)) continue;
                    if (method_getNumberOfArguments(m) != 2) continue;
                    if (!SCIEnabledStringLooksWanted(className, methodName)) continue;

                    IMP imp = method_getImplementation(m);
                    Dl_info info;
                    memset(&info, 0, sizeof(info));
                    if (dladdr((void *)imp, &info) == 0) continue;
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
                    entry.savedState = [SCIExpFlags overrideForName:key];
                    gSCIEnabledEntries[key] = entry;

                    Class hookClass = classMethod ? object_getClass(cls) : cls;
                    IMP original = NULL;
                    MSHookMessageEx(hookClass, sel, (IMP)SCIEnabledBoolReplacement, &original);
                    if (original) {
                        gSCIEnabledOriginalIMPs[key] = [NSValue valueWithPointer:original];
                        gSCIEnabledInstalledCount++;
                    } else {
                        [gSCIEnabledEntries removeObjectForKey:key];
                    }
                }
                if (methods) free(methods);
            }
        }
        if (classes) free(classes);
        NSLog(@"[RyukGram][EnabledExperiments] installed %lu main-exec no-arg BOOL getter hooks", (unsigned long)gSCIEnabledInstalledCount);
    });
}

+ (NSArray<SCIEnabledExperimentEntry *> *)allEntries {
    [self install];
    NSArray *values = nil;
    @synchronized(self) {
        values = [gSCIEnabledEntries.allValues copy];
        for (SCIEnabledExperimentEntry *e in values) e.savedState = [SCIExpFlags overrideForName:e.key];
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
            NSString *hay = [NSString stringWithFormat:@"%@ %@ %@ %@ %@", e.source, e.className, e.methodName, e.typeEncoding, e.key].lowercaseString;
            if (![hay containsString:q]) continue;
        }
        [out addObject:e];
    }
    return out;
}

+ (void)setSavedState:(SCIExpFlagOverride)state forEntry:(SCIEnabledExperimentEntry *)entry {
    if (!entry.key.length) return;
    [SCIExpFlags setOverride:state forName:entry.key];
    entry.savedState = state;
}

+ (SCIExpFlagOverride)savedStateForEntry:(SCIEnabledExperimentEntry *)entry {
    return [SCIExpFlags overrideForName:entry.key];
}

+ (NSString *)stateLabelForEntry:(SCIEnabledExperimentEntry *)entry {
    SCIExpFlagOverride state = [self savedStateForEntry:entry];
    if (state == SCIExpFlagOverrideTrue) return @"FORCE YES";
    if (state == SCIExpFlagOverrideFalse) return @"FORCE NO";
    return @"DEFAULT";
}

+ (NSString *)defaultLabelForEntry:(SCIEnabledExperimentEntry *)entry {
    if (!entry.defaultKnown) return @"not observed yet";
    return entry.defaultValue ? @"YES" : @"NO";
}

+ (NSString *)summaryTextForEntry:(SCIEnabledExperimentEntry *)entry {
    return [NSString stringWithFormat:@"source=%@ · default=%@ · state=%@ · hits=%lu · %@ · %@",
            entry.source ?: @"?",
            [self defaultLabelForEntry:entry],
            [self stateLabelForEntry:entry],
            (unsigned long)entry.hitCount,
            entry.imageName ?: @"?",
            entry.typeEncoding ?: @""];
}

+ (NSUInteger)installedCount {
    [self install];
    return gSCIEnabledInstalledCount;
}

@end
