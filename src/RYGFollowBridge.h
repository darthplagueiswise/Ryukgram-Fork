// IG 443 made IGFollowController a Swift class: mangled name, no -user getter
// (IGUser lives in the _user ivar), renamed tap handlers.

#import <objc/runtime.h>
#import <objc/message.h>
#import <Foundation/Foundation.h>
#import <substrate.h>

static inline Class rygFollowControllerClass(void) {
    static Class cls;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        cls = NSClassFromString(@"_TtC11IGFollowing18IGFollowController")
           ?: NSClassFromString(@"IGFollowing.IGFollowController")
           ?: NSClassFromString(@"IGFollowController");
    });
    return cls;
}

static inline id rygFollowControllerUser(id ctrl) {
    if (!ctrl) return nil;
    Ivar iv = class_getInstanceVariable(object_getClass(ctrl), "_user");
    if (iv) return object_getIvar(ctrl, iv);
    if ([ctrl respondsToSelector:@selector(user)])
        return ((id (*)(id, SEL))objc_msgSend)(ctrl, @selector(user));
    return nil;
}

static inline id rygFollowControllerIvar(id ctrl, const char *name) {
    if (!ctrl) return nil;
    Ivar iv = class_getInstanceVariable(object_getClass(ctrl), name);
    return iv ? object_getIvar(ctrl, iv) : nil;
}

static inline BOOL rygFollowHook(SEL sel, IMP repl, IMP *orig) {
    Class cls = rygFollowControllerClass();
    if (!cls || !class_getInstanceMethod(cls, sel)) return NO;
    MSHookMessageEx(cls, sel, repl, orig);
    return YES;
}
