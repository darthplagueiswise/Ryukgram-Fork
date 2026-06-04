#import "../../Utils.h"
#import "../../InstagramHeaders.h"
#import <objc/runtime.h>

// Swipe a reel left → open the author's profile via IG's own header tap so
// the back gesture returns to the reel. Single-author uses
// IGUnifiedVideoUserButton; collab uses IGCoreTextView's URL-attributed
// span routed through the coauthor view's link delegate.

static char kSCIReelsSwipePanKey;
static const CGFloat kSCIReelsSwipeBottomIgnore = 140.0;
static const NSTimeInterval kSCIReelsSwipeMaxDuration = 0.40;

static UIView *sciDeepFindByClassName(UIView *root, NSString *name) {
    if (!root) return nil;
    if ([NSStringFromClass([root class]) isEqualToString:name]) return root;
    for (UIView *sub in root.subviews) {
        UIView *hit = sciDeepFindByClassName(sub, name);
        if (hit) return hit;
    }
    return nil;
}

static UIView *sciCurrentReelCell(UIViewController *sundialVC) {
    SEL sels[] = {
        @selector(currentViewCell),
        @selector(swift__currentVideoCell),
        @selector(currentAdCell),
    };
    for (size_t i = 0; i < sizeof(sels)/sizeof(sels[0]); i++) {
        if ([sundialVC respondsToSelector:sels[i]]) {
            id v = ((id(*)(id, SEL))objc_msgSend)(sundialVC, sels[i]);
            if ([v isKindOfClass:[UIView class]]) return v;
        }
    }
    return nil;
}

// Collab reels: IGCoreTextView's _styledString holds a NSAttributedString
// with `URL` spans per author; the coauthor view implements
// coreTextView:didTapOnString:URL: which pushes via IG's nav.
static BOOL sciTryCoauthorLinkTap(UIView *cell) {
    UIView *attrib = sciDeepFindByClassName(cell, @"IGSundialViewerUserAttributionSwift.IGSundialViewerCoauthorUserTextAttributionView");
    if (!attrib) return NO;
    UIView *core = sciDeepFindByClassName(attrib, @"IGCoreTextView");
    if (!core) return NO;
    Ivar sIv = class_getInstanceVariable([core class], "_styledString");
    id styled = sIv ? object_getIvar(core, sIv) : nil;
    if (!styled) return NO;
    Ivar aIv = class_getInstanceVariable([styled class], "_attributedString");
    id rawAS = aIv ? object_getIvar(styled, aIv) : nil;
    if (![rawAS isKindOfClass:[NSAttributedString class]]) return NO;
    NSAttributedString *as = rawAS;
    __block NSURL *url = nil;
    __block NSString *tappedStr = nil;
    [as enumerateAttribute:@"URL" inRange:NSMakeRange(0, as.length) options:0 usingBlock:^(id value, NSRange range, BOOL *stop) {
        if (!value) return;
        if ([value isKindOfClass:[NSURL class]]) url = value;
        else if ([value isKindOfClass:[NSString class]]) url = [NSURL URLWithString:value];
        if (url) {
            tappedStr = [as.string substringWithRange:range];
            *stop = YES;
        }
    }];
    if (!url) return NO;
    SEL sel = @selector(coreTextView:didTapOnString:URL:);
    if (![attrib respondsToSelector:sel]) return NO;
    ((void(*)(id, SEL, id, id, id))objc_msgSend)(attrib, sel, core, tappedStr, url);
    return YES;
}

// Single-author reels: IGUnifiedVideoUserButton owns a UITapGestureRecognizer
// wired to its own _handleSingleTap: which pushes via IG's nav.
static BOOL sciTryHeaderButtonTap(UIView *cell) {
    UIView *button = sciDeepFindByClassName(cell, @"IGUnifiedVideoUserButton");
    if (!button) return NO;
    SEL handleTap = NSSelectorFromString(@"_handleSingleTap:");
    if (![button respondsToSelector:handleTap]) return NO;
    UITapGestureRecognizer *gr = nil;
    for (UIGestureRecognizer *g in button.gestureRecognizers) {
        if ([g isKindOfClass:[UITapGestureRecognizer class]]) { gr = (UITapGestureRecognizer *)g; break; }
    }
    if (!gr) return NO;
    ((void(*)(id, SEL, id))objc_msgSend)(button, handleTap, gr);
    return YES;
}

