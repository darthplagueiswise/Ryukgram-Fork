#import "SCIExpFlags.h"
#import "SCIMachODexKitResolver.h"
#import <objc/runtime.h>

typedef void (*SCIRecordInternalUseIMP)(id,
                                        SEL,
                                        unsigned long long,
                                        NSString *,
                                        NSString *,
                                        BOOL,
                                        BOOL,
                                        BOOL,
                                        void *);

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
    NSString *resolvedName = specifierName;

    SCIMachODexKitResolvedName *resolved =
        [[SCIMachODexKitResolver sharedResolver] resolvedNameForSpecifier:specifier
                                                             functionName:functionName
                                                             existingName:specifierName
                                                            callerAddress:callerAddress];

    if (resolved.name.length) {
        resolvedName = resolved.name;
    }

    if (orig_SCIRecordInternalUse) {
        orig_SCIRecordInternalUse(self,
                                  _cmd,
                                  specifier,
                                  functionName,
                                  resolvedName,
                                  defaultValue,
                                  resultValue,
                                  forcedValue,
                                  callerAddress);
    }
}

__attribute__((constructor)) static void SCIInstallMachODexKitResolverBridge(void) {
    Class cls = NSClassFromString(@"SCIExpFlags");
    if (!cls) return;

    SEL sel = @selector(recordInternalUseSpecifier:functionName:specifierName:defaultValue:resultValue:forcedValue:callerAddress:);
    Method method = class_getClassMethod(cls, sel);
    if (!method) return;

    orig_SCIRecordInternalUse = (SCIRecordInternalUseIMP)method_setImplementation(method, (IMP)hook_SCIRecordInternalUse);

    NSLog(@"[RyukGram][MachoDex] InternalUse resolver bridge installed");
}
