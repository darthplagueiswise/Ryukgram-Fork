#import "../../Utils.h"
#import "../../InstagramHeaders.h"
#import "../../RYGFollowBridge.h"
#import <substrate.h>

#define RYG_CONFIRM_FOLLOW(origCall) \
	if ([RYGUtils getBoolPref:@"follow_confirm"]) { \
		[RYGUtils showConfirmation:^{ origCall; } title:RYGLocalized(@"Confirm follow")]; \
		return; \
	} \
	origCall;

static void (*orig_didPressFollowWith)(id, SEL, id);
static void (*orig_didPressFollowControlEvent)(id, SEL);
static void (*orig_performUnfollow)(id, SEL);

static NSInteger rygFollowStatus(id ctrl) {
	IGUser *user = rygFollowControllerUser(ctrl);
	return user ? user.followStatus : -1;
}

static BOOL rygConfirmFollowTap(id ctrl, void (^proceed)(void)) {
	RYGProbeHit(@"followconfirm.press", @"followStatus=%ld", (long)rygFollowStatus(ctrl));
	if (rygFollowStatus(ctrl) != 2) return NO;
	if (![RYGUtils getBoolPref:@"follow_confirm"]) return NO;
	[RYGUtils showConfirmation:proceed title:RYGLocalized(@"Confirm follow")];
	return YES;
}

static void ryg_didPressFollowWith(id self, SEL _cmd, id sender) {
	if (rygConfirmFollowTap(self, ^{ orig_didPressFollowWith(self, _cmd, sender); })) return;
	orig_didPressFollowWith(self, _cmd, sender);
}

static void ryg_didPressFollowControlEvent(id self, SEL _cmd) {
	if (rygConfirmFollowTap(self, ^{ orig_didPressFollowControlEvent(self, _cmd); })) return;
	orig_didPressFollowControlEvent(self, _cmd);
}

// Unreached on IG 443 — IG calls this by direct Swift dispatch.
static void ryg_performUnfollow(id self, SEL _cmd) {
	RYGProbeOnce(@"followconfirm.unfollow", @"followStatus=%ld", (long)rygFollowStatus(self));
	if ([RYGUtils getBoolPref:@"unfollow_confirm"] &&
		[RYGUtils showConfirmation:^{ orig_performUnfollow(self, _cmd); }
							 title:RYGLocalized(@"Confirm unfollow")]) return;
	orig_performUnfollow(self, _cmd);
}

%hook IGDiscoverPeopleButtonGroupView

- (void)_onFollowButtonTapped:(id)arg1 {
	RYG_CONFIRM_FOLLOW(%orig);
}

- (void)_onFollowingButtonTapped:(id)arg1 {
	RYG_CONFIRM_FOLLOW(%orig);
}

%end

%hook IGHScrollAYMFCell

- (void)_didTapAYMFActionButton {
	RYG_CONFIRM_FOLLOW(%orig);
}

%end

%hook IGHScrollAYMFActionButton

- (void)_didTapTextActionButton {
	RYG_CONFIRM_FOLLOW(%orig);
}

%end

%hook IGUnifiedVideoFollowButton

- (void)_hackilyHandleOurOwnButtonTaps:(id)arg1 event:(id)arg2 {
	RYG_CONFIRM_FOLLOW(%orig);
}

%end

%hook IGProfileViewController

- (void)navigationItemsControllerDidTapHeaderFollowButton:(id)arg1 {
	RYG_CONFIRM_FOLLOW(%orig);
}

%end

%hook IGStorySectionController

- (void)followButtonTapped:(id)arg1 cell:(id)arg2 {
	RYG_CONFIRM_FOLLOW(%orig);
}

%end

static void (*orig_listSectionController)(id, SEL, id, id);

static void hooked_listSectionController(id self, SEL _cmd, id arg1, id arg2) {
	if ([RYGUtils getBoolPref:@"follow_confirm"]) {
		[RYGUtils showConfirmation:^{
			if (orig_listSectionController) {
				orig_listSectionController(self, _cmd, arg1, arg2);
			}
		} title:RYGLocalized(@"Confirm follow")];
		return;
	}

	if (orig_listSectionController) {
		orig_listSectionController(self, _cmd, arg1, arg2);
	}
}

%ctor {
	RYGProbeClass(@"followconfirm.controller", @"IGFollowController");
	rygFollowHook(NSSelectorFromString(@"didPressFollowButtonWith:"),
				  (IMP)ryg_didPressFollowWith, (IMP *)&orig_didPressFollowWith);
	rygFollowHook(NSSelectorFromString(@"didPressFollowButtonFromControlEvent"),
				  (IMP)ryg_didPressFollowControlEvent, (IMP *)&orig_didPressFollowControlEvent);
	rygFollowHook(NSSelectorFromString(@"performUnfollow"),
				  (IMP)ryg_performUnfollow, (IMP *)&orig_performUnfollow);


	Class cls = objc_getClass("IGDirectDetailMembersKit.IGDirectThreadDetailsMembersListViewController");
	if (!cls) return;

	SEL sel = @selector(listSectionController:didTapHeaderButtonWithViewModel:);
	if (![cls instancesRespondToSelector:sel]) return;

	MSHookMessageEx(cls, sel, (IMP)hooked_listSectionController, (IMP *)&orig_listSectionController);
}