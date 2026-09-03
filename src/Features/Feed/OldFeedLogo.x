#import "../../Utils.h"
#import <objc/runtime.h>
#import <objc/message.h>
#import <substrate.h>

static BOOL rygWordmarkDisabled(id self, SEL _cmd) { return NO; }

static UIImage *rygOldWordmark(void) {
	static UIImage *img;
	static dispatch_once_t once;
	dispatch_once(&once, ^{
		img = [[UIImage imageNamed:@"ig_logo"] imageWithRenderingMode:UIImageRenderingModeAlwaysTemplate];
	});
	return img;
}

%group RYGOldFeedLogoGroup

%hook _TtC16IGHomeFeedHeader20IGHomeFeedHeaderView

- (void)layoutSubviews {
	%orig;

	id me = (id)self;
	if (![me respondsToSelector:@selector(logoContentView)]) return;
	UIView *content = ((id (*)(id, SEL))objc_msgSend)(me, @selector(logoContentView));

	// logoContentView is the button's own imageView, which UIButton rebuilds from its
	// state map every layout — the image only sticks when set on the button.
	UIButton *btn = (UIButton *)content.superview;
	if (![btn isKindOfClass:[UIButton class]]) return;

	UIImage *img = rygOldWordmark();
	if (!img || btn.currentImage == img) return;

	[btn setImage:img forState:UIControlStateNormal];
	btn.tintColor = UIColor.labelColor;
	btn.imageView.contentMode = UIViewContentModeScaleAspectFit;
}

%end

%end

// IG 444 removed these wordmark flags; the flip is a no-op there, kept for older builds.
%ctor {
	if (![RYGUtils getBoolPref:@"old_feed_logo"]) return;

	NSArray<NSString *> *sels = @[@"isIGWordmark1aEnabled", @"isIGWordmark1aAltEnabled",
	                              @"isIGWordmark1bEnabled", @"isIGWordmark1bAltEnabled"];
	NSArray<NSString *> *classes = @[@"IGDSLauncherConfig",
	                                 @"_TtC11BSLDSConfig11BSLDSConfig",
	                                 @"BSLDSConfig"];

	for (NSString *className in classes) {
		Class c = NSClassFromString(className);
		if (!c) continue;
		for (NSString *name in sels) {
			SEL sel = NSSelectorFromString(name);
			if (!class_getInstanceMethod(c, sel)) continue;
			BOOL (*orig)(id, SEL) = NULL;
			MSHookMessageEx(c, sel, (IMP)rygWordmarkDisabled, (IMP *)&orig);
			RYGProbeHit(@"oldlogo.install", @"%@ %@", className, name);
		}
	}

	%init(RYGOldFeedLogoGroup);
}
