#import "SCIMobileConfigIDResolver.h"
#import "SCIMobileConfigMapping.h"
#import "SCIExpMobileConfigMapping.h"
#import "SCIExpFlags.h"
#import "SCIMachODexKitResolver.h"

static NSString *const kSCIMCIDManualPrefix = @"sci_mc_id_manual_name:";
static NSString *const kSCIMCIDRuntimePrefix = @"sci_mc_id_runtime_name:";

@implementation SCIMobileConfigIDResolution
- (NSDictionary *)dictionaryRepresentation {
    return @{
        @"brokerID": self.brokerID ?: @"",
        @"rawValue": self.rawHex ?: @"",
        @"normalizedValue": self.normalizedHex ?: @"",
        @"title": self.title ?: @"",
        @"resolvedName": self.resolvedName ?: @"",
        @"resolvedDetail": self.resolvedDetail ?: @"",
        @"source": self.source ?: @"",
        @"tag": self.tagHex ?: @"",
        @"family": self.familyHex ?: @"",
        @"param": self.paramHex ?: @"",
        @"resolved": @(self.resolved),
        @"runtimePointerLike": @(self.runtimePointerLike)
    };
}
@end

@implementation SCIMobileConfigIDResolver

+ (NSString *)hexForValue:(unsigned long long)value { return [NSString stringWithFormat:@"%016llx", value]; }

+ (unsigned long long)normalizedSpecifierValue:(unsigned long long)value {
    unsigned long long tag = (value >> 56) & 0xffULL;
    if (tag == 0x20ULL || tag == 0x21ULL || tag == 0x24ULL) return value & 0x00ffffffffffffffULL;
    return value;
}

+ (NSString *)storeKeyForPrefix:(NSString *)prefix brokerID:(NSString *)brokerID value:(unsigned long long)value {
    return [NSString stringWithFormat:@"%@%@:%@", prefix ?: @"", brokerID.length ? brokerID : @"ig", [self hexForValue:[self normalizedSpecifierValue:value]]];
}

+ (NSString *)manualLabelForBrokerID:(NSString *)brokerID value:(unsigned long long)value {
    id v = [[NSUserDefaults standardUserDefaults] objectForKey:[self storeKeyForPrefix:kSCIMCIDManualPrefix brokerID:brokerID value:value]];
    return [v isKindOfClass:NSString.class] && [(NSString *)v length] ? v : nil;
}

+ (void)setManualLabel:(NSString *)label brokerID:(NSString *)brokerID value:(unsigned long long)value {
    NSString *key = [self storeKeyForPrefix:kSCIMCIDManualPrefix brokerID:brokerID value:value];
    if (label.length) [[NSUserDefaults standardUserDefaults] setObject:label forKey:key];
    else [[NSUserDefaults standardUserDefaults] removeObjectForKey:key];
}

+ (NSDictionary *)runtimeEntryForBrokerID:(NSString *)brokerID value:(unsigned long long)value {
    NSUserDefaults *ud = [NSUserDefaults standardUserDefaults];
    NSArray<NSString *> *keys = @[
        [self storeKeyForPrefix:kSCIMCIDRuntimePrefix brokerID:brokerID value:value],
        [self storeKeyForPrefix:kSCIMCIDRuntimePrefix brokerID:@"ig" value:value],
        [self storeKeyForPrefix:kSCIMCIDRuntimePrefix brokerID:@"igsl" value:value]
    ];
    for (NSString *key in keys) {
        id v = [ud objectForKey:key];
        if ([v isKindOfClass:NSDictionary.class]) return v;
        if ([v isKindOfClass:NSString.class] && [(NSString *)v length]) return @{@"name": v, @"source": @"runtime"};
    }
    return nil;
}

+ (void)noteResolvedName:(NSString *)name detail:(NSString *)detail brokerID:(NSString *)brokerID value:(unsigned long long)value source:(NSString *)source {
    if (!name.length || !value) return;
    NSString *key = [self storeKeyForPrefix:kSCIMCIDRuntimePrefix brokerID:brokerID value:value];
    [[NSUserDefaults standardUserDefaults] setObject:@{
        @"name": name ?: @"",
        @"detail": detail ?: @"",
        @"source": source.length ? source : @"runtime",
        @"raw": [self hexForValue:value],
        @"normalized": [self hexForValue:[self normalizedSpecifierValue:value]],
        @"ts": @([[NSDate date] timeIntervalSince1970])
    } forKey:key];
}

