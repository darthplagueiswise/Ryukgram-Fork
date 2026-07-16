#import "SCIInternalMenusLauncher.h"
#import "SCIDogfoodObjectRuntime.h"
#import <UIKit/UIKit.h>
#import <objc/message.h>
#import <objc/runtime.h>
#import <os/log.h>
#import <string.h>

#define IDMFLOG(fmt, ...) os_log(OS_LOG_DEFAULT, "[SCIGate] IGDebugMenuFix " fmt, ##__VA_ARGS__)

// Revalidated in Instagram(4), SHA-256
// a562b3626c663eec47b41ed1bca7a7af6aa00cc30bada3293046f7cce1a555aa:
//
//   -[IGWindow showDebugMenu]                v16@0:8
//   -[IGWindow showDebugMenuWithEntryPoint:] v24@0:8q16
//
// Entry-point mapping decoded from the native static-string descriptors:
//   1 = rageshake
//   2 = long_press_home_button
//   3 = settings
//   0/default = other
//
// showDebugMenuWithEntryPoint: returns immediately when the helper at
// 0x10977BB10 rejects the request. That helper reads standardUserDefaults using
// the native descriptor "user-opted-in-for-rageshake". This hook satisfies that
// local gate only for the native call, after RyukGram's sheet has finished
// dismissing. No timer, polling loop, inline patch or launch-time scan.

static BOOL sSCIIGDebugMenuOpenInFlight = NO;
static NSString *const kSCIIGRageShakeOptInKey = @"user-opted-in-for-rageshake";

static UIWindow *SCIIGActiveWindow(void) {
	Class igWindowClass = NSClassFromString(@"IGWindow");
	if (!igWindowClass) return nil;

	UIWindow *fallback = nil;
	for (UIScene *scene in UIApplication.sharedApplication.connectedScenes) {
		if (![scene isKindOfClass:UIWindowScene.class] ||
			scene.activationState != UISceneActivationStateForegroundActive) {
			continue;
		}
		for (UIWindow *window in ((UIWindowScene *)scene).windows) {
			if (![window isKindOfClass:igWindowClass]) continue;
			if (window.isKeyWindow) return window;
			if (!fallback) fallback = window;
		}
	}
	return fallback;
}

static UIViewController *SCIIGPresentedContainerForTop(UIViewController *top) {
	if (!top) return nil;

	UINavigationController *nav = top.navigationController;
	if (nav.presentingViewController) return nav;

	UITabBarController *tab = top.tabBarController;
	if (tab.presentingViewController) return tab;

	UIViewController *candidate = top;
	while (candidate.parentViewController &&
		candidate.parentViewController != candidate) {
		UIViewController *parent = candidate.parentViewController;
		if (parent.presentingViewController) return parent;
		candidate = parent;
	}

	return top.presentingViewController ? top : nil;
}

static void SCIIGDismissRyukGramSurface(dispatch_block_t completion) {
	UIViewController *top = [SCIDogfoodObjectRuntime topViewController];
	UIViewController *container = SCIIGPresentedContainerForTop(top);

	if (container && !container.isBeingDismissed) {
		[container dismissViewControllerAnimated:YES completion:^{
			dispatch_async(dispatch_get_main_queue(), completion);
		}];
		return;
	}

	UIWindow *sourceWindow = top.view.window;
	UIViewController *root = sourceWindow.rootViewController;
	if (root.presentedViewController && !root.presentedViewController.isBeingDismissed) {
		[root dismissViewControllerAnimated:YES completion:^{
			dispatch_async(dispatch_get_main_queue(), completion);
		}];
		return;
	}

	dispatch_async(dispatch_get_main_queue(), completion);
}

static void SCIIGCompleteDebugMenuError(void (^completion)(NSString *), NSString *message) {
	if (!completion) return;
	dispatch_async(dispatch_get_main_queue(), ^{
		completion(message ?: @"error: unknown debug-menu failure");
	});
}

%group SCIInstagramDebugMenuOpenerFixGroup

%hook SCIInternalMenusLauncher

