#import "SCIInternalMenusLauncher.h"
#import "../../Utils.h"
#import <UIKit/UIKit.h>
#import <objc/message.h>
#import <objc/runtime.h>
#import <os/log.h>
#import <string.h>

#define DMLOG(fmt, ...) os_log(OS_LOG_DEFAULT, "[SCIGate] InstagramDebugMenu " fmt, ##__VA_ARGS__)

typedef void (^SCIDebugMenuCompletion)(NSString *result);

void SCIInstallEmployeeInternalHooksIfNeeded(void);
void SCIInstallGraphQLDogfoodForceHooksIfNeeded(void);

static BOOL sSCIDebugMenuRequestInFlight = NO;

static BOOL SCIDMEncodingMatches(Method method, const char *expected) {
	if (!method || !expected) return NO;
	const char *encoding = method_getTypeEncoding(method);
	return encoding && strcmp(encoding, expected) == 0;
}

static NSArray<UIWindow *> *SCIDMForegroundWindows(void) {
	NSMutableArray<UIWindow *> *windows = [NSMutableArray array];
	for (UIScene *scene in UIApplication.sharedApplication.connectedScenes) {
		if (![scene isKindOfClass:UIWindowScene.class] ||
			scene.activationState != UISceneActivationStateForegroundActive) continue;
		for (UIWindow *window in ((UIWindowScene *)scene).windows) {
			if (!window.hidden && window.alpha > 0.0 && window.rootViewController) {
				[windows addObject:window];
			}
		}
	}
	return windows.copy;
}

static UIViewController *SCIDMNativePresenterForIGWindow(UIWindow *window) {
	if (!window) return nil;
	SEL selector = NSSelectorFromString(@"presentingViewController");
	Method method = class_getInstanceMethod(window.class, selector);
	if (SCIDMEncodingMatches(method, "@16@0:8")) {
		@try {
			id presenter = ((id (*)(id, SEL))objc_msgSend)(window, selector);
			if ([presenter isKindOfClass:UIViewController.class]) return presenter;
		} @catch (id exception) {
			DMLOG("presentingViewController threw: %{public}@", exception);
		}
	}
	return window.rootViewController;
}

static NSInteger SCIDMScoreIGWindow(UIWindow *window) {
	Class igWindowClass = NSClassFromString(@"IGWindow");
	if (!igWindowClass || ![window isKindOfClass:igWindowClass]) return NSIntegerMin;

	NSInteger score = 0;
	if (window.isKeyWindow) score += 200;
	if (window.windowLevel == UIWindowLevelNormal) score += 40;
	if (window.screen == UIScreen.mainScreen) score += 20;
	if (window.rootViewController.viewIfLoaded.window == window) score += 30;

	UIViewController *presenter = SCIDMNativePresenterForIGWindow(window);
	if (presenter) score += 100;
	if (presenter.viewIfLoaded.window == window) score += 80;
	return score;
}

static UIWindow *SCIDMBestIGWindow(void) {
	UIWindow *best = nil;
	NSInteger bestScore = NSIntegerMin;
	for (UIWindow *window in SCIDMForegroundWindows()) {
		NSInteger score = SCIDMScoreIGWindow(window);
		if (score > bestScore) {
			best = window;
			bestScore = score;
		}
	}
	DMLOG("selected IGWindow=%{public}@ score=%ld key=%d",
	      best, (long)bestScore, best.isKeyWindow);
	return best;
}

static UIViewController *SCIDMDeepestController(UIViewController *controller) {
	UIViewController *current = controller;
	BOOL advanced = YES;
	while (current && advanced) {
		advanced = NO;
		if (current.presentedViewController) {
			current = current.presentedViewController;
			advanced = YES;
			continue;
		}
		if ([current isKindOfClass:UINavigationController.class]) {
			UIViewController *visible = ((UINavigationController *)current).visibleViewController;
			if (visible && visible != current) {
				current = visible;
				advanced = YES;
				continue;
			}
		}
		if ([current isKindOfClass:UITabBarController.class]) {
			UIViewController *selected = ((UITabBarController *)current).selectedViewController;
			if (selected && selected != current) {
				current = selected;
				advanced = YES;
			}
		}
	}
	return current;
}

static BOOL SCIDMContains(NSString *value, NSArray<NSString *> *needles) {
	for (NSString *needle in needles) {
		if ([value rangeOfString:needle options:NSCaseInsensitiveSearch].location != NSNotFound) {
			return YES;
		}
	}
	return NO;
}

