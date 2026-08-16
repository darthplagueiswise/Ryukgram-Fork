#import "../../Utils.h"
#import "../../InstagramHeaders.h"

static void rygConfirmFollow(dispatch_block_t originalAction) {
	if (!originalAction) return;
	if ([RYGUtils getBoolPref:@"follow_confirm"]) {
		[RYGUtils showConfirmation:originalAction title:RYGLocalized(@"Confirm follow")];
		return;
	}
	originalAction();
}

%hook IGFollowController

- (void)_didPressFollowButton {
	if (self.user.followStatus == 2) {
		rygConfirmFollow(^{ %orig; });
		return;
	}
	%orig;
}

- (void)_performUnfollow {
	if ([RYGUtils getBoolPref:@"unfollow_confirm"]) {
		[RYGUtils showConfirmation:^{ %orig; } title:RYGLocalized(@"Confirm unfollow")];
		return;
	}
	%orig;
}

%end

%hook IGDiscoverPeopleButtonGroupView

- (void)_onFollowButtonTapped:(id)arg1 {
	rygConfirmFollow(^{ %orig; });
}

- (void)_onFollowingButtonTapped:(id)arg1 {
	rygConfirmFollow(^{ %orig; });
}

%end

%hook IGHScrollAYMFCell

- (void)_didTapAYMFActionButton {
	rygConfirmFollow(^{ %orig; });
}

%end

%hook IGHScrollAYMFActionButton

- (void)_didTapTextActionButton {
	rygConfirmFollow(^{ %orig; });
}

%end

%hook IGUnifiedVideoFollowButton

- (void)_hackilyHandleOurOwnButtonTaps:(id)arg1 event:(id)arg2 {
	rygConfirmFollow(^{ %orig; });
}

%end

%hook IGProfileViewController

- (void)navigationItemsControllerDidTapHeaderFollowButton:(id)arg1 {
	rygConfirmFollow(^{ %orig; });
}

%end

%hook IGStorySectionController

- (void)followButtonTapped:(id)arg1 cell:(id)arg2 {
	rygConfirmFollow(^{ %orig; });
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
	Class cls = objc_getClass("IGDirectDetailMembersKit.IGDirectThreadDetailsMembersListViewController");
	if (!cls) return;

	SEL sel = @selector(listSectionController:didTapHeaderButtonWithViewModel:);
	if (![cls instancesRespondToSelector:sel]) return;

	MSHookMessageEx(cls, sel, (IMP)hooked_listSectionController, (IMP *)&orig_listSectionController);
}
