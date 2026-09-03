#import "RYGNotificationMirror.h"
#import "RYGNotificationActions.h"
#import "../../Utils.h"
#import <UIKit/UIKit.h>
#import <UserNotifications/UserNotifications.h>
#import <objc/runtime.h>
#import <substrate.h>

static NSString *const kPrefMirrorEnabled     = @"notif_mirror_enabled";
static NSString *const kPrefMirrorWhileOpen   = @"notif_mirror_while_open";
static NSString *const kPrefMirrorClearOnOpen = @"notif_mirror_clear_on_open";
static NSString *const kPerActionMirrorPrefix = @"notif_mirror_";
static NSString *const kIdentifierPrefix      = @"ryg_mirror_";
static NSString *const kUserInfoKey           = @"ryg_mirror";

static const NSTimeInterval kRepeatThrottle = 2.0;

// ───── Tap actions ─────
// Keyed by notification identifier; in-memory, so a tap after IG was killed
// just opens the app.
static NSMutableDictionary<NSString *, void (^)(void)> *rygTapMap(void) {
	static NSMutableDictionary *map;
	static dispatch_once_t once;
	dispatch_once(&once, ^{ map = [NSMutableDictionary new]; });
	return map;
}

// Foregrounding via a notification tap delivers the response while the app is
// still inactive — presenting then races IG's UI restore, so defer to active.
static void rygRunWhenActive(void (^block)(void)) {
	dispatch_async(dispatch_get_main_queue(), ^{
		if (UIApplication.sharedApplication.applicationState == UIApplicationStateActive) {
			block();
			return;
		}
		__block id token = [NSNotificationCenter.defaultCenter addObserverForName:UIApplicationDidBecomeActiveNotification
		                                                                   object:nil
		                                                                    queue:NSOperationQueue.mainQueue
		                                                               usingBlock:^(__unused NSNotification *note) {
			[NSNotificationCenter.defaultCenter removeObserver:token];
			dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.35 * NSEC_PER_SEC)), dispatch_get_main_queue(), block);
		}];
	});
}

// ───── Tap guard ─────
// IG's delegate must never parse our foreign userInfo — swallow the response,
// run our stored tap action (if any) once the app is active.
static void (*orig_didReceiveResponse)(id, SEL, UNUserNotificationCenter *, UNNotificationResponse *, void (^)(void));
static void ryg_didReceiveResponse(id self, SEL _cmd, UNUserNotificationCenter *center, UNNotificationResponse *response, void (^completion)(void)) {
	if ([response.notification.request.content.userInfo[kUserInfoKey] boolValue]) {
		NSString *identifier = response.notification.request.identifier;
		void (^tap)(void) = nil;

		NSMutableDictionary *map = rygTapMap();
		@synchronized (map) {
			tap = map[identifier];
			if (tap) [map removeObjectForKey:identifier];
		}

		if (tap && [response.actionIdentifier isEqualToString:UNNotificationDefaultActionIdentifier])
			rygRunWhenActive(tap);

		if (completion) completion();
		return;
	}
	orig_didReceiveResponse(self, _cmd, center, response, completion);
}

// IG hides foreign notifications in the foreground; force ours to a banner.
// IG's own keep the delegate's (or, when we added the method, the OS) default.
static void (*orig_willPresent)(id, SEL, UNUserNotificationCenter *, UNNotification *, void (^)(UNNotificationPresentationOptions));
static void ryg_willPresent(id self, SEL _cmd, UNUserNotificationCenter *center, UNNotification *notification, void (^completion)(UNNotificationPresentationOptions)) {
	if ([notification.request.content.userInfo[kUserInfoKey] boolValue]) {
		if (completion) completion(UNNotificationPresentationOptionBanner | UNNotificationPresentationOptionList);
		return;
	}
	if (orig_willPresent) { orig_willPresent(self, _cmd, center, notification, completion); return; }
	if (completion) completion(UNNotificationPresentationOptionNone);
}
// Hooks at most one delegate class — the orig IMP is a single slot and a
// second hook would corrupt the first class's original.
static void rygInstallTapGuardIfNeeded(void) {
	id<UNUserNotificationCenterDelegate> delegate = UNUserNotificationCenter.currentNotificationCenter.delegate;
	if (!delegate) return;

	static BOOL installed = NO;
	@synchronized (RYGNotificationMirror.class) {
		if (installed) return;

		Class cls = object_getClass(delegate);
		SEL sel = @selector(userNotificationCenter:didReceiveNotificationResponse:withCompletionHandler:);
		if (![cls instancesRespondToSelector:sel]) return;

		MSHookMessageEx(cls, sel, (IMP)ryg_didReceiveResponse, (IMP *)&orig_didReceiveResponse);

		SEL wp = @selector(userNotificationCenter:willPresentNotification:withCompletionHandler:);
		if ([cls instancesRespondToSelector:wp])
			MSHookMessageEx(cls, wp, (IMP)ryg_willPresent, (IMP *)&orig_willPresent);
		else
			class_addMethod(cls, wp, (IMP)ryg_willPresent, "v@:@@@?");

		installed = YES;
	}
}

