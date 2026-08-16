// Make the DM thread header honest. IG's "Active now" + green dot is built by sealed
// Swift with no hookable getter, so we drive the ObjC title view off our own presence:
// when the recipient is offline, rewrite the subtitle to "Active … ago" and hide the dot.

#import "RYGActivityEngine.h"
#import "../../Utils.h"
#import <objc/runtime.h>
#import <objc/message.h>

static __weak UIView *sCurrentTitleView;
static const void *kDotHiddenKey = &kDotHiddenKey;

static id ahCall(id o, SEL s) { return (o && [o respondsToSelector:s]) ? ((id (*)(id, SEL))objc_msgSend)(o, s) : nil; }
static id ahIvar(id o, const char *n) { Ivar iv = o ? class_getInstanceVariable([o class], n) : NULL; return iv ? object_getIvar(o, iv) : nil; }

// The header active-now dot is a small green IGGradientView (corner ~5). Hide just
// that view when offline (leaves the avatar notch behind — accepted).
static void ahSetDotHidden(UIView *root, BOOL hidden) {
    if (!root) return;
    NSMutableArray *stack = [NSMutableArray arrayWithObject:root];
    while (stack.count) {
        UIView *v = stack.lastObject; [stack removeLastObject];
        for (UIView *s in v.subviews) [stack addObject:s];
        if (v == root || ![NSStringFromClass([v class]) containsString:@"GradientView"]) continue;
        CGFloat cr = v.layer.cornerRadius;
        if (cr < 2 || cr > 9) continue;                 // small circle = the dot
        UIColor *bg = v.backgroundColor; if (!bg) continue;
        CGFloat r = 0, g = 0, b = 0, a = 0;
        if (![bg getRed:&r green:&g blue:&b alpha:&a] || a < 0.3 || !(g > 0.4 && g > r && g > b)) continue;
        if (hidden) {
            if (!v.hidden) { objc_setAssociatedObject(v, kDotHiddenKey, @YES, OBJC_ASSOCIATION_RETAIN_NONATOMIC); v.hidden = YES; }
        } else if ([objc_getAssociatedObject(v, kDotHiddenKey) boolValue]) {
            v.hidden = NO; objc_setAssociatedObject(v, kDotHiddenKey, nil, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        }
    }
}

static id ahViewModel(UIView *tv) {
    id sp = ahIvar(ahCall(tv, @selector(delegate)), "_stateProvider");
    return ahCall(sp, @selector(viewModel));
}
static NSDate *ahLastActive(UIView *tv) {
    id vm = ahViewModel(tv);
    if (!vm) return nil;
    @try { id v = [vm valueForKey:@"lastActiveTime"]; if ([v isKindOfClass:NSDate.class]) return v; } @catch (__unused id e) {}
    return nil;
}


static NSString *ahOfflineText(NSDate *la) {
    if ([RYGUtils getBoolPref:@"dm_full_last_active"]) {
        // match FullLastActive's bare-date output exactly so both-on doesn't flicker
        static NSDateFormatter *df; static dispatch_once_t o;
        dispatch_once(&o, ^{ df = [NSDateFormatter new]; df.dateFormat = @"MMM d 'at' h:mm a"; });
        return [df stringFromDate:la];
    }
    long m = (long)(-[la timeIntervalSinceNow] / 60.0);
    if (m < 1) m = 1;
    if (m < 60) return [NSString stringWithFormat:RYGLocalized(@"Active %ldm ago"), m];
    long h = m / 60;
    if (h < 24) return [NSString stringWithFormat:RYGLocalized(@"Active %ldh ago"), h];
    return [NSString stringWithFormat:RYGLocalized(@"Active %ldd ago"), h / 24];
}

static void ahApply(UIView *tv) {
    if (!tv) return;
    if (![RYGUtils getBoolPref:@"activity_fast_presence"]) return;
    NSDate *la = ahLastActive(tv);
    if (!la) return;                      // group thread / no presence subtitle
    // Correlate this header's recipient by its last-active timestamp; fall back to
    // freshness if the engine hasn't stamped a matching ms yet.
    int st = [RYGActivityEngine presenceForLastActiveMs:la.timeIntervalSince1970 * 1000.0];
    if (st < 0) st = (-[la timeIntervalSinceNow] > 60.0) ? 0 : 1;
    ahSetDotHidden(tv, st == 0);          // hide the green dot when offline (notch shows through)
    if (st != 0) return;                  // active -> leave IG's "Active now"
    id sub = ahCall(tv, @selector(_currentSubtitleViewModel));
    if (!sub) return;
    @try {
        id cur = [sub valueForKey:@"text"];
        if (![cur isKindOfClass:NSAttributedString.class]) return;
        NSAttributedString *attr = cur;
        NSString *plain = attr.string.lowercaseString;
        // only touch the presence subtitle (leave typing / other subtitles alone)
        BOOL presence = [plain containsString:@"active"] || [plain containsString:@"ago"] || [plain containsString:@"now"];
        if (!presence) return;
        NSString *want = ahOfflineText(la);
        if ([attr.string isEqualToString:want]) return; // already showing it — no churn
        NSDictionary *a = attr.length ? [attr attributesAtIndex:0 effectiveRange:NULL] : nil;
        NSAttributedString *ns = [[NSAttributedString alloc] initWithString:want attributes:a];
        [sub setValue:ns forKey:@"text"];
        Ivar lv = class_getInstanceVariable([tv class], "_subtitleLabel");
        UILabel *lbl = lv ? object_getIvar(tv, lv) : nil;
        if ([lbl isKindOfClass:UILabel.class]) lbl.attributedText = ns;
    } @catch (__unused id e) {}
}

%group ActivityHeader
%hook IGDirectLeftAlignedTitleView
- (void)layoutSubviews {
    %orig;
    sCurrentTitleView = self;
    ahApply(self);
}
- (void)setTitleViewModel:(id)vm {
    %orig;
    sCurrentTitleView = self;
    ahApply(self);
}
%end
%end

%ctor {
    if (![RYGUtils getBoolPref:@"activity_fast_presence"]) return;
    %init(ActivityHeader);
    [NSNotificationCenter.defaultCenter addObserverForName:RYGActivityPresenceDidChangeNotification object:nil queue:NSOperationQueue.mainQueue usingBlock:^(NSNotification *n) {
        UIView *tv = sCurrentTitleView;
        if (tv) ahApply(tv);
    }];
    // Re-apply on a short cadence so the freshness fallback flips without a layout pass.
    dispatch_source_t t = dispatch_source_create(DISPATCH_SOURCE_TYPE_TIMER, 0, 0, dispatch_get_main_queue());
    dispatch_source_set_timer(t, dispatch_time(DISPATCH_TIME_NOW, (int64_t)(8 * NSEC_PER_SEC)), (uint64_t)(8 * NSEC_PER_SEC), (uint64_t)(2 * NSEC_PER_SEC));
    dispatch_source_set_event_handler(t, ^{ UIView *tv = sCurrentTitleView; if (tv && tv.window) ahApply(tv); });
    dispatch_resume(t);
}
