#import "../../Utils.h"
#import "../../InstagramHeaders.h"
#import <objc/runtime.h>
#import <objc/message.h>
#import <substrate.h>

// When tap control is set to pause/play, these enhancements activate:
// - Mute sub-toggle hidden (only play/pause icon visible)
// - Audio forced on in reels tab
// - Play/pause indicator hidden when video plays (fixes IG bug after hold/zoom)
// - Playback toggle synced with overlay visibility during hold/zoom

static BOOL rygIsPausePlayMode(void) {
	return [[RYGUtils getStringPref:@"reels_tap_control"] isEqualToString:@"pause"];
}

static BOOL rygIsInReelsTab = NO;
static BOOL rygIsZooming = NO;

static id rygIvar(id obj, const char *name) {
	Ivar ivar = obj ? class_getInstanceVariable([obj class], name) : NULL;
	return ivar ? object_getIvar(obj, ivar) : nil;
}

static BOOL rygBool(id obj, SEL sel) {
	return obj && [obj respondsToSelector:sel] ? ((BOOL(*)(id, SEL))objc_msgSend)(obj, sel) : NO;
}

// ============ FIND PLAYBACK VIEW ============
// Handles two IG A/B test variants:
// 1. IGSundialPlaybackToggleView wrapper (contains play + mute subviews)
// 2. Standalone IGDSMediaIconButton (no wrapper)

static UIView * _Nullable rygFindPlaybackView(UIView *videoCell) {
	if (!videoCell) return nil;

	Class toggleClass = objc_getClass("IGSundialPlaybackToggle.IGSundialPlaybackToggleView");
	if (!toggleClass) toggleClass = NSClassFromString(@"_TtC23IGSundialPlaybackToggle27IGSundialPlaybackToggleView");

	Class iconBtnClass = NSClassFromString(@"IGDSMediaIconButton");
	UIView *fallbackIconBtn = nil;
	NSMutableArray *stack = [NSMutableArray arrayWithObject:videoCell];

	for (NSUInteger d = 0; d < 6 && stack.count; d++) {
		NSMutableArray *next = [NSMutableArray array];

		for (UIView *view in stack) {
			for (UIView *sub in view.subviews) {
				if (toggleClass && [sub isKindOfClass:toggleClass]) return sub;

				if (iconBtnClass && [sub isKindOfClass:iconBtnClass] &&
					sub.frame.size.width > 50 && sub.frame.size.height > 50 &&
					!sub.hidden && sub.frame.origin.x > 100) {
					fallbackIconBtn = sub;
				}

				if (sub.subviews.count) [next addObject:sub];
			}
		}

		stack = next;
	}

	return fallbackIconBtn;
}
// ============ KVO: SYNC PLAYBACK VIEW WITH OVERLAY ============
// IG animates the overlay container via Core Animation during hold/zoom.
// The download button (tag 1337) is inside the container so it hides automatically.
// The playback toggle is in a separate view branch — we KVO the download
// button's layer.opacity and sync the toggle to match.

@interface RYGOpacityObserver : NSObject
@end

@implementation RYGOpacityObserver

- (void)observeValueForKeyPath:(NSString *)keyPath ofObject:(id)object change:(NSDictionary *)change context:(void *)context {
	if (![keyPath isEqualToString:@"opacity"]) return;

	CALayer *layer = (CALayer *)object;
	UIView *dlBtn = [layer.delegate isKindOfClass:UIView.class] ? (UIView *)layer.delegate : nil;
	if (!dlBtn) return;

	UIView *cell = dlBtn.superview;
	while (cell && ![NSStringFromClass(cell.class) containsString:@"VideoCell"])
		cell = cell.superview;

	// Skip during zoom — zoom callbacks handle the play button directly
	if (rygIsZooming) return;

	UIView *playView = rygFindPlaybackView(cell);
	if (playView) playView.layer.opacity = [change[NSKeyValueChangeNewKey] floatValue];
}

@end

static RYGOpacityObserver *rygObserver = nil;
static NSHashTable *rygObservedLayers = nil;

