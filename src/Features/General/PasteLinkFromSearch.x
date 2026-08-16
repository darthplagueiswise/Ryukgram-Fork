// Long-press the Explore/search tab to open an IG link from the clipboard.

#import "../../Utils.h"
#import "../../RYGURLOpener.h"
#import "../../InstagramHeaders.h"
#import <objc/runtime.h>

static const void *kPasteGestureKey = &kPasteGestureKey;

// Parse the clipboard string into a URL IG will recognize. Accepts bare
// hostnames, canonical IG hosts, and fix-embed mirrors (any host with
// "instagram" in it — ddinstagram, eeinstagram, vxinstagram, etc.) which
// get rewritten to www.instagram.com.
static NSURL *rygNormalizeIGURL(NSString *raw) {
    if (!raw.length) return nil;
    raw = [raw stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
    if (![raw containsString:@"://"]) raw = [@"https://" stringByAppendingString:raw];

    NSURL *url = [NSURL URLWithString:raw];
    NSString *scheme = url.scheme.lowercaseString;
    if ([scheme isEqualToString:@"instagram"]) return url;
    if (![scheme isEqualToString:@"http"] && ![scheme isEqualToString:@"https"]) return nil;

    NSString *host = url.host.lowercaseString;
    if (!host.length) return nil;

    if ([host isEqualToString:@"instagram.com"]
        || [host hasSuffix:@".instagram.com"]
        || [host isEqualToString:@"instagr.am"]
        || [host isEqualToString:@"ig.me"]) {
        return url;
    }

    if ([host containsString:@"instagram"]) {
        NSURLComponents *comps = [NSURLComponents componentsWithURL:url resolvingAgainstBaseURL:NO];
        comps.scheme = @"https";
        comps.host = @"www.instagram.com";
        return comps.URL;
    }

    return nil;
}

@interface RYGPasteLinkHandler : NSObject <UIGestureRecognizerDelegate>
+ (instancetype)shared;
- (void)longPressed:(UILongPressGestureRecognizer *)g;
@end

@implementation RYGPasteLinkHandler
+ (instancetype)shared {
    static RYGPasteLinkHandler *s;
    static dispatch_once_t once;
    dispatch_once(&once, ^{ s = [RYGPasteLinkHandler new]; });
    return s;
}

// Gate the gesture on the pref. When off, IG's default long-press falls through.
- (BOOL)gestureRecognizerShouldBegin:(UIGestureRecognizer *)g {
    return [RYGUtils getBoolPref:@"paste_link_from_search"];
}

- (void)longPressed:(UILongPressGestureRecognizer *)g {
    if (g.state != UIGestureRecognizerStateBegan) return;

    NSURL *url = rygNormalizeIGURL([[UIPasteboard generalPasteboard] string]);
    if (!url) {
        RYGNotifyWarning(RYG_NOTIF_PASTE_LINK_INVALID, RYGLocalized(@"Clipboard is not an Instagram URL"), nil);
        return;
    }
    [RYGURLOpener openURL:url];
}
@end

static void rygAttachPasteGesture(UIButton *btn) {
    if (!btn || objc_getAssociatedObject(btn, kPasteGestureKey)) return;
    RYGPasteLinkHandler *handler = [RYGPasteLinkHandler shared];
    UILongPressGestureRecognizer *g = [[UILongPressGestureRecognizer alloc]
        initWithTarget:handler action:@selector(longPressed:)];
    g.minimumPressDuration = 0.5;
    g.delegate = handler;
    // Cancel the tap so IG's tab-tap doesn't fire after and clobber our nav.
    g.cancelsTouchesInView = YES;
    [btn addGestureRecognizer:g];
    objc_setAssociatedObject(btn, kPasteGestureKey, g, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
}

%hook IGTabBarController
- (void)viewDidLayoutSubviews {
    %orig;
    Ivar iv = class_getInstanceVariable([self class], "_exploreButton");
    if (!iv) return;
    id btn = object_getIvar(self, iv);
    if ([btn isKindOfClass:[UIButton class]]) rygAttachPasteGesture(btn);
}
%end
