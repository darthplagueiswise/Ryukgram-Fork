#import "SCIExpFlags.h"
#import "SCIMobileConfigMapping.h"
#import <objc/runtime.h>
#import <substrate.h>

static BOOL SCIMCSessionlessBool(id obj, BOOL fallback) {
    if (!obj) return fallback;
    if ([obj respondsToSelector:@selector(boolValue)]) return [obj boolValue];
    NSString *s = [[obj description] lowercaseString];
    if ([s isEqualToString:@"true"] || [s isEqualToString:@"yes"] || [s isEqualToString:@"1"]) return YES;
    if ([s isEqualToString:@"false"] || [s isEqualToString:@"no"] || [s isEqualToString:@"0"]) return NO;
    return fallback;
}

static void SCIMCSessionlessRecord(id self, SEL _cmd, unsigned long long pid, BOOL def, BOOL original) {
    [SCIExpFlags recordMCParamID:pid
                            type:SCIExpMCTypeBool
                    defaultValue:def ? @"YES" : @"NO"
                   originalValue:original ? @"YES" : @"NO"
                    contextClass:NSStringFromClass(object_getClass(self))
                    selectorName:NSStringFromSelector(_cmd)];
}

static BOOL (*orig_sl_getBool)(id, SEL, unsigned long long);
static BOOL new_sl_getBool(id self, SEL _cmd, unsigned long long pid) {
    BOOL v = orig_sl_getBool ? orig_sl_getBool(self, _cmd, pid) : NO;
    SCIMCSessionlessRecord(self, _cmd, pid, v, v);
    id forced = [SCIMobileConfigMapping overrideObjectForParamID:pid typeName:@"bool"];
    return forced ? SCIMCSessionlessBool(forced, v) : v;
}

static BOOL (*orig_sl_getBoolDef)(id, SEL, unsigned long long, BOOL);
static BOOL new_sl_getBoolDef(id self, SEL _cmd, unsigned long long pid, BOOL def) {
    BOOL v = orig_sl_getBoolDef ? orig_sl_getBoolDef(self, _cmd, pid, def) : def;
    SCIMCSessionlessRecord(self, _cmd, pid, def, v);
    id forced = [SCIMobileConfigMapping overrideObjectForParamID:pid typeName:@"bool"];
    return forced ? SCIMCSessionlessBool(forced, v) : v;
}

%ctor {
    Class cls = NSClassFromString(@"IGMobileConfigSessionlessContextManager");
    SEL b = NSSelectorFromString(@"getBool:");
    SEL bd = NSSelectorFromString(@"getBool:withDefault:");
    if (class_getInstanceMethod(cls, b)) MSHookMessageEx(cls, b, (IMP)new_sl_getBool, (IMP *)&orig_sl_getBool);
    if (class_getInstanceMethod(cls, bd)) MSHookMessageEx(cls, bd, (IMP)new_sl_getBoolDef, (IMP *)&orig_sl_getBoolDef);
}
