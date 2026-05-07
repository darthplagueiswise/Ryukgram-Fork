#import "SCIDexKitNameResolver.h"
#import "SCIMobileConfigMapping.h"
#import "SCIExpMobileConfigMapping.h"
#import "SCIExpFlags.h"
#import <objc/message.h>
#import <objc/runtime.h>

NSString * const SCIDexKitNameResolverDidUpdateNotification = @"SCIDexKitNameResolverDidUpdateNotification";
NSString * const SCIDexKitNameResolverRuntimeFeedDidUpdateNotification = @"SCIDexKitNameResolverRuntimeFeedDidUpdateNotification";

static NSString * const kSCIDexKitNameManualPrefix = @"dexkit.name.manual:";
static NSString * const kSCIDexKitNameRuntimePrefix = @"dexkit.name.runtime:";
static NSString * const kSCIDexKitRuntimeEntryPrefix = @"dexkit.runtime.entry:";
static NSString * const kSCIDexKitRuntimeIndexKey = @"dexkit.runtime.entry.idx";
static NSString * const kSCIDexKitAliasRuntimePrefix = @"dexkit.alias.runtime:";
static NSString * const kSCIDexKitAliasSourceRuntimePrefix = @"dexkit.alias.runtime.source:";

static NSString *SCIDexKitHexNoPrefix(uint64_t value) { return [NSString stringWithFormat:@"%016llx", (unsigned long long)value]; }
static NSString *SCIDexKitHex(uint64_t value) { return [NSString stringWithFormat:@"0x%016llx", (unsigned long long)value]; }
static NSString *SCIDexKitAddressHex(uint64_t value) { return value ? [NSString stringWithFormat:@"0x%llx", (unsigned long long)value] : @""; }
static NSString *SCIDexKitString(id value) { return [value isKindOfClass:NSString.class] ? (NSString *)value : @""; }
static BOOL SCIDexKitBool(id value) { return [value respondsToSelector:@selector(boolValue)] ? [value boolValue] : NO; }

