#import "RYGReelsHold.h"
#import "../../Utils.h"
#import "../ExpFlags/RYGMobileConfig.h"
#import <objc/runtime.h>
#import <objc/message.h>
#import <substrate.h>

static unsigned int const kRYGHoldConfigNumber = 121815;
static NSString *const kRYGHoldConfigName = @"ig_reels_long_press_overflow_menu";

typedef struct { unsigned long long sessionless, session; } RYGHoldPid;

static RYGHoldPid gEnabledPid, gPipPid, gStylePid;
static BOOL gForceEnabled, gForcePip, gForceStyle;
static BOOL gEnabledValue, gPipValue;
static long long gStyleValue;
static BOOL gSuppressMenu, gInLongPress;

static inline NSString *rygHoldMode(void) {
	NSString *mode = [RYGUtils getStringPref:@"reels_long_press"];
	return mode.length ? mode : @"default";
}

static inline BOOL rygHoldPidMatches(RYGHoldPid p, unsigned long long pid) {
	return p.sessionless && (pid == p.sessionless || pid == p.session);
}

static BOOL rygHoldForcedBool(unsigned long long pid, BOOL *out) {
	if (gForceEnabled && rygHoldPidMatches(gEnabledPid, pid)) { *out = gEnabledValue; return YES; }
	if (gForcePip && rygHoldPidMatches(gPipPid, pid)) { *out = gPipValue; return YES; }
	return NO;
}

#define RYG_HOLD_BOOL(pid) \
	BOOL forced; \
	if (rygHoldForcedBool(pid, &forced)) return forced;

#define RYG_HOLD_INT(pid) \
	if (gForceStyle && rygHoldPidMatches(gStylePid, pid)) return gStyleValue;

static BOOL (*orig_getBool)(id, SEL, unsigned long long);
static BOOL new_getBool(id self, SEL _cmd, unsigned long long pid) {
	RYG_HOLD_BOOL(pid);
	return orig_getBool(self, _cmd, pid);
}
static BOOL (*orig_getBoolDef)(id, SEL, unsigned long long, BOOL);
static BOOL new_getBoolDef(id self, SEL _cmd, unsigned long long pid, BOOL def) {
	RYG_HOLD_BOOL(pid);
	return orig_getBoolDef(self, _cmd, pid, def);
}
static BOOL (*orig_getBoolOpts)(id, SEL, unsigned long long, id);
static BOOL new_getBoolOpts(id self, SEL _cmd, unsigned long long pid, id opts) {
	RYG_HOLD_BOOL(pid);
	return orig_getBoolOpts(self, _cmd, pid, opts);
}
static BOOL (*orig_getBoolOptsDef)(id, SEL, unsigned long long, id, BOOL);
static BOOL new_getBoolOptsDef(id self, SEL _cmd, unsigned long long pid, id opts, BOOL def) {
	RYG_HOLD_BOOL(pid);
	return orig_getBoolOptsDef(self, _cmd, pid, opts, def);
}

static long long (*orig_getInt)(id, SEL, unsigned long long);
static long long new_getInt(id self, SEL _cmd, unsigned long long pid) {
	RYG_HOLD_INT(pid);
	return orig_getInt(self, _cmd, pid);
}
static long long (*orig_getIntDef)(id, SEL, unsigned long long, long long);
static long long new_getIntDef(id self, SEL _cmd, unsigned long long pid, long long def) {
	RYG_HOLD_INT(pid);
	return orig_getIntDef(self, _cmd, pid, def);
}
static long long (*orig_getIntOpts)(id, SEL, unsigned long long, id);
static long long new_getIntOpts(id self, SEL _cmd, unsigned long long pid, id opts) {
	RYG_HOLD_INT(pid);
	return orig_getIntOpts(self, _cmd, pid, opts);
}
static long long (*orig_getIntOptsDef)(id, SEL, unsigned long long, id, long long);
static long long new_getIntOptsDef(id self, SEL _cmd, unsigned long long pid, id opts, long long def) {
	RYG_HOLD_INT(pid);
	return orig_getIntOptsDef(self, _cmd, pid, opts, def);
}

static void (*orig_longPressBegin)(id, SEL, id, id);
static void new_longPressBegin(id self, SEL _cmd, id cell, id recognizer) {
	RYGProbeOnce(@"reels-hold.section-begin", @"%@", NSStringFromClass([cell class]));
	gInLongPress = YES;
	orig_longPressBegin(self, _cmd, cell, recognizer);
}

static void (*orig_longPressEnd)(id, SEL, id, id);
static void new_longPressEnd(id self, SEL _cmd, id cell, id recognizer) {
	gInLongPress = NO;
	orig_longPressEnd(self, _cmd, cell, recognizer);
}

static id (*orig_menuDataSource)(id, SEL);
static id new_menuDataSource(id self, SEL _cmd) {
	if (gSuppressMenu && gInLongPress) return nil;
	return orig_menuDataSource(self, _cmd);
}

static RYGMCConfig *rygHoldConfig(void) {
	for (RYGMCConfig *c in [[RYGMobileConfig shared] configsMatching:kRYGHoldConfigName onlyOverridden:NO])
		if (c.number == kRYGHoldConfigNumber || [c.name isEqualToString:kRYGHoldConfigName]) return c;
	return nil;
}