static BOOL SCIDMLooksLikeNativeDebugController(UIViewController *controller) {
	if (!controller) return NO;
	NSString *className = NSStringFromClass(controller.class) ?: @"";
	if ([className hasPrefix:@"SCI"] || [className containsString:@"Ryuk"]) return NO;
	if (SCIDMContains(className, @[
		@"IGBugReportMenuViewController", @"BugReport", @"RageShake",
		@"InternalSettings", @"Dogfooding", @"DebugMenu"
	])) return YES;
	return SCIDMContains(controller.title ?: @"", @[
		@"Internal Settings", @"Report a Problem", @"Bug Report",
		@"Dogfooding", @"Debug Menu"
	]);
}

static UIViewController *SCIDMFindNativeDebugController(UIViewController *controller) {
	if (!controller) return nil;
	if (SCIDMLooksLikeNativeDebugController(controller)) return controller;
	if (controller.presentedViewController) {
		UIViewController *match = SCIDMFindNativeDebugController(controller.presentedViewController);
		if (match) return match;
	}
	if ([controller isKindOfClass:UINavigationController.class]) {
		UIViewController *match = SCIDMFindNativeDebugController(
			((UINavigationController *)controller).visibleViewController);
		if (match) return match;
	}
	if ([controller isKindOfClass:UITabBarController.class]) {
		UIViewController *match = SCIDMFindNativeDebugController(
			((UITabBarController *)controller).selectedViewController);
		if (match) return match;
	}
	for (UIViewController *child in controller.childViewControllers.reverseObjectEnumerator) {
		UIViewController *match = SCIDMFindNativeDebugController(child);
		if (match) return match;
	}
	return nil;
}

static UIViewController *SCIDMFindNativeMenuInForegroundWindows(void) {
	for (UIWindow *window in SCIDMForegroundWindows()) {
		UIViewController *match = SCIDMFindNativeDebugController(window.rootViewController);
		if (match) return match;
	}
	return nil;
}

static BOOL SCIDMControllerTransitioning(UIViewController *controller) {
	if (!controller) return NO;
	if (controller.isBeingPresented || controller.isBeingDismissed) return YES;
	if (controller.transitionCoordinator) return YES;
	UIViewController *presented = controller.presentedViewController;
	return presented && (presented.isBeingPresented || presented.isBeingDismissed ||
		presented.transitionCoordinator);
}

static void SCIDMWaitUntilReady(UIWindow *window, NSUInteger remaining,
	void (^completion)(BOOL ready)) {
	dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.05 * NSEC_PER_SEC)),
		dispatch_get_main_queue(), ^{
			UIViewController *root = window.rootViewController;
			UIViewController *nativePresenter = SCIDMNativePresenterForIGWindow(window);
			BOOL ready = root && nativePresenter &&
				!root.presentedViewController &&
				!nativePresenter.presentedViewController &&
				!SCIDMControllerTransitioning(root) &&
				!SCIDMControllerTransitioning(nativePresenter);
			if (ready || remaining <= 1) {
				if (completion) completion(ready);
				return;
			}
			SCIDMWaitUntilReady(window, remaining - 1, completion);
		});
}

static void SCIDMDismissRyukGramAndNativePresentation(UIWindow *target,
	void (^completion)(BOOL ready)) {
	UIWindow *currentKey = nil;
	for (UIWindow *window in SCIDMForegroundWindows()) {
		if (window.isKeyWindow) { currentKey = window; break; }
	}

	void (^clearTarget)(void) = ^{
		SEL dismissSelector = NSSelectorFromString(@"dismissPresentedViewController");
		Method dismissMethod = class_getInstanceMethod(target.class, dismissSelector);
		if (SCIDMEncodingMatches(dismissMethod, "v16@0:8")) {
			UIViewController *presenter = SCIDMNativePresenterForIGWindow(target);
			if (presenter.presentedViewController || target.rootViewController.presentedViewController) {
				@try {
					((void (*)(id, SEL))objc_msgSend)(target, dismissSelector);
				} @catch (id exception) {
					DMLOG("IGWindow dismissPresentedViewController threw: %{public}@", exception);
				}
			}
		}
		SCIDMWaitUntilReady(target, 80, completion);
	};

	UIViewController *currentRoot = currentKey.rootViewController;
	UIViewController *presented = currentRoot.presentedViewController;
	if (presented && !SCIDMLooksLikeNativeDebugController(
		SCIDMDeepestController(presented))) {
		[currentRoot dismissViewControllerAnimated:YES completion:clearTarget];
		return;
	}
	clearTarget();
}