static BOOL SCIDexKitParseHexString(NSString *string, uint64_t *outValue) {
    if (![string isKindOfClass:NSString.class] || string.length == 0) return NO;
    NSString *s = [string stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
    if ([s hasPrefix:@"0x"] || [s hasPrefix:@"0X"]) s = [s substringFromIndex:2];
    if (!s.length) return NO;
    unsigned long long parsed = 0;
    NSScanner *scanner = [NSScanner scannerWithString:s];
    if (![scanner scanHexLongLong:&parsed]) return NO;
    if (outValue) *outValue = (uint64_t)parsed;
    return YES;
}

static void SCIDexKitPostUpdate(BOOL runtime) {
    dispatch_async(dispatch_get_main_queue(), ^{
        if (runtime) [[NSNotificationCenter defaultCenter] postNotificationName:SCIDexKitNameResolverRuntimeFeedDidUpdateNotification object:nil];
        [[NSNotificationCenter defaultCenter] postNotificationName:SCIDexKitNameResolverDidUpdateNotification object:nil];
    });
}

static void SCIDexKitAddUniqueString(NSMutableArray<NSString *> *items, NSString *value) {
    if (value.length && ![items containsObject:value]) [items addObject:value];
}
static void SCIDexKitAddUniqueValue(NSMutableArray<NSNumber *> *items, uint64_t value) {
    NSNumber *n = @(value);
    if (![items containsObject:n]) [items addObject:n];
}

static NSString *SCIDexKitInferBrokerID(NSString *className) {
    if (![className isKindOfClass:NSString.class] || className.length == 0) return @"";
    if ([className containsString:@"Sessionless"]) return @"igsl";
    if ([className hasPrefix:@"IGMobileConfig"]) return @"ig";
    if ([className hasPrefix:@"FBMobileConfig"]) return @"fb";
    return @"";
}

static NSString *SCIDexKitFeatureLikeSelectorName(NSString *selectorName) {
    if (![selectorName isKindOfClass:NSString.class] || selectorName.length == 0) return @"";
    if ([selectorName hasPrefix:@"getBool"] || [selectorName hasPrefix:@"getInt"] || [selectorName hasPrefix:@"getDouble"] || [selectorName hasPrefix:@"getString"] || [selectorName hasPrefix:@"_get"]) return @"";
    if ([selectorName hasPrefix:@"is"] || [selectorName hasPrefix:@"should"] || [selectorName hasPrefix:@"has"] || [selectorName hasPrefix:@"can"] || [selectorName hasPrefix:@"enable"] || [selectorName hasPrefix:@"enabled"]) return selectorName;
    return @"";
}

static BOOL SCIDexKitMappingMethodLooksLikeObjectForU64(Class cls, SEL sel) {
    Method m = class_getClassMethod(cls, sel);
    if (!m || method_getNumberOfArguments(m) != 3) return NO;
    char ret[128] = {0};
    char arg[128] = {0};
    method_getReturnType(m, ret, sizeof(ret));
    method_getArgumentType(m, 2, arg, sizeof(arg));
    if (ret[0] != '@') return NO;
    NSUInteger argSize = 0;
    NSGetSizeAndAlignment(arg, &argSize, NULL);
    return argSize == sizeof(uint64_t);
}

static NSString *SCIDexKitNameFromMappingObject(id candidate) {
    if ([candidate isKindOfClass:NSString.class] && [(NSString *)candidate length] > 0) return (NSString *)candidate;
    if ([candidate isKindOfClass:NSDictionary.class]) {
        NSDictionary *d = (NSDictionary *)candidate;
        for (NSString *key in @[@"name", @"mobile_config_name", @"config_name", @"display_name", @"title", @"field_name", @"param_name", @"parameter_name", @"id_name"]) {
            id value = d[key];
            if ([value isKindOfClass:NSString.class] && [(NSString *)value length] > 0) return (NSString *)value;
        }
    }
    return nil;
}

static NSString *SCIResolveMappedNameForSingleValue(uint64_t value) {
    NSArray<NSString *> *classNames = @[@"SCIMobileConfigMapping", @"SCIExpMobileConfigMapping"];
    NSArray<NSString *> *selectorNames = @[
        @"resolvedNameForParamID:",
        @"resolvedNameForSpecifier:",
        @"nameForSpecifier:",
        @"nameForSpecifierValue:",
        @"mappedNameForSpecifier:",
        @"mappingForParamID:",
        @"nameForParamID:",
        @"nameForID:"
    ];

    for (NSString *className in classNames) {
        Class cls = NSClassFromString(className);
        if (!cls) continue;
        for (NSString *selectorName in selectorNames) {
            SEL sel = NSSelectorFromString(selectorName);
            if (![cls respondsToSelector:sel]) continue;
            if (!SCIDexKitMappingMethodLooksLikeObjectForU64(cls, sel)) continue;
            IMP imp = [cls methodForSelector:sel];
            if (!imp) continue;
            id (*fn)(id, SEL, uint64_t) = (id (*)(id, SEL, uint64_t))imp;
            NSString *name = SCIDexKitNameFromMappingObject(fn(cls, sel, value));
            if (name.length) return name;
        }
    }
    return nil;
}

static NSString *SCIResolveMappedNameForSpecifier(uint64_t value) {
    uint64_t normalized = [SCIDexKitNameResolver normalizedSpecifierValue:value];
    NSMutableArray<NSNumber *> *values = [NSMutableArray array];
    SCIDexKitAddUniqueValue(values, value);
    SCIDexKitAddUniqueValue(values, normalized);
    SCIDexKitAddUniqueValue(values, (uint64_t)((uint32_t)normalized));
    SCIDexKitAddUniqueValue(values, (uint64_t)((uint32_t)value));

    for (NSNumber *n in values) {
        NSString *mapped = SCIResolveMappedNameForSingleValue(n.unsignedLongLongValue);
        if (mapped.length) return mapped;
    }
    return nil;
}

static NSDictionary *SCIDexKitRuntimeEntryForIdentity(NSString *identity) {
    if (!identity.length) return nil;
    NSString *key = [kSCIDexKitRuntimeEntryPrefix stringByAppendingString:identity];
    id obj = [[NSUserDefaults standardUserDefaults] objectForKey:key];
    return [obj isKindOfClass:NSDictionary.class] ? (NSDictionary *)obj : nil;
}

static NSDictionary *SCIDexKitRuntimeEntryForBrokerAndValue(NSString *brokerID, uint64_t value) {
    for (NSString *identity in [SCIDexKitNameResolver identityCandidatesForBrokerID:brokerID value:value]) {
        NSDictionary *entry = SCIDexKitRuntimeEntryForIdentity(identity);
        if (entry) return entry;
    }
    return nil;
}

static NSString *SCIDexKitAliasForIdentity(NSString *identity) {
    if (!identity.length) return nil;
    NSString *key = [kSCIDexKitAliasRuntimePrefix stringByAppendingString:identity];
    id obj = [[NSUserDefaults standardUserDefaults] objectForKey:key];
    return [obj isKindOfClass:NSString.class] ? (NSString *)obj : nil;
}

static NSString *SCIDexKitAliasSourceForIdentity(NSString *identity) {
    if (!identity.length) return nil;
    NSString *key = [kSCIDexKitAliasSourceRuntimePrefix stringByAppendingString:identity];
    id obj = [[NSUserDefaults standardUserDefaults] objectForKey:key];
    return [obj isKindOfClass:NSString.class] ? (NSString *)obj : nil;
}

static NSArray<NSNumber *> *SCIDexKitCandidateValuesForBrokerAndValue(NSString *brokerID, uint64_t value) {
    NSMutableArray<NSNumber *> *values = [NSMutableArray array];
    uint64_t normalized = [SCIDexKitNameResolver normalizedSpecifierValue:value];
    SCIDexKitAddUniqueValue(values, value);
    SCIDexKitAddUniqueValue(values, normalized);

    NSArray<NSNumber *> *seed = [values copy];
    for (NSNumber *seedValue in seed) {
        for (NSString *identity in [SCIDexKitNameResolver identityCandidatesForBrokerID:brokerID value:seedValue.unsignedLongLongValue]) {
            NSString *alias = SCIDexKitAliasForIdentity(identity);
            uint64_t aliasValue = 0;
            if (SCIDexKitParseHexString(alias, &aliasValue)) {
                SCIDexKitAddUniqueValue(values, aliasValue);
                SCIDexKitAddUniqueValue(values, [SCIDexKitNameResolver normalizedSpecifierValue:aliasValue]);
            }
        }
    }
    return values;
}

static NSString *SCIDexKitRuntimeTitleFromEntry(NSDictionary *entry, uint64_t normalizedValue) {
    NSString *callerSymbol = SCIDexKitString(entry[@"callerSymbol"]);
    if (callerSymbol.length) return callerSymbol;
    NSString *className = SCIDexKitString(entry[@"className"]);
    NSString *selector = SCIDexKitString(entry[@"selector"]);
    if (className.length || selector.length) return [NSString stringWithFormat:@"%@ %@", className.length ? className : @"?", selector.length ? selector : @"?"];
    NSString *callerImage = SCIDexKitString(entry[@"callerImage"]);
    NSString *callerAddress = SCIDexKitString(entry[@"callerAddress"]);
    if (callerImage.length || callerAddress.length) return [NSString stringWithFormat:@"%@ %@", callerImage.length ? callerImage : @"?", callerAddress.length ? callerAddress : @"?"];
    return SCIDexKitHex(normalizedValue);
}

static NSString *SCIDexKitRuntimeDetailFromEntry(NSDictionary *entry) {
    NSNumber *def = [entry[@"defaultValue"] respondsToSelector:@selector(boolValue)] ? entry[@"defaultValue"] : nil;
    NSNumber *orig = [entry[@"originalValue"] respondsToSelector:@selector(boolValue)] ? entry[@"originalValue"] : nil;
    NSNumber *fin = [entry[@"finalValue"] respondsToSelector:@selector(boolValue)] ? entry[@"finalValue"] : nil;
    return [NSString stringWithFormat:@"context=%@ · selector=%@ · source=%@ · raw=%@ · normalized=%@ · caller=%@/%@/%@ · default=%@ · original=%@ · final=%@",
            SCIDexKitString(entry[@"className"]),
            SCIDexKitString(entry[@"selector"]),
            SCIDexKitString(entry[@"source"]).length ? SCIDexKitString(entry[@"source"]) : @"objc-getBool",
            SCIDexKitString(entry[@"rawHex"]),
            SCIDexKitString(entry[@"normalizedHex"]),
            SCIDexKitString(entry[@"callerImage"]),
            SCIDexKitString(entry[@"callerSymbol"]),
            SCIDexKitString(entry[@"callerAddress"]),
            def ? (def.boolValue ? @"YES" : @"NO") : @"?",
            orig ? (orig.boolValue ? @"YES" : @"NO") : @"?",
            fin ? (fin.boolValue ? @"YES" : @"NO") : @"?"];
}

static BOOL SCIDexKitLooksLikeRuntimePointerToken(NSString *brokerID, uint64_t value) {
    if (![brokerID isKindOfClass:NSString.class]) return NO;
    if (!([brokerID hasPrefix:@"eg"] || [brokerID hasPrefix:@"meta"] || [brokerID hasPrefix:@"mci"] || [brokerID hasPrefix:@"msgc"])) return NO;
    return value >= 0x0000000100000000ULL && value <= 0x00000001ffffffffULL;
}

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
        @"callerAddress": self.callerAddress ?: @""
    };
}
@end

