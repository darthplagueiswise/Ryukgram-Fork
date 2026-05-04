#import "SCIMobileConfigBrokerDescriptor.h"

@implementation SCIMobileConfigBrokerDescriptor

static SCIMobileConfigBrokerDescriptor *SCIMCBrokerMake(NSString *bid,
                                                        NSString *symbol,
                                                        NSString *name,
                                                        NSString *details,
                                                        uint64_t orig8,
                                                        uintptr_t vm,
                                                        NSUInteger xrefs,
                                                        SCIMCBrokerABI abi,
                                                        SCIMCBrokerKeyKind keyKind,
                                                        SCIMCBrokerTier tier,
                                                        NSUInteger keyArg,
                                                        NSUInteger defaultArg,
                                                        BOOL enabledByDefault) {
    SCIMobileConfigBrokerDescriptor *d = [SCIMobileConfigBrokerDescriptor new];
    d.brokerID = bid ?: @"";
    d.symbol = symbol ?: @"";
    d.displayName = name ?: symbol ?: @"";
    d.details = details ?: @"";
    d.imageName = @"FBSharedFramework";
    d.expectedOrig8 = orig8;
    d.vmAddress = vm;
    d.xrefCount = xrefs;
    d.abi = abi;
    d.keyKind = keyKind;
    d.tier = tier;
    d.keyArgumentIndex = keyArg;
    d.defaultArgumentIndex = defaultArg;
    d.enabledByDefault = enabledByDefault;
    return d;
}

