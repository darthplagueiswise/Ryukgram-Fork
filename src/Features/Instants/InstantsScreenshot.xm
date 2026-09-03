// Bypass Instants screenshot block. Gate: instants_allow_screenshot
// (requiresRestart). IG wraps content in a UITextField w/ secureTextEntry
// — iOS blacks that out in captures, so we clamp the setter to NO. Plus
// spoof isCaptured, swallow the screenshot notif, and hide the warning
// cover label.

#import <UIKit/UIKit.h>
#import "../../Utils.h"
#import "../../RYGChrome.h"

#pragma mark - Instants helpers

static NSInteger sQuickSnapVCCount = 0;

static inline BOOL rygIsQuickSnapVC(UIViewController *vc) {
	return vc && [NSStringFromClass(vc.class) rangeOfString:@"QuickSnap"].location != NSNotFound;
}

static BOOL rygContainsQuickSnapVC(UIViewController *vc) {
	if (!vc) return NO;
	if (rygIsQuickSnapVC(vc)) return YES;

	for (UIViewController *child in vc.childViewControllers) {
		if (rygContainsQuickSnapVC(child)) return YES;
	}

	return rygContainsQuickSnapVC(vc.presentedViewController);
}

static BOOL rygAnyQuickSnapVCLoaded(void) {
	for (UIScene *scene in UIApplication.sharedApplication.connectedScenes) {
		if (![scene isKindOfClass:UIWindowScene.class]) continue;

		for (UIWindow *window in ((UIWindowScene *)scene).windows) {
			if (rygContainsQuickSnapVC(window.rootViewController)) return YES;
		}
	}

	return NO;
}

static inline BOOL rygInstantsActive(void) {
	return sQuickSnapVCCount > 0;
}

static inline BOOL rygShouldDisarmSecureField(void) {
	return rygInstantsActive() || rygAnyQuickSnapVCLoaded();
}

static inline BOOL rygIsCoverString(NSString *s) {
	if (![s isKindOfClass:NSString.class] || !s.length) return NO;

	return [s containsString:@"screenshot or record"]
		|| [s containsString:@"only meant to be viewed once"]
		|| [s containsString:@"only meant to be replayed once"];
}

static UIView *rygFindCoverContainer(UIView *v) {
	if (!v) return nil;

	UIView *p = v.superview;
	int depth = 0;

	while (p && depth < 8 && ![p isKindOfClass:UIWindow.class]) {
		NSString *cls = NSStringFromClass(p.class);

		if ([cls containsString:@"ScreenCaptureProtection"]
			|| [cls containsString:@"BlockScreenshot"]
			|| [cls containsString:@"ScreenshotBlocking"]) {
			return p;
		}

		p = p.superview;
		depth++;
	}

	return nil;
}

static void rygHideWarningLabel(UILabel *label) {
	label.hidden = YES;
	label.alpha = 0.0;

	UIView *cover = rygFindCoverContainer(label);
	if (cover) {
		cover.hidden = YES;
		cover.alpha = 0.0;
	}
}

#pragma mark - Instants allow screenshot

%group RYGInstantsBypass

%hook UIViewController

- (void)viewDidAppear:(BOOL)animated {
	%orig;

	if (rygIsQuickSnapVC(self)) {
		sQuickSnapVCCount++;
	}
}

- (void)viewWillDisappear:(BOOL)animated {
	%orig;

	if (rygIsQuickSnapVC(self) && sQuickSnapVCCount > 0) {
		sQuickSnapVCCount--;
	}
}

%end

%hook UITextField

- (void)setSecureTextEntry:(BOOL)secure {
	if (!secure || RYGChromeCanvasOwnsSecureField((UITextField *)self) || !rygShouldDisarmSecureField()) {
		%orig;
		return;
	}

	%orig(NO);
}

%end

%hook UIScreen

- (BOOL)isCaptured {
	return rygInstantsActive() ? NO : %orig;
}

%end

%hook NSNotificationCenter

- (void)postNotificationName:(NSNotificationName)name object:(id)obj userInfo:(NSDictionary *)info {
	if (rygInstantsActive() && [name isEqualToString:UIApplicationUserDidTakeScreenshotNotification]) return;
	%orig;
}

- (void)postNotificationName:(NSNotificationName)name object:(id)obj {
	if (rygInstantsActive() && [name isEqualToString:UIApplicationUserDidTakeScreenshotNotification]) return;
	%orig;
}

%end

%hook UILabel

- (void)setText:(NSString *)text {
	%orig;

	if (rygIsCoverString(text)) {
		rygHideWarningLabel((UILabel *)self);
	}
}

- (void)setAttributedText:(NSAttributedString *)attr {
	%orig;

	if (rygIsCoverString(attr.string)) {
		rygHideWarningLabel((UILabel *)self);
	}
}

%end

%end

%ctor {
	if ([RYGUtils getBoolPref:@"instants_allow_screenshot"]) {
		%init(RYGInstantsBypass);
	}
}
