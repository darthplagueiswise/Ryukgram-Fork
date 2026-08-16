#import "../../Utils.h"
#import <objc/runtime.h>
#import <objc/message.h>
#import <substrate.h>

// Hides IGPillButtons labelled "Made with Edits" / "Use template", plus the
// feed-post attribution row. configureWithViewModel: fires once per pill setup,
// not per layout — cheaper hook point than a layout pass.

static const void *kRYGPillEditsHideKey = &kRYGPillEditsHideKey;

static UILabel *rygFindFirstNonEmptyLabel(UIView *root, int depth) {
    if (!root || depth > 4) return nil;
    if ([root isKindOfClass:[UILabel class]] && ((UILabel *)root).text.length) return (UILabel *)root;
    for (UIView *sub in root.subviews) {
        UILabel *hit = rygFindFirstNonEmptyLabel(sub, depth + 1);
        if (hit) return hit;
    }
    return nil;
}

static NSString *rygPillText(UIView *pill) {
    @try {
        Ivar iv = class_getInstanceVariable([pill class], "_lazyTitleLabel");
        if (iv) {
            id v = object_getIvar(pill, iv);
            if ([v isKindOfClass:[UILabel class]] && ((UILabel *)v).text.length) return ((UILabel *)v).text;
        }
    } @catch (__unused id e) {}
    return rygFindFirstNonEmptyLabel(pill, 0).text;
}

static BOOL rygTextShouldHidePill(NSString *txt) {
    if (!txt.length) return NO;
    return [txt rangeOfString:@"edits" options:NSCaseInsensitiveSearch].location != NSNotFound ||
           [txt rangeOfString:@"template" options:NSCaseInsensitiveSearch].location != NSNotFound;
}

static void rygCollapseView(UIView *v) {
    v.hidden = YES;
    v.alpha = 0;
    CGRect f = v.frame; f.size = CGSizeZero; v.frame = f;
}

%hook IGPillButton

// Block re-show after we've hidden a flagged pill.
- (void)setHidden:(BOOL)hidden {
    if (!hidden && objc_getAssociatedObject((id)self, kRYGPillEditsHideKey)) {
        %orig(YES);
        return;
    }
    %orig(hidden);
}

%end

static void (*orig_IGPillButton_configureWithViewModel)(id, SEL, id);
static void new_IGPillButton_configureWithViewModel(id self, SEL _cmd, id model) {
    orig_IGPillButton_configureWithViewModel(self, _cmd, model);
    if (![RYGUtils getBoolPref:@"hide_made_with_edits"]) return;
    UIView *pill = (UIView *)self;
    if (!rygTextShouldHidePill(rygPillText(pill))) return;
    objc_setAssociatedObject(pill, kRYGPillEditsHideKey, @YES, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    rygCollapseView(pill);
    [pill removeFromSuperview];
}

// Feed-post attribution row. The controller exposes its view under the
// ivar-named KVC key `madeWithEditsAttributionView`, not a generic
// `attributionView` — try the specific keys first, then fall back to the
// controller's own view.
typedef void (*ryg_configureView_t)(id, SEL);
static ryg_configureView_t orig_attribution_configureView[2];

static void ryg_run_attribution(id self, SEL _cmd, NSUInteger idx) {
    if (orig_attribution_configureView[idx]) orig_attribution_configureView[idx](self, _cmd);
    if (![RYGUtils getBoolPref:@"hide_made_with_edits"]) return;
    UIView *v = nil;
    for (NSString *key in @[@"madeWithEditsAttributionView", @"attributionView", @"templatesAttributionView"]) {
        @try { id cand = [(NSObject *)self valueForKey:key];
               if ([cand isKindOfClass:[UIView class]]) { v = cand; break; } }
        @catch (__unused id e) {}
    }
    if (!v && [self respondsToSelector:@selector(view)]) {
        id cv = ((id (*)(id, SEL))objc_msgSend)(self, @selector(view));
        if ([cv isKindOfClass:[UIView class]]) v = cv;
    }
    if (v) rygCollapseView(v);
}

static void new_attribution_configureView_0(id self, SEL _cmd) { ryg_run_attribution(self, _cmd, 0); }
static void new_attribution_configureView_1(id self, SEL _cmd) { ryg_run_attribution(self, _cmd, 1); }

static void rygHookAttributionController(NSString *mangled, NSUInteger idx) {
    static IMP imps[2] = { (IMP)new_attribution_configureView_0, (IMP)new_attribution_configureView_1 };
    Class cls = objc_getClass(mangled.UTF8String);
    if (cls && class_getInstanceMethod(cls, @selector(configureView))) {
        MSHookMessageEx(cls, @selector(configureView), imps[idx], (IMP *)&orig_attribution_configureView[idx]);
    }
}

%ctor {
    Class cls = objc_getClass("IGPillButton");
    SEL sel = @selector(configureWithViewModel:);
    if (cls && class_getInstanceMethod(cls, sel)) {
        MSHookMessageEx(cls, sel,
                        (IMP)new_IGPillButton_configureWithViewModel,
                        (IMP *)&orig_IGPillButton_configureWithViewModel);
    }

    rygHookAttributionController(@"_TtC24IGFeedItemAttributionKit40IGFeedItemTemplatesAttributionController", 0);
    rygHookAttributionController(@"_TtC24IGFeedItemAttributionKit44IGFeedItemMadeWithEditsAttributionController", 1);
}