static BOOL sciTriggerHeaderUsernameTap(UIViewController *sundialVC) {
    UIView *cell = sciCurrentReelCell(sundialVC);
    if (!cell) return NO;
    if (sciTryHeaderButtonTap(cell)) return YES;
    if (sciTryCoauthorLinkTap(cell)) return YES;
    return NO;
}

// Carousel reels (`IGSundialViewerCarouselCell` - don't hijack it.
static BOOL sciCurrentReelIsCarousel(UIViewController *sundialVC) {
    UIView *cell = sciCurrentReelCell(sundialVC);
    if (!cell) return NO;
    if ([NSStringFromClass([cell class]) containsString:@"Carousel"]) return YES;
    return sciDeepFindByClassName(cell, @"IGSundialViewerCarouselCell") != nil;
}

// Failure-couple ancestor pans so a leftward flick wins on the reel and
// other directions still page tabs / scroll.
static void sciCoupleParentPanRecognizers(UIView *startView, UIPanGestureRecognizer *ourPan) {
    UIView *v = startView.superview;
    int hops = 0;
    while (v && hops++ < 20) {
        for (UIGestureRecognizer *gr in v.gestureRecognizers) {
            if (gr != ourPan && [gr isKindOfClass:[UIPanGestureRecognizer class]]) {
                [gr requireGestureRecognizerToFail:ourPan];
            }
        }
        if ([v isKindOfClass:[UIScrollView class]]) {
            UIPanGestureRecognizer *sp = ((UIScrollView *)v).panGestureRecognizer;
            if (sp && sp != ourPan) [sp requireGestureRecognizerToFail:ourPan];
        }
        v = v.superview;
    }
}

@interface SCIReelsSwipeToProfileDelegate : NSObject <UIGestureRecognizerDelegate>
@property (nonatomic, weak) UIViewController *owner;
@property (nonatomic, weak) UIPanGestureRecognizer *pan;
@property (nonatomic, assign) NSTimeInterval startTime;
@end

@implementation SCIReelsSwipeToProfileDelegate

- (BOOL)gestureRecognizerShouldBegin:(UIPanGestureRecognizer *)gr {
    if (![SCIUtils getBoolPref:@"reels_swipe_to_profile"]) return NO;
    CGPoint v = [gr velocityInView:gr.view];
    if (!(fabs(v.x) > fabs(v.y) * 1.2 && v.x < 0)) return NO;
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
    CGPoint t = [gr translationInView:gr.view];
    CGPoint v = [gr velocityInView:gr.view];
    if (!(t.x < -60 || v.x < -400)) return;
    if (fabs(t.x) < fabs(t.y) * 1.2) return;
    UIViewController *vc = self.owner;
    if (!vc) return;
    sciTriggerHeaderUsernameTap(vc);
}

@end

%hook IGSundialFeedViewController

- (void)viewDidLoad {
    %orig;
    if (objc_getAssociatedObject(self, &kSCIReelsSwipePanKey)) return;
    SCIReelsSwipeToProfileDelegate *d = [[SCIReelsSwipeToProfileDelegate alloc] init];
    d.owner = self;
    UIPanGestureRecognizer *pan = [[UIPanGestureRecognizer alloc] initWithTarget:d action:@selector(handle:)];
    pan.delegate = d;
    pan.maximumNumberOfTouches = 1;
    d.pan = pan;
    [self.view addGestureRecognizer:pan];
    objc_setAssociatedObject(self, &kSCIReelsSwipePanKey, d, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
}

- (void)viewDidAppear:(BOOL)animated {
    %orig;
    SCIReelsSwipeToProfileDelegate *d = objc_getAssociatedObject(self, &kSCIReelsSwipePanKey);
    if (d.pan) sciCoupleParentPanRecognizers(self.view, d.pan);
}

%end
