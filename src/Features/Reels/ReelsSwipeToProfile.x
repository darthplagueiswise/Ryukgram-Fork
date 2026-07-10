#import "../../Utils.h"
#import "../../InstagramHeaders.h"
#import <objc/runtime.h>
#import <objc/message.h>

// Swipe a reel left → open the author's profile via IG's own header tap so
// the back gesture returns to the reel. Single-author uses
// IGUnifiedVideoUserButton; collab uses the coauthor text attribution view's
// IGCoreTextView URL span routed through IG's own link handler.

static char kSCIReelsSwipePanKey;

static const CGFloat kSCIReelsSwipeBottomIgnore = 140.0;
static const NSTimeInterval kSCIReelsSwipeMaxDuration = 0.40;

static BOOL sciReelsSwipeEnabled(void) {
	return [SCIUtils getBoolPref:@"reels_swipe_to_profile"];
}

static UIView *sciDeepFindByClass(UIView *root, Class cls) {
	if (!root || !cls) return nil;
	if ([root isKindOfClass:cls]) return root;

	for (UIView *sub in root.subviews) {
		UIView *hit = sciDeepFindByClass(sub, cls);
		if (hit) return hit;
	}

	return nil;
}

static UIView *sciCurrentReelCell(UIViewController *vc) {
	if (!vc) return nil;

	SEL sels[] = {
		@selector(currentViewCell),
		@selector(swift__currentVideoCell),
		@selector(currentAdCell),
	};

	for (NSUInteger i = 0; i < sizeof(sels) / sizeof(sels[0]); i++) {
		if (![vc respondsToSelector:sels[i]]) continue;

		id cell = ((id (*)(id, SEL))objc_msgSend)(vc, sels[i]);
		if ([cell isKindOfClass:UIView.class]) return cell;
	}

	return nil;
}

static NSAttributedString *sciAttributedStringFromCoreTextView(id core) {
	if (!core) return nil;

	SEL styledSel = @selector(styledString);
	id styled = [core respondsToSelector:styledSel] ? ((id (*)(id, SEL))objc_msgSend)(core, styledSel) : nil;

	if (!styled) {
		Ivar iv = class_getInstanceVariable([core class], "_styledString");
		styled = iv ? object_getIvar(core, iv) : nil;
	}

	SEL attrSel = @selector(attributedString);
	id raw = [styled respondsToSelector:attrSel] ? ((id (*)(id, SEL))objc_msgSend)(styled, attrSel) : nil;

	if (!raw) {
		Ivar iv = styled ? class_getInstanceVariable([styled class], "_attributedString") : NULL;
		raw = iv ? object_getIvar(styled, iv) : nil;
	}

	return [raw isKindOfClass:NSAttributedString.class] ? raw : nil;
}

static BOOL sciFirstURL(NSAttributedString *as, NSURL **outURL, NSString **outString) {
	if (!as.length) return NO;

	__block NSURL *url = nil;
	__block NSString *text = nil;

	[as enumerateAttribute:@"URL" inRange:NSMakeRange(0, as.length) options:0 usingBlock:^(id value, NSRange range, BOOL *stop) {
		if ([value isKindOfClass:NSURL.class]) {
			url = value;
		} else if ([value isKindOfClass:NSString.class]) {
			url = [NSURL URLWithString:value];
		}

		if (url) {
			text = [as.string substringWithRange:range];
			*stop = YES;
		}
	}];

	if (!url) return NO;

	if (outURL) *outURL = url;
	if (outString) *outString = text;
	return YES;
}

// Collab reels: reuse the coauthor text attribution view's own URL handler.
static BOOL sciTryCoauthorTap(UIView *cell) {
	static Class textCls;
	static dispatch_once_t once;
	dispatch_once(&once, ^{
		textCls = NSClassFromString(@"_TtC35IGSundialViewerUserAttributionSwift46IGSundialViewerCoauthorUserTextAttributionView");
	});

	UIView *attrib = sciDeepFindByClass(cell, textCls);
	if (!attrib) return NO;

	SEL textSel = @selector(attributionTextView);
	id core = [attrib respondsToSelector:textSel] ? ((id (*)(id, SEL))objc_msgSend)(attrib, textSel) : nil;

	if (!core) {
		Ivar iv = class_getInstanceVariable([attrib class], "attributionTextView");
		core = iv ? object_getIvar(attrib, iv) : nil;
	}

	NSURL *url = nil;
	NSString *text = nil;

	if (!sciFirstURL(sciAttributedStringFromCoreTextView(core), &url, &text)) return NO;

	SEL tapSel = @selector(coreTextView:didTapOnString:URL:);
	if (![attrib respondsToSelector:tapSel]) return NO;

	((void (*)(id, SEL, id, id, id))objc_msgSend)(attrib, tapSel, core, text, url);
	return YES;
}

