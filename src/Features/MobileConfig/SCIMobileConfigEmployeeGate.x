// SCIMobileConfigEmployeeGate.x
// =====================================================================
// Pre-session MobileConfig identity gate.
//
// Instagram imports _ig_is_employee and _ig_is_employee_or_test_user from
// FBSharedFramework as DATA.  They are 16-byte descriptors, not callable C
// functions.  Consumers load descriptor->field0 and pass that uint64_t to
// -getBool:.  The replacement below therefore matches only those two complete
// specifiers and delegates every other MobileConfig read to its original IMP.
//
// Installation has two synchronous, idempotent passes: the tweak constructor
// and IGInstagramAppDelegate's willFinishLaunching.  The first is early enough
// for normal session construction; the second only fills a missing descriptor
// or class if FBSharedFramework had not yet completed loading.  There is no
// dyld callback, class scan, foreground retry, delayed installation, or
// preference lookup on the getBool: hot path.
// =====================================================================

#import <substrate.h>
#import <objc/runtime.h>
#import <dlfcn.h>
#import <stdatomic.h>
#import <stdint.h>
#import <stdlib.h>
#import <string.h>

#import "../../Utils.h"
#import "../../SCIFileLog.h"
#import "../Dogfooding/SCIInternalGatePrefs.h"

typedef uint64_t SCIMobileConfigBoolSpecifier;
typedef BOOL (*SCIGetBoolIMP)(id, SEL, SCIMobileConfigBoolSpecifier);

static const char *const kSCIEmployeeDescriptorSymbols[] = {
	"ig_is_employee",
	"ig_is_employee_or_test_user",
};
enum { kSCIEmployeeDescriptorCount = 2 };

static _Atomic(BOOL) sSCIEmployeeGateEnabled = NO;
static _Atomic(BOOL) sSCIEmployeeSpecifierResolved[kSCIEmployeeDescriptorCount];
static _Atomic(SCIMobileConfigBoolSpecifier) sSCIEmployeeSpecifiers[kSCIEmployeeDescriptorCount];
static _Atomic(uint32_t) sSCIEmployeeLoggedMask = 0;

typedef struct {
	Class owner;
	SCIGetBoolIMP original;
} SCIGetBoolHook;

static SCIGetBoolHook sSCIGetBoolHooks[4];
static NSUInteger sSCIGetBoolHookCount = 0;
static dispatch_once_t sSCIEmployeeGateStateOnce;

static void SCIInitializeEmployeeGateState(void) {
	dispatch_once(&sSCIEmployeeGateStateOnce, ^{
		BOOL enabled = [SCIInternalGatePrefs employeeInternalMasterEnabled] ||
			[SCIUtils getBoolPref:@"sci_force_mc_session_employee_gate"];
		atomic_store_explicit(&sSCIEmployeeGateEnabled, enabled, memory_order_release);
	});
}

static void SCIResolveEmployeeSpecifiers(void) {
	for (NSUInteger i = 0; i < kSCIEmployeeDescriptorCount; i++) {
		if (atomic_load_explicit(&sSCIEmployeeSpecifierResolved[i], memory_order_acquire)) {
			continue;
		}

		const void *descriptor = dlsym(RTLD_DEFAULT, kSCIEmployeeDescriptorSymbols[i]);
		if (!descriptor) continue;

		SCIMobileConfigBoolSpecifier specifier =
			*(const SCIMobileConfigBoolSpecifier *)descriptor;
		if (!specifier) continue;

		atomic_store_explicit(&sSCIEmployeeSpecifiers[i], specifier, memory_order_release);
		atomic_store_explicit(&sSCIEmployeeSpecifierResolved[i], YES, memory_order_release);
	}
}

static NSInteger SCIEmployeeSpecifierIndex(SCIMobileConfigBoolSpecifier specifier) {
	if (!specifier) return NSNotFound;
	for (NSUInteger i = 0; i < kSCIEmployeeDescriptorCount; i++) {
		if (!atomic_load_explicit(&sSCIEmployeeSpecifierResolved[i], memory_order_acquire)) {
			continue;
		}
		if (specifier == atomic_load_explicit(&sSCIEmployeeSpecifiers[i], memory_order_acquire)) {
			return (NSInteger)i;
		}
	}
	return NSNotFound;
}

static void SCILogEmployeeGateHit(NSInteger index, id object) {
	if (index == NSNotFound || !SCIFileLogIsEnabled()) return;
	uint32_t bit = UINT32_C(1) << (uint32_t)index;
	uint32_t seen = atomic_fetch_or_explicit(&sSCIEmployeeLoggedMask, bit, memory_order_relaxed);
	if (seen & bit) return;
	SCIFLog(@"SCIEmpGate", @"forced -getBool: %s on %s",
		kSCIEmployeeDescriptorSymbols[index], object_getClassName(object));
}

