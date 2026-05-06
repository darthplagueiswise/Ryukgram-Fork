#import "SCIDexKitNameResolver.h"
#import "SCIMobileConfigMapping.h"
#import "SCIExpMobileConfigMapping.h"
#import "SCIExpFlags.h"
#import <objc/message.h>

static NSString * const kSCIDexKitNameManualPrefix = @"dexkit.name.manual:";
static NSString * const kSCIDexKitNameRuntimePrefix = @"dexkit.name.runtime:";
static NSString * const kSCIDexKitAliasRuntimePrefix = @"dexkit.alias.runtime:";

@implementation SCIDexKitResolvedName
- (NSDictionary *)dictionaryRepresentation {
    return @{
        @"title": self.title ?: @"",
        @"name": self.name ?: @"",
        @"detail": self.detail ?: @"",
        @"source": self.source ?: @"",
        @"rawKey": self.rawKey ?: @"",
        @"normalizedKey": self.normalizedKey ?: @"",
        @"family": self.family ?: @"",
        @"param": self.param ?: @"",
        @"tag": self.tag ?: @"",
        @"confidence": @(self.confidence),
        @"manual": @(self.manual),
        @"runtimeObserved": @(self.runtimeObserved),
        @"pointerLike": @(self.pointerLike),
        @"callerImage": self.callerImage ?: @"",
        @"callerSymbol": self.callerSymbol ?: @"",
        @"callerAddress": self.callerAddress ?: @"",
    };
}
@end

@implementation SCIDexKitNameResolver

+ (NSString *)hexForValue:(uint64_t)value { return [NSString stringWithFormat:@"%016llx", (unsigned long long)value]; }

+ (uint64_t)normalizedSpecifierValue:(uint64_t)value {
    uint64_t tag = (value >> 56) & 0xffULL;
    if (tag == 0x20ULL || tag == 0x21ULL || tag == 0x24ULL) return value & 0x00ffffffffffffffULL;
    return value;
}

+ (NSString *)manualKeyForIdentity:(NSString *)identity { return [kSCIDexKitNameManualPrefix stringByAppendingString:identity ?: @""]; }
+ (NSString *)runtimeKeyForSpecifier:(uint64_t)specifier { return [kSCIDexKitNameRuntimePrefix stringByAppendingString:[self hexForValue:[self normalizedSpecifierValue:specifier]]]; }
+ (NSString *)aliasKeyForSpecifier:(uint64_t)specifier { return [kSCIDexKitAliasRuntimePrefix stringByAppendingString:[self hexForValue:specifier]]; }

+ (NSString *)manualNameForIdentity:(NSString *)identity {
    id v = [[NSUserDefaults standardUserDefaults] objectForKey:[self manualKeyForIdentity:identity]];
    return [v isKindOfClass:NSString.class] ? v : nil;
}

+ (void)setManualName:(NSString *)name forIdentity:(NSString *)identity {
    if (!identity.length) return;
    NSUserDefaults *ud = [NSUserDefaults standardUserDefaults];
    if (name.length) [ud setObject:name forKey:[self manualKeyForIdentity:identity]];
    else [ud removeObjectForKey:[self manualKeyForIdentity:identity]];
}

+ (uint64_t)aliasTargetForSpecifier:(uint64_t)specifier {
    id v = [[NSUserDefaults standardUserDefaults] objectForKey:[self aliasKeyForSpecifier:specifier]];
    if (![v isKindOfClass:NSDictionary.class]) return 0;
    NSString *hex = ((NSDictionary *)v)[@"to"];
    if (![hex isKindOfClass:NSString.class]) return 0;
    unsigned long long out = 0;
    NSScanner *scanner = [NSScanner scannerWithString:hex];
    return [scanner scanHexLongLong:&out] ? (uint64_t)out : 0;
}

+ (NSArray<NSNumber *> *)lookupSpecifiersForValue:(uint64_t)value {
    NSMutableOrderedSet<NSNumber *> *set = [NSMutableOrderedSet orderedSet];
    if (value) [set addObject:@(value)];
    uint64_t normalized = [self normalizedSpecifierValue:value];
    if (normalized && normalized != value) [set addObject:@(normalized)];
    uint64_t alias = [self aliasTargetForSpecifier:value];
    if (alias) {
        [set addObject:@(alias)];
        uint64_t normalizedAlias = [self normalizedSpecifierValue:alias];
        if (normalizedAlias && normalizedAlias != alias) [set addObject:@(normalizedAlias)];
    }
    return set.array;
}

