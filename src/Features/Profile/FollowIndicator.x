// Follow indicator — shows whether the profile user follows you.
// Fetches once per profile PK, renders directly inside the stats container.

#import "../../InstagramHeaders.h"
#import "../../Utils.h"
#import "../../RYGChrome.h"
#import "../../Networking/RYGInstagramAPI.h"
#import <objc/runtime.h>

static const NSInteger kFollowBadgeTag = 99788;
static const NSInteger kFollowBgTag = 99789;
static const NSInteger kFollowLabelTag = 99790;

static const char kFollowProfilePKKey;
static const char kFollowFetchPKKey;
static const char kFollowContainerKey;

static NSCache *rygFollowCache(void) {
	static NSCache *c;
	static dispatch_once_t once;
	dispatch_once(&once, ^{
		c = [NSCache new];
		c.countLimit = 100;
	});
	return c;
}

static inline NSString *rygFollowMode(void) {
	NSString *mode = [RYGUtils getStringPref:@"follow_indicator"];
	return mode.length ? mode : @"off";
}

static inline BOOL rygFollowEnabled(void) {
	return ![rygFollowMode() isEqualToString:@"off"];
}

static inline BOOL rygFollowColored(void) {
	return [rygFollowMode() isEqualToString:@"colored"];
}

static inline NSString *rygFollowProfilePK(id vc) {
	return objc_getAssociatedObject(vc, &kFollowProfilePKKey);
}

static inline void rygSetFollowProfilePK(id vc, NSString *pk) {
	objc_setAssociatedObject(vc, &kFollowProfilePKKey, pk, OBJC_ASSOCIATION_COPY_NONATOMIC);
}

static inline NSString *rygFollowFetchPK(id vc) {
	return objc_getAssociatedObject(vc, &kFollowFetchPKKey);
}

static inline void rygSetFollowFetchPK(id vc, NSString *pk) {
	objc_setAssociatedObject(vc, &kFollowFetchPKKey, pk, OBJC_ASSOCIATION_COPY_NONATOMIC);
}

static inline UIView *rygFollowContainer(id vc) {
	return objc_getAssociatedObject(vc, &kFollowContainerKey);
}