static RYGHoldPid rygHoldPidFor(RYGMCConfig *config, NSString *name, RYGMCType type) {
	for (RYGMCParam *p in config.params) {
		if (p.type != type || ![p.name isEqualToString:name]) continue;
		unsigned long long low = p.paramID & 0x0000FFFFFFFFFFFFULL;
		return (RYGHoldPid){ low | ((0x40ULL | type) << 48), low | ((0x80ULL | type) << 48) };
	}
	return (RYGHoldPid){0, 0};
}

@implementation RYGReelsHold

+ (BOOL)mobileConfigOverridesLongPress {
	if (![RYGUtils getBoolPref:@"ryg_metaconfig_enabled"]) return NO;
	RYGMCConfig *config = rygHoldConfig();
	if (!config) return NO;
	RYGMobileConfig *engine = [RYGMobileConfig shared];
	for (RYGMCParam *p in config.params)
		if ([engine overrideStateFor:p] == RYGMCOverrideSet) return YES;
	return NO;
}

@end

static void rygHoldHook(Class cls, NSString *name, IMP replacement, IMP *orig) {
	if (!cls) return;
	SEL sel = NSSelectorFromString(name);
	if (class_getInstanceMethod(cls, sel)) MSHookMessageEx(cls, sel, replacement, orig);
}

static void rygHoldInstallConfigHooks(void) {
	Class mc = NSClassFromString(@"IGMobileConfigContextManager");
	rygHoldHook(mc, @"getBool:",                          (IMP)new_getBool,        (IMP *)&orig_getBool);
	rygHoldHook(mc, @"getBool:withDefault:",              (IMP)new_getBoolDef,     (IMP *)&orig_getBoolDef);
	rygHoldHook(mc, @"getBool:withOptions:",              (IMP)new_getBoolOpts,    (IMP *)&orig_getBoolOpts);
	rygHoldHook(mc, @"getBool:withOptions:withDefault:",  (IMP)new_getBoolOptsDef, (IMP *)&orig_getBoolOptsDef);
	if (!gForceStyle) return;
	rygHoldHook(mc, @"getInt64:",                         (IMP)new_getInt,         (IMP *)&orig_getInt);
	rygHoldHook(mc, @"getInt64:withDefault:",             (IMP)new_getIntDef,      (IMP *)&orig_getIntDef);
	rygHoldHook(mc, @"getInt64:withOptions:",             (IMP)new_getIntOpts,     (IMP *)&orig_getIntOpts);
	rygHoldHook(mc, @"getInt64:withOptions:withDefault:", (IMP)new_getIntOptsDef,  (IMP *)&orig_getIntOptsDef);
}

static BOOL rygHoldInstallSectionHooks(void) {
	Class section = NSClassFromString(@"IGSundialViewerVideoSectionController");
	if (!section) return NO;
	rygHoldHook(section, @"sundialViewerVideoCellDidLongPressBegin:gestureRecognizer:", (IMP)new_longPressBegin, (IMP *)&orig_longPressBegin);
	rygHoldHook(section, @"sundialViewerVideoCellDidLongPressEnd:gestureRecognizer:", (IMP)new_longPressEnd, (IMP *)&orig_longPressEnd);
	rygHoldHook(section, @"longPressMenuDataSource", (IMP)new_menuDataSource, (IMP *)&orig_menuDataSource);
	return YES;
}

static void rygHoldScheduleSectionHooks(NSInteger attempt) {
	if (rygHoldInstallSectionHooks() || attempt >= 40) return;
	dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(3 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
		rygHoldScheduleSectionHooks(attempt + 1);
	});
}

static BOOL rygHoldResolve(NSString *mode) {
	RYGMCConfig *config = rygHoldConfig();
	if (!config) return NO;

	gEnabledPid = rygHoldPidFor(config, @"is_enabled", RYGMCTypeBool);
	if (!gEnabledPid.sessionless) return NO;
	gForceEnabled = YES;
	gEnabledValue = ![mode isEqualToString:@"pause"];

	if ([mode isEqualToString:@"menu_pip"]) {
		gPipPid = rygHoldPidFor(config, @"pip_enabled", RYGMCTypeBool);
		gStylePid = rygHoldPidFor(config, @"menu_style", RYGMCTypeInt);
		gForcePip = gPipPid.sessionless != 0;
		gPipValue = YES;
		gForceStyle = gStylePid.sessionless != 0;
		gStyleValue = 1;
	}
	return YES;
}

static void rygHoldStart(NSString *mode, NSInteger attempt) {
	if (!rygHoldResolve(mode)) {
		if (attempt >= 8) return;
		dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(4 * NSEC_PER_SEC)),
					   dispatch_get_global_queue(QOS_CLASS_UTILITY, 0), ^{
			rygHoldStart(mode, attempt + 1);
		});
		return;
	}
	dispatch_async(dispatch_get_main_queue(), ^{
		rygHoldInstallConfigHooks();
		if (gSuppressMenu) rygHoldScheduleSectionHooks(0);
	});
}

%ctor {
	NSString *mode = rygHoldMode();
	if ([mode isEqualToString:@"default"]) return;

	gSuppressMenu = [mode isEqualToString:@"pause"];
	dispatch_async(dispatch_get_global_queue(QOS_CLASS_UTILITY, 0), ^{
		if ([RYGReelsHold mobileConfigOverridesLongPress]) return;
		rygHoldStart(mode, 0);
	});
}
