// Open links in external browser + strip IG tracking from URLs
#import "../../Utils.h"
#import <objc/runtime.h>
#import <objc/message.h>

// Extract the real URL from l.instagram.com redirects and strip tracking params
static NSURL *rygCleanBrowserURL(NSURL *url) {
    if (![RYGUtils getBoolPref:@"strip_browser_tracking"]) return url;
    if (!url) return url;

    NSString *urlStr = url.absoluteString;

    // Unwrap l.instagram.com/?u=ENCODED_URL&e=TRACKING redirects
    if ([url.host isEqualToString:@"l.instagram.com"]) {
        NSURLComponents *comps = [NSURLComponents componentsWithURL:url resolvingAgainstBaseURL:NO];
        for (NSURLQueryItem *q in comps.queryItems) {
            if ([q.name isEqualToString:@"u"] && q.value.length) {
                NSString *decoded = [q.value stringByRemovingPercentEncoding];
                if (decoded) urlStr = decoded;
                break;
            }
        }
    }

    NSURL *result = [NSURL URLWithString:[RYGUtils stripTrackingParams:urlStr]];
    return result ?: url;
}

%hook IGBrowserNavigationController
- (void)viewWillAppear:(BOOL)animated {
    id session = ((id(*)(id,SEL))objc_msgSend)(self, @selector(browserSession));
    Ivar urlIvar = session ? class_getInstanceVariable([session class], "_urlRequest") : nil;
    NSURLRequest *req = urlIvar ? object_getIvar(session, urlIvar) : nil;
    NSURL *url = req.URL;

    if (url && [RYGUtils getBoolPref:@"open_links_external"]) {
        NSURL *cleaned = rygCleanBrowserURL(url);
        [[UIApplication sharedApplication] openURL:cleaned options:@{} completionHandler:nil];
        [(UIViewController *)self dismissViewControllerAnimated:NO completion:nil];
        return;
    }

    // For in-app browser: replace the URL request with the cleaned version
    if (url && [RYGUtils getBoolPref:@"strip_browser_tracking"]) {
        NSURL *cleaned = rygCleanBrowserURL(url);
        if (![cleaned isEqual:url]) {
            NSURLRequest *cleanReq = [NSURLRequest requestWithURL:cleaned];
            object_setIvar(session, urlIvar, cleanReq);
        }
    }

    %orig;
}
%end