@implementation SCIDexKitNameResolver

+ (uint64_t)normalizedSpecifierValue:(uint64_t)value {
    uint64_t topByte = value & 0xff00000000000000ULL;
    if (topByte == 0x2000000000000000ULL) return value & 0x00ffffffffffffffULL;
    return value;
}

+ (NSString *)hexForValue:(uint64_t)value { return SCIDexKitHex(value); }

+ (NSArray<NSString *> *)identityCandidatesForBrokerID:(NSString * _Nullable)brokerID value:(uint64_t)value {
    uint64_t normalized = [self normalizedSpecifierValue:value];
    NSMutableArray<NSString *> *out = [NSMutableArray array];

    NSString *rawHex = SCIDexKitHex(value);
    NSString *rawNoPrefix = SCIDexKitHexNoPrefix(value);
    NSString *normHex = SCIDexKitHex(normalized);
    NSString *normNoPrefix = SCIDexKitHexNoPrefix(normalized);

    if (brokerID.length) {
        SCIDexKitAddUniqueString(out, [NSString stringWithFormat:@"%@:%@", brokerID, rawHex]);
        SCIDexKitAddUniqueString(out, [NSString stringWithFormat:@"%@:%@", brokerID, rawNoPrefix]);
        SCIDexKitAddUniqueString(out, [NSString stringWithFormat:@"%@:%@", brokerID, normHex]);
        SCIDexKitAddUniqueString(out, [NSString stringWithFormat:@"%@:%@", brokerID, normNoPrefix]);
    }

    SCIDexKitAddUniqueString(out, rawHex);
    SCIDexKitAddUniqueString(out, rawNoPrefix);
    SCIDexKitAddUniqueString(out, normHex);
    SCIDexKitAddUniqueString(out, normNoPrefix);
    return out;
}

