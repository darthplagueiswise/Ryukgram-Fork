#import "SCIEnabledExperimentRuntime.h"
#import "SCIDexKitScanner.h"
#import "SCIDexKitStore.h"
#import "SCIDexKitBoolRouter.h"

@implementation SCIEnabledExperimentEntry
@end

@implementation SCIEnabledExperimentRuntime

+ (void)install { }

+ (SCIEnabledExperimentEntry *)entryFromDescriptor:(SCIDexKitDescriptor *)d {
    SCIEnabledExperimentEntry *e = [SCIEnabledExperimentEntry new];
    e.key = d.overrideKey;
    e.className = d.className;
    e.methodName = d.selectorName;
    e.source = d.imageBasename;
    e.imageName = d.imageBasename;
    e.typeEncoding = d.typeEncoding;
    e.classMethod = d.classMethod;
    e.defaultKnown = d.observedKnown;
    e.defaultValue = d.observedValue;
    NSNumber *forced = [SCIDexKitStore overrideValueForKey:d.overrideKey];
    e.savedState = forced ? (forced.boolValue ? SCIExpFlagOverrideTrue : SCIExpFlagOverrideFalse) : SCIExpFlagOverrideOff;
    return e;
}

+ (SCIDexKitDescriptor *)descriptorFromEntry:(SCIEnabledExperimentEntry *)entry {
    NSString *image = nil, *sign = nil, *cls = nil, *sel = nil;
    if (![SCIDexKitStore parseBoolKey:entry.key image:&image sign:&sign className:&cls selector:&sel]) return nil;
    SCIDexKitDescriptor *d = [SCIDexKitDescriptor new];
    d.imageBasename = image;
    d.className = cls;
    d.selectorName = sel;
    d.classMethod = [sign isEqualToString:@"+"];
    d.overrideKey = entry.key;
    d.observedKey = [SCIDexKitStore observedKeyForOverrideKey:entry.key];
    return d;
}

+ (NSArray<SCIEnabledExperimentEntry *> *)allEntries {
    NSMutableArray *out = [NSMutableArray array];
    for (SCIDexKitDescriptor *d in [SCIDexKitScanner scanDescriptorsWithMode:SCIDexKitScannerModeCurated query:nil]) [out addObject:[self entryFromDescriptor:d]];
    return out;
}

+ (NSArray<SCIEnabledExperimentEntry *> *)filteredEntriesForQuery:(NSString *)query mode:(NSInteger)mode {
    NSMutableArray *out = [NSMutableArray array];
    for (SCIDexKitDescriptor *d in [SCIDexKitScanner scanDescriptorsWithMode:SCIDexKitScannerModeCurated query:query]) {
        if (mode == 1 && !d.observedKnown) continue;
        if (mode == 2 && d.effectiveState != SCIDexKitKnownBoolStateOn) continue;
        if (mode == 3 && d.effectiveState != SCIDexKitKnownBoolStateOff) continue;
        if (mode == 4 && !d.overrideValue) continue;
        [out addObject:[self entryFromDescriptor:d]];
    }
    return out;
}

+ (void)setSavedState:(SCIExpFlagOverride)state forEntry:(SCIEnabledExperimentEntry *)entry {
    NSNumber *value = nil;
    if (state == SCIExpFlagOverrideTrue) value = @YES;
    if (state == SCIExpFlagOverrideFalse) value = @NO;
    [SCIDexKitStore setOverrideValue:value forKey:entry.key];
    SCIDexKitDescriptor *d = [self descriptorFromEntry:entry];
    if (value && d) SCIDexKitInstallHookForDescriptor(d, SCIDexKitInstallReasonUserOverride, nil);
}

+ (SCIExpFlagOverride)savedStateForEntry:(SCIEnabledExperimentEntry *)entry {
    NSNumber *v = [SCIDexKitStore overrideValueForKey:entry.key];
    if (!v) return SCIExpFlagOverrideOff;
    return v.boolValue ? SCIExpFlagOverrideTrue : SCIExpFlagOverrideFalse;
}
+ (NSString *)stateLabelForEntry:(SCIEnabledExperimentEntry *)entry {
    SCIExpFlagOverride s = [self savedStateForEntry:entry];
    return s == SCIExpFlagOverrideTrue ? @"OVERRIDE ON" : (s == SCIExpFlagOverrideFalse ? @"OVERRIDE OFF" : @"SYSTEM");
}
+ (NSString *)defaultLabelForEntry:(SCIEnabledExperimentEntry *)entry { return entry.defaultKnown ? (entry.defaultValue ? @"ON" : @"OFF") : @"unknown"; }
+ (NSString *)summaryTextForEntry:(SCIEnabledExperimentEntry *)entry { return [NSString stringWithFormat:@"%@ · %@ · %@", entry.imageName ?: @"?", [self defaultLabelForEntry:entry], [self stateLabelForEntry:entry]]; }
+ (NSUInteger)installedCount { return SCIDexKitInstalledHookCount(); }
@end
