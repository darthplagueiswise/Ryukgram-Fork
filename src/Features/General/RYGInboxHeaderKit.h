// Shared placement for RYGChromeButtons parented to IG's inbox nav header, so
// every injected header button centers off one native reference.

#import <UIKit/UIKit.h>
#import "../../RYGChrome.h"

static inline UIView *RYGInboxHeaderView(UIView *root) {
    if (!root) return nil;
    if ([NSStringFromClass([root class]) containsString:@"NavigationHeaderView"]) return root;
    for (UIView *sub in root.subviews) {
        UIView *r = RYGInboxHeaderView(sub);
        if (r) return r;
    }
    return nil;
}

// Native UIButtons in the header's right third, left→right. Skips our own chrome
// buttons; keeps hidden/fading ones so the collapse mirror tracks them to alpha 0.
static inline NSArray<UIView *> *RYGInboxTrailingButtons(UIView *header) {
    NSMutableArray<UIView *> *out = [NSMutableArray array];
    NSMutableArray *stack = [NSMutableArray arrayWithObject:header];
    while (stack.count) {
        UIView *v = stack.lastObject;
        [stack removeLastObject];
        for (UIView *s in v.subviews) [stack addObject:s];
        if (v == header || [v isKindOfClass:[RYGChromeButton class]]) continue;
        if (![v isKindOfClass:[UIButton class]] || CGRectIsEmpty(v.bounds)) continue;
        if (CGRectGetMinX([v convertRect:v.bounds toView:header]) <= header.bounds.size.width * 0.6) continue;
        [out addObject:v];
    }
    [out sortUsingComparator:^NSComparisonResult(UIView *a, UIView *b) {
        CGFloat xa = CGRectGetMinX([a convertRect:a.bounds toView:header]);
        CGFloat xb = CGRectGetMinX([b convertRect:b.bounds toView:header]);
        return xa < xb ? NSOrderedAscending : (xa > xb ? NSOrderedDescending : NSOrderedSame);
    }];
    return out;
}

// Rightmost native trailing button — the row every injected button centers on.
static inline UIView *RYGInboxRowRef(UIView *header) {
    return RYGInboxTrailingButtons(header).lastObject;
}

static inline CGFloat RYGInboxRowTop(UIView *header, UIView *ref, CGFloat side) {
    if (ref) return CGRectGetMidY([ref convertRect:ref.bounds toView:header]) - side * 0.5;
    return (header.bounds.size.height - side) * 0.5;
}

// Match a reference button's effective alpha + hidden so injected buttons follow
// IG's scroll-collapse.
static inline void RYGInboxMirrorChrome(UIView *btn, UIView *ref, UIView *header) {
    if (!ref) { btn.alpha = 1.0; btn.hidden = NO; return; }
    CGFloat eff = 1.0;
    BOOL hidden = NO;
    for (UIView *v = ref; v && v != header; v = v.superview) {
        if (v.hidden) hidden = YES;
        eff *= v.alpha;
    }
    btn.alpha = eff;
    btn.hidden = hidden;
}