static void rygSetupKVO(UIView *ufi) {
	UIView *parent = ufi.superview;
	if (!parent) return;

	UIView *dlBtn = [parent viewWithTag:1337];
	if (!dlBtn) return;

	if (!rygObserver) rygObserver = [RYGOpacityObserver new];
	if (!rygObservedLayers) rygObservedLayers = [NSHashTable weakObjectsHashTable];
	if ([rygObservedLayers containsObject:dlBtn.layer]) return;

	[dlBtn.layer addObserver:rygObserver forKeyPath:@"opacity" options:NSKeyValueObservingOptionNew context:NULL];
	[rygObservedLayers addObject:dlBtn.layer];
}

// ============ HIDE PLAY INDICATOR ON PLAY + ZOOM ============

// Use hidden for play/unpause (IG controls unhiding on next pause).
// Use layer.opacity for zoom/KVO (we control restore).
static void rygHidePlayView(id cell) {
	UIView *playView = rygFindPlaybackView(cell);
	if (playView) playView.hidden = YES;

	UIView *indicator = rygIvar(cell, "_playPauseMediaIndicator");
	if (indicator && indicator != playView) indicator.hidden = YES;
}

static void rygSetPlayViewOpacity(id cell, CGFloat opacity) {
	UIView *playView = rygFindPlaybackView(cell);
	if (playView) playView.layer.opacity = opacity;

	UIView *indicator = rygIvar(cell, "_playPauseMediaIndicator");
	if (indicator && indicator != playView) indicator.layer.opacity = opacity;
}

static NSMutableSet<NSString *> *rygNoAudioMediaIds = nil;

static void rygForceUnmuteCell(id cell) {
	if (!cell) return;

	NSString *mediaPk = nil;
	if ([cell respondsToSelector:@selector(mediaPk)]) {
		id pk = ((id(*)(id, SEL))objc_msgSend)(cell, @selector(mediaPk));
		if (pk) mediaPk = [NSString stringWithFormat:@"%@", pk];
	}

	if (mediaPk && [rygNoAudioMediaIds containsObject:mediaPk]) return;

	if ([cell respondsToSelector:@selector(hasAudio)] && !rygBool(cell, @selector(hasAudio))) {
		if (mediaPk) {
			if (!rygNoAudioMediaIds) rygNoAudioMediaIds = [NSMutableSet new];
			[rygNoAudioMediaIds addObject:mediaPk];
		}
		return;
	}

	if ([cell respondsToSelector:@selector(isAudioEnabled)] && rygBool(cell, @selector(isAudioEnabled))) return;

	SEL sel = @selector(setAudioEnabled:forReason:);
	if ([cell respondsToSelector:sel])
		((void(*)(id, SEL, BOOL, NSInteger))objc_msgSend)(cell, sel, YES, 0);
}

%group ReelsPauseModeGroup

%hook IGSundialViewerVideoCell

// hidden=YES on play; IG resets it on the next pause.
- (void)sundialVideoPlaybackViewDidStartPlaying:(id)view {
	%orig;
	if (!rygIsPausePlayMode()) return;

	rygHidePlayView(self);
	if (rygIsInReelsTab) rygForceUnmuteCell(self);
}

- (void)videoViewDidUnpause:(id)view {
	%orig;
	if (rygIsPausePlayMode()) rygHidePlayView(self);
}

// Zoom — use layer.opacity (we restore it ourselves on zoom end)
- (void)sundialVideoPlaybackView:(id)pbView willBeginZoomInteractionForView:(id)view withLogging:(id)logging {
	%orig;

	rygIsZooming = YES;

	if (rygIsPausePlayMode()) rygSetPlayViewOpacity(self, 0);
}

- (void)sundialVideoPlaybackView:(id)pbView didEndZoomInteractionForView:(id)view withLogging:(id)logging minScale:(CGFloat)minScale {
	%orig;

	rygIsZooming = NO;

	if (!rygIsPausePlayMode()) return;

	rygSetPlayViewOpacity(self, 1);

	__weak id weakSelf = self;
	dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.3 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
		id strongSelf = weakSelf;
		if (strongSelf && rygBool(strongSelf, @selector(isPlaying))) rygHidePlayView(strongSelf);
	});
}

%end

