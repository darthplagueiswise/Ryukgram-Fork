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
             abi:(SCIMCBrokerABI)abi
         keyKind:(SCIMCBrokerKeyKind)keyKind
          keyArg:(NSUInteger)keyArg
      defaultArg:(NSUInteger)defaultArg
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
    d.abi = abi;
    d.keyKind = keyKind;
    d.keyArgumentIndex = keyArg;
    d.defaultArgumentIndex = defaultArg;
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
               name:@"IG Context ObjC Bool"
            details:@"ObjC pass-through observer target: IGMobileConfigContextManager getBool* / getBoolWithoutLogging*. C broker symbol is retained only as lab metadata; Dev Mode uses ObjC runtime hooks."
              orig8:0xd503201f10fdae23ULL
                 vm:0x00308f64
              xrefs:16
               kind:SCIMCBrokerKindPrimary
                abi:SCIMCBrokerABIIGInternalBool
            keyKind:SCIMCBrokerKeyKindSpecifier
             keyArg:2
         defaultArg:1
            exactIG:NO],

            [self d:@"igsl"
             symbol:@"_IGMobileConfigSessionlessBooleanValueForInternalUse"
               name:@"IG Sessionless ObjC Bool"
            details:@"ObjC pass-through observer target: IGMobileConfigSessionlessContextManager getBool*. C broker symbol is retained only as lab metadata; Dev Mode uses ObjC runtime hooks."
              orig8:0x91129063b0ffee43ULL
                 vm:0x0053b87c
              xrefs:6
               kind:SCIMCBrokerKindPrimary
                abi:SCIMCBrokerABIIGInternalBool
            keyKind:SCIMCBrokerKeyKindSpecifier
             keyArg:2
         defaultArg:1
            exactIG:NO],

            [self d:@"igus"
             symbol:@"IGMobileConfigUserSessionContextManager"
               name:@"IG UserSession ObjC Bool"
            details:@"ObjC pass-through observer target: IGMobileConfigUserSessionContextManager getBool* / exposure readers. Override is per observed specifier."
              orig8:0
                 vm:0
              xrefs:0
               kind:SCIMCBrokerKindPrimary
                abi:SCIMCBrokerABIGeneric8Bool
            keyKind:SCIMCBrokerKeyKindSpecifier
             keyArg:2
         defaultArg:0
            exactIG:NO],

            [self d:@"fb"
             symbol:@"FBMobileConfigContextManager"
               name:@"FB Context ObjC Bool"
            details:@"ObjC pass-through observer target: FBMobileConfigContextManager getBool* / getBoolWithoutLogging*. Override is per observed specifier."
              orig8:0
                 vm:0
              xrefs:0
               kind:SCIMCBrokerKindPrimary
                abi:SCIMCBrokerABIGeneric8Bool
            keyKind:SCIMCBrokerKeyKindSpecifier
             keyArg:2
         defaultArg:0
            exactIG:NO],

            [self d:@"fbsl"
             symbol:@"FBMobileConfigSessionlessContextManager"
               name:@"FB Sessionless ObjC Bool"
            details:@"ObjC pass-through observer target: FBMobileConfigSessionlessContextManager getBool*. Override is per observed specifier."
              orig8:0
                 vm:0
              xrefs:0
               kind:SCIMCBrokerKindPrimary
                abi:SCIMCBrokerABIGeneric8Bool
            keyKind:SCIMCBrokerKeyKindSpecifier
             keyArg:2
         defaultArg:0
            exactIG:NO],

            [self d:@"fbus"
             symbol:@"FBMobileConfigUserSessionContextManager"
               name:@"FB UserSession ObjC Bool"
            details:@"ObjC pass-through observer target: FBMobileConfigUserSessionContextManager getBool*. Override is per observed specifier."
              orig8:0
                 vm:0
              xrefs:0
               kind:SCIMCBrokerKindPrimary
                abi:SCIMCBrokerABIGeneric8Bool
            keyKind:SCIMCBrokerKeyKindSpecifier
             keyArg:2
         defaultArg:0
            exactIG:NO],

            [self d:@"fbapt"
             symbol:@"FBMobileConfigAccessedParamsTracker"
               name:@"FB AccessedParams Tracker"
            details:@"ObjC access-only observer target: firstTimeAccessForParameter:context:completion:. Used to collect IDs/call-sites; bool state comes from getters."
              orig8:0
                 vm:0
              xrefs:0
               kind:SCIMCBrokerKindAdvanced
                abi:SCIMCBrokerABIGeneric8Bool
            keyKind:SCIMCBrokerKeyKindSpecifier
             keyArg:2
         defaultArg:0
            exactIG:NO],

            [self d:@"fbctx"
             symbol:@"FBMobileConfigContextTracker"
               name:@"FB Context Tracker"
            details:@"ObjC validated observer target. Context/session metadata only; no bool override is applied here."
              orig8:0
                 vm:0
              xrefs:0
               kind:SCIMCBrokerKindAdvanced
                abi:SCIMCBrokerABIGeneric8Bool
            keyKind:SCIMCBrokerKeyKindSpecifier
             keyArg:2
         defaultArg:0
            exactIG:NO],

            [self d:@"fbpd"
             symbol:@"FBMobileConfigParameterDescription"
               name:@"FB Parameter Description"
            details:@"ObjC validated observer target for parameter value/source metadata. No bool override is applied directly here."
              orig8:0
                 vm:0
              xrefs:0
               kind:SCIMCBrokerKindAdvanced
                abi:SCIMCBrokerABIGeneric8Bool
            keyKind:SCIMCBrokerKeyKindSpecifier
             keyArg:2
         defaultArg:0
            exactIG:NO],

            [self d:@"metaser"
             symbol:@"METAMobileConfigUsageSerializer"
               name:@"META Usage Serializer"
            details:@"ObjC validated observer target. Serializer has C++ shared_ptr class methods; kept validation-only for safety."
              orig8:0
                 vm:0
              xrefs:0
               kind:SCIMCBrokerKindAdvanced
                abi:SCIMCBrokerABIGeneric8Bool
            keyKind:SCIMCBrokerKeyKindSpecifier
             keyArg:2
         defaultArg:0
            exactIG:NO],

            [self d:@"metaut"
             symbol:@"METAMobileConfigUsageTracker"
               name:@"META Usage Tracker"
            details:@"ObjC access-only observer target: trackParameterAccess:. Used to collect IDs/call-sites; bool state comes from getters."
              orig8:0
                 vm:0
              xrefs:0
               kind:SCIMCBrokerKindAdvanced
                abi:SCIMCBrokerABIGeneric8Bool
            keyKind:SCIMCBrokerKeyKindSpecifier
             keyArg:2
         defaultArg:0
            exactIG:NO],

            [self d:@"eg"
             symbol:@"_EasyGatingPlatformGetBoolean"
               name:@"EasyGating Platform Bool"
            details:@"Canonical EasyGating platform broker for this build. Generic wrapper. Override is per gate value, heuristic x1."
              orig8:0xa90557f6d10203ffULL
                 vm:0x00652d44
              xrefs:1
               kind:SCIMCBrokerKindComplement
                abi:SCIMCBrokerABIGeneric8Bool
            keyKind:SCIMCBrokerKeyKindGate
             keyArg:1
         defaultArg:2
            exactIG:NO],

            [self d:@"mci"
             symbol:@"_MCIMobileConfigGetBoolean"
               name:@"MCI MobileConfig Bool"
            details:@"MCI-specific complement. Generic wrapper. Override is per specifier, heuristic x2."
              orig8:0xa9014ff4a9bd57f6ULL
                 vm:0x006a0afc
              xrefs:5
               kind:SCIMCBrokerKindComplement
                abi:SCIMCBrokerABIGeneric8Bool
            keyKind:SCIMCBrokerKeyKindSpecifier
             keyArg:2
         defaultArg:2
            exactIG:NO],

            [self d:@"egi"
             symbol:@"_EasyGatingGetBoolean_Internal_DoNotUseOrMock"
               name:@"EasyGating Internal Shim"
            details:@"Compat/lab only. v72 shim. Many xrefs and higher risk. Prefer EasyGating Platform."
              orig8:0
                 vm:0x00652d14
              xrefs:23
               kind:SCIMCBrokerKindCompat
                abi:SCIMCBrokerABIGeneric8Bool
            keyKind:SCIMCBrokerKeyKindGate
             keyArg:0
         defaultArg:2
            exactIG:NO],

            [self d:@"ega"
             symbol:@"_EasyGatingGetBooleanUsingAuthDataContext_Internal_DoNotUseOrMock"
               name:@"EasyGating AuthData Bool"
            details:@"Compat/lab only. Auth-data-context EasyGating bool, generic wrapper, gate heuristic x1."
              orig8:0
                 vm:0x00ce3cfc
              xrefs:0
               kind:SCIMCBrokerKindCompat
                abi:SCIMCBrokerABIGeneric8Bool
            keyKind:SCIMCBrokerKeyKindGate
             keyArg:1
         defaultArg:2
            exactIG:NO],

            [self d:@"mcic"
             symbol:@"_MCIExperimentCacheGetMobileConfigBoolean"
               name:@"MCI ExperimentCache Bool"
            details:@"Advanced/lab MCI experiment cache bool reader. Per specifier."
              orig8:0xa90157f6d10103ffULL
                 vm:0x006a4998
              xrefs:1
               kind:SCIMCBrokerKindAdvanced
                abi:SCIMCBrokerABIGeneric8Bool
            keyKind:SCIMCBrokerKeyKindSpecifier
             keyArg:2
         defaultArg:2
            exactIG:NO],

            [self d:@"mcie"
             symbol:@"_MCIExtensionExperimentCacheGetMobileConfigBoolean"
               name:@"MCI ExtensionCache Bool"
            details:@"Advanced/lab MCI extension experiment bool reader. Per specifier."
              orig8:0xa90557f6d10203ffULL
                 vm:0x00697ad8
              xrefs:4
               kind:SCIMCBrokerKindAdvanced
                abi:SCIMCBrokerABIGeneric8Bool
            keyKind:SCIMCBrokerKeyKindSpecifier
             keyArg:2
         defaultArg:2
            exactIG:NO],

            [self d:@"meta"
             symbol:@"_METAExtensionsExperimentGetBoolean"
               name:@"META Extensions Bool"
            details:@"Advanced/lab METAExtensions bool reader. Per gate, heuristic x1."
              orig8:0x1404b45252800024ULL
                 vm:0x00bbf154
              xrefs:3
               kind:SCIMCBrokerKindAdvanced
                abi:SCIMCBrokerABIGeneric8Bool
            keyKind:SCIMCBrokerKeyKindGate
             keyArg:1
         defaultArg:2
            exactIG:NO],

            [self d:@"metanx"
             symbol:@"_METAExtensionsExperimentGetBooleanWithoutExposure"
               name:@"META Extensions Bool NoExposure"
            details:@"Advanced/lab METAExtensions bool reader without exposure. Per gate, heuristic x1."
              orig8:0x1404d33e52800004ULL
                 vm:0x00bb75a4
              xrefs:0
               kind:SCIMCBrokerKindAdvanced
                abi:SCIMCBrokerABIGeneric8Bool
            keyKind:SCIMCBrokerKeyKindGate
             keyArg:1
         defaultArg:2
            exactIG:NO],

            [self d:@"msgc"
             symbol:@"_MSGCSessionedMobileConfigGetBoolean"
               name:@"MSGC Sessioned Bool"
            details:@"Advanced/lab MSGC sessioned MobileConfig bool reader. Per specifier, heuristic x2."
              orig8:0x97a81efba9bf7bfdULL
                 vm:0x0160a398
              xrefs:0
               kind:SCIMCBrokerKindAdvanced
                abi:SCIMCBrokerABIGeneric8Bool
            keyKind:SCIMCBrokerKeyKindSpecifier
             keyArg:2
         defaultArg:2
            exactIG:NO],
        ];
    });
    return items;
}

