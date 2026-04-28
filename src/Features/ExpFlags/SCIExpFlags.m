#import "SCIExpFlags.h"
#import "SCIMachODexKitResolver.h"
#import <sys/mman.h>
#import <sys/stat.h>
#import <fcntl.h>
#import <dlfcn.h>

static NSString *const kOverridesKey    = @"sci_exp_overrides_by_name";
static NSString *const kCrashCounterKey = @"sci_exp_flags_unstable_launches";
static const NSInteger kCrashThreshold  = 3;

@implementation SCIExpObservation @end
@implementation SCIExpMCObservation @end
@implementation SCIExpInternalUseObservation @end

@implementation SCIExpFlags

// overrides
+ (NSMutableDictionary *)loadOverrides { ... }  // (keep all original methods exactly as they were)

// ... (all the original code for observations, crash guard, etc. remains unchanged)

// ============================================================
// CLEAN INTEGRATION: DexKit-level resolver
// ============================================================

static NSString *SCIResolvedSpecifierName(NSString *specifierName,
                                          unsigned long long specifier,
                                          NSString *functionName,
                                          void *callerAddress) {

    SCIMachODexKitResolvedName *resolved =
        [[SCIMachODexKitResolver sharedResolver] resolvedNameForSpecifier:specifier
                                                             functionName:functionName
                                                             existingName:specifierName
                                                            callerAddress:callerAddress];

    if (resolved.name.length && ![resolved.name hasPrefix:@"unknown"]) {
        return resolved.name;
    }

    // Final safety fallback (should rarely be reached)
    if (specifierName.length && ![specifierName isEqualToString:@"unknown"]) {
        return specifierName;
    }
    return [NSString stringWithFormat:@"unknown 0x%016llx", specifier];
}

+ (void)recordInternalUseSpecifier:(unsigned long long)specifier
                      functionName:(NSString *)functionName
                     specifierName:(NSString *)specifierName
                      defaultValue:(BOOL)defaultValue
                       resultValue:(BOOL)resultValue
                       forcedValue:(BOOL)forcedValue
                     callerAddress:(void *)callerAddress {

    if (!functionName.length) functionName = @"InternalUse";

    NSString *resolvedName = SCIResolvedSpecifierName(specifierName, specifier, functionName, callerAddress);
    NSString *caller = SCICallerDescription(callerAddress);  // keep existing helper
    NSString *key = [NSString stringWithFormat:@"%@:%016llx", functionName, specifier];

    dispatch_barrier_async(internalUseQueue(), ^{
        if (!gInternalUseObs) gInternalUseObs = [NSMutableDictionary dictionary];
        SCIExpInternalUseObservation *o = gInternalUseObs[key];
        if (!o) {
            o = [SCIExpInternalUseObservation new];
            o.functionName = functionName;
            o.specifier = specifier;
            gInternalUseObs[key] = o;
        }
        o.specifierName = resolvedName;
        o.callerDescription = caller;
        o.defaultValue = defaultValue;
        o.resultValue = resultValue;
        o.forcedValue = forcedValue;
        o.lastSeenOrder = ++gInternalUseOrder;
        o.hitCount++;
    });
}

// (rest of the file remains exactly as in the original repo)

@end