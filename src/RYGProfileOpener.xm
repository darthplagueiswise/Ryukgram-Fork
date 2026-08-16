#import "RYGProfileOpener.h"
#import "RYGURLOpener.h"
#import "Utils.h"
#import "InstagramHeaders.h"
#import "Networking/RYGInstagramAPI.h"
#import <objc/runtime.h>

// Live IGUserMap that mints IG's canonical, Pando-subscribed users. Captured once
// from IG's user deserialization; re-armed to nil if a mint ever fails.
static id gRYGUserMap;

// Left-edge swipe to dismiss; only at the nav root so sub-profiles keep IG's back.
static char kRYGSwipeKey;

@interface RYGProfileSwipe : NSObject <UIGestureRecognizerDelegate>
@property (nonatomic, weak) UINavigationController *host;
@property (nonatomic, weak) UIScreenEdgePanGestureRecognizer *edge;
@end

@implementation RYGProfileSwipe

- (void)attachTo:(UINavigationController *)host {
	self.host = host;
	objc_setAssociatedObject(host, &kRYGSwipeKey, self, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
	UIScreenEdgePanGestureRecognizer *edge = [[UIScreenEdgePanGestureRecognizer alloc] initWithTarget:self action:@selector(handleEdge:)];
	edge.edges = UIRectEdgeLeft;
	edge.delegate = self;
	self.edge = edge;
	[host.view addGestureRecognizer:edge];
}

- (BOOL)gestureRecognizerShouldBegin:(UIGestureRecognizer *)g {
	return self.host.viewControllers.count <= 1;
}

// Make IG's horizontal tab pager defer to the edge pan, so an edge swipe dismisses.
- (BOOL)gestureRecognizer:(UIGestureRecognizer *)g shouldBeRequiredToFailByGestureRecognizer:(UIGestureRecognizer *)other {
	return g == self.edge && [other isKindOfClass:[UIPanGestureRecognizer class]];
}

- (void)handleEdge:(UIScreenEdgePanGestureRecognizer *)g {
	if (g.state != UIGestureRecognizerStateEnded) return;
	CGFloat width = MAX(g.view.bounds.size.width, 1);
	CGFloat progress = [g translationInView:g.view].x / width;
	if (progress > 0.33 || [g velocityInView:g.view].x > 600)
		[self.host dismissViewControllerAnimated:YES completion:nil];
}

@end

%hook IGUser
+ (id)valueWithJSONDictionary:(id)json objectMaps:(id)maps error:(id *)error {
	if (!gRYGUserMap && maps && [maps respondsToSelector:@selector(userMap)])
		gRYGUserMap = ((id (*)(id, SEL))objc_msgSend)(maps, @selector(userMap));
	return %orig;
}
%end

@implementation RYGProfileOpener

+ (id)canonicalUserForPK:(NSString *)pk username:(NSString *)username {
	if (!gRYGUserMap || !pk.length) return nil;
	if (![gRYGUserMap respondsToSelector:@selector(userWithDict:)]) return nil;
	NSDictionary *dict = username.length ? @{ @"pk": pk, @"username": username } : @{ @"pk": pk };
	@try {
		id user = ((id (*)(id, SEL, id))objc_msgSend)(gRYGUserMap, @selector(userWithDict:), dict);
		if (!user) gRYGUserMap = nil;
		return user;
	} @catch (__unused id e) { gRYGUserMap = nil; return nil; }
}

+ (void)hydrateCanonicalUser:(id)user pk:(NSString *)pk {
	if (!user || !pk.length) return;
	[RYGInstagramAPI sendRequestWithMethod:@"GET"
									  path:[NSString stringWithFormat:@"users/%@/info/", pk]
									  body:nil
								completion:^(NSDictionary *response, NSError *error) {
		id raw = [response isKindOfClass:[NSDictionary class]] ? response[@"user"] : nil;
		id map = gRYGUserMap;
		if (![raw isKindOfClass:[NSDictionary class]] || !map ||
			![map respondsToSelector:@selector(userWithDict:)]) return;
		NSMutableDictionary *dict = [raw mutableCopy];
		dict[@"pk"] = pk;
		@try { ((id (*)(id, SEL, id))objc_msgSend)(map, @selector(userWithDict:), dict); }
		@catch (__unused id e) {}
	}];
}

+ (UIViewController *)nativeProfileVCForUser:(id)user session:(id)session {
	Class refCls = NSClassFromString(@"IGUserReference");
	Class cfgCls = NSClassFromString(@"IGProfileConfig");
	Class vcCls = NSClassFromString(@"IGProfileViewController");
	if (!refCls || !cfgCls || !vcCls || !user || !session) return nil;
	@try {
		id ref = [[refCls alloc] init];
		Ivar uv = class_getInstanceVariable(refCls, "_user");
		if (uv) object_setIvar(ref, uv, user);
		Ivar sv = class_getInstanceVariable(refCls, "_subtype");
		if (sv) *(unsigned long long *)((char *)(__bridge void *)ref + ivar_getOffset(sv)) = 2;

		id cfg = [[cfgCls alloc] initWithUserReference:ref userSession:session];
		if (!cfg) return nil;
		UIViewController *vc = [[vcCls alloc] initWithConfiguration:cfg accountSwitcherPresenter:nil isMainProfileSurface:NO];
		return vc;
	} @catch (__unused id e) { return nil; }
}

+ (UIViewController *)topMostFrom:(UIViewController *)presenter {
	// A non-VC presenter (e.g. a UIView) would crash on -presentedViewController.
	UIViewController *top = [presenter isKindOfClass:UIViewController.class] ? presenter : nil;
	if (!top) {
		for (UIScene *s in [UIApplication sharedApplication].connectedScenes) {
			if (![s isKindOfClass:[UIWindowScene class]]) continue;
			for (UIWindow *w in ((UIWindowScene *)s).windows) if (w.isKeyWindow) { top = w.rootViewController; break; }
			if (top) break;
		}
	}
	while (top.presentedViewController) top = top.presentedViewController;
	return top;
}

// The native profile needs a PK, so username-only callers look one up first.
+ (BOOL)resolvePKThenOpenForUsername:(NSString *)username from:(UIViewController *)presenter {
	__weak UIViewController *weakPresenter = presenter;
	[RYGInstagramAPI searchUsersWithQuery:username completion:^(NSArray<NSDictionary *> *users, __unused NSError *error) {
		NSString *pk = nil;
		for (NSDictionary *u in users) {
			if ([u[@"username"] isKindOfClass:[NSString class]] &&
				[u[@"username"] caseInsensitiveCompare:username] == NSOrderedSame) { pk = u[@"pk"]; break; }
		}
		if (pk.length && [self openProfileForPK:pk username:username from:weakPresenter]) return;
		[RYGURLOpener dismiss:weakPresenter thenOpenInstagramProfileForUsername:username];
	}];
	return YES;
}

+ (BOOL)openProfileForPK:(NSString *)pk username:(NSString *)username from:(UIViewController *)presenter {
	if (!pk.length && username.length) return [self resolvePKThenOpenForUsername:username from:presenter];

	id session = [RYGUtils activeUserSession];
	id user = [self canonicalUserForPK:pk username:username];
	UIViewController *vc = [self nativeProfileVCForUser:user session:session];
	if (!vc) {
		if (username.length) return [RYGURLOpener dismiss:presenter thenOpenInstagramProfileForUsername:username];
		return NO;
	}

	Class igNavCls = NSClassFromString(@"IGNavigationController");
	UINavigationController *host = igNavCls ? [[igNavCls alloc] initWithRootViewController:vc]
										   : [[UINavigationController alloc] initWithRootViewController:vc];
	host.modalPresentationStyle = UIModalPresentationFullScreen;
	[[RYGProfileSwipe new] attachTo:host];
	if (!vc.navigationItem.leftBarButtonItem && !vc.navigationItem.leftBarButtonItems.count)
		vc.navigationItem.leftBarButtonItem =
			[[UIBarButtonItem alloc] initWithImage:[UIImage systemImageNamed:@"chevron.backward"]
											 style:UIBarButtonItemStylePlain
											target:self
											action:@selector(closeProfile:)];

	UIViewController *top = [self topMostFrom:presenter];
	if (!top) return NO;
	[top presentViewController:host animated:YES completion:nil];
	[self hydrateCanonicalUser:user pk:pk];
	return YES;
}

+ (void)closeProfile:(UIBarButtonItem *)sender {
	[[self topMostFrom:nil] dismissViewControllerAnimated:YES completion:nil];
}

@end
