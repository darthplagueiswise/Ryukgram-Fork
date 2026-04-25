#import "SCIExpFlags.h"
#import "SCIExpCallsiteResolver.h"
#import <objc/runtime.h>

typedef void (*SCIRecordInternalUseIMP)(id, SEL, unsigned long long, NSString *, NSString *, BOOL, BOOL, BOOL, void *);
static SCIRecordInternalUseIMP orig_SCIRecordInternalUse = NULL;

static void hook_SCIRecordInternalUse(id self,
                                      SEL _cmd,
                                      unsigned long long specifier,
                                      NSString *functionName,
                                      NSString *specifierName,
                                      BOOL defaultValue,
                                      BOOL resultValue,
                                      BOOL forcedValue,
                                      void *callerAddress) {
    NSString *resolved = specifierName;
    if (!resolved.length || [resolved isEqualToString:@"unknown"]) {
        NSString *caller = SCIExpDescribeCallsite(callerAddress);
        if (caller.length && ![caller isEqualToString:@"unknown"]) {
            resolved = [@"callsite " stringByAppendingString:caller];
        } else {
            resolved = @"unknown";
        }
    }

    if (orig_SCIRecordInternalUse) {
        orig_SCIRecordInternalUse(self, _cmd, specifier, functionName, resolved, defaultValue, resultValue, forcedValue, callerAddress);
    }
}

__attribute__((constructor)) static void SCIInstallInternalUseCallsiteResolverBridge(void) {
    Class cls = NSClassFromString(@"SCIExpFlags");
    if (!cls) return;
    Class meta = object_getClass(cls);
    if (!meta) return;

    SEL sel = @selector(recordInternalUseSpecifier:functionName:specifierName:defaultValue:resultValue:forcedValue:callerAddress:);
    Method m = class_getClassMethod(cls, sel);
    if (!m) m = class_getInstanceMethod(meta, sel);
    if (!m) return;

    orig_SCIRecordInternalUse = (SCIRecordInternalUseIMP)method_setImplementation(m, (IMP)hook_SCIRecordInternalUse);
    NSLog(@"[RyukGram][MC] InternalUse callsite resolver bridge installed original=%p", orig_SCIRecordInternalUse);
}
