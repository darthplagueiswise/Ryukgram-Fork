#import "SCILauncherOverride.h"
#import "../../Utils.h"
#import "SCIDogfoodObjectRuntime.h"
#import <objc/runtime.h>
#import <objc/message.h>

static NSString * const kSCILauncherOverridesKey = @"sci_launcher_overrides";
static NSString * const kClientDemangled = @"IGDogfoodingAssistantLauncherClient.IGDogfoodingAssistantLauncherClient";
static NSString * const kClientMangled = @"_TtC35IGDogfoodingAssistantLauncherClient35IGDogfoodingAssistantLauncherClient";

static Class sciLauncherClientClass(void) {
	Class c = NSClassFromString(kClientDemangled);
	if (!c) c = NSClassFromString(kClientMangled);
	return c;
}

static id sciNewLauncherClient(void) {
	Class cls = sciLauncherClientClass();
	if (!cls) return nil;
	@try {
		typedef id (*InitIMP)(id, SEL);
		return ((InitIMP)objc_msgSend)([cls alloc], @selector(init));
	} @catch (__unused id e) { return nil; }
}

static NSMutableDictionary *sciMutableOverrideRoot(void) {
	id raw = [[NSUserDefaults standardUserDefaults] objectForKey:kSCILauncherOverridesKey];
	if (![raw isKindOfClass:[NSDictionary class]]) return [NSMutableDictionary dictionary];
	NSMutableDictionary *root = [NSMutableDictionary dictionaryWithCapacity:[(NSDictionary *)raw count]];
	for (NSString *launcher in (NSDictionary *)raw) {
		id sub = raw[launcher];
		if ([launcher isKindOfClass:[NSString class]] && [sub isKindOfClass:[NSDictionary class]])
			root[launcher] = [sub mutableCopy];
	}
	return root;
}

@implementation SCILauncherOverride

+ (BOOL)isAvailable { return sciLauncherClientClass() != nil; }

+ (NSDictionary<NSString *, NSDictionary<NSString *, id> *> *)allOverrides {
	id raw = [[NSUserDefaults standardUserDefaults] objectForKey:kSCILauncherOverridesKey];
	return [raw isKindOfClass:[NSDictionary class]] ? (NSDictionary *)raw : @{};
}

+ (NSUInteger)totalOverrideCount {
	NSUInteger n = 0;
	for (NSString *l in [self allOverrides]) {
		id sub = [self allOverrides][l];
		if ([sub isKindOfClass:[NSDictionary class]]) n += [(NSDictionary *)sub count];
	}
	return n;
}

+ (void)persistLauncher:(NSString *)launcherName parameter:(NSString *)paramName value:(id)value {
	if (![launcherName isKindOfClass:[NSString class]] || launcherName.length == 0) return;
	if (![paramName isKindOfClass:[NSString class]] || paramName.length == 0) return;
	NSMutableDictionary *root = sciMutableOverrideRoot();
	NSMutableDictionary *sub = root[launcherName] ?: [NSMutableDictionary dictionary];
	if (value == nil) [sub removeObjectForKey:paramName];
	else sub[paramName] = value;
	if (sub.count == 0) [root removeObjectForKey:launcherName];
	else root[launcherName] = sub;
	[[NSUserDefaults standardUserDefaults] setObject:root forKey:kSCILauncherOverridesKey];
}

+ (BOOL)forwardLauncher:(NSString *)launcherName parameters:(NSDictionary *)params client:(id)client session:(id)session {
	if (!client || !session) return NO;
	if (![launcherName isKindOfClass:[NSString class]] || launcherName.length == 0) return NO;
	if (![params isKindOfClass:[NSDictionary class]] || params.count == 0) return NO;
	SEL sel = @selector(overrideLauncherWithUserSession:launcherName:parametersToValues:);
	if (![client respondsToSelector:sel]) return NO;
	@try {
		typedef BOOL (*OverrideIMP)(id, SEL, id, id, id);
		return ((OverrideIMP)objc_msgSend)(client, sel, session, launcherName, params);
	} @catch (__unused id e) { return NO; }
}

+ (BOOL)applyLauncher:(NSString *)launcherName parameter:(NSString *)parameterName value:(id)value {
	if (!value) return NO;
	[self persistLauncher:launcherName parameter:parameterName value:value];
	id session = [SCIDogfoodObjectRuntime activeUserSession];
	id client = sciNewLauncherClient();
	return [self forwardLauncher:launcherName parameters:@{parameterName: value} client:client session:session];
}

+ (void)removeLauncher:(NSString *)launcherName parameter:(NSString *)parameterName {
	[self persistLauncher:launcherName parameter:parameterName value:nil];
}

+ (void)clearAll {
	[[NSUserDefaults standardUserDefaults] removeObjectForKey:kSCILauncherOverridesKey];
}

+ (void)replayPersistedOverrides {
	NSDictionary *root = [self allOverrides];
	if (root.count == 0) return;
	id session = [SCIDogfoodObjectRuntime activeUserSession];
	id client = sciNewLauncherClient();
	if (!session || !client) return;
	for (NSString *launcher in root) {
		NSDictionary *params = root[launcher];
		if ([params isKindOfClass:[NSDictionary class]] && params.count > 0)
			[self forwardLauncher:launcher parameters:params client:client session:session];
	}
}

@end
