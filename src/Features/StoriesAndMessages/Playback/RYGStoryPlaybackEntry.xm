// Long-press entry points for the story Playback menu, plus its shared story-menu row.

#import "RYGStoryPlayback.h"
#import "../StoryMenuItems.h"
#import "../../../Utils.h"
#import "../../../InstagramHeaders.h"
#import <objc/runtime.h>
#import <objc/message.h>

extern "C" id rygStoryMediaController(void) {
	UIViewController *vc = rygActiveStoryViewerVC;
	SEL sel = @selector(currentlyDisplayedSectionController);
	if (![vc respondsToSelector:sel]) return nil;
	@try { return ((id (*)(id, SEL))objc_msgSend)(vc, sel); }
	@catch (__unused id e) { return nil; }
}

static void rygCollectStoryVideoViews(UIView *root, Class cls, NSMutableArray *out) {
	if (!root) return;
	for (UIView *sub in root.subviews) {
		if ([sub isKindOfClass:cls]) [out addObject:sub];
		else rygCollectStoryVideoViews(sub, cls, out);
	}
}

extern "C" id rygStoryVideoView(void) {
	Class cls = NSClassFromString(@"IGStoryVideoView");
	if (!cls) return nil;

	id mediaView = nil;
	id sc = rygStoryMediaController();
	if ([sc respondsToSelector:@selector(mediaView)]) {
		@try { mediaView = ((id (*)(id, SEL))objc_msgSend)(sc, @selector(mediaView)); }
		@catch (__unused id e) {}
	}
	if ([mediaView isKindOfClass:cls]) return mediaView;

	NSMutableArray *found = [NSMutableArray array];
	if ([mediaView isKindOfClass:[UIView class]]) rygCollectStoryVideoViews(mediaView, cls, found);
	if (found.count == 0) rygCollectStoryVideoViews(rygActiveStoryViewerVC.view, cls, found);

	for (UIView *v in found) {
		if (!v.window) continue;
		if ([v respondsToSelector:@selector(isPlaying)]
			&& ((BOOL (*)(id, SEL))objc_msgSend)(v, @selector(isPlaying))) return v;
	}
	for (UIView *v in found) {
		if (!v.window) continue;
		CGRect inWindow = [v convertRect:v.bounds toView:v.window];
		if (CGRectIntersectsRect(inWindow, v.window.bounds)) return v;
	}
	return nil;
}

extern "C" void rygInstallStoryPlaybackLongPress(UIView *view) {
	if (![RYGPlaybackMenu anyModuleEnabledForSurface:RYGPlaybackSurfaceStories]) return;
	[RYGPlaybackMenu installLongPressOnView:view surface:RYGPlaybackSurfaceStories];
}

#pragma mark - More button

static NSString *const kRYGStoryReshareID = @"story-footer-view-reshare-button";
static NSString *const kRYGStoryLikeID = @"story-footer-like-button";

static BOOL rygStringHasAny(NSString *haystack, NSArray<NSString *> *needles) {
	if (!haystack.length) return NO;
	NSString *lower = haystack.lowercaseString;
	for (NSString *needle in needles)
		if ([lower containsString:needle]) return YES;
	return NO;
}

static BOOL rygControlActionLooksLikeMore(UIControl *control) {
	for (id target in control.allTargets) {
		for (NSString *action in [control actionsForTarget:target forControlEvent:0]) {
			if (rygStringHasAny(action, @[@"moreoption", @"morebutton", @"kebab", @"overflow"]))
				return YES;
		}
	}
	return NO;
}

// IG's footer ⋯ has no ObjC class of its own and varies by account, so match on what it exposes.
static NSString *rygStoryMoreButtonReason(UIView *view) {
	if (![view isKindOfClass:[UIControl class]]) return nil;
	if (rygStringHasAny(NSStringFromClass([view class]), @[@"moreoptions", @"morebutton", @"kebab"]))
		return @"class";
	if (rygStringHasAny(view.accessibilityIdentifier,
						@[@"more-button", @"more_button", @"more-options", @"more_options"]))
		return @"identifier";
	if (rygControlActionLooksLikeMore((UIControl *)view)) return @"action";
	return nil;
}

