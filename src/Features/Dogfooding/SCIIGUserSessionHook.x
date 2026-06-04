#import "SCIDogfoodObjectRuntime.h"
#import <Foundation/Foundation.h>
#import <objc/runtime.h>
#import <substrate.h>

static id (*orig_iguser_userID)(id, SEL) = NULL;
static id (*orig_foauser_userID)(id, SEL) = NULL;

static id new_iguser_userID(id self, SEL _cmd) {
    id ret = orig_iguser_userID ? orig_iguser_userID(self, _cmd) : nil;
    @try { [SCIDogfoodObjectRuntime noteLiveUserSession:self source:@"IGUserSession.userID"]; } @catch (__unused id e) {}
    return ret;
}

static id new_foauser_userID(id self, SEL _cmd) {
    id ret = orig_foauser_userID ? orig_foauser_userID(self, _cmd) : nil;
    @try { [SCIDogfoodObjectRuntime noteLiveUserSession:self source:@"FOAUserSession.userID"]; } @catch (__unused id e) {}
    return ret;
}

static void SCIInstallUserSessionHooks(void) {
    Class ig = NSClassFromString(@"IGUserSession");
    if (ig && [ig instancesRespondToSelector:@selector(userID)] && !orig_iguser_userID) {
        MSHookMessageEx(ig, @selector(userID), (IMP)new_iguser_userID, (IMP *)&orig_iguser_userID);
    }
    Class foa = NSClassFromString(@"FOAUserSession");
    if (foa && [foa instancesRespondToSelector:@selector(userID)] && !orig_foauser_userID) {
        MSHookMessageEx(foa, @selector(userID), (IMP)new_foauser_userID, (IMP *)&orig_foauser_userID);
    }
}

%ctor {
    SCIInstallUserSessionHooks();
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(2 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{ SCIInstallUserSessionHooks(); });
}
