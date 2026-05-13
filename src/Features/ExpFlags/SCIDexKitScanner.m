#import "SCIDexKitScanner.h"
#import "SCIDexKitImagePolicy.h"
#import "SCIDexKitSelectorRules.h"
#import "SCIDexKitStore.h"
#import "SCIDexKitBoolRouter.h"
#import <objc/runtime.h>
#import <dlfcn.h>

@implementation SCIDexKitScanner

+ (BOOL)method:(Method)m isEligibleForMode:(SCIDexKitScannerMode)mode selector:(NSString *)sel {
    if (!m) return NO;
    if (method_getNumberOfArguments(m) != 2) return NO;
    char rt[32] = {0};
    method_getReturnType(m, rt, sizeof(rt));
    if (rt[0] == 'B') return YES;
    if (mode == SCIDexKitScannerModeRaw && rt[0] == 'c' && [SCIDexKitSelectorRules selectorLooksBoolLegacyC:sel]) return YES;
    return NO;
}

+ (NSString *)typeEncodingForMethod:(Method)m {
    const char *t = method_getTypeEncoding(m);
    return t ? @(t) : @"";
}

+ (void)fillStateForDescriptor:(SCIDexKitDescriptor *)d {
    d.overrideValue = [SCIDexKitStore overrideValueForKey:d.overrideKey];
    NSNumber *obs = [SCIDexKitStore observedValueForKey:d.observedKey];
    d.observedKnown = obs != nil;
    d.observedValue = obs.boolValue;
    d.effectiveState = [SCIDexKitStore effectiveStateForOverrideKey:d.overrideKey observedKey:d.observedKey];
    d.hookInstalled = SCIDexKitIsHookInstalled(d.overrideKey);
}

+ (void)fillClassificationForDescriptor:(SCIDexKitDescriptor *)d method:(Method)m dlInfo:(Dl_info *)info {
    NSDictionary<NSString *, id> *classification = [SCIDexKitSelectorRules classificationForClassName:d.className
                                                                                             selector:d.selectorName
                                                                                        imageBasename:d.imageBasename
                                                                                         typeEncoding:d.typeEncoding];
    d.semanticCategory = classification[@"semanticCategory"] ?: @"unknown-bool";
    d.riskLevel = [classification[@"riskLevel"] integerValue];
    d.batchForceAllowed = [classification[@"batchForceAllowed"] boolValue];
    d.observeRecommended = [classification[@"observeRecommended"] boolValue];
    d.forceRecommended = [classification[@"forceRecommended"] boolValue];
    d.classificationReason = classification[@"classificationReason"] ?: @"";
    d.familyKey = classification[@"familyKey"] ?: [SCIDexKitSelectorRules familyKeyForClassName:d.className selector:d.selectorName];

    IMP imp = m ? method_getImplementation(m) : NULL;
    d.impAddress = (uint64_t)(uintptr_t)imp;
    d.impSymbol = (info && info->dli_sname) ? @(info->dli_sname) : @"";
    d.implementationKey = [NSString stringWithFormat:@"%@|0x%llx|%@", d.imageBasename ?: @"?", (unsigned long long)d.impAddress, d.impSymbol ?: @""];
}

+ (SCIDexKitDescriptor *)descriptorForImage:(SCIDexKitImageInfo *)image className:(NSString *)className selectorName:(NSString *)selectorName classMethod:(BOOL)classMethod method:(Method)m score:(NSInteger)score dlInfo:(Dl_info *)info {
    NSString *sign = classMethod ? @"+" : @"-";
    SCIDexKitDescriptor *d = [SCIDexKitDescriptor new];
    d.imageBasename = image.basename ?: @"";
    d.imagePath = image.path ?: @"";
    d.className = className ?: @"";
    d.selectorName = selectorName ?: @"";
    d.classMethod = classMethod;
    d.typeEncoding = [self typeEncodingForMethod:m];
    d.overrideKey = [SCIDexKitStore overrideKeyForImage:d.imageBasename sign:sign className:d.className selector:d.selectorName];
    d.observedKey = [SCIDexKitStore observedKeyForImage:d.imageBasename sign:sign className:d.className selector:d.selectorName];
    d.curatedScore = score;
    [self fillClassificationForDescriptor:d method:m dlInfo:info];
    [self fillStateForDescriptor:d];
    return d;
}

