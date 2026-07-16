#import "SCIInternalGatePrefs.h"
#import <objc/runtime.h>
#import <substrate.h>
#import <os/log.h>
#import <string.h>

#define E2ECGLOG(fmt, ...) os_log(OS_LOG_DEFAULT, "[SCIGate] E2ECrashGuard " fmt, ##__VA_ARGS__)

static NSArray<NSString *> *(*orig_SCIGateKeys)(id, SEL) = NULL;

static NSArray<NSString *> *SCIGateKeysWithE2E(id self, SEL _cmd) {
	NSArray<NSString *> *original = orig_SCIGateKeys
		? orig_SCIGateKeys(self, _cmd)
		: @[];
	if ([original containsObject:@"sci_force_e2e_bypass"]) return original;

	NSMutableArray<NSString *> *keys = [original mutableCopy]
		?: [NSMutableArray array];
	[keys addObject:@"sci_force_e2e_bypass"];
	return keys.copy;
}

__attribute__((constructor(101)))
static void SCIInstallE2ECrashGuardBridge(void) {
	@autoreleasepool {
		Class cls = objc_getClass("SCIInternalGatePrefs");
		Class meta = cls ? object_getClass(cls) : Nil;
		SEL selector = sel_registerName("allGateKeys");
		Method method = meta ? class_getInstanceMethod(meta, selector) : NULL;
		const char *encoding = method ? method_getTypeEncoding(method) : NULL;
		if (!encoding || strcmp(encoding, "@16@0:8") != 0) {
			E2ECGLOG("allGateKeys ABI unavailable or changed: %{public}s",
				encoding ?: "missing");
			return;
		}

		MSHookMessageEx(meta, selector,
			(IMP)SCIGateKeysWithE2E,
			(IMP *)&orig_SCIGateKeys);
		E2ECGLOG("bridge %{public}s", orig_SCIGateKeys ? "installed" : "not installed");
	}
}