+ (NSString *)knownAnchorNameForValue:(unsigned long long)value {
    unsigned long long n = [self normalizedSpecifierValue:value];
    switch (n) {
        case 0x0081030f00000a95ULL: return @"ig_is_employee";
        case 0x0081030f00010a96ULL: return @"ig_is_employee";
        case 0x008100b200000161ULL: return @"ig_is_employee_or_test_user";
        default: return nil;
    }
}

+ (BOOL)isSpecifierBroker:(NSString *)brokerID {
    NSString *b = brokerID.lowercaseString ?: @"";
    return [b isEqualToString:@"ig"] || [b isEqualToString:@"igsl"] || [b isEqualToString:@"mci"] || [b isEqualToString:@"mcic"] || [b isEqualToString:@"mcie"] || [b isEqualToString:@"meta"] || [b isEqualToString:@"metanx"] || [b isEqualToString:@"msgc"];
}

+ (BOOL)isPointerLikeGateForBrokerID:(NSString *)brokerID value:(unsigned long long)value {
    if ([self isSpecifierBroker:brokerID]) return NO;
    return value >= 0x100000000ULL;
}

+ (NSString *)mappedNameForValue:(unsigned long long)value source:(NSString **)sourceOut {
    unsigned long long n = [self normalizedSpecifierValue:value];
    NSString *mapped = nil;

    mapped = [self knownAnchorNameForValue:n];
    if (mapped.length) { if (sourceOut) *sourceOut = @"known-anchor"; return mapped; }

    mapped = [SCIMobileConfigMapping resolvedNameForParamID:n];
    if (mapped.length) { if (sourceOut) *sourceOut = [SCIMobileConfigMapping sourceForParamID:n] ?: @"id_name_mapping"; return mapped; }

    mapped = [SCIMobileConfigMapping resolvedNameForParamID:value];
    if (mapped.length) { if (sourceOut) *sourceOut = [SCIMobileConfigMapping sourceForParamID:value] ?: @"id_name_mapping-raw"; return mapped; }

    mapped = [SCIExpMobileConfigMapping resolvedNameForSpecifier:n];
    if (mapped.length) { if (sourceOut) *sourceOut = @"SCIExpMobileConfigMapping"; return mapped; }

    mapped = [SCIExpMobileConfigMapping resolvedNameForSpecifier:value];
    if (mapped.length) { if (sourceOut) *sourceOut = @"SCIExpMobileConfigMapping-raw"; return mapped; }

    // DexKit 2.0: resolver-only path. This does not install hooks, does not patch C broker,
    // and does not change startup timing. It only asks the Mach-O index for names that were
    // recovered from real in-memory MobileConfig data tables.
    NSDictionary<NSNumber *, NSString *> *dexNames = [[SCIMachODexKitResolver sharedResolver] allKnownSpecifierNames];
    NSString *dexName = dexNames[@(n)];
    if (!dexName.length && value != n) dexName = dexNames[@(value)];
    if (dexName.length &&
        ![dexName isEqualToString:@"unknown"] &&
        ![dexName hasPrefix:@"unknown 0x"] &&
        ![dexName hasPrefix:@"callsite "] &&
        ![dexName hasPrefix:@"spec_0x"]) {
        if (sourceOut) *sourceOut = @"SCIMachODexKitResolver";
        return dexName;
    }

    for (SCIExpMCObservation *obs in [SCIExpFlags allMCObservations] ?: @[]) {
        if ([self normalizedSpecifierValue:obs.paramID] != n) continue;
        if (obs.resolvedName.length) { if (sourceOut) *sourceOut = obs.source.length ? obs.source : @"runtime-mc-observation"; return obs.resolvedName; }
        if (obs.lastDefault.length) {
            NSRange marker = [obs.lastDefault rangeOfString:@"name="];
            if (marker.location != NSNotFound) {
                NSString *tail = [obs.lastDefault substringFromIndex:marker.location + marker.length];
                NSRange end = [tail rangeOfString:@" ·"];
                NSString *candidate = end.location == NSNotFound ? tail : [tail substringToIndex:end.location];
                if (candidate.length && ![candidate isEqualToString:@"(null)"]) { if (sourceOut) *sourceOut = @"runtime-mc-detail"; return candidate; }
            }
        }
    }

    for (SCIExpInternalUseObservation *obs in [SCIExpFlags allInternalUseObservations] ?: @[]) {
        if ([self normalizedSpecifierValue:obs.specifier] != n) continue;
        NSString *candidate = obs.specifierName;
        if (candidate.length && ![candidate isEqualToString:@"unknown"] && ![candidate hasPrefix:@"unknown 0x"] && ![candidate hasPrefix:@"callsite "]) {
            if (sourceOut) *sourceOut = @"runtime-internaluse";
            return candidate;
        }
    }

    if (sourceOut) *sourceOut = @"decoded-id";
    return nil;
}

