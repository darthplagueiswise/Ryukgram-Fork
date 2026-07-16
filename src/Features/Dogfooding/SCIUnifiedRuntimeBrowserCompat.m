// Compatibility layer for the existing Unified Runtime Browser UI. The browser
// controller was written when every ObjC entry was a no-argument BOOL getter;
// the current engine also exposes one-object and one-integer argument methods.
#import <Foundation/Foundation.h>
#import <objc/runtime.h>
#import <objc/message.h>
#import <substrate.h>

static id (*origEntryABI)(id, SEL) = NULL;
static id (*origEntryKind)(id, SEL) = NULL;
static id (*origEntryHookPlan)(id, SEL) = NULL;
static BOOL (*origDefaultFilter)(id, SEL, id) = NULL;
static id (*origCategory)(id, SEL, id) = NULL;

static id SCIGet(id object, SEL selector) {
	if (!object || !selector || ![object respondsToSelector:selector]) return nil;
	id (*fn)(id, SEL) = (id (*)(id, SEL))objc_msgSend;
	return fn(object, selector);
}
static BOOL SCIGetBool(id object, SEL selector) {
	if (!object || !selector || ![object respondsToSelector:selector]) return NO;
	BOOL (*fn)(id, SEL) = (BOOL (*)(id, SEL))objc_msgSend;
	return fn(object, selector);
}
static Method SCIEntryMethod(id entry) {
	NSString *className = SCIGet(entry, @selector(objcClassName));
	NSString *selectorName = SCIGet(entry, @selector(objcSelectorName));
	if (!className.length || !selectorName.length) return NULL;
	Class cls = NSClassFromString(className);
	SEL sel = NSSelectorFromString(selectorName);
	if (!cls || !sel) return NULL;
	return SCIGetBool(entry, @selector(objcClassMethod)) ? class_getClassMethod(cls, sel) : class_getInstanceMethod(cls, sel);
}
static NSString *SCIArgumentDescription(Method method) {
	if (!method) return nil;
	unsigned count = method_getNumberOfArguments(method);
	if (count == 2) return @"BOOL(id self, SEL _cmd) -> w0";
	if (count != 3) return nil;
	char type[32] = {0};
	method_getArgumentType(method, 2, type, sizeof(type));
	const char *p = type;
	while (*p == 'r' || *p == 'n' || *p == 'N' || *p == 'o' || *p == 'O' || *p == 'R' || *p == 'V') p++;
	if (*p == '@' || *p == '#' || *p == ':')
		return [NSString stringWithFormat:@"BOOL(id self, SEL _cmd, id arg [%s]) -> w0", p];
	if (strchr("BcCsSiIlLqQ^*", *p))
		return [NSString stringWithFormat:@"BOOL(id self, SEL _cmd, uint64_t/pointer arg [%s]) -> w0", p];
	return nil;
}
static BOOL SCINameHasExperimentKeyword(NSString *name) {
	NSString *n = name.lowercaseString;
	for (NSString *needle in @[@"fbccigexperimentmanager", @"fbcustomexperimentmanager", @"experimentconfig", @"experimentconfiguration", @"quickexperiment", @"igmagicmod", @"igstoriestab", @"igdirectnotes", @"igliquidglass", @"experimenthelper", @"gatinghelper", @"featurehelper"])
		if ([n containsString:needle]) return YES;
	return NO;
}

static id SCIEntryABI(id self, SEL _cmd) {
	NSString *selector = SCIGet(self, @selector(objcSelectorName));
	if (!selector.length) return origEntryABI ? origEntryABI(self, _cmd) : nil;
	NSString *signature = SCIArgumentDescription(SCIEntryMethod(self));
	return signature ? [@"ObjC runtime: " stringByAppendingString:signature] : (origEntryABI ? origEntryABI(self, _cmd) : nil);
}
static id SCIEntryKind(id self, SEL _cmd) {
	NSString *selector = SCIGet(self, @selector(objcSelectorName));
	if (!selector.length) return origEntryKind ? origEntryKind(self, _cmd) : nil;
	Method method = SCIEntryMethod(self);
	unsigned count = method ? method_getNumberOfArguments(method) : 0;
	return count == 3 ? @"ObjC BOOL method (1 argument)" : @"ObjC BOOL method (no argument)";
}
static id SCIEntryHookPlan(id self, SEL _cmd) {
	NSString *selector = SCIGet(self, @selector(objcSelectorName));
	if (!selector.length) return origEntryHookPlan ? origEntryHookPlan(self, _cmd) : nil;
	return @"Persisted MSHookMessageEx override with an ABI-matched 0/1-argument replacement; one original IMP is preserved per selector.";
}
static BOOL SCIDefaultFilter(id self, SEL _cmd, id entry) {
	if (origDefaultFilter && origDefaultFilter(self, _cmd, entry)) return YES;
	NSString *name = SCIGet(entry, @selector(name));
	return SCINameHasExperimentKeyword(name ?: @"");
}
static id SCICategory(id self, SEL _cmd, id entry) {
	NSString *name = SCIGet(entry, @selector(name));
	NSString *lower = name.lowercaseString;
	if ([lower containsString:@"fbccigexperimentmanager"] || [lower containsString:@"fbcustomexperimentmanager"]) return @"Unified experiment managers";
	if ([lower containsString:@"experimentconfig"] || [lower containsString:@"experimentconfiguration"] || [lower containsString:@"quickexperiment"]) return @"QuickExperiment / ExperimentConfig";
	if (SCINameHasExperimentKeyword(name ?: @"")) return @"Experiment helpers";
	return origCategory ? origCategory(self, _cmd, entry) : @"ObjC BOOL methods";
}

__attribute__((constructor)) static void SCIInstallUnifiedRuntimeBrowserCompatibility(void) {
	@autoreleasepool {
		Class entry = objc_getClass("SCICSymbolEntry");
		if (entry) {
			MSHookMessageEx(entry, @selector(abi), (IMP)SCIEntryABI, (IMP *)&origEntryABI);
			MSHookMessageEx(entry, @selector(kind), (IMP)SCIEntryKind, (IMP *)&origEntryKind);
			MSHookMessageEx(entry, @selector(hookPlan), (IMP)SCIEntryHookPlan, (IMP *)&origEntryHookPlan);
		}
		Class browser = objc_getClass("SCISymbolsBrowserViewController");
		if (browser) {
			SEL filter = NSSelectorFromString(@"entryMatchesDefaultFilters:");
			SEL category = NSSelectorFromString(@"categoryForEntry:");
			if (class_getInstanceMethod(browser, filter)) MSHookMessageEx(browser, filter, (IMP)SCIDefaultFilter, (IMP *)&origDefaultFilter);
			if (class_getInstanceMethod(browser, category)) MSHookMessageEx(browser, category, (IMP)SCICategory, (IMP *)&origCategory);
		}
	}
}