+ (BOOL)sourceRepresentsExactName:(NSString *)source {
    if (![source isKindOfClass:NSString.class] || source.length == 0) return NO;
    return [source isEqualToString:@"manual"] || [source isEqualToString:@"mapping"] || [source isEqualToString:@"runtime-name"];
}

+ (BOOL)sourceRepresentsRuntimeObservation:(NSString *)source {
    if (![source isKindOfClass:NSString.class] || source.length == 0) return NO;
    return [source isEqualToString:@"runtime-name"] || [source isEqualToString:@"runtime-callsite"] || [source isEqualToString:@"alias"];
}

+ (nullable NSString *)manualNameForIdentity:(NSString *)identity {
    if (!identity.length) return nil;
    NSString *key = [kSCIDexKitNameManualPrefix stringByAppendingString:identity];
    NSString *value = [[NSUserDefaults standardUserDefaults] stringForKey:key];
    return value.length ? value : nil;
}

+ (void)setManualName:(nullable NSString *)name forIdentity:(NSString *)identity {
    if (!identity.length) return;
    NSString *key = [kSCIDexKitNameManualPrefix stringByAppendingString:identity];
    if (name.length) [[NSUserDefaults standardUserDefaults] setObject:name forKey:key];
    else [[NSUserDefaults standardUserDefaults] removeObjectForKey:key];
    [[NSUserDefaults standardUserDefaults] synchronize];
    SCIDexKitPostUpdate(NO);
}