+ (void)openInstagramDebugMenuWithCompletion:(void (^)(NSString *result))completion {
	dispatch_async(dispatch_get_main_queue(), ^{
		if (sSCIIGDebugMenuOpenInFlight) {
			SCIIGCompleteDebugMenuError(completion,
				@"error: a native Instagram Debug Menu request is already running");
			return;
		}

		UIWindow *target = SCIIGActiveWindow();
		if (!target) {
			SCIIGCompleteDebugMenuError(completion, @"error: no foreground IGWindow");
			return;
		}

		SEL entrySelector = NSSelectorFromString(@"showDebugMenuWithEntryPoint:");
		Method entryMethod = class_getInstanceMethod([target class], entrySelector);
		const char *entryEncoding = entryMethod ? method_getTypeEncoding(entryMethod) : NULL;
		BOOL hasSettingsEntry = entryMethod && entryEncoding &&
			strcmp(entryEncoding, "v24@0:8q16") == 0;

		SEL fallbackSelector = NSSelectorFromString(@"showDebugMenu");
		Method fallbackMethod = class_getInstanceMethod([target class], fallbackSelector);
		const char *fallbackEncoding = fallbackMethod ? method_getTypeEncoding(fallbackMethod) : NULL;
		BOOL hasFallback = fallbackMethod && fallbackEncoding &&
			strcmp(fallbackEncoding, "v16@0:8") == 0;

		if (!hasSettingsEntry && !hasFallback) {
			SCIIGCompleteDebugMenuError(completion,
				[NSString stringWithFormat:
					@"error: IGWindow debug-menu ABI changed (entry=%s fallback=%s)",
					entryEncoding ?: "missing", fallbackEncoding ?: "missing"]);
			return;
		}

		sSCIIGDebugMenuOpenInFlight = YES;

		SCIIGDismissRyukGramSurface(^{
			NSUserDefaults *defaults = NSUserDefaults.standardUserDefaults;
			id previous = [defaults objectForKey:kSCIIGRageShakeOptInKey];
			BOOL hadPrevious = previous != nil;
			[defaults setBool:YES forKey:kSCIIGRageShakeOptInKey];

			[target makeKeyAndVisible];

			@try {
				if (hasSettingsEntry) {
					((void (*)(id, SEL, NSInteger))objc_msgSend)(
						target, entrySelector, 3
					);
					IDMFLOG("requested native menu through settings entryPoint=3");
				} else {
					((void (*)(id, SEL))objc_msgSend)(target, fallbackSelector);
					IDMFLOG("requested native menu through showDebugMenu fallback");
				}
			} @catch (id exception) {
				if (hadPrevious) [defaults setObject:previous forKey:kSCIIGRageShakeOptInKey];
				else [defaults removeObjectForKey:kSCIIGRageShakeOptInKey];
				sSCIIGDebugMenuOpenInFlight = NO;
				SCIIGCompleteDebugMenuError(completion,
					[NSString stringWithFormat:
						@"error: native Instagram Debug Menu threw: %@", exception]);
				return;
			}

			// The proven rageshake preference is read by the synchronous preflight
			// before Instagram enters its account/build callback path. Restore it on
			// the following main-loop turn without introducing a timer-based retry.
			dispatch_async(dispatch_get_main_queue(), ^{
				if (hadPrevious) [defaults setObject:previous forKey:kSCIIGRageShakeOptInKey];
				else [defaults removeObjectForKey:kSCIIGRageShakeOptInKey];
				sSCIIGDebugMenuOpenInFlight = NO;
			});

			// Deliberately do not call the completion on success. The native opener
			// presents asynchronously; the Dev row must not cover it with a result
			// alert. Errors above still reach the completion immediately.
		});
	});
}

+ (NSString *)openInstagramDebugMenu {
	[self openInstagramDebugMenuWithCompletion:nil];
	return @"requested native Instagram Debug Menu through settings entry point";
}

%end
%end

%ctor {
	@autoreleasepool {
		%init(SCIInstagramDebugMenuOpenerFixGroup);
	}
}
