// SCILauncherClientHook.x
// Functional persistence hook for Notes/Dogfooding native writes. If native
// dogfood writes launcher overrides, we persist exactly those tuples and replay
// them on later launches. This is safer than touching Swift toggle delegates.

#import "SCILauncherOverride.h"
#import "SCIDogfoodObjectRuntime.h"
#import <Foundation/Foundation.h>
#import <objc/runtime.h>
#import <substrate.h>
#import <os/log.h>

static BOOL (*orig_overrideLauncher)(id, SEL, id, id, id) = NULL;

static Class SCIClassByNames(NSArray<NSString *> *names) {
    for (NSString *n in names) { if (!n.length) continue; Class c = NSClassFromString(n); if (c) return c; c = objc_getClass(n.UTF8String); if (c) return c; }
    unsigned int count = 0; Class *classes = objc_copyClassList(&count); Class found = Nil;
    for (unsigned int i=0; classes && i<count && !found; i++) { const char *cn = class_getName(classes[i]); if (!cn) continue; NSString *s = [NSString stringWithUTF8String:cn]; for (NSString *n in names) if ([s isEqualToString:n] || [s hasSuffix:n] || [s containsString:n]) { found = classes[i]; break; } }
    if (classes) free(classes); return found;
}

static BOOL new_overrideLauncher(id self, SEL _cmd, id session, id name, id params) {
    BOOL ok = orig_overrideLauncher ? orig_overrideLauncher(self, _cmd, session, name, params) : NO;
    @try {
        [SCIDogfoodObjectRuntime noteAction:@"Dogfooding launcher override" status:(ok?@"native ok":@"native returned NO") detail:@{ @"launcher": name ?: @"", @"params": params ?: @{} }];
        if ([name isKindOfClass:NSString.class] && [params isKindOfClass:NSDictionary.class]) {
            for (id k in (NSDictionary *)params) {
                if (![k isKindOfClass:NSString.class]) continue;
                id v = ((NSDictionary *)params)[k];
                if (v) [SCILauncherOverride persistLauncher:name parameter:k value:v];
            }
        }
    } @catch (__unused id e) {}
    return ok;
}

static void sciInstallLauncherClientHook(void) {
    if (orig_overrideLauncher) return;
    Class cls = SCIClassByNames(@[@"_TtC35IGDogfoodingAssistantLauncherClient35IGDogfoodingAssistantLauncherClient", @"IGDogfoodingAssistantLauncherClient.IGDogfoodingAssistantLauncherClient", @"IGDogfoodingAssistantLauncherClient"]);
    if (!cls) { [SCIDogfoodObjectRuntime noteAction:@"LauncherClient hook" status:@"class not loaded" detail:@"IGDogfoodingAssistantLauncherClient"]; return; }
    SEL sel = @selector(overrideLauncherWithUserSession:launcherName:parametersToValues:);
    if (!class_getInstanceMethod(cls, sel)) { [SCIDogfoodObjectRuntime noteAction:@"LauncherClient hook" status:@"selector missing" detail:NSStringFromClass(cls)]; return; }
    IMP orig = NULL; MSHookMessageEx(cls, sel, (IMP)new_overrideLauncher, &orig); orig_overrideLauncher = (BOOL(*)(id,SEL,id,id,id))orig;
    [SCIDogfoodObjectRuntime noteAction:@"LauncherClient hook" status:(orig?@"hooked":@"failed") detail:[NSString stringWithFormat:@"%s#overrideLauncherWithUserSession:launcherName:parametersToValues:", class_getName(cls)]];
}

%ctor {
    @autoreleasepool {
        sciInstallLauncherClientHook();
        double d[] = {1.0, 3.0, 6.0, 10.0};
        for (NSUInteger i=0;i<sizeof(d)/sizeof(d[0]);i++) dispatch_after(dispatch_time(DISPATCH_TIME_NOW,(int64_t)(d[i]*NSEC_PER_SEC)),dispatch_get_main_queue(),^{ sciInstallLauncherClientHook(); });
    }
}
