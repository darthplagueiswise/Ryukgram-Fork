#import "SCIInternalMenusLauncher.h"
#import "../../Utils.h"
#import <UIKit/UIKit.h>
#import <objc/message.h>
#import <objc/runtime.h>
#import <substrate.h>
#import <os/log.h>
#import <string.h>

#define DMFIXLOG(fmt, ...) os_log(OS_LOG_DEFAULT, "[SCIGate] DebugMenuFix " fmt, ##__VA_ARGS__)

typedef void (^SCIDebugMenuCompletion)(NSString *result);

void SCIInstallEmployeeInternalHooksIfNeeded(void);
void SCIInstallGraphQLDogfoodForceHooksIfNeeded(void);

static void (*orig_SCIOpenInstagramDebugMenu)(id, SEL, SCIDebugMenuCompletion) = NULL;
static BOOL sSCIDebugMenuFixRequestInFlight = NO;

static UIWindow *SCIDMForegroundKeyWindow(void) {
	UIWindow *fallback = nil;
	for (UIScene *scene in UIApplication.sharedApplication.connectedScenes) {
		if (![scene isKindOfClass:UIWindowScene.class] ||
			scene.activationState != UISceneActivationStateForegroundActive) continue;
		for (UIWindow *window in ((UIWindowScene *)scene).windows) {
			if (window.hidden || window.alpha <= 0.0) continue;
			if (window.isKeyWindow) return window;
			if (!fallback && window.windowLevel == UIWindowLevelNormal) fallback = window;
		}
	}
	return fallback;
}

static UIWindow *SCIDMActiveIGWindow(void) {
	Class igWindowClass = NSClassFromString(@"IGWindow");
	if (!igWindowClass) return nil;

	UIWindow *fallback = nil;
	for (UIScene *scene in UIApplication.sharedApplication.connectedScenes) {
		if (![scene isKindOfClass:UIWindowScene.class] ||
			scene.activationState != UISceneActivationStateForegroundActive) continue;
		for (UIWindow *window in ((UIWindowScene *)scene).windows) {
			if (![window isKindOfClass:igWindowClass]) continue;
			if (window.isKeyWindow) return window;
			if (!fallback) fallback = window;
		}
	}
	return fallback;
}

static BOOL SCIDMStringContainsNeedle(NSString *value, NSArray<NSString *> *needles) {
	if (!value.length) return NO;
	for (NSString *needle in needles) {
		if ([value rangeOfString:needle options:NSCaseInsensitiveSearch].location != NSNotFound) {
			return YES;
		}
	}
	return NO;
}

static BOOL SCIDMControllerLooksNativeDebug(UIViewController *controller) {
	if (!controller) return NO;
	NSString *className = NSStringFromClass(controller.class) ?: @"";
	if ([className hasPrefix:@"SCI"] || [className containsString:@"Ryuk"]) return NO;

	NSArray<NSString *> *classNeedles = @[
		@"IGBugReportMenuViewController",
		@"BugReport", @"RageShake", @"InternalSettings",
		@"Dogfooding", @"DebugMenu"
	];
	if (SCIDMStringContainsNeedle(className, classNeedles)) return YES;

	NSArray<NSString *> *titleNeedles = @[
		@"Internal Settings", @"Report a Problem", @"Bug Report",
		@"Dogfooding", @"Debug Menu"
	];
	return SCIDMStringContainsNeedle(controller.title, titleNeedles);
}

static UIViewController *SCIDMFindNativeDebugController(UIViewController *controller) {
	if (!controller) return nil;
	if (SCIDMControllerLooksNativeDebug(controller)) return controller;

	UIViewController *presented = controller.presentedViewController;
	if (presented) {
		UIViewController *match = SCIDMFindNativeDebugController(presented);
		if (match) return match;
	}

	if ([controller isKindOfClass:UINavigationController.class]) {
		UIViewController *match = SCIDMFindNativeDebugController(
			((UINavigationController *)controller).visibleViewController
		);
		if (match) return match;
	}

	if ([controller isKindOfClass:UITabBarController.class]) {
		UIViewController *match = SCIDMFindNativeDebugController(
			((UITabBarController *)controller).selectedViewController
		);
		if (match) return match;
	}

	for (UIViewController *child in controller.childViewControllers.reverseObjectEnumerator) {
		UIViewController *match = SCIDMFindNativeDebugController(child);
		if (match) return match;
	}
	return nil;
}