@implementation RYGNotificationMirror

+ (void)load {
	[NSNotificationCenter.defaultCenter addObserverForName:UIApplicationDidBecomeActiveNotification
	                                                object:nil
	                                                 queue:NSOperationQueue.mainQueue
	                                            usingBlock:^(__unused NSNotification *note) {
		[self rygClearDeliveredMirrors];
	}];
}

+ (BOOL)appIsBackgrounded {
	return UIApplication.sharedApplication.applicationState == UIApplicationStateBackground;
}

+ (BOOL)mirrorsWhileForeground {
	return [RYGUtils getBoolPref:kPrefMirrorEnabled] && [RYGUtils getBoolPref:kPrefMirrorWhileOpen];
}

+ (BOOL)shouldMirrorAction:(NSString *)actionID {
	if (![RYGUtils getBoolPref:kPrefMirrorEnabled]) return NO;

	NSString *key = [kPerActionMirrorPrefix stringByAppendingString:actionID ?: @""];
	return ![[RYGUtils getStringPref:key] isEqualToString:@"off"];
}

+ (void)mirrorActionID:(NSString *)actionID title:(NSString *)title subtitle:(NSString *)subtitle onTap:(void (^)(void))onTap {
	if (!title.length) return;

	// Deterministic identifier — an identical repeat replaces its NC entry
	// instead of stacking.
	NSString *action = actionID.length ? actionID : @"generic";
	NSString *identifier = [NSString stringWithFormat:@"%@%@_%lx", kIdentifierPrefix, action,
	                        (unsigned long)(title.hash ^ (subtitle.hash * 31))];

	if ([self rygIsThrottled:identifier]) return;

	NSMutableDictionary *map = rygTapMap();
	@synchronized (map) {
		if (map.count > 64) [map removeAllObjects];
		if (onTap) map[identifier] = [onTap copy];
		else [map removeObjectForKey:identifier];
	}

	rygInstallTapGuardIfNeeded();

	UNUserNotificationCenter *center = UNUserNotificationCenter.currentNotificationCenter;
	[center getNotificationSettingsWithCompletionHandler:^(UNNotificationSettings *settings) {
		BOOL allowed = settings.authorizationStatus == UNAuthorizationStatusAuthorized
		            || settings.authorizationStatus == UNAuthorizationStatusProvisional;
		if (!allowed) return;

		UNMutableNotificationContent *content = [UNMutableNotificationContent new];
		content.title = title;
		if (subtitle.length) content.body = subtitle;
		content.threadIdentifier = [kIdentifierPrefix stringByAppendingString:action];
		content.userInfo = @{ kUserInfoKey: @1 };

		UNNotificationRequest *request = [UNNotificationRequest requestWithIdentifier:identifier content:content trigger:nil];
		[center addNotificationRequest:request withCompletionHandler:nil];
	}];
}

+ (BOOL)rygIsThrottled:(NSString *)identifier {
	static NSMutableDictionary<NSString *, NSNumber *> *recent;
	static dispatch_once_t once;
	dispatch_once(&once, ^{ recent = [NSMutableDictionary new]; });

	CFAbsoluteTime now = CFAbsoluteTimeGetCurrent();

	@synchronized (recent) {
		NSNumber *last = recent[identifier];
		if (last && now - last.doubleValue < kRepeatThrottle) return YES;

		if (recent.count > 128) {
			for (NSString *key in recent.allKeys)
				if (now - recent[key].doubleValue >= kRepeatThrottle) [recent removeObjectForKey:key];
		}

		recent[identifier] = @(now);
	}

	return NO;
}

+ (void)rygClearDeliveredMirrors {
	if (![RYGUtils getBoolPref:kPrefMirrorClearOnOpen]) return;

	UNUserNotificationCenter *center = UNUserNotificationCenter.currentNotificationCenter;
	[center getDeliveredNotificationsWithCompletionHandler:^(NSArray<UNNotification *> *delivered) {
		NSMutableArray<NSString *> *ids = [NSMutableArray new];

		for (UNNotification *notif in delivered)
			if ([notif.request.identifier hasPrefix:kIdentifierPrefix]) [ids addObject:notif.request.identifier];

		if (!ids.count) return;
		[center removeDeliveredNotificationsWithIdentifiers:ids];

		NSMutableDictionary *map = rygTapMap();
		@synchronized (map) {
			[map removeObjectsForKeys:ids];
		}
	}];
}

+ (NSDictionary<NSString *, NSString *> *)defaultPerActionPrefs {
	NSMutableDictionary *m = [NSMutableDictionary new];

	for (RYGNotificationActionInfo *info in RYGNotificationActionsAll()) {
		if (!info.identifier.length) continue;
		BOOL offByDefault = (info.caps & RYGNotificationActionCapsMirrorOffByDefault) != 0;
		m[[kPerActionMirrorPrefix stringByAppendingString:info.identifier]] = offByDefault ? @"off" : @"on";
	}

	return m.copy;
}

@end