+ (void)addLegacyActiveOverridesToMap:(NSMutableDictionary<NSString *, SCIDexKitDescriptor *> *)map {
    for (NSString *key in [SCIDexKitStore activeOverrideKeys]) {
        if (map[key]) continue;
        NSString *image = nil, *sign = nil, *cls = nil, *sel = nil;
        if (![SCIDexKitStore parseBoolKey:key image:&image sign:&sign className:&cls selector:&sel]) continue;
        SCIDexKitDescriptor *d = [SCIDexKitDescriptor new];
        d.imageBasename = image ?: @"?";
        d.imagePath = @"";
        d.className = cls ?: @"";
        d.selectorName = sel ?: @"";
        d.classMethod = [sign isEqualToString:@"+"];
        d.typeEncoding = @"";
        d.overrideKey = key;
        d.observedKey = [SCIDexKitStore observedKeyForOverrideKey:key];
        d.unavailable = YES;
        d.unavailableReason = @"Unavailable in this build or image not loaded";
        d.curatedScore = 0;
        NSDictionary<NSString *, id> *classification = [SCIDexKitSelectorRules classificationForClassName:d.className
                                                                                                 selector:d.selectorName
                                                                                            imageBasename:d.imageBasename
                                                                                             typeEncoding:d.typeEncoding];
        d.semanticCategory = classification[@"semanticCategory"] ?: @"unknown-bool";
        d.riskLevel = [classification[@"riskLevel"] integerValue];
        d.batchForceAllowed = NO;
        d.observeRecommended = NO;
        d.forceRecommended = NO;
        d.classificationReason = [NSString stringWithFormat:@"legacy override only · %@", classification[@"classificationReason"] ?: @""];
        d.familyKey = classification[@"familyKey"] ?: [SCIDexKitSelectorRules familyKeyForClassName:d.className selector:d.selectorName];
        d.impAddress = 0;
        d.impSymbol = @"";
        d.implementationKey = @"";
        [self fillStateForDescriptor:d];
        map[key] = d;
    }
}

+ (NSArray<SCIDexKitDescriptor *> *)scanDescriptorsWithMode:(SCIDexKitScannerMode)mode query:(NSString *)query {
    NSMutableDictionary<NSString *, SCIDexKitDescriptor *> *byKey = [NSMutableDictionary dictionary];
    NSString *lowerQuery = query.lowercaseString ?: @"";

    for (SCIDexKitImageInfo *image in [SCIDexKitImagePolicy loadedAllowedImages]) {
        unsigned int classCount = 0;
        const char **classNames = objc_copyClassNamesForImage(image.path.UTF8String, &classCount);
        for (unsigned int i = 0; i < classCount; i++) {
            NSString *className = classNames[i] ? @(classNames[i]) : @"";
            if (!className.length) continue;
            Class cls = NSClassFromString(className);
            if (!cls) continue;

            for (int pass = 0; pass < 2; pass++) {
                BOOL classMethod = (pass == 1);
                Class methodClass = classMethod ? object_getClass(cls) : cls;
                if (!methodClass) continue;
                unsigned int methodCount = 0;
                Method *methods = class_copyMethodList(methodClass, &methodCount);
                for (unsigned int mIdx = 0; mIdx < methodCount; mIdx++) {
                    Method m = methods[mIdx];
                    SEL sel = method_getName(m);
                    NSString *selName = NSStringFromSelector(sel);
                    if (![self method:m isEligibleForMode:mode selector:selName]) continue;

                    Dl_info info; memset(&info, 0, sizeof(info));
                    if (dladdr((void *)method_getImplementation(m), &info) == 0) continue;
                    NSString *impBase = info.dli_fname ? @(info.dli_fname).lastPathComponent : @"";
                    if (![impBase isEqualToString:image.basename]) continue;

                    NSInteger score = [SCIDexKitSelectorRules curatedScoreForClassName:className selector:selName];
                    if (mode == SCIDexKitScannerModeCurated && score < 10) continue;
                    NSString *typeEncoding = [self typeEncodingForMethod:m];
                    NSDictionary<NSString *, id> *classification = [SCIDexKitSelectorRules classificationForClassName:className selector:selName imageBasename:image.basename typeEncoding:typeEncoding];
                    NSString *semantic = classification[@"semanticCategory"] ?: @"";
                    NSString *reason = classification[@"classificationReason"] ?: @"";
                    NSString *hay = [NSString stringWithFormat:@"%@ %@ %@ %@ %@ %@ %@", image.basename, className, selName, typeEncoding, semantic, reason, classification[@"familyKey"] ?: @""].lowercaseString;
                    if (lowerQuery.length && ![hay containsString:lowerQuery]) continue;

                    SCIDexKitDescriptor *d = [self descriptorForImage:image className:className selectorName:selName classMethod:classMethod method:m score:score dlInfo:&info];
                    if (d.overrideKey.length) byKey[d.overrideKey] = d;
                }
                if (methods) free(methods);
            }
        }
        if (classNames) free(classNames);
    }
    [self addLegacyActiveOverridesToMap:byKey];
    NSArray *values = [byKey.allValues sortedArrayUsingComparator:^NSComparisonResult(SCIDexKitDescriptor *a, SCIDexKitDescriptor *b) {
        NSComparisonResult c = [a.imageBasename caseInsensitiveCompare:b.imageBasename];
        if (c != NSOrderedSame) return c;
        c = [a.className caseInsensitiveCompare:b.className];
        if (c != NSOrderedSame) return c;
        return [a.selectorName caseInsensitiveCompare:b.selectorName];
    }];
    return values;
}

@end
