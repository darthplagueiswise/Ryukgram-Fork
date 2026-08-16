// Renders the user's custom image/video background under IG's chat surface,
// re-asserting on configureWithTheme: since IG re-applies its own theme there.

#import "../../Utils.h"
#import "RYGChatBackgroundManager.h"
#import "RYGChatBgThreadPickerVC.h"
#import "RYGChatBgVideoView.h"
#import "RYGChatBgIvars.h"
#import <objc/runtime.h>

@interface UIView (RYGChatBG)
- (NSString *)ryg_resolveThreadID;
- (void)ryg_applyCustomBackground;
@end

static const void *kManagedIVKey = &kManagedIVKey;
static const void *kManagedVideoKey = &kManagedVideoKey;
static const void *kManagedBackdropKey = &kManagedBackdropKey;
static const void *kLastStateKey = &kLastStateKey;

static NSHashTable<UIView *> *rygLiveViews(void) {
	static NSHashTable *views;
	static dispatch_once_t once;
	dispatch_once(&once, ^{ views = [NSHashTable weakObjectsHashTable]; });
	return views;
}

static NSHashTable<UIView *> *rygLiveComposers(void) {
	static NSHashTable *composers;
	static dispatch_once_t once;
	dispatch_once(&once, ^{ composers = [NSHashTable weakObjectsHashTable]; });
	return composers;
}

