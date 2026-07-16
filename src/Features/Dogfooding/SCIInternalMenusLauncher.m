#import "SCIInternalMenusLauncher.h"
#import "SCIDogfoodObjectRuntime.h"
#import <UIKit/UIKit.h>
#import <objc/message.h>
#import <objc/runtime.h>
#import <os/log.h>
#import <string.h>

#define MLOG(fmt,...) os_log(OS_LOG_DEFAULT,"[SCIGate] Menus " fmt,##__VA_ARGS__)

static BOOL sDebugMenuRequestInFlight = NO;
static NSString *const kSCIRageShakeOptInKey = @"user-opted-in-for-rageshake";

@implementation SCIInternalMenusLauncher

+ (UIViewController *)topVC { return [SCIDogfoodObjectRuntime topViewController]; }
+ (id)session               { return [SCIDogfoodObjectRuntime activeUserSession]; }

+ (UIWindow *)activeIGWindow {
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

+ (UIViewController *)presentedContainerForTop:(UIViewController *)top {
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

+ (void)dismissRyukGramSurfaceWithCompletion:(dispatch_block_t)completion {
	UIViewController *top = [self topVC];
	UIViewController *container = [self presentedContainerForTop:top];

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

+ (void)completeDebugMenuError:(void (^)(NSString *result))completion
	message:(NSString *)message {
	if (!completion) return;
	dispatch_async(dispatch_get_main_queue(), ^{
		completion(message ?: @"error: unknown debug-menu failure");
	});
}

// Revalidated in Instagram(4), SHA-256
// a562b3626c663eec47b41ed1bca7a7af6aa00cc30bada3293046f7cce1a555aa:
//
//   -showDebugMenu                  v16@0:8
//   -showDebugMenuWithEntryPoint:   v24@0:8q16
//
// Native entry-point mapping decoded from the static-string descriptors:
//   1 = rageshake
//   2 = long_press_home_button
//   3 = settings
//   0/default = other
//
// showDebugMenuWithEntryPoint: synchronously calls the helper at 0x10977BB10.
// That helper reads standardUserDefaults using the native descriptor
// "user-opted-in-for-rageshake" and returns false before presentation when the
// opt-in is missing. Dismiss RyukGram's actual presentation container, restore
// IGWindow as key, satisfy the local opt-in only for the native settings call,
// then restore the previous value on the following main-loop turn. There is no
// polling, dispatch_after retry, inline patch or launch-time work.
+ (void)openInstagramDebugMenuWithCompletion:(void (^)(NSString *result))completion {
	dispatch_async(dispatch_get_main_queue(), ^{
		if (sDebugMenuRequestInFlight) {
			[self completeDebugMenuError:completion
				message:@"error: a native Instagram Debug Menu request is already running"];
			return;
		}

		UIWindow *target = [self activeIGWindow];
		if (!target) {
			[self completeDebugMenuError:completion message:@"error: no foreground IGWindow"];
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
			[self completeDebugMenuError:completion
				message:[NSString stringWithFormat:
					@"error: IGWindow debug-menu ABI changed (entry=%s fallback=%s)",
					entryEncoding ?: "missing", fallbackEncoding ?: "missing"]];
			return;
		}

		sDebugMenuRequestInFlight = YES;

		[self dismissRyukGramSurfaceWithCompletion:^{
			NSUserDefaults *defaults = NSUserDefaults.standardUserDefaults;
			id previous = [defaults objectForKey:kSCIRageShakeOptInKey];
			BOOL hadPrevious = previous != nil;
			[defaults setBool:YES forKey:kSCIRageShakeOptInKey];

			[target makeKeyAndVisible];

			@try {
				if (hasSettingsEntry) {
					((void (*)(id, SEL, NSInteger))objc_msgSend)(
						target, entrySelector, 3
					);
					MLOG("Instagram debug menu requested through settings entryPoint=3");
				} else {
					((void (*)(id, SEL))objc_msgSend)(target, fallbackSelector);
					MLOG("Instagram debug menu requested through showDebugMenu fallback");
				}
			} @catch (id exception) {
				if (hadPrevious) [defaults setObject:previous forKey:kSCIRageShakeOptInKey];
				else [defaults removeObjectForKey:kSCIRageShakeOptInKey];
				sDebugMenuRequestInFlight = NO;
				[self completeDebugMenuError:completion
					message:[NSString stringWithFormat:
						@"error: native Instagram Debug Menu threw: %@", exception]];
				return;
			}

			// The proven opt-in is consumed by the synchronous native preflight.
			// Restore it one main-loop turn later without a timer-based retry.
			dispatch_async(dispatch_get_main_queue(), ^{
				if (hadPrevious) [defaults setObject:previous forKey:kSCIRageShakeOptInKey];
				else [defaults removeObjectForKey:kSCIRageShakeOptInKey];
				sDebugMenuRequestInFlight = NO;
			});

			// Success intentionally has no result alert: Instagram presents the
			// native controller asynchronously and an alert here would cover it.
			// Immediate ABI/runtime failures above still reach the completion.
		}];
	});
}

+ (NSString *)openInstagramDebugMenu {
	[self openInstagramDebugMenuWithCompletion:nil];
	return @"requested native Instagram Debug Menu through settings entry point";
}

+ (UINavigationController *)navFor:(UIViewController *)vc {
	if (!vc) return nil;
	if ([vc isKindOfClass:UINavigationController.class])
		return (UINavigationController *)vc;
	return vc.navigationController;
}

+ (NSString *)openDogfoodingNotesSettings {
	id session = [self session];
	if (!session) return @"no live user session (open after login)";

	Class C = NSClassFromString(@"IGDirectNotesDogfoodingSettingsStaticFuncs");
	if (!C) C = NSClassFromString(
		@"_TtC31IGDirectNotesDogfoodingSettings42IGDirectNotesDogfoodingSettingsStaticFuncs");
	if (!C) return @"IGDirectNotesDogfoodingSettingsStaticFuncs not found";

	SEL s = NSSelectorFromString(
		@"notesDogfoodingSettingsOpenOnViewController:userSession:");
	if (![C respondsToSelector:s]) return @"selector not found on class";

	UIViewController *top = [self topVC];
	UIViewController *presenter = [self navFor:top] ?: top;

	@try {
		((void(*)(id,SEL,id,id))objc_msgSend)(C, s, presenter, session);
		MLOG("notes dogfooding opened");
		return @"opened Notes dogfooding settings";
	} @catch (id e) {
		return [NSString stringWithFormat:@"threw: %@", e];
	}
}

+ (NSString *)openDogfoodingSettingsVC {
	id session = [self session];
	if (!session) return @"no live user session (open after login)";

	Class cfgCls = NSClassFromString(@"IGDogfoodingSettingsConfig");
	if (!cfgCls) return @"IGDogfoodingSettingsConfig not found in this build";

	id config = nil;
	@try {
		config = [[cfgCls alloc] init];
	} @catch (id e) {
		return [NSString stringWithFormat:@"config init threw: %@", e];
	}
	if (!config) return @"IGDogfoodingSettingsConfig init returned nil";

	UIViewController *top = [self topVC];

	Class factory = NSClassFromString(
		@"_TtC20IGDogfoodingSettings20IGDogfoodingSettings");
	SEL openSel = NSSelectorFromString(
		@"openWithConfig:onViewController:userSession:");
	if (factory && [factory respondsToSelector:openSel]) {
		@try {
			((void(*)(id,SEL,id,id,id))objc_msgSend)(
				factory, openSel, config, top, session
			);
			MLOG("dogfooding settings opened via factory");
			return @"opened native Dogfooding Settings";
		} @catch (__unused id e) {
			MLOG("factory threw, trying VC init fallback");
		}
	}

	Class vcCls = NSClassFromString(
		@"_TtC20IGDogfoodingSettings34IGDogfoodingSettingsViewController");
	SEL initSel = NSSelectorFromString(@"initWithConfig:userSession:");
	if (vcCls && [vcCls instancesRespondToSelector:initSel]) {
		@try {
			UIViewController *vc =
				((id(*)(id,SEL,id,id))objc_msgSend)(
					[vcCls alloc], initSel, config, session
				);
			if ([vc isKindOfClass:UIViewController.class]) {
				UINavigationController *nav =
					[[UINavigationController alloc]
						initWithRootViewController:vc];
				nav.modalPresentationStyle =
					UIModalPresentationPageSheet;

				if (!vc.navigationItem.leftBarButtonItem &&
					[vc respondsToSelector:
						NSSelectorFromString(@"closeButtonTapped")]) {
					vc.navigationItem.leftBarButtonItem =
						[[UIBarButtonItem alloc]
							initWithBarButtonSystemItem:
								UIBarButtonSystemItemDone
							target:vc
							action:NSSelectorFromString(
								@"closeButtonTapped")];
				}
				[top presentViewController:nav
					animated:YES completion:nil];
				MLOG("dogfooding settings opened via VC init");
				return @"opened native Dogfooding Settings (VC)";
			}
		} @catch (id e) {
			return [NSString stringWithFormat:@"threw: %@", e];
		}
	}

	return @"IGDogfoodingSettings entrypoints not found in this build";
}

+ (NSString *)openInternalURLString:(NSString *)urlString {
	id session = [self session];
	if (!session) return @"no live user session";

	Class C = NSClassFromString(@"IGURLHandler");
	SEL s = NSSelectorFromString(
		@"openInternalURL:presentationConfig:controller:animated:userSession:annotation:");
	if (!C || ![C respondsToSelector:s])
		return @"IGURLHandler.openInternalURL not found";

	UIViewController *top = [self topVC];
	NSURL *url = [NSURL URLWithString:urlString];

	@try {
		BOOL ok = ((BOOL(*)(id,SEL,id,id,id,BOOL,id,id))objc_msgSend)(
			C, s, url, nil, top, YES, session, nil
		);
		return ok
			? [NSString stringWithFormat:@"opened: %@", urlString]
			: @"openInternalURL returned NO";
	} @catch (id e) {
		return [NSString stringWithFormat:@"threw: %@", e];
	}
}

@end