+ (NSArray<SCIMobileConfigBrokerDescriptor *> *)allDescriptors {
    static NSArray<SCIMobileConfigBrokerDescriptor *> *items;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        items = @[
            SCIMCBrokerMake(@"ig", @"_IGMobileConfigBooleanValueForInternalUse", @"IG MobileConfig InternalUse Bool", @"Primary C broker. Validated owner FBSharedFramework(72), VM 0x308f64, direct xrefs include IGStashSetExperimentsValues.", 0xd503201f10fdae23ULL, 0x00308f64, 11, SCIMCBrokerABIIGInternalBool, SCIMCBrokerKeyKindSpecifier, SCIMCBrokerTierPrimary, 2, 1, YES),
            SCIMCBrokerMake(@"igsl", @"_IGMobileConfigSessionlessBooleanValueForInternalUse", @"IG MobileConfig Sessionless Bool", @"Sessionless complement. Validated owner FBSharedFramework(72), VM 0x53b87c.", 0xb0ffee4391129063ULL, 0x0053b87c, 5, SCIMCBrokerABIIGInternalBool, SCIMCBrokerKeyKindSpecifier, SCIMCBrokerTierPrimary, 2, 1, YES),
            SCIMCBrokerMake(@"egp", @"_EasyGatingPlatformGetBoolean", @"EasyGating Platform Bool", @"Canonical EasyGating platform bool in this build. Generic ABI wrapper, gate heuristic x1, default heuristic x2.", 0xd10203ffa90557f6ULL, 0x00652d44, 0, SCIMCBrokerABIGeneric8Bool, SCIMCBrokerKeyKindGate, SCIMCBrokerTierComplement, 1, 2, NO),
            SCIMCBrokerMake(@"mci", @"_MCIMobileConfigGetBoolean", @"MCI MobileConfig Bool", @"Complementary MCI broker. Generic ABI wrapper; use selectively.", 0xa9014ff4a9bd57f6ULL, 0x006a0afc, 4, SCIMCBrokerABIGeneric8Bool, SCIMCBrokerKeyKindSpecifier, SCIMCBrokerTierComplement, 2, 2, NO),

            SCIMCBrokerMake(@"egi", @"_EasyGatingGetBoolean_Internal_DoNotUseOrMock", @"EasyGating Internal Bool", @"Compat/lab only. Small shim in v72, but many xrefs and higher risk.", 0, 0x00652d14, 13, SCIMCBrokerABIGeneric8Bool, SCIMCBrokerKeyKindGate, SCIMCBrokerTierCompat, 0, 2, NO),
            SCIMCBrokerMake(@"ega", @"_EasyGatingGetBooleanUsingAuthDataContext_Internal_DoNotUseOrMock", @"EasyGating AuthData Bool", @"Compat/lab only. Generic ABI wrapper; gate heuristic x1.", 0, 0x00ce3cfc, 0, SCIMCBrokerABIGeneric8Bool, SCIMCBrokerKeyKindGate, SCIMCBrokerTierCompat, 1, 2, NO),
            SCIMCBrokerMake(@"mcic", @"_MCIExperimentCacheGetMobileConfigBoolean", @"MCI Experiment Cache Bool", @"Complementary cache bool reader.", 0, 0, 1, SCIMCBrokerABIGeneric8Bool, SCIMCBrokerKeyKindSpecifier, SCIMCBrokerTierAdvanced, 2, 2, NO),
            SCIMCBrokerMake(@"mcie", @"_MCIExtensionExperimentCacheGetMobileConfigBoolean", @"MCI Extension Experiment Bool", @"Complementary extension cache bool reader.", 0, 0, 4, SCIMCBrokerABIGeneric8Bool, SCIMCBrokerKeyKindSpecifier, SCIMCBrokerTierAdvanced, 2, 2, NO),
            SCIMCBrokerMake(@"meta", @"_METAExtensionsExperimentGetBoolean", @"META Extensions Bool", @"Advanced complementary META extension bool reader.", 0, 0, 3, SCIMCBrokerABIGeneric8Bool, SCIMCBrokerKeyKindGate, SCIMCBrokerTierAdvanced, 1, 2, NO),
            SCIMCBrokerMake(@"metanx", @"_METAExtensionsExperimentGetBooleanWithoutExposure", @"META Extensions Bool No Exposure", @"Advanced complementary META extension bool reader without exposure.", 0, 0, 0, SCIMCBrokerABIGeneric8Bool, SCIMCBrokerKeyKindGate, SCIMCBrokerTierAdvanced, 1, 2, NO),
            SCIMCBrokerMake(@"msgc", @"_MSGCSessionedMobileConfigGetBoolean", @"MSGC Sessioned MC Bool", @"Advanced complementary MSGC sessioned bool reader.", 0, 0, 0, SCIMCBrokerABIGeneric8Bool, SCIMCBrokerKeyKindSpecifier, SCIMCBrokerTierAdvanced, 2, 2, NO),
        ];
    });
    return items;
}

+ (nullable SCIMobileConfigBrokerDescriptor *)descriptorForID:(NSString *)brokerID {
    for (SCIMobileConfigBrokerDescriptor *d in [self allDescriptors]) {
        if ([d.brokerID isEqualToString:brokerID]) return d;
    }
    return nil;
}

+ (nullable SCIMobileConfigBrokerDescriptor *)descriptorForSymbol:(NSString *)symbol {
    NSString *needle = symbol ?: @"";
    if (![needle hasPrefix:@"_"]) needle = [@"_" stringByAppendingString:needle];
    for (SCIMobileConfigBrokerDescriptor *d in [self allDescriptors]) {
        if ([d.symbol isEqualToString:needle]) return d;
    }
    return nil;
}

- (NSString *)namespaceSymbol {
    NSString *s = self.symbol ?: @"";
    return [s hasPrefix:@"_"] ? [s substringFromIndex:1] : s;
}

- (NSString *)tierLabel {
    switch (self.tier) {
        case SCIMCBrokerTierPrimary: return @"primary";
        case SCIMCBrokerTierComplement: return @"complement";
        case SCIMCBrokerTierCompat: return @"compat";
        case SCIMCBrokerTierAdvanced: return @"advanced";
    }
    return @"unknown";
}

- (NSString *)kindLabel {
    return self.keyKind == SCIMCBrokerKeyKindGate ? @"gate" : @"specifier";
}

@end
