#import "SCIDogfooding.h"
#import "../../Utils.h"
#import "../../UI/SCIUIKit26LiquidGlass.h"
#import "SCILauncherOverride.h"
#import "SCIDogfoodObjectRuntime.h"
#import <objc/runtime.h>
#import <objc/message.h>
#import <UIKit/UIKit.h>

static dispatch_queue_t sciMetaLocalQueue(void) {
	static dispatch_queue_t q; static dispatch_once_t once;
	dispatch_once(&once, ^{ q = dispatch_queue_create("com.ryukgram.metalocalexperiment.open", DISPATCH_QUEUE_SERIAL); });
	return q;
}

static NSArray<Class> *sciMetaLocalConfigClasses(void) {
	static NSArray<Class> *classes; static dispatch_once_t once;
	dispatch_once(&once, ^{
		Protocol *p = objc_getProtocol("MetaLocalExperimentConfigProtocol");
		if (!p) { classes = @[]; return; }
		unsigned int n = 0; Class *all = objc_copyClassList(&n);
		NSMutableArray<Class> *out = [NSMutableArray array];
		for (unsigned int i = 0; i < n; i++) {
			Class c = all[i];
			if (!c) continue;
			if (class_conformsToProtocol(c, p)) [out addObject:c];
		}
		if (all) free(all);
		classes = out.copy;
	});
	return classes ?: @[];
}

static NSArray *sciMetaLocalCachedConfigs(void) {
	static NSArray *configs;
	@synchronized (SCIDogfooding.class) {
		if (configs) return configs;
		NSMutableArray *out = [NSMutableArray array];
		for (Class c in sciMetaLocalConfigClasses()) {
			@try { id x = [[c alloc] init]; if (x) [out addObject:x]; } @catch (__unused id e) {}
		}
		configs = out.copy;
		return configs;
	}
}

static id sciMetaLocalCachedGenerator(void) {
	static id generator;
	@synchronized (SCIDogfooding.class) {
		if (generator) return generator;
		Class c = NSClassFromString(@"LIDExperimentGenerator");
		SEL s = @selector(initWithDeviceID:logger:);
		if (c && [c instancesRespondToSelector:s]) {
			@try { typedef id (*InitIMP)(id, SEL, id, id); generator = ((InitIMP)objc_msgSend)([c alloc], s, nil, nil); } @catch (__unused id e) {}
		}
		return generator;
	}
}

static UIViewController *sciMetaLocalLoadingController(void) {
	UIViewController *vc = [UIViewController new];
	vc.title = @"MetaLocalExperiment";
	SCIUIKit26ConfigureViewController(vc);
	UIActivityIndicatorView *spinner = [[UIActivityIndicatorView alloc] initWithActivityIndicatorStyle:UIActivityIndicatorViewStyleLarge];
	spinner.translatesAutoresizingMaskIntoConstraints = NO;
	[spinner startAnimating];
	UILabel *label = [UILabel new];
	label.translatesAutoresizingMaskIntoConstraints = NO;
	label.text = @"Loading native experiment browser…";
	label.textColor = UIColor.secondaryLabelColor;
	label.font = [UIFont systemFontOfSize:14.0 weight:UIFontWeightRegular];
	[vc.view addSubview:spinner]; [vc.view addSubview:label];
	[NSLayoutConstraint activateConstraints:@[
		[spinner.centerXAnchor constraintEqualToAnchor:vc.view.centerXAnchor],
		[spinner.centerYAnchor constraintEqualToAnchor:vc.view.centerYAnchor constant:-12.0],
		[label.topAnchor constraintEqualToAnchor:spinner.bottomAnchor constant:14.0],
		[label.centerXAnchor constraintEqualToAnchor:vc.view.centerXAnchor],
	]];
	return vc;
}

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
	return sciMetaLocalCachedConfigs();
}

+ (id)sciBuildExperimentGenerator {
	return sciMetaLocalCachedGenerator();
}

+ (void)presentMetaLocalExperimentBrowser {
	UIViewController *top = sciDogfoodTopVC();
	if (!top) { [SCIUtils showErrorHUDWithDescription:@"No top view controller"]; return; }

	Class cls = NSClassFromString(@"MetaLocalExperimentListViewController");
	if (!cls) { [SCIUtils showErrorHUDWithDescription:@"MetaLocalExperiment browser not registered"]; return; }

	UIViewController *loading = sciMetaLocalLoadingController();
	sciInstallBackButtonOnController(loading, @"Back");
	UINavigationController *nav = sciWrapInNav(loading);
	nav.navigationBar.prefersLargeTitles = NO;
	[top presentViewController:nav animated:YES completion:nil];

	dispatch_async(sciMetaLocalQueue(), ^{
		NSArray *configs = [self sciCollectMetaLocalExperimentConfigs];
		id gen = [self sciBuildExperimentGenerator];
		dispatch_async(dispatch_get_main_queue(), ^{
			UIViewController *vc = nil;
			SEL initSel = @selector(initWithExperimentConfigs:experimentGenerator:);
			@try {
				if ([cls instancesRespondToSelector:initSel]) {
					typedef id (*InitIMP)(id, SEL, id, id);
					vc = ((InitIMP)objc_msgSend)([cls alloc], initSel, configs ?: @[], gen);
				} else {
					vc = [[cls alloc] init];
				}
			} @catch (__unused id e) {}

			if (![vc isKindOfClass:UIViewController.class]) {
				[SCIUtils showErrorHUDWithDescription:@"MetaLocalExperiment init failed"];
				[nav dismissViewControllerAnimated:YES completion:nil];
				return;
			}
			sciInstallBackButtonOnController(vc, @"Back");
			SCIUIKit26ConfigureViewController(vc);
			[nav setViewControllers:@[vc] animated:NO];
			dispatch_async(dispatch_get_main_queue(), ^{ sciInstallBackButtonOnController(vc, @"Back"); });
		});
	});
}


@end