+ (NSDictionary *)runtimeEntryForSpecifier:(uint64_t)specifier {
    for (NSNumber *candidate in [self lookupSpecifiersForValue:specifier]) {
        id v = [[NSUserDefaults standardUserDefaults] objectForKey:[self runtimeKeyForSpecifier:candidate.unsignedLongLongValue]];
        if ([v isKindOfClass:NSDictionary.class]) return v;
    }
    return nil;
}

+ (NSString *)knownAnchorNameForSpecifier:(uint64_t)specifier {
    for (NSNumber *candidate in [self lookupSpecifiersForValue:specifier]) {
        uint64_t n = [self normalizedSpecifierValue:candidate.unsignedLongLongValue];
        switch (n) {
            case 0x0081030f00000a95ULL: return @"ig_is_employee";
            case 0x0081030f00010a96ULL: return @"ig_is_employee";
            case 0x008100b200000161ULL: return @"ig_is_employee_or_test_user";
            default: break;
        }
    }
    return nil;
}

+ (NSDictionary *)dynamicEntryFromObject:(id)obj {
    if (!obj) return nil;
    id rawSpec = nil;
    id rawName = nil;
    id rawSource = nil;
    id rawSuggested = nil;
    @try { rawSpec = [obj valueForKey:@"specifier"]; } @catch (__unused NSException *e) {}
    @try { rawName = [obj valueForKey:@"name"]; } @catch (__unused NSException *e) {}
    @try { rawSource = [obj valueForKey:@"source"]; } @catch (__unused NSException *e) {}
    @try { rawSuggested = [obj valueForKey:@"suggestedValue"]; } @catch (__unused NSException *e) {}
    NSString *name = [rawName isKindOfClass:NSString.class] ? rawName : nil;
    if (!name.length) return nil;
    uint64_t specifier = 0;
    if ([rawSpec respondsToSelector:@selector(unsignedLongLongValue)]) specifier = (uint64_t)[rawSpec unsignedLongLongValue];
    NSString *source = [rawSource isKindOfClass:NSString.class] ? rawSource : @"SCIResolverScanner";
    BOOL suggested = [rawSuggested respondsToSelector:@selector(boolValue)] ? [rawSuggested boolValue] : NO;
    return @{ @"specifier": @(specifier), @"name": name, @"source": source ?: @"", @"suggestedValue": @(suggested) };
}

+ (NSArray *)optionalSCIResolverScannerEntries {
    Class scannerClass = NSClassFromString(@"SCIResolverScanner");
    SEL sel = NSSelectorFromString(@"allKnownSpecifierEntries");
    if (!scannerClass || ![scannerClass respondsToSelector:sel]) return @[];
    NSArray *entries = nil;
    @try {
        entries = ((NSArray *(*)(id, SEL))objc_msgSend)(scannerClass, sel);
    } @catch (__unused NSException *e) {
        entries = nil;
    }
    return [entries isKindOfClass:NSArray.class] ? entries : @[];
}

+ (NSDictionary *)resolverEntryForSpecifier:(uint64_t)value {
    NSArray<NSNumber *> *candidates = [self lookupSpecifiersForValue:value];

    // Runtime observations from SCIExpFlags remain first because they are produced by live execution.
    for (SCIExpInternalUseObservation *o in [SCIExpFlags allInternalUseObservations] ?: @[]) {
        if (!o.specifierName.length) continue;
        uint64_t observed = (uint64_t)o.specifier;
        uint64_t normalizedObserved = [self normalizedSpecifierValue:observed];
        for (NSNumber *candidate in candidates) {
            uint64_t candidateValue = candidate.unsignedLongLongValue;
            if (observed == candidateValue || normalizedObserved == [self normalizedSpecifierValue:candidateValue]) {
                return @{ @"specifier": @(observed), @"name": o.specifierName ?: @"", @"source": (o.functionName.length ? o.functionName : @"SCIExpFlags runtime observation"), @"suggestedValue": @(o.resultValue) };
            }
        }
    }

    // SCIResolverScanner is optional diagnostic/static provider only. Do not import it or depend on it at link time.
    for (id obj in [self optionalSCIResolverScannerEntries]) {
        NSDictionary *entry = [self dynamicEntryFromObject:obj];
        if (!entry[@"name"]) continue;
        uint64_t entrySpecifier = (uint64_t)[entry[@"specifier"] unsignedLongLongValue];
        uint64_t normalizedEntry = [self normalizedSpecifierValue:entrySpecifier];
        for (NSNumber *candidate in candidates) {
            uint64_t candidateValue = candidate.unsignedLongLongValue;
            if (entrySpecifier == candidateValue || normalizedEntry == [self normalizedSpecifierValue:candidateValue]) return entry;
        }
    }
    return nil;
}