static void rygInvalidateAll(void) {
	for (UIView *v in [rygLiveViews() allObjects]) {
		objc_setAssociatedObject(v, kLastStateKey, nil, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
		[v setNeedsLayout];
	}
	for (UIView *c in [rygLiveComposers() allObjects]) [c setNeedsLayout];
}

static BOOL rygIsPickerSurface(UIView *view) {
	UIResponder *r = view.nextResponder;
	for (NSUInteger i = 0; r && i < 16; i++, r = r.nextResponder) {
		NSString *cls = NSStringFromClass(r.class);
		if ([cls containsString:@"ThemePreview"] || [cls containsString:@"ThemePicker"] || [cls containsString:@"PickerCell"]) return YES;
	}
	return NO;
}

static UIImageView *rygImageView(UIView *view) {
	UIImageView *iv = objc_getAssociatedObject(view, kManagedIVKey);
	if (iv) return iv;

	iv = [UIImageView new];
	iv.contentMode = UIViewContentModeScaleAspectFill;
	iv.clipsToBounds = YES;
	iv.userInteractionEnabled = NO;
	objc_setAssociatedObject(view, kManagedIVKey, iv, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
	return iv;
}

static RYGChatBgVideoView *rygVideoView(UIView *view) {
	RYGChatBgVideoView *vv = objc_getAssociatedObject(view, kManagedVideoKey);
	if (vv) return vv;

	vv = [[RYGChatBgVideoView alloc] initWithFrame:CGRectZero];
	objc_setAssociatedObject(view, kManagedVideoKey, vv, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
	return vv;
}

static UIView *rygBackdrop(UIView *view) {
	UIView *bg = objc_getAssociatedObject(view, kManagedBackdropKey);
	if (bg) return bg;

	bg = [UIView new];
	bg.userInteractionEnabled = NO;
	objc_setAssociatedObject(view, kManagedBackdropKey, bg, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
	return bg;
}

static void rygTeardown(UIView *view) {
	UIImageView *iv = objc_getAssociatedObject(view, kManagedIVKey);
	RYGChatBgVideoView *vv = objc_getAssociatedObject(view, kManagedVideoKey);
	UIView *bg = objc_getAssociatedObject(view, kManagedBackdropKey);

	iv.image = nil;
	iv.hidden = NO;
	[iv removeFromSuperview];
	vv.onReadyForDisplayChanged = nil;
	vv.videoURL = nil;
	[vv removeFromSuperview];
	[bg removeFromSuperview];
	objc_setAssociatedObject(view, kLastStateKey, nil, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
}

#pragma mark - Composer transparency

// IGDirectComposer is opaque over the background; clear its backing per thread so
// the custom background shows through (neighbor chats stay untouched).
static const void *kComposerOrigBgKey = &kComposerOrigBgKey;
static const void *kComposerOrigHiddenKey = &kComposerOrigHiddenKey;

static NSString *rygComposerThreadID(UIView *composer) {
	static Class tc;
	if (!tc) tc = NSClassFromString(@"IGDirectThreadViewController");

	for (UIResponder *r = composer; r; r = r.nextResponder) {
		if (tc && [r isKindOfClass:tc]) {
			id session = RYGBgIvarValue(r, "_threadSession");
			return RYGBgReadTidFromContainer(RYGBgFindThreadKey(session));
		}
	}
	return nil;
}

static void rygClearComposerBacking(UIView *backing, BOOL clear, BOOL hide) {
	if (!backing) return;

	if (clear) {
		if (!objc_getAssociatedObject(backing, kComposerOrigBgKey)) {
			objc_setAssociatedObject(backing, kComposerOrigBgKey, backing.backgroundColor ?: (id)NSNull.null, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
			objc_setAssociatedObject(backing, kComposerOrigHiddenKey, @(backing.hidden), OBJC_ASSOCIATION_RETAIN_NONATOMIC);
		}
		backing.backgroundColor = UIColor.clearColor;
		if (hide) backing.hidden = YES;
	} else {
		id origBg = objc_getAssociatedObject(backing, kComposerOrigBgKey);
		if (!origBg) return;
		backing.backgroundColor = [origBg isKindOfClass:UIColor.class] ? origBg : nil;
		NSNumber *wasHidden = objc_getAssociatedObject(backing, kComposerOrigHiddenKey);
		if (hide) backing.hidden = wasHidden.boolValue;
		objc_setAssociatedObject(backing, kComposerOrigBgKey, nil, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
		objc_setAssociatedObject(backing, kComposerOrigHiddenKey, nil, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
	}
}

// IG 437's background-view ivar is a Swift lazy-storage slot RYGBgIvarValue can't read;
// fall back to a subview scan.
static const void *kComposerBgViewKey = &kComposerBgViewKey;

static UIView *rygComposerBackgroundView(UIView *composer) {
	UIView *cached = objc_getAssociatedObject(composer, kComposerBgViewKey);
	if (cached && cached.superview) return cached;

	UIView *bg = RYGBgIvarValue(composer, "_composerBackgroundView")
		?: RYGBgIvarValue(composer, "$__lazy_storage_$_composerBackgroundView");
	if (!bg) {
		static Class bvc;
		static dispatch_once_t once;
		dispatch_once(&once, ^{ bvc = NSClassFromString(@"IGDirectComposerBackgroundView"); });
		for (UIView *sub in composer.subviews) {
			if ([sub isKindOfClass:bvc]) { bg = sub; break; }
			for (UIView *s2 in sub.subviews) if ([s2 isKindOfClass:bvc]) { bg = s2; break; }
			if (bg) break;
		}
	}
	if (bg) objc_setAssociatedObject(composer, kComposerBgViewKey, bg, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
	return bg;
}

// Transparent-out the composer's decorative layers (masking + IG 437 light blur) and
// its scroll-view fill — clearing the background view itself would hide the input box.
static void rygSetComposerBackingClear(UIView *bgView, UIView *composerMasking, BOOL clear) {
	UIView *masking = composerMasking ?: RYGBgIvarValue(bgView, "_composerMaskingView");
	UIView *lightBlur = RYGBgIvarValue(bgView, "_lightBlurBackgroundView");
	rygClearComposerBacking(masking, clear, YES);
	rygClearComposerBacking(lightBlur, clear, YES);
	rygClearComposerBacking(bgView, clear, NO);
}

static BOOL rygThreadHasCustomBackground(NSString *tid) {
	RYGChatBackgroundManager *m = [RYGChatBackgroundManager shared];
	return m.isEnabled && tid.length && [m resolvedAssetForThreadID:tid].length > 0;
}

static void rygApplyComposerTransparency(UIView *composer) {
	BOOL clear = rygThreadHasCustomBackground(rygComposerThreadID(composer));
	UIView *bgView = rygComposerBackgroundView(composer);
	UIView *masking = RYGBgIvarValue(composer, "_composerMaskingView");
	rygSetComposerBackingClear(bgView, masking, clear);
}

%group RYGChatBgRenderGroup

%hook _TtC28IGDirectThreadBackgroundView28IGDirectThreadBackgroundView

- (id)initWithFrame:(CGRect)frame userSession:(id)userSession {
	id v = %orig;
	if (v) [rygLiveViews() addObject:v];
	return v;
}

%new
- (NSString *)ryg_resolveThreadID {
	// Bail out inside the theme picker preview surface — same class is reused there.
	return rygIsPickerSurface((UIView *)self) ? nil : [RYGChatBgThreadPickerVC activeThreadID];
}

%new
- (void)ryg_applyCustomBackground {
	UIView *view = (UIView *)self;
	RYGChatBackgroundManager *m = [RYGChatBackgroundManager shared];

	if (![m isEnabled]) {
		rygTeardown(view);
		return;
	}

	NSString *tid = [view ryg_resolveThreadID];
	NSString *asset = [m resolvedAssetForThreadID:tid];

	if (!asset.length) {
		rygTeardown(view);
		return;
	}

	BOOL dark = view.traitCollection.userInterfaceStyle == UIUserInterfaceStyleDark;
	CGFloat opacity = (CGFloat)[m effectiveOpacityForAsset:asset];
	BOOL isVideo = [RYGChatBackgroundManager isVideoAsset:asset];

	CGRect fill = view.bounds;

	UIView *bg = rygBackdrop(view);
	if (bg.superview != view) [view addSubview:bg];
	bg.frame = fill;
	bg.backgroundColor = dark ? UIColor.blackColor : UIColor.whiteColor;
	[view bringSubviewToFront:bg];

	if (isVideo) {
		RYGChatBgVideoView *vv = rygVideoView(view);
		// Poster covers the first-frame decode gap on entry.
		UIImageView *iv = rygImageView(view);

		if (iv.superview != view) [view addSubview:iv];
		if (vv.superview != view) [view addSubview:vv];
		iv.frame = fill;
		vv.frame = fill;
		iv.image = [m imageForAsset:asset];
		iv.alpha = opacity;
		vv.alpha = opacity;

		// Drop the poster once the video paints, else it bleeds through at opacity < 1.
		__weak UIImageView *wiv = iv;
		vv.onReadyForDisplayChanged = ^(BOOL ready) { if (ready) wiv.hidden = YES; };
		iv.hidden = vv.isReadyForDisplay;

		[view bringSubviewToFront:iv];
		[view bringSubviewToFront:vv];

		vv.videoURL = [m urlForRelativeAsset:asset];
		[vv setBlurRadius:(CGFloat)[m effectiveBlurForAsset:asset] dim:(dark ? (CGFloat)[m effectiveDimForAsset:asset] : 0.0)];
		[vv play];
		objc_setAssociatedObject(view, kLastStateKey, [NSString stringWithFormat:@"vid|%@|%.3f", asset, opacity], OBJC_ASSOCIATION_RETAIN_NONATOMIC);
		return;
	}

	NSString *state = [NSString stringWithFormat:@"%@|%d|%.3f|%.0fx%.0f", asset, dark, opacity, fill.size.width, fill.size.height];
	NSString *oldState = objc_getAssociatedObject(view, kLastStateKey);

	RYGChatBgVideoView *oldVV = objc_getAssociatedObject(view, kManagedVideoKey);
	if (oldVV.superview) { oldVV.videoURL = nil; [oldVV removeFromSuperview]; }

	UIImageView *iv = rygImageView(view);
	if (iv.superview != view) [view addSubview:iv];
	iv.frame = fill;
	iv.hidden = NO;
	[view bringSubviewToFront:iv];

	if ([oldState isEqualToString:state] && iv.image) {
		iv.alpha = opacity;
		return;
	}

	UIImage *img = [m processedImageForThreadID:tid darkAppearance:dark];
	if (!img) {
		rygTeardown(view);
		return;
	}

	iv.image = img;
	iv.alpha = opacity;
	objc_setAssociatedObject(view, kLastStateKey, state, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
}

- (void)layoutSubviews {
	%orig;
	[(UIView *)self ryg_applyCustomBackground];
}

- (void)configureWithTheme:(id)theme threadAppearance:(NSInteger)appearance themeId:(id)themeId traitCollection:(id)trait {
	%orig;
	[(UIView *)self ryg_applyCustomBackground];
}

%end

%hook _TtC16IGDirectComposer16IGDirectComposer

- (void)layoutSubviews {
	%orig;
	[rygLiveComposers() addObject:self];
	rygApplyComposerTransparency((UIView *)self);
}

%end

// IG's own paint point for the input bar — re-assert transparency when it recolors.
%hook IGDirectComposerBackgroundView

- (void)updateBackgroundColorWithBackgroundConfig:(id)config {
	%orig;
	UIView *bgView = (UIView *)self;
	BOOL clear = rygThreadHasCustomBackground(rygComposerThreadID(bgView));
	rygSetComposerBackingClear(bgView, nil, clear);
}

%end

%end

%ctor {
	if (![RYGUtils getBoolPref:RYGPrefChatBackgroundEnabled]) return;

	%init(RYGChatBgRenderGroup);

	[NSNotificationCenter.defaultCenter addObserverForName:RYGChatBackgroundRenderDirtyNotification object:nil queue:NSOperationQueue.mainQueue usingBlock:^(__unused NSNotification *_) {
		rygInvalidateAll();
	}];
}