+ (SCIDexKitResolvedName *)resolveBrokerID:(NSString * _Nullable)brokerID value:(uint64_t)value {
    uint64_t normalized = [self normalizedSpecifierValue:value];
    NSArray<NSNumber *> *candidateValues = SCIDexKitCandidateValuesForBrokerAndValue(brokerID, value);
    NSDictionary *runtimeForOriginal = SCIDexKitRuntimeEntryForBrokerAndValue(brokerID, value);

    SCIDexKitResolvedName *res = [[SCIDexKitResolvedName alloc] init];
    res.rawKey = SCIDexKitHex(value);
    res.normalizedKey = SCIDexKitHex(normalized);
    res.family = [NSString stringWithFormat:@"%06llx", (unsigned long long)((normalized >> 32) & 0xffffffULL)];
    res.param = [NSString stringWithFormat:@"%08llx", (unsigned long long)(normalized & 0xffffffffULL)];
    res.tag = [NSString stringWithFormat:@"%02llx", (unsigned long long)((value >> 56) & 0xffULL)];
    res.pointerLike = SCIDexKitLooksLikeRuntimePointerToken(brokerID ?: @"", value);
    res.runtimeObserved = (runtimeForOriginal != nil);

    for (NSNumber *n in candidateValues) {
        for (NSString *identity in [self identityCandidatesForBrokerID:brokerID value:n.unsignedLongLongValue]) {
            NSString *manual = [self manualNameForIdentity:identity];
            if (manual.length) {
                res.title = manual;
                res.name = manual;
                res.detail = [NSString stringWithFormat:@"manual identity=%@ · raw=%@ · normalized=%@", identity, res.rawKey, res.normalizedKey];
                res.source = @"manual";
                res.confidence = SCIDexKitNameConfidenceExact;
                res.manual = YES;
                res.runtimeObserved = res.runtimeObserved || (SCIDexKitRuntimeEntryForBrokerAndValue(brokerID, n.unsignedLongLongValue) != nil);
                return res;
            }
        }
    }

    for (NSNumber *n in candidateValues) {
        NSString *mapped = SCIResolveMappedNameForSpecifier(n.unsignedLongLongValue);
        if (mapped.length) {
            res.title = mapped;
            res.name = mapped;
            res.detail = [NSString stringWithFormat:@"mapping value=%@ · raw=%@ · normalized=%@", SCIDexKitHex(n.unsignedLongLongValue), res.rawKey, res.normalizedKey];
            res.source = @"mapping";
            res.confidence = SCIDexKitNameConfidenceExact;
            res.runtimeObserved = res.runtimeObserved || (SCIDexKitRuntimeEntryForBrokerAndValue(brokerID, n.unsignedLongLongValue) != nil);
            return res;
        }
    }

    for (NSNumber *n in candidateValues) {
        for (NSString *identity in [self identityCandidatesForBrokerID:brokerID value:n.unsignedLongLongValue]) {
            NSString *key = [kSCIDexKitNameRuntimePrefix stringByAppendingString:identity];
            NSString *runtimeName = [[NSUserDefaults standardUserDefaults] stringForKey:key];
            if (runtimeName.length) {
                res.title = runtimeName;
                res.name = runtimeName;
                res.detail = [NSString stringWithFormat:@"runtime-name identity=%@ · raw=%@ · normalized=%@", identity, res.rawKey, res.normalizedKey];
                res.source = @"runtime-name";
                res.confidence = SCIDexKitNameConfidenceHigh;
                res.runtimeObserved = YES;
                return res;
            }
        }
    }

    NSDictionary *runtimeEntry = nil;
    uint64_t runtimeValue = value;
    for (NSNumber *n in candidateValues) {
        runtimeEntry = SCIDexKitRuntimeEntryForBrokerAndValue(brokerID, n.unsignedLongLongValue);
        if (runtimeEntry) {
            runtimeValue = n.unsignedLongLongValue;
            break;
        }
    }

    if (runtimeEntry) {
        uint64_t runtimeNorm = [self normalizedSpecifierValue:runtimeValue];
        res.title = SCIDexKitRuntimeTitleFromEntry(runtimeEntry, runtimeNorm);
        res.name = @"";
        res.detail = SCIDexKitRuntimeDetailFromEntry(runtimeEntry);
        res.source = @"runtime-callsite";
        res.confidence = SCIDexKitNameConfidenceLow;
        res.runtimeObserved = YES;
        res.callerImage = SCIDexKitString(runtimeEntry[@"callerImage"]);
        res.callerSymbol = SCIDexKitString(runtimeEntry[@"callerSymbol"]);
        res.callerAddress = SCIDexKitString(runtimeEntry[@"callerAddress"]);
        return res;
    }

    NSString *aliasValue = @"";
    NSString *aliasIdentity = @"";
    NSString *aliasSource = @"";
    for (NSString *identity in [self identityCandidatesForBrokerID:brokerID value:value]) {
        aliasValue = SCIDexKitAliasForIdentity(identity) ?: @"";
        if (aliasValue.length) {
            aliasIdentity = identity;
            aliasSource = SCIDexKitAliasSourceForIdentity(identity) ?: @"alias";
            break;
        }
    }

    if (aliasValue.length) {
        res.title = SCIDexKitHex(normalized);
        res.name = @"";
        res.detail = [NSString stringWithFormat:@"alias identity=%@ · translated=%@ · aliasSource=%@ · raw=%@ · normalized=%@ · family=0x%@ · param=0x%@ · tag=0x%@", aliasIdentity, aliasValue, aliasSource, res.rawKey, res.normalizedKey, res.family ?: @"", res.param ?: @"", res.tag ?: @""];
        res.source = @"alias";
        res.confidence = SCIDexKitNameConfidenceLow;
        res.runtimeObserved = YES;
        return res;
    }

    if (res.pointerLike) {
        res.title = [NSString stringWithFormat:@"runtime gate token %@", SCIDexKitHex(value)];
        res.name = @"";
        res.detail = @"EasyGating/MCI/META value looks like a runtime pointer/token, not a stable MobileConfig specifier. Use caller/callsite or a manual label after correlation.";
        res.source = @"runtime-token";
        res.confidence = SCIDexKitNameConfidenceNone;
        return res;
    }

    res.title = SCIDexKitHex(normalized);
    res.name = @"";
    res.detail = [NSString stringWithFormat:@"decoded family=0x%@ · param=0x%@ · tag=0x%@ · normalized=%@", res.family ?: @"", res.param ?: @"", res.tag ?: @"", res.normalizedKey ?: @""];
    res.source = @"decoded-id";
    res.confidence = SCIDexKitNameConfidenceNone;
    return res;
}