+ (SCIMobileConfigIDResolution *)resolutionForBrokerID:(NSString *)brokerID value:(unsigned long long)value {
    SCIMobileConfigIDResolution *r = [SCIMobileConfigIDResolution new];
    r.brokerID = brokerID.length ? brokerID : @"ig";
    r.rawValue = value;
    r.normalizedValue = [self normalizedSpecifierValue:value];
    r.rawHex = [self hexForValue:value];
    r.normalizedHex = [self hexForValue:r.normalizedValue];
    r.tagHex = [NSString stringWithFormat:@"%02llx", (value >> 56) & 0xffULL];
    r.familyHex = [NSString stringWithFormat:@"%06llx", (r.normalizedValue >> 32) & 0x00ffffffULL];
    r.paramHex = [NSString stringWithFormat:@"%08llx", r.normalizedValue & 0xffffffffULL];
    r.title = [NSString stringWithFormat:@"0x%@", r.rawHex];
    r.source = @"decoded-id";
    r.resolvedDetail = [NSString stringWithFormat:@"tag=0x%@ · family=0x%@ · param=0x%@ · normalized=0x%@", r.tagHex, r.familyHex, r.paramHex, r.normalizedHex];
    r.runtimePointerLike = [self isPointerLikeGateForBrokerID:r.brokerID value:value];

    NSString *manual = [self manualLabelForBrokerID:r.brokerID value:value];
    if (manual.length) {
        r.title = manual; r.resolvedName = manual; r.source = @"manual"; r.resolved = YES;
        r.resolvedDetail = [NSString stringWithFormat:@"manual label · raw=0x%@ · normalized=0x%@", r.rawHex, r.normalizedHex];
        return r;
    }

    NSDictionary *runtime = [self runtimeEntryForBrokerID:r.brokerID value:value];
    NSString *runtimeName = [runtime[@"name"] isKindOfClass:NSString.class] ? runtime[@"name"] : nil;
    if (runtimeName.length) {
        r.title = runtimeName; r.resolvedName = runtimeName; r.source = [runtime[@"source"] isKindOfClass:NSString.class] ? runtime[@"source"] : @"runtime"; r.resolved = YES;
        NSString *detail = [runtime[@"detail"] isKindOfClass:NSString.class] ? runtime[@"detail"] : nil;
        r.resolvedDetail = detail.length ? detail : [NSString stringWithFormat:@"runtime mapping · raw=0x%@ · normalized=0x%@", r.rawHex, r.normalizedHex];
        return r;
    }

    NSString *source = nil;
    NSString *mapped = [self mappedNameForValue:value source:&source];
    if (mapped.length) {
        r.title = mapped; r.resolvedName = mapped; r.source = source.length ? source : @"mapping"; r.resolved = YES;
        r.resolvedDetail = [NSString stringWithFormat:@"%@ · raw=0x%@ · normalized=0x%@ · family=0x%@ · param=0x%@", r.source, r.rawHex, r.normalizedHex, r.familyHex, r.paramHex];
        return r;
    }

    if (r.runtimePointerLike) {
        r.title = [NSString stringWithFormat:@"runtime gate token 0x%@", r.rawHex];
        r.source = @"runtime-token";
        r.resolvedDetail = @"EasyGating value looks like a runtime pointer/token, not a stable MobileConfig specifier. Use manual label after correlating callsite/context.";
        return r;
    }

    return r;
}

+ (NSDictionary *)resolvedDictionaryForBrokerID:(NSString *)brokerID value:(unsigned long long)value {
    return [[self resolutionForBrokerID:brokerID value:value] dictionaryRepresentation];
}

+ (NSString *)displayTitleForBrokerID:(NSString *)brokerID value:(unsigned long long)value {
    return [self resolutionForBrokerID:brokerID value:value].title ?: @"";
}

+ (NSString *)detailLineForBrokerID:(NSString *)brokerID value:(unsigned long long)value {
    SCIMobileConfigIDResolution *r = [self resolutionForBrokerID:brokerID value:value];
    return [NSString stringWithFormat:@"%@ · %@", r.source ?: @"unknown", r.resolvedDetail ?: @""];
}

+ (NSString *)mappingStatusLine {
    return [NSString stringWithFormat:@"Unified resolver · %@ · expMap=%@", [SCIMobileConfigMapping mappingStatusLine] ?: @"id_name_mapping unavailable", [SCIExpMobileConfigMapping mappingSourceDescription] ?: @"unknown"];
}

@end