static void SCIDMPollForPresentation(NSUInteger remaining,
	void (^completion)(UIViewController *controller)) {
	dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.25 * NSEC_PER_SEC)),
		dispatch_get_main_queue(), ^{
			UIViewController *match = SCIDMFindNativeMenuInForegroundWindows();
			if (match || remaining <= 1) {
				if (completion) completion(match);
				return;
			}
			SCIDMPollForPresentation(remaining - 1, completion);
		});
}

%group SCIInstagramDebugMenuDirectGroup

%hook SCIInternalMenusLauncher

+ (void)openInstagramDebugMenuWithCompletion:(SCIDebugMenuCompletion)completion {
	dispatch_async(dispatch_get_main_queue(), ^{
		if (sSCIDebugMenuRequestInFlight) {
			if (completion) completion(@"error: a native debug-menu request is already running");
			return;
		}

		UIWindow *target = SCIDMBestIGWindow();
		if (!target) {
			if (completion) completion(@"error: no usable foreground IGWindow");
			return;
		}

		SEL showSelector = NSSelectorFromString(@"showDebugMenu");
		Method showMethod = class_getInstanceMethod(target.class, showSelector);
		BOOL canShow = SCIDMEncodingMatches(showMethod, "v16@0:8");

		SEL entrySelector = NSSelectorFromString(@"showDebugMenuWithEntryPoint:");
		Method entryMethod = class_getInstanceMethod(target.class, entrySelector);
		BOOL canEntryZero = SCIDMEncodingMatches(entryMethod, "v24@0:8q16");

		if (!canShow && !canEntryZero) {
			if (completion) completion([NSString stringWithFormat:
				@"error: IGWindow debug-menu ABI unavailable (show=%s entry=%s)",
				showMethod ? method_getTypeEncoding(showMethod) : "missing",
				entryMethod ? method_getTypeEncoding(entryMethod) : "missing"]);
			return;
		}

		SCIInstallEmployeeInternalHooksIfNeeded();
		SCIInstallGraphQLDogfoodForceHooksIfNeeded();

		sSCIDebugMenuRequestInFlight = YES;
		NSUserDefaults *defaults = NSUserDefaults.standardUserDefaults;
		NSString *optInKey = @"user-opted-in-for-rageshake";
		id previousOptIn = [defaults objectForKey:optInKey];
		BOOL hadPreviousOptIn = previousOptIn != nil;
		[defaults setObject:@YES forKey:optInKey];
		[defaults synchronize];

		__block BOOL completed = NO;
		void (^finishOnce)(NSString *) = ^(NSString *result) {
			if (completed) return;
			completed = YES;
			sSCIDebugMenuRequestInFlight = NO;
			if (hadPreviousOptIn) [defaults setObject:previousOptIn forKey:optInKey];
			else [defaults removeObjectForKey:optInKey];
			[defaults synchronize];
			if (completion) completion(result ?: @"unknown result");
		};

		SCIDMDismissRyukGramAndNativePresentation(target, ^(BOOL ready) {
			if (!ready) {
				finishOnce(@"error: presentation hierarchy did not become ready after dismissing RyukGram");
				return;
			}

			[target makeKeyWindow];
			dispatch_after(dispatch_time(DISPATCH_TIME_NOW,
				(int64_t)(0.20 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
				@try {
					// Prefer the validated native zero-argument thunk. It sets entryPoint=0
					// and dispatches to -showDebugMenuWithEntryPoint:.
					if (canShow) {
						((void (*)(id, SEL))objc_msgSend)(target, showSelector);
						DMLOG("invoked -[IGWindow showDebugMenu]");
					} else {
						((void (*)(id, SEL, NSInteger))objc_msgSend)(target, entrySelector, 0);
						DMLOG("invoked -[IGWindow showDebugMenuWithEntryPoint:0]");
					}
				} @catch (id exception) {
					finishOnce([NSString stringWithFormat:
						@"error: native debug-menu opener threw: %@", exception]);
					return;
				}

				SCIDMPollForPresentation(48, ^(UIViewController *controller) {
					if (controller) {
						finishOnce([NSString stringWithFormat:@"presented %@",
							NSStringFromClass(controller.class) ?: @"native debug controller"]);
						return;
					}
					finishOnce(@"error: the validated IGWindow opener ran after the presentation hierarchy was cleared, but no native debug controller appeared. This is now a native account/build/internal gate result, not a RyukGram sheet collision. Check GraphQL dogfood snapshot for eligibility, warning expiration, update checks and build-status checks.");
				});
			});
		});
	});
}

%end
%end

%ctor {
	@autoreleasepool {
		%init(SCIInstagramDebugMenuDirectGroup);
	}
}
