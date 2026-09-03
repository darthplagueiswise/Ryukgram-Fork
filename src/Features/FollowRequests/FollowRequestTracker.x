#import "../../InstagramHeaders.h"
#import "../../Utils.h"
#import "RYGFollowRequestTracker.h"
#import "../../RYGFollowBridge.h"
#import <substrate.h>
#import <objc/runtime.h>

// Capture sent/cancelled follow requests at the controller level (no network sniffing).
static void (*origFR_didPressFollowWith)(id, SEL, id);
static void (*origFR_didPressFollowControlEvent)(id, SEL);
static void (*origFR_performUnfollow)(id, SEL);

static void rygFR_didPressFollowWith(id self, SEL _cmd, id sender) {
	origFR_didPressFollowWith(self, _cmd, sender);
	RYGProbeOnce(@"followreq.capture.press", @"with:");
	[[RYGFollowRequestTracker shared] captureFollowForUser:rygFollowControllerUser(self)];
}

static void rygFR_didPressFollowControlEvent(id self, SEL _cmd) {
	origFR_didPressFollowControlEvent(self, _cmd);
	RYGProbeOnce(@"followreq.capture.press-control", @"controlEvent");
	[[RYGFollowRequestTracker shared] captureFollowForUser:rygFollowControllerUser(self)];
}

static void rygFR_performUnfollow(id self, SEL _cmd) {
	RYGProbeOnce(@"followreq.capture.unfollow", @"performUnfollow");
	[[RYGFollowRequestTracker shared] captureCancelForUser:rygFollowControllerUser(self)];
	origFR_performUnfollow(self, _cmd);
}

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
	rygFollowHook(NSSelectorFromString(@"didPressFollowButtonWith:"),
				  (IMP)rygFR_didPressFollowWith, (IMP *)&origFR_didPressFollowWith);
	rygFollowHook(NSSelectorFromString(@"didPressFollowButtonFromControlEvent"),
				  (IMP)rygFR_didPressFollowControlEvent, (IMP *)&origFR_didPressFollowControlEvent);
	rygFollowHook(NSSelectorFromString(@"performUnfollow"),
				  (IMP)rygFR_performUnfollow, (IMP *)&origFR_performUnfollow);
	sOrigByClass = [NSMutableDictionary dictionary];
	rygHookDelete(@"IGDirectInboxRender.IGDirectInboxRenderCoordinator",
				  @"_TtC19IGDirectInboxRender30IGDirectInboxRenderCoordinator");
	rygHookDelete(@"IGProfileFriendDelegate.IGProfileFriendDelegate",
				  @"_TtC23IGProfileFriendDelegate23IGProfileFriendDelegate");
	rygHookDelete(@"IGInFeedPendingFollows.IGPendingRequestInFeedUnitSectionController",
				  @"_TtC22IGInFeedPendingFollows43IGPendingRequestInFeedUnitSectionController");
}
