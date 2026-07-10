// Replace IG near-black surfaces with pure black under OLED mode.
// RyukGram surfaces are exempt — they keep the stock iOS appearance.

#import "../../Utils.h"
#import "SCITheme.h"

static NSArray *SCIFlatOLEDColors(NSArray *colors) {
	if (!colors.count) return nil;

	for (id raw in colors) {
		if (![SCITheme cgColorIsNearBlack:(__bridge CGColorRef)raw]) return nil;
	}

	id black = (__bridge id)[SCITheme backgroundColor].CGColor;
	NSMutableArray *flat = [NSMutableArray arrayWithCapacity:colors.count];

	for (NSUInteger i = 0; i < colors.count; i++) {
		[flat addObject:black];
	}

	return flat;
}

// IG surfaces whose grey matches page-background values but must stay grey
// (buttons, search fields, Notes bubbles). Matched on the view + its ancestors.
static NSArray<NSString *> *SCIOLEDKeepGreyClasses(void) {
	static NSArray *names;
	static dispatch_once_t once;
	dispatch_once(&once, ^{ names = @[@"NotesIconic", @"IGSearchBar", @"IGProfilePhotoView", @"IGShortenableTextButton", @"BKBloksFlexboxView", @"IGMediaThumbnailView"]; });
	return names;
}

// Verdicts memoized on the Class — identity is stable, so the cache never goes stale.
static BOOL SCIColorIsDynamic(UIColor *color) {
	Class cls = [color class];
	static const void *key = &key;
	NSNumber *cached = objc_getAssociatedObject(cls, key);
	if (cached) return cached.boolValue;
	BOOL dyn = [NSStringFromClass(cls) containsString:@"Dynamic"];
	objc_setAssociatedObject(cls, key, @(dyn), OBJC_ASSOCIATION_RETAIN_NONATOMIC);
	return dyn;
}

static BOOL SCIClassMatchesKeepGrey(Class cls) {
	static const void *key = &key;
	NSNumber *cached = objc_getAssociatedObject(cls, key);
	if (cached) return cached.boolValue;
	NSString *name = NSStringFromClass(cls);
	BOOL match = NO;
	for (NSString *needle in SCIOLEDKeepGreyClasses()) {
		if ([name containsString:needle]) { match = YES; break; }
	}
	objc_setAssociatedObject(cls, key, @(match), OBJC_ASSOCIATION_RETAIN_NONATOMIC);
	return match;
}

static BOOL SCIOLEDKeepGrey(UIView *view) {
	for (UIView *v = view; v; v = v.superview) {
		if (SCIClassMatchesKeepGrey([v class])) return YES;
	}
	return NO;
}

// Views are often colored before joining a hierarchy — no responder chain yet to
// prove RyukGram ownership. Stash the color and undo the flatten on attach.
static const void *kSCIFlattenedOriginalKey = &kSCIFlattenedOriginalKey;

%group OLEDRecolorGroup

%hook UIView

- (void)setBackgroundColor:(UIColor *)color {
	if (!color) {
		%orig;
		return;
	}

	// Only dynamic colors read light at set-time; static ones resolve to themselves,
	// so skip the trait resolve on the hot path.
	UIColor *resolved = SCIColorIsDynamic(color) ? [color resolvedColorWithTraitCollection:self.traitCollection] : color;

	if ([SCITheme colorIsDarkSurface:resolved] && !SCIOLEDKeepGrey(self)) {
		if ([SCITheme isTweakSurface:self]) {
			%orig;
			return;
		}
		// Stash for the didMoveToWindow restore only while detached; an attached view's verdict is final.
		if (!self.window)
			objc_setAssociatedObject(self, kSCIFlattenedOriginalKey, color, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
		%orig([SCITheme backgroundColor]);
		return;
	}

	if (objc_getAssociatedObject(self, kSCIFlattenedOriginalKey))
		objc_setAssociatedObject(self, kSCIFlattenedOriginalKey, nil, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
	%orig;
}

- (void)didMoveToWindow {
	%orig;
	if (!self.window) return;

	UIColor *original = objc_getAssociatedObject(self, kSCIFlattenedOriginalKey);
	if (!original) return;

	objc_setAssociatedObject(self, kSCIFlattenedOriginalKey, nil, OBJC_ASSOCIATION_RETAIN_NONATOMIC);

	if ([SCITheme isTweakSurface:self]) {
		// Re-enters the hook; chain now proves ownership.
		self.backgroundColor = original;
	}
}

%end

%hook CAGradientLayer

- (void)setColors:(NSArray *)colors {
	NSArray *flat = SCIFlatOLEDColors(colors);
	%orig(flat ?: colors);
}

%end

%end

%ctor {
	[SCITheme migrateLegacyPrefs];

	if ([SCITheme shouldRecolor]) {
		%init(OLEDRecolorGroup);
	}
}