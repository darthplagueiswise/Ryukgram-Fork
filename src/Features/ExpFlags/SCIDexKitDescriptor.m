#import "SCIDexKitDescriptor.h"

@implementation SCIDexKitDescriptor
- (id)copyWithZone:(NSZone *)zone {
    SCIDexKitDescriptor *d = [[[self class] allocWithZone:zone] init];
    d.imageBasename = self.imageBasename;
    d.imagePath = self.imagePath;
    d.className = self.className;
    d.selectorName = self.selectorName;
    d.classMethod = self.classMethod;
    d.typeEncoding = self.typeEncoding;
    d.overrideKey = self.overrideKey;
    d.observedKey = self.observedKey;
    d.observedKnown = self.observedKnown;
    d.observedValue = self.observedValue;
    d.overrideValue = self.overrideValue;
    d.effectiveState = self.effectiveState;
    d.hookInstalled = self.hookInstalled;
    d.unavailable = self.unavailable;
    d.unavailableReason = self.unavailableReason;
    d.curatedScore = self.curatedScore;
    d.semanticCategory = self.semanticCategory;
    d.riskLevel = self.riskLevel;
    d.batchForceAllowed = self.batchForceAllowed;
    d.observeRecommended = self.observeRecommended;
    d.forceRecommended = self.forceRecommended;
    d.classificationReason = self.classificationReason;
    d.familyKey = self.familyKey;
    d.impAddress = self.impAddress;
    d.impSymbol = self.impSymbol;
    d.implementationKey = self.implementationKey;
    return d;
}

- (NSString *)ownerDisplayName {
    if (!self.className.length) return @"Unknown owner";
    NSArray<NSString *> *parts = [self.className componentsSeparatedByString:@"."];
    NSString *lastPart = parts.lastObject;
    return lastPart.length ? lastPart : self.className;
}

- (NSString *)ownerGroupKey {
    return [NSString stringWithFormat:@"%@|%@|%@", self.imageBasename ?: @"?", self.imagePath ?: @"", self.className ?: @"?"];
}
@end