static void rygScanStoryControls(UIView *root, NSInteger depth, NSMutableArray<UIControl *> *controls) {
	if (!root || depth > 14) return;
	for (UIView *sub in root.subviews) {
		if ([sub isKindOfClass:[UIControl class]]) [controls addObject:(UIControl *)sub];
		rygScanStoryControls(sub, depth + 1, controls);
	}
}

// Send and like carry stable ids, so the unlabelled control beside them is the overflow.
static UIView *rygStoryFooterOverflow(NSArray<UIControl *> *controls) {
	UIView *footer = nil;
	for (UIControl *c in controls) {
		NSString *identifier = c.accessibilityIdentifier;
		if ([identifier isEqualToString:kRYGStoryReshareID] || [identifier isEqualToString:kRYGStoryLikeID]) {
			footer = c.superview;
			break;
		}
	}
	if (!footer) return nil;
	for (UIView *sibling in footer.subviews) {
		if (![sibling isKindOfClass:[UIControl class]]) continue;
		if (sibling.accessibilityIdentifier.length) continue;
		return sibling;
	}
	return nil;
}

static void rygInstallStoryFooterLongPress(void) {
	if (![RYGPlaybackMenu anyModuleEnabledForSurface:RYGPlaybackSurfaceStories]) return;
	UIViewController *vc = rygActiveStoryViewerVC;
	if (!vc.viewLoaded) return;

	NSMutableArray<UIControl *> *controls = [NSMutableArray array];
	rygScanStoryControls(vc.view, 0, controls);

	BOOL matched = NO;
	for (UIControl *c in controls) {
		NSString *reason = rygStoryMoreButtonReason(c);
		if (!reason) continue;
		matched = YES;
		rygInstallStoryPlaybackLongPress(c);
		RYGProbeOnce(@"story.playback.more-button", @"via=%@ class=%@", reason, NSStringFromClass([c class]));
	}

	UIView *overflow = rygStoryFooterOverflow(controls);
	if (overflow) {
		matched = YES;
		rygInstallStoryPlaybackLongPress(overflow);
	}

	if (!matched) RYGProbeOnce(@"story.playback.more-button-missing", @"controls=%lu",
							   (unsigned long)controls.count);
}

extern "C" RYGStoryMenuEntry *rygStoryPlaybackMenuEntry(void) {
	if (!rygActiveStoryViewerVC) return nil;
	if (![RYGPlaybackMenu anyModuleEnabledForSurface:RYGPlaybackSurfaceStories]) return nil;
	// The old IGDSMenu tears its window down after the handler runs, so wait and use the story window.
	return [RYGStoryMenuEntry entryWithTitle:RYGLocalized(@"Playback") symbol:@"play.circle" handler:^{
		dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.35 * NSEC_PER_SEC)),
			dispatch_get_main_queue(), ^{
			[RYGPlaybackMenu presentForSurface:RYGPlaybackSurfaceStories
										anchor:rygActiveStoryViewerVC.viewIfLoaded];
		});
	}];
}

%hook IGStoryFullscreenHeaderView

- (void)layoutSubviews {
	%orig;
	if (![RYGPlaybackMenu anyModuleEnabledForSurface:RYGPlaybackSurfaceStories]) return;

	id header = self;
	UIView *more = nil;
	@try { more = [header valueForKey:@"moreOptionsButton"]; } @catch (__unused id e) {}
	rygInstallStoryPlaybackLongPress(more);

	Ivar iv = class_getInstanceVariable([header class], "_mimicryHamburgerButton");
	UIView *hamburger = iv ? object_getIvar(header, iv) : nil;
	rygInstallStoryPlaybackLongPress(hamburger);

	RYGProbeOnce(@"story.playback.header", @"more=%@ hamburger=%@",
				 more ? @"y" : @"n", hamburger ? @"y" : @"n");
}

%end

%hook IGStoryViewerViewController

- (void)fullscreenSectionController:(id)sc didDisplayStoryModel:(id)model {
	%orig;
	rygInstallStoryFooterLongPress();
}

- (void)fullscreenSectionController:(id)sc didStartToProgressWithStoryItem:(id)item {
	%orig;
	rygInstallStoryFooterLongPress();
	dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.35 * NSEC_PER_SEC)),
		dispatch_get_main_queue(), ^{ rygInstallStoryFooterLongPress(); });
}

%end