+ (SCIMobileConfigBrokerDescriptor *)descriptorForID:(NSString *)brokerID {
    if (!brokerID.length) return nil;
    for (SCIMobileConfigBrokerDescriptor *d in [self allDescriptors]) {
        if ([d.brokerID isEqualToString:brokerID]) return d;
    }
    return nil;
}

+ (SCIMobileConfigBrokerDescriptor *)descriptorForSymbol:(NSString *)symbol {
    if (!symbol.length) return nil;
    NSString *needle = [symbol hasPrefix:@"_"] ? symbol : [@"_" stringByAppendingString:symbol];
    for (SCIMobileConfigBrokerDescriptor *d in [self allDescriptors]) {
        if ([d.symbol isEqualToString:needle]) return d;
    }
    return nil;
}

- (NSString *)namespaceSymbol {
    NSString *s = self.symbol ?: @"";
    return [s hasPrefix:@"_"] ? [s substringFromIndex:1] : s;
}

- (NSString *)kindLabel {
    return self.keyKind == SCIMCBrokerKeyKindGate ? @"gate" : @"specifier";
}

- (NSString *)tierLabel {
    switch (self.kind) {
        case SCIMCBrokerKindPrimary: return @"core";
        case SCIMCBrokerKindComplement: return @"extra";
        case SCIMCBrokerKindCompat: return @"compat";
        case SCIMCBrokerKindAdvanced: return @"advanced";
    }
    return @"unknown";
}

@end