+ (BOOL)isPointerLikeValue:(uint64_t)value brokerID:(NSString *)brokerID {
    if ([brokerID isEqualToString:@"egi"] || [brokerID isEqualToString:@"ega"]) return value >= 0x100000000ULL;
    if ([brokerID hasPrefix:@"eg"] && value >= 0x100000000ULL) return YES;
    return NO;
}

+ (void)fillCommonFields:(SCIDexKitResolvedName *)r specifier:(uint64_t)value identity:(NSString *)identity {
    uint64_t normalized = [self normalizedSpecifierValue:value];
    r.rawKey = identity ?: [self hexForValue:value];
    r.normalizedKey = [self hexForValue:normalized];
    r.tag = [NSString stringWithFormat:@"%02llx", (unsigned long long)((value >> 56) & 0xffULL)];
    r.family = [NSString stringWithFormat:@"%06llx", (unsigned long long)((normalized >> 32) & 0x00ffffffULL)];
    r.param = [NSString stringWithFormat:@"%08llx", (unsigned long long)(normalized & 0xffffffffULL)];
}

+ (NSString *)mappedNameForSpecifier:(uint64_t)value source:(NSString **)sourceOut {
    for (NSNumber *candidate in [self lookupSpecifiersForValue:value]) {
        uint64_t normalized = [self normalizedSpecifierValue:candidate.unsignedLongLongValue];
        NSString *mapped = [SCIMobileConfigMapping resolvedNameForParamID:normalized];
        if (mapped.length) {
            if (sourceOut) {
                NSString *source = [SCIMobileConfigMapping sourceForParamID:normalized];
                *sourceOut = source.length ? source : @"id_name_mapping";
            }
            return mapped;
        }
        NSString *expMapped = [SCIExpMobileConfigMapping resolvedNameForSpecifier:normalized];
        if (expMapped.length) { if (sourceOut) *sourceOut = @"schema-mapping"; return expMapped; }
    }
    return nil;
}

+ (void)applyRuntimeCallerFromEntry:(NSDictionary *)runtime toResolvedName:(SCIDexKitResolvedName *)resolved {
    if (![runtime isKindOfClass:NSDictionary.class] || !resolved) return;
    NSString *image = [runtime[@"callerImage"] isKindOfClass:NSString.class] ? runtime[@"callerImage"] : @"";
    NSString *symbol = [runtime[@"callerSymbol"] isKindOfClass:NSString.class] ? runtime[@"callerSymbol"] : @"";
    NSString *address = [runtime[@"callerAddress"] isKindOfClass:NSString.class] ? runtime[@"callerAddress"] : @"";
    resolved.callerImage = image ?: @"";
    resolved.callerSymbol = symbol ?: @"";
    resolved.callerAddress = address ?: @"";
}

+ (NSString *)usefulRuntimeCallerFromEntry:(NSDictionary *)runtime {
    NSString *sym = [runtime[@"callerSymbol"] isKindOfClass:NSString.class] ? runtime[@"callerSymbol"] : nil;
    if (!sym.length) return nil;
    NSArray<NSString *> *bad = @[@"SCI", @"objc_msgSend", @"MSHook", @"H1", @"H2", @"H3", @"H4", @"Rec", @"SCIDexKitNameResolver"];
    for (NSString *b in bad) if ([sym containsString:b]) return nil;
    return sym;
}

