// Replace IG near-black surfaces with pure black under OLED mode.
// RyukGram surfaces are exempt — they keep the stock iOS appearance.

#import "../../Utils.h"
#import "RYGTheme.h"

static NSArray *RYGFlatOLEDColors(NSArray *colors) {
	if (!colors.count) return nil;

	for (id raw in colors) {
		if (![RYGTheme cgColorIsNearBlack:(__bridge CGColorRef)raw]) return nil;
	}

	id black = (__bridge id)[RYGTheme backgroundColor].CGColor;
	NSMutableArray *flat = [NSMutableArray arrayWithCapacity:colors.count];

	for (NSUInteger i = 0; i < colors.count; i++) {
		[flat addObject:black];
	}

	return flat;
}

// IG greys that match page-background values but must stay grey.
static NSArray<NSString *> *RYGOLEDKeepGreyClasses(void) {
	static NSArray *names;
	static dispatch_once_t once;
	dispatch_once(&once, ^{ names = @[@"NotesIconic", @"IGSearchBar", @"IGProfilePhotoView", @"IGShortenableTextButton", @"BKBloksFlexboxView", @"IGMediaThumbnailView"]; });
	return names;
}

// Verdicts memoized on the Class — identity is stable, so the cache never goes stale.
static BOOL RYGColorIsDynamic(UIColor *color) {
	Class cls = [color class];
	static const void *key = &key;
	NSNumber *cached = objc_getAssociatedObject(cls, key);
	if (cached) return cached.boolValue;
	BOOL dyn = [NSStringFromClass(cls) containsString:@"Dynamic"];
	objc_setAssociatedObject(cls, key, @(dyn), OBJC_ASSOCIATION_RETAIN_NONATOMIC);
	return dyn;
}

static BOOL RYGClassMatchesKeepGrey(Class cls) {
	static const void *key = &key;
	NSNumber *cached = objc_getAssociatedObject(cls, key);
	if (cached) return cached.boolValue;
	NSString *name = NSStringFromClass(cls);
	BOOL match = NO;
	for (NSString *needle in RYGOLEDKeepGreyClasses()) {
		if ([name containsString:needle]) { match = YES; break; }
	}
	objc_setAssociatedObject(cls, key, @(match), OBJC_ASSOCIATION_RETAIN_NONATOMIC);
	return match;
}

// Secondary buttons (Follow, Message) share IG's page-tier grey; flattening erases them.
static BOOL RYGOLEDKeepGrey(UIView *view, BOOL allowControl) {
	for (UIView *v = view; v; v = v.superview) {
		if (RYGClassMatchesKeepGrey([v class])) return YES;
		if (allowControl && [v isKindOfClass:UIControl.class]) return YES;
	}
	return NO;
}

// A detached view has no responder chain to prove RyukGram ownership, so undo on attach.
static const void *kRYGFlattenedOriginalKey = &kRYGFlattenedOriginalKey;

%group OLEDRecolorGroup

%hook UIView

- (void)setBackgroundColor:(UIColor *)color {
	if (!color) { %orig; return; }

	// Static colors resolve to themselves, so skip the trait resolve on the hot path.
	UIColor *resolved = RYGColorIsDynamic(color) ? [color resolvedColorWithTraitCollection:self.traitCollection] : color;

	if ([RYGTheme colorIsDarkSurface:resolved] && !RYGOLEDKeepGrey(self, ![RYGTheme colorIsNearBlack:resolved])) {
		if ([RYGTheme isTweakSurface:self]) { %orig; return; }
		// An attached view's verdict is final, so only stash while detached.
		if (!self.window)
			objc_setAssociatedObject(self, kRYGFlattenedOriginalKey, color, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
		%orig([RYGTheme backgroundColor]);
		return;
	}

	if (objc_getAssociatedObject(self, kRYGFlattenedOriginalKey))
		objc_setAssociatedObject(self, kRYGFlattenedOriginalKey, nil, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
	%orig;
}

- (void)didMoveToWindow {
	%orig;
	if (!self.window) return;

	UIColor *original = objc_getAssociatedObject(self, kRYGFlattenedOriginalKey);
	if (!original) return;

	objc_setAssociatedObject(self, kRYGFlattenedOriginalKey, nil, OBJC_ASSOCIATION_RETAIN_NONATOMIC);

	if ([RYGTheme isTweakSurface:self]) {
		// Re-enters the hook; chain now proves ownership.
		self.backgroundColor = original;
	}
}

%end

%hook CAGradientLayer

- (void)setColors:(NSArray *)colors {
	NSArray *flat = RYGFlatOLEDColors(colors);
	%orig(flat ?: colors);
}

%end

%end

%ctor {
	[RYGTheme migrateLegacyPrefs];

	if ([RYGTheme shouldRecolor]) {
		%init(OLEDRecolorGroup);
	}
}