static BOOL SCIDMControllerIsTransitioning(UIViewController *controller) {
	if (!controller) return NO;
	if (controller.isBeingPresented || controller.isBeingDismissed) return YES;
	if (controller.transitionCoordinator) return YES;
	UIViewController *presented = controller.presentedViewController;
	return presented && (presented.isBeingPresented || presented.isBeingDismissed || presented.transitionCoordinator);
}

static UIViewController *SCIDMOutermostPresentedContainer(UIWindow *window) {
	UIViewController *root = window.rootViewController;
	UIViewController *presented = root.presentedViewController;
	if (!presented) return nil;
	while (presented.presentedViewController) presented = presented.presentedViewController;
	while (presented.parentViewController) presented = presented.parentViewController;
	return presented;
}

static void SCIDMWaitUntilWindowReady(
	UIWindow *window,
	NSUInteger remaining,
	void (^completion)(BOOL ready)
) {
	dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.05 * NSEC_PER_SEC)),
		dispatch_get_main_queue(), ^{
			UIViewController *root = window.rootViewController;
			BOOL ready = root && !root.presentedViewController && !SCIDMControllerIsTransitioning(root);
			if (ready || remaining <= 1) {
				if (completion) completion(ready);
				return;
			}
			SCIDMWaitUntilWindowReady(window, remaining - 1, completion);
		});
}

static void SCIDMPollForNativeMenu(
	UIWindow *window,
	NSUInteger remaining,
	void (^completion)(UIViewController *controller)
) {
	dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.25 * NSEC_PER_SEC)),
		dispatch_get_main_queue(), ^{
			UIViewController *match = SCIDMFindNativeDebugController(window.rootViewController);
			if (match || remaining <= 1) {
				if (completion) completion(match);
				return;
			}
			SCIDMPollForNativeMenu(window, remaining - 1, completion);
		});
}

static void SCIDMDismissSettingsHierarchy(UIWindow *target, void (^completion)(BOOL ready)) {
	UIWindow *current = SCIDMForegroundKeyWindow();
	UIViewController *presentedContainer = current ? SCIDMOutermostPresentedContainer(current) : nil;

	void (^clearNativePresenter)(void) = ^{
		SEL dismissSelector = NSSelectorFromString(@"dismissPresentedViewController");
		Method dismissMethod = class_getInstanceMethod(target.class, dismissSelector);
		const char *encoding = dismissMethod ? method_getTypeEncoding(dismissMethod) : NULL;
		if (encoding && strcmp(encoding, "v16@0:8") == 0 &&
			target.rootViewController.presentedViewController) {
			@try {
				((void (*)(id, SEL))objc_msgSend)(target, dismissSelector);
			} @catch (id exception) {
				DMFIXLOG("native dismiss threw: %{public}@", exception);
			}
		}
		SCIDMWaitUntilWindowReady(target, 60, completion);
	};

	if (presentedContainer && presentedContainer.presentingViewController) {
		[presentedContainer dismissViewControllerAnimated:NO completion:clearNativePresenter];
		return;
	}

	UIViewController *root = current.rootViewController;
	if (root.presentedViewController) {
		[root dismissViewControllerAnimated:NO completion:clearNativePresenter];
		return;
	}

	clearNativePresenter();
}