static SCIGetBoolIMP SCIOriginalGetBoolForObject(id object) {
	for (Class cls = object_getClass(object); cls; cls = class_getSuperclass(cls)) {
		for (NSUInteger i = 0; i < sSCIGetBoolHookCount; i++) {
			if (sSCIGetBoolHooks[i].owner == cls) return sSCIGetBoolHooks[i].original;
		}
	}
	return NULL;
}

static BOOL SCIEmployeeGateGetBool(id self, SEL _cmd,
	SCIMobileConfigBoolSpecifier specifier) {
	if (atomic_load_explicit(&sSCIEmployeeGateEnabled, memory_order_acquire)) {
		NSInteger match = SCIEmployeeSpecifierIndex(specifier);
		if (match != NSNotFound) {
			SCILogEmployeeGateHit(match, self);
			return YES;
		}
	}

	SCIGetBoolIMP original = SCIOriginalGetBoolForObject(self);
	return original ? original(self, _cmd, specifier) : NO;
}

static Class SCIGetBoolDeclaringClass(Class cls, SEL selector) {
	for (Class current = cls; current; current = class_getSuperclass(current)) {
		unsigned int methodCount = 0;
		Method *methods = class_copyMethodList(current, &methodCount);
		BOOL declaresSelector = NO;
		for (unsigned int i = 0; methods && i < methodCount; i++) {
			if (method_getName(methods[i]) == selector) {
				declaresSelector = YES;
				break;
			}
		}
		free(methods);
		if (declaresSelector) return current;
	}
	return Nil;
}

static char SCIUnqualifiedObjCType(const char *encoding) {
	if (!encoding) return '\0';
	while (*encoding == 'r' || *encoding == 'n' || *encoding == 'N' ||
		   *encoding == 'o' || *encoding == 'O' || *encoding == 'R' ||
		   *encoding == 'V') {
		encoding++;
	}
	return *encoding;
}

static BOOL SCIGetBoolABIMatches(Method method) {
	if (!method || method_getNumberOfArguments(method) != 3) return NO;
	char returnType[16] = {0};
	char argumentType[16] = {0};
	method_getReturnType(method, returnType, sizeof(returnType));
	method_getArgumentType(method, 2, argumentType, sizeof(argumentType));
	char result = SCIUnqualifiedObjCType(returnType);
	char parameter = SCIUnqualifiedObjCType(argumentType);
	return (result == 'B' || result == 'c') && (parameter == 'Q' || parameter == 'q');
}

static BOOL SCIAlreadyHooksGetBoolOwner(Class owner) {
	for (NSUInteger i = 0; i < sSCIGetBoolHookCount; i++) {
		if (sSCIGetBoolHooks[i].owner == owner) return YES;
	}
	return NO;
}

static void SCIInstallGetBoolHookOnClass(const char *className) {
	if (sSCIGetBoolHookCount >= sizeof(sSCIGetBoolHooks) / sizeof(sSCIGetBoolHooks[0])) {
		return;
	}

	Class requestedClass = objc_getClass(className);
	SEL selector = @selector(getBool:);
	Class owner = SCIGetBoolDeclaringClass(requestedClass, selector);
	if (!owner || SCIAlreadyHooksGetBoolOwner(owner)) return;

	Method method = class_getInstanceMethod(owner, selector);
	if (!SCIGetBoolABIMatches(method)) return;

	SCIGetBoolIMP original = (SCIGetBoolIMP)method_getImplementation(method);
	if (!original) return;
	MSHookMessageEx(owner, selector, (IMP)SCIEmployeeGateGetBool, (IMP *)&original);
	if (!original) return;

	sSCIGetBoolHooks[sSCIGetBoolHookCount++] = (SCIGetBoolHook){
		.owner = owner,
		.original = original,
	};
}

void SCIInstallMobileConfigEmployeeGateIfNeeded(void) {
	SCIInitializeEmployeeGateState();
	if (!atomic_load_explicit(&sSCIEmployeeGateEnabled, memory_order_acquire)) return;

	SCIResolveEmployeeSpecifiers();
	SCIInstallGetBoolHookOnClass("FBMobileConfigUserSessionContextManager");
	SCIInstallGetBoolHookOnClass("IGMobileConfigUserSessionContextManager");
	SCIInstallGetBoolHookOnClass("FBMobileConfigContextManager");
	SCIInstallGetBoolHookOnClass("IGMobileConfigContextManager");

	if (SCIFileLogIsEnabled()) {
		NSUInteger resolved = 0;
		for (NSUInteger i = 0; i < kSCIEmployeeDescriptorCount; i++) {
			if (atomic_load_explicit(&sSCIEmployeeSpecifierResolved[i], memory_order_acquire)) {
				resolved++;
			}
		}
		SCIFLog(@"SCIEmpGate", @"installed resolved=%lu/%u hooked=%lu",
			(unsigned long)resolved, kSCIEmployeeDescriptorCount,
			(unsigned long)sSCIGetBoolHookCount);
	}
}

%ctor {
	@autoreleasepool {
		SCIInstallMobileConfigEmployeeGateIfNeeded();
	}
}