// ============ PHOTO REELS: TAP-TO-MUTE ============
// Skip IG's single-tap delegate on photo cells and drive the mute via the
// same hardware-switch notification StoryAudioToggle uses.

extern "C" void rygToggleStoryAudio(void);

static BOOL rygIsPhotoMuteEnabled(void) {
	return rygIsPausePlayMode() && [RYGUtils getBoolPref:@"reels_photo_tap_mute"];
}

%hook IGSundialViewerPhotoCell

- (void)gestureController:(id)gc didObserveSingleTap:(id)tap {
	if (rygIsPhotoMuteEnabled()) {
		rygToggleStoryAudio();
		return;
	}

	%orig;
}

%end

%hook IGSundialViewerCarouselPhotoCell

- (void)gestureController:(id)gc didObserveSingleTap:(id)tap {
	if (rygIsPhotoMuteEnabled()) {
		rygToggleStoryAudio();
		return;
	}

	%orig;
}

%end

// Carousels route the tap through the outer cell, so hijack there too —
// but only when the visible page is a photo. Video pages keep %orig.

%hook IGSundialViewerCarouselCell

- (void)gestureController:(id)gc didObserveSingleTap:(id)tap {
	if (!rygIsPhotoMuteEnabled()) {
		%orig;
		return;
	}

	UICollectionView *cv = rygIvar(self, "_collectionView");
	if (![cv isKindOfClass:UICollectionView.class]) {
		%orig;
		return;
	}

	Ivar ivar = class_getInstanceVariable([self class], "_currentIndex");
	NSInteger index = ivar ? *(NSInteger *)((uint8_t *)(__bridge void *)self + ivar_getOffset(ivar)) : NSNotFound;
	id cell = nil;

	if (index != NSNotFound)
		cell = [cv cellForItemAtIndexPath:[NSIndexPath indexPathForItem:index inSection:0]];

	if (!cell) {
		CGPoint center = CGPointMake(CGRectGetMidX(cv.bounds), CGRectGetMidY(cv.bounds));
		CGFloat bestDistance = CGFLOAT_MAX;

		for (NSIndexPath *ip in [cv indexPathsForVisibleItems]) {
			UICollectionViewLayoutAttributes *attrs = [cv layoutAttributesForItemAtIndexPath:ip];
			if (!attrs) continue;

			CGFloat dx = attrs.center.x - center.x;
			CGFloat dy = attrs.center.y - center.y;
			CGFloat distance = (dx * dx) + (dy * dy);

			if (distance < bestDistance) {
				bestDistance = distance;
				cell = [cv cellForItemAtIndexPath:ip];
			}
		}
	}

	NSString *cls = NSStringFromClass([cell class]);
	if ([cls containsString:@"PhotoCell"] && ![cls containsString:@"VideoCell"]) {
		rygToggleStoryAudio();
		return;
	}

	%orig;
}

%end

// ============ UFI: SYNC DOWNLOAD BUTTON + SETUP KVO ============

%hook _TtC26IGSundialViewerVerticalUFI26IGSundialViewerVerticalUFI

- (void)setAlpha:(CGFloat)alpha {
	%orig;

	UIView *parent = ((UIView *)self).superview;
	if (!parent) return;

	UIView *dlBtn = [parent viewWithTag:1337];
	if (dlBtn) dlBtn.alpha = alpha;

	rygSetupKVO((UIView *)self);
}

%end

// ============ HIDE MUTE SUBVIEW IN PLAYBACK TOGGLE ============
// When pause/play mode is active, hide the mute sub-toggle (top subview)
// and keep only the play/pause button visible.

static void (*orig_playbackToggle_didMoveToSuperview)(id self, SEL _cmd);
static void (*orig_playbackToggle_layoutSubviews)(id self, SEL _cmd);

