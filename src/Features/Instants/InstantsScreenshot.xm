// Bypass Instants screenshot block. Gate: instants_allow_screenshot
// (requiresRestart). IG wraps content in a UITextField w/ secureTextEntry
// — iOS blacks that out in captures, so we clamp the setter to NO. Plus
// spoof isCaptured, swallow the screenshot notif, and hide the warning
// cover label.

#import <UIKit/UIKit.h>
#import "../../Utils.h"
#import "../../SCIChrome.h"

#pragma mark - Instants helpers

static NSInteger sQuickSnapVCCount = 0;

static inline BOOL sciIsQuickSnapVC(UIViewController *vc) {
	return vc && [NSStringFromClass(vc.class) rangeOfString:@"QuickSnap"].location != NSNotFound;
}

static BOOL sciContainsQuickSnapVC(UIViewController *vc) {
	if (!vc) return NO;
	if (sciIsQuickSnapVC(vc)) return YES;

	for (UIViewController *child in vc.childViewControllers) {
		if (sciContainsQuickSnapVC(child)) return YES;
	}

	return sciContainsQuickSnapVC(vc.presentedViewController);
}

static BOOL sciAnyQuickSnapVCLoaded(void) {
	for (UIScene *scene in UIApplication.sharedApplication.connectedScenes) {
		if (![scene isKindOfClass:UIWindowScene.class]) continue;

		for (UIWindow *window in ((UIWindowScene *)scene).windows) {
			if (sciContainsQuickSnapVC(window.rootViewController)) return YES;
		}
	}

	return NO;
}

static inline BOOL sciInstantsActive(void) {
	return sQuickSnapVCCount > 0;
}

static inline BOOL sciShouldDisarmSecureField(void) {
	return sciInstantsActive() || sciAnyQuickSnapVCLoaded();
}

static inline BOOL sciIsCoverString(NSString *s) {
	if (![s isKindOfClass:NSString.class] || !s.length) return NO;

	return [s containsString:@"screenshot or record"]
		|| [s containsString:@"only meant to be viewed once"]
		|| [s containsString:@"only meant to be replayed once"];
}

static UIView *sciFindCoverContainer(UIView *v) {
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

static void sciHideWarningLabel(UILabel *label) {
	label.hidden = YES;
	label.alpha = 0.0;

	UIView *cover = sciFindCoverContainer(label);
	if (cover) {
		cover.hidden = YES;
		cover.alpha = 0.0;
	}
}

#pragma mark - Instants allow screenshot

%group SCIInstantsBypass

%hook UIViewController

- (void)viewDidAppear:(BOOL)animated {
	%orig;

	if (sciIsQuickSnapVC(self)) {
		sQuickSnapVCCount++;
	}
}

- (void)viewWillDisappear:(BOOL)animated {
	%orig;

	if (sciIsQuickSnapVC(self) && sQuickSnapVCCount > 0) {
		sQuickSnapVCCount--;
	}
}

%end

%hook UITextField

- (void)setSecureTextEntry:(BOOL)secure {
	if (!secure || SCIChromeCanvasOwnsSecureField((UITextField *)self) || !sciShouldDisarmSecureField()) {
		%orig;
		return;
	}

	%orig(NO);
}

%end

%hook UIScreen

- (BOOL)isCaptured {
	return sciInstantsActive() ? NO : %orig;
}

%end

%hook NSNotificationCenter

- (void)postNotificationName:(NSNotificationName)name object:(id)obj userInfo:(NSDictionary *)info {
	if (sciInstantsActive() && [name isEqualToString:UIApplicationUserDidTakeScreenshotNotification]) return;
	%orig;
}

- (void)postNotificationName:(NSNotificationName)name object:(id)obj {
	if (sciInstantsActive() && [name isEqualToString:UIApplicationUserDidTakeScreenshotNotification]) return;
	%orig;
}

%end

%hook UILabel

- (void)setText:(NSString *)text {
	%orig;

	if (sciIsCoverString(text)) {
		sciHideWarningLabel((UILabel *)self);
	}
}

- (void)setAttributedText:(NSAttributedString *)attr {
	%orig;

	if (sciIsCoverString(attr.string)) {
		sciHideWarningLabel((UILabel *)self);
	}
}

%end

%end

%ctor {
	if ([SCIUtils getBoolPref:@"instants_allow_screenshot"]) {
		%init(SCIInstantsBypass);
	}
}
