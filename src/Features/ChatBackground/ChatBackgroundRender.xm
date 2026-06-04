// Inserts a managed UIImageView under IG's chat surface to render the user's
// custom background. IG re-applies its own theme via configureWithTheme:..., so
// we re-render there in addition to layoutSubviews.

#import "../../Utils.h"
#import "SCIChatBackgroundManager.h"
#import "SCIChatBgThreadPickerVC.h"
#import <objc/runtime.h>

@interface UIView (SCIChatBG)
- (NSString *)sci_resolveThreadID;
- (void)sci_applyCustomBackground;
@end

static const void *kManagedIVKey = &kManagedIVKey;
static const void *kManagedBackdropKey = &kManagedBackdropKey;
static const void *kLastStateKey = &kLastStateKey;

static NSHashTable<UIView *> *sciLiveViews(void) {
	static NSHashTable *views;
	static dispatch_once_t once;
	dispatch_once(&once, ^{ views = [NSHashTable weakObjectsHashTable]; });
	return views;
}

static void sciInvalidateAll(void) {
	for (UIView *v in [sciLiveViews() allObjects]) {
		objc_setAssociatedObject(v, kLastStateKey, nil, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
		[v setNeedsLayout];
	}
}

static BOOL sciIsPickerSurface(UIView *view) {
	UIResponder *r = view.nextResponder;
	for (NSUInteger i = 0; r && i < 16; i++, r = r.nextResponder) {
		NSString *cls = NSStringFromClass(r.class);
		if ([cls containsString:@"ThemePreview"] || [cls containsString:@"ThemePicker"] || [cls containsString:@"PickerCell"]) return YES;
	}
	return NO;
}

static UIImageView *sciImageView(UIView *view) {
	UIImageView *iv = objc_getAssociatedObject(view, kManagedIVKey);
	if (iv) return iv;

	iv = [UIImageView new];
	iv.contentMode = UIViewContentModeScaleAspectFill;
	iv.clipsToBounds = YES;
	iv.userInteractionEnabled = NO;
	iv.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
	objc_setAssociatedObject(view, kManagedIVKey, iv, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
	return iv;
}

static UIView *sciBackdrop(UIView *view) {
	UIView *bg = objc_getAssociatedObject(view, kManagedBackdropKey);
	if (bg) return bg;

	bg = [UIView new];
	bg.userInteractionEnabled = NO;
	bg.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
	objc_setAssociatedObject(view, kManagedBackdropKey, bg, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
	return bg;
}

static void sciTeardown(UIView *view) {
	UIImageView *iv = objc_getAssociatedObject(view, kManagedIVKey);
	UIView *bg = objc_getAssociatedObject(view, kManagedBackdropKey);

	iv.image = nil;
	[iv removeFromSuperview];
	[bg removeFromSuperview];
	objc_setAssociatedObject(view, kLastStateKey, nil, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
}

%group SCIChatBgRenderGroup

%hook _TtC28IGDirectThreadBackgroundView28IGDirectThreadBackgroundView

- (id)initWithFrame:(CGRect)frame userSession:(id)userSession {
	id v = %orig;
	if (v) [sciLiveViews() addObject:v];
	return v;
}

%new
- (NSString *)sci_resolveThreadID {
	// Bail out inside the theme picker preview surface — same class is reused there.
	return sciIsPickerSurface((UIView *)self) ? nil : [SCIChatBgThreadPickerVC activeThreadID];
}

%new
- (void)sci_applyCustomBackground {
	UIView *view = (UIView *)self;
	SCIChatBackgroundManager *m = [SCIChatBackgroundManager shared];

	if (![m isEnabled]) {
		sciTeardown(view);
		return;
	}

	NSString *tid = [view sci_resolveThreadID];
	NSString *asset = [m resolvedAssetForThreadID:tid];

	if (!asset.length) {
		sciTeardown(view);
		return;
	}

	BOOL dark = view.traitCollection.userInterfaceStyle == UIUserInterfaceStyleDark;
	CGFloat opacity = (CGFloat)[m effectiveOpacityForAsset:asset];
	NSString *state = [NSString stringWithFormat:@"%@|%d|%.3f|%.0fx%.0f", asset, dark, opacity, view.bounds.size.width, view.bounds.size.height];
	NSString *oldState = objc_getAssociatedObject(view, kLastStateKey);

	UIImageView *iv = sciImageView(view);
	UIView *bg = sciBackdrop(view);

	if (bg.superview != view) [view addSubview:bg];
	if (iv.superview != view) [view addSubview:iv];

	bg.frame = view.bounds;
	iv.frame = view.bounds;
	bg.backgroundColor = dark ? UIColor.blackColor : UIColor.whiteColor;

	[view bringSubviewToFront:bg];
	[view bringSubviewToFront:iv];

	if ([oldState isEqualToString:state] && iv.image) {
		iv.alpha = opacity;
		return;
	}

	UIImage *img = [m processedImageForThreadID:tid darkAppearance:dark];
	if (!img) {
		sciTeardown(view);
		return;
	}

	iv.image = img;
	iv.alpha = opacity;
	objc_setAssociatedObject(view, kLastStateKey, state, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
}

- (void)layoutSubviews {
	%orig;
	[(UIView *)self sci_applyCustomBackground];
}

- (void)configureWithTheme:(id)theme threadAppearance:(NSInteger)appearance themeId:(id)themeId traitCollection:(id)trait {
	%orig;
	[(UIView *)self sci_applyCustomBackground];
}

%end

%end

%ctor {
	if (![SCIUtils getBoolPref:SCIPrefChatBackgroundEnabled]) return;

	%init(SCIChatBgRenderGroup);

	[NSNotificationCenter.defaultCenter addObserverForName:SCIChatBackgroundRenderDirtyNotification object:nil queue:NSOperationQueue.mainQueue usingBlock:^(__unused NSNotification *_) {
		sciInvalidateAll();
	}];
}