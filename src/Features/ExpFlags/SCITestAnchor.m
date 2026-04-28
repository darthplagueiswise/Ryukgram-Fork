#import "SCIExpFlags.h"
#import "SCIMobileConfigMapping.h"

@implementation SCIExpFlags (MobileConfigRuntime)

+ (void)recordMCParamID:(unsigned long long)pid
                   type:(SCIExpMCType)t
           defaultValue:(NSString *)def
          originalValue:(NSString *)original
           contextClass:(NSString *)contextClass
           selectorName:(NSString *)selectorName {
    [self recordMCParamID:pid type:t defaultValue:def];

    NSString *resolved = [SCIMobileConfigMapping resolvedNameForParamID:pid];
    NSString *source = [SCIMobileConfigMapping sourceForParamID:pid];
    NSString *typeName = @"unknown";
    switch (t) {
        case SCIExpMCTypeBool: typeName = @"bool"; break;
        case SCIExpMCTypeInt: typeName = @"int64"; break;
        case SCIExpMCTypeDouble: typeName = @"double"; break;
        case SCIExpMCTypeString: typeName = @"string"; break;
    }
    id forcedObj = [SCIMobileConfigMapping overrideObjectForParamID:pid typeName:typeName];
    NSString *forcedText = forcedObj ? [forcedObj description] : nil;

    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(20 * NSEC_PER_MSEC)), dispatch_get_main_queue(), ^{
        for (SCIExpMCObservation *o in [SCIExpFlags allMCObservations]) {
            if (o.paramID != pid) continue;
            if (resolved.length) o.resolvedName = resolved;
            if (source.length) o.source = source;
            if (contextClass.length) o.contextClass = contextClass;
            if (selectorName.length) o.selectorName = selectorName;
            if (original.length) o.lastOriginalValue = original;
            if (forcedText.length) o.overrideValue = forcedText;
            break;
        }
    });
}

@end