static inline void rygSetFollowContainer(id vc, UIView *view) {
	objc_setAssociatedObject(vc, &kFollowContainerKey, view, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
}

static NSString *rygProfilePK(UIViewController *vc) {
	@try {
		return [RYGUtils pkFromIGUser:[vc valueForKey:@"user"]];
	} @catch (__unused id e) {
		return nil;
	}
}

static void rygRemoveFollowBadge(UIView *root) {
	[[root viewWithTag:kFollowBadgeTag] removeFromSuperview];
}

static void rygRenderFollowBadge(UIViewController *vc, UIView *container) {
	if (!vc || !container) return;

	NSString *pk = rygFollowProfilePK(vc);
	NSNumber *status = pk.length ? [rygFollowCache() objectForKey:pk] : nil;

	if (!rygFollowEnabled() || !status) {
		rygRemoveFollowBadge(container);
		return;
	}

	BOOL followedBy = status.boolValue;
	BOOL colored = rygFollowColored();

	NSString *text = followedBy
		? RYGLocalized(@"Follows you")
		: RYGLocalized(@"Doesn't follow you");

	RYGChromeCanvas *badge = (RYGChromeCanvas *)[container viewWithTag:kFollowBadgeTag];

	if (![badge isKindOfClass:RYGChromeCanvas.class]) {
		[badge removeFromSuperview];

		badge = [RYGChromeCanvas new];
		badge.tag = kFollowBadgeTag;
		badge.translatesAutoresizingMaskIntoConstraints = NO;
		badge.userInteractionEnabled = NO;

		UIView *host = badge.contentContainer;

		UIView *bg = [UIView new];
		bg.tag = kFollowBgTag;
		bg.translatesAutoresizingMaskIntoConstraints = NO;
		bg.userInteractionEnabled = NO;
		bg.clipsToBounds = YES;
		bg.layer.cornerRadius = 10.0;

		UILabel *label = [UILabel new];
		label.tag = kFollowLabelTag;
		label.translatesAutoresizingMaskIntoConstraints = NO;
		label.textAlignment = NSTextAlignmentCenter;
		label.font = [UIFont systemFontOfSize:11.0 weight:UIFontWeightSemibold];
		label.adjustsFontSizeToFitWidth = YES;
		label.minimumScaleFactor = 0.78;
		label.lineBreakMode = NSLineBreakByClipping;

		[host addSubview:bg];
		[host addSubview:label];

		[container addSubview:badge];

		[NSLayoutConstraint activateConstraints:@[
			[badge.leadingAnchor constraintEqualToAnchor:container.leadingAnchor],
			[badge.bottomAnchor constraintEqualToAnchor:container.bottomAnchor constant:-2.0],
			[badge.heightAnchor constraintEqualToConstant:21.0],
			[badge.widthAnchor constraintGreaterThanOrEqualToConstant:112.0],
			[badge.widthAnchor constraintLessThanOrEqualToConstant:138.0],

			[bg.leadingAnchor constraintEqualToAnchor:host.leadingAnchor],
			[bg.trailingAnchor constraintEqualToAnchor:host.trailingAnchor],
			[bg.topAnchor constraintEqualToAnchor:host.topAnchor],
			[bg.bottomAnchor constraintEqualToAnchor:host.bottomAnchor],

			[label.leadingAnchor constraintEqualToAnchor:host.leadingAnchor constant:7.0],
			[label.trailingAnchor constraintEqualToAnchor:host.trailingAnchor constant:-7.0],
			[label.topAnchor constraintEqualToAnchor:host.topAnchor],
			[label.bottomAnchor constraintEqualToAnchor:host.bottomAnchor]
		]];
	}

	UIColor *color = followedBy
		? [UIColor colorWithRed:0.22 green:0.68 blue:0.36 alpha:1.0]
		: [UIColor colorWithRed:0.86 green:0.28 blue:0.28 alpha:1.0];

	UILabel *label = (UILabel *)[badge viewWithTag:kFollowLabelTag];
	UIView *bg = [badge viewWithTag:kFollowBgTag];

	label.text = text;
	label.textColor = colored ? color : UIColor.secondaryLabelColor;

	bg.backgroundColor = colored ? [color colorWithAlphaComponent:0.13] : UIColor.clearColor;
	bg.layer.borderWidth = colored ? 1.0 : 0.0;
	bg.layer.borderColor = colored ? [color colorWithAlphaComponent:0.50].CGColor : nil;
}

static void rygResetFollowState(UIViewController *vc) {
	rygRemoveFollowBadge(vc.view);
	rygSetFollowProfilePK(vc, nil);
	rygSetFollowFetchPK(vc, nil);
}

static void rygRenderFollowBadgeNow(UIViewController *vc) {
	UIView *container = rygFollowContainer(vc);
	if (container.window) rygRenderFollowBadge(vc, container);
}

static void rygFetchFollowStatus(UIViewController *vc, NSString *pk) {
	rygSetFollowFetchPK(vc, pk);

	__weak UIViewController *weakVC = vc;
	NSString *requestedPK = pk.copy;
	NSString *path = [NSString stringWithFormat:@"friendships/show/%@/", requestedPK];

	[RYGInstagramAPI sendRequestWithMethod:@"GET" path:path body:nil completion:^(NSDictionary *response, NSError *error) {
		dispatch_async(dispatch_get_main_queue(), ^{
			UIViewController *strongVC = weakVC;
			if (!strongVC) return;

			if (![rygFollowFetchPK(strongVC) isEqualToString:requestedPK]) return;
			rygSetFollowFetchPK(strongVC, nil);

			if (error || ![response isKindOfClass:NSDictionary.class]) return;
			if (![rygFollowProfilePK(strongVC) isEqualToString:requestedPK]) return;

			[rygFollowCache() setObject:@([response[@"followed_by"] boolValue]) forKey:requestedPK];
			rygRenderFollowBadgeNow(strongVC);
		});
	}];
}

static void rygRefreshFollowIndicator(UIViewController *vc) {
	if (!rygFollowEnabled()) {
		rygResetFollowState(vc);
		return;
	}

	NSString *pk = rygProfilePK(vc);
	NSString *myPK = [RYGUtils currentUserPK];

	if (!pk.length || !myPK.length || [pk isEqualToString:myPK]) {
		rygResetFollowState(vc);
		return;
	}

	if (![rygFollowProfilePK(vc) isEqualToString:pk]) {
		rygRemoveFollowBadge(vc.view);
		rygSetFollowProfilePK(vc, pk);
	}

	if ([rygFollowCache() objectForKey:pk]) {
		rygRenderFollowBadgeNow(vc);
		return;
	}

	if (![rygFollowFetchPK(vc) isEqualToString:pk]) {
		rygFetchFollowStatus(vc, pk);
	}
}

%hook IGProfileViewController

- (void)setUser:(id)user {
	%orig;

	dispatch_async(dispatch_get_main_queue(), ^{
		rygRefreshFollowIndicator(self);
	});
}

- (void)viewDidAppear:(BOOL)animated {
	%orig;
	rygRefreshFollowIndicator(self);
}

%end

%hook _TtC23IGProfileHeaderIdentity38IGProfileHeaderStatButtonContainerView

- (void)layoutSubviews {
	%orig;

	UIView *view = (UIView *)self;
	UIViewController *vc = [RYGUtils nearestViewControllerForView:view];

	if ([vc isKindOfClass:%c(IGProfileViewController)]) {
		rygSetFollowContainer(vc, view);
		rygRenderFollowBadge(vc, view);
	}
}

%end