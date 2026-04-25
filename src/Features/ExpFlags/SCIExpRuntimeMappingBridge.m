#import "SCIExpMobileConfigMapping.h"
#import <objc/runtime.h>
#import <objc/message.h>

typedef NSString *(*SCIResolvedNameIMP)(id, SEL, unsigned long long);
typedef NSString *(*SCIMappingSourceIMP)(id, SEL);

static SCIResolvedNameIMP orig_SCIResolvedNameForSpecifier = NULL;
static SCIMappingSourceIMP orig_SCIMappingSourceDescription = NULL;

static id SCISafeCallNoArgObject(id target, SEL sel) {
    if (!target || !sel || ![target respondsToSelector:sel]) return nil;
    @try {
        id (*send)(id, SEL) = (id (*)(id, SEL))objc_msgSend;
        return send(target, sel);
    } @catch (__unused NSException *e) {
        return nil;
    }
}

static NSString *SCITrimmedString(id obj) {
    if (!obj) return nil;
    NSString *s = nil;
    if ([obj isKindOfClass:[NSString class]]) s = (NSString *)obj;
    else if ([obj respondsToSelector:@selector(description)]) s = [obj description];
    if (!s.length) return nil;
    s = [s stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
    if (!s.length || [s isEqualToString:@"(null)"] || [s isEqualToString:@"null"]) return nil;
    return s;
}

static NSString *SCIRuntimeResolvedNameForSpecifier(unsigned long long specifier) {
    Class cls = NSClassFromString(@"FBMobileConfigStartupConfigs");
    if (!cls) return nil;

    id instance = SCISafeCallNoArgObject(cls, NSSelectorFromString(@"getInstance"));
    if (!instance) {
        @try { instance = [[cls alloc] init]; } @catch (__unused NSException *e) { instance = nil; }
    }
    SEL convert = NSSelectorFromString(@"convertSpecifierToParamName:");
    if (!instance || ![instance respondsToSelector:convert]) return nil;

    @try {
        id (*send)(id, SEL, unsigned long long) = (id (*)(id, SEL, unsigned long long))objc_msgSend;
        NSString *name = SCITrimmedString(send(instance, convert, specifier));
        if (name.length) return name;
    } @catch (__unused NSException *e) {
        return nil;
    }
    return nil;
}

static NSString *hook_SCIResolvedNameForSpecifier(id self, SEL _cmd, unsigned long long specifier) {
    NSString *runtimeName = SCIRuntimeResolvedNameForSpecifier(specifier);
    if (runtimeName.length) return runtimeName;
    return orig_SCIResolvedNameForSpecifier ? orig_SCIResolvedNameForSpecifier(self, _cmd, specifier) : nil;
}

static NSString *hook_SCIMappingSourceDescription(id self, SEL _cmd) {
    NSString *base = orig_SCIMappingSourceDescription ? orig_SCIMappingSourceDescription(self, _cmd) : @"none";
    NSString *runtime = NSClassFromString(@"FBMobileConfigStartupConfigs") ? @"available" : @"missing";
    return [NSString stringWithFormat:@"%@ · runtimeConvert=%@", base ?: @"none", runtime];
}

__attribute__((constructor)) static void SCIInstallRuntimeMobileConfigMappingBridge(void) {
    Class cls = NSClassFromString(@"SCIExpMobileConfigMapping");
    if (!cls) return;
    Class meta = object_getClass(cls);
    if (!meta) return;

    SEL resolvedSEL = @selector(resolvedNameForSpecifier:);
    Method resolvedMethod = class_getClassMethod(cls, resolvedSEL);
    if (resolvedMethod) {
        orig_SCIResolvedNameForSpecifier = (SCIResolvedNameIMP)method_setImplementation(resolvedMethod, (IMP)hook_SCIResolvedNameForSpecifier);
    }

    SEL sourceSEL = @selector(mappingSourceDescription);
    Method sourceMethod = class_getClassMethod(cls, sourceSEL);
    if (sourceMethod) {
        orig_SCIMappingSourceDescription = (SCIMappingSourceIMP)method_setImplementation(sourceMethod, (IMP)hook_SCIMappingSourceDescription);
    }

    NSLog(@"[RyukGram][MCMapping] runtime bridge installed resolved=%p source=%p", orig_SCIResolvedNameForSpecifier, orig_SCIMappingSourceDescription);
}