+ (SCIDexKitResolvedName *)resolveBrokerID:(NSString *)brokerID value:(uint64_t)value {
    NSString *bid = brokerID ?: @"";
    NSString *rawHex = [self hexForValue:value];
    NSString *identity = [NSString stringWithFormat:@"mcbr:%@:%@", bid, rawHex];
    SCIDexKitResolvedName *r = [SCIDexKitResolvedName new];
    [self fillCommonFields:r specifier:value identity:identity];
    r.pointerLike = [self isPointerLikeValue:value brokerID:bid];

    NSString *manual = [self manualNameForIdentity:identity];
    if (manual.length) { r.title = manual; r.name = manual; r.detail = [NSString stringWithFormat:@"manual label for %@", identity]; r.source = @"manual"; r.confidence = SCIDexKitNameConfidenceExact; r.manual = YES; return r; }

    NSDictionary *runtime = [self runtimeEntryForSpecifier:value];
    [self applyRuntimeCallerFromEntry:runtime toResolvedName:r];
    NSString *runtimeName = [runtime[@"name"] isKindOfClass:NSString.class] ? runtime[@"name"] : nil;
    NSString *runtimeDetail = [runtime[@"detail"] isKindOfClass:NSString.class] ? runtime[@"detail"] : nil;
    NSString *runtimeSource = [runtime[@"source"] isKindOfClass:NSString.class] ? runtime[@"source"] : nil;
    NSString *callerSymbol = [self usefulRuntimeCallerFromEntry:runtime ?: @{}];

    if (runtimeName.length && ![runtimeName hasPrefix:@"0x"]) {
        r.title = runtimeName; r.name = runtimeName; r.detail = runtimeDetail ?: @"runtime MobileConfig observation"; r.source = runtimeSource ?: @"runtime"; r.confidence = SCIDexKitNameConfidenceHigh; r.runtimeObserved = YES; return r;
    }

    NSString *anchor = [self knownAnchorNameForSpecifier:value];
    if (anchor.length) { r.title = anchor; r.name = anchor; r.detail = [NSString stringWithFormat:@"known anchor · 0x%@", r.normalizedKey]; r.source = @"known-anchor"; r.confidence = SCIDexKitNameConfidenceExact; r.runtimeObserved = runtime != nil; return r; }

    if (!r.pointerLike) {
        NSString *mappedSource = nil;
        NSString *mapped = [self mappedNameForSpecifier:value source:&mappedSource];
        if (mapped.length) { r.title = mapped; r.name = mapped; r.detail = [NSString stringWithFormat:@"%@ · 0x%@", mappedSource ?: @"mapping", r.normalizedKey]; r.source = mappedSource ?: @"mapping"; r.confidence = SCIDexKitNameConfidenceExact; r.runtimeObserved = runtime != nil; return r; }

        NSDictionary *entry = [self resolverEntryForSpecifier:value];
        NSString *entryName = [entry[@"name"] isKindOfClass:NSString.class] ? entry[@"name"] : nil;
        if (entryName.length) {
            NSString *entrySource = [entry[@"source"] isKindOfClass:NSString.class] ? entry[@"source"] : @"SCIResolverScanner";
            BOOL suggested = [entry[@"suggestedValue"] respondsToSelector:@selector(boolValue)] ? [entry[@"suggestedValue"] boolValue] : NO;
            r.title = entryName; r.name = entryName;
            r.detail = [NSString stringWithFormat:@"%@ · suggested=%@ · 0x%@", entrySource ?: @"SCIResolverScanner", suggested ? @"YES" : @"NO", r.normalizedKey];
            if (runtimeDetail.length) r.detail = [r.detail stringByAppendingFormat:@" · %@", runtimeDetail];
            r.source = entrySource.length ? entrySource : @"SCIResolverScanner"; r.confidence = SCIDexKitNameConfidenceExact; r.runtimeObserved = runtime != nil; return r;
        }
    }

    if (callerSymbol.length) {
        r.title = callerSymbol;
        r.name = callerSymbol;
        r.detail = runtimeDetail.length ? runtimeDetail : [NSString stringWithFormat:@"runtime callsite context · 0x%@", r.normalizedKey];
        r.source = @"runtime-callsite";
        r.confidence = SCIDexKitNameConfidenceMedium;
        r.runtimeObserved = YES;
        return r;
    }

    if (r.pointerLike) { r.title = [NSString stringWithFormat:@"runtime gate token 0x%@", rawHex]; r.name = @""; r.detail = @"not a stable feature id; use ObjC/context mapping or manual label"; r.source = @"runtime-token"; r.confidence = SCIDexKitNameConfidenceLow; r.runtimeObserved = runtime != nil; return r; }

    r.title = [NSString stringWithFormat:@"0x%@", rawHex]; r.name = @"";
    NSString *base = [NSString stringWithFormat:@"unresolved · tag=0x%@ · family=0x%@ · param=0x%@ · normalized=0x%@", r.tag, r.family, r.param, r.normalizedKey];
    r.detail = runtimeDetail.length ? [base stringByAppendingFormat:@" · %@", runtimeDetail] : base;
    r.source = runtime ? (runtimeSource.length ? runtimeSource : @"runtime-unresolved") : @"decoded-id";
    r.confidence = SCIDexKitNameConfidenceNone;
    r.runtimeObserved = runtime != nil;
    return r;
}

