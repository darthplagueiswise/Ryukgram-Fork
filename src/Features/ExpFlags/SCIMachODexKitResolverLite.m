#import "SCIMachODexKitResolver.h"
#import "SCIExpMobileConfigMapping.h"

@implementation SCIMachODexKitResolvedName
@end

@implementation SCIMachODexKitResolver

+ (instancetype)sharedResolver {
    static SCIMachODexKitResolver *resolver;
    static dispatch_once_t once;
    dispatch_once(&once, ^{ resolver = [SCIMachODexKitResolver new]; });
    return resolver;
}

- (SCIMachODexKitResolvedName *)makeResult:(NSString *)name source:(NSString *)source confidence:(NSString *)confidence specifier:(unsigned long long)specifier {
    SCIMachODexKitResolvedName *r = [SCIMachODexKitResolvedName new];
    r.name = name.length ? name : @"unknown";
    r.source = source.length ? source : @"unknown";
    r.confidence = confidence.length ? confidence : @"low";
    r.specifier = specifier;
    return r;
}

- (SCIMachODexKitResolvedName *)resolvedNameForSpecifier:(unsigned long long)specifier
                                            functionName:(NSString *)functionName
                                            existingName:(NSString *)existingName
                                           callerAddress:(void *)callerAddress {
    (void)functionName;
    (void)callerAddress;

    if (existingName.length && ![existingName isEqualToString:@"unknown"] && ![existingName hasPrefix:@"callsite "] && ![existingName hasPrefix:@"spec_0x"]) {
        return [self makeResult:existingName source:@"provided" confidence:@"exact" specifier:specifier];
    }

    NSString *mapped = [SCIExpMobileConfigMapping resolvedNameForSpecifier:specifier];
    if (mapped.length) return [self makeResult:mapped source:@"igios-schema-json" confidence:@"exact" specifier:specifier];

    return [self makeResult:[NSString stringWithFormat:@"unknown 0x%016llx", specifier] source:@"raw" confidence:@"low" specifier:specifier];
}

- (NSDictionary<NSNumber *, NSString *> *)allKnownSpecifierNames { return @{}; }
- (NSArray<NSString *> *)reportLines { return @[@"[MachoDex] disabled: using igios schema JSON import cache"]; }
- (void)rebuildIndex { [SCIExpMobileConfigMapping reloadMapping]; }

@end
