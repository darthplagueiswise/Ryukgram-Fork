#import "RYGURLOpener.h"

// IG post shortcode -> numeric media pk (base64 over IG's alphabet). Lets us open a
// post link via instagram://media?id=, which surfaces the dedicated viewer instead of
// routing through the home tab (which the grid overlay covers).
static NSString *rygMediaIDFromShortcode(NSString *code) {
	static NSString *const alphabet = @"ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-_";
	if (!code.length) return nil;
	unsigned long long value = 0;
	for (NSUInteger i = 0; i < code.length; i++) {
		NSRange r = [alphabet rangeOfString:[code substringWithRange:NSMakeRange(i, 1)]];
		if (r.location == NSNotFound) return nil;
		value = value * 64 + (unsigned long long)r.location;
	}
	return value ? [@(value) stringValue] : nil;
}

static NSString *rygShortcodeFromIGURL(NSURL *url) {
	NSArray<NSString *> *parts = url.pathComponents;
	NSSet *markers = [NSSet setWithArray:@[@"p", @"reel", @"reels", @"tv"]];
	for (NSUInteger i = 0; i + 1 < parts.count; i++) {
		if ([markers containsObject:parts[i]] && [parts[i + 1] length]) return parts[i + 1];
	}
	return nil;
}

@implementation RYGURLOpener

+ (BOOL)isInstagramHost:(NSString *)host {
	if (!host.length) return NO;
	NSString *h = host.lowercaseString;
	return [h isEqualToString:@"instagram.com"]
		|| [h hasSuffix:@".instagram.com"]
		|| [h isEqualToString:@"instagr.am"]
		|| [h isEqualToString:@"ig.me"];
}

// IG / FB outbound redirectors wrap the real destination in `?u=<URL>`.
+ (NSURL *)unwrapRedirector:(NSURL *)url {
	NSString *h = url.host.lowercaseString;
	if (![h isEqualToString:@"l.instagram.com"]
		&& ![h isEqualToString:@"l.facebook.com"]
		&& ![h isEqualToString:@"lm.facebook.com"]) return url;
	NSURLComponents *comps = [NSURLComponents componentsWithURL:url resolvingAgainstBaseURL:NO];
	for (NSURLQueryItem *q in comps.queryItems) {
		if ([q.name isEqualToString:@"u"] && q.value.length) {
			NSURL *real = [NSURL URLWithString:q.value];
			if (real) return real;
		}
	}
	return url;
}

+ (BOOL)openURL:(NSURL *)url {
	if (!url) return NO;
	url = [self unwrapRedirector:url];

	UIApplication *app = [UIApplication sharedApplication];
	id<UIApplicationDelegate> delegate = app.delegate;
	NSString *scheme = url.scheme.lowercaseString;

	if ([scheme isEqualToString:@"instagram"]) {
		if ([delegate respondsToSelector:@selector(application:openURL:options:)]) {
			[delegate application:app openURL:url options:@{}];
			return YES;
		}
		[app openURL:url options:@{} completionHandler:nil];
		return YES;
	}

	if (([scheme isEqualToString:@"http"] || [scheme isEqualToString:@"https"])
		&& [self isInstagramHost:url.host]) {
		// Post links open in the dedicated media viewer (survives the grid overlay).
		NSString *pk = rygMediaIDFromShortcode(rygShortcodeFromIGURL(url));
		if (pk.length && [delegate respondsToSelector:@selector(application:openURL:options:)]) {
			NSURL *appURL = [NSURL URLWithString:[NSString stringWithFormat:@"instagram://media?id=%@", pk]];
			if (appURL) { [delegate application:app openURL:appURL options:@{}]; return YES; }
		}
		NSUserActivity *activity = [[NSUserActivity alloc] initWithActivityType:NSUserActivityTypeBrowsingWeb];
		activity.webpageURL = url;
		SEL contSel = @selector(application:continueUserActivity:restorationHandler:);
		if ([delegate respondsToSelector:contSel]) {
			BOOL handled = [delegate application:app
							continueUserActivity:activity
							  restorationHandler:^(NSArray<id<UIUserActivityRestoring>> *_Nullable _) {}];
			if (handled) return YES;
		}
		if ([delegate respondsToSelector:@selector(application:openURL:options:)]) {
			[delegate application:app openURL:url options:@{}];
			return YES;
		}
	}

	[app openURL:url options:@{} completionHandler:nil];
	return YES;
}

+ (BOOL)openURLString:(NSString *)urlString {
	if (!urlString.length) return NO;
	return [self openURL:[NSURL URLWithString:urlString]];
}

+ (BOOL)dismiss:(UIViewController *)presenter thenOpenURL:(NSURL *)url {
	if (!url) return NO;
	// A non-VC presenter (e.g. a UIView) would crash on -presentingViewController.
	UIViewController *root = [presenter isKindOfClass:UIViewController.class] ? presenter : nil;
	while (root.presentingViewController) root = root.presentingViewController;
	void (^open)(void) = ^{ [self openURL:url]; };
	if (root && root != presenter) {
		[root dismissViewControllerAnimated:YES completion:open];
		return YES;
	}
	open();
	return YES;
}

+ (NSURL *)profileURLForUsername:(NSString *)username {
	if (!username.length) return nil;
	NSString *enc = [username stringByAddingPercentEncodingWithAllowedCharacters:[NSCharacterSet URLQueryAllowedCharacterSet]];
	if (!enc.length) return nil;
	NSURL *appURL = [NSURL URLWithString:[NSString stringWithFormat:@"instagram://user?username=%@", enc]];
	if (appURL && [[UIApplication sharedApplication] canOpenURL:appURL]) return appURL;
	return [NSURL URLWithString:[NSString stringWithFormat:@"https://www.instagram.com/%@/", enc]];
}

+ (BOOL)openInstagramProfileForUsername:(NSString *)username {
	NSURL *url = [self profileURLForUsername:username];
	return url ? [self openURL:url] : NO;
}

+ (BOOL)dismiss:(UIViewController *)presenter thenOpenInstagramProfileForUsername:(NSString *)username {
	NSURL *url = [self profileURLForUsername:username];
	return url ? [self dismiss:presenter thenOpenURL:url] : NO;
}

@end
