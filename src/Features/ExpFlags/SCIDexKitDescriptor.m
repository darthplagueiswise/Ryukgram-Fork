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
    return d;
}
- (NSString *)ownerDisplayName {
    if (!self.className.length) return @"Unknown owner";
    NSArray *parts = [self.className componentsSeparatedByString:@"."];
    return parts.lastObject.length ? parts.lastObject : self.className;
}
- (NSString *)ownerGroupKey {
    return [NSString stringWithFormat:@"%@|%@|%@", self.imageBasename ?: @"?", self.imagePath ?: @"", self.className ?: @"?"];
}
@end
