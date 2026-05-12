#import "../../Utils.h"
#import <objc/runtime.h>
#import <pthread.h>

static NSMutableDictionary<NSString *, NSValue *> *gSCIOrigMutualIMPs;
static pthread_mutex_t gSCIMutualLock = PTHREAD_MUTEX_INITIALIZER;

static NSArray<NSString *> *SCIMutualPrefsForSelector(NSString *selectorName) {
    if (!selectorName.length) return nil;
    NSString *l = selectorName.lowercaseString;
    if ([l containsString:@"icebreaker"] || [l containsString:@"mutuallyliked"] || [l containsString:@"stickercard"]) return @[@"igt_icebreaker", @"igt_mutual_interest"];
    if ([l containsString:@"mutualfollow"] || [l containsString:@"mutualinterest"] || ([l containsString:@"mutual"] && [l containsString:@"interest"])) return @[@"igt_mutual_interest"];
    if ([l containsString:@"largercard"] || [l containsString:@"infinitereels"] || [l containsString:@"chaining"]) return @[@"igt_icebreaker"];
    return nil;
}

static NSString *SCIMutualKey(Class cls, NSString *selectorName) {
    return [NSString stringWithFormat:@"%@:%@", NSStringFromClass(cls), selectorName ?: @""];
}

static BOOL SCIMutualGateRouter(id self, SEL _cmd) {
    NSString *selectorName = NSStringFromSelector(_cmd);
    for (NSString *key in SCIMutualPrefsForSelector(selectorName)) {
        if ([SCIUtils getBoolPref:key]) return YES;
    }

    NSValue *origValue = nil;
    pthread_mutex_lock(&gSCIMutualLock);
    Class cls = object_getClass(self);
    while (cls && !origValue) {
        origValue = gSCIOrigMutualIMPs[SCIMutualKey(cls, selectorName)];
        cls = class_getSuperclass(cls);
    }
    pthread_mutex_unlock(&gSCIMutualLock);

    if (!origValue) return NO;
    BOOL (*orig)(id, SEL) = (BOOL (*)(id, SEL))origValue.pointerValue;
    return orig ? orig(self, _cmd) : NO;
}

static BOOL SCIMethodReturnsBool(Method method) {
    char rt[16] = {0};
    method_getReturnType(method, rt, sizeof(rt));
    return rt[0] == 'B' || rt[0] == 'c' || rt[0] == 'C';
}

static void SCIHookMutualClass(Class cls) {
    if (!cls) return;
    unsigned int count = 0;
    Method *methods = class_copyMethodList(cls, &count);
    for (unsigned int i = 0; i < count; i++) {
        Method method = methods[i];
        if (method_getNumberOfArguments(method) != 2 || !SCIMethodReturnsBool(method)) continue;
        SEL sel = method_getName(method);
        NSString *selectorName = NSStringFromSelector(sel);
        if (!SCIMutualPrefsForSelector(selectorName)) continue;
        IMP original = method_setImplementation(method, (IMP)SCIMutualGateRouter);
        if (original) {
            pthread_mutex_lock(&gSCIMutualLock);
            gSCIOrigMutualIMPs[SCIMutualKey(cls, selectorName)] = [NSValue valueWithPointer:(const void *)original];
            pthread_mutex_unlock(&gSCIMutualLock);
        }
    }
    if (methods) free(methods);
}

%ctor {
    if (![SCIUtils getBoolPref:@"igt_mutual_interest"] && ![SCIUtils getBoolPref:@"igt_icebreaker"]) return;
    gSCIOrigMutualIMPs = [NSMutableDictionary dictionary];
    SCIHookMutualClass(NSClassFromString(@"_TtC32IGDirectMutualInterestIcebreaker42IGDirectMutualInterestFeatureGatingService"));
}
