#import "SCIExpFlags.h"
#import "SCIMobileConfigMapping.h"

@implementation SCIExpFlags (MobileConfigRuntime)

+ (void)recordMCParamID:(unsigned long long)pid
                   type:(SCIExpMCType)t
           defaultValue:(NSString *)def
          originalValue:(NSString *)original
           contextClass:(NSString *)contextClass
           selectorName:(NSString *)selectorName {
    // This method is called from very hot MobileConfig paths. Keep it cheap:
    // record the ID/default snapshot only and avoid dispatching work to the main queue
    // for every hit. UI/debug enrichment must happen lazily when the menu is opened.
    (void)original;
    (void)contextClass;
    (void)selectorName;
    [self recordMCParamID:pid type:t defaultValue:def];
}

@end