+ (NSDictionary *)resolvedDictionaryForBrokerID:(NSString * _Nullable)brokerID value:(uint64_t)value {
    return [[self resolveBrokerID:brokerID value:value] dictionaryRepresentation];
}

+ (void)noteMobileConfigBoolReadWithClassName:(NSString *)className
                                     selector:(NSString *)selectorName
                                    specifier:(uint64_t)specifier
                                 defaultValue:(BOOL)defaultValue
                                originalValue:(BOOL)originalValue
                                   finalValue:(BOOL)finalValue
                                       source:(NSString *)source {
    [self noteMobileConfigBoolReadWithClassName:className
                                       selector:selectorName
                                      specifier:specifier
                                   defaultValue:defaultValue
                                  originalValue:originalValue
                                     finalValue:finalValue
                                         source:source
                                    callerImage:nil
                                   callerSymbol:nil
                                  callerAddress:0];
}

+ (void)noteMobileConfigBoolReadWithClassName:(NSString *)className
                                     selector:(NSString *)selectorName
                                    specifier:(uint64_t)specifier
                                 defaultValue:(BOOL)defaultValue
                                originalValue:(BOOL)originalValue
                                   finalValue:(BOOL)finalValue
                                       source:(NSString *)source
                                  callerImage:(nullable NSString *)callerImage
                                 callerSymbol:(nullable NSString *)callerSymbol
                                callerAddress:(uint64_t)callerAddress {
    NSString *safeClass = className.length ? className : @"?";
    NSString *safeSelector = selectorName.length ? selectorName : @"?";
    NSString *safeSource = source.length ? source : @"objc-getBool";
    NSString *brokerID = SCIDexKitInferBrokerID(safeClass);
    uint64_t normalized = [self normalizedSpecifierValue:specifier];

    NSString *runtimeExactName = SCIDexKitFeatureLikeSelectorName(safeSelector);
    if (runtimeExactName.length) {
        for (NSString *identity in [self identityCandidatesForBrokerID:brokerID value:specifier]) {
            NSString *key = [kSCIDexKitNameRuntimePrefix stringByAppendingString:identity];
            NSString *existing = [[NSUserDefaults standardUserDefaults] stringForKey:key];
            if (![existing isEqualToString:runtimeExactName]) {
                [[NSUserDefaults standardUserDefaults] setObject:runtimeExactName forKey:key];
            }
        }
    }

    NSDictionary *entry = @{
        @"rawHex": SCIDexKitHex(specifier),
        @"rawHexNoPrefix": SCIDexKitHexNoPrefix(specifier),
        @"normalizedHex": SCIDexKitHex(normalized),
        @"normalizedHexNoPrefix": SCIDexKitHexNoPrefix(normalized),
        @"className": safeClass,
        @"selector": safeSelector,
        @"source": safeSource,
        @"brokerID": brokerID ?: @"",
        @"defaultValue": @(defaultValue),
        @"originalValue": @(originalValue),
        @"finalValue": @(finalValue),
        @"callerImage": callerImage ?: @"",
        @"callerSymbol": callerSymbol ?: @"",
        @"callerAddress": SCIDexKitAddressHex(callerAddress),
        @"runtimeObserved": @YES
    };

    BOOL changed = NO;
    NSMutableOrderedSet<NSString *> *index = [NSMutableOrderedSet orderedSetWithArray:[[NSUserDefaults standardUserDefaults] arrayForKey:kSCIDexKitRuntimeIndexKey] ?: @[]];

    for (NSString *identity in [self identityCandidatesForBrokerID:brokerID value:specifier]) {
        NSString *key = [kSCIDexKitRuntimeEntryPrefix stringByAppendingString:identity];
        NSDictionary *existing = [[NSUserDefaults standardUserDefaults] dictionaryForKey:key];
        if (![existing isEqualToDictionary:entry]) {
            [[NSUserDefaults standardUserDefaults] setObject:entry forKey:key];
            changed = YES;
        }
        [index addObject:identity];
    }

    [[NSUserDefaults standardUserDefaults] setObject:index.array forKey:kSCIDexKitRuntimeIndexKey];
    if (changed) SCIDexKitPostUpdate(YES);
}

