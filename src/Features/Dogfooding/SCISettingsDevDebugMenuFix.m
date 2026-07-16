#import "../../Settings/Sections/SCISettingsSections.h"
#import "../../Settings/SCISetting.h"
#import "SCIInternalMenusLauncher.h"
#import "../../Utils.h"
#import <objc/runtime.h>
#import <substrate.h>
#import <os/log.h>
#import <string.h>

#define SDMLOG(fmt, ...) os_log(OS_LOG_DEFAULT, "[SCIGate] DevDebugMenuFix " fmt, ##__VA_ARGS__)

static SCISetting *(*orig_SCIDevNavCell)(id, SEL) = NULL;

static SCISetting *SCIDevNavCell(id self, SEL _cmd) {
	SCISetting *navigation = orig_SCIDevNavCell
		? orig_SCIDevNavCell(self, _cmd)
		: nil;
	if (![navigation isKindOfClass:SCISetting.class]) return navigation;

	for (NSDictionary *section in navigation.navSections) {
		NSArray *rows = [section[@"rows"] isKindOfClass:NSArray.class]
			? section[@"rows"] : @[];
		for (SCISetting *row in rows) {
			if (![row isKindOfClass:SCISetting.class] ||
				![row.title isEqualToString:SCILocalized(@"Open Instagram Debug Menu")]) continue;

			row.subtitle = SCILocalized(
				@"Dismisses RyukGram and invokes the validated -[IGWindow showDebugMenu] / entryPoint 0 path"
			);
			row.action = ^{
				[SCIInternalMenusLauncher
					openInstagramDebugMenuWithCompletion:^(NSString *result) {
						if ([result hasPrefix:@"presented"]) return;
						[SCIUtils showToastForDuration:5.0
							title:SCILocalized(@"Instagram Debug Menu")
							subtitle:result ?: @"Native opener returned no result"];
					}];
			};
			return navigation;
		}
	}
	return navigation;
}

__attribute__((constructor))
static void SCIInstallSettingsDevDebugMenuFix(void) {
	@autoreleasepool {
		Class cls = objc_getClass("SCITweakSettings");
		Class meta = cls ? object_getClass(cls) : Nil;
		SEL selector = sel_registerName("devNavCell");
		Method method = meta ? class_getInstanceMethod(meta, selector) : NULL;
		const char *encoding = method ? method_getTypeEncoding(method) : NULL;
		if (!encoding || strcmp(encoding, "@16@0:8") != 0) {
			SDMLOG("devNavCell ABI unavailable or changed: %{public}s",
				encoding ?: "missing");
			return;
		}

		MSHookMessageEx(meta, selector,
			(IMP)SCIDevNavCell,
			(IMP *)&orig_SCIDevNavCell);
		SDMLOG("row fix %{public}s",
			orig_SCIDevNavCell ? "installed" : "not installed");
	}
}