static void SCIFixedOpenInstagramDebugMenu(
	id self,
	SEL _cmd,
	SCIDebugMenuCompletion completion
) {
	(void)self;
	(void)_cmd;
	dispatch_async(dispatch_get_main_queue(), ^{
		if (sSCIDebugMenuFixRequestInFlight) {
			if (completion) completion(@"error: a native debug-menu request is already running");
			return;
		}

		UIWindow *target = SCIDMActiveIGWindow();
		if (!target) {
			if (completion) completion(@"error: no foreground IGWindow");
			return;
		}

		SEL entrySelector = NSSelectorFromString(@"showDebugMenuWithEntryPoint:");
		Method entryMethod = class_getInstanceMethod(target.class, entrySelector);
		const char *entryEncoding = entryMethod ? method_getTypeEncoding(entryMethod) : NULL;
		BOOL canEntryZero = entryEncoding && strcmp(entryEncoding, "v24@0:8q16") == 0;

		SEL showSelector = NSSelectorFromString(@"showDebugMenu");
		Method showMethod = class_getInstanceMethod(target.class, showSelector);
		const char *showEncoding = showMethod ? method_getTypeEncoding(showMethod) : NULL;
		BOOL canShow = showEncoding && strcmp(showEncoding, "v16@0:8") == 0;

		if (!canEntryZero && !canShow) {
			if (completion) {
				completion([NSString stringWithFormat:
					@"error: IGWindow debug-menu ABI unavailable (entry=%s show=%s)",
					entryEncoding ?: "missing", showEncoding ?: "missing"]);
			}
			return;
		}

		SCIInstallEmployeeInternalHooksIfNeeded();
		SCIInstallGraphQLDogfoodForceHooksIfNeeded();

		sSCIDebugMenuFixRequestInFlight = YES;
		NSUserDefaults *defaults = NSUserDefaults.standardUserDefaults;
		NSString *optInKey = @"user-opted-in-for-rageshake";
		id previousOptIn = [defaults objectForKey:optInKey];
		BOOL hadPreviousOptIn = previousOptIn != nil;
		[defaults setObject:@YES forKey:optInKey];

		__block BOOL finished = NO;
		void (^finishOnce)(NSString *) = ^(NSString *result) {
			if (finished) return;
			finished = YES;
			sSCIDebugMenuFixRequestInFlight = NO;
			if (hadPreviousOptIn) [defaults setObject:previousOptIn forKey:optInKey];
			else [defaults removeObjectForKey:optInKey];
			if (completion) completion(result ?: @"unknown result");
		};

		SCIDMDismissSettingsHierarchy(target, ^(BOOL ready) {
			if (!ready) {
				finishOnce(@"error: RyukGram presentation hierarchy did not fully dismiss");
				return;
			}

			[target makeKeyAndVisible];
			dispatch_async(dispatch_get_main_queue(), ^{
				@try {
					if (canEntryZero) {
						((void (*)(id, SEL, NSInteger))objc_msgSend)(target, entrySelector, 0);
						DMFIXLOG("invoked -showDebugMenuWithEntryPoint:0");
					} else {
						((void (*)(id, SEL))objc_msgSend)(target, showSelector);
						DMFIXLOG("invoked -showDebugMenu fallback");
					}
				} @catch (id exception) {
					finishOnce([NSString stringWithFormat:
						@"error: native debug-menu opener threw: %@", exception]);
					return;
				}

				SCIDMPollForNativeMenu(target, 40, ^(UIViewController *controller) {
					if (controller) {
						finishOnce([NSString stringWithFormat:@"presented %@",
							NSStringFromClass(controller.class) ?: @"native debug controller"]);
						return;
					}
					finishOnce(@"error: -showDebugMenuWithEntryPoint:0 returned without a native debug controller. Presentation collision was cleared; a native account/build/internal gate rejected the request. Check GraphQL dogfood snapshot for eligibility and repeated _ig_is_employee build/update checks.");
				});
			});
		});
	});
}

__attribute__((constructor))
static void SCIInstallInstagramDebugMenuPresentationFix(void) {
	@autoreleasepool {
		Class cls = objc_getClass("SCIInternalMenusLauncher");
		Class meta = cls ? object_getClass(cls) : Nil;
		SEL selector = sel_registerName("openInstagramDebugMenuWithCompletion:");
		Method method = meta ? class_getInstanceMethod(meta, selector) : NULL;
		if (!method || method_getNumberOfArguments(method) != 3) {
			DMFIXLOG("launcher method unavailable");
			return;
		}

		char returnType[8] = {0};
		method_getReturnType(method, returnType, sizeof(returnType));
		if (returnType[0] != 'v') {
			DMFIXLOG("launcher ABI changed: %{public}s", method_getTypeEncoding(method));
			return;
		}

		MSHookMessageEx(meta, selector,
			(IMP)SCIFixedOpenInstagramDebugMenu,
			(IMP *)&orig_SCIOpenInstagramDebugMenu);
		DMFIXLOG("presentation fix %{public}s",
			orig_SCIOpenInstagramDebugMenu ? "installed" : "not installed");
	}
}
