#import "SCIDogfooding.h"
#import "../../Utils.h"
#import "SCILauncherOverride.h"
#import "SCIDogfoodObjectRuntime.h"
#import <objc/runtime.h>
#import <objc/message.h>
#import <UIKit/UIKit.h>

static UIViewController *sciDogfoodTopVC(void) {
	UIWindow *key = nil;
	for (UIScene *scene in UIApplication.sharedApplication.connectedScenes) {
		if (![scene isKindOfClass:UIWindowScene.class]) continue;
		for (UIWindow *w in ((UIWindowScene *)scene).windows) {
			if (w.isKeyWindow) { key = w; break; }
		}
		if (key) break;
	}
	UIViewController *top = key.rootViewController;
	while (top.presentedViewController && !top.presentedViewController.isBeingDismissed) {
		top = top.presentedViewController;
	}
	return top;
}

static UINavigationController *sciWrapInNav(UIViewController *vc) {
	UINavigationController *nav = [[UINavigationController alloc] initWithRootViewController:vc];
	nav.modalPresentationStyle = UIModalPresentationFullScreen;
	return nav;
}

static void sciInstallBackButtonOnController(UIViewController *vc, NSString *title) {
	if (![vc isKindOfClass:UIViewController.class]) return;
	UIBarButtonItem *back = [[UIBarButtonItem alloc] initWithTitle:(title ?: @"Back")
	                                                        style:UIBarButtonItemStylePlain
	                                                       target:SCIDogfooding.class
	                                                       action:@selector(sciDismissDogfoodModal:)];
	vc.navigationItem.leftBarButtonItem = back;
}

@implementation SCIDogfooding

+ (void)sciDismissDogfoodModal:(id)sender {
	dispatch_async(dispatch_get_main_queue(), ^{
		UIViewController *top = sciDogfoodTopVC();
		if (!top || top.isBeingDismissed) return;
		[top.view endEditing:YES];
		UINavigationController *nav = [top isKindOfClass:UINavigationController.class] ? (UINavigationController *)top : top.navigationController;
		if (nav && nav.viewControllers.count > 1) {
			[nav popViewControllerAnimated:YES];
			return;
		}
		UIViewController *target = nav ?: top;
		if (!target.presentingViewController && target.navigationController.viewControllers.count > 1) {
			[target.navigationController popViewControllerAnimated:YES];
			return;
		}
		[target dismissViewControllerAnimated:YES completion:nil];
	});
}

+ (BOOL)isAvailable {
	return NSClassFromString(@"IGDirectNotesDogfoodingSettings.IGDirectNotesDogfoodingSettingsStaticFuncs") != nil ||
	       NSClassFromString(@"MetaLocalExperimentListViewController") != nil;
}

// ---- Notes dogfooding ----
// Working: has its own static-funcs class that bootstraps config + presents.
+ (void)presentNotesDogfoodingSettings {
	id session = [SCIDogfoodObjectRuntime activeUserSession];
	if (!session) { [SCIUtils showErrorHUDWithDescription:@"No active user session"]; return; }
	UIViewController *top = sciDogfoodTopVC();
	if (!top) { [SCIUtils showErrorHUDWithDescription:@"No top view controller"]; return; }

	Class notesClass = NSClassFromString(@"IGDirectNotesDogfoodingSettings.IGDirectNotesDogfoodingSettingsStaticFuncs");
	if (!notesClass) notesClass = NSClassFromString(@"_TtC31IGDirectNotesDogfoodingSettings42IGDirectNotesDogfoodingSettingsStaticFuncs");
	SEL openSel = @selector(notesDogfoodingSettingsOpenOnViewController:userSession:);
	if (notesClass && [notesClass respondsToSelector:openSel]) {
		@try {
			typedef void (*OpenIMP)(id, SEL, id, id);
			((OpenIMP)objc_msgSend)(notesClass, openSel, top, session);
			dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.35 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
				[SCILauncherOverride replayPersistedOverrides];
			});
			return;
		} @catch (__unused id e) {}
	}
	[SCIUtils showErrorHUDWithDescription:@"Notes dogfooding unavailable"];
}

// ---- MetaLocalExperiment native browser ----
// Init signature confirmed: initWithExperimentConfigs:experimentGenerator:
// Configs collected via protocol conformance scan over the loaded class set.
// Pattern extracted from the disabled SCIExpFlagsViewController code path.

+ (NSArray *)sciCollectMetaLocalExperimentConfigs {
	Protocol *p = objc_getProtocol("MetaLocalExperimentConfigProtocol");
	if (!p) return @[];
	unsigned int n = 0;
	// Enumerate the runtime class set to find every type conforming to
	// MetaLocalExperimentConfigProtocol — the native browser VC requires this
	// array, and there is no public registry to query in its place.
	Class *all = objc_copyClassList(&n);
	NSMutableArray *out = [NSMutableArray array];
	for (unsigned int i = 0; i < n; i++) {
		if (class_conformsToProtocol(all[i], p)) {
			@try {
				id x = [[all[i] alloc] init];
				if (x) [out addObject:x];
			} @catch (__unused id e) {}
		}
	}
	if (all) free(all);
	return out;
}

+ (id)sciBuildExperimentGenerator {
	Class c = NSClassFromString(@"LIDExperimentGenerator");
	if (!c) return nil;
	SEL s = @selector(initWithDeviceID:logger:);
	if (![c instancesRespondToSelector:s]) return nil;
	@try {
		typedef id (*InitIMP)(id, SEL, id, id);
		return ((InitIMP)objc_msgSend)([c alloc], s, nil, nil);
	} @catch (__unused id e) { return nil; }
}

+ (void)presentMetaLocalExperimentBrowser {
	UIViewController *top = sciDogfoodTopVC();
	if (!top) { [SCIUtils showErrorHUDWithDescription:@"No top view controller"]; return; }

	Class cls = NSClassFromString(@"MetaLocalExperimentListViewController");
	if (!cls) { [SCIUtils showErrorHUDWithDescription:@"MetaLocalExperiment browser not registered"]; return; }

	UIViewController *vc = nil;
	SEL initSel = @selector(initWithExperimentConfigs:experimentGenerator:);
	@try {
		if ([cls instancesRespondToSelector:initSel]) {
			NSArray *configs = [self sciCollectMetaLocalExperimentConfigs];
			id gen = [self sciBuildExperimentGenerator];
			typedef id (*InitIMP)(id, SEL, id, id);
			vc = ((InitIMP)objc_msgSend)([cls alloc], initSel, configs, gen);
		} else {
			vc = [[cls alloc] init];
		}
	} @catch (__unused id e) {}

	if (![vc isKindOfClass:UIViewController.class]) {
		[SCIUtils showErrorHUDWithDescription:@"MetaLocalExperiment init failed"];
		return;
	}
	sciInstallBackButtonOnController(vc, @"Back");
	UINavigationController *nav = sciWrapInNav(vc);
	nav.navigationBar.prefersLargeTitles = NO;
	[top presentViewController:nav animated:YES completion:nil];
}

@end