+ (NSDictionary *)resolvedDictionaryForBrokerID:(NSString *)brokerID value:(uint64_t)value { return [[self resolveBrokerID:brokerID value:value] dictionaryRepresentation]; }

+ (void)noteMobileConfigBoolReadWithClassName:(NSString *)className selector:(NSString *)selectorName specifier:(uint64_t)specifier defaultValue:(BOOL)defaultValue originalValue:(BOOL)originalValue finalValue:(BOOL)finalValue source:(NSString *)source {
    [self noteMobileConfigBoolReadWithClassName:className selector:selectorName specifier:specifier defaultValue:defaultValue originalValue:originalValue finalValue:finalValue source:source callerImage:nil callerSymbol:nil callerAddress:0];
}

+ (void)noteMobileConfigBoolReadWithClassName:(NSString *)className selector:(NSString *)selectorName specifier:(uint64_t)specifier defaultValue:(BOOL)defaultValue originalValue:(BOOL)originalValue finalValue:(BOOL)finalValue source:(NSString *)source callerImage:(NSString *)callerImage callerSymbol:(NSString *)callerSymbol callerAddress:(uint64_t)callerAddress {
    uint64_t normalized = [self normalizedSpecifierValue:specifier];
    NSString *mappedSource = nil;
    NSString *mapped = [self mappedNameForSpecifier:specifier source:&mappedSource];
    if (!mapped.length) mapped = [self knownAnchorNameForSpecifier:specifier];
    if (!mapped.length) {
        NSDictionary *entry = [self resolverEntryForSpecifier:specifier];
        NSString *entryName = [entry[@"name"] isKindOfClass:NSString.class] ? entry[@"name"] : nil;
        if (entryName.length) mapped = entryName;
    }
    NSString *usefulCaller = [self usefulRuntimeCallerFromEntry:@{@"callerSymbol": callerSymbol ?: @""}];
    NSString *name = mapped.length ? mapped : (usefulCaller.length ? usefulCaller : [NSString stringWithFormat:@"0x%@", [self hexForValue:normalized]]);
    NSMutableDictionary *entry = [@{
        @"name": name ?: @"",
        @"detail": [NSString stringWithFormat:@"%@ %@ · default=%@ · original=%@ · final=%@", className ?: @"", selectorName ?: @"", defaultValue ? @"ON" : @"OFF", originalValue ? @"ON" : @"OFF", finalValue ? @"ON" : @"OFF"],
        @"source": mapped.length ? (mappedSource ?: @"objc-mobileconfig") : (usefulCaller.length ? @"runtime-callsite" : (source.length ? source : @"objc-mobileconfig")),
        @"className": className ?: @"",
        @"selector": selectorName ?: @"",
        @"raw": [self hexForValue:specifier],
        @"normalized": [self hexForValue:normalized],
        @"default": @(defaultValue),
        @"original": @(originalValue),
        @"final": @(finalValue),
        @"ts": @([[NSDate date] timeIntervalSince1970])
    } mutableCopy];
    if (callerImage.length) entry[@"callerImage"] = callerImage;
    if (callerSymbol.length) entry[@"callerSymbol"] = callerSymbol;
    if (callerAddress) entry[@"callerAddress"] = [NSString stringWithFormat:@"0x%016llx", (unsigned long long)callerAddress];
    [[NSUserDefaults standardUserDefaults] setObject:entry forKey:[self runtimeKeyForSpecifier:specifier]];
    [[NSUserDefaults standardUserDefaults] setObject:entry forKey:[self runtimeKeyForSpecifier:normalized]];
}

+ (void)noteAliasFromSpecifier:(uint64_t)rawSpecifier toSpecifier:(uint64_t)translatedSpecifier source:(NSString *)source {
    if (!rawSpecifier || !translatedSpecifier || rawSpecifier == translatedSpecifier) return;
    NSDictionary *entry = @{ @"to": [self hexForValue:translatedSpecifier], @"from": [self hexForValue:rawSpecifier], @"source": source.length ? source : @"objc-mobileconfig-alias", @"ts": @([[NSDate date] timeIntervalSince1970]) };
    [[NSUserDefaults standardUserDefaults] setObject:entry forKey:[self aliasKeyForSpecifier:rawSpecifier]];
}

@end
