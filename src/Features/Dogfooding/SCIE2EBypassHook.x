#import "../../Utils.h"
#import "SCIGraphQLDogfoodDiagnostics.h"
#import <objc/runtime.h>
#import <substrate.h>
#import <os/log.h>
#import <string.h>

#define E2ELOG(fmt, ...) os_log(OS_LOG_DEFAULT, "[SCIGate] E2EBypass " fmt, ##__VA_ARGS__)

static NSString *const kSCIE2EBypassKey = @"sci_force_e2e_bypass";
static BOOL (*orig_SCIE2EShouldBypass)(id, SEL, id) = NULL;
static BOOL sSCIE2EHookInstalled = NO;

static BOOL SCIE2EBypassEnabled(void) {
	return [SCIUtils getBoolPref:kSCIE2EBypassKey];
}

static BOOL SCIE2EShouldBypass(id self, SEL _cmd, id launcherSet) {
	if (SCIE2EBypassEnabled()) return YES;
	return orig_SCIE2EShouldBypass
		? orig_SCIE2EShouldBypass(self, _cmd, launcherSet)
		: NO;
}

void SCIInstallE2EBypassHookIfNeeded(void) {
	SCIRegisterGraphQLDogfoodDevDefaults();
	if (sSCIE2EHookInstalled || !SCIE2EBypassEnabled()) return;

	Class cls = objc_getClass("_TtC15IGE2EBypassUtil15IGE2EBypassUtil");
	if (!cls) {
		E2ELOG("class not loaded; installer remains retryable");
		return;
	}

	SEL selector = sel_registerName("shouldBypassForE2EWithLauncherSet:");
	Method method = class_getClassMethod(cls, selector);
	if (!method) {
		E2ELOG("selector absent");
		return;
	}

	const char *encoding = method_getTypeEncoding(method);
	if (!encoding || strcmp(encoding, "B24@0:8@16") != 0) {
		E2ELOG("skip ABI changed: %{public}s", encoding ?: "(null)");
		return;
	}

	Class metaclass = object_getClass(cls);
	if (!metaclass) return;

	MSHookMessageEx(
		metaclass,
		selector,
		(IMP)SCIE2EShouldBypass,
		(IMP *)&orig_SCIE2EShouldBypass
	);

	sSCIE2EHookInstalled = (orig_SCIE2EShouldBypass != NULL);
	E2ELOG("hook %{public}s", sSCIE2EHookInstalled ? "installed" : "not installed");
}

%ctor {
	@autoreleasepool {
		if (!SCIE2EBypassEnabled()) return;
		SCIInstallE2EBypassHookIfNeeded();
	}
}
