// The legacy DATA-param backend depended on the removed
// IGMobileConfigBooleanValueForInternalUse reader. Disable only that backend at
// runtime so the browser cannot claim a descriptor patch succeeded.
#import "SCICSymbolStub.h"
#import <objc/runtime.h>
#import <substrate.h>

static BOOL sci_noParamSymbol(id self __unused, SEL _cmd __unused, NSString *name __unused) { return NO; }
static BOOL sci_noParamObserve(id self __unused, SEL _cmd __unused, BOOL observe __unused, NSString *name __unused) { return NO; }
static BOOL sci_noParamForce(id self __unused, SEL _cmd __unused, NSNumber *value __unused, NSString *name __unused) { return NO; }

__attribute__((constructor)) static void SCIDisableRemovedIGMCDescriptorBackend(void) {
	@autoreleasepool {
		Class cls = objc_getClass("SCICSymbolStub");
		Class meta = cls ? object_getClass(cls) : Nil;
		if (!meta) return;
		SEL isParam = @selector(isParamDescriptorSymbol:);
		SEL canForce = @selector(canForceAsParamDescriptor:);
		SEL setObserve = @selector(setParamDescriptorObserve:forSymbol:);
		SEL setForce = @selector(setParamDescriptorForce:forSymbol:);
		if (class_getInstanceMethod(meta, isParam)) MSHookMessageEx(meta, isParam, (IMP)sci_noParamSymbol, NULL);
		if (class_getInstanceMethod(meta, canForce)) MSHookMessageEx(meta, canForce, (IMP)sci_noParamSymbol, NULL);
		if (class_getInstanceMethod(meta, setObserve)) MSHookMessageEx(meta, setObserve, (IMP)sci_noParamObserve, NULL);
		if (class_getInstanceMethod(meta, setForce)) MSHookMessageEx(meta, setForce, (IMP)sci_noParamForce, NULL);
	}
}
