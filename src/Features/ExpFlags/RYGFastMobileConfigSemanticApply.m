#import "RYGMobileConfig.h"
#import <Foundation/Foundation.h>
#import <objc/runtime.h>
#include <math.h>
#include <stdlib.h>

// The fast browser's document store intentionally owns the canonical JSON edit,
// but a row imported from id_name_mapping may have been created before the
// active MobileConfig manager existed. Route every edit through the semantic
// resolver first so configId:paramId can become runtime-backed on demand without
// waiting for a getter observation.

@interface RYGFastMCDocumentStore : NSObject
- (BOOL)setValueText:(nullable NSString *)valueText forParam:(RYGMCParam *)param error:(NSError **)error;
@end

@interface RYGFastMCDocumentStore (RYGSemanticApply)
- (BOOL)ryg_semantic_setValueText:(nullable NSString *)valueText forParam:(RYGMCParam *)param error:(NSError **)error;
@end

static id RYGMCCanonicalObjectFromText(NSString *text) {
    if (![text isKindOfClass:NSString.class]) return nil;
    NSString *trim = [text stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet];
    NSString *lower = trim.lowercaseString;
    if ([lower isEqualToString:@"true"]) return @YES;
    if ([lower isEqualToString:@"false"]) return @NO;

    const char *raw = trim.UTF8String;
    if (raw && *raw) {
        char *end = NULL;
        long long integer = strtoll(raw, &end, 10);
        if (end != raw && *end == '\0') return @(integer);
        end = NULL;
        double floating = strtod(raw, &end);
        if (end != raw && *end == '\0' && isfinite(floating)) return @(floating);
    }
    return text;
}

@implementation RYGFastMCDocumentStore (RYGSemanticApply)

- (BOOL)ryg_semantic_setValueText:(NSString *)valueText forParam:(RYGMCParam *)param error:(NSError **)error {
    if (!param) return NO;

    // This call may enrich `param` with exact PID/type/ordinal from the native
    // descriptor table. It does not depend on call-site observation.
    if (valueText) {
        id value = RYGMCCanonicalObjectFromText(valueText);
        if (!value || ![RYGMobileConfig.shared setOverride:value for:param]) {
            if (error) *error = [NSError errorWithDomain:@"RYGFastMobileConfig"
                                                    code:7
                                                userInfo:@{NSLocalizedDescriptionKey:@"The imported config/parameter resolved to a native type that rejected this value."}];
            return NO;
        }
    } else {
        [RYGMobileConfig.shared clearOverrideFor:param];
    }

    // After method exchange this is the original document-store implementation.
    // If semantic resolution enriched the row it will use the same exact PID;
    // otherwise it still performs the authoritative atomic mc_overrides.json edit.
    return [self ryg_semantic_setValueText:valueText forParam:param error:error];
}

@end

__attribute__((constructor(65490))) static void RYGInstallFastMobileConfigSemanticApply(void) {
    Class cls = objc_lookUpClass("RYGFastMCDocumentStore");
    if (!cls) return;
    SEL originalSelector = @selector(setValueText:forParam:error:);
    SEL replacementSelector = @selector(ryg_semantic_setValueText:forParam:error:);
    Method original = class_getInstanceMethod(cls, originalSelector);
    Method replacement = class_getInstanceMethod(cls, replacementSelector);
    if (!original || !replacement || method_getNumberOfArguments(original) != method_getNumberOfArguments(replacement)) return;
    method_exchangeImplementations(original, replacement);
}
