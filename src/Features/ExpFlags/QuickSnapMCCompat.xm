#import "../../Utils.h"
#import <objc/runtime.h>
#import <substrate.h>

static BOOL rgQSOn(void) { return [SCIUtils getBoolPref:@"igt_quicksnap"]; }

static BOOL rgQSName(id key) {
    if (![key isKindOfClass:[NSString class]]) return NO;
    NSString *s = [(NSString *)key lowercaseString];
    return [s containsString:@"quicksnap"] || [s containsString:@"quick_snap"] || [s containsString:@"instants"] || [s containsString:@"xma_quicksnap"];
}

static BOOL (*orig_igmc_bool_key)(id, SEL, id) = NULL;
static BOOL hook_igmc_bool_key(id self, SEL _cmd, id key) {
    if (rgQSOn() && rgQSName(key)) return YES;
    return orig_igmc_bool_key ? orig_igmc_bool_key(self, _cmd, key) : NO;
}

static BOOL (*orig_igmc_bool_key_def)(id, SEL, id, BOOL) = NULL;
static BOOL hook_igmc_bool_key_def(id self, SEL _cmd, id key, BOOL def) {
    if (rgQSOn() && rgQSName(key)) return YES;
    return orig_igmc_bool_key_def ? orig_igmc_bool_key_def(self, _cmd, key, def) : def;
}

static void rgHookInst(NSString *className, NSString *selName, IMP repl, IMP *orig) {
    Class cls = NSClassFromString(className);
    if (!cls) return;
    SEL sel = NSSelectorFromString(selName);
    if (!class_getInstanceMethod(cls, sel)) return;
    MSHookMessageEx(cls, sel, repl, orig);
}

%ctor {
    if (!rgQSOn()) return;
    rgHookInst(@"IGMobileConfigContextManager", @"ig_boolForKey:", (IMP)hook_igmc_bool_key, (IMP *)&orig_igmc_bool_key);
    rgHookInst(@"IGMobileConfigContextManager", @"ig_boolForKey:defaultValue:", (IMP)hook_igmc_bool_key_def, (IMP *)&orig_igmc_bool_key_def);
    rgHookInst(@"IGMobileConfigUserSessionContextManager", @"ig_boolForKey:", (IMP)hook_igmc_bool_key, (IMP *)&orig_igmc_bool_key);
    rgHookInst(@"IGMobileConfigUserSessionContextManager", @"ig_boolForKey:defaultValue:", (IMP)hook_igmc_bool_key_def, (IMP *)&orig_igmc_bool_key_def);
}
