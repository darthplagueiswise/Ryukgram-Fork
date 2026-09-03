#import "RYGStoryInteractionPipeline.h"
#import "StoryHelpers.h"
#import "../../Utils.h"
#import <objc/message.h>
#import <mach/mach_time.h>

extern __weak UIViewController *rygActiveStoryVC;
extern BOOL rygAdvanceBypassActive;

#pragma mark - Policy table

typedef struct {
	NSString *confirmPref;
	NSString *confirmTitle;
	NSString *seenPref;
	NSString *advancePref;
	NSTimeInterval advanceDelay;
} RYGStoryPolicy;

static RYGStoryPolicy rygPolicyForType(RYGStoryInteraction type) {
	switch (type) {
		case RYGStoryInteractionLike:
			return (RYGStoryPolicy){
				@"story_like_confirm",
				RYGLocalized(@"Confirm story like"),
				@"seen_on_story_like",
				@"advance_on_story_like",
				0.3
			};

		case RYGStoryInteractionEmojiReaction:
			return (RYGStoryPolicy){
				@"emoji_reaction_confirm",
				RYGLocalized(@"Confirm story emoji reaction"),
				@"seen_on_story_reply",
				@"advance_on_story_reply",
				0.4
			};

		case RYGStoryInteractionTextReply:
			return (RYGStoryPolicy){
				nil,
				nil,
				@"seen_on_story_reply",
				@"advance_on_story_reply",
				0.4
			};
	}

	return (RYGStoryPolicy){ nil, nil, nil, nil, 0.3 };
}

#pragma mark - Helpers

static id rygSafeCall0(id target, SEL sel) {
	if (!target || !sel || ![target respondsToSelector:sel]) return nil;

	@try {
		return ((id (*)(id, SEL))objc_msgSend)(target, sel);
	} @catch (__unused id e) {
		return nil;
	}
}

static id rygCurrentStorySectionController(UIViewController *vc) {
	return rygSafeCall0(vc, @selector(currentlyDisplayedSectionController));
}

#pragma mark - Side effects

static UIView *rygFindOverlay(UIViewController *vc) {
	if (!vc) return nil;

	Class cls = NSClassFromString(@"IGStoryFullscreenOverlayView");
	if (!cls) return nil;

	NSMutableArray *stack = [NSMutableArray arrayWithObject:vc.view];

	while (stack.count) {
		UIView *v = stack.lastObject;
		[stack removeLastObject];

		if ([v isKindOfClass:cls]) return v;

		for (UIView *s in v.subviews) {
			[stack addObject:s];
		}
	}

	return nil;
}

static void rygMarkSeen(NSString *prefKey) {
	if (!prefKey || ![RYGUtils getBoolPref:prefKey]) return;

	UIView *overlay = rygFindOverlay(rygActiveStoryVC);
	if (!overlay) return;

	SEL sel = NSSelectorFromString(@"rygStoryMarkSeenTapped:");

	if ([overlay respondsToSelector:sel]) {
		((void (*)(id, SEL, id))objc_msgSend)(overlay, sel, nil);
	}
}

static uint64_t rygLastAdvanceTime = 0;

static void rygAdvance(NSString *prefKey, NSTimeInterval delay) {
	if (!prefKey || ![RYGUtils getBoolPref:prefKey]) return;

	UIViewController *vc = rygActiveStoryVC;
	if (!vc) return;

	id ctrl = rygCurrentStorySectionController(vc);
	if (!ctrl) return;

	uint64_t now = clock_gettime_nsec_np(CLOCK_MONOTONIC_RAW);
	if (now - rygLastAdvanceTime < 500000000ULL) return;

	rygLastAdvanceTime = now;

	dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(delay * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
		rygAdvanceBypassActive = YES;

		SEL advSel = NSSelectorFromString(@"advanceToNextItemWithNavigationAction:");
		if ([ctrl respondsToSelector:advSel]) {
			((void (*)(id, SEL, NSInteger))objc_msgSend)(ctrl, advSel, 1);
		}

		dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.2 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
			id c2 = vc ? rygCurrentStorySectionController(vc) : nil;

			if (c2) {
				SEL resumeSel = NSSelectorFromString(@"tryResumePlaybackWithReason:");

				if ([c2 respondsToSelector:resumeSel]) {
					((void (*)(id, SEL, NSInteger))objc_msgSend)(c2, resumeSel, 0);
				}
			}

			rygAdvanceBypassActive = NO;
		});
	});
}

static void rygFireSideEffects(RYGStoryPolicy policy) {
	rygMarkSeen(policy.seenPref);
	rygAdvance(policy.advancePref, policy.advanceDelay);
}

#pragma mark - Pipeline

void rygStoryInteraction(RYGStoryInteraction type,
						 void (^action)(void),
						 void (^_Nullable uiRevert)(void),
						 void (^_Nullable uiReapply)(void)) {
	RYGStoryPolicy policy = rygPolicyForType(type);

	if (policy.confirmPref && [RYGUtils getBoolPref:policy.confirmPref]) {
		if (uiRevert) uiRevert();

		[RYGUtils showConfirmation:^{
			if (uiReapply) uiReapply();
			if (action) action();

			rygFireSideEffects(policy);
		} title:policy.confirmTitle];

		return;
	}

	if (action) action();

	rygFireSideEffects(policy);
}

void rygStoryInteractionSideEffects(RYGStoryInteraction type) {
	rygFireSideEffects(rygPolicyForType(type));
}