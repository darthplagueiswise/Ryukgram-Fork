#import "SCIInternalMenusLauncher.h"
#import "SCIDogfoodObjectRuntime.h"
#import <UIKit/UIKit.h>
#import <objc/message.h>
#import <objc/runtime.h>
#import <os/log.h>
#import <string.h>

#define MLOG(fmt,...) os_log(OS_LOG_DEFAULT,"[SCIGate] Menus " fmt,##__VA_ARGS__)

static BOOL sDebugMenuRequestInFlight = NO;

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

+ (UIViewController *)deepestVisibleControllerFrom:(UIViewController *)controller {
	UIViewController *top = controller;
	while (top.presentedViewController) top = top.presentedViewController;

	BOOL advanced = YES;
	while (advanced && top) {
		advanced = NO;
		if ([top isKindOfClass:UINavigationController.class]) {
			UIViewController *visible = ((UINavigationController *)top).visibleViewController;
			if (visible && visible != top) { top = visible; advanced = YES; continue; }
		}
		if ([top isKindOfClass:UITabBarController.class]) {
			UIViewController *selected = ((UITabBarController *)top).selectedViewController;
			if (selected && selected != top) { top = selected; advanced = YES; continue; }
		}
	}
	return top;
}

+ (BOOL)isNativeDebugController:(UIViewController *)controller {
	if (!controller) return NO;
	NSString *name = NSStringFromClass([controller class]) ?: @"";
	NSArray<NSString *> *needles = @[
		@"BugReport", @"RageShake", @"InternalSettings", @"Dogfooding", @"DebugMenu"
	];
	for (NSString *needle in needles) {
		if ([name rangeOfString:needle options:NSCaseInsensitiveSearch].location != NSNotFound)
			return YES;
	}
	return NO;
}

+ (void)pollDebugMenuOnWindow:(UIWindow *)window
	baseline:(UIViewController *)baseline
	remaining:(NSUInteger)remaining
	completion:(void (^)(BOOL presented, UIViewController *controller))completion {
	dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.25 * NSEC_PER_SEC)),
		dispatch_get_main_queue(), ^{
			UIViewController *after = [self deepestVisibleControllerFrom:window.rootViewController];
			BOOL native = [self isNativeDebugController:after];
			BOOL changed = after && baseline && after != baseline;
			if (native || changed) {
				if (completion) completion(YES, after);
				return;
			}
			if (remaining > 1) {
				[self pollDebugMenuOnWindow:window baseline:baseline
					remaining:remaining - 1 completion:completion];
				return;
			}
			if (completion) completion(NO, after);
		});
}

// Revalidated in Instagram(4), SHA-256
// a562b3626c663eec47b41ed1bca7a7af6aa00cc30bada3293046f7cce1a555aa:
//   -showDebugMenu                  v16@0:8
//   -showDebugMenuWithEntryPoint:   v24@0:8q16
//
// -showDebugMenu is the native entryPoint=0 thunk. The opener must run only
// after RyukGram's presented hierarchy is fully dismissed. The native method
// continues through asynchronous build/account callbacks, so the temporary
// rageshake opt-in remains active until presentation succeeds or the bounded
// post-tap verification expires. This is UI sequencing, never launch-time work.
+ (void)openInstagramDebugMenuWithCompletion:(void (^)(NSString *result))completion {
	dispatch_async(dispatch_get_main_queue(), ^{
		if (sDebugMenuRequestInFlight) {
			if (completion) completion(@"error: a native debug-menu request is already running");
			return;
		}

		UIWindow *target = [self activeIGWindow];
		if (!target) {
			if (completion) completion(@"error: no active IGWindow");
			return;
		}

		SEL showSelector = NSSelectorFromString(@"showDebugMenu");
		Method showMethod = class_getInstanceMethod([target class], showSelector);
		const char *showEncoding = showMethod ? method_getTypeEncoding(showMethod) : NULL;
		BOOL canShow = showMethod && showEncoding && strcmp(showEncoding, "v16@0:8") == 0;

		SEL entrySelector = NSSelectorFromString(@"showDebugMenuWithEntryPoint:");
		Method entryMethod = class_getInstanceMethod([target class], entrySelector);
		const char *entryEncoding = entryMethod ? method_getTypeEncoding(entryMethod) : NULL;
		BOOL canEntryZero = entryMethod && entryEncoding && strcmp(entryEncoding, "v24@0:8q16") == 0;

		if (!canShow && !canEntryZero) {
			if (completion) {
				completion([NSString stringWithFormat:
					@"error: IGWindow debug-menu ABI unavailable (show=%s entry=%s)",
					showEncoding ?: "missing", entryEncoding ?: "missing"]);
			}
			return;
		}

		sDebugMenuRequestInFlight = YES;
		NSUserDefaults *defaults = NSUserDefaults.standardUserDefaults;
		NSString *optInKey = @"user-opted-in-for-rageshake";
		id previousOptIn = [defaults objectForKey:optInKey];
		BOOL hadPreviousOptIn = previousOptIn != nil;
		[defaults setObject:@YES forKey:optInKey];

		__block BOOL finished = NO;
		void (^finishOnce)(NSString *) = ^(NSString *result) {
			if (finished) return;
			finished = YES;
			sDebugMenuRequestInFlight = NO;
			if (hadPreviousOptIn) [defaults setObject:previousOptIn forKey:optInKey];
			else [defaults removeObjectForKey:optInKey];
			if (completion) completion(result ?: @"unknown result");
		};

		void (^invokeNative)(void) = ^{
			[target makeKeyAndVisible];
			UIViewController *baseline =
				[self deepestVisibleControllerFrom:target.rootViewController];
			@try {
				if (canShow) {
					((void (*)(id, SEL))objc_msgSend)(target, showSelector);
					MLOG("Instagram debug menu invoked through -showDebugMenu");
				} else {
					((void (*)(id, SEL, NSInteger))objc_msgSend)(target, entrySelector, 0);
					MLOG("Instagram debug menu invoked through entryPoint=0 fallback");
				}
			} @catch (id exception) {
				finishOnce([NSString stringWithFormat:@"error: native debug-menu opener threw: %@", exception]);
				return;
			}

			[self pollDebugMenuOnWindow:target baseline:baseline remaining:24
				completion:^(BOOL presented, UIViewController *controller) {
					if (presented) {
						finishOnce([NSString stringWithFormat:@"presented %@",
							NSStringFromClass([controller class]) ?: @"native debug controller"]);
					} else {
						finishOnce(@"error: native opener completed without presenting UI. The local call and ABI succeeded, but the asynchronous account/build gate returned without a controller. Open GraphQL dogfood snapshot to inspect eligibility and repeated build checks.");
					}
				}];
		};

		UIViewController *root = target.rootViewController;
		if (root.presentedViewController) {
			[root dismissViewControllerAnimated:YES completion:^{
				dispatch_async(dispatch_get_main_queue(), invokeNative);
			}];
		} else {
			dispatch_async(dispatch_get_main_queue(), invokeNative);
		}
	});
}

+ (NSString *)openInstagramDebugMenu {
	[self openInstagramDebugMenuWithCompletion:nil];
	return @"requested native Instagram Debug Menu";
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
