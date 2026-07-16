#import "SCIInternalMenusLauncher.h"
#import <UIKit/UIKit.h>
#import <objc/message.h>
#import <objc/runtime.h>
#import <substrate.h>
#import <os/log.h>
#import <string.h>

#define IDMLOG(fmt, ...) os_log(OS_LOG_DEFAULT, "[SCIGate] DebugMenuFix " fmt, ##__VA_ARGS__)

// The Dev row is presented inside RyukGram's own sheet. Calling IGWindow's
// native opener while that sheet is still covering the Instagram window makes
// the request disappear behind the current presentation. Replace only our
// launcher entrypoint: dismiss the covering controller first, restore IGWindow
// as key, then call the validated entryPoint=0 path on the next main-loop turn.
//
// Success deliberately does not invoke the completion block. The current Dev
// row presents every non-"presented" completion as an alert; firing a synthetic
// "requested" result immediately recreates the same modal collision. Errors are
// still returned through the completion block.

static void (*orig_SCIInternalDebugMenuOpen)(id, SEL, id) = NULL;
static BOOL sSCIInternalDebugMenuFixInstalled = NO;

static UIWindow *SCIActiveInstagramWindow(void) {
	Class igWindowClass = objc_getClass("IGWindow");
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

static void SCICompleteDebugMenuError(void (^completion)(NSString *), NSString *message) {
	if (!completion) return;
	dispatch_async(dispatch_get_main_queue(), ^{
		completion(message ?: @"error: unknown debug-menu failure");
	});
}

static void SCIInternalDebugMenuOpen(id self, SEL _cmd, id completionObject) {
	(void)self;
	(void)_cmd;

	void (^completion)(NSString *) = [completionObject copy];
	dispatch_async(dispatch_get_main_queue(), ^{
		UIWindow *target = SCIActiveInstagramWindow();
		if (!target) {
			SCICompleteDebugMenuError(completion, @"error: no active IGWindow");
			return;
		}

		SEL selector = sel_registerName("showDebugMenuWithEntryPoint:");
		Method method = class_getInstanceMethod([target class], selector);
		const char *encoding = method ? method_getTypeEncoding(method) : NULL;
		if (!encoding || strcmp(encoding, "v24@0:8q16") != 0) {
			SCICompleteDebugMenuError(completion,
				[NSString stringWithFormat:
					@"error: IGWindow debug-menu ABI unavailable or changed: %s",
					encoding ?: "missing"]);
			return;
		}

		void (^invokeNative)(void) = ^{
			[target makeKeyAndVisible];
			dispatch_async(dispatch_get_main_queue(), ^{
				@try {
					((void (*)(id, SEL, NSInteger))objc_msgSend)(target, selector, 0);
					IDMLOG("requested native Instagram Debug Menu entryPoint=0");
					// Do not present a success alert over the native controller.
				} @catch (id exception) {
					SCICompleteDebugMenuError(completion,
						[NSString stringWithFormat:
							@"error: showDebugMenuWithEntryPoint: threw: %@",
							exception]);
				}
			});
		};

		UIViewController *covering = target.rootViewController.presentedViewController;
		if (covering) {
			[covering dismissViewControllerAnimated:YES completion:invokeNative];
		} else {
			invokeNative();
		}
	});
}

__attribute__((constructor))
static void SCIInstallInternalDebugMenuPresentationFix(void) {
	@autoreleasepool {
		if (sSCIInternalDebugMenuFixInstalled) return;

		Class cls = objc_getClass("SCIInternalMenusLauncher");
		Class meta = cls ? object_getClass(cls) : Nil;
		SEL selector = sel_registerName("openInstagramDebugMenuWithCompletion:");
		Method method = meta ? class_getInstanceMethod(meta, selector) : NULL;
		const char *encoding = method ? method_getTypeEncoding(method) : NULL;

		if (!encoding || strcmp(encoding, "v24@0:8@?16") != 0) {
			IDMLOG("launcher ABI unavailable or changed: %{public}s", encoding ?: "missing");
			return;
		}

		MSHookMessageEx(meta, selector,
			(IMP)SCIInternalDebugMenuOpen,
			(IMP *)&orig_SCIInternalDebugMenuOpen);
		sSCIInternalDebugMenuFixInstalled = (orig_SCIInternalDebugMenuOpen != NULL);
		IDMLOG("presentation fix %{public}s",
			sSCIInternalDebugMenuFixInstalled ? "installed" : "not installed");
	}
}
