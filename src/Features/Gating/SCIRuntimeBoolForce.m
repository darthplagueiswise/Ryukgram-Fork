#import "SCIRuntimeBoolForce.h"
#import <objc/runtime.h>

@implementation SCIRuntimeBoolForce

// class+selector keys already forced, so re-entry / multiple callers are no-ops.
static NSMutableSet<NSString *> *SCIForcedKeys(void) {
    static NSMutableSet *set;
    static dispatch_once_t once;
    dispatch_once(&once, ^{ set = [NSMutableSet set]; });
    return set;
}

+ (BOOL)forceClassNamed:(NSString *)className
               selector:(NSString *)selectorName
            classMethod:(BOOL)classMethod
                  value:(BOOL)value {
    if (!className.length || !selectorName.length) return NO;

    Class cls = objc_getClass(className.UTF8String);
    if (!cls) return NO;

    // Class methods live on the metaclass; class_getInstanceMethod on the
    // metaclass is the correct way to reach a +method.
    Class target = classMethod ? object_getClass(cls) : cls;
    SEL sel = NSSelectorFromString(selectorName);
    Method m = class_getInstanceMethod(target, sel);
    if (!m) return NO;

    // Must be a true no-argument getter: only self + _cmd.
    if (method_getNumberOfArguments(m) != 2) return NO;

    // Return type must be BOOL/_Bool (arm64: 'B') or signed/unsigned char
    // ('c'/'C') for older-style BOOL typedefs.
    char ret[8] = {0};
    method_getReturnType(m, ret, sizeof(ret));
    if (!(ret[0] == 'B' || ret[0] == 'c' || ret[0] == 'C')) return NO;

    NSString *key = [NSString stringWithFormat:@"%@%@.%@",
                     classMethod ? @"+" : @"-", className, selectorName];
    NSMutableSet *forced = SCIForcedKeys();
    @synchronized (forced) {
        if ([forced containsObject:key]) return YES;
    }

    // Reuse the original method's exact type encoding so the trampoline ABI
    // matches the getter precisely. The block captures a constant and does no
    // Objective-C work, so it cannot recurse through MobileConfig.
    const char *types = method_getTypeEncoding(m);
    IMP imp = imp_implementationWithBlock(^BOOL(__unused id _self) { return value; });
    class_replaceMethod(target, sel, imp, types);

    @synchronized (forced) { [forced addObject:key]; }
    return YES;
}

+ (void)forceInstanceSelectors:(NSArray<NSString *> *)selectors
                   onClassNamed:(NSString *)className
                          value:(BOOL)value {
    for (NSString *sel in selectors) {
        [self forceClassNamed:className selector:sel classMethod:NO value:value];
    }
}

+ (void)forceClassSelectors:(NSArray<NSString *> *)selectors
                onClassNamed:(NSString *)className
                       value:(BOOL)value {
    for (NSString *sel in selectors) {
        [self forceClassNamed:className selector:sel classMethod:YES value:value];
    }
}

@end
