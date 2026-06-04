#import "SCIMobileConfigRuntime.h"
#import "../../Utils.h"
#import <objc/runtime.h>
#import <substrate.h>

#define SCI_MC_RECORD(pid, kind, ret, def) \
    [SCIMobileConfigRuntime recordParamID:(unsigned long long)(pid) type:(kind) returned:(ret) defaultValue:(def) sourceObject:self selector:NSStringFromSelector(_cmd)]

#define SCI_MC_OVERRIDE(pid, kind, ret) [SCIMobileConfigRuntime overrideForParamID:(unsigned long long)(pid) type:(kind) original:(ret)]

#define DEFINE_MC_SLOT(N) \
static BOOL (*orig_bool_##N)(id, SEL, unsigned long long); \
static BOOL new_bool_##N(id self, SEL _cmd, unsigned long long pid) { BOOL v = orig_bool_##N ? orig_bool_##N(self,_cmd,pid) : NO; SCI_MC_RECORD(pid,@"bool",@(v),nil); id o = SCI_MC_OVERRIDE(pid,@"bool",@(v)); return o ? [o boolValue] : v; } \
static BOOL (*orig_bool_opt_##N)(id, SEL, unsigned long long, id); \
static BOOL new_bool_opt_##N(id self, SEL _cmd, unsigned long long pid, id opt) { BOOL v = orig_bool_opt_##N ? orig_bool_opt_##N(self,_cmd,pid,opt) : NO; SCI_MC_RECORD(pid,@"bool",@(v),nil); id o = SCI_MC_OVERRIDE(pid,@"bool",@(v)); return o ? [o boolValue] : v; } \
static BOOL (*orig_bool_def_##N)(id, SEL, unsigned long long, BOOL); \
static BOOL new_bool_def_##N(id self, SEL _cmd, unsigned long long pid, BOOL def) { BOOL v = orig_bool_def_##N ? orig_bool_def_##N(self,_cmd,pid,def) : def; SCI_MC_RECORD(pid,@"bool",@(v),@(def)); id o = SCI_MC_OVERRIDE(pid,@"bool",@(v)); return o ? [o boolValue] : v; } \
static BOOL (*orig_bool_opt_def_##N)(id, SEL, unsigned long long, id, BOOL); \
static BOOL new_bool_opt_def_##N(id self, SEL _cmd, unsigned long long pid, id opt, BOOL def) { BOOL v = orig_bool_opt_def_##N ? orig_bool_opt_def_##N(self,_cmd,pid,opt,def) : def; SCI_MC_RECORD(pid,@"bool",@(v),@(def)); id o = SCI_MC_OVERRIDE(pid,@"bool",@(v)); return o ? [o boolValue] : v; } \
static long long (*orig_int_##N)(id, SEL, unsigned long long); \
static long long new_int_##N(id self, SEL _cmd, unsigned long long pid) { long long v = orig_int_##N ? orig_int_##N(self,_cmd,pid) : 0; SCI_MC_RECORD(pid,@"int",@(v),nil); id o = SCI_MC_OVERRIDE(pid,@"int",@(v)); return o ? [o longLongValue] : v; } \
static long long (*orig_int_opt_##N)(id, SEL, unsigned long long, id); \
static long long new_int_opt_##N(id self, SEL _cmd, unsigned long long pid, id opt) { long long v = orig_int_opt_##N ? orig_int_opt_##N(self,_cmd,pid,opt) : 0; SCI_MC_RECORD(pid,@"int",@(v),nil); id o = SCI_MC_OVERRIDE(pid,@"int",@(v)); return o ? [o longLongValue] : v; } \
static long long (*orig_int_def_##N)(id, SEL, unsigned long long, long long); \
static long long new_int_def_##N(id self, SEL _cmd, unsigned long long pid, long long def) { long long v = orig_int_def_##N ? orig_int_def_##N(self,_cmd,pid,def) : def; SCI_MC_RECORD(pid,@"int",@(v),@(def)); id o = SCI_MC_OVERRIDE(pid,@"int",@(v)); return o ? [o longLongValue] : v; } \
static long long (*orig_int_opt_def_##N)(id, SEL, unsigned long long, id, long long); \
static long long new_int_opt_def_##N(id self, SEL _cmd, unsigned long long pid, id opt, long long def) { long long v = orig_int_opt_def_##N ? orig_int_opt_def_##N(self,_cmd,pid,opt,def) : def; SCI_MC_RECORD(pid,@"int",@(v),@(def)); id o = SCI_MC_OVERRIDE(pid,@"int",@(v)); return o ? [o longLongValue] : v; } \
static double (*orig_double_##N)(id, SEL, unsigned long long); \
static double new_double_##N(id self, SEL _cmd, unsigned long long pid) { double v = orig_double_##N ? orig_double_##N(self,_cmd,pid) : 0; SCI_MC_RECORD(pid,@"double",@(v),nil); id o = SCI_MC_OVERRIDE(pid,@"double",@(v)); return o ? [o doubleValue] : v; } \
static double (*orig_double_opt_##N)(id, SEL, unsigned long long, id); \
static double new_double_opt_##N(id self, SEL _cmd, unsigned long long pid, id opt) { double v = orig_double_opt_##N ? orig_double_opt_##N(self,_cmd,pid,opt) : 0; SCI_MC_RECORD(pid,@"double",@(v),nil); id o = SCI_MC_OVERRIDE(pid,@"double",@(v)); return o ? [o doubleValue] : v; } \
static double (*orig_double_def_##N)(id, SEL, unsigned long long, double); \
static double new_double_def_##N(id self, SEL _cmd, unsigned long long pid, double def) { double v = orig_double_def_##N ? orig_double_def_##N(self,_cmd,pid,def) : def; SCI_MC_RECORD(pid,@"double",@(v),@(def)); id o = SCI_MC_OVERRIDE(pid,@"double",@(v)); return o ? [o doubleValue] : v; } \
static double (*orig_double_opt_def_##N)(id, SEL, unsigned long long, id, double); \
static double new_double_opt_def_##N(id self, SEL _cmd, unsigned long long pid, id opt, double def) { double v = orig_double_opt_def_##N ? orig_double_opt_def_##N(self,_cmd,pid,opt,def) : def; SCI_MC_RECORD(pid,@"double",@(v),@(def)); id o = SCI_MC_OVERRIDE(pid,@"double",@(v)); return o ? [o doubleValue] : v; } \
static id (*orig_string_##N)(id, SEL, unsigned long long); \
static id new_string_##N(id self, SEL _cmd, unsigned long long pid) { id v = orig_string_##N ? orig_string_##N(self,_cmd,pid) : nil; SCI_MC_RECORD(pid,@"string",v,nil); id o = SCI_MC_OVERRIDE(pid,@"string",v); return o ?: v; } \
static id (*orig_string_opt_##N)(id, SEL, unsigned long long, id); \
static id new_string_opt_##N(id self, SEL _cmd, unsigned long long pid, id opt) { id v = orig_string_opt_##N ? orig_string_opt_##N(self,_cmd,pid,opt) : nil; SCI_MC_RECORD(pid,@"string",v,nil); id o = SCI_MC_OVERRIDE(pid,@"string",v); return o ?: v; } \
static id (*orig_string_def_##N)(id, SEL, unsigned long long, id); \
static id new_string_def_##N(id self, SEL _cmd, unsigned long long pid, id def) { id v = orig_string_def_##N ? orig_string_def_##N(self,_cmd,pid,def) : def; SCI_MC_RECORD(pid,@"string",v,def); id o = SCI_MC_OVERRIDE(pid,@"string",v); return o ?: v; } \
static id (*orig_string_opt_def_##N)(id, SEL, unsigned long long, id, id); \
static id new_string_opt_def_##N(id self, SEL _cmd, unsigned long long pid, id opt, id def) { id v = orig_string_opt_def_##N ? orig_string_opt_def_##N(self,_cmd,pid,opt,def) : def; SCI_MC_RECORD(pid,@"string",v,def); id o = SCI_MC_OVERRIDE(pid,@"string",v); return o ?: v; }

DEFINE_MC_SLOT(0)
DEFINE_MC_SLOT(1)
DEFINE_MC_SLOT(2)
DEFINE_MC_SLOT(3)
DEFINE_MC_SLOT(4)
DEFINE_MC_SLOT(5)
DEFINE_MC_SLOT(6)

static NSMutableSet<NSString *> *sInstalled;

static void sciHook(Class cls, NSString *selName, IMP newImp, IMP *origOut) {
    if (!cls || !selName.length || !newImp || !origOut) return;
    SEL sel = NSSelectorFromString(selName);
    if (!class_getInstanceMethod(cls, sel)) return;
    if (!sInstalled) sInstalled = [NSMutableSet new];
    NSString *key = [NSString stringWithFormat:@"%@:%@", NSStringFromClass(cls), selName];
    if ([sInstalled containsObject:key]) return;
    [sInstalled addObject:key];
    MSHookMessageEx(cls, sel, newImp, origOut);
}


static id (*orig_dog_init)(id, SEL, id, id, id);
static id new_dog_init(id self, SEL _cmd, id launcherSet, id networker, id logger) {
    id obj = orig_dog_init ? orig_dog_init(self, _cmd, launcherSet, networker, logger) : self;
    if ([SCIMobileConfigRuntime runtimeHooksEnabled]) {
        [SCIMobileConfigRuntime noteLiveObject:obj role:@"IGDogfooderProd" source:NSStringFromSelector(_cmd)];
        if (launcherSet) [SCIMobileConfigRuntime noteLiveObject:launcherSet role:@"IGUserLauncherSet" source:@"IGDogfooderProd._launcherSet"];
        if (networker) [SCIMobileConfigRuntime noteLiveObject:networker role:@"IGAPIClient/networker" source:@"IGDogfooderProd._networker"];
        if (logger) [SCIMobileConfigRuntime noteLiveObject:logger role:@"IGDogfoodingLogger" source:@"IGDogfooderProd._logger"];
    }
    return obj;
}

static void (*orig_dog_check_updates)(id, SEL, id);
static void new_dog_check_updates(id self, SEL _cmd, id completion) {
    if ([SCIMobileConfigRuntime runtimeHooksEnabled]) [SCIMobileConfigRuntime noteLiveObject:self role:@"IGDogfooderProd" source:NSStringFromSelector(_cmd)];
    if (orig_dog_check_updates) orig_dog_check_updates(self, _cmd, completion);
}

static void (*orig_dog_check_build)(id, SEL, id, BOOL, id);
static void new_dog_check_build(id self, SEL _cmd, id build, BOOL useCache, id completion) {
    if ([SCIMobileConfigRuntime runtimeHooksEnabled]) [SCIMobileConfigRuntime noteLiveObject:self role:@"IGDogfooderProd" source:NSStringFromSelector(_cmd)];
    if (orig_dog_check_build) orig_dog_check_build(self, _cmd, build, useCache, completion);
}

static void (*orig_dog_trigger_update)(id, SEL, NSInteger, id);
static void new_dog_trigger_update(id self, SEL _cmd, NSInteger mode, id completion) {
    if ([SCIMobileConfigRuntime runtimeHooksEnabled]) [SCIMobileConfigRuntime noteLiveObject:self role:@"IGDogfooderProd" source:NSStringFromSelector(_cmd)];
    if (orig_dog_trigger_update) orig_dog_trigger_update(self, _cmd, mode, completion);
}

static void sciInstallMobileConfigLiveContextHooks(void) {
    Class dog = NSClassFromString(@"IGDogfooderProd");
    sciHook(dog, @"initWithLauncherSet:networker:logger:", (IMP)new_dog_init, (IMP *)&orig_dog_init);
    sciHook(dog, @"checkAvailableAppUpdatesWithCompletion:", (IMP)new_dog_check_updates, (IMP *)&orig_dog_check_updates);
    sciHook(dog, @"checkBuildStatusForBuild:useCacheResultIfAvailable:completion:", (IMP)new_dog_check_build, (IMP *)&orig_dog_check_build);
    sciHook(dog, @"triggerUpdateWithMode:completion:", (IMP)new_dog_trigger_update, (IMP *)&orig_dog_trigger_update);
}


#define INSTALL_SLOT(cls, N) do { \
    sciHook(cls,@"getBool:",(IMP)new_bool_##N,(IMP *)&orig_bool_##N); \
    sciHook(cls,@"getBool:withOptions:",(IMP)new_bool_opt_##N,(IMP *)&orig_bool_opt_##N); \
    sciHook(cls,@"getBool:withDefault:",(IMP)new_bool_def_##N,(IMP *)&orig_bool_def_##N); \
    sciHook(cls,@"getBool:withOptions:withDefault:",(IMP)new_bool_opt_def_##N,(IMP *)&orig_bool_opt_def_##N); \
    sciHook(cls,@"getInt64:",(IMP)new_int_##N,(IMP *)&orig_int_##N); \
    sciHook(cls,@"getInt64:withOptions:",(IMP)new_int_opt_##N,(IMP *)&orig_int_opt_##N); \
    sciHook(cls,@"getInt64:withDefault:",(IMP)new_int_def_##N,(IMP *)&orig_int_def_##N); \
    sciHook(cls,@"getInt64:withOptions:withDefault:",(IMP)new_int_opt_def_##N,(IMP *)&orig_int_opt_def_##N); \
    sciHook(cls,@"getDouble:",(IMP)new_double_##N,(IMP *)&orig_double_##N); \
    sciHook(cls,@"getDouble:withOptions:",(IMP)new_double_opt_##N,(IMP *)&orig_double_opt_##N); \
    sciHook(cls,@"getDouble:withDefault:",(IMP)new_double_def_##N,(IMP *)&orig_double_def_##N); \
    sciHook(cls,@"getDouble:withOptions:withDefault:",(IMP)new_double_opt_def_##N,(IMP *)&orig_double_opt_def_##N); \
    sciHook(cls,@"getString:",(IMP)new_string_##N,(IMP *)&orig_string_##N); \
    sciHook(cls,@"getString:withOptions:",(IMP)new_string_opt_##N,(IMP *)&orig_string_opt_##N); \
    sciHook(cls,@"getString:withDefault:",(IMP)new_string_def_##N,(IMP *)&orig_string_def_##N); \
    sciHook(cls,@"getString:withOptions:withDefault:",(IMP)new_string_opt_def_##N,(IMP *)&orig_string_opt_def_##N); \
} while (0)

static void sciInstallMobileConfigRuntimeHooks(void) {
    if (![SCIMobileConfigRuntime runtimeHooksEnabled]) return;
    Class c0 = NSClassFromString(@"IGMobileConfigUserSessionContextManager");
    Class c1 = NSClassFromString(@"IGMobileConfigSessionlessContextManager");
    Class c2 = NSClassFromString(@"IGMobileConfigContextManager");
    Class c3 = NSClassFromString(@"FBMobileConfigUserSessionContext");
    Class c4 = NSClassFromString(@"FBMobileConfigSessionlessContext");
    Class c5 = NSClassFromString(@"FBMobileConfigContext");
    Class c6 = NSClassFromString(@"FBMobileConfigAPI");
    INSTALL_SLOT(c0, 0);
    INSTALL_SLOT(c1, 1);
    INSTALL_SLOT(c2, 2);
    INSTALL_SLOT(c3, 3);
    INSTALL_SLOT(c4, 4);
    INSTALL_SLOT(c5, 5);
    INSTALL_SLOT(c6, 6);
    sciInstallMobileConfigLiveContextHooks();
}

static void sciScheduleMobileConfigRuntimeHookRetry(NSTimeInterval delay) {
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(delay * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
        sciInstallMobileConfigRuntimeHooks();
    });
}

void SCIInstallMobileConfigRuntimeHooksIfNeeded(void) {
    if (![SCIMobileConfigRuntime runtimeHooksEnabled]) return;
    sciInstallMobileConfigRuntimeHooks();
    sciScheduleMobileConfigRuntimeHookRetry(1.0);
    sciScheduleMobileConfigRuntimeHookRetry(2.0);
    sciScheduleMobileConfigRuntimeHookRetry(5.0);
}

%ctor {
    // Runtime capture is installed on demand by SCIMobileConfigBrowserViewController.
}
