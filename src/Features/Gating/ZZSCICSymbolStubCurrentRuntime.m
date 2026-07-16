// The legacy param-descriptor backend depended on the removed
// IGMobileConfigBooleanValueForInternalUse reader. Disable only that backend so
// the Unified Runtime Browser cannot claim a DATA descriptor patch succeeded.
#import "SCICSymbolStub.h"

@implementation SCICSymbolStub (CurrentRuntimeNoLegacyIGMC)
+ (BOOL)isParamDescriptorSymbol:(NSString *)name { (void)name; return NO; }
+ (BOOL)canForceAsParamDescriptor:(NSString *)name { (void)name; return NO; }
+ (BOOL)setParamDescriptorObserve:(BOOL)observe forSymbol:(NSString *)name { (void)observe; (void)name; return NO; }
+ (BOOL)setParamDescriptorForce:(NSNumber *)value forSymbol:(NSString *)name { (void)value; (void)name; return NO; }
@end
