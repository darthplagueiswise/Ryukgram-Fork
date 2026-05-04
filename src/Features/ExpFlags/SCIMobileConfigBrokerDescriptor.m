#import "SCIMobileConfigBrokerDescriptor.h"

@implementation SCIMobileConfigBrokerDescriptor

+ (instancetype)d:(NSString *)brokerID
          symbol:(NSString *)symbol
            name:(NSString *)name
         details:(NSString *)details
           orig8:(uint64_t)orig8
              vm:(uintptr_t)vm
           xrefs:(NSUInteger)xrefs
            kind:(SCIMCBrokerKind)kind
         exactIG:(BOOL)exactIG {
    SCIMobileConfigBrokerDescriptor *d = [SCIMobileConfigBrokerDescriptor new];
    d.brokerID = brokerID ?: @"";
    d.symbol = symbol ?: @"";
    d.displayName = name ?: d.symbol;
    d.details = details ?: @"";
    d.imageName = @"FBSharedFramework";
    d.expectedOrig8 = orig8;
    d.vmAddress = vm;
    d.xrefCount = xrefs;
    d.kind = kind;
    d.exactIGInternalSignature = exactIG;
    return d;
}

+ (NSArray<SCIMobileConfigBrokerDescriptor *> *)allDescriptors {
    static NSArray<SCIMobileConfigBrokerDescriptor *> *items;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        items = @[
            [self d:@"ig"
             symbol:@"_IGMobileConfigBooleanValueForInternalUse"
               name:@"IG InternalUse Bool"
            details:@"Primary MobileConfig boolean broker. v72: VM 0x308f64, size ~6312, xrefs 16. Main dogfood choke point."
              orig8:0xd503201f10fdae23ULL
                 vm:0x308f64
              xrefs:16
               kind:SCIMCBrokerKindPrimary
            exactIG:YES],

            [self d:@"igsl"
             symbol:@"_IGMobileConfigSessionlessBooleanValueForInternalUse"
               name:@"IG Sessionless Bool"
            details:@"Sessionless complement. v72: VM 0x53b87c, size ~1156, xrefs 6."
              orig8:0xb0ffee4391129063ULL
                 vm:0x53b87c
              xrefs:6
               kind:SCIMCBrokerKindPrimary
            exactIG:YES],

            [self d:@"eg"
             symbol:@"_EasyGatingPlatformGetBoolean"
               name:@"EasyGating Platform Bool"
            details:@"Canonical EasyGating v72 platform broker. VM 0x652d44, size ~112, xrefs 1."
              orig8:0xa90557f6d10203ffULL
                 vm:0x652d44
              xrefs:1
               kind:SCIMCBrokerKindComplement
            exactIG:NO],

            [self d:@"mci"
             symbol:@"_MCIMobileConfigGetBoolean"
               name:@"MCI MobileConfig Bool"
            details:@"MCI-specific complement. VM 0x6a0afc, size ~448, xrefs 5. Not a substitute for IG InternalUse."
              orig8:0xa9014ff4a9bd57f6ULL
                 vm:0x6a0afc
              xrefs:5
               kind:SCIMCBrokerKindComplement
            exactIG:NO],

            [self d:@"egi"
             symbol:@"_EasyGatingGetBoolean_Internal_DoNotUseOrMock"
               name:@"EasyGating Internal Shim"
            details:@"Compat/lab only. v72 shim, VM 0x652d14, size ~48, xrefs 23. Prefer eg."
              orig8:0
                 vm:0x652d14
              xrefs:23
               kind:SCIMCBrokerKindCompat
            exactIG:NO],

            [self d:@"mcic"
             symbol:@"_MCIExperimentCacheGetMobileConfigBoolean"
               name:@"MCI ExperimentCache Bool"
            details:@"Compat/lab MCI cache path."
              orig8:0
                 vm:0
              xrefs:0
               kind:SCIMCBrokerKindCompat
            exactIG:NO],

            [self d:@"mcie"
             symbol:@"_MCIExtensionExperimentCacheGetMobileConfigBoolean"
               name:@"MCI ExtensionCache Bool"
            details:@"Compat/lab MCI extension cache path."
              orig8:0
                 vm:0
              xrefs:0
               kind:SCIMCBrokerKindCompat
            exactIG:NO],

            [self d:@"meta"
             symbol:@"_METAExtensionsExperimentGetBoolean"
               name:@"META Extensions Bool"
            details:@"Compat/lab METAExtensions path."
              orig8:0
                 vm:0
              xrefs:0
               kind:SCIMCBrokerKindCompat
            exactIG:NO],

            [self d:@"metanx"
             symbol:@"_METAExtensionsExperimentGetBooleanWithoutExposure"
               name:@"META Extensions Bool NoExposure"
            details:@"Compat/lab METAExtensions no-exposure path."
              orig8:0
                 vm:0
              xrefs:0
               kind:SCIMCBrokerKindCompat
            exactIG:NO],

            [self d:@"msgc"
             symbol:@"_MSGCSessionedMobileConfigGetBoolean"
               name:@"MSGC Sessioned Bool"
            details:@"Compat/lab MSGC sessioned path."
              orig8:0
                 vm:0
              xrefs:0
               kind:SCIMCBrokerKindCompat
            exactIG:NO],
        ];
    });
    return items;
}

+ (SCIMobileConfigBrokerDescriptor *)descriptorForID:(NSString *)brokerID {
    if (!brokerID.length) return nil;
    for (SCIMobileConfigBrokerDescriptor *d in self.allDescriptors) {
        if ([d.brokerID isEqualToString:brokerID]) return d;
    }
    return nil;
}

+ (SCIMobileConfigBrokerDescriptor *)descriptorForSymbol:(NSString *)symbol {
    if (!symbol.length) return nil;
    for (SCIMobileConfigBrokerDescriptor *d in self.allDescriptors) {
        if ([d.symbol isEqualToString:symbol] || [[d.symbol stringByTrimmingCharactersInSet:[NSCharacterSet characterSetWithCharactersInString:@"_"]] isEqualToString:symbol]) return d;
    }
    return nil;
}

@end
