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
static NSString * const kSCIDexKitAliasRuntimePrefix = @"dexkit.alias.runtime:";

static BOOL SCIDexKitMappingMethodLooksLikeObjectForU64(Class cls, SEL sel) {
    Method m = class_getClassMethod(cls, sel);
    if (!m) return NO;
    if (method_getNumberOfArguments(m) != 3) return NO; // self, _cmd, value

    char ret[128] = {0};
    char arg[128] = {0};
    method_getReturnType(m, ret, sizeof(ret));
    method_getArgumentType(m, 2, arg, sizeof(arg));

    if (ret[0] != '@') return NO;

    NSUInteger argSize = 0;
    NSGetSizeAndAlignment(arg, &argSize, NULL);
    return argSize == sizeof(uint64_t);
}

static NSString *SCIResolveMappedNameForSpecifier(uint64_t value) {
    NSArray<NSString *> *classNames = @[
        @"SCIMobileConfigMapping",
        @"SCIExpMobileConfigMapping"
    ];

    NSArray<NSString *> *selectorNames = @[
        @"nameForSpecifier:",
        @"nameForSpecifierValue:",
        @"mappedNameForSpecifier:",
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
            id candidate = fn(cls, sel, value);

            if ([candidate isKindOfClass:[NSString class]] && [(NSString *)candidate length] > 0) {
                return (NSString *)candidate;
            }
        }
    }

    return nil;
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
    // Bits 63-32: config_id, Bits 31-0: param_id
    return value;
}

+ (NSString *)hexForValue:(uint64_t)value {
    return [NSString stringWithFormat:@"0x%016llx", value];
}

+ (nullable NSString *)manualNameForIdentity:(NSString *)identity {
    if (!identity) return nil;
    NSString *key = [kSCIDexKitNameManualPrefix stringByAppendingString:identity];
    return [[NSUserDefaults standardUserDefaults] stringForKey:key];
}

+ (void)setManualName:(nullable NSString *)name forIdentity:(NSString *)identity {
    if (!identity) return;
    NSString *key = [kSCIDexKitNameManualPrefix stringByAppendingString:identity];
    if (name) {
        [[NSUserDefaults standardUserDefaults] setObject:name forKey:key];
    } else {
        [[NSUserDefaults standardUserDefaults] removeObjectForKey:key];
    }
    [[NSUserDefaults standardUserDefaults] synchronize];
    
    dispatch_async(dispatch_get_main_queue(), ^{
        [[NSNotificationCenter defaultCenter] postNotificationName:SCIDexKitNameResolverDidUpdateNotification object:nil];
    });
}

+ (SCIDexKitResolvedName *)resolveBrokerID:(NSString * _Nullable)brokerID value:(uint64_t)value {
    SCIDexKitResolvedName *res = [[SCIDexKitResolvedName alloc] init];
    res.rawKey = brokerID ?: @"";
    res.normalizedKey = [self hexForValue:value];
    
    // 1. Manual
    NSString *manual = [self manualNameForIdentity:res.normalizedKey];
    if (manual) {
        res.title = manual;
        res.source = @"manual";
        res.confidence = SCIDexKitNameConfidenceExact;
        res.manual = YES;
        return res;
    }
    
    // 2. Runtime
    NSString *runtimeKey = [kSCIDexKitNameRuntimePrefix stringByAppendingString:res.normalizedKey];
    NSString *runtime = [[NSUserDefaults standardUserDefaults] stringForKey:runtimeKey];
    if (runtime) {
        res.title = runtime;
        res.source = @"runtime";
        res.confidence = SCIDexKitNameConfidenceHigh;
        res.runtimeObserved = YES;
        return res;
    }
    
    // 3. Mapping
    NSString *mapped = SCIResolveMappedNameForSpecifier(value);
    if (mapped) {
        res.title = mapped;
        res.source = @"mapping";
        res.confidence = SCIDexKitNameConfidenceMedium;
        return res;
    }
    
    res.title = res.normalizedKey;
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
    
    NSString *normHex = [self hexForValue:specifier];
    NSString *name = nil;
    
    if ([selectorName hasPrefix:@"is"] || [selectorName hasPrefix:@"should"]) {
        name = selectorName;
    }
    
    if (name) {
        NSString *key = [kSCIDexKitNameRuntimePrefix stringByAppendingString:normHex];
        NSString *existing = [[NSUserDefaults standardUserDefaults] stringForKey:key];
        if (![existing isEqualToString:name]) {
            [[NSUserDefaults standardUserDefaults] setObject:name forKey:key];
            [[NSUserDefaults standardUserDefaults] synchronize];
            
            dispatch_async(dispatch_get_main_queue(), ^{
                [[NSNotificationCenter defaultCenter] postNotificationName:SCIDexKitNameResolverRuntimeFeedDidUpdateNotification object:nil];
                [[NSNotificationCenter defaultCenter] postNotificationName:SCIDexKitNameResolverDidUpdateNotification object:nil];
            });
        }
    }
}

+ (void)noteAliasFromSpecifier:(uint64_t)rawSpecifier
                   toSpecifier:(uint64_t)translatedSpecifier
                        source:(NSString *)source {
    NSString *rawHex = [self hexForValue:rawSpecifier];
    NSString *transHex = [self hexForValue:translatedSpecifier];
    
    NSString *key = [kSCIDexKitAliasRuntimePrefix stringByAppendingString:rawHex];
    [[NSUserDefaults standardUserDefaults] setObject:transHex forKey:key];
    [[NSUserDefaults standardUserDefaults] synchronize];
}

@end
