#import "SCIInternalMenusLauncher.h"
#import "SCIDogfoodObjectRuntime.h"
#import <UIKit/UIKit.h>
#import <objc/message.h>
#import <objc/runtime.h>
#import <os/log.h>
#import <string.h>

#define MLOG(fmt,...) os_log(OS_LOG_DEFAULT,"[SCIGate] Menus " fmt,##__VA_ARGS__)

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

// Revalidated in Instagram(3):
//   -showDebugMenu                  v16@0:8
//   -showDebugMenuWithEntryPoint:   v24@0:8q16
//
// -showDebugMenu is the entryPoint=0 thunk. The failure in the previous button
// was presentation collision: RyukGram's sheet was still covering IGWindow.
// Dismiss the sheet, restore IGWindow as key, and invoke entryPoint 0 on the
// next main-loop turn. No synthetic controller, rageshake-default mutation or
// timer-based retry.
+ (void)openInstagramDebugMenuWithCompletion:(void (^)(NSString *result))completion {
	void (^finish)(NSString *) = ^(NSString *result) {
		if (!completion) return;
		dispatch_async(dispatch_get_main_queue(), ^{
			completion(result ?: @"unknown result");
		});
	};

	dispatch_async(dispatch_get_main_queue(), ^{
		UIWindow *target = [self activeIGWindow];
		if (!target) {
			finish(@"error: no active IGWindow");
			return;
		}

		SEL selector = NSSelectorFromString(@"showDebugMenuWithEntryPoint:");
		Method method = class_getInstanceMethod([target class], selector);
		const char *encoding = method ? method_getTypeEncoding(method) : NULL;
		if (!method || !encoding || strcmp(encoding, "v24@0:8q16") != 0) {
			finish([NSString stringWithFormat:
				@"error: IGWindow debug-menu ABI unavailable or changed: %s",
				encoding ?: "missing"]);
			return;
		}

		void (^invokeNative)(void) = ^{
			[target makeKeyAndVisible];
			dispatch_async(dispatch_get_main_queue(), ^{
				@try {
					((void (*)(id, SEL, NSInteger))objc_msgSend)(
						target, selector, 0
					);
					MLOG("Instagram debug menu requested with entryPoint=0");
					finish(@"requested native Instagram Debug Menu");
				} @catch (id exception) {
					finish([NSString stringWithFormat:
						@"error: showDebugMenuWithEntryPoint: threw: %@",
						exception]);
				}
			});
		};

		UIViewController *presented =
			target.rootViewController.presentedViewController;
		if (presented) {
			[presented dismissViewControllerAnimated:YES
				completion:invokeNative];
		} else {
			invokeNative();
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