+ (void)noteAliasFromSpecifier:(uint64_t)rawSpecifier
                   toSpecifier:(uint64_t)translatedSpecifier
                        source:(NSString *)source {
    if (!rawSpecifier || !translatedSpecifier || rawSpecifier == translatedSpecifier) return;

    uint64_t rawNorm = [self normalizedSpecifierValue:rawSpecifier];
    uint64_t translatedNorm = [self normalizedSpecifierValue:translatedSpecifier];

    NSMutableDictionary<NSString *, NSString *> *pairs = [NSMutableDictionary dictionary];
    pairs[SCIDexKitHex(rawSpecifier)] = SCIDexKitHex(translatedSpecifier);
    pairs[SCIDexKitHexNoPrefix(rawSpecifier)] = SCIDexKitHex(translatedSpecifier);
    pairs[SCIDexKitHex(rawNorm)] = SCIDexKitHex(translatedNorm);
    pairs[SCIDexKitHexNoPrefix(rawNorm)] = SCIDexKitHex(translatedNorm);

    BOOL changed = NO;
    NSString *safeSource = source.length ? source : @"alias";

    for (NSString *identity in pairs.allKeys) {
        NSString *aliasValue = pairs[identity];
        NSString *aliasKey = [kSCIDexKitAliasRuntimePrefix stringByAppendingString:identity];
        NSString *sourceKey = [kSCIDexKitAliasSourceRuntimePrefix stringByAppendingString:identity];

        NSString *existing = [[NSUserDefaults standardUserDefaults] stringForKey:aliasKey];
        if (![existing isEqualToString:aliasValue]) {
            [[NSUserDefaults standardUserDefaults] setObject:aliasValue forKey:aliasKey];
            changed = YES;
        }

        NSString *existingSource = [[NSUserDefaults standardUserDefaults] stringForKey:sourceKey];
        if (![existingSource isEqualToString:safeSource]) {
            [[NSUserDefaults standardUserDefaults] setObject:safeSource forKey:sourceKey];
            changed = YES;
        }
    }

    if (changed) SCIDexKitPostUpdate(YES);
}

@end
