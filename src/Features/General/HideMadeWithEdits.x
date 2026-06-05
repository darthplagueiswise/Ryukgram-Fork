#import "../../Utils.h"
#import <objc/runtime.h>
#import <substrate.h>

// Hides any IGPillButton whose text mentions "Edits" — Made with Edits,
// Open in Edits, etc. Hooks IGPillButton's `configureWithViewModel:`
// (resolved at %ctor) so it fires once per pill setup, not per layout.

static const void *kSCIPillEditsHideKey = &kSCIPillEditsHideKey;

static UILabel *sciFindFirstNonEmptyLabel(UIView *root, int depth) {
    if (!root || depth > 4) return nil;
    if ([root isKindOfClass:[UILabel class]] && ((UILabel *)root).text.length) return (UILabel *)root;
    for (UIView *sub in root.subviews) {
        UILabel *hit = sciFindFirstNonEmptyLabel(sub, depth + 1);
        if (hit) return hit;
    }
    return nil;
}

static NSString *sciPillText(UIView *pill) {
    @try {
        Ivar iv = class_getInstanceVariable([pill class], "_lazyTitleLabel");
        if (iv) {
            id v = object_getIvar(pill, iv);
            if ([v isKindOfClass:[UILabel class]] && ((UILabel *)v).text.length) return ((UILabel *)v).text;
        }
    } @catch (__unused id e) {}
    return sciFindFirstNonEmptyLabel(pill, 0).text;
}

static BOOL sciTextIsEdits(NSString *txt) {
    return txt.length && [txt rangeOfString:@"edits" options:NSCaseInsensitiveSearch].location != NSNotFound;
}

%hook IGPillButton

// Block re-show after we've hidden a flagged pill.
- (void)setHidden:(BOOL)hidden {
    if (!hidden && objc_getAssociatedObject((id)self, kSCIPillEditsHideKey)) {
        %orig(YES);
        return;
    }
    %orig(hidden);
}

%end

static void (*orig_IGPillButton_configureWithViewModel)(id, SEL, id);
static void new_IGPillButton_configureWithViewModel(id self, SEL _cmd, id model) {
    orig_IGPillButton_configureWithViewModel(self, _cmd, model);
    if (![SCIUtils getBoolPref:@"hide_made_with_edits"]) return;
    UIView *pill = (UIView *)self;
    if (!sciTextIsEdits(sciPillText(pill))) return;
    objc_setAssociatedObject(pill, kSCIPillEditsHideKey, @YES, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    pill.hidden = YES;
    pill.alpha = 0;
    CGRect f = pill.frame; f.size = CGSizeZero; pill.frame = f;
    [pill removeFromSuperview];
}

%ctor {
    Class cls = objc_getClass("IGPillButton");
    SEL sel = @selector(configureWithViewModel:);
    if (cls && class_getInstanceMethod(cls, sel)) {
        MSHookMessageEx(cls, sel,
                        (IMP)new_IGPillButton_configureWithViewModel,
                        (IMP *)&orig_IGPillButton_configureWithViewModel);
    }
}

// Feed-post "Made with Edits" attribution row.
%hook _TtC24IGFeedItemAttributionKit44IGFeedItemMadeWithEditsAttributionController

- (void)configureView {
    %orig;
    if (![SCIUtils getBoolPref:@"hide_made_with_edits"]) return;
    UIView *v = [(NSObject *)self valueForKey:@"attributionView"];
    if ([v isKindOfClass:[UIView class]]) {
        v.hidden = YES;
        CGRect f = v.frame; f.size.height = 0; v.frame = f;
    }
}

%end
