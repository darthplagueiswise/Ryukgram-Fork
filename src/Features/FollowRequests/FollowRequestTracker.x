#import "../../InstagramHeaders.h"
#import "../../Utils.h"
#import "RYGFollowRequestTracker.h"
#import <substrate.h>
#import <objc/runtime.h>

// Grouped so Logos doesn't auto-init it — hooks install only when the feature is on.
%group RYGFollowCaptureGroup

// Capture sent/cancelled follow requests at the controller level (no network sniffing).
%hook IGFollowController

- (void)_didPressFollowButton {
	%orig;
	[[RYGFollowRequestTracker shared] captureFollowForUser:self.user];
}

- (void)_performUnfollow {
	[[RYGFollowRequestTracker shared] captureCancelForUser:self.user];
	%orig;
}

%end

%end

// Deleting an incoming request calls -didDeleteFollowRequestFromUserPk: on whichever
// surface handled it (inbox / profile / in-feed), so hook all three — the poller then
// marks the request Ignored rather than Withdrawn. Per-class original kept by name.
static NSMutableDictionary<NSString *, NSValue *> *sOrigByClass;

static void hooked_didDeleteFR(id self, SEL _cmd, id pkArg) {
	NSString *pk = [pkArg isKindOfClass:NSString.class] ? pkArg
		: ([pkArg respondsToSelector:@selector(stringValue)] ? [pkArg stringValue] : nil);
	if (pk.length) [[RYGFollowRequestTracker shared] captureIgnoreIncomingPK:pk];

	void (*orig)(id, SEL, id) = NULL;
	for (Class c = object_getClass(self); c && !orig; c = class_getSuperclass(c))
		orig = (void (*)(id, SEL, id))[sOrigByClass[NSStringFromClass(c)] pointerValue];
	if (orig) orig(self, _cmd, pkArg);
}

static void rygHookDelete(NSString *swiftName, NSString *mangled) {
	Class c = NSClassFromString(swiftName) ?: NSClassFromString(mangled);
	if (!c) return;
	IMP orig = NULL;
	MSHookMessageEx(c, @selector(didDeleteFollowRequestFromUserPk:), (IMP)hooked_didDeleteFR, &orig);
	if (orig) sOrigByClass[NSStringFromClass(c)] = [NSValue valueWithPointer:(void *)orig];
}

%ctor {
	if (![RYGUtils getBoolPref:@"follow_requests_enabled"]) return;
	%init(RYGFollowCaptureGroup);
	sOrigByClass = [NSMutableDictionary dictionary];
	rygHookDelete(@"IGDirectInboxRender.IGDirectInboxRenderCoordinator",
				  @"_TtC19IGDirectInboxRender30IGDirectInboxRenderCoordinator");
	rygHookDelete(@"IGProfileFriendDelegate.IGProfileFriendDelegate",
				  @"_TtC23IGProfileFriendDelegate23IGProfileFriendDelegate");
	rygHookDelete(@"IGInFeedPendingFollows.IGPendingRequestInFeedUnitSectionController",
				  @"_TtC22IGInFeedPendingFollows43IGPendingRequestInFeedUnitSectionController");
}