static void rygHideMuteSubview(UIView *toggleView) {
	if (!rygIsPausePlayMode()) {
		for (UIView *sub in toggleView.subviews) {
			if (sub.tag == 9999) {
				sub.hidden = NO;
				sub.alpha = 1;
				sub.userInteractionEnabled = YES;
				sub.tag = 0;
			}
		}
		return;
	}

	NSArray *subs = toggleView.subviews;
	if (subs.count < 2) return;

	UIView *topView = nil;
	CGFloat minY = CGFLOAT_MAX;
	NSUInteger visibleCount = 0;

	for (UIView *sub in subs) {
		if (sub.frame.size.width < 1 || sub.frame.size.height < 1) continue;

		visibleCount++;
		if (sub.frame.origin.y < minY) {
			minY = sub.frame.origin.y;
			topView = sub;
		}
	}

	if (topView && visibleCount >= 2) {
		topView.hidden = YES;
		topView.alpha = 0;
		topView.userInteractionEnabled = NO;
		topView.tag = 9999;
	}
}

static void new_playbackToggle_didMoveToSuperview(id self, SEL _cmd) {
	orig_playbackToggle_didMoveToSuperview(self, _cmd);
	rygHideMuteSubview((UIView *)self);
}

static void new_playbackToggle_layoutSubviews(id self, SEL _cmd) {
	orig_playbackToggle_layoutSubviews(self, _cmd);
	rygHideMuteSubview((UIView *)self);
}

// ============ FORCE AUDIO IN REELS TAB ============

// `swift__currentAudioCell` is the Swift form of the same accessor — kept as a
// fallback in case the bridged ObjC selector ever stops registering.
static id rygCurrentAudioCell(id feedVC) {
	static SEL legacySel, swiftSel;
	static dispatch_once_t once;

	dispatch_once(&once, ^{
		legacySel = NSSelectorFromString(@"_currentAudioCell");
		swiftSel = NSSelectorFromString(@"swift__currentAudioCell");
	});

	SEL sel = [feedVC respondsToSelector:legacySel] ? legacySel : ([feedVC respondsToSelector:swiftSel] ? swiftSel : NULL);
	return sel ? ((id(*)(id, SEL))objc_msgSend)(feedVC, sel) : nil;
}

static void rygForceCurrentFeedAudio(id feedVC) {
	if (!rygIsPausePlayMode() || !rygIsInReelsTab) return;

	id cell = rygCurrentAudioCell(feedVC);
	if (cell) rygForceUnmuteCell(cell);
}

%hook IGSundialFeedViewController

- (void)viewDidAppear:(BOOL)animated {
	%orig;

	rygIsInReelsTab = YES;

	// Retry-until-ready: the first reel's cell may not be wired up yet.
	if (!rygIsPausePlayMode()) return;

	__weak id weakSelf = self;
	NSTimeInterval delays[] = {0.10, 0.35, 0.75, 1.10, 1.55};

	for (NSUInteger i = 0; i < sizeof(delays) / sizeof(delays[0]); i++) {
		NSTimeInterval delay = delays[i];

		dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(delay * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
			rygForceCurrentFeedAudio(weakSelf);
		});
	}
}

- (void)viewWillDisappear:(BOOL)animated {
	%orig;

	rygIsInReelsTab = NO;
}

- (void)scrollViewDidEndDecelerating:(UIScrollView *)scrollView {
	%orig;

	rygForceCurrentFeedAudio(self);
}

- (void)scrollViewDidEndDragging:(UIScrollView *)scrollView willDecelerate:(BOOL)decelerate {
	%orig;
	if (!decelerate) rygForceCurrentFeedAudio(self);
}

%end

%end // ReelsPauseModeGroup

// ============ RUNTIME HOOKS ============

%ctor {
	if (!rygIsPausePlayMode()) return;

	%init(ReelsPauseModeGroup);

	Class toggleClass = objc_getClass("IGSundialPlaybackToggle.IGSundialPlaybackToggleView");
	if (!toggleClass) toggleClass = NSClassFromString(@"_TtC23IGSundialPlaybackToggle27IGSundialPlaybackToggleView");

	if (toggleClass) {
		MSHookMessageEx(toggleClass,
			@selector(didMoveToSuperview), (IMP)new_playbackToggle_didMoveToSuperview, (IMP *)&orig_playbackToggle_didMoveToSuperview);
		MSHookMessageEx(toggleClass,
			@selector(layoutSubviews), (IMP)new_playbackToggle_layoutSubviews, (IMP *)&orig_playbackToggle_layoutSubviews);
	}
}