// Single-author reels: reuse IGUnifiedVideoUserButton's own tap handler.
static BOOL sciTryHeaderButtonTap(UIView *cell) {
	Class buttonCls = %c(IGUnifiedVideoUserButton);
	UIView *button = sciDeepFindByClass(cell, buttonCls);
	if (!button) return NO;

	SEL tapSel = NSSelectorFromString(@"_handleSingleTap:");
	if (![button respondsToSelector:tapSel]) return NO;

	UITapGestureRecognizer *tap = nil;
	Ivar iv = class_getInstanceVariable([button class], "_singleTapRecognizer");
	id raw = iv ? object_getIvar(button, iv) : nil;

	if ([raw isKindOfClass:UITapGestureRecognizer.class]) {
		tap = raw;
	} else {
		for (UIGestureRecognizer *gr in button.gestureRecognizers) {
			if ([gr isKindOfClass:UITapGestureRecognizer.class]) {
				tap = (UITapGestureRecognizer *)gr;
				break;
			}
		}
	}

	if (!tap) return NO;

	((void (*)(id, SEL, id))objc_msgSend)(button, tapSel, tap);
	return YES;
}

static BOOL sciTriggerHeaderUsernameTap(UIViewController *vc) {
	UIView *cell = sciCurrentReelCell(vc);
	if (!cell) return NO;

	return sciTryHeaderButtonTap(cell) || sciTryCoauthorTap(cell);
}

// Carousel reels use horizontal paging, so don't hijack left swipes there.
static BOOL sciCurrentReelIsCarousel(UIViewController *vc) {
	UIView *cell = sciCurrentReelCell(vc);
	if (!cell) return NO;
	if ([NSStringFromClass([cell class]) containsString:@"Carousel"]) return YES;
	Class carousel = %c(IGSundialViewerCarouselCell);
	return carousel && [cell isKindOfClass:carousel];
}

// Make parent pans wait for our left-swipe recognizer, while other directions
// still pass through normally.
static void sciCoupleParentPanRecognizers(UIView *view, UIPanGestureRecognizer *ourPan) {
	for (UIView *v = view.superview; v; v = v.superview) {
		for (UIGestureRecognizer *gr in v.gestureRecognizers) {
			if (gr != ourPan && [gr isKindOfClass:UIPanGestureRecognizer.class]) {
				[gr requireGestureRecognizerToFail:ourPan];
			}
		}

		if ([v isKindOfClass:UIScrollView.class]) {
			UIPanGestureRecognizer *pan = ((UIScrollView *)v).panGestureRecognizer;
			if (pan && pan != ourPan) [pan requireGestureRecognizerToFail:ourPan];
		}
	}
}

@interface SCIReelsSwipeToProfileDelegate : NSObject <UIGestureRecognizerDelegate>
@property (nonatomic, weak) UIViewController *owner;
@property (nonatomic, weak) UIPanGestureRecognizer *pan;
@property (nonatomic, assign) NSTimeInterval startTime;
@property (nonatomic, assign) BOOL coupled;
@end

@implementation SCIReelsSwipeToProfileDelegate

- (BOOL)gestureRecognizerShouldBegin:(UIPanGestureRecognizer *)gr {
	if (!sciReelsSwipeEnabled()) return NO;

	CGPoint velocity = [gr velocityInView:gr.view];
	if (!(velocity.x < 0.0 && fabs(velocity.x) > fabs(velocity.y) * 1.2)) return NO;

	CGPoint loc = [gr locationInView:gr.view];
	if (loc.y > gr.view.bounds.size.height - kSCIReelsSwipeBottomIgnore) return NO;

	if (sciCurrentReelIsCarousel(self.owner)) return NO;

	self.startTime = CACurrentMediaTime();
	return YES;
}

- (BOOL)gestureRecognizer:(UIGestureRecognizer *)gr shouldRecognizeSimultaneouslyWithGestureRecognizer:(UIGestureRecognizer *)other {
	return YES;
}

- (void)handle:(UIPanGestureRecognizer *)gr {
	if (gr.state != UIGestureRecognizerStateEnded) return;
	if (CACurrentMediaTime() - self.startTime > kSCIReelsSwipeMaxDuration) return;

	CGPoint translation = [gr translationInView:gr.view];
	CGPoint velocity = [gr velocityInView:gr.view];

	if (!(translation.x < -60.0 || velocity.x < -400.0)) return;
	if (fabs(translation.x) < fabs(translation.y) * 1.2) return;

	sciTriggerHeaderUsernameTap(self.owner);
}

@end

%group ReelsSwipeToProfileGroup

%hook IGSundialFeedViewController

- (void)viewDidLoad {
	%orig;

	if (!sciReelsSwipeEnabled()) return;
	if (objc_getAssociatedObject(self, &kSCIReelsSwipePanKey)) return;

	SCIReelsSwipeToProfileDelegate *delegate = [SCIReelsSwipeToProfileDelegate new];
	delegate.owner = self;

	UIPanGestureRecognizer *pan = [[UIPanGestureRecognizer alloc] initWithTarget:delegate action:@selector(handle:)];
	pan.delegate = delegate;
	pan.maximumNumberOfTouches = 1;

	delegate.pan = pan;
	[self.view addGestureRecognizer:pan];

	objc_setAssociatedObject(self, &kSCIReelsSwipePanKey, delegate, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
}

- (void)viewDidAppear:(BOOL)animated {
	%orig;

	SCIReelsSwipeToProfileDelegate *delegate = objc_getAssociatedObject(self, &kSCIReelsSwipePanKey);
	if (!delegate.pan || delegate.coupled) return;

	sciCoupleParentPanRecognizers(self.view, delegate.pan);
	delegate.coupled = YES;
}

%end

%end

%ctor {
	if (sciReelsSwipeEnabled()) {
		%init(ReelsSwipeToProfileGroup);
	}
}