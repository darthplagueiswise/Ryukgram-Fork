#import "RYGMobileConfig.h"
#import <Foundation/Foundation.h>
#import <objc/runtime.h>

// Semantic late resolver for imported id_name_mapping rows.
//
// The browser model may be prepared before the active FBMobileConfig session
// manager is available. In that case the imported configId:paramId still has a
// valid semantic identity, but the exact 64-bit paramSpecifier cannot yet be
// produced. This adapter retries the native descriptor/model resolution at the
// moment the user applies a value. It never waits for a getter observation and
// never fabricates mirrored unit PIDs.

@interface RYGMobileConfig (RYGSemanticResolverPrivate)
- (BOOL)ryg_semantic_setOverride:(id)value for:(RYGMCParam *)param;
- (void)ryg_semantic_clearOverrideFor:(RYGMCParam *)param;
@end

static RYGMCParam *RYGMCFindResolvedSemanticParam(RYGMobileConfig *mobileConfig, RYGMCParam *source) {
    if (!mobileConfig || !source) return nil;
    [mobileConfig reloadFromRuntime];
    for (RYGMCConfig *config in [mobileConfig allConfigs]) {
        if (config.number != source.configNumber) continue;
        for (RYGMCParam *candidate in config.params) {
            if (candidate.paramIndex != source.paramIndex) continue;
            if (!candidate.isRuntimeBacked || !candidate.paramID || !RYGMCTypeIsRuntimeValue(candidate.type)) return nil;
            return candidate;
        }
        break;
    }
    return nil;
}

static void RYGMCCopyRuntimeIdentity(RYGMCParam *destination, RYGMCParam *source) {
    if (!destination || !source) return;
    destination.paramID = source.paramID;
    destination.ordinal = source.ordinal;
    destination.type = source.type;
    destination.runtimeBacked = source.isRuntimeBacked;
    if (!destination.name.length && source.name.length) destination.name = source.name;
}

@implementation RYGMobileConfig (RYGSemanticResolver)

- (BOOL)ryg_semantic_setOverride:(id)value for:(RYGMCParam *)param {
    if (!param || !value) return NO;
    if (!param.isRuntimeBacked || !param.paramID || !RYGMCTypeIsRuntimeValue(param.type)) {
        RYGMCParam *resolved = RYGMCFindResolvedSemanticParam(self, param);
        if (resolved) RYGMCCopyRuntimeIdentity(param, resolved);
    }

    if (!param.isRuntimeBacked || !param.paramID || !RYGMCTypeIsRuntimeValue(param.type)) {
        // The canonical mc_overrides.json write belongs to the document store
        // and is still valid without an in-memory manager. Report semantic
        // acceptance so the edit is persisted for the native next load rather
        // than incorrectly requiring this PID to have been observed first.
        return YES;
    }
    return [self ryg_semantic_setOverride:value for:param];
}

- (void)ryg_semantic_clearOverrideFor:(RYGMCParam *)param {
    if (!param) return;
    if (!param.isRuntimeBacked || !param.paramID) {
        RYGMCParam *resolved = RYGMCFindResolvedSemanticParam(self, param);
        if (resolved) RYGMCCopyRuntimeIdentity(param, resolved);
    }
    if (!param.isRuntimeBacked || !param.paramID) return;
    [self ryg_semantic_clearOverrideFor:param];
}

@end

static BOOL RYGMCExchangeSemanticSelector(Class cls, SEL originalSelector, SEL replacementSelector) {
    Method original = class_getInstanceMethod(cls, originalSelector);
    Method replacement = class_getInstanceMethod(cls, replacementSelector);
    if (!original || !replacement) return NO;
    if (method_getNumberOfArguments(original) != method_getNumberOfArguments(replacement)) return NO;
    method_exchangeImplementations(original, replacement);
    return YES;
}

__attribute__((constructor(65480))) static void RYGInstallMobileConfigSemanticResolver(void) {
    Class cls = RYGMobileConfig.class;
    if (!cls) return;
    RYGMCExchangeSemanticSelector(cls, @selector(setOverride:for:), @selector(ryg_semantic_setOverride:for:));
    RYGMCExchangeSemanticSelector(cls, @selector(clearOverrideFor:), @selector(ryg_semantic_clearOverrideFor:));
}
